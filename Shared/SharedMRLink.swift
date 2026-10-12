import Foundation

enum SharedMRLink {
    // Slack may share a message containing a URL rather than a URL attachment.
    static func extract(from text: String) -> URL? {
        if let location = try? MRLocation.parse(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return location.url
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let url = match.url, let location = try? MRLocation.parse(url.absoluteString) { return location.url }
        }
        return nil
    }
}
