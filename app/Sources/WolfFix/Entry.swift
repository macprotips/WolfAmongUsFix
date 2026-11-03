import AppKit
import SwiftUI
import WolfFixKit

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            exit(SelfTest.run())
        }
        if let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count {
            exit(Snapshots.run(into: URL(fileURLWithPath: args[i + 1])))
        }
        WolfFixApp.main()
    }
}

struct WolfFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Wolf Among Us Trail Fix", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Link("Wolf Among Us Trail Fix Help",
                     destination: URL(string: "https://github.com/macprotips/WolfAmongUsFix")!)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A folder dropped on the app's icon (Dock or Finder).
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            AppModel.shared.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// `--selftest`: checks the bundled d3d11.dll, then does a full install/remove round trip in a
/// temporary folder (with a d3d11.dll of someone else's that must come back). Used on the built app.
enum SelfTest {
    static func run() -> Int32 {
        do {
            let payload = try AppModel.loadPayload()
            print("payload: \(payload.dll.path)")
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("wolffix-selftest-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: work) }
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: work.appendingPathComponent(GameFinder.exeName))
            let other = Data("someone else's d3d11.dll".utf8)
            try other.write(to: work.appendingPathComponent("d3d11.dll"))

            let installer = Installer(payload: payload, env: SystemEnvironment())
            let install = GameInstall(folder: work, bottle: nil, candidates: [])
            _ = try installer.install(install)
            guard installer.status(of: work) == .installed else {
                print("FAIL: status after install is \(installer.status(of: work))")
                return 1
            }
            _ = try installer.uninstall(install)
            guard installer.status(of: work) == .notInstalled,
                  try Data(contentsOf: work.appendingPathComponent("d3d11.dll")) == other else {
                print("FAIL: removing the fix didn't put the folder back")
                return 1
            }
            print("selftest ok")
            return 0
        } catch {
            print("FAIL: \(error.localizedDescription)")
            return 1
        }
    }
}
