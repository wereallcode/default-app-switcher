import DASCore

package enum AppStatusText {
    static func marker(_ status: AppStatus, style: Style) -> String {
        switch status.state {
        case .complete: return style.isTerminal ? style.green("✓") : "Default"
        case .partial: return style.isTerminal ? style.yellow("◐") : "Partial"
        case .none: return " "
        }
    }

    package static func summary(_ status: AppStatus, total: Int, style: Style) -> String {
        switch status.state {
        case .complete, .partial:
            return style.dim("Default for \(description(of: status.activeTargets)).")
        case .none:
            guard status.supportedTargets.count < total else { return "" }
            return style.dim("Can open \(description(of: status.supportedTargets)) only.")
        }
    }

    static func compactSummary(_ status: AppStatus, style: Style) -> String {
        switch status.state {
        case .complete: return style.dim("Default.")
        case .partial: return style.dim("Default for some types.")
        case .none: return style.dim("Limited support.")
        }
    }

    package static func assignmentResult(
        app: AppInfo, response: HelperResponse, skipped: [HandlerTarget], style: Style
    ) -> String {
        var messages: [String] = []
        if response.wasCancelled { messages.append("Cancelled.") }
        if !response.succeeded.isEmpty {
            messages.append(
                "\(app.name) is now the default for \(description(of: response.succeeded.map(\.target)))."
            )
        }
        if !response.failed.isEmpty {
            let targets = description(of: response.failed.map(\.target))
            messages.append(
                response.wasCancelled
                    ? "The default for \(targets) was not changed."
                    : "Could not set \(app.name) as the default for \(targets).")
        }
        if response.outcomes.isEmpty { messages.append("No defaults were changed.") }
        if !skipped.isEmpty {
            messages.append(
                "The default for \(description(of: skipped)) was kept because \(app.name) cannot open them."
            )
        }
        let message = messages.joined(separator: " ")
        if response.wasCancelled { return style.yellow(message) }
        if !response.failed.isEmpty {
            return response.succeeded.isEmpty
                ? style.red("✗ " + message) : style.yellow("◐ " + message)
        }
        return response.succeeded.isEmpty ? style.yellow(message) : style.green("✓ " + message)
    }

    static func description(of targets: [HandlerTarget]) -> String {
        let names = CategoryCatalog.displayNames(for: targets)
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
