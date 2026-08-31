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
    // (id, fileURL) rather than a network model — this queue plays both freshly
    // received messages and history replays triggered from the UI, neither of which
    // should require constructing a fake VoiceMessage.
    private var queue: [(id: String, fileURL: URL)] = []
    private var isPlaying = false
    @Published private(set) var currentlyPlayingID: String?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // A phone call, Siri, an alarm, etc. pauses our player(s) without ever calling
    // audioPlayerDidFinishPlaying — so without this, `keepAlivePlayer` can stay paused
    // (silently killing background execution) and, if a message was mid-playback,
    // `isPlaying`/the duck window can stay stuck until the app is relaunched.
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            break // system already paused playback; nothing to react to yet

        case .ended:
            let shouldResume: Bool
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            } else {
                shouldResume = false
            }

            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("AudioSessionManager: failed to reactivate session after interruption: \(error)")
            }

            // Must always come back, regardless of `shouldResume` — a paused keep-alive
            // means iOS can suspend the process the moment it's backgrounded.
            keepAlivePlayer?.play()

            guard isPlaying else { return }
            if shouldResume {
                messagePlayer?.play()
            } else {
                // System says don't resume (e.g. Siri) — drop this message instead of
                // leaving the queue frozen and the .duckOthers window stuck open.
                messagePlayer?.stop()
                finishPlayback()
            }

        @unknown default:
            break
        }
    }

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

    // Ignores a message already playing or already waiting in the queue — without this,
    // repeatedly tapping the same history row queued up that many back-to-back replays
    // instead of just playing it once.
    func enqueue(id: String, fileURL: URL) {
        guard currentlyPlayingID != id, !queue.contains(where: { $0.id == id }) else { return }
        queue.append((id, fileURL))
        playNextIfIdle()
    }

    /// Stops whatever is currently playing and drops anything still queued behind it.
    /// The only stop/pause control the app exposes — see `WalkieViewModel.replay`.
    func stop() {
        queue.removeAll()
        guard isPlaying else { return }
        messagePlayer?.stop()
        finishPlayback()
    }

    private func playNextIfIdle() {
        guard !isPlaying, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        isPlaying = true
        currentlyPlayingID = next.id

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            let player = try AVAudioPlayer(contentsOf: next.fileURL)
            player.delegate = self
            messagePlayer = player
            player.play()
        } catch {
            print("AudioSessionManager: failed to play message \(next.id): \(error)")
            finishPlayback()
        }
    }

    private func finishPlayback() {
        // Duck window closed — always revert, whether playback succeeded or not.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        messagePlayer = nil
        isPlaying = false
        currentlyPlayingID = nil
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
