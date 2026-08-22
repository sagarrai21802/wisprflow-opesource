import Foundation

struct GroqService {
    static let shared = GroqService()
    
    private let baseURLString = "https://api.groq.com/openai/v1"
    private let transcriptionModel = "whisper-large-v3"
    
    enum ServiceError: Error, CustomStringError {
        case missingApiKey
        case fileNotFound(String)
        case requestFailed(String)
        case invalidResponse
        
        var description: String {
            switch self {
            case .missingApiKey: return "Groq API key is missing."
            case .fileNotFound(let path): return "Audio file not found at path: \(path)"
            case .requestFailed(let msg): return "Groq API request failed: \(msg)"
            case .invalidResponse: return "Received invalid response from Groq Whisper API."
            }
        }
    }
    
    /// Transcribes an audio file using FreeFlow's EXACT TranscriptionService implementation line-for-line
    func transcribeAudio(fileURL: URL) async throws -> String {
        let apiKey = Config.shared.groqApiKey
        guard !apiKey.isEmpty else {
            throw ServiceError.missingApiKey
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ServiceError.fileNotFound(fileURL.path)
        }
        
        let url = URL(string: baseURLString)!
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
            
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let audioData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        
        // Exact FreeFlow makeMultipartBody implementation
        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        // 1. model (FreeFlow default: whisper-large-v3)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(transcriptionModel)\r\n")

        // 2. response_format (FreeFlow default: verbose_json for whisper-large-v3)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("verbose_json\r\n")

        // 3. file field matching FreeFlow exact mime type
        let mimeType = fileName.lowercased().hasSuffix(".wav") ? "audio/wav" : "audio/mp4"
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        
        // Upload via FreeFlow's LLMAPITransport.upload
        let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.requestFailed("No response received from Groq API")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            print("[GroqService] Error response HTTP \(httpResponse.statusCode): \(errorText)")
            throw ServiceError.requestFailed("HTTP \(httpResponse.statusCode): \(errorText)")
        }
        
        let transcript = try TranscriptionResponseParser.parse(data)
        print("[GroqService] Transcript parsed successfully: \"\(transcript)\"")
        return transcript
    }
}
