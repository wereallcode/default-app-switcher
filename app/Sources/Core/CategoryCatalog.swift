import Foundation

package enum CategoryCatalog {
    package static let browser = AppCategory(
        id: "browser",
        name: "Browser",
        summary: "Web links and HTML files",
        targets: [
            .scheme("http", primary: true),
            .uti("public.html"),
            .scheme("https"),
        ]
    )

    package static let codeEditor = AppCategory(
        id: "code-editor",
        name: "Code Editor",
        summary: "Source files",
        targets: [
            .uti("public.python-script", primary: true),
            .uti("public.shell-script"),
            .uti("com.netscape.javascript-source"),
            .uti("public.json"),
            .uti("public.yaml"),
            .uti("net.daringfireball.markdown"),
        ]
    )

    package static let mail = AppCategory(
        id: "mail",
        name: "Mail",
        summary: "Email links",
        targets: [.scheme("mailto", primary: true)]
    )

    package static let text = AppCategory(
        id: "text",
        name: "Plain Text",
        summary: "Plain text files",
        targets: [.uti("public.plain-text", primary: true)]
    )

    package static let all: [AppCategory] = [browser, codeEditor, mail, text]

    package static func builtin(id: String) -> AppCategory? {
        all.first { $0.id == id }
    }
    package static func displayNames(for targets: [HandlerTarget]) -> [String] {
        if Set(targets) == Set(codeEditor.targets) { return ["all supported file types"] }
        var names: [String] = []
        for target in targets {
            let name = displayName(for: target)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    package static func displayName(for target: HandlerTarget) -> String {
        switch (target.kind, target.value) {
        case (.scheme, "http"), (.scheme, "https"): return "web links"
        case (.scheme, "mailto"): return "email links"
        case (.uti, "public.html"): return "HTML files"
        case (.uti, "public.python-script"): return "Python scripts"
        case (.uti, "public.shell-script"): return "shell scripts"
        case (.uti, "com.netscape.javascript-source"): return "JavaScript files"
        case (.uti, "public.json"): return "JSON files"
        case (.uti, "public.yaml"): return "YAML files"
        case (.uti, "net.daringfireball.markdown"): return "Markdown files"
        case (.uti, "public.plain-text"): return "plain text files"
        default: return target.label
        }
    }
}
