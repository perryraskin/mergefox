import SwiftUI

struct ReleaseDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var metric: ReleaseMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Release overview", systemImage: "shippingbox").font(.headline).foregroundStyle(PajamasTheme.text)
            if !model.releaseProjects.isEmpty {
                Menu {
                    ForEach(model.releaseProjects) { project in
                        Button { Task { await model.selectReleaseProject(project.id) } } label: {
                            if project.id == model.releaseProjectID { Label(project.path, systemImage: "checkmark") }
                            else { Text(project.path) }
                        }
                    }
                } label: {
                    HStack { Text(model.releaseProjects.first(where: { $0.id == model.releaseProjectID })?.path ?? "Project").lineLimit(1); Spacer(); Image(systemName: "chevron.down") }
                        .font(.subheadline).foregroundStyle(PajamasTheme.text)
                }.disabled(model.loadingRelease)
            }
            if !model.releaseBranches.isEmpty {
                Menu {
                    ForEach(model.releaseBranches) { branch in
                        Button { Task { await model.selectReleaseBranch(branch.name) } } label: {
                            if branch.name == model.releaseBranchName { Label(branch.name, systemImage: "checkmark") }
                            else { Text(branch.name) }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(PajamasTheme.accent)
                        ScrollView(.horizontal, showsIndicators: false) { Text(model.releaseBranchName ?? "Release branch").font(.subheadline.monospaced()).fixedSize() }
                        Image(systemName: "chevron.down").font(.caption)
                    }.foregroundStyle(PajamasTheme.text).padding(12).background(PajamasTheme.inset, in: RoundedRectangle(cornerRadius: 8))
                }.disabled(model.loadingRelease)
                    .accessibilityLabel("Select release branch")
            }
            if let error = model.releaseError {
                Text(error).font(.subheadline).foregroundStyle(PajamasTheme.secondary)
                Button("Retry") { Task { await model.loadReleaseDashboard() } }.buttonStyle(PajamasDefaultButtonStyle())
            }
            if let summary = model.releaseSummary {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ReleaseMetric.allCases) { item in
                        Button { metric = item } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(model.loadingRelease && (item == .ready || item == .attention) ? "…" : "\(summary.matching(item).count)\(summary.truncated ? "+" : "")")
                                        .font(.title2.bold()).foregroundStyle(PajamasTheme.text)
                                    Spacer()
                                    Image(systemName: item.symbol).foregroundStyle(item == .attention ? PajamasTheme.orange : PajamasTheme.accent)
                                }
                                Text(item.title).font(.caption.weight(.medium)).foregroundStyle(PajamasTheme.text)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(PajamasTheme.inset, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(model.loadingRelease && (item == .ready || item == .attention))
                            .accessibilityLabel("\(item.title), \(summary.matching(item).count) merge requests")
                    }
                }
                if let oldest = summary.oldest, let date = ReleaseMetrics.date(oldest.mr.createdAt) {
                    Button { Task { await model.open(oldest.mr.webUrl) } } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "clock")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Oldest pending · opened \(date.formatted(.relative(presentation: .numeric)))").font(.caption.weight(.medium))
                                Text("!\(oldest.mr.iid) \(oldest.mr.title)").font(.caption).lineLimit(2)
                            }
                            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(PajamasTheme.text)
                    }.buttonStyle(.plain)
                }
                if summary.truncated { Text("Based on the latest 1,000 MRs targeting this branch. Counts are minimums.").font(.caption).foregroundStyle(PajamasTheme.secondary) }
                if !model.loadingRelease && summary.unknownCount > 0 {
                    Text("Status unconfirmed for \(summary.unknownCount) open MRs; they aren’t counted as ready.").font(.caption).foregroundStyle(PajamasTheme.secondary)
                }
            } else if !model.loadingRelease && model.releaseError == nil {
                Text(model.releaseProjects.isEmpty ? "Open an MR or join a review to discover your release projects." : "No release/* branches in this project.").font(.subheadline).foregroundStyle(PajamasTheme.secondary)
            }
            if model.loadingRelease { ProgressView(model.releaseSummary == nil ? "Loading release…" : "Checking merge readiness…").font(.caption) }
        }.card()
            .sheet(item: $metric) { metric in ReleaseMetricListView(metric: metric).environmentObject(model) }
    }
}

struct ReleaseMetricListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let metric: ReleaseMetric
    @State private var page = 1
    private var items: [ReleaseMR] { model.releaseSummary?.matching(metric) ?? [] }
    private var pageCount: Int { max(1, (items.count + 4) / 5) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.releaseProjects.first(where: { $0.id == model.releaseProjectID })?.path ?? "").font(.caption).foregroundStyle(PajamasTheme.secondary)
                    ScrollView(.horizontal, showsIndicators: false) { Text(model.releaseBranchName ?? "").font(.subheadline.monospaced()).fixedSize() }
                    Text("\(items.count) merge requests · all authors").font(.subheadline).foregroundStyle(PajamasTheme.secondary)
                    if items.isEmpty { Text("No merge requests here.").foregroundStyle(PajamasTheme.secondary).padding(.vertical) }
                    ForEach(HomePagination.items(items, page: min(page, pageCount))) { item in
                        Button {
                            dismiss()
                            Task { await model.open(item.mr.webUrl) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.mr.title).font(.subheadline.weight(.semibold)).foregroundStyle(PajamasTheme.text)
                                Text("!\(item.mr.iid) · @\(item.mr.author.username)").font(.caption).foregroundStyle(PajamasTheme.secondary)
                                ScrollView(.horizontal, showsIndicators: false) { Text(item.mr.sourceBranch).font(.caption.monospaced()).fixedSize().foregroundStyle(PajamasTheme.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if pageCount > 1 {
                        HomePageControls(section: metric.title, page: min(page, pageCount), hasNext: page < pageCount, loading: false) { page = $0 }
                    }
                }.padding()
            }.background(PajamasTheme.canvas)
                .navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
