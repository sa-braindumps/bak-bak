import Foundation

/// Line-level editing of a flat TOML file (`[table]` headers + `key = value`
/// entries), so writes touch only the lines they change.
///
/// TOMLKit parses fine but drops every comment when it re-serializes, and the
/// `# learned <timestamp>` comments in `profile.toml` are load-bearing
/// (SPEC §5.5). So `ProfileStore` reads with TOMLKit and writes with this.
struct TOMLLineEditor {

    private(set) var lines: [String]

    init(_ text: String) {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
    }

    var text: String {
        lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Editing

    /// Set `key = valueLiteral` inside `[table]`, creating the table if needed.
    /// An existing entry is replaced in place; a new one goes after the table's
    /// last non-blank line. `comment` (e.g. `"learned 2026-…Z"`) is written as a
    /// `# …` line directly above the entry, replacing a `# learned` line there.
    mutating func set(_ key: String, to valueLiteral: String, in table: String, comment: String? = nil) {
        let entryLine = "\(Self.quoteKey(key)) = \(valueLiteral)"

        if let entry = scan().first(where: { $0.table == table && $0.key == key }) {
            lines.replaceSubrange(entry.lines, with: [entryLine])
            if let comment {
                let above = entry.lines.lowerBound - 1
                if above >= 0, Self.isLearnedComment(lines[above]) {
                    lines[above] = "# \(comment)"
                } else {
                    lines.insert("# \(comment)", at: entry.lines.lowerBound)
                }
            }
            return
        }

        let newLines = (comment.map { ["# \($0)"] } ?? []) + [entryLine]

        guard let section = sectionRange(of: table) else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append("[\(table)]")
            lines.append(contentsOf: newLines)
            return
        }

        var insertAt = section.upperBound
        while insertAt > section.lowerBound + 1,
              lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        lines.insert(contentsOf: newLines, at: insertAt)
    }

    /// Remove `key` from `[table]`, along with a `# learned` comment directly
    /// above it. No-op if absent.
    mutating func remove(_ key: String, in table: String) {
        guard let entry = scan().first(where: { $0.table == table && $0.key == key }) else { return }
        var range = entry.lines
        if range.lowerBound > 0, Self.isLearnedComment(lines[range.lowerBound - 1]) {
            range = (range.lowerBound - 1)..<range.upperBound
        }
        lines.removeSubrange(range)
    }

    /// Keys currently present in `[table]`, in file order.
    func keys(in table: String) -> [String] {
        scan().filter { $0.table == table }.map(\.key)
    }

    // MARK: - Literals

    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    static func quoteKey(_ key: String) -> String {
        let bare = !key.isEmpty && key.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-"
        }
        return bare ? key : string(key)
    }

    // MARK: - Scanning

    private struct Entry {
        let table: String
        let key: String
        let lines: Range<Int>
    }

    private static func isLearnedComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("# learned ")
    }

    /// The line range of `[table]`: its header through the line before the
    /// next header (or end of file).
    private func sectionRange(of table: String) -> Range<Int>? {
        let headers = scanHeaders()
        guard let index = headers.firstIndex(where: { $0.name == table }) else { return nil }
        let start = headers[index].line
        let end = index + 1 < headers.count ? headers[index + 1].line : lines.count
        return start..<end
    }

    private func scanHeaders() -> [(name: String, line: Int)] {
        var headers: [(name: String, line: Int)] = []
        walk { _, line, header, _ in
            if let header { headers.append((header, line)) }
        }
        return headers
    }

    private func scan() -> [Entry] {
        var entries: [Entry] = []
        walk { table, _, _, entry in
            if let entry { entries.append(Entry(table: table, key: entry.key, lines: entry.lines)) }
        }
        return entries
    }

    /// Walk the file once, skipping the insides of multi-line strings so a
    /// snippet body that happens to contain `[x]` or `a = b` is never mistaken
    /// for a header or entry.
    private func walk(_ visit: (_ table: String, _ line: Int, _ header: String?, _ entry: (key: String, lines: Range<Int>)?) -> Void) {
        var table = ""
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("["), !trimmed.hasPrefix("[["),
               let close = trimmed.firstIndex(of: "]") {
                table = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
                    .trimmingCharacters(in: .whitespaces)
                visit(table, i, table, nil)
                i += 1
                continue
            }

            guard let (key, valueStart) = Self.parseKey(trimmed) else {
                i += 1
                continue
            }

            let value = String(trimmed[valueStart...])
            var end = i + 1
            if let delimiter = Self.openMultiline(value) {
                while end < lines.count, !lines[end].contains(delimiter) { end += 1 }
                end = min(end + 1, lines.count)
            }
            visit(table, i, nil, (key, i..<end))
            i = end
        }
    }

    /// If `value` opens a multi-line string that doesn't close on this line,
    /// return its delimiter.
    private static func openMultiline(_ value: String) -> String? {
        for delimiter in ["\"\"\"", "'''"] where value.hasPrefix(delimiter) {
            let rest = value.dropFirst(3)
            return rest.contains(delimiter) ? nil : delimiter
        }
        return nil
    }

    /// Parse the key of a `key = value` line. Returns the unescaped key and the
    /// index where the value starts, or nil for comments/blank/other lines.
    private static func parseKey(_ line: String) -> (String, String.Index)? {
        guard let first = line.first, first != "#" else { return nil }

        var key = ""
        var i = line.startIndex

        if first == "\"" || first == "'" {
            i = line.index(after: i)
            var closed = false
            while i < line.endIndex {
                let c = line[i]
                if c == first { closed = true; i = line.index(after: i); break }
                if c == "\\" && first == "\"" {
                    let next = line.index(after: i)
                    guard next < line.endIndex else { return nil }
                    switch line[next] {
                    case "n": key.append("\n")
                    case "t": key.append("\t")
                    case "r": key.append("\r")
                    default: key.append(line[next])
                    }
                    i = line.index(after: next)
                    continue
                }
                key.append(c)
                i = line.index(after: i)
            }
            guard closed else { return nil }
        } else {
            while i < line.endIndex, line[i] != "=", !line[i].isWhitespace {
                key.append(line[i])
                i = line.index(after: i)
            }
        }

        while i < line.endIndex, line[i].isWhitespace { i = line.index(after: i) }
        guard i < line.endIndex, line[i] == "=", !key.isEmpty else { return nil }
        i = line.index(after: i)
        while i < line.endIndex, line[i].isWhitespace { i = line.index(after: i) }
        return (key, i)
    }
}
