import SwiftUI
 
struct MRLoadingView: View {
    var title = "Opening merge request"

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(PajamasTheme.accent)
                .frame(width: 64, height: 64)
                .background(PajamasTheme.selected, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title).font(.headline).foregroundStyle(PajamasTheme.text)
                Text("Getting your review ready…").font(.subheadline).foregroundStyle(PajamasTheme.secondary)
            }
            .multilineTextAlignment(.center)
            ProgressView().tint(PajamasTheme.accent).accessibilityLabel(title)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PajamasTheme.canvas.ignoresSafeArea())
    }
}
import gitdiff

extension View {
    func card() -> some View { self.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(PajamasTheme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(PajamasTheme.border, lineWidth: 0.5)) }
}
struct Avatar: View {
    let person: Person
    var body: some View {
        AsyncImage(url: person.avatarUrl.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(String(person.name.prefix(1))).font(.subheadline.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.tertiarySystemFill)).foregroundStyle(PajamasTheme.secondary)
        }.frame(width: 32, height: 32).clipShape(Circle()).accessibilityHidden(true)
    }
}
struct BranchChip: View {
    let name: String
    var body: some View {
        Text(name).font(.caption.monospaced()).foregroundStyle(PajamasTheme.link)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(PajamasTheme.inset, in: RoundedRectangle(cornerRadius: 5))
    }
}
struct StatusBadge: View {
    let text: String
    var color: Color = PajamasTheme.secondary
    var body: some View { Text(text).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).foregroundStyle(color).background(color.opacity(0.12), in: Capsule()) }
}
struct PersonRow: View {
    let person: Person
    var detail: String = ""
    var body: some View {
        HStack(spacing: 10) {
            Avatar(person: person)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.subheadline.weight(.semibold))
                Text("@\(person.username)").font(.caption).foregroundStyle(PajamasTheme.secondary)
            }
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(PajamasTheme.secondary) }
        }
    }
}
struct DiffCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let file: FileDiff
    @State private var expanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .frame(width: 24, height: 30)
                }.accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(file.newPath)")
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(file.newPath).font(.subheadline.monospaced().weight(.semibold))
                        .fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                }.accessibilityHint("Swipe horizontally to read the full filename")
                if file.newFile == true { Text("Added").font(.caption).foregroundStyle(PajamasTheme.success) }
                if file.deletedFile == true { Text("Deleted").font(.caption).foregroundStyle(PajamasTheme.danger) }
                if file.renamedFile == true { Text("Renamed").font(.caption).foregroundStyle(PajamasTheme.secondary) }
            }.foregroundStyle(PajamasTheme.text).padding(.horizontal, 12).padding(.vertical, 10)
            Divider()
            if expanded {
                if file.diff.isEmpty {
                    Text(file.tooLarge == true ? "This diff exceeds GitLab’s size limit. View it in GitLab." : "No text diff provided. This may be a binary or collapsed file.").font(.caption).foregroundStyle(PajamasTheme.secondary).padding(16)
                } else {
                    EdgeDiffView(patch: file.patch)
                }
                ForEach(relatedThreads) { thread in DiscussionCard(thread: thread).padding(12) }
            }
            Divider()
        }.background(PajamasTheme.surface)
    }
    var relatedThreads: [Discussion] {
        model.discussions.filter { thread in
            let p = thread.notes.first?.position
            return p != nil && (p?.newPath == file.newPath || p?.oldPath == file.oldPath)
        }
    }
}
struct DiscussionCard: View {
    @EnvironmentObject var model: AppModel
    let thread: Discussion
    @State private var replying = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let position = thread.notes.first?.position {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("\(position.newPath ?? position.oldPath ?? "File")\(position.newLine.map { ":\($0)" } ?? position.oldLine.map { ":\($0) (old)" } ?? "")").font(.caption.monospaced()).lineLimit(3)
                    Spacer()
                    if let head = position.headSha, head != model.mr?.sha { StatusBadge(text: "Earlier revision", color: .secondary) }
                }.foregroundStyle(PajamasTheme.secondary)
            }
            ForEach(thread.notes) { note in
                if note.system == true {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock").font(.caption).foregroundStyle(PajamasTheme.secondary).padding(.top, 3)
                        MarkdownText(text: note.body, compact: true)
                    }
                }
                else {
                    VStack(alignment: .leading, spacing: 8) {
                        PersonRow(person: note.author, detail: dateLabel(note.createdAt))
                        MarkdownText(text: note.body)
                    }
                }
                if note.id != thread.notes.last?.id { Divider() }
            }
            HStack {
                if thread.isResolved { StatusBadge(text: "Resolved", color: PajamasTheme.success) }
                if model.canWrite && thread.individualNote != true {
                    Button(replying ? "Cancel reply" : "Reply") { replying.toggle() }.buttonStyle(PajamasDefaultButtonStyle())
                    Spacer()
                    if thread.isResolvable { Button(thread.isResolved ? "Reopen" : "Resolve") { Task { await model.resolve(thread) } }.buttonStyle(PajamasDefaultButtonStyle()).disabled(model.mutating) }
                }
            }
            if replying { CommentComposer(discussionID: thread.id, onSent: { replying = false }) }
        }.card()
    }
    func dateLabel(_ value: String?) -> String {
        guard let value else { return "" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return "" }
        return d.formatted(.relative(presentation: .numeric))
    }
}
struct CommentComposer: View {
    @EnvironmentObject var model: AppModel
    var discussionID: String? = nil
    var onSent: () -> Void = {}
    @State private var bodyText = ""
    @State private var sending = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(discussionID == nil ? "Add a comment" : "Reply to thread").font(.headline)
            TextEditor(text: $bodyText).frame(minHeight: 100).padding(6).background(PajamasTheme.inset, in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel(discussionID == nil ? "Comment text" : "Reply text")
            Button {
                sending = true
                Task {
                    let success = await model.comment(bodyText, discussionID: discussionID)
                    sending = false
                    if success { bodyText = ""; onSent() }
                }
            } label: { Label(sending ? "Sending…" : "Send", systemImage: "paperplane.fill") }
                .buttonStyle(PajamasPrimaryButtonStyle()).disabled(sending || model.mutating || model.loading || !model.canWrite || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.card()
    }
}
struct EditMRView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var target: String
    @State private var labels: String
    @State private var confirm = false
    init(mr: MergeRequest) {
        _title = State(initialValue: mr.title); _description = State(initialValue: mr.description ?? "")
        _target = State(initialValue: mr.targetBranch); _labels = State(initialValue: mr.labels.joined(separator: ", "))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("MR title", text: $title, axis: .vertical) }
                Section("Description") { TextEditor(text: $description).frame(minHeight: 160) }
                Section("Target branch") { TextField("main", text: $target).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Section { TextField("bug, iOS", text: $labels, axis: .vertical).textInputAutocapitalization(.never) } header: { Text("Labels") } footer: { Text("Separate labels with commas. Unknown names create project labels. Leave empty to remove all labels.") }
                Section { Text("Changing the target branch may change the diff and reset approvals, depending on project settings.").font(.caption).foregroundStyle(PajamasTheme.secondary) }
            }
            .navigationTitle("Edit merge request").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.mutating) }
                ToolbarItem(placement: .confirmationAction) { Button(model.mutating ? "Saving…" : "Save") { confirm = true }.disabled(model.mutating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .confirmationDialog("Save changes to GitLab?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Save changes") { Task { if await model.edit(title: title, description: description, target: target.trimmingCharacters(in: .whitespacesAndNewlines), labels: labels) { dismiss() } } }
            }
        }.interactiveDismissDisabled(model.mutating)
            .onAppear { model.errorInSheet = true }
            .onDisappear { model.errorInSheet = false }
            .alert("Couldn’t save changes", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
