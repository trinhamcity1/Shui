import AudioToolbox
import Foundation

/// Short UI sounds, played through System Sound Services rather than
/// `AVAudioPlayer`: system sounds go quiet on the silent switch by
/// themselves, and they never touch the shared `AVAudioSession` —
/// `FeedPlayerPool` sets that to `.playback` for video, a category that
/// would otherwise make these play even with the switch on silent.
///
/// Each case plays whichever file in `Shui/Resources/Sounds/` shares its
/// name, so a sound can be swapped by dropping in a new file — see that
/// folder's README.
@MainActor
enum SoundEffect: String {
    case generate

    /// System Sound Services only plays these; mp3/m4a would fail silently.
    private static let supportedExtensions = ["caf", "wav", "aiff", "aif"]
    private static var loaded: [SoundEffect: SystemSoundID] = [:]

    func play() {
        guard let soundID = Self.soundID(for: self) else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    private static func soundID(for effect: SoundEffect) -> SystemSoundID? {
        if let cached = loaded[effect] { return cached }
        let url = supportedExtensions.lazy
            .compactMap { Bundle.main.url(forResource: effect.rawValue, withExtension: $0) }
            .first
        guard let url else { return nil }
        var soundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else { return nil }
        loaded[effect] = soundID
        return soundID
    }
}
