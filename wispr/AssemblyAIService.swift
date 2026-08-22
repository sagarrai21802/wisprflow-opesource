import Foundation

struct AssemblyAIService {
    static let shared = AssemblyAIService()
    
    private let uploadEndpoint = "https://api.assemblyai.com/v2/upload"
    private let transcriptEndpoint = "https://api.assemblyai.com/v2/transcript"
    
    enum ServiceError: Error, CustomStringError {
        case missingApiKey
        case fileNotFound(String)
        case uploadFailed(String)
        case transcriptionFailed(String)
        case timeout
        
        var description: String {
            switch self {
            case .missingApiKey: return "AssemblyAI API key is missing."
            case .fileNotFound(let path): return "Audio file not found at path: \(path)"
            case .uploadFailed(let msg): return "Upload to AssemblyAI failed: \(msg)"
            case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
            case .timeout: return "AssemblyAI transcription request timed out."
            }
        }
    }

    /// Transcribes an audio file at local URL and returns raw text.
    func transcribeAudio(fileURL: URL, onProgress: ((String) -> Void)? = nil) async throws -> String {
        let apiKey = Config.shared.assemblyAiApiKey
        guard !apiKey.isEmpty else {
            throw ServiceError.missingApiKey
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ServiceError.fileNotFound(fileURL.path)
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        onProgress?("Uploading audio (\(fileSize / 1024) KB)...")
        print("[AssemblyAI] Starting upload for \(fileURL.path) (\(fileSize) bytes)...")
        let audioData = try Data(contentsOf: fileURL)
        var uploadRequest = URLRequest(url: URL(string: uploadEndpoint)!)
        uploadRequest.httpMethod = "POST"
        uploadRequest.addValue(apiKey, forHTTPHeaderField: "authorization")
        uploadRequest.addValue("application/octet-stream", forHTTPHeaderField: "content-type")
        uploadRequest.httpBody = audioData
        
        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        guard let httpResponse = uploadResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: uploadData, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.uploadFailed(errorText)
        }
        
        struct UploadResult: Decodable {
            let upload_url: String
        }
        let uploadResult = try JSONDecoder().decode(UploadResult.self, from: uploadData)
        let audioUrl = uploadResult.upload_url
        print("[AssemblyAI] Audio uploaded successfully: \(audioUrl)")
        
        // Step 2: Request transcription
        var transcriptRequest = URLRequest(url: URL(string: transcriptEndpoint)!)
        transcriptRequest.httpMethod = "POST"
        transcriptRequest.addValue(apiKey, forHTTPHeaderField: "authorization")
        transcriptRequest.addValue("application/json", forHTTPHeaderField: "content-type")
        
        let payload: [String: Any] = ["audio_url": audioUrl]
        transcriptRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (initData, initResponse) = try await URLSession.shared.data(for: transcriptRequest)
        guard let initHttpResponse = initResponse as? HTTPURLResponse, (200...202).contains(initHttpResponse.statusCode) else {
            let errorText = String(data: initData, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.transcriptionFailed(errorText)
        }
        
        struct InitResult: Decodable {
            let id: String
            let status: String
        }
        let initResult = try JSONDecoder().decode(InitResult.self, from: initData)
        let transcriptId = initResult.id
        print("[AssemblyAI] Transcription queued with ID: \(transcriptId)")
        
        // Step 3: Poll status until completed or error
        let pollUrl = URL(string: "\(transcriptEndpoint)/\(transcriptId)")!
        struct PollResult: Decodable {
            let id: String
            let status: String
            let text: String?
            let error: String?
        }
        
        let maxAttempts = 60
        var attemptCount = 0
        for _ in 0..<maxAttempts {
            attemptCount += 1
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s poll - faster first check
            
            var pollRequest = URLRequest(url: pollUrl)
            pollRequest.addValue(apiKey, forHTTPHeaderField: "authorization")
            
            let (pollData, _) = try await URLSession.shared.data(for: pollRequest)
            let pollResult = try JSONDecoder().decode(PollResult.self, from: pollData)
            
            onProgress?("Processing: \(pollResult.status) (#\(attemptCount))...")
            print("[AssemblyAI] Poll #\(attemptCount): status=\(pollResult.status)")
            
            if pollResult.status == "completed" {
                let text = pollResult.text ?? ""
                print("[AssemblyAI] Transcription complete! Text: \(text)")
                return text
            } else if pollResult.status == "error" {
                throw ServiceError.transcriptionFailed(pollResult.error ?? "Unknown transcription error")
            }
        }
        
        throw ServiceError.timeout
    }
}

protocol CustomStringError {
    var description: String { get }
}
