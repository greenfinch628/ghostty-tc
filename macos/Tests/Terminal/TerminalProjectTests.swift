import AppKit
import Testing
@testable import Ghostty

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
        delegate.restoreLocalProject(project)
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
        let directory = try #require(research.surfaceTree.first?.pwd)
        #expect(URL(fileURLWithPath: directory).resolvingSymlinksInPath() ==
                URL(fileURLWithPath: project.windows[0].tabs[0].directory).resolvingSymlinksInPath())
        let frame = TerminalProject.visibleFrame(project.windows[0].frame, screens: NSScreen.screens.map { $0.visibleFrame })
        #expect(abs(firstWindow.frame.minX - frame.minX) < 2)
        #expect(abs(firstWindow.frame.minY - frame.minY) < 2)
        #expect(abs(firstWindow.frame.width - frame.width) < 2)
        #expect(abs(firstWindow.frame.height - frame.height) < 2)
    }

}
