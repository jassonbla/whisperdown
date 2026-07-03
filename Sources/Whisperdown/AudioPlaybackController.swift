import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentURL: URL?
    @Published var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if currentURL == url, let player {
            if player.isPlaying {
                pause()
            } else {
                playLoadedPlayer()
            }
            return
        }

        do {
            stop()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            currentURL = url
            duration = player.duration
            currentTime = player.currentTime
            errorMessage = nil
            playLoadedPlayer()
        } catch {
            errorMessage = "오디오를 재생하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func seek(by delta: TimeInterval) {
        guard let player else {
            return
        }

        let nextTime = min(max(player.currentTime + delta, 0), max(player.duration, 0))
        player.currentTime = nextTime
        currentTime = nextTime
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        currentURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        stopTimer()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedDuration = player.duration
        Task { @MainActor in
            currentTime = finishedDuration
            isPlaying = false
            stopTimer()
        }
    }

    private func playLoadedPlayer() {
        guard let player else {
            return
        }

        if player.currentTime >= player.duration {
            player.currentTime = 0
        }

        guard player.play() else {
            errorMessage = "오디오 재생을 시작하지 못했습니다."
            return
        }

        isPlaying = true
        duration = player.duration
        currentTime = player.currentTime
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else {
                    return
                }

                self.currentTime = player.currentTime
                self.duration = player.duration
                self.isPlaying = player.isPlaying
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
