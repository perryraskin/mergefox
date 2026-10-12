import AuthenticationServices
import CryptoKit
import Security
import UIKit

@MainActor final class OAuthSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirectURI = "mergepocket://oauth/callback"
    private var session: ASWebAuthenticationSession?
    static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.message("Couldn’t start secure sign-in.") }
        return base64URL(Data(bytes))
    }
    static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func callbackCode(_ url: URL, state: String) throws -> String {
        guard url.scheme == "mergepocket", url.host == "oauth", url.path == "/callback",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              q.filter({ $0.name == "state" }).count == 1,
              q.first(where: { $0.name == "state" })?.value == state else { throw AppError.message("Sign-in couldn’t be verified. Please try again.") }
        guard q.first(where: { $0.name == "error" }) == nil,
              q.filter({ $0.name == "code" }).count == 1,
              let code = q.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw AppError.message("GitLab sign-in was canceled or denied.") }
        return code
    }
    func signIn(host: URL, clientID: String, api: GitLabAPI) async throws -> Credential {
        #if SHARE_EXTENSION
        throw AppError.message("Sign in from the Mergefox app first, then share this link again.")
        #else
        guard !clientID.isEmpty else { throw AppError.message("OAuth hasn’t been configured for this GitLab host yet. Use a token or add the application ID in advanced settings.") }
        guard session == nil else { throw AppError.message("Sign-in is already in progress.") }
        let state = try Self.randomString(), verifier = try Self.randomString()
        var c = URLComponents(url: host.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = ["client_id": clientID, "redirect_uri": Self.redirectURI, "response_type": "code", "scope": "api", "state": state, "code_challenge": Self.challenge(verifier), "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "mergepocket") { url, error in
                Task { @MainActor in
                    self.session = nil
                    if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: AppError.message("Sign-in canceled. You can try again whenever you’re ready.")) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() { self.session = nil; continuation.resume(throwing: AppError.message("Couldn’t open GitLab sign-in.")) }
        }
        let code = try Self.callbackCode(callback, state: state)
        return try await api.exchange(host: host, fields: ["grant_type": "authorization_code", "client_id": clientID, "code": code, "redirect_uri": Self.redirectURI, "code_verifier": verifier]).credential(host: host, clientID: clientID)
        #endif
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if SHARE_EXTENSION
        return ASPresentationAnchor()
        #else
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #endif
    }
}
