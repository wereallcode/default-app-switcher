import DASCore
import Foundation

enum Picker {
    private static let exitID = "exit"

    static func run(_ runtime: Runtime) throws -> Int32 {
        RawTerminal.enterRawMode()
        defer { RawTerminal.restore() }
        return try chooseCategory(runtime)
    }

    private static func chooseCategory(_ runtime: Runtime) throws -> Int32 {
        let style = runtime.style
        var state = PickerState(rows: [], isTopLevel: true)
        var message: String?
        var statuses: [String: CategoryStatus] = [:]

        func status(of category: AppCategory) -> CategoryStatus {
            if let known = statuses[category.id] { return known }
            let built = runtime.status(of: category)
            statuses[category.id] = built
            return built
        }

        while true {
            let rows = CategoryCatalog.all.map { category in
                let current = status(of: category)
                return Row(
                    label: category.name,
                    value: current.primaryApp?.name ?? style.dim("None"),
                    trailing: current.isMixed ? style.yellow("Mixed") : "",
                    id: category.id
                )
            }
            var shown = rows
            shown.append(Row(label: style.dim("Exit"), id: exitID))
            state.refresh(rows: shown)

            draw(
                Frame(
                    title: "das  \(style.dim("· Default App Switcher"))",
                    subtitle: AppMetadata.description,
                    isTopLevel: true,
                    rows: shown,
                    selected: state.selected,
                    search: "",
                    searching: false,
                    status: message
                ), style: style)

            let key = RawTerminal.readKey(searching: false)
            if key == .up || key == .down { message = nil }
            switch state.reduce(event: key) {
            case .select(let id):
                if id == exitID { return 0 }
                guard let category = CategoryCatalog.builtin(id: id) else { break }
                switch try chooseAppFor(category, runtime: runtime, status: status(of: category)) {
                case .assigned(let outcome):
                    statuses.removeValue(forKey: category.id)
                    message = outcome
                case .back:
                    statuses.removeValue(forKey: category.id)
                case .quit:
                    return 0
                }
            case .quit:
                return 0
            case .none, .refresh:
                break
            }
        }
    }

    private enum AppPick {
        case assigned(String)
        case back
        case quit
    }

    private static func chooseAppFor(
        _ category: AppCategory,
        runtime: Runtime,
        status initial: CategoryStatus
    ) throws -> AppPick {
        let style = runtime.style
        var status = initial
        var state = PickerState(
            rows: appRows(for: status, style: style),
            selected: status.apps.firstIndex { $0.ownsPrimary } ?? 0)
        var feedback = ShortcutFeedback()

        while true {
            let timeout = feedback.remainingMilliseconds()
            draw(
                Frame(
                    title: "das \(style.dim("›")) \(category.name)",
                    subtitle: "\(category.summary).",
                    rows: state.shown,
                    selected: state.selected,
                    search: state.search,
                    searching: state.searching,
                    status: nil,
                    pressedShortcut: feedback.key
                ), style: style)

            if state.returning {
                if let timeout {
                    Thread.sleep(forTimeInterval: Double(timeout) / 1000)
                }
                return .back
            }

            let key = RawTerminal.readKey(
                searching: state.searching, timeoutMilliseconds: timeout)
            if key == .search || key == .refresh || key == .back { feedback.press(key) }
            switch state.reduce(event: key) {
            case .none: break
            case .refresh:
                status = runtime.status(of: category)
                state.refresh(rows: appRows(for: status, style: style))
            case .select(let id):
                guard let chosen = status.apps.first(where: { $0.app.bundleIdentifier == id })
                else { continue }
                return .assigned(
                    makeDefault(
                        chosen.app, in: category, status: &status, runtime: runtime,
                        rows: state.shown, selected: state.selected, search: state.search))
            case .quit: return .quit
            }
        }
    }

    private static func makeDefault(
        _ app: AppInfo,
        in category: AppCategory,
        status: inout CategoryStatus,
        runtime: Runtime,
        rows: [Row],
        selected: Int,
        search: String
    ) -> String {
        let style = runtime.style

        func waitingFrame(_ message: String) {
            draw(
                Frame(
                    title: "das \(style.dim("›")) \(category.name)",
                    rows: rows, selected: selected,
                    search: search, searching: false,
                    status: message
                ), style: style)
        }

        let targets = status.supportedTargets(for: app)
        waitingFrame(
            style.dim(
                "Setting \(app.name) as the default for \(AppStatusText.description(of: targets)).")
        )

        do {
            let (response, skipped) = try runtime.performAssignment(
                status: status, app: app,
                onSlow: {
                    waitingFrame(
                        style.yellow("Check for a macOS confirmation dialog."))
                }
            )
            status = runtime.status(of: category)

            return AppStatusText.assignmentResult(
                app: app, response: response, skipped: skipped, style: style)
        } catch let error as DASError {
            let firstLine =
                stripANSI(error.description).split(separator: "\n").first.map(String.init)
                ?? "Assignment failed."
            return style.red("✗ ") + firstLine
        } catch {
            return style.red("✗ ") + error.localizedDescription
        }
    }

    private static func draw(_ frame: Frame, style: Style) {
        let (height, width) = RawTerminal.size
        RawTerminal.emit(Screen.render(frame, style: style, height: height, width: width))
    }

    private static func appRows(for status: CategoryStatus, style: Style) -> [Row] {
        status.apps.map { app in
            Row(
                marker: AppStatusText.marker(app, style: style),
                label: app.app.name,
                value: AppStatusText.summary(app, total: status.targets.count, style: style),
                compactValue: AppStatusText.compactSummary(app, style: style),
                id: app.app.bundleIdentifier
            )
        }
    }

}
