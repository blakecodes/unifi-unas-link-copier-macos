import Foundation

struct JWTClaims: Decodable {
    let csrfToken: String
    let exp: TimeInterval

    static func decode(from token: String) throws -> JWTClaims {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { throw JWTError.malformed }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64) else { throw JWTError.malformed }
        return try JSONDecoder().decode(JWTClaims.self, from: data)
    }

    var expirationDate: Date { Date(timeIntervalSince1970: exp) }
    var isExpired: Bool { expirationDate <= Date() }
}

enum JWTError: LocalizedError {
    case malformed

    var errorDescription: String? { "The UNAS session cookie is malformed." }
}
