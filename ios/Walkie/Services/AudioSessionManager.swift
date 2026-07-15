import AVFoundation

/// Two `AVAudioPlayer`s, two jobs:
///
/// - `keepAlivePlayer` loops `keepalive.caf` forever at near-zero volume under session
///   options `[.mixWithOthers]`. Its ONLY purpose is to keep this process alive in the
///   background — continuous audio playback under category `.playback` is the
///   sanctioned way iOS grants a non-VoIP app indefinite background execution time
///   (requires `UIBackgroundModes: audio` in Info.plist). It must NEVER be paused or
///   stopped while the app is backgrounded, or the process will be suspended.
///
/// - `messagePlayer` is created per incoming voice message and played from a serial
///   FIFO queue — never overlaps. `.duckOthers` is switched on only for the exact
///   window of message playback and switched back off as soon as it finishes; leaving
///   it on permanently would duck other apps' audio (Music, Podcasts, ...) even when
///   Walkie isn't actually speaking.
///
/// Note: `.playback` ignores the hardware mute switch by design — messages play even
/// with the phone physically silenced. That's the intended walkie-talkie behavior.
final class AudioSessionManager: NSObject, ObservableObject {
    private var keepAlivePlayer: AVAudioPlayer?
    private var messagePlayer: AVAudioPlayer?
    private var queue: [(message: VoiceMessage, fileURL: URL)] = []
    private var isPlaying = false

    func startKeepAlive() {
        guard keepAlivePlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "keepalive", withExtension: "caf") else {
            assertionFailure("keepalive.caf missing from bundle — background playback will not work")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.play()
            keepAlivePlayer = player
        } catch {
            print("AudioSessionManager: failed to start keep-alive loop: \(error)")
        }
    }

    func enqueue(_ message: VoiceMessage, localFileURL: URL) {
        queue.append((message, localFileURL))
        playNextIfIdle()
    }

    private func playNextIfIdle() {
        guard !isPlaying, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        isPlaying = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            let player = try AVAudioPlayer(contentsOf: next.fileURL)
            player.delegate = self
            messagePlayer = player
            player.play()
        } catch {
            print("AudioSessionManager: failed to play message \(next.message.id): \(error)")
            finishPlayback()
        }
    }

    private func finishPlayback() {
        // Duck window closed — always revert, whether playback succeeded or not.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        messagePlayer = nil
        isPlaying = false
        playNextIfIdle()
    }
}

extension AudioSessionManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finishPlayback()
    }
}
