import Foundation

package struct PickerState {
    package enum Effect: Equatable {
        case none, refresh, quit
        case select(String)
    }

    private let isTopLevel: Bool
    private var rows: [Row]
    package private(set) var selected: Int
    package private(set) var search = ""
    package private(set) var searching = false
    package private(set) var returning = false

    package init(rows: [Row], selected: Int = 0, isTopLevel: Bool = false) {
        self.rows = rows
        self.isTopLevel = isTopLevel
        self.selected = min(max(0, selected), max(0, rows.count - 1))
    }

    package var shown: [Row] {
        let needle = search.lowercased()
        guard !needle.isEmpty else { return rows }
        let matches = rows.filter { $0.searchText.contains(needle) }
        return matches.filter { $0.label.lowercased().contains(needle) }
            + matches.filter { !$0.label.lowercased().contains(needle) }
    }

    package mutating func refresh(rows: [Row]) {
        let previous = shown
        let id = previous.indices.contains(selected) ? previous[selected].id : nil
        self.rows = rows
        selected = shown.firstIndex { $0.id == id } ?? min(selected, max(0, shown.count - 1))
    }

    package mutating func reduce(event: Key) -> Effect {
        if isTopLevel {
            switch event {
            case .back, .quit: return .quit
            case .up, .down, .enter: break
            default: return .none
            }
        }
        let count = shown.count
        defer { selected = min(selected, max(0, shown.count - 1)) }
        switch event {
        case .up: selected = count == 0 ? 0 : (selected + count - 1) % count
        case .down: selected = count == 0 ? 0 : (selected + 1) % count
        case .refresh: return .refresh
        case .search: searching = true
        case .character(let character):
            if searching { search.append(character) }
        case .backspace:
            if searching, !search.isEmpty { search.removeLast() }
        case .back:
            if searching || !search.isEmpty {
                searching = false
                search = ""
            } else {
                returning = true
            }
        case .enter:
            if searching {
                searching = false
            } else if count > 0 {
                return .select(shown[selected].id)
            }
        case .quit: return .quit
        case .other: break
        }
        return .none
    }
}
