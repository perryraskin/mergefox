import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var settings = false
    private var showingMR: Binding<Bool> {
        Binding(get: { model.location != nil }, set: { presented in
            if !presented && model.location != nil { model.closeMergeRequest() }
        })
    }
    private var accountButton: some View {
        Button { settings = true } label: { Image(systemName: "person.crop.circle").foregroundStyle(PajamasTheme.accent) }
            .accessibilityLabel("Account settings")
    }
    var body: some View {
        NavigationStack {
            HomeView()
                .navigationTitle("Mergefox")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(PajamasTheme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.pull").foregroundStyle(PajamasTheme.orange)
                            Text("Mergefox").font(.headline).foregroundStyle(PajamasTheme.text)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { accountButton }
                }
                .navigationDestination(isPresented: showingMR) {
                    MRView()
                        .navigationTitle("Merge request")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(PajamasTheme.canvas, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { accountButton } }
                }
        }
        .sheet(isPresented: $settings) { AccountView() }
        .sheet(isPresented: $model.showSignIn) { AccountView() }
        .alert("Mergefox", isPresented: Binding(get: { model.error != nil && !model.errorInSheet }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task { await model.loadHome() }
    }
}
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var filtering = false
    @State private var openedPage = 1
    private var openedPageCount: Int { max(1, (model.recentURLs.count + 4) / 5) }
    private var visibleMerged: [MergeRequest] { HomePagination.items(model.recentlyMerged, page: model.mergedPage) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let user = model.user {
                    HStack(spacing: 10) { Avatar(person: user); Text("@\(user.username)").font(.subheadline).foregroundStyle(PajamasTheme.secondary); Spacer(); Text("GitLab").font(.caption).foregroundStyle(PajamasTheme.secondary) }
                } else {
                    Text("Code review, in your pocket.").font(.title3.bold())
                }
                if model.account == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your GitLab, wherever you are.").font(.headline)
                        Text("Sign in to review private MRs, reply to discussions, and approve changes.").foregroundStyle(PajamasTheme.secondary)
                        Button("Sign in to GitLab") { model.showSignIn = true }.buttonStyle(PajamasPrimaryButtonStyle())
                        Button("Explore the demo") { model.loadDemo() }.buttonStyle(PajamasDefaultButtonStyle())
                    }.card()
                } else {
                    ReleaseDashboardView()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("My merge requests", systemImage: "arrow.triangle.pull").font(.headline).foregroundStyle(PajamasTheme.text)
                            Spacer()
                            Button { filtering = true } label: {
                                Label(model.inboxFilters.activeCount(tab: model.inboxFilter) == 0 ? "Filters" : "Filters (\(model.inboxFilters.activeCount(tab: model.inboxFilter)))", systemImage: "line.3.horizontal.decrease")
                                    .font(.caption.weight(.semibold))
                            }.buttonStyle(PajamasDefaultButtonStyle())
                        }
                        PajamasTabs(selection: $model.inboxFilter, options: [("To review", "reviews"), ("Created by me", "authored")])
                            .onChange(of: model.inboxFilter) { _, _ in Task { await model.loadInbox() } }
                        if model.loadingInbox { ProgressView("Loading merge requests…").padding() }
                        else if model.inbox.isEmpty { Text(model.inboxFilters.status == "opened" && model.inboxFilters.activeCount(tab: model.inboxFilter) == 0 ? "Nothing waiting here." : "No merge requests match these filters.").foregroundStyle(PajamasTheme.secondary).padding(.vertical, 12) }
                        ForEach(model.inbox) { mr in
                            Button { Task { await model.open(mr.webUrl) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "arrow.triangle.pull").foregroundStyle(PajamasTheme.success).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text((try? MRLocation.parse(mr.webUrl).project) ?? "GitLab").font(.caption).foregroundStyle(PajamasTheme.secondary)
                                        Text(mr.title).font(.subheadline.weight(.semibold)).foregroundStyle(PajamasTheme.text)
                                        Text("!\(mr.iid) opened by @\(mr.author.username)").font(.caption).foregroundStyle(PajamasTheme.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                            }
                            Divider()
                        }
                        if model.inboxPage > 1 || model.inboxHasNext {
                            HomePageControls(section: "My merge requests", page: model.inboxPage, hasNext: model.inboxHasNext, loading: model.loadingInbox) { page in
                                Task { await model.loadInbox(page: page) }
                            }
                        }
                    }.card()
                }
                if !model.recentURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENTLY OPENED").font(.caption.weight(.semibold)).foregroundStyle(PajamasTheme.secondary)
                        ForEach(HomePagination.items(model.recentURLs, page: min(openedPage, openedPageCount)), id: \.self) { url in
                            Button { Task { await model.open(url) } } label: { Label(url.replacingOccurrences(of: "https://", with: ""), systemImage: "clock").font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        if openedPageCount > 1 {
                            HomePageControls(section: "Recently opened", page: min(openedPage, openedPageCount), hasNext: openedPage < openedPageCount, loading: false) { openedPage = $0 }
                        }
                    }.card()
                }
                if model.account != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENTLY MERGED").font(.caption.weight(.semibold)).foregroundStyle(PajamasTheme.secondary)
                        Text("Merge requests you created or were asked to review.").font(.caption).foregroundStyle(PajamasTheme.secondary)
                        if model.loadingMerged && model.recentlyMerged.isEmpty {
                            ProgressView("Loading merged requests…").padding(.vertical, 8)
                        } else if let error = model.mergedError {
                            Text(error).font(.subheadline).foregroundStyle(PajamasTheme.secondary)
                            Button("Retry") { Task { await model.loadRecentlyMerged() } }.buttonStyle(PajamasDefaultButtonStyle())
                        } else if model.recentlyMerged.isEmpty {
                            Text("No merged requests yet.").font(.subheadline).foregroundStyle(PajamasTheme.secondary)
                        }
                        ForEach(visibleMerged) { mr in
                            Button { Task { await model.open(mr.webUrl) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "arrow.triangle.merge").foregroundStyle(PajamasTheme.accent).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text((try? MRLocation.parse(mr.webUrl).project) ?? "GitLab").font(.caption).foregroundStyle(PajamasTheme.secondary)
                                        Text(mr.title).font(.subheadline.weight(.semibold)).foregroundStyle(PajamasTheme.text)
                                        Text("!\(mr.iid) · @\(mr.author.username)\(mergedDate(mr.mergedAt))").font(.caption).foregroundStyle(PajamasTheme.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(PajamasTheme.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                            if mr.id != visibleMerged.last?.id { Divider() }
                        }
                        if model.mergedPage > 1 || HomePagination.hasNext(count: model.recentlyMerged.count, page: model.mergedPage) {
                            HomePageControls(section: "Recently merged", page: model.mergedPage, hasNext: HomePagination.hasNext(count: model.recentlyMerged.count, page: model.mergedPage), loading: model.loadingMerged) { page in
                                Task { await model.loadRecentlyMerged(page: page, reset: false) }
                            }
                        }
                    }.card()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Open a merge request").font(.headline)
                    HStack {
                        PasteButton(payloadType: String.self) { values in if let first = values.first { model.openText = first } }.labelStyle(.titleAndIcon)
                        Spacer()
                    }
                    TextField("Paste a GitLab MR URL", text: $model.openText).keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).background(PajamasTheme.inset, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("mrURL")
                    Button { Task { await model.open(model.openText) } } label: { Label("Open merge request", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }.buttonStyle(PajamasPrimaryButtonStyle()).disabled(model.openText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.loading)
                }.card()
            }.padding()
        }.background(PajamasTheme.canvas)
            .refreshable { openedPage = 1; await model.loadHome() }
            .onChange(of: model.recentURLs) { _, _ in openedPage = 1 }
            .sheet(isPresented: $filtering) { InboxFiltersView(filters: model.inboxFilters).environmentObject(model) }
    }
    private func mergedDate(_ value: String?) -> String {
        guard let value else { return "" }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return "" }
        return " · Merged \(date.formatted(.relative(presentation: .numeric)))"
    }
}
struct AccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var host = "https://gitlab.com"
    @State private var clientID = ""
    @State private var token = ""
    @State private var useToken = false
    @State private var advanced = false
    var body: some View {
        NavigationStack {
            Form {
                if let account = model.account {
                    Section("Connected account") {
                        Label(model.user.map { "@\($0.username)" } ?? "GitLab account", systemImage: "person.crop.circle.fill")
                        Text(account.host.absoluteString).foregroundStyle(PajamasTheme.secondary)
                        Text(account.isOAuth ? "OAuth · credentials stored in Keychain" : "Personal access token · stored in Keychain").font(.caption).foregroundStyle(PajamasTheme.secondary)
                        Button("Sign out", role: .destructive) { Task { await model.signOut(); token = "" } }.disabled(model.authenticating || model.mutating)
                    }
                }
                Section {
                    Image(systemName: "arrow.triangle.pull").font(.largeTitle).foregroundStyle(PajamasTheme.orange).frame(maxWidth: .infinity).padding(.vertical, 10)
                    Text("Connect your GitLab account").font(.title2.bold())
                    Text("Sign in through GitLab. Your password stays with GitLab; account credentials are securely stored on this device.").font(.subheadline).foregroundStyle(PajamasTheme.secondary)
                    if model.authenticating { ProgressView("Connecting…") }
                    else {
                        Button { Task { await model.signIn(host: host, clientID: resolvedClientID); if model.account != nil && model.error == nil { dismiss() } } } label: { Label("Continue with GitLab", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }.buttonStyle(PajamasPrimaryButtonStyle())
                        if resolvedClientID.isEmpty { Text("One-time OAuth app registration is pending. You can use a personal access token now.").font(.caption).foregroundStyle(PajamasTheme.secondary) }
                    }
                }
                Section {
                    DisclosureGroup("Use a personal access token", isExpanded: $useToken) {
                        SecureField("GitLab personal access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("personalToken")
                        Text("Use a personal access token with the api scope for approval, comments, and edits. A read_api token can browse MRs.").font(.caption).foregroundStyle(PajamasTheme.secondary)
                        Button("Connect with token") { Task { await model.tokenSignIn(host: host, token: token); if model.account != nil && model.error == nil { token = ""; dismiss() } } }.disabled(token.isEmpty || model.authenticating)
                        Link("Create a token in GitLab", destination: tokenSettingsURL)
                    }
                }
                Section {
                    DisclosureGroup("Advanced / self-hosted GitLab", isExpanded: $advanced) {
                        TextField("GitLab host", text: $host).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("OAuth application ID (optional)", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("For a custom host, register a non-confidential OAuth app with redirect URI mergepocket://oauth/callback and api scope. No client secret is used.").font(.caption).foregroundStyle(PajamasTheme.secondary)
                    }
                }
                Section("Preferences") {
                    Picker("Default merge request tab", selection: $model.defaultInboxTab) {
                        Text("To review").tag("reviews")
                        Text("Created by me").tag("authored")
                    }
                    .onChange(of: model.defaultInboxTab) { _, value in
                        model.inboxFilter = value
                    }
                }
                Section {
                    Button("Explore the demo") { model.loadDemo(); dismiss() }
                    Text("Mergefox for GitLab · Public GitLab MRs can also be opened without signing in.").font(.caption).foregroundStyle(PajamasTheme.secondary)
                    NavigationLink("Open-source notices") {
                        ScrollView {
                            Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "gitdiff · MIT · Copyright 2024 Tornike Gomareli")
                                .font(.caption).textSelection(.enabled).padding()
                        }.navigationTitle("Open-source notices")
                    }
                }
            }
            .navigationTitle("GitLab account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.authenticating) } }
            .onAppear { host = model.account?.host.absoluteString ?? "https://gitlab.com"; clientID = model.account?.clientID ?? "" }
        }.interactiveDismissDisabled(model.authenticating)
            .onAppear { model.errorInSheet = true }
            .onDisappear { model.errorInSheet = false }
            .alert("GitLab sign-in", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
    var resolvedClientID: String {
        if !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
        if (try? URL.gitlabHost(host))?.host == "gitlab.com" { return Bundle.main.object(forInfoDictionaryKey: "GitLabOAuthClientID") as? String ?? "" }
        return ""
    }
    var tokenSettingsURL: URL { (try? URL.gitlabHost(host))?.appendingPathComponent("-/user_settings/personal_access_tokens") ?? URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens")! }
}
struct MRView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = "overview"
    @State private var editing = false
    @State private var confirmingApproval = false
    var body: some View {
        VStack(spacing: 0) {
            if model.demo {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(PajamasTheme.orange)
                    Text("Demo · Sample data, actions disabled").foregroundStyle(PajamasTheme.text)
                }.font(.caption.weight(.medium)).frame(maxWidth: .infinity).padding(10).background(PajamasTheme.inset)
            }
            if let mr = model.mr {
                PajamasTabs(selection: $tab, options: [("Overview", "overview"), ("Changes", "changes"), ("Discussion", "discussion")]).padding(.horizontal, 16).padding(.vertical, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if tab == "overview" { overview(mr) }
                        else if tab == "changes" { changes }
                        else { discussion }
                    }.padding(.horizontal, tab == "changes" ? 0 : 16).padding(.vertical, tab == "changes" ? 0 : 16)
                }.refreshable { if let loc = model.location, !model.demo { await model.load(loc) } }
                if model.loading { ProgressView("Loading MR content…").font(.caption).padding(8) }
                HStack(spacing: 12) {
                    if let url = URL(string: mr.webUrl) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(PajamasTheme.accent) }.accessibilityLabel("Share MR URL") }
                    if model.account == nil && !model.demo { Button("Sign in to approve") { model.showSignIn = true }.buttonStyle(PajamasPrimaryButtonStyle()).frame(maxWidth: .infinity) }
                    else {
                        Button { confirmingApproval = true } label: {
                            Label(model.approvedByMe ? "Undo approval" : "Approve", systemImage: model.approvedByMe ? "checkmark.circle.fill" : "checkmark.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(PajamasPrimaryButtonStyle()).disabled(!model.canWrite || model.mutating || model.loading || mr.state != "opened")
                    }
                    Button { editing = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(PajamasTheme.accent) }.accessibilityLabel("Edit merge request").disabled(!model.canWrite || model.mutating || model.loading)
                }.padding().background(PajamasTheme.surface).overlay(alignment: .top) { Rectangle().fill(PajamasTheme.border).frame(height: 0.5) }
            } else if model.loading {
                MRLoadingView()
            } else {
                ContentUnavailableView("Couldn’t load this MR", systemImage: "arrow.triangle.pull", description: Text("Check the URL and your GitLab account, then try again."))
                Button("Try again") { if let loc = model.location { Task { await model.load(loc) } } }.buttonStyle(PajamasDefaultButtonStyle()).padding()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PajamasTheme.canvas.ignoresSafeArea())
        .sheet(isPresented: $editing) { if let mr = model.mr { EditMRView(mr: mr) } }
        .confirmationDialog(model.approvedByMe ? "Remove your approval?" : "Approve this version of the MR?", isPresented: $confirmingApproval, titleVisibility: .visible) {
            Button(model.approvedByMe ? "Undo approval" : "Approve") { Task { await model.approve() } }
        } message: { Text(model.approvedByMe ? "Your approval will be removed." : "Your approval applies to the commit you’ve loaded. GitLab will reject it if the branch has changed.") }
        .onChange(of: model.location) { _, _ in tab = "overview" }
    }
    @ViewBuilder func overview(_ mr: MergeRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(model.location?.project ?? "GitLab")  !\(mr.iid)").font(.subheadline).foregroundStyle(PajamasTheme.secondary)
            Text(mr.title).font(.title2.bold()).foregroundStyle(PajamasTheme.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StatusBadge(text: mr.draft == true ? "Draft" : mr.state == "opened" ? "Open" : mr.state.capitalized, color: mr.state == "merged" ? PajamasTheme.accent : PajamasTheme.success)
                    BranchChip(name: mr.sourceBranch)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(PajamasTheme.secondary)
                    BranchChip(name: mr.targetBranch)
                }
            }
            if !mr.labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(mr.labels, id: \.self) { label in StatusBadge(text: label, color: PajamasTheme.secondary) } } }
            }
        }.card()
        VStack(alignment: .leading, spacing: 12) {
            PersonRow(person: mr.author, detail: "Author")
            Divider()
            MarkdownText(text: mr.description?.isEmpty == false ? mr.description! : "No description provided.")
        }.card()
        VStack(alignment: .leading, spacing: 0) {
            Button { tab = "changes" } label: {
                HStack { Label("\(model.diffs.count) files changed", systemImage: "doc.text"); Spacer(); Text("+\(additionCount)").foregroundStyle(PajamasTheme.success); Text("−\(deletionCount)").foregroundStyle(PajamasTheme.danger); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PajamasTheme.secondary) }.font(.subheadline).padding(.vertical, 8)
            }.foregroundStyle(PajamasTheme.text)
            Divider()
            Button { tab = "discussion" } label: {
                HStack { Label("Discussion", systemImage: "bubble.left.and.bubble.right"); Spacer(); Text("\(model.discussions.filter { $0.notes.first?.system != true }.count)").foregroundStyle(PajamasTheme.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PajamasTheme.secondary) }.font(.subheadline).padding(.vertical, 8)
            }.foregroundStyle(PajamasTheme.text)
        }.card()
        VStack(alignment: .leading, spacing: 14) {
            Text("Reviewers").font(.headline)
            if (mr.reviewers ?? []).isEmpty { Text("No reviewers assigned.").foregroundStyle(PajamasTheme.secondary) }
            ForEach(mr.reviewers ?? []) { p in PersonRow(person: p, detail: model.approval?.approvedBy.contains(where: { $0.user.id == p.id }) == true ? "Approved" : "Requested") }
            if !(mr.assignees ?? []).isEmpty {
                Divider(); Text("Assignees").font(.headline)
                ForEach(mr.assignees ?? []) { p in PersonRow(person: p, detail: "Assignee") }
            }
        }.card()
        VStack(alignment: .leading, spacing: 12) {
            Text("Checks & approvals").font(.headline)
            if let pipeline = mr.headPipeline { HStack { Image(systemName: pipeline.status == "success" ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(pipeline.status == "success" ? PajamasTheme.success : PajamasTheme.secondary); Text("Pipeline: \(pipeline.status)").foregroundStyle(PajamasTheme.text) } }
            if let status = mr.detailedMergeStatus { Text(status.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline).foregroundStyle(PajamasTheme.secondary) }
            if let approval = model.approval {
                Text("\(approval.approvedBy.count) approval\(approval.approvedBy.count == 1 ? "" : "s")")
                if let remaining = approval.approvalsLeft { Text("\(remaining) required approval\(remaining == 1 ? "" : "s") remaining").font(.caption).foregroundStyle(PajamasTheme.secondary) }
                ForEach(approval.approvedBy, id: \.user.id) { PersonRow(person: $0.user, detail: "Approved") }
            }
            if let warning = model.approvalWarning { Text(warning).font(.caption).foregroundStyle(PajamasTheme.secondary) }
            if let url = URL(string: mr.webUrl) { Link("Open in GitLab", destination: url) }
        }.card()
    }
    var additionCount: Int { model.diffs.reduce(0) { $0 + $1.diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count } }
    var deletionCount: Int { model.diffs.reduce(0) { $0 + $1.diff.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count } }
    var changes: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("\(model.diffs.count) files changed").font(.headline); Spacer(); Text("+\(additionCount)").foregroundStyle(PajamasTheme.success); Text("−\(deletionCount)").foregroundStyle(PajamasTheme.danger) }.font(.subheadline.monospaced()).padding(16)
            if model.diffs.count >= 1000 { Text("Showing up to 1,000 files. Open GitLab for the complete diff.").font(.caption).foregroundStyle(PajamasTheme.secondary) }
            if model.diffs.isEmpty && !model.loading { Text("No diff content available. GitLab may still be preparing the changes.").foregroundStyle(PajamasTheme.secondary) }
            LazyVStack(spacing: 0) { ForEach(model.diffs) { file in DiffCard(file: file) } }
        }
    }
    var discussion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(model.discussions.count) discussions").font(.headline)
            if model.discussions.count >= 1000 { Text("Showing up to 1,000 discussions. Open GitLab for the full history.").font(.caption).foregroundStyle(PajamasTheme.secondary) }
            if let warning = model.discussionWarning { Text(warning).foregroundStyle(PajamasTheme.secondary); if model.account == nil { Button("Sign in") { model.showSignIn = true }.buttonStyle(PajamasPrimaryButtonStyle()) } }
            else if model.discussions.isEmpty && !model.loading { Text("No discussions yet.").foregroundStyle(PajamasTheme.secondary) }
            LazyVStack(spacing: 16) { ForEach(model.discussions) { DiscussionCard(thread: $0) } }
            if model.canWrite { CommentComposer() }
        }
    }
}
