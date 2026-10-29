import Testing
@testable import Ghostty
@testable import GhosttyKit
import SwiftUI

@Suite
struct ConfigTests {
    // MARK: - Boolean Properties

    @Test func initialWindowDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.initialWindow == true)
    }

    @Test func initialWindowSetToFalse() throws {
        let config = try TemporaryConfig("initial-window = false")
        #expect(config.initialWindow == false)
    }

    @Test func quitAfterLastWindowClosedDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.shouldQuitAfterLastWindowClosed == false)
    }

    @Test func quitAfterLastWindowClosedSetToTrue() throws {
        let config = try TemporaryConfig("quit-after-last-window-closed = true")
        #expect(config.shouldQuitAfterLastWindowClosed == true)
    }

    @Test func windowStepResizeDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowStepResize == false)
    }

    @Test func focusFollowsMouseDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.focusFollowsMouse == false)
    }

    @Test func focusFollowsMouseSetToTrue() throws {
        let config = try TemporaryConfig("focus-follows-mouse = true")
        #expect(config.focusFollowsMouse == true)
    }

    @Test func windowDecorationsDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowDecorations == true)
    }

    @Test func windowDecorationsNone() throws {
        let config = try TemporaryConfig("window-decoration = none")
        #expect(config.windowDecorations == false)
    }

    @Test func macosWindowShadowDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosWindowShadow == true)
    }

    @Test func maximizeDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.maximize == false)
    }

    @Test func maximizeSetToTrue() throws {
        let config = try TemporaryConfig("maximize = true")
        #expect(config.maximize == true)
    }

    // MARK: - String / Optional String Properties

    @Test func windowShowTabBarDefaultsToAuto() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowShowTabBar == "auto")
    }

    @Test(arguments: ["always", "auto", "never"])
    func windowShowTabBarValues(value: String) throws {
        let config = try TemporaryConfig("window-show-tab-bar = \(value)")
        #expect(config.windowShowTabBar == value)
    }

    @Test func titleDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.title == nil)
    }

    @Test func titleSetToCustomValue() throws {
        let config = try TemporaryConfig("title = My Terminal")
        #expect(config.title == "My Terminal")
    }

    @Test func windowTitleFontFamilyDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowTitleFontFamily == nil)
    }

    @Test func windowTitleFontFamilySetToValue() throws {
        let config = try TemporaryConfig("window-title-font-family = Menlo")
        #expect(config.windowTitleFontFamily == "Menlo")
    }

    // MARK: - Enum Properties

    @Test func macosTitlebarStyleDefaultsToTransparent() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosTitlebarStyle == .transparent)
    }

    @Test(arguments: [
        ("native", Ghostty.Config.MacOSTitlebarStyle.native),
        ("transparent", Ghostty.Config.MacOSTitlebarStyle.transparent),
        ("tabs", Ghostty.Config.MacOSTitlebarStyle.tabs),
        ("hidden", Ghostty.Config.MacOSTitlebarStyle.hidden),
    ])
    func macosTitlebarStyleValues(raw: String, expected: Ghostty.Config.MacOSTitlebarStyle) throws {
        let config = try TemporaryConfig("macos-titlebar-style = \(raw)")
        #expect(config.macosTitlebarStyle == expected)
    }

    @Test func resizeOverlayDefaultsToAfterFirst() throws {
        let config = try TemporaryConfig("")
        #expect(config.resizeOverlay == .after_first)
    }

    @Test(arguments: [
        ("always", Ghostty.Config.ResizeOverlay.always),
        ("never", Ghostty.Config.ResizeOverlay.never),
        ("after-first", Ghostty.Config.ResizeOverlay.after_first),
    ])
    func resizeOverlayValues(raw: String, expected: Ghostty.Config.ResizeOverlay) throws {
        let config = try TemporaryConfig("resize-overlay = \(raw)")
        #expect(config.resizeOverlay == expected)
    }

    @Test func resizeOverlayPositionDefaultsToCenter() throws {
        let config = try TemporaryConfig("")
        #expect(config.resizeOverlayPosition == .center)
    }

    @Test func macosIconDefaultsToOfficial() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosIcon == .official)
    }

    @Test func macosIconFrameDefaultsToAluminum() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosIconFrame == .aluminum)
    }

    @Test func macosWindowButtonsDefaultsToVisible() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosWindowButtons == .visible)
    }

    @Test func scrollbarDefaultsToSystem() throws {
        let config = try TemporaryConfig("")
        #expect(config.scrollbar == .system)
    }

    @Test func scrollbarSetToNever() throws {
        let config = try TemporaryConfig("scrollbar = never")
        #expect(config.scrollbar == .never)
    }

    // MARK: - Numeric Properties

    @Test func backgroundOpacityDefaultsToOne() throws {
        let config = try TemporaryConfig("")
        #expect(config.backgroundOpacity == 1.0)
    }

    @Test func backgroundOpacitySetToCustom() throws {
        let config = try TemporaryConfig("background-opacity = 0.5")
        #expect(config.backgroundOpacity == 0.5)
    }

    @Test func windowPositionDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowPositionX == nil)
        #expect(config.windowPositionY == nil)
    }

    // MARK: - Config Loading

    @Test func loadedIsTrueForValidConfig() throws {
        let config = try TemporaryConfig("")
        #expect(config.loaded == true)
    }

    @Test func unfinalizedConfigIsLoaded() throws {
        let config = try TemporaryConfig("", finalize: false)
        #expect(config.loaded == true)
    }

    @Test func defaultConfigIsLoaded() throws {
        let config = try TemporaryConfig("")
        #expect(config.optionalAutoUpdateChannel != nil) // release or tip
        let config1 = try TemporaryConfig("", finalize: false)
        #expect(config1.optionalAutoUpdateChannel == nil)
    }

    @Test func errorsEmptyForValidConfig() throws {
        let config = try TemporaryConfig("")
        #expect(config.errors.isEmpty)
    }

    @Test func errorsReportedForInvalidConfig() throws {
        let config = try TemporaryConfig("not-a-real-key = value")
        #expect(!config.errors.isEmpty)
    }

    // MARK: - Multiple Config Lines

    @Test func multipleConfigValues() throws {
        let config = try TemporaryConfig("""
        initial-window = false
        quit-after-last-window-closed = true
        maximize = true
        focus-follows-mouse = true
        """)
        #expect(config.initialWindow == false)
        #expect(config.shouldQuitAfterLastWindowClosed == true)
        #expect(config.maximize == true)
        #expect(config.focusFollowsMouse == true)
    }
}

/// Create a temporary config file and delete it when this is deallocated
class TemporaryConfig: Ghostty.Config {
    let temporaryFile: URL

    init(_ configText: String, finalize: Bool = true) throws {
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghostty")
        try configText.write(to: temporaryFile, atomically: true, encoding: .utf8)
        self.temporaryFile = temporaryFile
        super.init(config: Self.loadConfig(at: temporaryFile.path(), finalize: finalize))
    }

    var optionalAutoUpdateChannel: Ghostty.AutoUpdateChannel? {
        guard let config = self.config else { return nil }
        var v: UnsafePointer<Int8>?
        let key = "auto-update-channel"
        guard ghostty_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
        guard let ptr = v else { return nil }
        let str = String(cString: ptr)
        return Ghostty.AutoUpdateChannel(rawValue: str)
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryFile)
    }
}

@Suite struct TerminalHostColorsTests {
    @Test func explicitHostMapping() {
        let mapping = TerminalHostColors(contents: "# SSH hosts\nscopuli=orange\nother=invalid\n")
        #expect(mapping.color(forTitle: "SSH: scopuli") == .orange)
        #expect(mapping.color(forTitle: "SSH: SCOPULI") == .orange)
        #expect(mapping.color(forTitle: "SSH: rocinante") == .none)
        #expect(mapping.color(forTitle: "editing scopuli.txt") == .none)
        #expect(mapping.color(forTitle: "SSH: scopuli-other") == .none)
    }
}

@Suite @MainActor struct AutomaticTabColorTests {
    @Test func manualChoiceSurvivesTitleChanges() {
        let window = TerminalWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.usesAutomaticTabColor = false
        window.tabColor = .blue
        window.title = "SSH: unconfigured-host"
        #expect(window.tabColor == .blue)
        window.title = "Local shell"
        #expect(window.tabColor == .blue)
        window.usesAutomaticTabColor = true
        #expect(window.tabColor == TerminalHostColors.load().color(forTitle: "Local shell"))
        window.orderOut(nil)
    }
}

@Suite struct LocalHostColorTests {
    @Test func localFallbackDoesNotOverrideExplicitSSHHost() {
        let mapping = TerminalHostColors(contents: "miller=blue\nscopuli=orange\n")
        #expect(mapping.color(forTitle: "~", localHost: "miller") == .blue)
        #expect(mapping.color(forTitle: "vim", localHost: "MILLER.local") == .blue)
        #expect(mapping.color(forTitle: "SSH: scopuli", localHost: "miller") == .orange)
        #expect(mapping.color(forTitle: "SSH: unknown", localHost: "miller") == .none)
        #expect(mapping.color(forTitle: "~", localHost: "other") == .none)
    }
}

@Suite @MainActor struct TabSelectionColorTests {
    @Test func everyHueHasDistinctSelectionAndReadableText() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            for color in TerminalTabColor.allCases where color != .none {
                let active = try #require(color.backgroundColor(selected: true, for: appearance))
                let inactive = try #require(color.backgroundColor(selected: false, for: appearance))
                func luminance(_ color: NSColor) -> CGFloat {
                    func linear(_ value: CGFloat) -> CGFloat {
                        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                    }
                    return 0.2126 * linear(color.redComponent) +
                        0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
                }
                let light = luminance(active)
                let dark = luminance(inactive)
                #expect((light + 0.05) / (dark + 0.05) > 6)
                #expect((light + 0.05) / 0.05 >= 4.5)
                #expect(1.05 / (dark + 0.05) >= 4.5)
                #expect(color.foregroundColor(selected: true, for: appearance) == .black)
                #expect(color.foregroundColor(selected: false, for: appearance) == .white)
            }
            #expect(TerminalTabColor.none.backgroundColor(selected: true, for: appearance) == nil)
        }
    }
}
