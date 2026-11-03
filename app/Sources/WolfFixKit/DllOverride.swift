import Foundation

/// The per-game Wine setting `d3d11 = native,builtin` for the game's exe, which makes Wine load
/// the fix's d3d11.dll from the game folder. Stored in the bottle's user.reg, which the app
/// edits directly (it never runs Wine).
public enum DllOverride {
    /// The key as written in user.reg (backslashes doubled).
    static let fileKey = #"Software\\Wine\\AppDefaults\\TheWolfAmongUsRemastered.exe\\DllOverrides"#
    static let valueLine = #""d3d11"="native,builtin""#

    /// The line range of the key's section in user.reg (header line first), if present.
    static func section(in lines: [String]) -> Range<Int>? {
        let header = "[" + fileKey.lowercased() + "]"
        guard let start = lines.firstIndex(where: { $0.lowercased().hasPrefix(header) }) else { return nil }
        var end = start + 1
        while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
        return start..<end
    }

    static func isD3D11Line(_ line: String) -> Bool {
        line.lowercased().hasPrefix(#""d3d11"="#)
    }

    /// Whether user.reg already makes the game load a native d3d11.dll first.
    public static func isSet(inUserReg text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard let range = section(in: lines) else { return false }
        return lines[range].contains { line in
            isD3D11Line(line) && line.lowercased().replacingOccurrences(of: " ", with: "").dropFirst(8).hasPrefix("\"native")
        }
    }

    /// The game's d3d11 line in user.reg, whatever its value.
    static func line(inUserReg text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let range = section(in: lines) else { return nil }
        return lines[range].first(where: isD3D11Line)
    }

    /// user.reg with the d3d11 line set to `line` (the fix's, unless restoring an earlier one).
    static func adding(toUserReg text: String, line valueLine: String = valueLine, now: Date = Date()) -> String {
        var lines = text.components(separatedBy: "\n")
        if let range = section(in: lines) {
            if let existing = lines[range].firstIndex(where: isD3D11Line) {
                lines[existing] = valueLine
            } else {
                var insertAt = range.lowerBound + 1
                if insertAt < lines.count, lines[insertAt].hasPrefix("#time=") { insertAt += 1 }
                lines.insert(valueLine, at: insertAt)
            }
            return lines.joined(separator: "\n")
        }
        let unix = Int(now.timeIntervalSince1970)
        let fileTime = String(UInt64(unix + 11_644_473_600) * 10_000_000, radix: 16)
        var out = text
        if !out.hasSuffix("\n") { out += "\n" }
        if !out.hasSuffix("\n\n") { out += "\n" }
        out += "[\(fileKey)] \(unix)\n#time=\(fileTime)\n\(valueLine)\n"
        return out
    }

    /// user.reg with the override removed. When it was the section's only value, the
    /// whole section goes, so the file is back to how it was before the fix.
    public static func removing(fromUserReg text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let range = section(in: lines), let line = lines[range].firstIndex(where: isD3D11Line) else { return text }
        lines.remove(at: line)
        let rest = lines[range.lowerBound + 1 ..< range.upperBound - 1]
        guard !rest.contains(where: { $0.hasPrefix("\"") || $0.hasPrefix("@") }) else { return lines.joined(separator: "\n") }
        var end = range.upperBound - 1
        while end > range.lowerBound + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        lines.removeSubrange(range.lowerBound ..< end)
        let at = range.lowerBound
        if at > 0, at < lines.count, lines[at - 1].isEmpty, lines[at].isEmpty { lines.remove(at: at) }
        return lines.joined(separator: "\n")
    }

    public enum Outcome: Equatable {
        case alreadySet
        case setInFile
        case removed
        case notNeeded
        /// Wine is running, and it would overwrite the change when it exits: quit CrossOver first.
        case wineRunning
        case failed(String)
    }

    /// Makes sure the override is set in `bottle`, by editing its user.reg. The app never
    /// starts Wine: while Wine runs it keeps the registry in memory and would overwrite
    /// the file when it exits, so then the user is asked to quit CrossOver first.
    public static func ensure(in bottle: Bottle, env: SystemEnvironment) -> Outcome {
        let current = (try? String(contentsOf: bottle.userReg, encoding: .utf8)) ?? ""
        if isSet(inUserReg: current) { return .alreadySet }
        return editFile(of: bottle, env: env) { adding(toUserReg: $0) } ?? .setInFile
    }

    /// The copy of user.reg from before the fix first changed it.
    static func backup(of bottle: Bottle) -> URL {
        bottle.path.appendingPathComponent("user.reg.wolffix-backup")
    }

    /// The d3d11 line the bottle had before the fix (nil: none), if the fix changed it.
    static func lineBeforeFix(in bottle: Bottle) -> String?? {
        guard let text = try? String(contentsOf: backup(of: bottle), encoding: .utf8) else { return nil }
        return .some(line(inUserReg: text))
    }

    /// Whether removing the fix has to change user.reg.
    public static func needsRestore(in bottle: Bottle) -> Bool {
        guard let before = lineBeforeFix(in: bottle) else { return false }
        let current = (try? String(contentsOf: bottle.userReg, encoding: .utf8)) ?? ""
        return line(inUserReg: current) != before
    }

    /// Puts the game's d3d11 setting back to what it was before the fix (used when the fix is
    /// removed). A setting the fix didn't make is left alone.
    public static func remove(from bottle: Bottle, env: SystemEnvironment) -> Outcome {
        guard let before = lineBeforeFix(in: bottle) else { return .notNeeded }
        guard needsRestore(in: bottle) else {
            try? FileManager.default.removeItem(at: backup(of: bottle))
            return .notNeeded
        }
        let restore = { (text: String) in before.map { adding(toUserReg: text, line: $0) } ?? removing(fromUserReg: text) }
        if let problem = editFile(of: bottle, env: env, restore) { return problem }
        try? FileManager.default.removeItem(at: backup(of: bottle))
        return .removed
    }

    /// Edits user.reg in place, keeping a copy of it from before the fix's first change; nil on success.
    static func editFile(of bottle: Bottle, env: SystemEnvironment, _ edit: (String) -> String) -> Outcome? {
        if env.wineIsRunning() { return .wineRunning }
        guard let text = try? String(contentsOf: bottle.userReg, encoding: .utf8) else {
            return .failed("Couldn't read \(bottle.userReg.path)")
        }
        let backup = backup(of: bottle)
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: bottle.userReg, to: backup)
            }
            try edit(text).write(to: bottle.userReg, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
