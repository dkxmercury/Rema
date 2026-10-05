import Foundation

enum Backend {
    static let base = URL(string: "https://api.remaapp.cc")!

    enum Failure: Error, Equatable {
        case offline
        case unauthorized
        case invalid(String?)
        case conflict(String?)
        case rateLimited
        case server
    }

    private struct Problem: Decodable {
        struct Field: Decodable {
            let code: String?
        }

        let code: String?
        let data: [String: Field]?
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func request<Response: Decodable>(_ method: String, _ path: String, token: String? = nil, as type: Response.Type) async throws -> Response {
        try decode(type, from: try await raw(method, path, token: token))
    }

    static func request<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body, token: String? = nil, as type: Response.Type) async throws -> Response {
        try decode(type, from: try await raw(method, path, body: try JSONEncoder().encode(body), token: token))
    }

    static func send(_ method: String, _ path: String, token: String? = nil) async throws {
        _ = try await raw(method, path, token: token)
    }

    static func send<Body: Encodable>(_ method: String, _ path: String, body: Body, token: String? = nil) async throws {
        _ = try await raw(method, path, body: try JSONEncoder().encode(body), token: token)
    }

    private static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw Failure.server
        }
    }

    static func raw(_ method: String, _ path: String, body: Data? = nil, contentType: String = "application/json", token: String? = nil) async throws -> Data {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return data }
        let problem = try? JSONDecoder().decode(Problem.self, from: data)
        switch status {
        case 401:
            throw Failure.unauthorized
        case 409:
            throw Failure.conflict(problem?.code)
        case 429:
            throw Failure.rateLimited
        case 400..<500:
            throw Failure.invalid(problem?.data?.values.compactMap(\.code).first ?? problem?.code)
        default:
            throw Failure.server
        }
    }
}

extension Backend.Failure {
    var message: String {
        switch self {
        case .offline:
            String(localized: "No internet connection. Try again when you are online.")
        case .unauthorized, .invalid(nil):
            String(localized: "Wrong email or password.")
        case .rateLimited:
            String(localized: "Too many attempts. Try again in a minute.")
        case .conflict(let code) where code == "email_taken":
            String(localized: "This email already belongs to another way of signing in.")
        case .invalid(let code) where code == "validation_not_unique":
            String(localized: "This email is already registered. Sign in with your password.")
        case .invalid(let code) where code?.contains("email") == true:
            String(localized: "Enter the whole email, like name@example.com.")
        case .invalid(let code) where code?.contains("length") == true || code?.contains("min") == true:
            String(localized: "The password needs at least 8 characters.")
        case .invalid:
            String(localized: "Check the email and password and try again.")
        default:
            String(localized: "Something went wrong. Try again.")
        }
    }
}
