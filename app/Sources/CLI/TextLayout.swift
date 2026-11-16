import Foundation
import TerminalSupport

private enum EscapeState {
    case text
    case afterEscape
    case insideCSI
}

private func scan(_ text: String, keeping keep: ((Character) -> Void)? = nil) -> Int {
    var state = EscapeState.text
    var visible = 0
    for character in text {
        switch state {
        case .text:
            if character == "\u{1B}" {
                state = .afterEscape
            } else {
                visible += characterWidth(character)
                keep?(character)
            }
        case .afterEscape:
            state = (character == "[") ? .insideCSI : .text
        case .insideCSI:
            if let ascii = character.asciiValue, ascii >= 0x40, ascii <= 0x7E {
                state = .text
            }
        }
    }
    return visible
}

package func visibleLength(_ text: String) -> Int {
    scan(text)
}

package func stripANSI(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    _ = scan(text) { result.append($0) }
    return result
}

package func pad(_ text: String, _ width: Int) -> String {
    let length = visibleLength(text)
    return length >= width ? text : text + String(repeating: " ", count: width - length)
}

package func trimTrailing(_ text: String) -> String {
    var result = text
    while result.hasSuffix(" ") { result.removeLast() }
    return result
}

private func characterWidth(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    if scalars.contains(where: { $0.properties.isEmojiPresentation })
        || scalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x20E3 })
    {
        return 2
    }
    return scalars.map { Int(das_scalar_width($0.value)) }.max() ?? 0
}

func columnPrefix(_ text: String, width: Int) -> String {
    var result = ""
    var used = 0
    for character in text {
        let next = characterWidth(character)
        guard used + next <= width else { break }
        result.append(character)
        used += next
    }
    return result
}

func columnSuffix(_ text: String, width: Int) -> String {
    String(columnPrefix(String(text.reversed()), width: width).reversed())
}
