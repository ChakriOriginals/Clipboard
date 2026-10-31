public enum KindFilter: String, CaseIterable, Sendable {
    case all, pinned, text, urls, code, images, files
}

public enum DateFilter: String, CaseIterable, Sendable {
    case any, today, last7Days, last30Days
}

public struct SearchQuery: Equatable, Sendable {
    public var text: String
    public var kind: KindFilter
    public var date: DateFilter

    public init(text: String = "", kind: KindFilter = .all, date: DateFilter = .any) {
        self.text = text
        self.kind = kind
        self.date = date
    }
}
