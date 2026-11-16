import DASCore
import Foundation

package struct HelperClient: Sendable {
    let helperURL: URL
    let timeout: Double

    package static let defaultTimeout: Double = 120

    private let confirmationHintDelay: Double = 3.0

    package init(helperURL: URL, timeout: Double = HelperClient.defaultTimeout) {
        self.helperURL = helperURL
        self.timeout = timeout
    }

    init(
        timeout: Double = HelperClient.defaultTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        self.init(helperURL: try HelperLocator.locate(environment: environment), timeout: timeout)
    }

    package func apply(
        app: AppInfo, targets: [HandlerTarget], onSlow: (() -> Void)? = nil,
        launch: ((String) throws -> Void)? = nil,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws
        -> HelperResponse
    {
        let id = UUID().uuidString
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let requestURL = tmp.appendingPathComponent("das-\(id).request.json")
        let responseURL = tmp.appendingPathComponent("das-\(id).response.json")
        defer {
            try? FileManager.default.removeItem(at: requestURL)
            try? FileManager.default.removeItem(at: responseURL)
        }

        let request = HelperRequest(
            applicationPath: app.url.path,
            targets: targets,
            responsePath: responseURL.path,
            budget: max(5, timeout - 5)
        )
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: requestURL.path)

        if let launch {
            try launch(requestURL.path)
        } else {
            try launchNewInstance(requestPath: requestURL.path)
        }

        let start = now()
        var warned = false
        while now() - start < timeout {
            if FileManager.default.fileExists(atPath: responseURL.path),
                let data = try? Data(contentsOf: responseURL),
                !data.isEmpty
            {
                return try HelperResponse.parse(data)
            }
            if !warned, now() - start > confirmationHintDelay {
                warned = true
                onSlow?()
            }
            sleep(0.05)
        }
        throw DASError.timedOut(seconds: timeout)
    }

    package func launchNewInstance(
        requestPath: String, runner: any ProcessRunning = SystemProcessRunner()
    ) throws {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-n", "-a", helperURL.path, "--args", "--request", requestPath])
        if result.status != 0 {
            throw DASError.helperFailed(
                "could not launch \(helperURL.lastPathComponent): \(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }
}
