import XCTest
@testable import Mergefox

final class ReleaseMetricsTests: XCTestCase {
    private func mr(_ id: Int, target: String = "release/2026-10-09", source: String = "perryraskin/web-3489-title", state: String = "opened", created: String = "2026-10-08T10:00:00Z") throws -> MergeRequest {
        let fixture: [String: Any] = ["id": id, "iid": id, "project_id": 1, "title": "Feature \(id)", "state": state,
            "author": ["id": 42, "username": "perryraskin", "name": "Perry"], "labels": [], "source_branch": source,
            "target_branch": target, "web_url": "https://gitlab.com/team/app/-/merge_requests/\(id)",
            "created_at": created, "updated_at": "2026-10-09T10:00:00Z"]
        return try JSONDecoder.gitlab.decode(MergeRequest.self, from: JSONSerialization.data(withJSONObject: fixture))
    }
    func testReadinessRequiresVerifiedApprovalAndPassingChecks() throws {
        var change = try mr(1)
        change.detailedMergeStatus = "mergeable"
        change.headPipeline = Pipeline(status: "success")
        var item = ReleaseMR(mr: change)
        XCTAssertFalse(item.ready)
        item.verified = true
        XCTAssertFalse(item.ready)
        item.approved = false
        XCTAssertFalse(item.ready)
        item.approved = true
        XCTAssertTrue(item.ready)
        item.mr.draft = true
        XCTAssertFalse(item.ready)
        item.mr.draft = false
        item.mr.hasConflicts = true
        XCTAssertFalse(item.ready)
        XCTAssertTrue(item.needsAttention)
        item.mr.hasConflicts = false
        item.mr.headPipeline = Pipeline(status: "running")
        item.mr.detailedMergeStatus = "ci_must_pass"
        XCTAssertFalse(item.ready)
        XCTAssertFalse(item.needsAttention)
        item.mr.headPipeline = Pipeline(status: "failed")
        XCTAssertTrue(item.needsAttention)
        item.mr.headPipeline = Pipeline(status: "success")
        item.mr.detailedMergeStatus = "mergeable"
        item.mr.blockingDiscussionsResolved = false
        XCTAssertTrue(item.needsAttention)
        XCTAssertFalse(item.ready)
    }
    func testSummaryCountsAndOldestUseStateAndCreationDate() throws {
        var ready = try mr(1)
        ready.detailedMergeStatus = "mergeable"
        let oldest = try mr(2, created: "2026-09-01T10:00:00.000Z")
        var blocked = try mr(3)
        blocked.hasConflicts = true
        let merged = try mr(4, state: "merged")
        let closed = try mr(5, state: "closed", created: "2020-01-01T00:00:00Z")
        let summary = ReleaseSummary(items: [ReleaseMR(mr: ready, verified: true, approved: true), ReleaseMR(mr: oldest), ReleaseMR(mr: blocked), ReleaseMR(mr: merged), ReleaseMR(mr: closed)])
        XCTAssertEqual(summary.matching(.open).count, 3)
        XCTAssertEqual(summary.matching(.ready).count, 1)
        XCTAssertEqual(summary.matching(.attention).count, 1)
        XCTAssertEqual(summary.matching(.merged).count, 1)
        XCTAssertEqual(summary.oldest?.id, 2)
        XCTAssertEqual(summary.unknownCount, 2)
        XCTAssertEqual(ready.sourceBranch, "perryraskin/web-3489-title")
    }
    func testReleaseBranchesUseExactPrefixAndMostRecentCommit() throws {
        let data = Data(#"[{"name":"release/old","commit":{"committed_date":"2026-01-01T00:00:00Z"}},{"name":"feature/release/not-a-cycle"},{"name":"release/new","commit":{"committed_date":"2026-10-09T10:00:00-04:00"}},{"name":"release/newer","commit":{"committed_date":"2026-10-09T15:00:00.000Z"}}]"#.utf8)
        let branches = try JSONDecoder.gitlab.decode([ReleaseBranch].self, from: data)
        XCTAssertEqual(ReleaseMetrics.sortedBranches(branches).map(\.name), ["release/newer", "release/new", "release/old"])
    }
    func testProjectDiscoveryDeduplicatesAndRejectsOtherHosts() throws {
        var a = try mr(1), b = try mr(2)
        b.webUrl = "https://other.example.com/team/app/-/merge_requests/2"
        a.updatedAt = "2026-10-09T00:00:00Z"
        let projects = ReleaseMetrics.projects(from: [a, a, b], recent: [], host: URL(string: "https://gitlab.com")!)
        XCTAssertEqual(projects, [ReleaseProject(id: 1, path: "team/app")])
    }
    func testReleaseGroupingUsesTargetNotSourceAndPersonalDiscovery() throws {
        let feature = try mr(1)
        let releaseOut = try mr(2, target: "main", source: "release/2026-10-09")
        let otherRelease = try mr(3, target: "release/old")
        let summary = ReleaseMetrics.summary(target: "release/2026-10-09", mrs: [feature, feature, releaseOut, otherRelease])
        XCTAssertEqual(summary.items.map(\.id), [1])
        XCTAssertEqual(ReleaseMetrics.discoveryQuery(tab: "authored", userID: 42)["author_id"], "42")
        XCTAssertEqual(ReleaseMetrics.discoveryQuery(tab: "reviews", userID: 42)["reviewer_id"], "42")
    }
    func testApprovalRequirementFlagDecodes() throws {
        let approved = try JSONDecoder.gitlab.decode(ApprovalState.self, from: Data(#"{"approved_by":[],"approved":true,"approvals_left":0}"#.utf8))
        XCTAssertEqual(approved.approved, true)
    }
}
