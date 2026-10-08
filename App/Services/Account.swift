import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit

@MainActor
@Observable
final class Account {
    static let shared = Account()

    enum Method: String, Codable {
        case password
        case apple
        case google
    }

    struct Session: Codable, Equatable {
        var token: String
        var userID: String
        var email: String
        var name: String
        var method: Method
        var issued: Date
    }

    private(set) var session: Session?
    // A session that ran out by itself, not by the person's choice; the home screen asks to sign in again.
    private(set) var expired = UserDefaults.standard.bool(forKey: Account.expiredKey)

    private static let expiredKey = "session.expired"

    private init() {
        session = Keychain.load()
    }

    var isSignedIn: Bool {
        session != nil
    }

    // Apple users who hid their address get a service address that only the server uses.
    var visibleEmail: String {
        guard let email = session?.email, !email.hasSuffix("@users.remaapp.cc") else { return "" }
        return email
    }

    private struct AuthResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
            let name: String?
        }

        let token: String
        let record: User
    }

    func signUp(email: String, password: String) async throws {
        struct Body: Encodable {
            let email: String
            let password: String
            let passwordConfirm: String
            let lang: String
        }
        try await Backend.send("POST", "/api/collections/users/records", body: Body(email: email, password: password, passwordConfirm: password, lang: AppLanguage.current.rawValue))
        try await signIn(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        struct Body: Encodable {
            let identity: String
            let password: String
        }
        let auth = try await Backend.request("POST", "/api/collections/users/auth-with-password", body: Body(identity: email, password: password), as: AuthResponse.self)
        begin(auth, method: .password)
    }

    func signInWithApple() async throws {
        let nonce = Nonce()
        let credential = try await AppleAuthorization().perform(hashedNonce: nonce.hashed)
        guard let tokenData = credential.identityToken, let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw Backend.Failure.server
        }
        struct Body: Encodable {
            let identityToken: String
            let code: String?
            let nonce: String
            let name: String
            let lang: String
        }
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
        let body = Body(identityToken: identityToken, code: code, nonce: nonce.raw, name: name, lang: AppLanguage.current.rawValue)
        let auth = try await Backend.request("POST", "/api/rema/auth/apple", body: body, as: AuthResponse.self)
        begin(auth, method: .apple)
    }

    func signInWithGoogle() async throws {
        let nonce = Nonce()
        let idToken = try await GoogleAuthorization().perform(nonce: nonce.hashed)
        struct Body: Encodable {
            let idToken: String
            let nonce: String
            let lang: String
        }
        let auth = try await Backend.request("POST", "/api/rema/auth/google", body: Body(idToken: idToken, nonce: nonce.raw, lang: AppLanguage.current.rawValue), as: AuthResponse.self)
        begin(auth, method: .google)
    }

    func requestReset(email: String) async throws {
        struct Body: Encodable {
            let email: String
        }
        try await Backend.send("POST", "/api/collections/users/request-password-reset", body: Body(email: email))
    }

    func refreshIfNeeded() async {
        guard let session, Date().timeIntervalSince(session.issued) > 7 * 86_400 else { return }
        do {
            let auth = try await Backend.request("POST", "/api/collections/users/auth-refresh", token: session.token, as: AuthResponse.self)
            // The phone may have signed out or into another account while the request was out.
            guard self.session?.token == session.token else { return }
            begin(auth, method: session.method)
        } catch Backend.Failure.unauthorized {
            expire(token: session.token)
        } catch {}
    }

    func updateLanguage() async {
        guard let session else { return }
        struct Body: Encodable {
            let lang: String
        }
        try? await Backend.send("PATCH", "/api/collections/users/records/\(session.userID)", body: Body(lang: AppLanguage.current.rawValue), token: session.token)
    }

    enum DeletionCheck {
        case email(String)
        case none
    }

    func requestDeletionCode() async throws -> DeletionCheck {
        guard let session else { throw Backend.Failure.unauthorized }
        struct Reply: Decodable {
            let method: String
            let email: String?
        }
        let reply = try await Backend.request("POST", "/api/rema/account/delete-code", token: session.token, as: Reply.self)
        return reply.method == "none" ? .none : .email(reply.email ?? session.email)
    }

    func deleteAccount(code: String) async throws {
        guard let session else { throw Backend.Failure.unauthorized }
        struct Body: Encodable {
            let code: String
        }
        try await Backend.send("POST", "/api/rema/account/delete", body: Body(code: code), token: session.token)
        end()
    }

    func signOut() {
        if let token = session?.token {
            // Sign-out doesn't wait for the network, offline the token just runs out in a month.
            Task { try? await Backend.send("POST", "/api/rema/auth/signout", token: token) }
        }
        end()
    }

    // The token ran out while the phone was away; the data stays until someone signs in again.
    func expire(token: String) {
        guard session?.token == token else { return }
        session = nil
        Keychain.delete()
        expired = true
        UserDefaults.standard.set(true, forKey: Self.expiredKey)
    }

    func dismissExpired() {
        guard expired else { return }
        expired = false
        UserDefaults.standard.set(false, forKey: Self.expiredKey)
    }

    private func begin(_ auth: AuthResponse, method: Method) {
        let session = Session(token: auth.token, userID: auth.record.id, email: auth.record.email ?? "", name: auth.record.name ?? "", method: method, issued: Date())
        self.session = session
        Keychain.save(session)
        dismissExpired()
    }

    private func end() {
        session = nil
        Keychain.delete()
    }
}

struct Nonce {
    let raw: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        raw = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum Keychain {
    private static let service = "uz.dkx.rema.account"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"]
    }

    static func load() -> Account.Session? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.Session.self, from: data)
    }

    static func save(_ session: Account.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        var item = query
        item[kSecValueData as String] = data
        // Background refresh runs while the phone is locked, after the first unlock.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AppleAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    func perform(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: CancellationError())
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            let code = (error as? ASAuthorizationError)?.code
            continuation?.resume(throwing: code == .canceled ? CancellationError() : error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.activeWindow ?? ASPresentationAnchor() }
    }
}

@MainActor
final class GoogleAuthorization: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Problem: Error {
        case notConfigured
        case failed
    }

    private var session: ASWebAuthenticationSession?

    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "RemaGoogleClientID") as? String ?? "").trimmingCharacters(in: .whitespaces)
    }

    static var configured: Bool {
        clientID.hasSuffix(".apps.googleusercontent.com")
    }

    func perform(nonce: String) async throws -> String {
        let clientID = Self.clientID
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { throw Problem.notConfigured }
        let scheme = "com.googleusercontent.apps." + clientID.dropLast(suffix.count)
        let redirect = scheme + ":/oauth2redirect"
        let verifier = Nonce().raw + Nonce().raw
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let state = Nonce().raw
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? Problem.failed)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: Problem.failed)
            }
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state, let code = items.first(where: { $0.name == "code" })?.value else {
            throw Problem.failed
        }
        var exchange = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        exchange.httpMethod = "POST"
        exchange.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        exchange.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        struct Tokens: Decodable {
            let id_token: String?
        }
        let data: Data
        do {
            (data, _) = try await Backend.session.data(for: exchange)
        } catch {
            throw Backend.Failure.offline
        }
        guard let token = try? JSONDecoder().decode(Tokens.self, from: data).id_token else { throw Problem.failed }
        return token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.activeWindow ?? ASPresentationAnchor() }
    }
}

extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }

    var mainWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.windowLevel == .normal }
    }
}
