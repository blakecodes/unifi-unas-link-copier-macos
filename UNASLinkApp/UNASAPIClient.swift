import Foundation

struct FileShare: Decodable {
    let id: String
    let token: String
    let path: String
    let type: String
}

private struct ShareCollection: Decodable {
    let data: [FileShare]
}

private struct CreatedShareEnvelope: Decodable {
    let data: FileShare
}

private struct CreateShareBody: Encodable {
    let type: String
    let path: String
}

enum UNASAPIError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case sessionExpired
    case invalidResponse
    case server(Int, String)
    case shareNotReturned

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The UNAS server URL is invalid."
        case .notAuthenticated: return "Sign in to UNAS before creating links."
        case .sessionExpired: return "Your UNAS session expired. Sign in again."
        case .invalidResponse: return "UNAS returned an invalid response."
        case .server(let status, let body): return "UNAS returned HTTP \(status): \(body)"
        case .shareNotReturned: return "The share was created but could not be found afterward."
        }
    }
}

final class UNASAPIClient: NSObject, URLSessionDelegate {
    private let configuration: UNASConfiguration
    private let trustedHost: String?

    init(configuration: UNASConfiguration) {
        self.configuration = configuration
        self.trustedHost = configuration.normalizedServerURL?.host
    }

    func copyableLink(for drivePath: String) async throws -> URL {
        if let existing = try await listShares().first(where: { $0.type == "public" && $0.path == drivePath }) {
            return try publicURL(token: existing.token)
        }

        if let created = try await createShare(path: drivePath) {
            return try publicURL(token: created.token)
        }

        guard let fetched = try await listShares().first(where: { $0.type == "public" && $0.path == drivePath }) else {
            throw UNASAPIError.shareNotReturned
        }
        return try publicURL(token: fetched.token)
    }

    func listShares() async throws -> [FileShare] {
        let request = try authenticatedRequest(path: "/proxy/drive/api/v1/file-sharing/links")
        let data = try await perform(request)
        return try JSONDecoder().decode(ShareCollection.self, from: data).data
    }

    private func createShare(path: String) async throws -> FileShare? {
        var request = try authenticatedRequest(path: "/proxy/drive/api/v1/file-sharing/links")
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.normalizedServerURL?.absoluteString, forHTTPHeaderField: "Origin")
        request.httpBody = try JSONEncoder().encode(CreateShareBody(type: "public", path: path))

        let data = try await perform(request)
        if data.isEmpty { return nil }
        if let direct = try? JSONDecoder().decode(FileShare.self, from: data) { return direct }
        if let envelope = try? JSONDecoder().decode(CreatedShareEnvelope.self, from: data) { return envelope.data }
        if let envelope = try? JSONDecoder().decode(ShareCollection.self, from: data) { return envelope.data.first }
        return nil
    }

    private func authenticatedRequest(path: String) throws -> URLRequest {
        guard let base = configuration.normalizedServerURL,
              let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw UNASAPIError.notConfigured
        }
        guard let token = try KeychainStore.loadSessionToken() else {
            throw UNASAPIError.notAuthenticated
        }
        let claims = try JWTClaims.decode(from: token)
        guard !claims.isExpired else { throw UNASAPIError.sessionExpired }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("TOKEN=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue(claims.csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue("local", forHTTPHeaderField: "x-connection-type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UNASAPIError.invalidResponse }
        adoptRefreshedSession(from: http, requestURL: request.url)
        if http.statusCode == 401 {
            KeychainStore.deleteSessionToken()
            throw UNASAPIError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UNASAPIError.server(http.statusCode, body)
        }
        return data
    }

    private func adoptRefreshedSession(from response: HTTPURLResponse, requestURL: URL?) {
        guard let requestURL else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key] = String(describing: pair.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: requestURL)
        guard let refreshed = cookies.first(where: { $0.name == "TOKEN" }),
              let claims = try? JWTClaims.decode(from: refreshed.value),
              !claims.isExpired else { return }
        try? KeychainStore.saveSessionToken(refreshed.value)
    }

    private func publicURL(token: String) throws -> URL {
        guard let url = URL(string: "https://drop.ui.com/\(token)") else {
            throw UNASAPIError.invalidResponse
        }
        return url
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard configuration.allowSelfSignedCertificate,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == trustedHost,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
