import Foundation

/// 외부 CLI 실행 공용 헬퍼. whisper-cli/ffmpeg/sherpa-onnx가 공유한다.
/// stderr는 라인 단위 스트리밍, stdout은 개행 없는 실시간 burst를 위해 chunk 단위로 읽는다.
enum ProcessRunner {
    struct Output: Sendable {
        let stdout: String
        let stderr: String
    }

    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String],
        onStderrLine: @escaping @Sendable (String) -> Void = { _ in },
        onStdoutText: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> Output {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // 종료 상태만 전달. AsyncStream은 순회 전에 yield돼도 버퍼링하므로
        // run() 전에 핸들러를 걸고 뒤에서 await해도 안전하다.
        let terminationStatuses = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            throw WhisperCppError.processLaunchFailed(executableURL.path, error.localizedDescription)
        }

        // stderr는 라인 단위 드레인(마커/진행률 라인은 개행 종료).
        let stderrTask = Task<String, Never> {
            var captured = ""
            do {
                for try await line in errorPipe.fileHandleForReading.bytes.lines {
                    onStderrLine(line)
                    captured += line + "\n"
                }
            } catch {}
            return captured
        }

        // stdout은 세그먼트 텍스트가 개행 없이 실시간 burst로 도착할 수 있으므로
        // chunk 단위로 읽는다. readabilityHandler가 burst당 1회 호출돼
        // MainActor 홉이 자연스럽게 코얼레싱되고, 순차 await가 청크 순서를 보장한다.
        let stdoutHandle = outputPipe.fileHandleForReading
        let stdoutChunks = AsyncStream<Data> { continuation in
            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        let stdoutTask = Task<String, Never> {
            var captured = ""
            var pending = Data()
            for await chunk in stdoutChunks {
                pending.append(chunk)
                let text = Self.consumeCompleteUTF8(&pending)
                guard !text.isEmpty else { continue }
                captured += text
                if let onStdoutText {
                    await onStdoutText(text)
                }
            }
            if !pending.isEmpty {
                captured += String(decoding: pending, as: UTF8.self)
            }
            return captured
        }

        // Task 취소 시 프로세스를 종료시켜, 호출측 defer(임시 디렉토리 삭제 등)보다
        // 사이드카가 먼저 죽는 것을 보장한다.
        var status: Int32 = -1
        await withTaskCancellationHandler {
            for await value in terminationStatuses {
                status = value
            }
        } onCancel: {
            process.terminate()
        }

        let errorOutput = await stderrTask.value
        let output = await stdoutTask.value

        guard status == 0 else {
            throw WhisperCppError.processFailed(
                executableURL.lastPathComponent,
                output + errorOutput
            )
        }

        return Output(stdout: output, stderr: errorOutput)
    }

    /// pending에서 완결된 UTF-8 프리픽스만 디코드해 반환하고,
    /// 잘린 멀티바이트 꼬리(최대 3바이트)는 pending에 남긴다.
    static func consumeCompleteUTF8(_ pending: inout Data) -> String {
        guard !pending.isEmpty else {
            return ""
        }

        var holdback = 0
        let tail = [UInt8](pending.suffix(4))
        for (offset, byte) in tail.enumerated().reversed() {
            if byte & 0b1100_0000 == 0b1000_0000 {
                continue
            }
            let expected: Int
            switch byte {
            case 0x00..<0x80: expected = 1
            case 0xC0..<0xE0: expected = 2
            case 0xE0..<0xF0: expected = 3
            case 0xF0..<0xF8: expected = 4
            default:          expected = 1
            }
            let available = tail.count - offset
            if available < expected {
                holdback = available
            }
            break
        }

        let complete = pending.prefix(pending.count - holdback)
        let text = String(decoding: complete, as: UTF8.self)
        pending = Data(pending.suffix(holdback))
        return text
    }
}
