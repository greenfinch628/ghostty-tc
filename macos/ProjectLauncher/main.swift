import AppKit
import UniformTypeIdentifiers

final class ProjectLauncher: NSObject, NSApplicationDelegate {
    private var choosing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.chooseProject() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !choosing { chooseProject() }
        return false
    }

    private func chooseProject() {
        guard !choosing else { return }
        choosing = true
        NSApp.activate(ignoringOtherApps: true)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ghostty-TC/Projects", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        let recent = (UserDefaults(suiteName: "local.miller.ghosttytc.singletab")?
            .stringArray(forKey: "LocalProjectPaths") ?? []).map { URL(fileURLWithPath: $0) }
        var seen = Set<URL>()
        let projects = (files + recent).map { $0.resolvingSymlinksInPath().standardizedFileURL }.filter {
            $0.pathExtension.lowercased() == "ghostty-project" &&
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && seen.insert($0).inserted
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let alert = NSAlert()
        alert.messageText = "Ghostty-TC Projects"
        alert.informativeText = "Open a saved project, or start with one terminal and one tab."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 460, height: 28))
        choices.addItem(withTitle: "Default — One Terminal")
        for file in projects {
            let name = file.deletingPathExtension().lastPathComponent
            let duplicate = projects.filter { $0.deletingPathExtension().lastPathComponent == name }.count > 1
            choices.addItem(withTitle: duplicate ? "\(name) (\(file.deletingLastPathComponent().path))" : name)
        }
        choices.addItem(withTitle: "Browse…")
        choices.setAccessibilityLabel("Project")
        alert.accessoryView = choices
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
        var components = URLComponents()
        components.scheme = "ghostty-tc-project"
        let selected = choices.indexOfSelectedItem
        if selected == 0 {
            components.host = "default"
        } else {
            let project: URL
            if selected == projects.count + 1 {
                let panel = NSOpenPanel()
                panel.title = "Open Ghostty-TC Project"
                panel.directoryURL = directory
                panel.allowedContentTypes = [.init(filenameExtension: "ghostty-project") ?? .json]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                guard panel.runModal() == .OK, let url = panel.url else { NSApp.terminate(nil); return }
                project = url
            } else {
                project = projects[selected - 1]
            }
            components.host = "open"
            components.queryItems = [.init(name: "path", value: project.path)]
        }
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Ghostty-TC.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ghostty-TC.app"),
            URL(fileURLWithPath: "/Applications/Ghostty-TC.app")
        ]
        guard let application = candidates.first(where: {
            Bundle(url: $0)?.bundleIdentifier == "local.miller.ghosttytc.singletab"
        }), let url = components.url else {
            showError("Install Ghostty-TC.app alongside this launcher or in your Applications folder.")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.environment = ["GHOSTTY_TC_EXPLICIT_LAUNCH": "1"]
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error { self.showError(error.localizedDescription) } else { NSApp.terminate(nil) }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could Not Open Ghostty-TC"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = ProjectLauncher()
app.delegate = delegate
app.setActivationPolicy(.regular)
let menu = NSMenu()
let applicationItem = NSMenuItem()
let applicationMenu = NSMenu()
applicationMenu.addItem(withTitle: "Quit Ghostty-TC Projects", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
applicationItem.submenu = applicationMenu
menu.addItem(applicationItem)
app.mainMenu = menu
app.run()
