import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var account: Credential?
    @Published var user: Person?
    @Published var inbox: [MergeRequest] = []
    @Published var loadingInbox = false
    @Published var inboxPage = 1
    @Published var inboxHasNext = false
    @Published var mergedPage = 1
    private var mergedAuthored = MRFeedBuffer()
    private var mergedReviewed = MRFeedBuffer()
    @Published var recentlyMerged: [MergeRequest] = []
    @Published var loadingMerged = false
    @Published var mergedError: String?
    @Published var releaseProjects: [ReleaseProject] = []
    @Published var releaseProjectID: Int?
    @Published var releaseBranches: [ReleaseBranch] = []
    @Published var releaseBranchName: String?
    @Published var releaseSummary: ReleaseSummary?
    @Published var loadingRelease = false
    @Published var releaseError: String?
    var releaseGeneration = UUID()
    @Published var location: MRLocation?
    @Published var mr: MergeRequest?
    @Published var diffs: [FileDiff] = []
    @Published var discussions: [Discussion] = []
    @Published var approval: ApprovalState?
    @Published var error: String?
    @Published var loading = false
    @Published var authenticating = false
    @Published var mutating = false
    @Published var demo = false
    @Published var approvalWarning: String?
    @Published var discussionWarning: String?
    @Published var openText = ""
    @Published var showSignIn = false
    @Published var errorInSheet = false
    @Published var inboxFilter = "reviews"
    @Published var inboxFilters = MRInboxFilters()
    @Published var defaultInboxTab = UserDefaults.standard.string(forKey: "defaultInboxTab") ?? "reviews" {
        didSet { UserDefaults.standard.set(defaultInboxTab, forKey: "defaultInboxTab") }
    }
    let api: GitLabAPI
    let oauth = OAuthSignIn()
    private var loadGeneration = UUID()
    private var mergedGeneration = UUID()
    private var inboxGeneration = UUID()
    var canWrite: Bool { account != nil && !demo && account?.host == location?.host }
    var approvedByMe: Bool { approval?.approvedBy.contains(where: { $0.user.id == user?.id }) == true }
    var recentURLs: [String] { UserDefaults.standard.stringArray(forKey: "recentMRs") ?? [] }
    init() {
        let saved = CredentialVault.load(); account = saved; api = GitLabAPI(credential: saved)
        inboxFilter = ["reviews", "authored"].contains(defaultInboxTab) ? defaultInboxTab : "reviews"
    }
    func restoreSharedAccount() async {
        let saved = CredentialVault.load()
        guard saved?.accessToken != account?.accessToken || saved?.host != account?.host else { return }
        // A share-sheet review may have rotated the OAuth refresh token.
        loadGeneration = UUID()
        await api.setCredential(saved)
        account = saved
        mergedGeneration = UUID(); recentlyMerged = []; mergedError = nil; loadingMerged = false
        mergedAuthored = MRFeedBuffer(); mergedReviewed = MRFeedBuffer(); mergedPage = 1
        inboxPage = 1; inboxHasNext = false
        resetReleaseDashboard()
        if saved == nil { user = nil; inbox = [] }
    }
    func signIn(host: String, clientID: String) async {
        guard !authenticating else { return }; authenticating = true; defer { authenticating = false }
        do {
            let hostURL = try URL.gitlabHost(host)
            let value = try await oauth.signIn(host: hostURL, clientID: clientID, api: api)
            try await finishSignIn(value)
        } catch { self.error = error.localizedDescription }
    }
    func tokenSignIn(host: String, token: String) async {
        guard !authenticating else { return }; authenticating = true; defer { authenticating = false }
        do {
            let value = Credential(host: try URL.gitlabHost(host), accessToken: token.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !value.accessToken.isEmpty else { throw AppError.message("Enter a personal access token with the api scope.") }
            try await finishSignIn(value)
        } catch { self.error = error.localizedDescription }
    }
    private func finishSignIn(_ value: Credential) async throws {
        // Validate before replacing the saved account.
        let candidate = GitLabAPI(credential: value)
        let signedInUser = try await candidate.request(Person.self, host: value.host, path: "user")
        try CredentialVault.save(value)
        loadGeneration = UUID()
        await api.setCredential(value)
        account = value; user = signedInUser; demo = false; showSignIn = false
        mergedGeneration = UUID(); recentlyMerged = []; mergedError = nil; loadingMerged = false
        mergedAuthored = MRFeedBuffer(); mergedReviewed = MRFeedBuffer(); mergedPage = 1
        inboxPage = 1; inboxHasNext = false
        resetReleaseDashboard()
        inbox = []; mr = nil; diffs = []; discussions = []; approval = nil
        if let loc = location, loc.host == value.host { await load(loc) }
        else { location = nil; await loadHome() }
    }
    func signOut() async {
        loadGeneration = UUID(); CredentialVault.clear(); await api.setCredential(nil)
        account = nil; user = nil; inbox = []; location = nil; mr = nil; diffs = []; discussions = []; approval = nil; demo = false
        mergedGeneration = UUID(); recentlyMerged = []; mergedError = nil; loadingMerged = false
        mergedAuthored = MRFeedBuffer(); mergedReviewed = MRFeedBuffer(); mergedPage = 1
        inboxPage = 1; inboxHasNext = false
        resetReleaseDashboard()
    }
    func loadHome() async {
        async let opened: Void = loadInbox()
        async let merged: Void = loadRecentlyMerged()
        async let release: Void = loadReleaseDashboard()
        _ = await (opened, merged, release)
    }
    func loadRecentlyMerged(page: Int = 1, reset: Bool = true) async {
        guard let account, !demo else { return }
        mergedGeneration = UUID(); let generation = mergedGeneration
        loadingMerged = true; mergedError = nil
        defer { if generation == mergedGeneration { loadingMerged = false } }
        do {
            let person: Person
            if let user { person = user }
            else { person = try await api.request(Person.self, host: account.host, path: "user") }
            let authoredBuffer = reset ? MRFeedBuffer() : mergedAuthored
            let reviewedBuffer = reset ? MRFeedBuffer() : mergedReviewed
            // Each stream must contain enough rows to determine the combined page,
            // plus one extra row so Next never leads to an empty page.
            let needed = max(1, page) * HomePagination.pageSize + 1
            async let authored = authoredBuffer.filling(upTo: needed, api: api, host: account.host,
                query: RecentlyMergedFeed.query(tab: "authored", userID: person.id))
            async let reviewed = reviewedBuffer.filling(upTo: needed, api: api, host: account.host,
                query: RecentlyMergedFeed.query(tab: "reviews", userID: person.id))
            let values = try await (authored, reviewed)
            guard generation == mergedGeneration, self.account?.host == account.host, !Task.isCancelled else { return }
            mergedAuthored = values.0; mergedReviewed = values.1
            recentlyMerged = RecentlyMergedFeed.combine(values.0.items, values.1.items)
            mergedPage = max(1, page)
        } catch {
            if generation == mergedGeneration, !Task.isCancelled { mergedError = error.localizedDescription }
        }
    }
    func loadInbox(page: Int = 1) async {
        guard let account, !demo else { return }
        inboxGeneration = UUID(); let inboxRequest = inboxGeneration
        loadingInbox = true; defer { if inboxRequest == inboxGeneration { loadingInbox = false } }
        let generation = loadGeneration
        let filters = inboxFilters, tab = inboxFilter
        do {
            let person = try await api.request(Person.self, host: account.host, path: "user")
            let query = filters.query(tab: tab, userID: person.id)
            let result = try await api.page(MergeRequest.self, host: account.host, path: "merge_requests", query: query, page: max(1, page))
            guard generation == loadGeneration, inboxRequest == inboxGeneration, !Task.isCancelled else { return }
            user = person; inbox = result.items; inboxPage = max(1, page); inboxHasNext = result.hasNext
            self.account = await api.currentCredential()
        } catch { if generation == loadGeneration, inboxRequest == inboxGeneration, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func open(_ input: String) async {
        do { let loc = try MRLocation.parse(input); await load(loc) }
        catch { self.error = error.localizedDescription }
    }
    func handle(_ url: URL) async {
        // OAuth callbacks belong exclusively to ASWebAuthenticationSession.
        if ["mergefox", "mergepocket"].contains(url.scheme ?? ""), url.host == "oauth" { return }
        if ["mergefox", "mergepocket"].contains(url.scheme ?? ""), url.host == "open", let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value {
            await open(value)
        } else { await open(url.absoluteString) }
    }
    func load(_ loc: MRLocation) async {
        loadGeneration = UUID(); let generation = loadGeneration
        loading = true; location = loc; mr = nil; diffs = []; discussions = []; approval = nil; approvalWarning = nil; discussionWarning = nil; demo = false
        defer { if generation == loadGeneration { loading = false } }
        do {
            let base = GitLabAPI.path(loc)
            let detail = try await api.request(MergeRequest.self, host: loc.host, path: base, anonymous: account == nil)
            guard generation == loadGeneration else { return }
            mr = detail
            var recent = recentURLs.filter { $0 != loc.url.absoluteString }; recent.insert(loc.url.absoluteString, at: 0)
            UserDefaults.standard.set(Array(recent.prefix(15)), forKey: "recentMRs")
            // Request independently so a unavailable approval endpoint doesn't hide the MR.
            async let files = api.paginated(FileDiff.self, host: loc.host, path: base + "/diffs", anonymous: account == nil)
            async let threads = api.paginated(Discussion.self, host: loc.host, path: base + "/discussions", anonymous: account == nil)
            do {
                let f = try await files
                guard generation == loadGeneration else { return }
                diffs = f
            } catch { if generation == loadGeneration { self.error = "The MR loaded, but its diff couldn’t load. " + error.localizedDescription } }
            do {
                let d = try await threads
                guard generation == loadGeneration else { return }
                discussions = d
            } catch { if generation == loadGeneration { discussionWarning = account == nil ? "Sign in to view discussions on this merge request." : error.localizedDescription } }
            if account != nil {
                do {
                    let approvals = try await api.request(ApprovalState.self, host: loc.host, path: base + "/approvals")
                    guard generation == loadGeneration else { return }; approval = approvals
                } catch { if generation == loadGeneration { approvalWarning = error.localizedDescription } }
            }
            if generation == loadGeneration { self.account = await api.currentCredential() }
        } catch { if generation == loadGeneration { self.error = error.localizedDescription } }
    }
    func approve() async {
        guard canWrite, !mutating, let loc = location, let detail = mr, detail.state == "opened" else { return }
        guard let sha = detail.sha, !sha.isEmpty else { error = "The commit is still being prepared. Refresh before approving."; return }
        let removing = approvedByMe
        await mutate(loc) {
            let _: EmptyResponse = try await self.api.request(EmptyResponse.self, host: loc.host, path: GitLabAPI.path(loc) + (removing ? "/unapprove" : "/approve"), method: "POST", body: removing ? [:] : ["sha": sha])
        }
    }
    func comment(_ body: String, discussionID: String? = nil) async -> Bool {
        guard canWrite, !mutating, let loc = location, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return await mutate(loc) {
            let path = GitLabAPI.path(loc) + (discussionID.map { "/discussions/\($0)/notes" } ?? "/discussions")
            let _: EmptyResponse = try await self.api.request(EmptyResponse.self, host: loc.host, path: path, method: "POST", body: ["body": body])
        }
    }
    func resolve(_ discussion: Discussion) async {
        guard canWrite, !mutating, let loc = location else { return }
        await mutate(loc) {
            let _: EmptyResponse = try await self.api.request(EmptyResponse.self, host: loc.host, path: GitLabAPI.path(loc) + "/discussions/\(discussion.id)", method: "PUT", body: ["resolved": !discussion.isResolved])
        }
    }
    func edit(title: String, description: String, target: String, labels: String) async -> Bool {
        guard canWrite, !mutating, let loc = location else { return false }
        return await mutate(loc) {
            let _: EmptyResponse = try await self.api.request(EmptyResponse.self, host: loc.host, path: GitLabAPI.path(loc), method: "PUT", body: ["title": title, "description": description, "target_branch": target, "labels": labels])
        }
    }
    @discardableResult private func mutate(_ loc: MRLocation, action: () async throws -> Void) async -> Bool {
        mutating = true; defer { mutating = false }
        do { try await action(); if location == loc { await load(loc) }; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func loadDemo() {
        loadGeneration = UUID(); loading = false; demo = true
        let p = Person(id: 1, name: "Alex Chen", username: "alex")
        let reviewer = Person(id: 2, name: "Sam Rivera", username: "sam")
        location = try! MRLocation.parse("https://gitlab.com/demo/mobile/-/merge_requests/42")
        mr = MergeRequest(id: 42, iid: 42, projectId: 1, title: "Make sign-in feel effortless", description: "## What changed\nUse the existing GitLab browser session and securely refresh credentials.\n\n- Keep credentials in Keychain\n- Add a personal access token option\n- Handle expired sessions gracefully\n\n```swift\nawait session.refreshIfNeeded()\n```\n\n<h2><a href=\"https://example.com/review?prompt=very-long-encoded-link\">Review summary</a></h2>\n\n<strong>Credentials stay protected.</strong>\n\n<details><summary>Fix with agent</summary>\n\n```text\nCheck token refresh and expired sessions.\n```\n\n</details>\n\n| Check | Result |\n| --- | --- |\n| Refresh | Passed |\n\n```mermaid\nflowchart TD\n    A[Sign in with GitLab] --> B[Save session in Keychain]\n    B --> C{Token expiring?}\n    C -- Yes --> D[Refresh session]\n    C -- No --> E[Open merge request]\n    D --> E\n```", state: "opened", author: p, reviewers: [reviewer], labels: ["iOS", "enhancement", "ready for review"], sourceBranch: "feature/oauth", targetBranch: "main", sha: "sample", webUrl: location!.url.absoluteString, headPipeline: Pipeline(status: "success"), changesCount: "2")
        diffs = [FileDiff(oldPath: "Auth/Session.swift", newPath: "Auth/Session.swift", diff: "@@ -12,5 +12,7 @@\n func signIn() async throws {\n-    let token = try await askForToken()\n-    defaults.set(token, forKey: \"token\")\n+    let session = try await oauth.authorize()\n+    try keychain.save(session)\n+    await refreshIfNeeded()\n     showInbox()\n }"), FileDiff(oldPath: "Sources/Mergefox/Features/Authentication/Views/SignInView.swift", newPath: "Sources/Mergefox/Features/Authentication/Views/SignInView.swift", diff: "@@ -1,3 +1,4 @@\n VStack {\n+    Button(\"Continue with GitLab\", action: signIn)\n     TokenField()\n }")]
        discussions = [Discussion(id: "demo-thread", notes: [Note(id: 1, author: reviewer, body: "Can we refresh the token before it expires?", resolvable: true, resolved: false, position: DiffPosition(newPath: "Auth/Session.swift", newLine: 16)), Note(id: 2, author: p, body: "Yes — refresh starts 90 seconds before expiry, and the rotated token is saved in Keychain.")]), Discussion(id: "demo-note", individualNote: true, notes: [Note(id: 3, author: p, body: "Ready for a first review, @sam. Fixed in 5ba7978b. Thanks!")])]
        approval = ApprovalState(approvedBy: [], approvalsRequired: 1, approvalsLeft: 1); approvalWarning = nil; discussionWarning = nil
    }
}
