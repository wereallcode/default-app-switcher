import DASCLI
import DASCore
import DASHelperSupport
import Foundation
import UniformTypeIdentifiers

@MainActor
private final class WorkspaceStub: WorkspaceAssigning {
    var applicationURL: URL?
    var type: UTType?
    var scheme: String?
    var completion: (@Sendable (Error?) -> Void)?
    var immediately = true
    var error: Error?

    func setDefaultApplication(
        at applicationURL: URL, toOpen type: UTType,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        self.applicationURL = applicationURL
        self.type = type
        self.completion = completion
        if immediately { completion(error) }
    }

    func setDefaultApplication(
        at applicationURL: URL, toOpenURLsWithScheme scheme: String,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        self.applicationURL = applicationURL
        self.scheme = scheme
        self.completion = completion
        if immediately { completion(error) }
    }
}

private struct ProcessStub: ProcessRunning {
    var execute: (URL, [String]) throws -> ProcessResult
    func run(executable: URL, arguments: [String]) throws -> ProcessResult {
        try execute(executable, arguments)
    }
}

@MainActor
func runAdapterTests(_ t: TestRunner) {
    t.suite("workspace-adapter") { t in
        let app = URL(fileURLWithPath: "/Applications/App With Spaces.app")
        let start = Date(timeIntervalSince1970: 100)
        for target in [HandlerTarget.uti("public.html"), .scheme("http"), .scheme("https")] {
            let workspace = WorkspaceStub()
            let result = DefaultAssignment.assign(
                target, to: app, deadline: start.addingTimeInterval(1), workspace: workspace,
                now: { start },
                pump: { _ in t.expect(false, "synchronous completion needs no pump") })
            t.expect(result.0 == nil, "synchronous success is retained")
            t.equal(workspace.applicationURL, app, "application URL reaches the workspace")
            if target.kind == .uti {
                t.equal(workspace.type?.identifier, target.value, "UTI resolves before assignment")
                t.expect(workspace.scheme == nil, "UTI does not use the scheme API")
            } else {
                t.equal(workspace.scheme, target.value, "scheme reaches the correct API")
                t.expect(workspace.type == nil, "scheme does not use the UTI API")
            }
        }
        let invalid = WorkspaceStub()
        let unknown = DefaultAssignment.assign(
            .uti("not a valid type"), to: app, deadline: start.addingTimeInterval(1),
            workspace: invalid, now: { start })
        t.equal(unknown.0?.code, 1, "invalid type is rejected")
        t.expect(invalid.applicationURL == nil, "invalid type never calls the workspace")

        let workspace = WorkspaceStub()
        workspace.immediately = false
        var now = start
        let failure = NSError(domain: "test", code: 42)
        let deferred = DefaultAssignment.assign(
            .scheme("https"), to: app, deadline: start.addingTimeInterval(1), workspace: workspace,
            now: { now },
            pump: { until in
                now = until
                workspace.completion?(failure)
            })
        t.equal(deferred.0?.code, 42, "deferred completion preserves the error")
        t.expect(deferred.1 > 0, "elapsed time includes pumping")

        now = start
        let timeout = DefaultAssignment.assign(
            .scheme("https"), to: app, deadline: start.addingTimeInterval(0.02),
            workspace: workspace,
            now: { now },
            pump: { until in
                t.expect(until <= start.addingTimeInterval(0.02), "pump cannot exceed the deadline")
                now = until
            })
        t.equal(timeout.0?.code, 2, "missing completion times out")
        workspace.completion?(nil)
        t.equal(timeout.0?.code, 2, "a late callback cannot change the returned timeout")
    }

    t.suite("process-adapter") { t in
        let client = HelperClient(helperURL: URL(fileURLWithPath: "/tmp/Helper With Spaces.app"))
        let request = "/tmp/request with spaces.json"
        try client.launchNewInstance(
            requestPath: request,
            runner: ProcessStub { executable, arguments in
                t.equal(executable.path, "/usr/bin/open", "launch uses the system open command")
                t.equal(
                    arguments,
                    ["-n", "-a", "/tmp/Helper With Spaces.app", "--args", "--request", request],
                    "paths are separate arguments and a new instance is requested")
                return ProcessResult(status: 0, standardError: "")
            })
        do {
            try client.launchNewInstance(
                requestPath: request,
                runner: ProcessStub { _, _ in
                    ProcessResult(status: 1, standardError: "  launch failed\n")
                })
            t.expect(false, "failed launch must throw")
        } catch let error as DASError {
            t.expect(
                error.description.contains("Helper With Spaces.app: launch failed"),
                "launch error includes the helper and trimmed stderr")
        }
        do {
            try client.launchNewInstance(
                requestPath: request,
                runner: ProcessStub { _, _ in
                    throw NSError(domain: "test", code: 47)
                })
            t.expect(false, "process startup failure must propagate")
        } catch {
            t.equal((error as NSError).code, 47, "startup error is preserved")
        }
        let runner = SystemProcessRunner()
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "i=0; while [ $i -lt 20000 ]; do printf 'error line\\n' >&2; i=$((i+1)); done; exit 7",
            ])
        t.equal(result.status, 7, "real child exit status is returned")
        t.equal(result.standardError.count, 220000, "stderr larger than a pipe buffer is drained")
        do {
            _ = try runner.run(
                executable: URL(fileURLWithPath: "/nonexistent/das-test"), arguments: [])
            t.expect(false, "missing executable must throw")
        } catch {
            t.expect(true, "real startup failure propagates")
        }
    }

    t.suite("category-picker-state") { t in
        let rows =
            CategoryCatalog.all.map { Row(label: $0.name, id: $0.id) }
            + [Row(label: "Exit", id: "exit")]
        var state = PickerState(rows: rows, isTopLevel: true)
        t.equal(state.reduce(event: .enter), .select("browser"), "first category is selected")
        _ = state.reduce(event: .up)
        t.equal(state.reduce(event: .enter), .select("exit"), "up wraps to exit")
        _ = state.reduce(event: .down)
        _ = state.reduce(event: .down)
        t.equal(state.reduce(event: .enter), .select("code-editor"), "down selects a category")
        state.refresh(rows: rows)
        t.equal(
            state.reduce(event: .enter), .select("code-editor"), "return keeps category selection")
        for key in [Key.search, .refresh, .character("x"), .backspace, .other] {
            t.equal(state.reduce(event: key), .none, "category screen ignores app-only controls")
        }
        t.expect(state.search.isEmpty && !state.searching, "category screen never filters")
        t.equal(state.reduce(event: .back), .quit, "back exits the category screen")
        t.equal(state.reduce(event: .quit), .quit, "quit exits the category screen")
        state.refresh(rows: [])
        t.equal(state.reduce(event: .enter), .none, "empty categories cannot be selected")
    }
}
