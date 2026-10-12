import SwiftUI
import UniformTypeIdentifiers
import SafariServices

@MainActor final class ShareViewController: UIViewController {
    private let state = ShareState()
    private let model = AppModel()
    private var loadingTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareReviewView(state: state, model: model, done: { [weak self] in
            self?.loadingTask?.cancel()
            self?.extensionContext?.completeRequest(returningItems: nil)
        }, openLink: { [weak self] url in self?.showWebLink(url) })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 600, height: 750)
        loadingTask = Task { [weak self] in await self?.readSharedLink() }
    }

    private func showWebLink(_ url: URL) {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    private func readSharedLink() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    if let text = await Self.text(from: provider, type: type), let url = SharedMRLink.extract(from: text) {
                        await openMR(url)
                        return
                    }
                }
            }
            if let text = item.attributedContentText?.string, let url = SharedMRLink.extract(from: text) {
                await openMR(url)
                return
            }
        }
        state.reading = false
        state.invalidLink = true
    }

    private func openMR(_ url: URL) async {
        if let account = model.account {
            model.user = try? await model.api.request(Person.self, host: account.host, path: "user")
        }
        guard !Task.isCancelled else { return }
        state.reading = false
        await model.open(url.absoluteString)
    }

    private static func text(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                let text: String?
                if let url = value as? URL { text = url.absoluteString }
                else if let string = value as? String { text = string }
                else if let data = value as? Data { text = String(data: data, encoding: .utf8) }
                else { text = nil }
                continuation.resume(returning: text)
            }
        }
    }
}

@MainActor final class ShareState: ObservableObject {
    @Published var reading = true
    @Published var invalidLink = false
}

struct ShareReviewView: View {
    @ObservedObject var state: ShareState
    @ObservedObject var model: AppModel
    let done: () -> Void
    let openLink: (URL) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if state.reading { MRLoadingView(title: "Reading shared link") }
                else if state.invalidLink {
                    ContentUnavailableView("Share a merge request", systemImage: "arrow.triangle.pull", description: Text("Share a GitLab MR link or a message containing one from Slack, Safari, or another app."))
                } else { MRView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PajamasTheme.canvas.ignoresSafeArea())
            .navigationTitle("Mergefox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: done) } }
            .toolbarBackground(PajamasTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .environmentObject(model)
        .environment(\.openURL, OpenURLAction { url in openLink(url); return .handled })
        .tint(PajamasTheme.accent)
        .foregroundStyle(PajamasTheme.text)
        .sheet(isPresented: $model.showSignIn) {
            NavigationStack {
                ContentUnavailableView("Sign in to Mergefox", systemImage: "person.crop.circle", description: Text("Open the Mergefox app and sign in to GitLab, then share this link again. Your sign-in is securely available here too."))
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { model.showSignIn = false } } }
            }
        }
        .alert("Mergefox", isPresented: Binding(get: { model.error != nil && !model.errorInSheet }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
