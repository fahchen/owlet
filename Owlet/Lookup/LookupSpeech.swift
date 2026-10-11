import AVFoundation
import Foundation

/// Manual system TTS for the looked-up text. Injectable so tests never make a sound and can stand
/// in for a Mac without the voice.
@MainActor
struct LookupSpeech {
    /// Whether a system voice for this language is installed now; nothing is downloaded on demand.
    var canSpeak: (String) -> Bool
    /// Speaks the text, interrupting whatever was playing.
    var speak: (String, String) -> Void
    var stop: () -> Void

    static let live: LookupSpeech = {
        // One synthesizer and one audible tracker for the whole launch: stopping a queue that is
        // already silent is what produced `AudioQueue underflow` and a zero-byte buffer on every card
        // close, even when nothing had been played.
        let speech = LiveSpeech()
        return LookupSpeech(
            canSpeak: { speech.canSpeak($0) },
            speak: { text, language in speech.speak(text, language: language) },
            stop: { speech.stop() })
    }()
}

/// The system voice for a language, resolved once per language: the lookup resolves voices while
/// speaking, and enumerating every installed voice on each call is wasted work on the audio path.
@MainActor
private final class VoiceCache {
    private var resolved: [String: AVSpeechSynthesisVoice?] = [:]

    func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let key = LanguageTag.key(language)
        if let cached = resolved[key] { return cached }
        let voice = Self.resolve(language)
        resolved[key] = voice
        return voice
    }

    /// The system's own choice for the language when it has one, else any installed voice for it.
    private static func resolve(_ language: String) -> AVSpeechSynthesisVoice? {
        let key = LanguageTag.key(language)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { LanguageTag.key($0.language) == key }
        guard !voices.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(language: language).flatMap { preferred in
            voices.contains { $0.identifier == preferred.identifier } ? preferred : nil
        } ?? voices.first
    }
}

/// Owns the app's one `AVSpeechSynthesizer`, and remembers whether anything was actually audible.
///
/// Asking a silent synthesizer to stop immediately is an immediate teardown of its audio queue: the
/// queue reports `AudioQueue underflow` and the framework logs a zero-byte buffer, every time a card
/// closes without having played anything. Stopping is only meaningful once an utterance has started,
/// which is what `audible` tracks through the synthesizer's own delegate callbacks.
@MainActor
private final class LiveSpeech: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voices = VoiceCache()
    /// Whether the synthesizer has produced audio that still needs stopping. Confined to the main
    /// actor with its owner, and written from the delegate's callbacks.
    private var audible = false
    /// The utterance most recently asked to speak, so an earlier one's delayed callback is ignored.
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func canSpeak(_ language: String) -> Bool { voices.voice(for: language) != nil }

    func speak(_ text: String, language: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voices.voice(for: language)
        current = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        guard audible || synthesizer.isSpeaking else { return }
        audible = false
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard utterance === current else { return }
        audible = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === current else { return }
        audible = false
        current = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === current else { return }
        audible = false
        current = nil
    }
}
