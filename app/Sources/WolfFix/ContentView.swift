import AppKit
import SwiftUI
import WolfFixKit

enum Metrics {
    static let windowWidth: CGFloat = 500
    static let edge: CGFloat = 24
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let labelWidth: CGFloat = 52
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false
    @AppStorage("shownBottleSupportNote") private var shownSupportNote = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Header(version: model.version)
                content
                if let banner = model.banner {
                    BannerView(banner: banner)
                        .transition(.opacity)
                }
            }
            .padding(Metrics.edge)

            if model.game != nil {
                Divider()
                FooterBar(model: model)
                    .padding(.horizontal, Metrics.edge)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: Metrics.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if dropTargeted && model.game != nil {
                DropOverlay()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
        .animation(.easeInOut(duration: 0.2), value: model.game)
        .onAppear { model.searchAtLaunch() }
        .alert("Before you start", isPresented: Binding(get: { !shownSupportNote && !model.isPreview },
                                                        set: { if !$0 { shownSupportNote = true } })) {
            Button("OK") { shownSupportNote = true }
        } message: {
            Text("This fix changes a setting in your CrossOver bottle. CodeWeavers can't support CrossOver while the fix is applied. Before contacting CrossOver support, click Remove Fix to put the bottle back as it was.")
        }
    }

    @ViewBuilder private var content: some View {
        if let game = model.game {
            GameCard(model: model, game: game)
        } else if !model.choices.isEmpty {
            ChoiceList(model: model)
        } else {
            DropZone(model: model, targeted: dropTargeted)
        }
    }
}

// MARK: - Header

struct Header: View {
    let version: String
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("Wolf Among Us Trail Fix")
                .font(.system(size: 18, weight: .semibold))
            Spacer(minLength: 0)
            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("How it works")
            .accessibilityLabel("How it works")
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                AboutFix(version: version)
            }
        }
    }
}

// MARK: - Card

/// The rounded container used for the game, the drop zone and the choice list.
struct Card<Content: View>: View {
    var dashed = false
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(highlighted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor : Color(nsColor: .separatorColor),
                                  style: StrokeStyle(lineWidth: highlighted ? 2 : 1, dash: dashed ? [6, 4] : []))
            )
    }
}

struct GameCard: View {
    @ObservedObject var model: AppModel
    let game: GameInstall

    var body: some View {
        Card {
            VStack(spacing: 0) {
                gameRow
                Divider().padding(.leading, Metrics.cardPadding)
                bottleRow
                Divider().padding(.leading, Metrics.cardPadding)
                CardRow(label: "Status") { StatusView(status: model.status) }
            }
        }
    }

    private var gameRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(GameFinder.folderName)
                    .font(.system(size: 13, weight: .semibold))
                Button(game.folder.deletingLastPathComponent().abbreviatedPath, action: model.showInFinder)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Show in Finder")
            }
            Spacer(minLength: 12)
            Button("Change…") { model.forget() }
                .disabled(model.busy)
        }
        .padding(Metrics.cardPadding)
    }

    private var bottleRow: some View {
        CardRow(label: "Bottle") {
            if model.bottles.isEmpty {
                Text("No CrossOver bottles found")
                    .foregroundStyle(.secondary)
                refreshButton
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Picker("Bottle", selection: Binding(get: { model.bottleID }, set: { model.choose(bottleID: $0) })) {
                            if model.bottleID == nil {
                                Text("Choose…").tag(String?.none)
                            }
                            ForEach(model.bottles) { bottle in
                                Text(bottle.name).tag(Optional(bottle.id))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(model.busy)
                        refreshButton
                    }
                    if model.selectedBottle == nil {
                        Label("Choose the bottle you run Steam in.", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            model.refreshBottles()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(model.busy)
        .help("Look for bottles again")
        .accessibilityLabel("Look for bottles again")
    }
}

/// A labelled row inside a card: label column on the left, content on the right.
struct CardRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: Metrics.labelWidth, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }
}

struct StatusView: View {
    let status: FixStatus?

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
    }

    private var title: String {
        switch status {
        case .installed?: return "Installed"
        case .updateAvailable?: return "Update available"
        case .inactive?: return "Not active in this bottle"
        case .notInstalled?: return "Not installed"
        case nil: return "Checking…"
        }
    }

    private var color: Color {
        switch status {
        case .installed?: return .green
        case .updateAvailable?, .inactive?: return .orange
        default: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}

// MARK: - Drop zone and choices

struct DropZone: View {
    @ObservedObject var model: AppModel
    let targeted: Bool

    var body: some View {
        Card(dashed: true, highlighted: targeted) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(targeted ? Color.accentColor : .secondary)
                    .padding(.bottom, 4)
                Text("Drop the game folder here")
                    .font(.system(size: 14, weight: .semibold))
                Text("In Steam, right-click the game and choose Manage › Browse local files.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                Group {
                    if model.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(model.busyText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Button("Choose Folder…") { model.chooseFolder() }
                            Button("Find Automatically") { model.findAutomatically() }
                        }
                    }
                }
                .frame(height: 24)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .padding(.horizontal, Metrics.cardPadding)
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

struct ChoiceList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The game is in more than one place. Which one do you play?")
                .font(.system(size: 13, weight: .semibold))
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(model.choices.enumerated()), id: \.element.folder) { index, install in
                        if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                        ChoiceRow(install: install) { model.select(install) }
                    }
                }
            }
            Button("Choose a Different Folder…") { model.chooseFolder() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }
}

struct ChoiceRow: View {
    let install: GameInstall
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(install.folder.abbreviatedPath)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(install.bottle.map { "Bottle: \($0.name)" } ?? "Bottle not known yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 30, weight: .light))
                Text("Drop to use this folder")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
        }
        .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 3))
        .allowsHitTesting(false)
    }
}

// MARK: - Banner

struct BannerView: View {
    let banner: Banner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(.system(size: 13, weight: .semibold))
                if !banner.detail.isEmpty {
                    Text(banner.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.30)))
    }

    private var color: Color {
        switch banner.kind {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var symbol: String {
        switch banner.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Footer

/// One main action for the current status; Remove Fix whenever the fix is in the folder.
struct FooterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.busy {
                ProgressView().controlSize(.small)
                Text(model.busyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let status = model.status, status != .notInstalled {
                Button("Remove Fix", action: model.remove)
                    .controlSize(.large)
                    .disabled(model.busy)
            }
            if let title = applyTitle {
                Button(action: model.apply) {
                    Text(title).frame(minWidth: 88)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canApply)
            }
        }
        .frame(minHeight: 32)
    }

    private var applyTitle: String? {
        switch model.status {
        case .installed?: return nil
        case .updateAvailable?: return "Update Fix"
        default: return "Apply Fix"
        }
    }
}

struct AboutFix: View {
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
                .font(.system(size: 13, weight: .semibold))
            Text("With anti-aliasing on, the game asks for 8x MSAA. Apple GPUs don't have 8x, so the graphics layer gives it 4x instead, but the game's shaders still read 8 samples per pixel. The missing ones read as black, which keeps dark leftovers of old frames on screen as trails behind anything that moves.")
            Text("The fix puts a small d3d11.dll in the game folder that makes those shaders read the 4 samples that exist, and tells Wine to load it. The game and CrossOver themselves aren't changed, and Remove Fix undoes everything.")
            Divider().padding(.vertical, 2)
            HStack {
                Link("Source code and details", destination: URL(string: "https://github.com/macprotips/WolfAmongUsFix")!)
                Spacer()
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
            }
            Text("Not affiliated with the makers or publishers of The Wolf Among Us.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 340)
        .padding(16)
    }
}

extension URL {
    /// The path with the home folder shown as ~.
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
