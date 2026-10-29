import AppKit
import Testing
@testable import Ghostty

@Suite(.serialized)
struct TerminalProjectTests {
    private func sample() -> TerminalProject {
        let folder = FileManager.default.temporaryDirectory.path
        return TerminalProject(windows: [
            .init(frame: CGRect(x: 10, y: 20, width: 800, height: 600), selectedTab: 1, tabs: [
                .init(directory: folder, title: "Research", color: .blue, automaticColor: false),
                .init(directory: "/", title: nil, color: .red, automaticColor: true)
            ]),
            .init(frame: CGRect(x: 850, y: 30, width: 700, height: 500), selectedTab: 0, tabs: [
                .init(directory: folder, title: "Other window", color: .teal, automaticColor: false)
            ])
        ])
    }

    @Test func roundTripMultipleWindows() throws {
        let project = sample()
        let data = try JSONEncoder().encode(project)
        let loaded = try JSONDecoder().decode(TerminalProject.self, from: data)
        try loaded.validate()
        #expect(loaded.windows.count == 2)
        #expect(loaded.windows[0].tabs.count == 2)
        #expect(loaded.windows[0].selectedTab == 1)
        #expect(loaded.windows[0].frame == project.windows[0].frame)
        #expect(loaded.windows[0].tabs[0].title == "Research")
        #expect(loaded.windows[0].tabs[0].color == .blue)
        #expect(!loaded.windows[0].tabs[0].automaticColor)
        #expect(loaded.windows[0].tabs[1].title == nil)
        #expect(loaded.windows[0].tabs[1].automaticColor)
        #expect(loaded.windows[1].tabs[0].directory == project.windows[1].tabs[0].directory)
    }

    @Test func rejectsMissingFolderBeforeOpening() {
        var project = sample()
        project.windows[1].tabs[0].directory = "/missing-project-folder-" + UUID().uuidString
        #expect(throws: (any Error).self) { try project.validate() }
    }

    @Test func rejectsInvalidFormatAndSelection() {
        var project = sample()
        project.version = 2
        #expect(throws: (any Error).self) { try project.validate() }
        project.version = 1
        project.windows[0].selectedTab = 99
        #expect(throws: (any Error).self) { try project.validate() }
        project = sample()
        project.windows = []
        #expect(throws: (any Error).self) { try project.validate() }
    }

    @Test func keepsConnectedScreenPlacement() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        let saved = CGRect(x: -1800, y: 100, width: 800, height: 600)
        #expect(TerminalProject.visibleFrame(saved, screens: screens) == saved)
    }

    @Test func recoversDisconnectedMonitorAndOversizedWindow() {
        let screen = CGRect(x: 0, y: 30, width: 1440, height: 870)
        let saved = CGRect(x: -1800, y: 100, width: 2000, height: 1200)
        #expect(TerminalProject.visibleFrame(saved, screens: [screen]) == screen)
    }
    @Test @MainActor func restoresSeparateWindowsAndTabs() async throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        let menus = NSApp.mainMenu?.items.compactMap { $0.submenu } ?? []
        #expect(menus.contains { $0.items.contains { $0.title == "Save Project…" } })
        #expect(menus.contains { $0.items.contains { $0.title == "Open Project…" } })
        let existing = Set(TerminalController.all.map { ObjectIdentifier($0) })
        defer {
            for controller in TerminalController.all where !existing.contains(ObjectIdentifier(controller)) {
                controller.closeTabImmediately(registerRedo: false)
            }
        }
        let project = sample()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Dock Test.ghostty-project")
        try JSONEncoder().encode(project).write(to: url)
        let previousPaths = UserDefaults.ghostty.object(forKey: "LocalProjectPaths")
        defer { UserDefaults.ghostty.set(previousPaths, forKey: "LocalProjectPaths") }
        let dock = try #require(delegate.applicationDockMenu(NSApp))
        #expect(dock.items.contains { $0.title == "Open Project…" })
        #expect(TerminalController.all.count == existing.count)
        #expect(delegate.application(NSApp, openFile: url.path))
        try await Task.sleep(for: .seconds(2))
        let created = TerminalController.all.filter { !existing.contains(ObjectIdentifier($0)) }
        #expect(created.count == 3)
        let research = try #require(created.first { $0.titleOverride == "Research" })
        let other = try #require(created.first { $0.titleOverride == "Other window" })
        let firstWindow = try #require(research.window as? TerminalWindow)
        let otherWindow = try #require(other.window as? TerminalWindow)
        #expect(firstWindow.tabGroup?.windows.count == 2)
        #expect(otherWindow.tabGroup?.windows.count ?? 1 == 1)
        #expect(firstWindow.tabGroup !== otherWindow.tabGroup || firstWindow.tabGroup == nil)
        #expect(firstWindow.tabColor == .blue)
        #expect(!firstWindow.usesAutomaticTabColor)
        let ordered = try #require(firstWindow.tabGroup?.windows)
        #expect(ordered.first === firstWindow)
        #expect(firstWindow.tabGroup?.selectedWindow === ordered[1])
        let snapshot = try delegate.captureLocalProject()
        let captured = try #require(snapshot.windows.first { $0.tabs.first?.title == "Research" })
        #expect(captured.tabs.count == 2)
        #expect(captured.selectedTab == 1)
        #expect(captured.tabs[0].color == .blue)
        #expect(!captured.tabs[0].automaticColor)
        #expect(snapshot.windows.contains { $0.tabs.first?.title == "Other window" })
        var launch = URLComponents()
        launch.scheme = "ghostty-tc-project"
        launch.host = "open"
        launch.queryItems = [.init(name: "path", value: url.path)]
        delegate.application(NSApp, open: [try #require(launch.url)])
        try await Task.sleep(for: .seconds(1))
        #expect(TerminalController.all.count == existing.count + 6)
        #expect(delegate.application(NSApp, openFile: url.path))
        try await Task.sleep(for: .seconds(1))
        #expect(TerminalController.all.count == existing.count + 9)
        #expect(NSDocumentController.shared.recentDocumentURLs.contains {
            $0.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
        })
        let directory = try #require(research.surfaceTree.first?.pwd)
        #expect(URL(fileURLWithPath: directory).resolvingSymlinksInPath() ==
                URL(fileURLWithPath: project.windows[0].tabs[0].directory).resolvingSymlinksInPath())
        let frame = TerminalProject.visibleFrame(project.windows[0].frame, screens: NSScreen.screens.map { $0.visibleFrame })
        #expect(abs(firstWindow.frame.minX - frame.minX) < 2)
        #expect(abs(firstWindow.frame.minY - frame.minY) < 2)
        #expect(abs(firstWindow.frame.width - frame.width) < 2)
        #expect(abs(firstWindow.frame.height - frame.height) < 2)
    }

    @Test func savedProjectListFindsExistingFilesAndDropsDuplicates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = folder.appendingPathComponent("Alpha.ghostty-project")
        let elsewhere = folder.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let remoteFile = elsewhere.appendingPathComponent("Beta.ghostty-project")
        let missing = folder.appendingPathComponent("Missing.ghostty-project")
        let unrelated = folder.appendingPathComponent("Notes.txt")
        let directory = folder.appendingPathComponent("NotAFile.ghostty-project", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in [local, remoteFile, unrelated] { try Data().write(to: url) }
        #expect(TerminalProject.savedProjectURLs(in: folder, recent: [local, remoteFile, missing, unrelated]) == [local, remoteFile].map { $0.resolvingSymlinksInPath() })
        try FileManager.default.removeItem(at: local)
        #expect(TerminalProject.savedProjectURLs(in: folder, recent: [local, remoteFile]) == [remoteFile.resolvingSymlinksInPath()])
    }

    @Test func parsesLauncherRequestsWithoutLosingPathCharacters() throws {
        let file = URL(fileURLWithPath: "/tmp/Project #1 & 50%.ghostty-project")
        var components = URLComponents()
        components.scheme = "ghostty-tc-project"
        components.host = "open"
        components.queryItems = [.init(name: "path", value: file.path)]
        let request = try TerminalProject.launchRequest(from: #require(components.url))
        #expect(request == .project(file))
        #expect(try TerminalProject.launchRequest(from: #require(URL(string: "ghostty-tc-project://default"))) == .defaultTerminal)
        for invalid in ["https://default", "ghostty-tc-project://open", "ghostty-tc-project://open?path=relative.ghostty-project",
                        "ghostty-tc-project://open?path=/tmp/script.sh"] {
            #expect(throws: (any Error).self) {
                try TerminalProject.launchRequest(from: #require(URL(string: invalid)))
            }
        }
    }

    @Test @MainActor func launcherDefaultAddsExactlyOneStandaloneTab() async throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        let before = Set(TerminalController.all.map { ObjectIdentifier($0) })
        defer {
            for controller in TerminalController.all where !before.contains(ObjectIdentifier(controller)) {
                controller.closeTabImmediately(registerRedo: false)
            }
        }
        delegate.application(NSApp, open: [try #require(URL(string: "ghostty-tc-project://default"))])
        try await Task.sleep(for: .seconds(2))
        let added = TerminalController.all.filter { !before.contains(ObjectIdentifier($0)) }
        #expect(added.count == 1)
        let controller = try #require(added.first)
        #expect(controller.window?.tabGroup?.windows.count ?? 1 == 1)
        #expect(!controller.surfaceTree.isSplit)
        let directory = try #require(controller.surfaceTree.first?.pwd)
        #expect(URL(fileURLWithPath: directory).resolvingSymlinksInPath() ==
                FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath())
    }

}
