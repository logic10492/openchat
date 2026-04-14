import Foundation

final class MockURLProtocol: URLProtocol {
    typealias RequestHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let sessionHeader = "X-OpenChat-Mock-Session"
    nonisolated(unsafe) private static var requestHandlers: [String: RequestHandler] = [:]
    private static let lock = NSLock()

    static func makeSession(handler: @escaping RequestHandler) -> URLSession {
        let identifier = UUID().uuidString
        withLock {
            requestHandlers[identifier] = handler
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        configuration.httpAdditionalHeaders = [sessionHeader: identifier]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let identifier = request.value(forHTTPHeaderField: Self.sessionHeader)
        guard let identifier,
              let handler = Self.withLock({ Self.requestHandlers[identifier] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
