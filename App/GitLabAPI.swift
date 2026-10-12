import Foundation

// Credentials never leave their configured origin. Redirects are rejected so an
// API redirect cannot forward an Authorization or PRIVATE-TOKEN header.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
actor GitLabAPI {
    private var credential: Credential?
    private var generation = UUID()
    private var refreshTask: Task<Credential, Error>?
    private let session: URLSession
    private let redirectDelegate = NoRedirectDelegate()
    init(credential: Credential? = nil) {
        self.credential = credential
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }
    func setCredential(_ value: Credential?) {
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil; credential = value
    }
    func currentCredential() -> Credential? { credential }
    func ensureFresh() async throws {
        guard let value = credential, let refresh = value.refreshToken,
              let expiry = value.expiresAt, expiry.timeIntervalSinceNow < 90 else { return }
        let currentGeneration = generation
        if let task = refreshTask {
            let new = try await task.value
            guard generation == currentGeneration else { throw CancellationError() }
            credential = new; return
        }
        let task = Task { try await self.exchange(host: value.host, fields: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": value.clientID ?? ""]) }
        let mapped = Task {
            let updated = try await task.value.credential(host: value.host, clientID: value.clientID ?? "")
            try Task.checkCancellation()
            guard self.generation == currentGeneration else { throw CancellationError() }
            try CredentialVault.save(updated)
            return updated
        }
        refreshTask = mapped
        do {
            let updated = try await mapped.value
            guard generation == currentGeneration else { throw CancellationError() }
            credential = updated; refreshTask = nil
        } catch {
            if generation == currentGeneration { refreshTask = nil }
            throw error
        }
    }
    func exchange(host: URL, fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: host.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents(); form.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return try JSONDecoder.gitlab.decode(TokenResponse.self, from: data)
    }
    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.message("GitLab returned an invalid response.") }
        guard (200..<300).contains(http.statusCode) else {
            let text: String
            switch http.statusCode {
            case 401: text = "Your session or token has expired. Sign in again."
            case 403: text = "GitLab denied this action. Check your permissions, token scope, or approval reauthentication settings."
            case 404: text = "This merge request wasn’t found, or your account doesn’t have access."
            case 408: text = "GitLab took too long to respond. Try again shortly."
            case 409: text = "The merge request changed since you loaded it. Refresh and review the latest diff before approving."
            case 422, 400: text = "GitLab couldn’t apply this change. Check the branch, labels, and project rules."
            case 429: text = "GitLab is rate limiting requests. Try again shortly."
            case 300..<400: text = "GitLab redirected this request. Enter the final HTTPS GitLab host in account settings."
            default: text = "GitLab request failed (HTTP \(http.statusCode)). Try again."
            }
            throw AppError.message(text)
        }
    }
    func request<T: Decodable>(_ type: T.Type, host: URL, path: String, query: [String: String] = [:], method: String = "GET", body: [String: Any]? = nil, anonymous: Bool = false) async throws -> T {
        let (value, _) = try await requestResult(type, host: host, path: path, query: query, method: method, body: body, anonymous: anonymous)
        return value
    }
    func page<T: Decodable>(_ type: T.Type, host: URL, path: String, query: [String: String], page: Int) async throws -> (items: [T], hasNext: Bool) {
        var query = query; query["per_page"] = "5"; query["page"] = String(page)
        let (items, response) = try await requestResult([T].self, host: host, path: path, query: query)
        let next = response.value(forHTTPHeaderField: "X-Next-Page")
        return (items, next.map { !$0.isEmpty } ?? (items.count == 5))
    }
    private func requestResult<T: Decodable>(_ type: T.Type, host: URL, path: String, query: [String: String] = [:], method: String = "GET", body: [String: Any]? = nil, anonymous: Bool = false) async throws -> (T, HTTPURLResponse) {
        let requestGeneration = generation
        if !anonymous { try await ensureFresh() }
        guard requestGeneration == generation else { throw CancellationError() }
        let account = anonymous ? nil : credential
        if let account, account.host != host { throw AppError.message("This MR is on a different GitLab host. Switch accounts before opening it.") }
        var components = URLComponents(url: host, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/api/v4/" + path
        components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw AppError.message("Invalid GitLab API URL.") }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let account {
            request.setValue(account.isOAuth ? "Bearer \(account.accessToken)" : account.accessToken,
                             forHTTPHeaderField: account.isOAuth ? "Authorization" : "PRIVATE-TOKEN")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard requestGeneration == generation else { throw CancellationError() }
        let http = response as! HTTPURLResponse // check() validated the response type.
        if T.self == EmptyResponse.self { return (EmptyResponse() as! T, http) }
        return (try JSONDecoder.gitlab.decode(type, from: data), http)
    }
    func paginated<T: Decodable>(_ type: T.Type, host: URL, path: String, query: [String: String] = [:], anonymous: Bool = false) async throws -> [T] {
        var output: [T] = []
        // Fully fetch within a practical v0 cap; callers show that cap explicitly.
        for page in 1...10 {
            var q = query; q["per_page"] = "100"; q["page"] = "\(page)"
            let values = try await request([T].self, host: host, path: path, query: q, anonymous: anonymous)
            output += values
            if values.count < 100 { break }
        }
        return output
    }
    static func encodedProject(_ project: String) -> String {
        project.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }
    static func path(_ location: MRLocation) -> String { "projects/\(encodedProject(location.project))/merge_requests/\(location.iid)" }
}
