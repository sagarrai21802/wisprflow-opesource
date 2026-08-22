import Foundation

struct Config {
    static let shared = Config()
    
    let geminiApiKey: String
    let geminiApiKeySecond: String
    let assemblyAiApiKey: String
    let groqApiKey: String
    
    private init() {
        let envVars = Config.loadDotEnv()
        
        self.geminiApiKey = envVars["GEMINI_API_KEY"] ?? ""
        self.geminiApiKeySecond = envVars["GEMINI_API_KEY_SECOND"] ?? ""
        self.assemblyAiApiKey = envVars["ASSEMBLYAI_API_KEY"] ?? ""
        self.groqApiKey = envVars["GROQ_API_KEY"] ?? ""
    }
    
    private static func loadDotEnv() -> [String: String] {
        var results: [String: String] = [:]
        
        // Search locations: workspace root, bundle resource, working directory
        let possiblePaths = [
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundlePath + "/.env",
            Bundle.main.resourcePath.flatMap { $0 + "/.env" } ?? "",
            NSHomeDirectory() + "/Desktop/new/wispr/.env"
        ]
        
        for path in possiblePaths {
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { continue }
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count == 2 {
                        results[parts[0]] = parts[1]
                    }
                }
                print("[Config] Successfully loaded .env from \(path)")
                break
            } catch {
                print("[Config] Failed to read .env at \(path): \(error)")
            }
        }
        
        return results
    }
    
    func printSummary() {
        print("--- Wispr Configuration ---")
        print("Gemini Primary Key Loaded: \(geminiApiKey.isEmpty ? "❌ NO" : "✅ YES (\(geminiApiKey.prefix(6))...)")")
        print("Gemini Secondary Key Loaded: \(geminiApiKeySecond.isEmpty ? "❌ NO" : "✅ YES (\(geminiApiKeySecond.prefix(6))...)")")
        print("AssemblyAI Key Loaded: \(assemblyAiApiKey.isEmpty ? "❌ NO" : "✅ YES (\(assemblyAiApiKey.prefix(6))...)")")
        print("---------------------------")
    }
}
