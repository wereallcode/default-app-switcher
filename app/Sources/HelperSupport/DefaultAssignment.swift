import AppKit
import DASCore
import Foundation
import UniformTypeIdentifiers

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        stored = newValue
    }
}

package enum DefaultAssignment {
    private static let foregroundRetryThreshold: TimeInterval = 0.75

    @MainActor
    package static func perform(
        _ targets: [HandlerTarget],
        using appURL: URL,
        startingInForeground: Bool,
        deadline: Date,
        assign: @MainActor (HandlerTarget, URL, Date) -> (NSError?, TimeInterval) = assign,
        activate: @MainActor () -> Void = becomeForeground,
        now: () -> Date = Date.init
    ) -> [HelperResponse.Outcome] {
        var isForeground = startingInForeground
        var outcomes: [HelperResponse.Outcome] = []

        for target in targets {
            guard now() < deadline else {
                outcomes.append(
                    .init(
                        target: target,
                        ok: false,
                        errorCode: 2,
                        errorMessage: "Not attempted. The time limit was reached."
                    ))
                continue
            }
            var (failure, elapsed) = assign(target, appURL, deadline)

            if isCancellation(failure), !isForeground, elapsed < foregroundRetryThreshold,
                now() < deadline
            {
                activate()
                isForeground = true
                (failure, elapsed) = assign(target, appURL, deadline)
            }

            guard let failure else {
                outcomes.append(.init(target: target, ok: true))
                continue
            }
            outcomes.append(
                .init(
                    target: target,
                    ok: false,
                    errorCode: failure.code,
                    errorMessage: describeErrorChain(failure),
                    cancelled: isCancellation(failure)
                ))
        }
        return outcomes
    }

    @MainActor
    package static func becomeForeground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    package static func assign(_ target: HandlerTarget, to appURL: URL, deadline: Date) -> (
        NSError?, TimeInterval
    ) {
        assign(target, to: appURL, deadline: deadline, workspace: SystemWorkspaceAssignment())
    }

    @MainActor
    package static func assign(
        _ target: HandlerTarget, to appURL: URL, deadline: Date,
        workspace: any WorkspaceAssigning,
        now: () -> Date = Date.init,
        pump: (Date) -> Void = { RunLoop.main.run(mode: .default, before: $0) }
    ) -> (NSError?, TimeInterval) {
        let finished = LockedValue(false)
        let failure = LockedValue<NSError?>(nil)
        let started = now()

        let completion: @Sendable (Error?) -> Void = { error in
            failure.set(error as NSError?)
            finished.set(true)
        }

        switch target.kind {
        case .uti:
            guard let type = UTType(target.value) else {
                return (
                    NSError(
                        domain: "das", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown type: \(target.value)."]), 0
                )
            }
            workspace.setDefaultApplication(
                at: appURL, toOpen: type, completion: completion)
        case .scheme:
            workspace.setDefaultApplication(
                at: appURL, toOpenURLsWithScheme: target.value, completion: completion)
        }
        while !finished.value, now() < deadline {
            pump(min(deadline, now().addingTimeInterval(0.05)))
        }

        let elapsed = now().timeIntervalSince(started)
        guard finished.value else {
            let timeout = NSError(
                domain: "das", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "macOS did not respond within \(Int(elapsed)) seconds."
                ])
            return (timeout, elapsed)
        }
        return (failure.value, elapsed)
    }

    private static func isCancellation(_ error: NSError?) -> Bool {
        guard let error else { return false }
        if error.code == kDASUserCancelledCode { return true }
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying?.code == kDASUserCancelledCode
    }

    private static func describeErrorChain(_ error: NSError) -> String {
        var codes = ["\(error.domain) \(error.code)"]
        var current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        while let next = current, codes.count < 3 {
            codes.append("\(next.domain) \(next.code)")
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return "\(error.localizedDescription) (\(codes.joined(separator: " / ")))"
    }
}
