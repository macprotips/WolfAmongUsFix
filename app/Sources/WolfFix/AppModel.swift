import AppKit
import Foundation
import WolfFixKit

/// A message shown under the game card.
struct Banner: Equatable {
    enum Kind { case success, warning, error }
    var kind: Kind
    var title: String
    var detail: String = ""
}

/// The app's state. All the work happens in WolfFixKit, off the main thread.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var game: GameInstall?
    @Published var bottleID: String?
    @Published var status: FixStatus?
    @Published var busy = false
    @Published var busyText = ""
    @Published var banner: Banner?
    /// More than one copy of the game was found: the user picks one.
    @Published var choices: [GameInstall] = []

    let env = SystemEnvironment()
    let payload: Result<Payload, Error>
    /// Screenshots: no searching, no disk access.
    let isPreview: Bool
    private let queue = DispatchQueue(label: "wolffix.work", qos: .userInitiated)
    private var searchedAtLaunch = false
    private static let rememberedKey = "BottleForGameFolder"

    init(preview: Bool = false) {
        isPreview = preview
        payload = Result { try AppModel.loadPayload() }
        if !preview, case .failure(let error) = payload {
            banner = Banner(kind: .error, title: "This copy of the app is incomplete.", detail: error.localizedDescription)
        }
    }

    static func loadPayload() throws -> Payload {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return try Payload(directory: resources.appendingPathComponent("payload"))
    }

    var bottles: [Bottle] { game?.candidates ?? [] }

    var selectedBottle: Bottle? {
        bottles.first { $0.id == bottleID }
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Apply needs a bottle, unless there are no bottles at all (then it explains the manual step).
    var canApply: Bool {
        game != nil && !busy && (selectedBottle != nil || bottles.isEmpty)
    }

    // MARK: - Finding the game

    /// Looks for the game once at launch, and picks it if there's exactly one copy.
    func searchAtLaunch() {
        guard !isPreview, !searchedAtLaunch, game == nil else { return }
        searchedAtLaunch = true
        findAutomatically(quiet: true)
    }

    func findAutomatically(quiet: Bool = false) {
        busy = true
        busyText = "Looking for The Wolf Among Us…"
        banner = nil
        let env = self.env
        queue.async {
            let found = GameFinder.findAll(env: env)
            DispatchQueue.main.async {
                self.busy = false
                if found.count == 1 {
                    self.select(found[0])
                } else if found.count > 1 {
                    self.choices = found
                } else if !quiet {
                    self.banner = Banner(kind: .warning, title: "Couldn't find The Wolf Among Us automatically.",
                                         detail: "Drag The Wolf Among Us Remastered folder into this window, or click Choose Folder.")
                }
            }
        }
    }

    /// Something dropped on the window or the app icon, or picked in the open panel.
    func open(_ url: URL) {
        busy = true
        busyText = "Checking \(url.lastPathComponent)…"
        banner = nil
        let env = self.env
        queue.async {
            let folder = GameFinder.gameFolder(from: url)
            let install = folder.map { GameFinder.install(at: $0, env: env) }
            DispatchQueue.main.async {
                self.busy = false
                if let install {
                    self.select(install)
                } else {
                    self.banner = Banner(kind: .error, title: "That isn't The Wolf Among Us folder.",
                                         detail: "Choose the folder that contains TheWolfAmongUsRemastered.exe. In Steam: right-click the game, then Manage › Browse local files.")
                }
            }
        }
    }

    /// Looks at the bottles again, after adding one or moving CrossOver's bottles folder.
    func refreshBottles() {
        if let game { open(game.folder) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose The Wolf Among Us Remastered Folder"
        panel.message = "Choose the folder that contains TheWolfAmongUsRemastered.exe."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    /// Uses the bottle the user picked for this folder before, unless the game is inside a bottle.
    func select(_ install: GameInstall) {
        choices = []
        game = install
        let remembered = (UserDefaults.standard.dictionary(forKey: Self.rememberedKey) as? [String: String])?[install.folder.path]
        if install.reason != .insideBottle, let remembered, install.candidates.contains(where: { $0.id == remembered }) {
            bottleID = remembered
        } else {
            bottleID = install.bottle?.id
        }
        refreshStatus()
    }

    /// The user picked a bottle: remember it for this game folder.
    func choose(bottleID id: String?) {
        bottleID = id
        refreshStatus()
        guard let game, let id, !isPreview else { return }
        var remembered = UserDefaults.standard.dictionary(forKey: Self.rememberedKey) as? [String: String] ?? [:]
        remembered[game.folder.path] = id
        UserDefaults.standard.set(remembered, forKey: Self.rememberedKey)
    }

    func forget() {
        game = nil
        status = nil
        banner = nil
        choices = []
    }

    func refreshStatus() {
        guard !isPreview, let game, case .success(let payload) = payload else { return }
        status = Installer(payload: payload, env: env).status(of: game.folder, bottle: selectedBottle)
    }

    // MARK: - Installing

    func apply() { run(remove: false) }
    func remove() { run(remove: true) }

    private func run(remove: Bool) {
        guard var game, case .success(let payload) = payload else { return }
        game.bottle = selectedBottle
        busy = true
        busyText = remove ? "Removing the fix…" : "Applying the fix…"
        banner = nil
        let installer = Installer(payload: payload, env: env)
        queue.async {
            let result = Result { try remove ? installer.uninstall(game) : installer.install(game) }
            DispatchQueue.main.async {
                self.busy = false
                self.refreshStatus()
                self.banner = Self.banner(for: result, removing: remove)
            }
        }
    }

    static func banner(for result: Result<InstallReport, Error>, removing: Bool) -> Banner {
        let report: InstallReport
        switch result {
        case .failure(InstallError.gameRunning):
            return Banner(kind: .warning, title: "Quit The Wolf Among Us first", detail: InstallError.gameRunning.localizedDescription)
        case .failure(InstallError.quitCrossOver):
            return Banner(kind: .warning, title: "Quit Steam and CrossOver", detail: InstallError.quitCrossOver.localizedDescription)
        case .failure(let error):
            return Banner(kind: .error, title: removing ? "Couldn't remove the fix." : "Couldn't apply the fix.",
                          detail: error.localizedDescription)
        case .success(let r):
            report = r
        }
        var notes = report.notes
        let manual = "In CrossOver, select the bottle, open Wine Configuration › Libraries, add d3d11 and set it to “Native then Builtin”."
        if removing {
            return Banner(kind: .success, title: "The fix was removed.",
                          detail: (["The game is back to how it was."] + notes).joined(separator: " "))
        }
        switch report.override {
        case .failed(let reason)?:
            notes.insert("The fix is in the game folder, but Wine couldn't be set to load it (\(reason)). Do it once by hand: \(manual)", at: 0)
            return Banner(kind: .warning, title: "One more step", detail: notes.joined(separator: " "))
        case .wineRunning?:
            notes.insert("Quit CrossOver, then click Apply Fix again.", at: 0)
            return Banner(kind: .warning, title: "One more step", detail: notes.joined(separator: " "))
        case nil:
            notes.insert("No CrossOver bottle was found, so Wine wasn't set to load it. If the fix doesn't take effect: \(manual)", at: 0)
            return Banner(kind: .warning, title: "The fix was copied", detail: notes.joined(separator: " "))
        default:
            notes.insert("Start the game from CrossOver as usual.", at: 0)
            return Banner(kind: .success, title: "The fix is applied.", detail: notes.joined(separator: " "))
        }
    }

    func showInFinder() {
        guard let game else { return }
        NSWorkspace.shared.activateFileViewerSelecting([game.folder.appendingPathComponent(GameFinder.exeName)])
    }
}
