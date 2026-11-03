import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The fix's d3d11.dll, bundled with the app.
public struct Payload {
    public let dll: URL

    public enum LoadError: Error, LocalizedError {
        case missing
        public var errorDescription: String? { "The app is missing its d3d11.dll. Download it again." }
    }

    public init(directory: URL) throws {
        let dll = directory.appendingPathComponent("d3d11.dll")
        guard FileManager.default.fileExists(atPath: dll.path) else { throw LoadError.missing }
        self.dll = dll
    }
}

/// Whether the fix is in a game folder and switched on in its bottle.
public enum FixStatus: Equatable {
    case notInstalled
    case installed
    /// An older (or newer) version of the fix.
    case updateAvailable
    /// The DLL is there, but the bottle isn't set to load it.
    case inactive
}

public enum InstallError: Error, LocalizedError, Equatable {
    case notAGameFolder
    case gameRunning
    case quitCrossOver
    case readOnly(String)
    case copyFailed(String)
    /// Another d3d11.dll is in the folder, and one is already kept aside.
    case twoOtherDLLs

    public var errorDescription: String? {
        switch self {
        case .notAGameFolder:
            return "That folder doesn't contain \(GameFinder.exeName)."
        case .gameRunning:
            return "Quit The Wolf Among Us, then click the button again. Nothing was changed."
        case .quitCrossOver:
            return "Then click the button again. Nothing was changed. If you still see this, restart your Mac."
        case .readOnly(let path):
            return "Can't write to \(path). If the game is on an external drive formatted as NTFS, macOS can only read it."
        case .copyFailed(let reason):
            return "Couldn't copy the fix into the game folder: \(reason)"
        case .twoOtherDLLs:
            return "The game folder has a d3d11.dll from something else, and another one kept as d3d11.dll\(Installer.backupSuffix). Move one of them out of the folder, then try again. Nothing was changed."
        }
    }
}

/// What an install or removal did, for showing to the user.
public struct InstallReport: Equatable {
    public var override: DllOverride.Outcome?
    public var notes: [String] = []

    public init(override: DllOverride.Outcome? = nil, notes: [String] = []) {
        self.override = override
        self.notes = notes
    }
}

/// Puts the fix's d3d11.dll in the game folder and tells Wine to load it, or takes both away.
public struct Installer {
    public let payload: Payload
    public let env: SystemEnvironment

    public init(payload: Payload, env: SystemEnvironment) {
        self.payload = payload
        self.env = env
    }

    static let dllName = "d3d11.dll"
    static let backupSuffix = ".wolffix-backup"

    /// Whether a file is the fix's DLL (any version), from the marker it carries.
    static func isFix(_ file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return false }
        return data.range(of: Data("wolffix d3d11.dll".utf8)) != nil
    }

    public func status(of folder: URL, bottle: Bottle? = nil) -> FixStatus {
        let dll = folder.appendingPathComponent(Self.dllName)
        guard Self.isFix(dll) else { return .notInstalled }
        guard FileManager.default.contentsEqual(atPath: dll.path, andPath: payload.dll.path) else { return .updateAvailable }
        if let bottle, !DllOverride.isSet(inUserReg: readUserReg(bottle)) { return .inactive }
        return .installed
    }

    func readUserReg(_ bottle: Bottle) -> String {
        (try? String(contentsOf: bottle.userReg, encoding: .utf8)) ?? ""
    }

    func checkWritable(_ folder: URL) throws {
        guard GameFinder.hasExe(folder) else { throw InstallError.notAGameFolder }
        if env.gameIsRunning() { throw InstallError.gameRunning }
        let probe = folder.appendingPathComponent(".wolffix-write-test")
        guard FileManager.default.createFile(atPath: probe.path, contents: Data()) else {
            throw InstallError.readOnly(folder.path)
        }
        try? FileManager.default.removeItem(at: probe)
    }

    /// Installs (or updates) the fix in `game.folder` and sets the DLL override in its bottle.
    /// A d3d11.dll that isn't the fix's is kept aside, and put back on removal.
    public func install(_ game: GameInstall) throws -> InstallReport {
        let folder = game.folder
        try checkWritable(folder)
        if let bottle = game.bottle, !DllOverride.isSet(inUserReg: readUserReg(bottle)), env.wineIsRunning() {
            throw InstallError.quitCrossOver
        }
        let fm = FileManager.default
        var report = InstallReport()
        let dll = folder.appendingPathComponent(Self.dllName)
        let backup = folder.appendingPathComponent(Self.dllName + Self.backupSuffix)
        let otherDLL = fm.fileExists(atPath: dll.path) && !Self.isFix(dll)
        if otherDLL, fm.fileExists(atPath: backup.path) { throw InstallError.twoOtherDLLs }
        do {
            if otherDLL {
                try fm.moveItem(at: dll, to: backup)
                report.notes.append("Your game folder already had a d3d11.dll; it was kept as d3d11.dll\(Self.backupSuffix).")
            }
            if fm.fileExists(atPath: dll.path) { try fm.removeItem(at: dll) }
            try fm.copyItem(at: payload.dll, to: dll)
            #if canImport(Darwin)
            removexattr(dll.path, "com.apple.quarantine", 0)
            #endif
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }
        if let bottle = game.bottle {
            report.override = DllOverride.ensure(in: bottle, env: env)
        }
        return report
    }

    /// Removes the fix from `game.folder`, puts back a d3d11.dll it replaced, and puts the
    /// bottle's setting back to how it was.
    public func uninstall(_ game: GameInstall) throws -> InstallReport {
        let folder = game.folder
        try checkWritable(folder)
        if let bottle = game.bottle, DllOverride.needsRestore(in: bottle), env.wineIsRunning() {
            throw InstallError.quitCrossOver
        }
        let fm = FileManager.default
        let dll = folder.appendingPathComponent(Self.dllName)
        let backup = folder.appendingPathComponent(Self.dllName + Self.backupSuffix)
        let restoring = fm.fileExists(atPath: backup.path)
        var report = InstallReport()
        do {
            if Self.isFix(dll) { try fm.removeItem(at: dll) }
            if restoring, !fm.fileExists(atPath: dll.path) {
                try fm.moveItem(at: backup, to: dll)
                report.notes.append("Put back the d3d11.dll your game folder had before.")
            }
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }
        if let bottle = game.bottle {
            report.override = DllOverride.remove(from: bottle, env: env)
        }
        return report
    }
}
