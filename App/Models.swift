import Foundation

struct MRLocation: Equatable, Hashable {
    let host: URL
    let project: String
    let iid: Int
    var url: URL { host.appendingPathComponent(project + "/-/merge_requests/\(iid)") }
    static func parse(_ input: String) throws -> Self {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              let range = url.path.range(of: "/-/merge_requests/") else {
            throw AppError.message("Paste a GitLab merge request URL, such as https://gitlab.com/group/project/-/merge_requests/123.")
        }
        let project = String(url.path[..<range.lowerBound]) .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let tail = String(url.path[range.upperBound...]).split(separator: "/")
        guard project.split(separator: "/").count >= 2, let first = tail.first, let iid = Int(first), iid > 0,
              !project.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
            throw AppError.message("This URL doesn’t identify a merge request.")
        }
        var origin = URLComponents(); origin.scheme = "https"; origin.host = url.host; origin.port = url.port
        return Self(host: origin.url!, project: project, iid: iid)
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct Person: Codable, Identifiable {
    let id: Int
    let name: String
    let username: String
    var avatarUrl: String?
}
struct Pipeline: Codable { let status: String; var webUrl: String? }
struct MergeRequest: Codable, Identifiable {
    let id: Int
    let iid: Int
    let projectId: Int
    var title: String
    var description: String?
    var state: String
    var author: Person
    var reviewers: [Person]?
    var assignees: [Person]?
    var labels: [String]
    var sourceBranch: String
    var targetBranch: String
    var sha: String?
    var webUrl: String
    var draft: Bool?
    var detailedMergeStatus: String?
    var headPipeline: Pipeline?
    var changesCount: String?
    var updatedAt: String?
    var mergedAt: String?
    var createdAt: String?
    var hasConflicts: Bool?
    var blockingDiscussionsResolved: Bool?
    var userNotesCount: Int?
}
struct FileDiff: Codable, Identifiable {
    var oldPath: String
    var newPath: String
    var diff: String
    var newFile: Bool?
    var renamedFile: Bool?
    var deletedFile: Bool?
    var collapsed: Bool?
    var tooLarge: Bool?
    var id: String { oldPath + "→" + newPath }
    var patch: String { "diff --git a/\(oldPath) b/\(newPath)\n--- a/\(oldPath)\n+++ b/\(newPath)\n" + diff }
}
struct DiffPosition: Codable {
    var oldPath: String?
    var newPath: String?
    var oldLine: Int?
    var newLine: Int?
    var headSha: String?
}
struct Note: Codable, Identifiable {
    let id: Int
    let author: Person
    let body: String
    var createdAt: String?
    var system: Bool?
    var resolvable: Bool?
    var resolved: Bool?
    var position: DiffPosition?
}
struct Discussion: Codable, Identifiable {
    let id: String
    var individualNote: Bool?
    var notes: [Note]
    var isResolved: Bool { notes.first?.resolved == true }
    var isResolvable: Bool { notes.first?.resolvable == true }
}
struct ApprovalUser: Codable { let user: Person }
struct ApprovalState: Codable {
    var approvedBy: [ApprovalUser]
    var approved: Bool?
    var approvalsRequired: Int?
    var approvalsLeft: Int?
}
struct Credential: Codable {
    let host: URL
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var clientID: String?
    var isOAuth: Bool { refreshToken != nil }
}
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let createdAt: Double?
    func credential(host: URL, clientID: String) -> Credential {
        Credential(host: host, accessToken: accessToken, refreshToken: refreshToken,
                   expiresAt: Date(timeIntervalSince1970: createdAt ?? Date().timeIntervalSince1970).addingTimeInterval(expiresIn), clientID: clientID)
    }
}
struct EmptyResponse: Decodable {}

extension JSONDecoder {
    static var gitlab: JSONDecoder { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }
}
extension URL {
    static func gitlabHost(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: text.contains("://") ? text : "https://" + text),
              c.scheme == "https", c.host != nil, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/", let url = c.url else {
            throw AppError.message("Enter an HTTPS GitLab host without a path, such as https://gitlab.com.")
        }
        var origin = c; origin.path = ""; return origin.url ?? url
    }
}
