import Foundation

struct MRInboxFilters: Equatable {
    var status = "opened"
    var targetBranch = ""
    var author = ""
    var labels = ""
    var search = ""

    func activeCount(tab: String) -> Int {
        (status == "opened" ? 0 : 1) + [targetBranch, labels, search, tab == "reviews" ? author : ""].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    func query(tab: String, userID: Int) -> [String: String] {
        var result = ["state": status, "scope": "all", "order_by": status == "merged" ? "merged_at" : "updated_at", "sort": "desc", "per_page": "5"]
        result[tab == "reviews" ? "reviewer_id" : "author_id"] = String(userID)
        let fields = ["target_branch": targetBranch, "labels": labels, "search": search, "author_username": tab == "reviews" ? author : ""]
        for (key, value) in fields {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result[key] = key == "author_username" && trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed }
        }
        return result
    }
}
