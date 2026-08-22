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
    
    /// Cleans up, formats, and refines transcribed text using Gemini.
    func processAndRefineText(_ rawText: String) async throws -> String {
        let apiKey = Config.shared.geminiApiKey.isEmpty ? Config.shared.geminiApiKeySecond : Config.shared.geminiApiKey
        guard !apiKey.isEmpty else {
            throw ServiceError.missingApiKey
        }
        
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw ServiceError.requestFailed("Invalid URL construct")
        }
        
        let systemPrompt = """
        You are an intelligent voice dictation post-processor.
        Your task is to fix grammar, remove speech hesitations (like "um", "uh", "er"), format numbers/punctuation properly, and return ONLY the final refined text.
        Do NOT add any preamble, explanation, quotes, or conversational filler. Return strictly the polished text.
        """
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemPrompt)\n\nInput Speech Text:\n\(rawText)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
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
        
        // Parse Gemini JSON response
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
        print("[Gemini] Refined Output: \(outputText)")
        return outputText
    }
}
