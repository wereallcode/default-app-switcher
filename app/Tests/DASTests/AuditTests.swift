import DASCLI
import DASCore
import DASHelperSupport
import Foundation

@MainActor
func runAuditTests(_ t: TestRunner) {
    t.suite("picker-state") { t in
        let rows = [
            Row(label: "Beta", id: "a.alpha"),
            Row(label: "Alpha", id: "b"),
            Row(label: "Gamma", id: "c"),
        ]
        var state = PickerState(rows: rows, selected: 1)
        t.equal(state.reduce(event: .enter), .select("b"), "initial owner is selected")
        _ = state.reduce(event: .up)
        _ = state.reduce(event: .up)
        t.equal(state.selected, 2, "up wraps")
        _ = state.reduce(event: .down)
        t.equal(state.selected, 0, "down wraps")
        _ = state.reduce(event: .search)
        for character in "alpha" { _ = state.reduce(event: .character(character)) }
        t.equal(state.shown.count, 2, "search includes name and identifier matches")
        t.equal(state.reduce(event: .enter), .none, "enter ends editing without assigning")
        t.equal(state.reduce(event: .enter), .select("b"), "enter assigns filtered selection")
        t.equal(state.reduce(event: .refresh), .refresh, "refresh requests a new snapshot")
        state.refresh(rows: Array(rows.reversed()))
        t.equal(state.reduce(event: .enter), .select("b"), "refresh preserves selected identity")
        _ = state.reduce(event: .back)
        t.equal(state.search, "", "back clears an applied filter")
        t.expect(!state.returning, "clearing a filter does not leave")
        _ = state.reduce(event: .search)
        _ = state.reduce(event: .character("z"))
        t.equal(state.shown.count, 0, "unknown search has no matches")
        _ = state.reduce(event: .down)
        t.equal(state.selected, 0, "empty results keep a valid selection")
        _ = state.reduce(event: .backspace)
        t.equal(state.shown.count, 3, "backspace restores results")
        _ = state.reduce(event: .back)
        t.expect(!state.searching && !state.returning, "back exits search first")
        state.refresh(rows: [])
        t.equal(state.reduce(event: .enter), .none, "empty snapshot cannot assign")
        _ = state.reduce(event: .back)
        t.expect(state.returning, "back leaves an unfiltered picker")
        t.equal(state.reduce(event: .quit), .quit, "quit exits directly")
    }

    t.suite("assignment-retry") { t in
        let target = HandlerTarget.uti("public.html")
        let app = URL(fileURLWithPath: "/unused.app")
        let now = Date(timeIntervalSince1970: 100)
        let cancellation = NSError(domain: NSOSStatusErrorDomain, code: -128)
        let wrapped = NSError(
            domain: "outer", code: 42, userInfo: [NSUnderlyingErrorKey: cancellation])
        for (error, elapsed, foreground, expectedCalls) in [
            (cancellation, 0.1, false, 2),
            (wrapped, 0.1, false, 2),
            (cancellation, 0.75, false, 1),
            (cancellation, 0.1, true, 1),
            (NSError(domain: "test", code: 1), 0.1, false, 1),
        ] {
            var calls = 0
            var activations = 0
            let outcomes = DefaultAssignment.perform(
                [target], using: app, startingInForeground: foreground,
                deadline: now.addingTimeInterval(10),
                assign: { _, _, _ in
                    calls += 1
                    return (calls == 1 ? error : nil, elapsed)
                }, activate: { activations += 1 }, now: { now })
            t.equal(calls, expectedCalls, "retry respects cancellation, time and foreground")
            t.equal(activations, expectedCalls - 1, "activate only for a retry")
            t.equal(outcomes.first?.ok, expectedCalls == 2, "retry result is reported")
        }
        var calls = 0
        let cancelled = DefaultAssignment.perform(
            [target, target], using: app, startingInForeground: false,
            deadline: now.addingTimeInterval(10),
            assign: { _, _, _ in
                calls += 1
                return (wrapped, 0.1)
            },
            activate: {}, now: { now })
        t.equal(calls, 3, "foreground retry happens only once across targets")
        t.expect(cancelled.allSatisfy { $0.cancelled == true }, "nested cancellation is reported")
        t.expect(
            cancelled[0].errorMessage?.contains("outer 42 / NSOSStatusErrorDomain -128") == true,
            "error chain is retained")
        calls = 0
        let expired = DefaultAssignment.perform(
            [target], using: app, startingInForeground: false, deadline: now,
            assign: { _, _, _ in
                calls += 1
                return (nil, 0)
            },
            activate: { calls += 1 }, now: { now })
        t.equal(calls, 0, "expired deadline never invokes platform operations")
        t.equal(expired.first?.errorCode, 2, "deadline is reported")
        var clock = now
        calls = 0
        _ = DefaultAssignment.perform(
            [target], using: app, startingInForeground: false,
            deadline: now.addingTimeInterval(1),
            assign: { _, _, _ in
                calls += 1
                clock = now.addingTimeInterval(2)
                return (cancellation, 0.1)
            },
            activate: { calls += 1 }, now: { clock })
        t.equal(calls, 1, "deadline prevents a foreground retry")
    }

    t.suite("catalog-display-and-browser") { t in
        for category in CategoryCatalog.all {
            for target in category.targets {
                t.expect(
                    CategoryCatalog.displayName(for: target) != target.label,
                    "every catalog target has a display name")
            }
        }
        t.equal(
            CategoryCatalog.displayNames(for: [.scheme("http"), .scheme("https")]),
            ["web links"], "web link labels are not repeated")
        let reader = StubReader(
            defaultAppsByTarget: ["http": "com.A", "https": "com.B", "public.html": "com.A"],
            candidatesByTarget: [
                "http": ["com.A"], "https": ["com.A", "com.B"], "public.html": ["com.A"],
            ])
        let status = Runtime(reader: reader, style: Style(enabled: false)).status(
            of: CategoryCatalog.browser)
        t.expect(status.isMixed, "a different HTTPS owner makes browser defaults mixed")
    }

    t.suite("helper-client") { t in
        let client = HelperClient(helperURL: URL(fileURLWithPath: "/unused.app"), timeout: 5)
        let app = StubReader.app("com.A", "A")
        let targets = [HandlerTarget.scheme("https")]
        var requestPath = ""
        var responsePath = ""
        let response = try client.apply(
            app: app, targets: targets,
            launch: { path in
                requestPath = path
                let request = try JSONDecoder().decode(
                    HelperRequest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                responsePath = request.responsePath
                t.equal(request.targets, targets, "client serializes assignment targets")
                let response = HelperResponse(outcomes: [.init(target: targets[0], ok: true)])
                try JSONEncoder().encode(response).write(
                    to: URL(fileURLWithPath: responsePath), options: .atomic)
            })
        t.equal(response.succeeded.count, 1, "client reads helper response")
        t.expect(
            !FileManager.default.fileExists(atPath: requestPath), "request is removed on success")
        t.expect(
            !FileManager.default.fileExists(atPath: responsePath), "response is removed on success")
        var time = 0.0
        var hints = 0
        do {
            _ = try client.apply(
                app: app, targets: targets, onSlow: { hints += 1 },
                launch: { requestPath = $0 }, now: { time }, sleep: { time += $0 })
            t.expect(false, "missing response must time out")
        } catch let error as DASError {
            if case .timedOut = error {
                t.expect(true, "timeout is typed")
            } else {
                t.expect(false, "unexpected error: \(error)")
            }
        }
        t.equal(hints, 1, "slow hint appears only once")
        t.expect(
            !FileManager.default.fileExists(atPath: requestPath), "request is removed on timeout")
        do {
            _ = try client.apply(
                app: app, targets: targets,
                launch: {
                    requestPath = $0
                    throw DASError.helperFailed("test launch failure")
                })
            t.expect(false, "launch error must propagate")
        } catch {
            t.expect(
                !FileManager.default.fileExists(atPath: requestPath),
                "request is removed on launch failure")
        }
    }

    t.suite("unicode-columns") { t in
        t.equal(visibleLength("中文"), 4, "CJK uses two columns per character")
        t.equal(visibleLength("e\u{301}"), 1, "combining marks share a column")
        t.equal(visibleLength("👩‍💻🇹🇷❤️"), 6, "emoji sequences use two columns")
        t.equal(visibleLength("\u{1B}[31m中文\u{1B}[0m"), 4, "ANSI does not add columns")
        for width in [10, 20, 40] {
            let output = Screen.render(
                Frame(
                    title: "中文👩‍💻", rows: [Row(label: String(repeating: "中文👩‍💻", count: 10))],
                    selected: 0, search: String(repeating: "中文", count: 20), searching: true,
                    status: nil),
                style: Style(enabled: false), height: 24, width: width)
            t.expect(
                output.components(separatedBy: "\n").allSatisfy { visibleLength($0) < width },
                "wide text fits in \(width) columns")
        }
    }
}
