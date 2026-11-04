import Foundation

// A message in the discussion of a shared reminder; a taken back one keeps its place without the words.
public struct SharedComment: Codable, Hashable, Identifiable, Sendable {
    public static let maximumLength = 500

    public var id: String
    public var author: String
    public var text: String?
    public var deleted: Bool
    public var at: Int64
    public var seq: Int64

    public init(id: String, author: String, text: String?, deleted: Bool = false, at: Int64, seq: Int64) {
        self.id = id
        self.author = author
        self.text = text
        self.deleted = deleted
        self.at = at
        self.seq = seq
    }

    enum CodingKeys: String, CodingKey {
        case id, author, text, deleted, at, seq
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = (try? container.decodeIfPresent(String.self, forKey: .author)) ?? ""
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        deleted = (try? container.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false
        at = (try? container.decodeIfPresent(Int64.self, forKey: .at)) ?? 0
        seq = (try? container.decodeIfPresent(Int64.self, forKey: .seq)) ?? 0
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(at) / 1000)
    }
}

public enum Discussion {
    // A newer state of a message replaces the older one; the list keeps the order the messages were written in.
    public static func merge(_ page: [SharedComment], into list: [SharedComment]) -> [SharedComment] {
        var byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for comment in page {
            if let known = byID[comment.id], known.seq > comment.seq {
                continue
            }
            byID[comment.id] = comment
        }
        return byID.values.sorted { $0.at == $1.at ? $0.seq < $1.seq : $0.at < $1.at }
    }

    public static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > SharedComment.maximumLength ? nil : trimmed
    }
}
