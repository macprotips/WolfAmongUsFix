import Foundation
import XCTest
@testable import WolfFixKit

final class BottleTests: XCTestCase {
    func testLibraryPathsFromVDF() {
        let vdf = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"K:\\\\SteamLibrary"
        \t\t"label"\t\t""
        \t}
        }
        """
        XCTAssertEqual(Bottle.libraryPaths(inVDF: vdf), [#"C:\Program Files (x86)\Steam"#, #"K:\SteamLibrary"#])
    }

    func testFindsBottlesWithDriveC() throws {
        let mac = try FakeMac()
        try mac.bottle("Steam")
        try mac.bottle("Games", steam: false)
        try mac.fm.createDirectory(at: mac.home.appendingPathComponent("Library/Application Support/CrossOver/Bottles/empty"),
                                   withIntermediateDirectories: true)
        let bottles = Bottles.all(in: mac.env)
        XCTAssertEqual(bottles.map(\.name), ["Games", "Steam"])
        XCTAssertFalse(bottles[0].hasSteam)
        XCTAssertTrue(bottles[1].hasSteam)
    }

    func testFindsBottlesInCrossOversBottlePath() throws {
        let mac = try FakeMac()
        try mac.bottle("Steam")
        let custom = try mac.bottle("Wolf", base: "CXPBottles")
        try #"""
        ;;"BottlePath" = ""
        "BottlePath" = "${HOME}/CXPBottles:/nowhere"
        """#.write(to: mac.home.appendingPathComponent("Library/Application Support/CrossOver/CrossOver.conf"),
                   atomically: true, encoding: .utf8)
        XCTAssertEqual(Bottles.all(in: mac.env).map(\.name), ["Wolf", "Steam"])
        let game = try mac.game(in: custom.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
        XCTAssertEqual(GameFinder.findAll(env: mac.env).first?.bottle?.name, "Wolf")
        XCTAssertEqual(GameFinder.install(at: game, env: mac.env).reason, .insideBottle)
    }

    func testFindsBottlesInTheFolderChosenInCrossOver() throws {
        let mac = try FakeMac()
        try mac.bottle("Steam")
        try mac.bottle("Wolf", base: "Games/Bottles")
        let prefs = mac.home.appendingPathComponent("Library/Preferences")
        try mac.fm.createDirectory(at: prefs, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["BottleDir": "~/Games/Bottles"], format: .binary, options: 0)
            .write(to: prefs.appendingPathComponent("com.codeweavers.CrossOver.plist"))
        XCTAssertEqual(Bottles.all(in: mac.env).map(\.name), ["Wolf", "Steam"])
    }

    func testGameInsideAnUnlistedBottleUsesThatBottle() throws {
        let mac = try FakeMac()
        try mac.bottle("Steam")
        let other = try mac.bottle("Elsewhere", base: "Somewhere")
        let game = try mac.game(in: other.appendingPathComponent("drive_c/Games"))
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(install.bottle?.name, "Elsewhere")
        XCTAssertEqual(install.reason, .insideBottle)
        XCTAssertEqual(install.candidates.map(\.name), ["Steam", "Elsewhere"])
    }

    func testDriveLettersMapToMacFolders() throws {
        let mac = try FakeMac()
        let bottle = try mac.bottle("Steam")
        let drive = mac.volumes.appendingPathComponent("Games")
        try mac.fm.createDirectory(at: drive.appendingPathComponent("SteamLibrary"), withIntermediateDirectories: true)
        try mac.drive("k", in: bottle, to: drive)
        let b = Bottles.all(in: mac.env)[0]
        XCTAssertEqual(b.macURL(forWindowsPath: #"K:\SteamLibrary"#)?.canonicalPath,
                       drive.appendingPathComponent("SteamLibrary").canonicalPath)
        XCTAssertEqual(b.macURL(forWindowsPath: #"C:\Program Files (x86)"#)?.canonicalPath,
                       bottle.appendingPathComponent("drive_c/Program Files (x86)").canonicalPath)
        XCTAssertNil(b.macURL(forWindowsPath: #"Q:\nothing"#))
        XCTAssertNil(b.macURL(forWindowsPath: "relative"))
    }

    func testBottleForGameInsideBottle() throws {
        let mac = try FakeMac()
        try mac.bottle("Other")
        let bottle = try mac.bottle("Steam")
        let game = try mac.game(in: bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(install.bottle?.name, "Steam")
    }

    func testBottleForGameOnExternalDriveViaSteamLibrary() throws {
        let mac = try FakeMac()
        let other = try mac.bottle("Other")
        let bottle = try mac.bottle("Steam")
        let drive = mac.volumes.appendingPathComponent("Games")
        let game = try mac.game(in: drive.appendingPathComponent("SteamLibrary"))
        try mac.drive("k", in: bottle, to: drive)
        try mac.libraryVDF(in: bottle, paths: [#"C:\Program Files (x86)\Steam"#, #"K:\SteamLibrary"#])
        try mac.libraryVDF(in: other, paths: [#"C:\Program Files (x86)\Steam"#])
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(install.bottle?.name, "Steam")
    }

    func testOnlyBottleWithSteamIsPicked() throws {
        let mac = try FakeMac()
        try mac.bottle("Office", steam: false)
        try mac.bottle("Steam")
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        XCTAssertEqual(GameFinder.install(at: game, env: mac.env).bottle?.name, "Steam")
    }

    func testAmbiguousBottleOffersCandidates() throws {
        let mac = try FakeMac()
        try mac.bottle("A")
        try mac.bottle("B")
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertNil(install.bottle)
        XCTAssertEqual(install.candidates.map(\.name), ["A", "B"])
    }
}

final class GameFinderTests: XCTestCase {
    func testGameFolderFromWhatTheUserDrops() throws {
        let mac = try FakeMac()
        let library = mac.volumes.appendingPathComponent("Games/SteamLibrary")
        let game = try mac.game(in: library)
        let exe = game.appendingPathComponent("TheWolfAmongUsRemastered.exe")
        XCTAssertEqual(GameFinder.gameFolder(from: game)?.canonicalPath, game.canonicalPath)
        XCTAssertEqual(GameFinder.gameFolder(from: exe)?.canonicalPath, game.canonicalPath)
        XCTAssertEqual(GameFinder.gameFolder(from: library)?.canonicalPath, game.canonicalPath)
        XCTAssertEqual(GameFinder.gameFolder(from: mac.volumes.appendingPathComponent("Games"))?.canonicalPath, game.canonicalPath)
        XCTAssertNil(GameFinder.gameFolder(from: game.appendingPathComponent("fmod64.dll")))
        XCTAssertNil(GameFinder.gameFolder(from: mac.home))
        XCTAssertNil(GameFinder.gameFolder(from: mac.root.appendingPathComponent("missing")))
    }

    func testFindAll() throws {
        let mac = try FakeMac()
        let bottle = try mac.bottle("Steam")
        let drive = mac.volumes.appendingPathComponent("Games")
        let external = try mac.game(in: drive.appendingPathComponent("SteamLibrary"))
        try mac.drive("k", in: bottle, to: drive)
        try mac.libraryVDF(in: bottle, paths: [#"K:\SteamLibrary"#])
        let inside = try mac.game(in: bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
        let found = GameFinder.findAll(env: mac.env)
        XCTAssertEqual(Set(found.map(\.folder.canonicalPath)), [external.canonicalPath, inside.canonicalPath])
        XCTAssertTrue(found.allSatisfy { $0.bottle?.name == "Steam" })
    }
}

final class DllOverrideTests: XCTestCase {
    let reg = "WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n\n[Software\\\\Wine] 1700000000\n#time=1d9\n\"Version\"=\"win10\"\n"

    func testAddAndRemoveRoundTrip() {
        XCTAssertFalse(DllOverride.isSet(inUserReg: reg))
        let added = DllOverride.adding(toUserReg: reg, now: Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertTrue(DllOverride.isSet(inUserReg: added))
        XCTAssertTrue(added.hasPrefix(reg))
        XCTAssertTrue(added.contains("[Software\\\\Wine\\\\AppDefaults\\\\TheWolfAmongUsRemastered.exe\\\\DllOverrides] 1760000000\n#time="))
        XCTAssertTrue(added.contains("\"Version\"=\"win10\""))
        XCTAssertEqual(DllOverride.adding(toUserReg: added), added)
        let removed = DllOverride.removing(fromUserReg: added)
        XCTAssertFalse(DllOverride.isSet(inUserReg: removed))
        XCTAssertTrue(removed.contains("\"Version\"=\"win10\""))
    }

    func testFixesAWrongValueInAnExistingSection() {
        let text = reg + "\n[Software\\\\Wine\\\\AppDefaults\\\\TheWolfAmongUsRemastered.exe\\\\DllOverrides] 1\n#time=1\n\"d3d11\"=\"builtin\"\n\"dxgi\"=\"native\"\n"
        XCTAssertFalse(DllOverride.isSet(inUserReg: text))
        let fixed = DllOverride.adding(toUserReg: text)
        XCTAssertTrue(DllOverride.isSet(inUserReg: fixed))
        XCTAssertTrue(fixed.contains("\"dxgi\"=\"native\""))
        XCTAssertEqual(fixed.components(separatedBy: "\"d3d11\"").count, 2)
    }

    func testEditsUserRegWithoutWine() throws {
        let mac = try FakeMac()
        let path = try mac.bottle("Steam", userReg: reg)
        let bottle = Bottles.all(in: mac.env)[0]
        XCTAssertEqual(DllOverride.ensure(in: bottle, env: mac.env), .setInFile)
        let text = try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8)
        XCTAssertTrue(DllOverride.isSet(inUserReg: text))
        XCTAssertEqual(try String(contentsOf: path.appendingPathComponent("user.reg.wolffix-backup"), encoding: .utf8), reg)
        XCTAssertEqual(DllOverride.ensure(in: bottle, env: mac.env), .alreadySet)
        XCTAssertEqual(DllOverride.remove(from: bottle, env: mac.env), .removed)
        XCTAssertEqual(try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8), reg)
        XCTAssertFalse(mac.fm.fileExists(atPath: path.appendingPathComponent("user.reg.wolffix-backup").path))
        XCTAssertEqual(DllOverride.remove(from: bottle, env: mac.env), .notNeeded)
    }

    func testWontEditUserRegWhileWineRuns() throws {
        let mac = try FakeMac()
        let path = try mac.bottle("Steam", userReg: reg)
        mac.runner.processes = ["/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineserver"]
        XCTAssertEqual(DllOverride.ensure(in: Bottles.all(in: mac.env)[0], env: mac.env), .wineRunning)
        XCTAssertEqual(try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8), reg)
    }

    /// wineserver as `ps` shows it for the CrossOver builds seen on a real Mac (paths with spaces, -arm64/-x86 names).
    func testSeesWineserverOfEveryCrossOver() {
        let mac = { (line: String) -> Bool in
            let runner = FakeRunner()
            runner.processes = [line]
            return SystemEnvironment(home: URL(fileURLWithPath: "/tmp"), runner: runner).wineIsRunning()
        }
        XCTAssertTrue(mac("/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver/bin/wineserver-x86"))
        XCTAssertTrue(mac("/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver/bin/wineserver-arm64"))
        XCTAssertTrue(mac("/Applications/CrossOver Preview (GPTK 4.0b2).app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineserver-arm64"))
        XCTAssertTrue(mac("/Users/me/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineserver"))
        XCTAssertTrue(mac("wineserver -p"))
        XCTAssertFalse(mac(#"C:\windows\system32\services.exe"#))
        XCTAssertFalse(mac("/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winewrapper.exe --start"))
    }

    /// The app never starts Wine: the only program it runs here is ps.
    func testNeverRunsWine() throws {
        let mac = try FakeMac()
        try mac.bottle("Steam", userReg: reg)
        let bottle = Bottles.all(in: mac.env)[0]
        XCTAssertEqual(DllOverride.ensure(in: bottle, env: mac.env), .setInFile)
        XCTAssertEqual(DllOverride.remove(from: bottle, env: mac.env), .removed)
        XCTAssertEqual(mac.runner.otherCalls, [])
    }
}

final class BottleSignalTests: XCTestCase {
    /// Two bottles with Steam, game on an external drive that no Steam library lists: the
    /// bottle where the game was set up before wins.
    func testPrefersTheBottleWhereTheGameWasSetUp() throws {
        let mac = try FakeMac()
        try mac.bottle("Other")
        try mac.bottle("Steam", userReg: "WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\AppDefaults\\\\TheWolfAmongUsRemastered.exe\\\\DllOverrides] 1\n\"d3d11\"=\"native,builtin\"\n")
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Games/SteamLibrary"))
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(install.bottle?.name, "Steam")
        XCTAssertEqual(install.reason, .gameSettings)
        XCTAssertEqual(install.candidates.map(\.name), ["Other", "Steam"])
    }

    /// The bottle with a drive letter for the game's disk (Z: = / doesn't count).
    func testPrefersTheBottleWithADriveLetterForTheDisk() throws {
        let mac = try FakeMac()
        let other = try mac.bottle("Other")
        let steam = try mac.bottle("Steam")
        let drive = mac.volumes.appendingPathComponent("Games")
        let game = try mac.game(in: drive.appendingPathComponent("SteamLibrary"))
        try mac.drive("z", in: other, to: URL(fileURLWithPath: "/"))
        try mac.drive("z", in: steam, to: URL(fileURLWithPath: "/"))
        try mac.drive("k", in: steam, to: drive)
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(install.bottle?.name, "Steam")
        XCTAssertEqual(install.reason, .driveLetter)
    }

    /// Newer Steam keeps the library list in config/libraryfolders.vdf too.
    func testReadsTheConfigLibraryList() throws {
        let mac = try FakeMac()
        try mac.bottle("Other")
        let steam = try mac.bottle("Steam")
        let drive = mac.volumes.appendingPathComponent("Games")
        let game = try mac.game(in: drive.appendingPathComponent("SteamLibrary"))
        try mac.drive("k", in: steam, to: drive)
        let config = steam.appendingPathComponent("drive_c/Program Files (x86)/Steam/config")
        try mac.fm.createDirectory(at: config, withIntermediateDirectories: true)
        try "\"libraryfolders\"\n{\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"K:\\\\SteamLibrary\"\n\t}\n}\n"
            .write(to: config.appendingPathComponent("libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(install.bottle?.name, "Steam")
        XCTAssertEqual(install.reason, .steamLibrary)
    }
}


final class InstallerTests: XCTestCase {
    func testInstallStatusAndUninstall() throws {
        let mac = try FakeMac()
        let path = try mac.bottle("Steam")
        let game = try mac.game(in: path.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
        let installer = try mac.installer()
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertEqual(installer.status(of: game), .notInstalled)

        let report = try installer.install(install)
        XCTAssertEqual(report.override, .setInFile)
        XCTAssertEqual(report.notes, [])
        XCTAssertEqual(installer.status(of: game), .installed)
        XCTAssertTrue(DllOverride.isSet(inUserReg: try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8)))

        XCTAssertEqual(installer.status(of: game, bottle: install.bottle), .installed)

        // installing again changes nothing
        XCTAssertEqual(try installer.install(install).override, .alreadySet)
        XCTAssertEqual(installer.status(of: game), .installed)

        // the bottle setting gone (CrossOver reset, say): the fix isn't active, and Apply puts it back
        let userReg = path.appendingPathComponent("user.reg")
        try DllOverride.removing(fromUserReg: try String(contentsOf: userReg, encoding: .utf8)).write(to: userReg, atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.status(of: game, bottle: install.bottle), .inactive)
        XCTAssertEqual(try installer.install(install).override, .setInFile)
        XCTAssertEqual(installer.status(of: game, bottle: install.bottle), .installed)

        let removed = try installer.uninstall(install)
        XCTAssertEqual(removed.override, .removed)
        XCTAssertEqual(installer.status(of: game), .notInstalled)
        XCTAssertEqual(try mac.fm.contentsOfDirectory(atPath: game.path).sorted(), ["TheWolfAmongUsRemastered.exe", "fmod64.dll"])
        XCTAssertFalse(DllOverride.isSet(inUserReg: try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8)))
    }

    /// Another version of the fix's DLL in the folder: Update Fix replaces it.
    func testAnotherVersionOfTheFixNeedsAnUpdate() throws {
        let mac = try FakeMac()
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        let installer = try mac.installer()
        try Data("MZ ... wolffix d3d11.dll for The Wolf Among Us Remastered, older".utf8)
            .write(to: game.appendingPathComponent("d3d11.dll"))
        XCTAssertEqual(installer.status(of: game), .updateAvailable)
        let report = try installer.install(GameInstall(folder: game, bottle: nil, candidates: []))
        XCTAssertEqual(report.notes, [])
        XCTAssertEqual(installer.status(of: game), .installed)
        XCTAssertFalse(mac.fm.fileExists(atPath: game.appendingPathComponent("d3d11.dll.wolffix-backup").path))
    }

    func testKeepsAndRestoresAnotherD3D11() throws {
        let mac = try FakeMac()
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        let installer = try mac.installer()
        let install = GameInstall(folder: game, bottle: nil, candidates: [])
        try Data("someone else's d3d11".utf8).write(to: game.appendingPathComponent("d3d11.dll"))
        XCTAssertEqual(installer.status(of: game), .notInstalled)
        let report = try installer.install(install)
        XCTAssertNil(report.override)
        XCTAssertEqual(report.notes.count, 1)
        XCTAssertEqual(installer.status(of: game), .installed)
        _ = try installer.install(install)   // a reinstall keeps the first backup
        let removed = try installer.uninstall(install)
        XCTAssertEqual(removed.notes.count, 1)
        XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent("d3d11.dll")), Data("someone else's d3d11".utf8))
        XCTAssertFalse(mac.fm.fileExists(atPath: game.appendingPathComponent("d3d11.dll.wolffix-backup").path))
    }

    /// Removing the fix puts the bottle back as it was, with or without another DLL to restore.
    func testRestoresTheBottleWithAnotherD3D11() throws {
        let mac = try FakeMac()
        let path = try mac.bottle("Steam")
        let before = try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8)
        let game = try mac.game(in: path.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
        let installer = try mac.installer()
        let install = GameFinder.install(at: game, env: mac.env)
        try Data("someone else's d3d11".utf8).write(to: game.appendingPathComponent("d3d11.dll"))
        _ = try installer.install(install)
        XCTAssertEqual(try installer.uninstall(install).override, .removed)
        XCTAssertEqual(try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8), before)
        XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent("d3d11.dll")), Data("someone else's d3d11".utf8))
    }

    /// A d3d11 setting the player had before comes back; one the fix didn't make stays.
    func testRestoresAnEarlierSettingAndLeavesOnesItDidntMake() throws {
        let section = "\n[Software\\\\Wine\\\\AppDefaults\\\\TheWolfAmongUsRemastered.exe\\\\DllOverrides] 1\n#time=1\n"
        for (value, outcome) in [("\"d3d11\"=\"builtin\"", DllOverride.Outcome.setInFile), (DllOverride.valueLine, .alreadySet)] {
            let mac = try FakeMac()
            let reg = "WINE REGISTRY Version 2\n" + section + value + "\n"
            let path = try mac.bottle("Steam", userReg: reg)
            let game = try mac.game(in: path.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
            let installer = try mac.installer()
            let install = GameFinder.install(at: game, env: mac.env)
            XCTAssertEqual(try installer.install(install).override, outcome)
            XCTAssertEqual(installer.status(of: game, bottle: install.bottle), .installed)
            _ = try installer.uninstall(install)
            XCTAssertEqual(try String(contentsOf: path.appendingPathComponent("user.reg"), encoding: .utf8), reg)
            XCTAssertFalse(mac.fm.fileExists(atPath: path.appendingPathComponent("user.reg.wolffix-backup").path))
        }
    }

    /// One other DLL kept aside already: a second one is never overwritten.
    func testRefusesASecondOtherD3D11() throws {
        let mac = try FakeMac()
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        let installer = try mac.installer()
        try Data("first".utf8).write(to: game.appendingPathComponent("d3d11.dll.wolffix-backup"))
        try Data("second".utf8).write(to: game.appendingPathComponent("d3d11.dll"))
        XCTAssertThrowsError(try installer.install(GameInstall(folder: game, bottle: nil, candidates: []))) {
            XCTAssertEqual($0 as? InstallError, .twoOtherDLLs)
        }
        XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent("d3d11.dll")), Data("second".utf8))
        XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent("d3d11.dll.wolffix-backup")), Data("first".utf8))
    }

    /// If processes can't be listed, Wine and the game are assumed to be running.
    func testAssumesRunningWhenProcessesCantBeListed() throws {
        let mac = try FakeMac()
        mac.runner.psFails = true
        XCTAssertTrue(mac.env.wineIsRunning())
        XCTAssertTrue(mac.env.gameIsRunning())
    }

    /// With CrossOver running, the bottle setting can't be changed: nothing is touched.
    func testAsksToQuitCrossOverAndChangesNothing() throws {
        let mac = try FakeMac()
        let path = try mac.bottle("Steam")
        let game = try mac.game(in: path.appendingPathComponent("drive_c/Program Files (x86)/Steam"))
        let installer = try mac.installer()
        mac.runner.processes = ["/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver/bin/wineserver-x86"]
        let install = GameFinder.install(at: game, env: mac.env)
        XCTAssertThrowsError(try installer.install(install)) { XCTAssertEqual($0 as? InstallError, .quitCrossOver) }
        XCTAssertEqual(try mac.fm.contentsOfDirectory(atPath: game.path).sorted(), ["TheWolfAmongUsRemastered.exe", "fmod64.dll"])
        // once the setting is there, CrossOver may stay open for reinstalls
        mac.runner.processes = []
        _ = try installer.install(install)
        mac.runner.processes = ["/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/wineserver"]
        XCTAssertEqual(try installer.install(install).override, .alreadySet)
        XCTAssertThrowsError(try installer.uninstall(install)) { XCTAssertEqual($0 as? InstallError, .quitCrossOver) }
        XCTAssertEqual(installer.status(of: game), .installed)
    }

    func testRefusesWhileTheGameRuns() throws {
        let mac = try FakeMac()
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        mac.runner.processes = [#"M:\SteamLibrary\steamapps\common\The Wolf Among Us Remastered\TheWolfAmongUsRemastered.exe"#]
        let installer = try mac.installer()
        XCTAssertThrowsError(try installer.install(GameInstall(folder: game, bottle: nil, candidates: []))) {
            XCTAssertEqual($0 as? InstallError, .gameRunning)
        }
        XCTAssertFalse(mac.fm.fileExists(atPath: game.appendingPathComponent("d3d11.dll").path))
    }

    func testRefusesAFolderWithoutTheGame() throws {
        let mac = try FakeMac()
        let installer = try mac.installer()
        XCTAssertThrowsError(try installer.install(GameInstall(folder: mac.home, bottle: nil, candidates: []))) {
            XCTAssertEqual($0 as? InstallError, .notAGameFolder)
        }
    }

    func testReadOnlyFolder() throws {
        let mac = try FakeMac()
        let game = try mac.game(in: mac.volumes.appendingPathComponent("Ext"))
        try mac.fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: game.path)
        defer { try? mac.fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.path) }
        guard getuid() != 0 else { throw XCTSkip("root can write anywhere") }
        let installer = try mac.installer()
        XCTAssertThrowsError(try installer.install(GameInstall(folder: game, bottle: nil, candidates: []))) {
            XCTAssertEqual($0 as? InstallError, .readOnly(game.path))
        }
    }

    /// The bundled DLL is the one built from fix/ (checked against prebuilt/d3d11.dll.sha256 by build-app.sh).
    func testPrebuiltDLLIsTheFix() throws {
        let mac = try FakeMac()
        XCTAssertTrue(Installer.isFix(try mac.payload().dll))
    }
}
