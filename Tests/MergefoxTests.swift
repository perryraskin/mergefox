import XCTest
import WebKit
import SwiftUI
@testable import Mergefox

final class MergefoxTests: XCTestCase {
    func testSharedMessageExtractsMRInsteadOfOtherLinks() {
        let text = "Docs https://example.com — please review https://gitlab.com/company/team/repo/-/merge_requests/37/diffs#note_12"
        XCTAssertEqual(SharedMRLink.extract(from: text)?.absoluteString, "https://gitlab.com/company/team/repo/-/merge_requests/37")
        XCTAssertEqual(SharedMRLink.extract(from: "https://git.example.com:8443/group/repo/-/merge_requests/2")?.host, "git.example.com")
        XCTAssertNil(SharedMRLink.extract(from: "https://gitlab.com/group/repo"))
        XCTAssertNil(SharedMRLink.extract(from: "http://gitlab.com/group/repo/-/merge_requests/1"))
        XCTAssertNil(SharedMRLink.extract(from: "https://user:secret@gitlab.com/group/repo/-/merge_requests/1"))
    }
    func testNestedProjectAndLineFragment() throws {
        let mr = try MRLocation.parse("https://gitlab.com/company/team/repo/-/merge_requests/37/diffs#note_123")
        XCTAssertEqual(mr.project, "company/team/repo")
        XCTAssertEqual(mr.iid, 37)
        XCTAssertEqual(GitLabAPI.path(mr), "projects/company%2Fteam%2Frepo/merge_requests/37")
        XCTAssertEqual(mr.host.absoluteString, "https://gitlab.com")
    }
    func testInvalidLinksDoNotBecomeAPIRequests() {
        for url in ["https://gitlab.com/group/repo", "http://gitlab.com/g/r/-/merge_requests/1", "https://user:secret@gitlab.com/g/r/-/merge_requests/1", "https://gitlab.com/g/r/-/merge_requests/0", "https://gitlab.com/g/r/-/merge_requests/no"] {
            XCTAssertThrowsError(try MRLocation.parse(url))
        }
    }
    func testHostRejectsInsecureAndCredentialedOrigins() throws {
        XCTAssertEqual(try URL.gitlabHost("gitlab.com").absoluteString, "https://gitlab.com")
        XCTAssertEqual(try URL.gitlabHost("https://git.example.com:8443/").absoluteString, "https://git.example.com:8443")
        for host in ["http://gitlab.com", "https://user:pass@gitlab.com", "https://gitlab.com/path", "https://gitlab.com?token=x"] { XCTAssertThrowsError(try URL.gitlabHost(host)) }
    }
    @MainActor func testPKCEAgainstRFCVector() {
        XCTAssertEqual(OAuthSignIn.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    @MainActor func testOAuthRejectsWrongStateAndDuplicateCode() throws {
        let valid = URL(string: "mergepocket://oauth/callback?state=expected&code=good")!
        XCTAssertEqual(try OAuthSignIn.callbackCode(valid, state: "expected"), "good")
        for input in ["mergepocket://oauth/callback?state=wrong&code=good", "mergepocket://oauth/callback?state=expected&code=a&code=b", "mergepocket://open?state=expected&code=good", "mergepocket://oauth/callback?state=expected&error=access_denied"] {
            XCTAssertThrowsError(try OAuthSignIn.callbackCode(URL(string: input)!, state: "expected"))
        }
    }
    func testGitLabMRDecoding() throws {
        let json = #"{"id":3,"iid":2,"project_id":1,"title":"Review","state":"opened","author":{"id":5,"username":"alex","name":"Alex"},"labels":[],"source_branch":"feature","target_branch":"main","web_url":"https://gitlab.com/g/r/-/merge_requests/2","head_pipeline":{"status":"success"}}"#
        let mr = try JSONDecoder.gitlab.decode(MergeRequest.self, from: Data(json.utf8))
        XCTAssertEqual(mr.projectId, 1); XCTAssertEqual(mr.headPipeline?.status, "success")
    }
    func testMergedRequestTimestampDecoding() throws {
        let json = #"{"id":3,"iid":2,"project_id":1,"title":"Merged change","state":"merged","author":{"id":5,"username":"alex","name":"Alex"},"labels":[],"source_branch":"feature","target_branch":"main","web_url":"https://gitlab.com/g/r/-/merge_requests/2","merged_at":"2026-10-09T15:00:00.000Z"}"#
        let mr = try JSONDecoder.gitlab.decode(MergeRequest.self, from: Data(json.utf8))
        XCTAssertEqual(mr.state, "merged")
        XCTAssertEqual(mr.mergedAt, "2026-10-09T15:00:00.000Z")
    }
    func testApprovalConflictIsActionable() {
        let response = HTTPURLResponse(url: URL(string: "https://gitlab.com")!, statusCode: 409, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try GitLabAPI.check(response)) { XCTAssertTrue($0.localizedDescription.contains("Refresh")) }
    }
}


private final class MarkdownTestNavigation: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}

extension MergefoxTests {
    @MainActor func testMixedHTMLMarkdownRenderingAndSanitizing() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let loaded = expectation(description: "Renderer loaded")
        let navigation = MarkdownTestNavigation(loaded)
        web.navigationDelegate = navigation
        web.loadHTMLString(RichMarkdownDocument.html, baseURL: URL(string: "https://gitlab.com"))
        await fulfillment(of: [loaded], timeout: 15)
        let fixture = """
        ## Markdown title
        Body with `createdAt`.

        <h2><a href="https://example.com/?prompt=encoded-long-value">Review summary</a></h2>

        <details><summary>Fix with agent</summary><p>Expanded instructions</p></details>

        <img alt="P2" src="https://example.com/badge.svg" height="20" onerror="window.compromised=true">
        <script>window.compromised=true</script><a href="javascript:alert(1)">Bad link</a>

        | Check | Result |
        | --- | --- |
        | Refresh | Passed |
        """
        let rawResult = try await web.callAsyncJavaScript("""
        window.renderMarkdown(text, false, 17, 'https://gitlab.com');
        const c = document.getElementById('content');
        const closedHeight = c.getBoundingClientRect().height;
        c.querySelector('details').open = true;
        return {
          headings: c.querySelectorAll('h2').length,
          label: c.querySelector('h2 a').textContent,
          url: c.querySelector('h2 a').href,
          table: !!c.querySelector('table'),
          code: c.querySelector('code').textContent,
          safe: !window.compromised && !c.querySelector('script,[onerror],a[href^="javascript:"]'),
          rawTags: c.textContent.includes('<h2>'),
          grows: c.getBoundingClientRect().height > closedHeight,
          color: getComputedStyle(document.body).color
        };
        """, arguments: ["text": fixture], in: nil, contentWorld: .page)
        let result = try XCTUnwrap(rawResult as? [String: Any])
        XCTAssertEqual(result["headings"] as? Int, 2)
        XCTAssertEqual(result["label"] as? String, "Review summary")
        XCTAssertEqual(result["url"] as? String, "https://example.com/?prompt=encoded-long-value")
        XCTAssertEqual(result["code"] as? String, "createdAt")
        for key in ["table", "safe", "grows"] { XCTAssertEqual(result[key] as? Bool, true, key) }
        XCTAssertEqual(result["rawTags"] as? Bool, false)
        XCTAssertEqual(result["color"] as? String, "rgb(24, 23, 29)")
    }
}


extension MergefoxTests {
    @MainActor func testEmbeddedRendererLoadsAndReportsExpandedHeight() async {
        let sized = expectation(description: "Rich content reports its height")
        var measured: CGFloat = 24
        var fulfilled = false
        let coordinator = MarkdownWebView.Coordinator(height: Binding(get: { measured }, set: {
            measured = $0
            if $0 > 80 && !fulfilled { fulfilled = true; sized.fulfill() }
        }))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(coordinator, name: "height")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 24), configuration: configuration)
        coordinator.webView = web
        coordinator.arguments = ["text": "## Description\n\nReadable body text.\n\n- First change\n- Second change", "dark": false, "fontSize": 17, "base": "https://gitlab.com"]
        web.navigationDelegate = coordinator
        web.loadHTMLString(RichMarkdownDocument.html, baseURL: URL(string: "https://gitlab.com"))
        await fulfillment(of: [sized], timeout: 15)
        XCTAssertTrue(coordinator.ready)
        XCTAssertGreaterThan(measured, 80)
        configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }
}

extension MergefoxTests {
    @MainActor func testDiscussionMentionsAndActivityMarkup() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let loaded = expectation(description: "Discussion renderer loaded")
        let navigation = MarkdownTestNavigation(loaded)
        web.navigationDelegate = navigation
        web.loadHTMLString(RichMarkdownDocument.html, baseURL: URL(string: "https://git.example.com"))
        await fulfillment(of: [loaded], timeout: 15)
        let fixture = """
        @greptile re-review pls. Thanks **@alex.smith** and [@existing](https://git.example.com/existing).
        Email perry@example.com, `@literal`, and https://example.com/@path stay unchanged.

        <p>changed title from <code class="idiff"><span class="idiff deletion">old title</span></code> to <code class="idiff"><span class="idiff addition">new title</span></code></p>

        added 1 commit

        <ul><li>5ba7978b - Preserve first license</li></ul>

        [Compare with previous version](/group/repo/-/merge_requests/1/diffs?diff_id=2&start_sha=abc)
        """
        let raw = try await web.callAsyncJavaScript("""
        window.renderMarkdown(text, false, 14, 'https://git.example.com');
        const c = document.getElementById('content');
        return {
          mentions: [...c.querySelectorAll('a.mention')].map(a => a.textContent),
          profile: c.querySelector('a.mention').href,
          weight: getComputedStyle(c.querySelector('a.mention')).fontWeight,
          literal: c.querySelector('code').textContent,
          deleted: c.querySelector('.idiff.deletion').textContent,
          inserted: c.querySelector('.idiff.addition').textContent,
          commit: c.querySelector('li').textContent,
          compare: [...c.querySelectorAll('a')].find(a => a.textContent === 'Compare with previous version').href,
          rawHTML: c.textContent.includes('<ul>') || c.textContent.includes('<span'),
          fontSize: getComputedStyle(document.body).fontSize
        };
        """, arguments: ["text": fixture], in: nil, contentWorld: .page)
        let result = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(result["mentions"] as? [String], ["@greptile", "@alex.smith", "@existing"])
        XCTAssertEqual(result["profile"] as? String, "https://git.example.com/greptile")
        XCTAssertEqual(result["weight"] as? String, "600")
        XCTAssertEqual(result["literal"] as? String, "@literal")
        XCTAssertEqual(result["deleted"] as? String, "old title")
        XCTAssertEqual(result["inserted"] as? String, "new title")
        XCTAssertEqual(result["commit"] as? String, "5ba7978b - Preserve first license")
        XCTAssertEqual(result["compare"] as? String, "https://git.example.com/group/repo/-/merge_requests/1/diffs?diff_id=2&start_sha=abc")
        XCTAssertEqual(result["rawHTML"] as? Bool, false)
        XCTAssertEqual(result["fontSize"] as? String, "14px")
    }
}

extension MergefoxTests {
    @MainActor func testMermaidDiagramsAndCommitLinks() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let loaded = expectation(description: "Diagram renderer loaded")
        let navigation = MarkdownTestNavigation(loaded)
        web.navigationDelegate = navigation
        web.loadHTMLString(RichMarkdownDocument.html, baseURL: URL(string: "https://git.example.com"))
        await fulfillment(of: [loaded], timeout: 15)
        _ = try await web.evaluateJavaScript(RichMarkdownDocument.script("mermaid"))
        let fixture = """
        Fixed in 5ba7978b. `23d818b7` remains code.

        <details open><summary>Diagram</summary>

        ```mermaid
        %%{init: {'theme': 'neutral'}}%%
        flowchart TD
          A[Start transaction] --> B{Write succeeds?}
          B -- Yes --> C[Commit changes]
          B -- No --> D[Roll back]
        ```

        </details>
        """
        let raw = try await web.callAsyncJavaScript("""
        await window.renderMarkdown(text, false, 17, 'https://git.example.com', 'team/subgroup/repo');
        const c = document.getElementById('content'), diagram = c.querySelector('.mermaid-diagram');
        return {
          commit: c.querySelector('a').href,
          code: c.querySelector('code').textContent,
          svg: !!diagram?.querySelector('svg'),
          label: diagram?.textContent.includes('Start transaction'),
          height: diagram?.getBoundingClientRect().height,
          source: !!c.querySelector('code.language-mermaid'),
          safe: !diagram?.querySelector('script,foreignObject,[onclick],a[href]')
        };
        """, arguments: ["text": fixture], in: nil, contentWorld: .page)
        let result = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(result["commit"] as? String, "https://git.example.com/team/subgroup/repo/-/commit/5ba7978b")
        XCTAssertEqual(result["code"] as? String, "23d818b7")
        for key in ["svg", "label", "safe"] { XCTAssertEqual(result[key] as? Bool, true, key) }
        XCTAssertEqual(result["source"] as? Bool, false)
        XCTAssertGreaterThan(result["height"] as? Double ?? 0, 100)
        let fallback = try await web.callAsyncJavaScript("""
        await window.renderMarkdown('```mermaid\\nnot a valid diagram\\n```', true, 17, 'https://git.example.com');
        return document.getElementById('content').textContent;
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertTrue((fallback as? String)?.contains("Couldn’t render this diagram") == true)
        XCTAssertTrue((fallback as? String)?.contains("not a valid diagram") == true)
    }
}

extension MergefoxTests {
    func testRecentlyMergedQueriesAlwaysHavePersonalScope() {
        let authored = RecentlyMergedFeed.query(tab: "authored", userID: 42)
        let reviewed = RecentlyMergedFeed.query(tab: "reviews", userID: 42)
        XCTAssertEqual(authored["author_id"], "42")
        XCTAssertNil(authored["reviewer_id"])
        XCTAssertEqual(reviewed["reviewer_id"], "42")
        XCTAssertNil(reviewed["author_id"])
        for query in [authored, reviewed] {
            XCTAssertEqual(query["state"], "merged")
            XCTAssertEqual(query["order_by"], "merged_at")
            XCTAssertEqual(query["sort"], "desc")
            XCTAssertEqual(query["per_page"], "5")
        }
    }
    func testRecentlyMergedCombinesWithoutDuplicatesAndSortsActualMergeDates() throws {
        func mr(_ id: Int, _ date: String?, state: String = "merged") throws -> MergeRequest {
            var fixture: [String: Any] = ["id": id, "iid": id, "project_id": 1, "title": "Change", "state": state,
                "author": ["id": 42, "username": "alex", "name": "Alex"], "labels": [], "source_branch": "feature",
                "target_branch": "main", "web_url": "https://gitlab.com/g/r/-/merge_requests/\(id)"]
            fixture["merged_at"] = date
            return try JSONDecoder.gitlab.decode(MergeRequest.self, from: JSONSerialization.data(withJSONObject: fixture))
        }
        let older = try mr(1, "2026-10-09T14:00:00.000Z")
        let newest = try mr(2, "2026-10-09T11:00:00-04:00")
        let undated = try mr(3, nil)
        let opened = try mr(4, nil, state: "opened")
        XCTAssertEqual(RecentlyMergedFeed.combine([older, newest], [newest, undated, opened]).map(\.id), [2, 1, 3])
        let many = try (1...30).map { try mr($0, "2026-10-09T15:00:00Z") }
        let capped = RecentlyMergedFeed.combine(Array(many.prefix(20)), Array(many.suffix(20)))
        XCTAssertEqual(capped.count, 30)
        XCTAssertEqual(capped.map(\.id), Array((1...30).reversed()))
        XCTAssertEqual(HomePagination.items(capped, page: 1).map(\.id), [30, 29, 28, 27, 26])
        XCTAssertEqual(HomePagination.items(capped, page: 2).map(\.id), [25, 24, 23, 22, 21])
        XCTAssertEqual(HomePagination.items(capped, page: 6).map(\.id), [5, 4, 3, 2, 1])
        XCTAssertFalse(HomePagination.hasNext(count: 30, page: 6))
        XCTAssertTrue(HomePagination.hasNext(count: 30, page: 5))
    }
    func testInboxFiltersKeepPersonalScopeAndApplyAPIParameters() {
        var filters = MRInboxFilters()
        XCTAssertEqual(filters.activeCount(tab: "reviews"), 0)
        XCTAssertEqual(filters.query(tab: "reviews", userID: 42)["reviewer_id"], "42")
        filters.status = "merged"
        filters.targetBranch = " main "
        filters.author = " @alex "
        filters.labels = "backend,bug"
        filters.search = " license rollback "
        let review = filters.query(tab: "reviews", userID: 42)
        XCTAssertEqual(review["state"], "merged")
        XCTAssertEqual(review["order_by"], "merged_at")
        XCTAssertEqual(review["target_branch"], "main")
        XCTAssertEqual(review["author_username"], "alex")
        XCTAssertEqual(review["search"], "license rollback")
        XCTAssertEqual(review["labels"], "backend,bug")
        XCTAssertEqual(filters.activeCount(tab: "reviews"), 5)
        let authored = filters.query(tab: "authored", userID: 42)
        XCTAssertEqual(authored["author_id"], "42")
        XCTAssertNil(authored["reviewer_id"])
        XCTAssertNil(authored["author_username"])
        XCTAssertEqual(filters.activeCount(tab: "authored"), 4)
    }
}
