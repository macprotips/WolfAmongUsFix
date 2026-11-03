import Foundation
import XCTest
@testable import WolfFixKit

/// Records commands and answers `ps` with `processes`.
final class FakeRunner: CommandRunner {
    var processes: [String] = []
    var psFails = false
    var calls: [String] = []

    func run(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval) -> CommandResult {
        calls.append(executable.path)
        guard executable.lastPathComponent == "ps", !psFails else { return CommandResult(status: 1, output: "") }
        return CommandResult(status: 0, output: processes.joined(separator: "\n"))
    }

    /// Everything run besides ps.
    var otherCalls: [String] { calls.filter { !$0.hasSuffix("/ps") } }
}

/// A fake Mac: a home folder with bottles, and a folder standing in for /Volumes.
final class FakeMac {
    let root: URL
    let home: URL
    /// Stands in for /Volumes (external drives).
    let volumes: URL
    let runner = FakeRunner()
    let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("wolffix-tests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        volumes = root.appendingPathComponent("Volumes")
        for dir in [home, volumes] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? fm.removeItem(at: root)
    }

    var env: SystemEnvironment {
        SystemEnvironment(home: home, runner: runner)
    }

    @discardableResult
    func bottle(_ name: String, steam: Bool = true, userReg: String = "WINE REGISTRY Version 2\n",
                base: String = "Library/Application Support/CrossOver/Bottles") throws -> URL {
        let bottle = home.appendingPathComponent(base).appendingPathComponent(name)
        try fm.createDirectory(at: bottle.appendingPathComponent("drive_c/windows/system32"), withIntermediateDirectories: true)
        try fm.createDirectory(at: bottle.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: bottle.appendingPathComponent("dosdevices/c:").path, withDestinationPath: "../drive_c")
        if steam {
            let steamDir = bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam")
            try fm.createDirectory(at: steamDir.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
            try Data().write(to: steamDir.appendingPathComponent("steam.exe"))
        }
        try userReg.write(to: bottle.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
        return bottle
    }

    /// A drive letter in `bottle` pointing at `target`.
    func drive(_ letter: String, in bottle: URL, to target: URL) throws {
        try fm.createSymbolicLink(atPath: bottle.appendingPathComponent("dosdevices/\(letter):").path, withDestinationPath: target.path)
    }

    func libraryVDF(in bottle: URL, paths: [String]) throws {
        var text = "\"libraryfolders\"\n{\n"
        for (i, path) in paths.enumerated() {
            let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            text += "\t\"\(i)\"\n\t{\n\t\t\"path\"\t\t\"\(escaped)\"\n\t\t\"label\"\t\t\"\"\n\t}\n"
        }
        text += "}\n"
        try text.write(to: bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"),
                       atomically: true, encoding: .utf8)
    }

    /// A game folder, with a stand-in exe and one of the game's other DLLs.
    @discardableResult
    func game(in folder: URL) throws -> URL {
        let game = folder.appendingPathComponent("steamapps/common/The Wolf Among Us Remastered")
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("MZ game".utf8).write(to: game.appendingPathComponent("TheWolfAmongUsRemastered.exe"))
        try Data("MZ fmod".utf8).write(to: game.appendingPathComponent("fmod64.dll"))
        return game
    }

    /// An installer with the fix's real d3d11.dll from the repository.
    func installer() throws -> Installer {
        Installer(payload: try payload(), env: env)
    }

    func payload() throws -> Payload {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("payload")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.copyItem(at: repo.appendingPathComponent("prebuilt/d3d11.dll"), to: dir.appendingPathComponent("d3d11.dll"))
        return try Payload(directory: dir)
    }
}

