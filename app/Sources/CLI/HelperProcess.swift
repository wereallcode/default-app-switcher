import Foundation

package struct ProcessResult {
    package let status: Int32
    package let standardError: String

    package init(status: Int32, standardError: String) {
        self.status = status
        self.standardError = standardError
    }
}

package protocol ProcessRunning {
    func run(executable: URL, arguments: [String]) throws -> ProcessResult
}

package struct SystemProcessRunner: ProcessRunning {
    package init() {}

    package func run(executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Drain before waiting so a full stderr pipe cannot block the child.
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            standardError: String(decoding: data, as: UTF8.self))
    }
}
