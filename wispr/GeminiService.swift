import Foundation

struct GeminiService {
    static let shared = GeminiService()
    
    private let modelName = "gemini-2.5-flash"
    
    enum ServiceError: Error, CustomStringError {
        case missingApiKey
        case requestFailed(String)
        case invalidResponse
        
        var description: String {
            switch self {
            case .missingApiKey: return "Gemini API key is missing."
            case .requestFailed(let msg): return "Gemini API request failed: \(msg)"
            case .invalidResponse: return "Received invalid response format from Gemini API."
            }
        }
    }
    
    /// Context-aware AI processing method that analyzes voice instruction + application context
    func processWithContext(rawTranscript: String, context: AppContextSnapshot) async throws -> String {
        let apiKey = Config.shared.geminiApiKey.isEmpty ? Config.shared.geminiApiKeySecond : Config.shared.geminiApiKey
        guard !apiKey.isEmpty else {
            throw ServiceError.missingApiKey
        }
        
        let trimmedRawText = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRawText.isEmpty else {
            return ""
        }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw ServiceError.requestFailed("Invalid URL construct")
        }
        
        let systemPrompt = """
        You are an intelligent, context-aware Voice Assistant and AI dictation processor.
        You receive:
        1. User's spoken voice command/transcript.
        2. Context about the active application (App Name, Window Title, and any Selected/On-Screen Text).

        INSTRUCTIONS:
        - Analyze the user's spoken voice transcript in relation to the active app and window context.
        - If the user asks to write/reply/generate an email, document, response, code, or message based on the context (e.g. "write a mail for the reply of this mail..."), generate the complete, high-quality, professional text output requested.
        - If the user is dictating standard text, refine the grammar and remove speech hesitations ("um", "uh") while preserving the user's intent.
        - Output ONLY the final generated content ready to be pasted directly into the user's application caret.
        - Do NOT include any meta-commentary, introductory remarks (e.g., "Here is your email:"), preambles, or markdown quote blocks. Return strictly the final text to be pasted.
        """
        
        var userPromptContent = "APPLICATION CONTEXT:\n"
        userPromptContent += context.summary
        userPromptContent += "\n\nSPOKEN VOICE COMMAND / TRANSCRIPT:\n\(trimmedRawText)"
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemPrompt)\n\n\(userPromptContent)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2048
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            print("[Gemini] API error response: \(errorText)")
            throw ServiceError.requestFailed("HTTP Status Code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        
        let jsonResult = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let candidate = jsonResult.candidates?.first,
              let parts = candidate.content?.parts,
              let firstTextPart = parts.first?.text else {
            throw ServiceError.invalidResponse
        }
        
        let outputText = firstTextPart.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[Gemini] Context-Aware Generated Output:\n\(outputText)")
        return outputText
    }
    
    /// Legacy fallback method for raw text processing
    func processAndRefineText(_ rawText: String) async throws -> String {
        let dummyContext = AppContextSnapshot(appName: nil, bundleIdentifier: nil, windowTitle: nil, selectedText: nil)
        return try await processWithContext(rawTranscript: rawText, context: dummyContext)
    }
}
