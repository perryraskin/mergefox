import Foundation

extension AppModel {
    func resetReleaseDashboard() {
        releaseGeneration = UUID()
        releaseProjects = []; releaseBranches = []; releaseSummary = nil
        releaseProjectID = nil; releaseBranchName = nil; releaseError = nil; loadingRelease = false
    }

    func loadReleaseDashboard() async {
        guard let account, !demo else { return }
        releaseGeneration = UUID(); let generation = releaseGeneration
        loadingRelease = true; releaseError = nil
        defer { if generation == releaseGeneration { loadingRelease = false } }
        do {
            let person: Person
            if let user { person = user }
            else { person = try await api.request(Person.self, host: account.host, path: "user") }
            let authoredQuery = ReleaseMetrics.discoveryQuery(tab: "authored", userID: person.id)
            let reviewedQuery = ReleaseMetrics.discoveryQuery(tab: "reviews", userID: person.id)
            async let authored = api.request([MergeRequest].self, host: account.host, path: "merge_requests", query: authoredQuery)
            async let reviewed = api.request([MergeRequest].self, host: account.host, path: "merge_requests", query: reviewedQuery)
            let values = try await (authored, reviewed)
            var candidates = values.0 + values.1
            // Include projects visited through shared links, even when the user isn't a reviewer.
            for url in recentURLs.prefix(3) {
                guard let loc = try? MRLocation.parse(url), loc.host == account.host,
                      !candidates.contains(where: { (try? MRLocation.parse($0.webUrl).project) == loc.project }) else { continue }
                if let detail = try? await api.request(MergeRequest.self, host: account.host, path: GitLabAPI.path(loc)) { candidates.append(detail) }
            }
            guard generation == releaseGeneration, !Task.isCancelled else { return }
            releaseProjects = ReleaseMetrics.projects(from: candidates, recent: recentURLs, host: account.host)
            let saved = UserDefaults.standard.integer(forKey: "releaseProject:\(account.host.absoluteString)")
            releaseProjectID = releaseProjects.first(where: { $0.id == releaseProjectID || $0.id == saved })?.id ?? releaseProjects.first?.id
            guard let projectID = releaseProjectID else { releaseSummary = nil; return }
            try await fetchReleaseBranches(projectID: projectID, host: account.host, generation: generation)
        } catch {
            if generation == releaseGeneration, !Task.isCancelled { releaseError = error.localizedDescription }
        }
    }

    func selectReleaseProject(_ projectID: Int) async {
        guard let account else { return }
        releaseGeneration = UUID(); let generation = releaseGeneration
        releaseProjectID = projectID; releaseBranchName = nil; releaseBranches = []; releaseSummary = nil
        loadingRelease = true; releaseError = nil
        UserDefaults.standard.set(projectID, forKey: "releaseProject:\(account.host.absoluteString)")
        defer { if generation == releaseGeneration { loadingRelease = false } }
        do { try await fetchReleaseBranches(projectID: projectID, host: account.host, generation: generation) }
        catch { if generation == releaseGeneration, !Task.isCancelled { releaseError = error.localizedDescription } }
    }

    private func fetchReleaseBranches(projectID: Int, host: URL, generation: UUID) async throws {
        let branches = try await api.paginated(ReleaseBranch.self, host: host,
            path: "projects/\(projectID)/repository/branches", query: ["search": "^release/"])
        guard generation == releaseGeneration, !Task.isCancelled else { return }
        releaseBranches = ReleaseMetrics.sortedBranches(branches)
        let saved = UserDefaults.standard.string(forKey: "releaseBranch:\(host.absoluteString):\(projectID)")
        releaseBranchName = releaseBranches.first(where: { $0.name == releaseBranchName || $0.name == saved })?.name ?? releaseBranches.first?.name
        guard let branch = releaseBranchName else { releaseSummary = nil; return }
        try await fetchReleaseSummary(projectID: projectID, branch: branch, host: host, generation: generation)
    }

    func selectReleaseBranch(_ branch: String) async {
        guard let account, let projectID = releaseProjectID else { return }
        releaseGeneration = UUID(); let generation = releaseGeneration
        releaseBranchName = branch; releaseSummary = nil; loadingRelease = true; releaseError = nil
        UserDefaults.standard.set(branch, forKey: "releaseBranch:\(account.host.absoluteString):\(projectID)")
        defer { if generation == releaseGeneration { loadingRelease = false } }
        do { try await fetchReleaseSummary(projectID: projectID, branch: branch, host: account.host, generation: generation) }
        catch { if generation == releaseGeneration, !Task.isCancelled { releaseError = error.localizedDescription } }
    }

    private func fetchReleaseSummary(projectID: Int, branch: String, host: URL, generation: UUID) async throws {
        let values = try await api.paginated(MergeRequest.self, host: host, path: "projects/\(projectID)/merge_requests",
            query: ["state": "all", "scope": "all", "target_branch": branch, "order_by": "updated_at", "sort": "desc"])
        guard generation == releaseGeneration, !Task.isCancelled else { return }
        // Match the exact target locally too, so unrelated branches never affect the counts.
        var summary = ReleaseMetrics.summary(target: branch, mrs: values)
        releaseSummary = summary
        let open = summary.matching(.open).map(\.mr)
        // Four MRs at a time avoids a burst of detail and approval requests.
        for start in stride(from: 0, to: open.count, by: 4) {
            try Task.checkCancellation()
            guard generation == releaseGeneration else { return }
            let batch = Array(open[start..<min(start + 4, open.count)])
            let results = await withTaskGroup(of: ReleaseMR.self, returning: [ReleaseMR].self) { group in
                for mr in batch { group.addTask { await ReleaseMetrics.hydrate(mr, api: self.api, host: host) } }
                var output: [ReleaseMR] = []
                for await result in group { output.append(result) }
                return output
            }
            guard generation == releaseGeneration, !Task.isCancelled else { return }
            for result in results {
                if let index = summary.items.firstIndex(where: { $0.id == result.id }) {
                    if result.mr.targetBranch == branch { summary.items[index] = result }
                    else { summary.items.remove(at: index) }
                }
            }
            releaseSummary = summary
        }
    }
}
