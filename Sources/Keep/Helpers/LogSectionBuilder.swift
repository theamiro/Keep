import Foundation

struct LogSection {
    let title: String
    let logs: [Log]
}

enum LogSectionBuilder {
    static func makeSections(from logs: [Log]) -> [LogSection] {
        guard !logs.isEmpty else { return [] }

        let pinnedLogs = logs.filter { $0.pinned }
        let unpinnedLogs = logs.filter { !$0.pinned }

        var sections: [LogSection] = []

        if !pinnedLogs.isEmpty {
            sections.append(LogSection(title: "Pinned", logs: pinnedLogs))
        }

        let allSectionLogs = pinnedLogs.isEmpty ? logs : unpinnedLogs

        if !allSectionLogs.isEmpty {
            sections.append(LogSection(title: "All", logs: allSectionLogs))
        }

        return sections
    }
}
