import Foundation

enum TranscriptionResponseParsingError: Error, Equatable {
    case invalidResponse
}

enum TranscriptionResponseParser {
    // Whisper emits these stock phrases for silence or background noise.
    // FreeFlow filters them out so quiet audio doesn't paste "Thank you."
    private static let hallucinationPhrases: Set<String> = [
        "thank you",
        "thank you.",
        "thank you for watching",
        "thank you very much",
        "thank you so much",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara.org community",
        "you"
    ]

    static func parse(_ data: Data) throws -> String {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TranscriptionResponseParsingError.invalidResponse
        }

        if let json = object as? [String: Any],
           let text = json["text"] as? String {
            if isHallucination(text: text, json: json) {
                print("[TranscriptionParser] Suppressed silence/noise hallucination: '\(text)'")
                return ""
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let plainText = String(data: data, encoding: .utf8) ?? ""
        let text = plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionResponseParsingError.invalidResponse
        }

        return text
    }

    private static func isHallucination(text: String, json: [String: Any]) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        
        guard hallucinationPhrases.contains(normalized) else {
            return false
        }

        if let segments = json["segments"] as? [[String: Any]],
           let noSpeechProb = segments.first?["no_speech_prob"] as? Double {
            return noSpeechProb >= 0.1
        }
        
        // Default to filtering if phrase is in hallucination list
        return true
    }
}
