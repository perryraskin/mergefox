import Foundation

enum RecentlyMergedFeed {
    static func query(tab: String, userID: Int) -> [String: String] {
        var filters = MRInboxFilters()
        filters.status = "merged"
        var query = filters.query(tab: tab, userID: userID)
        query["per_page"] = "5"
        return query
    }

    static func combine(_ authored: [MergeRequest], _ reviewed: [MergeRequest]) -> [MergeRequest] {
        var seen = Set<Int>()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func mergedDate(_ mr: MergeRequest) -> Date {
            guard let value = mr.mergedAt else { return .distantPast }
            return fractional.date(from: value) ?? plain.date(from: value) ?? .distantPast
        }
        return Array((authored + reviewed)
            .filter { $0.state == "merged" && seen.insert($0.id).inserted }
            .sorted {
                let left = mergedDate($0), right = mergedDate($1)
                return left == right ? $0.id > $1.id : left > right
            })
    }
}

struct MRFeedBuffer {
    var items: [MergeRequest] = []
    var nextPage = 1
    var hasMore = true

    func filling(upTo count: Int, api: GitLabAPI, host: URL, query: [String: String]) async throws -> MRFeedBuffer {
        var buffer = self
        while buffer.items.count < count && buffer.hasMore {
            try Task.checkCancellation()
            let result = try await api.page(MergeRequest.self, host: host, path: "merge_requests", query: query, page: buffer.nextPage)
            buffer.items += result.items
            buffer.nextPage += 1
            buffer.hasMore = result.hasNext && !result.items.isEmpty
        }
        return buffer
    }
}

enum HomePagination {
    static let pageSize = 5
    static func items<T>(_ values: [T], page: Int) -> [T] {
        Array(values.dropFirst((max(1, page) - 1) * pageSize).prefix(pageSize))
    }
    static func hasNext(count: Int, page: Int) -> Bool { count > max(1, page) * pageSize }
}
