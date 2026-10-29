#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Explicit local workspace snapshots, separate from automatic quit restoration.
struct TerminalProject: Codable {
    var version = 1
    var windows: [Window]

    struct Window: Codable {
        var frame: CGRect
        var selectedTab: Int
        var tabs: [Tab]
    }

    struct Tab: Codable {
        var directory: String
        var title: String?
        var color: TerminalTabColor
        var automaticColor: Bool
    }

    enum ProjectError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let message): return message
            }
        }
    }

    func validate() throws {
        guard version == 1 else {
            throw ProjectError.invalid("This project uses an unsupported format version.")
        }
        guard !windows.isEmpty, windows.count <= 50 else {
            throw ProjectError.invalid("A project must contain between 1 and 50 windows.")
        }
        for window in windows {
            let frame = window.frame
            guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }),
                  frame.width > 0, frame.height > 0,
                  !window.tabs.isEmpty, window.tabs.count <= 100,
                  window.tabs.indices.contains(window.selectedTab) else {
                throw ProjectError.invalid("The project contains an invalid window or tab selection.")
            }
            for tab in window.tabs {
                var isDirectory: ObjCBool = false
                guard tab.directory.hasPrefix("/"), !tab.directory.contains("\0"),
                      FileManager.default.fileExists(atPath: tab.directory, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw ProjectError.invalid("The local folder does not exist: \(tab.directory)")
                }
            }
        }
    }

    /// Keep a saved frame on a connected screen; resize only when it cannot fit.
    static func visibleFrame(_ saved: CGRect, screens: [CGRect]) -> CGRect {
        guard let screen = screens.max(by: {
            let lhs = $0.intersection(saved)
            let rhs = $1.intersection(saved)
            return (lhs.isNull ? 0 : lhs.width * lhs.height) < (rhs.isNull ? 0 : rhs.width * rhs.height)
        }) else { return saved }
        let width = min(saved.width, screen.width)
        let height = min(saved.height, screen.height)
        return CGRect(
            x: min(max(saved.minX, screen.minX), screen.maxX - width),
            y: min(max(saved.minY, screen.minY), screen.maxY - height),
            width: width, height: height)
    }
}

extension AppDelegate {
    func installProjectMenu() {
        guard let menu = NSApp.mainMenu?.items.compactMap({ $0.submenu }).first(where: { menu in
            menu.items.contains { $0.action == #selector(TerminalController.newWindow(_:)) }
        }) else { return }
        let save = NSMenuItem(title: "Save Project…", action: #selector(saveLocalProject(_:)), keyEquivalent: "")
        let open = NSMenuItem(title: "Open Project…", action: #selector(openLocalProject(_:)), keyEquivalent: "")
        save.target = self
        open.target = self
        menu.insertItem(.separator(), at: 2)
        menu.insertItem(save, at: 3)
        menu.insertItem(open, at: 4)
    }

    private var projectDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ghostty-TC/Projects", isDirectory: true)
    }

    @objc func saveLocalProject(_ sender: Any?) {
        do {
            let project = try captureLocalProject()
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            let panel = NSSavePanel()
            panel.title = "Save Project"
            panel.message = "Save all terminal windows, tab order, names, colors, and local folders. Reopening starts fresh local shells; SSH connections and running programs are not saved."
            panel.nameFieldStringValue = "My Project.ghostty-project"
            panel.directoryURL = projectDirectory
            panel.allowedContentTypes = [.init(filenameExtension: "ghostty-project") ?? .json]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(project).write(to: url, options: .atomic)
        } catch { NSApp.presentError(error) }
    }

    @objc func openLocalProject(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.message = "Open saved local terminals in additional windows."
        panel.directoryURL = projectDirectory
        panel.allowedContentTypes = [.init(filenameExtension: "ghostty-project") ?? .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 5_000_000 else {
                throw TerminalProject.ProjectError.invalid("This project file is too large.")
            }
            let project = try JSONDecoder().decode(TerminalProject.self, from: data)
            try project.validate()
            restoreLocalProject(project)
        } catch { NSApp.presentError(error) }
    }

    func captureLocalProject() throws -> TerminalProject {
        var seen = Set<ObjectIdentifier>()
        var groups: [TerminalProject.Window] = []
        for controller in TerminalController.all {
            guard let window = controller.window, !seen.contains(ObjectIdentifier(window)) else { continue }
            let windows = window.tabGroup?.windows ?? [window]
            var tabs: [TerminalProject.Tab] = []
            for tab in windows {
                seen.insert(ObjectIdentifier(tab))
                guard let controller = tab.windowController as? TerminalController,
                      let terminal = tab as? TerminalWindow else { continue }
                guard !controller.surfaceTree.isSplit, let surface = controller.surfaceTree.first else {
                    throw TerminalProject.ProjectError.invalid("Saving split panes is not supported yet. Use one terminal pane per tab for this first version.")
                }
                guard !surface.title.hasPrefix("SSH: "), let directory = surface.pwd else {
                    throw TerminalProject.ProjectError.invalid("A tab has no known local folder or is marked as an SSH tab. This first version saves local terminals only.")
                }
                tabs.append(.init(directory: directory, title: controller.titleOverride,
                                  color: terminal.tabColor, automaticColor: terminal.usesAutomaticTabColor))
            }
            guard !tabs.isEmpty else { continue }
            let selected = window.tabGroup?.selectedWindow ?? window
            groups.append(.init(frame: selected.frame,
                                selectedTab: windows.firstIndex(of: selected) ?? 0, tabs: tabs))
        }
        let project = TerminalProject(windows: groups)
        try project.validate()
        return project
    }

    func restoreLocalProject(_ project: TerminalProject) {
        var opened: [(TerminalProject.Window, [TerminalController])] = []
        for saved in project.windows {
            var controllers: [TerminalController] = []
            for tab in saved.tabs {
                var config = Ghostty.SurfaceConfiguration()
                config.workingDirectory = tab.directory
                let controller = TerminalController(ghostty, withBaseConfig: config)
                guard let window = controller.window as? TerminalWindow else { continue }
                window.tabbingMode = .disallowed
                controller.titleOverride = tab.title
                window.usesAutomaticTabColor = false
                window.tabColor = tab.color
                window.usesAutomaticTabColor = tab.automaticColor
                controllers.append(controller)
            }
            opened.append((saved, controllers))
        }
        // AppKit and SwiftUI finish initial window sizing on the next run-loop turn.
        DispatchQueue.main.async {
            for (saved, controllers) in opened {
                guard let first = controllers.first, let firstWindow = first.window else { continue }
                first.showWindow(nil)
                for controller in controllers.dropFirst() {
                    guard let window = controller.window else { continue }
                    window.tabbingMode = .preferred
                    (firstWindow.tabGroup?.windows.last ?? firstWindow)
                        .addTabbedWindowSafely(window, ordered: .above)
                    controller.showWindow(nil)
                }
                firstWindow.tabbingMode = .preferred
                let frame = TerminalProject.visibleFrame(saved.frame, screens: NSScreen.screens.map { $0.visibleFrame })
                for controller in controllers { controller.window?.setFrame(frame, display: true) }
                let selected = controllers[min(saved.selectedTab, controllers.count - 1)]
                selected.window?.makeKeyAndOrderFront(nil)
                if let surface = selected.focusedSurface {
                    Ghostty.moveFocus(to: surface)
                }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

#endif
