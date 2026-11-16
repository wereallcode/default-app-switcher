import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
package protocol WorkspaceAssigning {
    func setDefaultApplication(
        at applicationURL: URL, toOpen type: UTType,
        completion: @escaping @Sendable (Error?) -> Void)
    func setDefaultApplication(
        at applicationURL: URL, toOpenURLsWithScheme scheme: String,
        completion: @escaping @Sendable (Error?) -> Void)
}

@MainActor
package struct SystemWorkspaceAssignment: WorkspaceAssigning {
    package init() {}

    package func setDefaultApplication(
        at applicationURL: URL, toOpen type: UTType,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        NSWorkspace.shared.setDefaultApplication(
            at: applicationURL, toOpen: type, completion: completion)
    }

    package func setDefaultApplication(
        at applicationURL: URL, toOpenURLsWithScheme scheme: String,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        NSWorkspace.shared.setDefaultApplication(
            at: applicationURL, toOpenURLsWithScheme: scheme, completion: completion)
    }
}
