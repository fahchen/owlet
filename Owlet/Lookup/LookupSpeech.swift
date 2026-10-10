import AVFoundation

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
        let synthesizer = AVSpeechSynthesizer()
        return LookupSpeech(
            canSpeak: { voice(for: $0) != nil },
            speak: { text, language in
                synthesizer.stopSpeaking(at: .immediate)
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice(for: language)
                synthesizer.speak(utterance)
            },
            stop: { synthesizer.stopSpeaking(at: .immediate) })
    }()

    /// The system's own choice for the language when it has one, else any installed voice for it.
    private static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let key = LanguageTag.key(language)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { LanguageTag.key($0.language) == key }
        guard !voices.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(language: language).flatMap { preferred in
            voices.contains { $0.identifier == preferred.identifier } ? preferred : nil
        } ?? voices.first
    }
}
