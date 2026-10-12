import Foundation

struct ReleaseProject: Identifiable, Equatable {
    let id: Int
    let path: String
}

struct ReleaseBranch: Decodable, Identifiable {
    struct Commit: Decodable { var committedDate: String? }
    let name: String
    var commit: Commit?
    var id: String { name }
}

enum ReleaseMetric: String, CaseIterable, Identifiable {
    case open, ready, attention, merged
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: return "Open MRs"
        case .ready: return "Ready to merge"
        case .attention: return "Needs attention"
        case .merged: return "Merged"
        }
    }
    var symbol: String {
        switch self {
        case .open: return "arrow.triangle.pull"
        case .ready: return "checkmark.circle"
        case .attention: return "exclamationmark.triangle"
        case .merged: return "arrow.triangle.merge"
        }
    }
}

struct ReleaseMR: Identifiable {
    var mr: MergeRequest
    var verified = false
    var approved: Bool?
    var id: Int { mr.id }
    var needsAttention: Bool {
        guard mr.state == "opened" else { return false }
        return mr.hasConflicts == true || mr.blockingDiscussionsResolved == false
            || ["failed", "canceled"].contains(mr.headPipeline?.status ?? "")
            || ["conflict", "discussions_not_resolved", "ci_failed", "security_policy_violations"].contains(mr.detailedMergeStatus ?? "")
            || (mr.detailedMergeStatus == "ci_must_pass" && mr.headPipeline == nil)
    }
    var ready: Bool {
        verified && approved == true && mr.state == "opened" && mr.draft != true
            && mr.detailedMergeStatus == "mergeable" && !needsAttention
            && (mr.headPipeline == nil || mr.headPipeline?.status == "success" || mr.headPipeline?.status == "skipped")
    }
    var statusUnknown: Bool { mr.state == "opened" && (!verified || approved == nil || [nil, "checking", "unchecked", "approvals_syncing"].contains(mr.detailedMergeStatus)) }
}

struct ReleaseSummary {
    var items: [ReleaseMR] = []
    var truncated = false
    func matching(_ metric: ReleaseMetric) -> [ReleaseMR] {
        items.filter {
            switch metric {
            case .open: return $0.mr.state == "opened"
            case .ready: return $0.ready
            case .attention: return $0.needsAttention
            case .merged: return $0.mr.state == "merged"
            }
        }
    }
    var unknownCount: Int { items.filter(\.statusUnknown).count }
    var oldest: ReleaseMR? {
        matching(.open).filter { ReleaseMetrics.date($0.mr.createdAt) != nil }
            .min { ReleaseMetrics.date($0.mr.createdAt)! < ReleaseMetrics.date($1.mr.createdAt)! }
    }
}

enum ReleaseMetrics {
    static func discoveryQuery(tab: String, userID: Int) -> [String: String] {
        var query = MRInboxFilters().query(tab: tab, userID: userID)
        query["state"] = "all"; query["per_page"] = "100"
        return query
    }
    static func summary(target: String, mrs: [MergeRequest]) -> ReleaseSummary {
        var seen = Set<Int>()
        return ReleaseSummary(items: mrs.filter { $0.targetBranch == target && seen.insert($0.id).inserted }.map { ReleaseMR(mr: $0) }, truncated: mrs.count >= 1000)
    }
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func projects(from mrs: [MergeRequest], recent: [String], host: URL) -> [ReleaseProject] {
        var projects: [ReleaseProject] = [], seen = Set<Int>()
        let recentPaths = recent.compactMap { try? MRLocation.parse($0) }.filter { $0.host == host }.map(\.project)
        let ordered = mrs.sorted {
            let left = (try? MRLocation.parse($0.webUrl).project).flatMap { recentPaths.firstIndex(of: $0) } ?? Int.max
            let right = (try? MRLocation.parse($1.webUrl).project).flatMap { recentPaths.firstIndex(of: $0) } ?? Int.max
            if left != right { return left < right }
            return (date($0.updatedAt) ?? .distantPast) > (date($1.updatedAt) ?? .distantPast)
        }
        for mr in ordered {
            guard let location = try? MRLocation.parse(mr.webUrl), location.host == host, seen.insert(mr.projectId).inserted else { continue }
            projects.append(ReleaseProject(id: mr.projectId, path: location.project))
        }
        return projects
    }
    static func sortedBranches(_ branches: [ReleaseBranch]) -> [ReleaseBranch] {
        branches.filter { $0.name.hasPrefix("release/") }.sorted {
            let left = date($0.commit?.committedDate) ?? .distantPast
            let right = date($1.commit?.committedDate) ?? .distantPast
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedDescending : left > right
        }
    }
    static func hydrate(_ mr: MergeRequest, api: GitLabAPI, host: URL) async -> ReleaseMR {
        let base = "projects/\(mr.projectId)/merge_requests/\(mr.iid)"
        // Preserve a row when an endpoint is unavailable; it cannot count as ready.
        async let detail = try? api.request(MergeRequest.self, host: host, path: base)
        async let approval = try? api.request(ApprovalState.self, host: host, path: base + "/approvals")
        let values = await (detail, approval)
        return ReleaseMR(mr: values.0 ?? mr, verified: values.0 != nil, approved: values.1?.approved)
    }
}
