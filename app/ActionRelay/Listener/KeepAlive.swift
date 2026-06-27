import AVFoundation

/// Keeps the app alive in the background by holding a silent AVAudioSession —
/// the standard sideload technique now that we have no Network Extension
/// (docs/integration.md). ponytail: silent-audio keepalive. Ceiling: another app
/// seizing the audio session can suspend us; we `.mixWithOthers` and re-activate
/// on interruption end. Upgrade path if this proves flaky: add a background
/// CLLocationManager as a second anchor (sturdier, but shows the location arrow).
final class KeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var active = false

    func start() {
        guard !active else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: session)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0 // inaudible
        do { try engine.start() } catch { return }
        scheduleSilence(format: format)
        player.play()
        active = true
    }

    private func scheduleSilence(format: AVAudioFormat) {
        let frames = AVAudioFrameCount(format.sampleRate) // 1 s, looped
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames // zero-filled == silence
        player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
        player.play()
    }

    func stop() {
        guard active else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        active = false
    }
}
