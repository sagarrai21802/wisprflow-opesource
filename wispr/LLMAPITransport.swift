import Foundation

enum LLMAPITransport {
    private static func makeEphemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    private static func timeout(for request: URLRequest) -> TimeInterval {
        let requestTimeout = request.timeoutInterval
        guard requestTimeout.isFinite, requestTimeout > 0 else {
            return 25
        }
        return requestTimeout
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        let session = makeEphemeralSession(timeout: timeout(for: request))
        defer { session.finishTasksAndInvalidate() }
        return try await session.upload(for: request, from: bodyData)
    }
}
