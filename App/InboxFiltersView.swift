import SwiftUI

struct InboxFiltersView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var filters: MRInboxFilters

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Status", selection: $filters.status) {
                        Text("Open").tag("opened")
                        Text("Merged").tag("merged")
                        Text("Closed").tag("closed")
                        Text("All statuses").tag("all")
                    }
                    TextField("Target branch", text: $filters.targetBranch)
                    if model.inboxFilter == "reviews" {
                        TextField("Author username", text: $filters.author)
                    } else {
                        LabeledContent("Author", value: model.user.map { "@\($0.username)" } ?? "You")
                    }
                    TextField("Labels, separated by commas", text: $filters.labels)
                    TextField("Search title and description", text: $filters.search)
                } footer: {
                    Text(model.inboxFilter == "reviews" ? "Filters apply to merge requests where you’re a reviewer." : "Filters apply to merge requests you created.")
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                Section {
                    Button("Reset filters") { filters = MRInboxFilters() }
                }
            }
            .navigationTitle("Filter merge requests").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.inboxFilters = filters
                        dismiss()
                        Task { await model.loadInbox() }
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}
