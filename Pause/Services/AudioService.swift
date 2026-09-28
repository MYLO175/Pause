import AVFoundation

@MainActor final class AudioService {
    private var ambient: AVAudioPlayer?
    private var ending: AVAudioPlayer?
    private var preview: AVAudioPlayer?
    private var previewName: String?
    private(set) var scheduledEnding = false
    private func player(_ name: String) throws -> AVAudioPlayer {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            throw BackupError.invalid("The sound ‘\(name)’ could not be loaded.")
        }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        return try AVAudioPlayer(contentsOf: url)
    }
    func start(_ preferences: Preferences, remaining: Double) throws {
        stop()
        if preferences.ambient != "none" {
            let loop = try player(preferences.ambient); loop.numberOfLoops = -1
            loop.volume = preferences.ambientVolume; loop.prepareToPlay(); loop.play(); ambient = loop
        } else if preferences.needsSilentSessionAudio {
            // Keep a real background playback stream alive while Silence is selected.
            // The player is digitally muted; the selected ending below uses this same session.
            let keeper = try player("ambient"); keeper.numberOfLoops = -1
            keeper.volume = 0; keeper.prepareToPlay(); keeper.play(); ambient = keeper
        }
        if remaining > 0, preferences.ending != "none", preferences.endingVolume > 0 {
            let bell = try player(preferences.ending); bell.volume = preferences.endingVolume
            bell.prepareToPlay()
            if bell.play(atTime: bell.deviceCurrentTime + remaining) {
                ending = bell
                scheduledEnding = true
            }
        }
    }
    func playEnding(_ preferences: Preferences) throws {
        guard preferences.ending != "none", preferences.endingVolume > 0 else { return }
        try previewSound(preferences.ending, volume: preferences.endingVolume)
    }
    func previewSound(_ name: String, volume: Float, looping: Bool = false) throws {
        preview?.stop(); preview = nil; previewName = nil
        guard name != "none" else { return }
        let sound = try player(name)
        sound.numberOfLoops = looping ? -1 : 0
        sound.volume = volume; sound.play(); preview = sound; previewName = name
    }
    func previewSoundIfNeeded(_ name: String, volume: Float, looping: Bool = false) throws {
        guard name != "none" else { return }
        if previewName == name, preview?.isPlaying == true { return }
        try previewSound(name, volume: volume, looping: looping)
    }
    func setPreviewVolume(_ name: String, volume: Float) {
        guard previewName == name, let preview, preview.isPlaying else { return }
        preview.volume = volume
    }
    func stop() {
        ambient?.stop(); ambient = nil; ending?.stop(); ending = nil; preview?.stop(); preview = nil; previewName = nil
        scheduledEnding = false
    }
}
