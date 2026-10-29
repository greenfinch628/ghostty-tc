import AppKit
import SwiftUI
import GhosttyKit

/// The base class for all standalone, "normal" terminal windows. This sets the basic
/// style and configuration of the window based on the app configuration.
class TerminalWindow: NSWindow {
    /// Posted when a terminal window awakes from nib.
    static let terminalDidAwake = Notification.Name("TerminalWindowDidAwake")

    /// Posted when a terminal window will close
    static let terminalWillCloseNotification = Notification.Name("TerminalWindowWillClose")

    /// This is the key in UserDefaults to use for the default `level` value. This is
    /// used by the manual float on top menu item feature.
    static let defaultLevelKey: String = "TerminalDefaultLevel"

    /// The view model for SwiftUI views
    private var viewModel = ViewModel()

    /// Reset split zoom button in titlebar
    private let resetZoomAccessory = NSTitlebarAccessoryViewController()

    /// Update notification UI in titlebar
    private let updateAccessory = NSTitlebarAccessoryViewController()

    /// Visual indicator that mirrors the selected tab color.
    private lazy var tabColorIndicator: NSHostingView<TabColorIndicatorView> = {
        let view = NSHostingView(rootView: TabColorIndicatorView(tabColor: tabColor))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var tabColorAccessory: TabColorAccessoryView?

    /// The configuration derived from the Ghostty config so we don't need to rely on references.
    private(set) var derivedConfig: DerivedConfig = .init()

    /// Sets up our tab context menu
    private var tabMenuObserver: NSObjectProtocol?

    /// Handles inline tab title editing for this host window.
    private(set) lazy var tabTitleEditor = TabTitleEditor(
        hostWindow: self,
        delegate: self
    )

    /// Whether this window supports the update accessory. If this is false, then views within this
    /// window should determine how to show update notifications.
    var supportsUpdateAccessory: Bool {
        // Native window supports it.
        true
    }

    /// Glass effect view for liquid glass background when transparency is enabled
    private var glassEffectView: NSView?

    /// Gets the terminal controller from the window controller.
    var terminalController: TerminalController? {
        windowController as? TerminalController
    }

    /// The color assigned to this window's tab. Setting this updates the tab background
    /// and marks the window's restorable state as dirty.
    var tabColor: TerminalTabColor = .none {
        didSet {
            guard tabColor != oldValue else { return }
            tabColorIndicator.rootView = TabColorIndicatorView(tabColor: tabColor)
            tabColorAccessory?.updateBackground()
            updateTabColorText()
            invalidateRestorableState()
        }
    }

    // Manual selections are pinned; the menu can explicitly resume automatic colors.
    var usesAutomaticTabColor = true {
        didSet {
            invalidateRestorableState()
            updateAutomaticTabColor()
        }
    }

    private func updateAutomaticTabColor() {
        guard usesAutomaticTabColor else { return }
        tabColor = TerminalHostColors.load().color(forTitle: title)
    }

    @objc private func useAutomaticTabColor(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? TerminalWindow else { return }
        target.usesAutomaticTabColor = true
    }

    fileprivate var isSelectedTab: Bool {
        guard let tabGroup else { return true }
        return tabGroup.selectedWindow === self
    }

    private var tabForegroundColor: NSColor? {
        guard tabColorAccessory?.hasBackground == true else { return nil }
        return tabColor.foregroundColor(selected: isSelectedTab, for: effectiveAppearance)
    }

    fileprivate func updateTabColorText() {
        let styledTitle = attributedTitle
        if tab.attributedTitle != styledTitle { tab.attributedTitle = styledTitle }
        let shortcut = NSMutableAttributedString(attributedString: keyEquivalentLabel.attributedStringValue)
        shortcut.addAttribute(
            .foregroundColor,
            value: tabForegroundColor ?? (isKeyWindow ? NSColor.labelColor : NSColor.secondaryLabelColor),
            range: NSRange(location: 0, length: shortcut.length)
        )
        if keyEquivalentLabel.attributedStringValue != shortcut { keyEquivalentLabel.attributedStringValue = shortcut }
        resetZoomTabButton.contentTintColor = tabForegroundColor ??
            (isKeyWindow ? .controlAccentColor : .secondaryLabelColor)
    }

    // MARK: NSWindow Overrides

    override func update() {
        super.update()

        // AppKit normally hides the native tab bar when only one tab remains.
        // Apply the explicit config after AppKit's window updates, including
        // initial display and removal of the penultimate tab.
        guard derivedConfig.alwaysShowTabBar,
              isVisible, styleMask.contains(.titled), tabbingMode != .disallowed,
              tabGroup?.isTabBarVisible != true else { return }
        toggleTabBar(nil)
    }

    override var toolbar: NSToolbar? {
        didSet {
            DispatchQueue.main.async {
                // When we have a toolbar, our SwiftUI view needs to know for layout
                self.viewModel.hasToolbar = self.toolbar != nil
            }
        }
    }

    override func awakeFromNib() {
        // Notify that this terminal window has loaded
        NotificationCenter.default.post(name: Self.terminalDidAwake, object: self)

        // This is fragile, but there doesn't seem to be an official API for customizing
        // native tab bar menus.
        tabMenuObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: "NSMenuWillOpenNotification"),
            object: nil,
            queue: .main
        ) { [weak self] n in
            guard let self, let menu = n.object as? NSMenu else { return }
            self.configureTabContextMenuIfNeeded(menu)
        }

        // This is required so that window restoration properly creates our tabs
        // again. I'm not sure why this is required. If you don't do this, then
        // tabs restore as separate windows.
        tabbingMode = .preferred
        DispatchQueue.main.async {
            self.tabbingMode = .automatic
        }

        // All new windows are based on the app config at the time of creation.
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let config = appDelegate.ghostty.config

        // Setup our initial config
        derivedConfig = .init(config)

        // If there is a hardcoded title in the configuration, we set that
        // immediately. Future `set_title` apprt actions will override this
        // if necessary but this ensures our window loads with the proper
        // title immediately rather than on another event loop tick (see #5934)
        if let title = derivedConfig.title {
            self.title = title
        }

        // If window decorations are disabled, remove our title
        if !config.windowDecorations { styleMask.remove(.titled) }

        // NOTE: setInitialWindowPosition is NOT called here because subclass
        // awakeFromNib may add decorations (e.g. toolbar for tabs style) that
        // change the frame. It is called from TerminalController.windowDidLoad
        // after the window is fully set up.

        // If our traffic buttons should be hidden, then hide them
        if config.macosWindowButtons == .hidden {
            hideWindowButtons()
        }

        // Create our reset zoom titlebar accessory. We have to have a title
        // to do this or AppKit triggers an assertion.
        if styleMask.contains(.titled) {
            resetZoomAccessory.layoutAttribute = .right
            resetZoomAccessory.view = NSHostingView(rootView: ResetZoomAccessoryView(
                viewModel: viewModel,
                action: { [weak self] in
                    guard let self else { return }
                    self.terminalController?.splitZoom(self)
                }))
            addTitlebarAccessoryViewController(resetZoomAccessory)
            resetZoomAccessory.view.translatesAutoresizingMaskIntoConstraints = false

            // Create update notification accessory
            if supportsUpdateAccessory {
                updateAccessory.layoutAttribute = .right
                updateAccessory.view = NonDraggableHostingView(rootView: UpdateAccessoryView(
                    viewModel: viewModel,
                    model: appDelegate.updateViewModel
                ))
                addTitlebarAccessoryViewController(updateAccessory)
                updateAccessory.view.translatesAutoresizingMaskIntoConstraints = false
            }
        }

        // Setup the accessory view for tabs that shows our keyboard shortcuts,
        // zoomed state, etc. Note I tried to use SwiftUI here but ran into issues
        // where buttons were not clickable.
        tabColorIndicator.rootView = TabColorIndicatorView(tabColor: tabColor)

        let stackView = TabColorAccessoryView()
        stackView.terminalWindow = self
        stackView.indicator = tabColorIndicator
        tabColorAccessory = stackView
        stackView.orientation = .horizontal
        stackView.setHuggingPriority(.defaultHigh, for: .horizontal)
        stackView.spacing = 4
        stackView.alignment = .centerY
        stackView.addArrangedSubview(tabColorIndicator)
        stackView.addArrangedSubview(keyEquivalentLabel)
        stackView.addArrangedSubview(resetZoomTabButton)
        tab.accessoryView = stackView

        // Get our saved level
        level = UserDefaults.ghostty.value(forKey: Self.defaultLevelKey) as? NSWindow.Level ?? .normal
    }

    // Both of these must be true for windows without decorations to be able to
    // still become key/main and receive events.
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    override func sendEvent(_ event: NSEvent) {
        if showTabContextMenu(for: event) { return }
        if tabTitleEditor.handleMouseDown(event) {
            return
        }

        super.sendEvent(event)
    }

    override func close() {
        tabTitleEditor.finishEditing(commit: true)
        NotificationCenter.default.post(name: Self.terminalWillCloseNotification, object: self)
        super.close()
    }

    override func becomeKey() {
        super.becomeKey()
        updateTabColorText()
    }

    override func resignKey() {
        super.resignKey()
        updateTabColorText()
        tabTitleEditor.finishEditing(commit: true)
    }

    override func becomeMain() {
        super.becomeMain()

        // Its possible we miss the accessory titlebar call so we check again
        // whenever the window becomes main. Both of these are idempotent.
        if tabBarView != nil {
            tabBarDidAppear()
        } else {
            tabBarDidDisappear()
        }
        viewModel.isMainWindow = true
    }

    override func resignMain() {
        super.resignMain()
        viewModel.isMainWindow = false
    }

    @discardableResult
    func beginInlineTabTitleEdit(for targetWindow: NSWindow) -> Bool {
        tabTitleEditor.beginEditing(for: targetWindow)
    }

    @objc private func renameTabFromContextMenu(_ sender: NSMenuItem) {
        let targetWindow = sender.representedObject as? NSWindow ?? self
        if beginInlineTabTitleEdit(for: targetWindow) {
            return
        }

        guard let targetController = targetWindow.windowController as? BaseTerminalController else { return }
        targetController.promptTabTitle()
    }

    override func mergeAllWindows(_ sender: Any?) {
        super.mergeAllWindows(sender)

        // It takes an event loop cycle to merge all the windows so we set a
        // short timer to relabel the tabs (issue #1902)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.terminalController?.relabelTabs()
        }
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        super.addTitlebarAccessoryViewController(childViewController)

        // Tab bar is attached as a titlebar accessory view controller (layout bottom). We
        // can detect when it is shown or hidden by overriding add/remove and searching for
        // it. This has been verified to work on macOS 12 to 26
        if isTabBar(childViewController) {
            childViewController.identifier = Self.tabBarIdentifier
            tabBarDidAppear()
        }
    }

    override func removeTitlebarAccessoryViewController(at index: Int) {
        if let childViewController = titlebarAccessoryViewControllers[safe: index], isTabBar(childViewController) {
            tabBarDidDisappear()
        }

        super.removeTitlebarAccessoryViewController(at: index)
    }

    // MARK: Tab Bar

    /// This identifier is attached to the tab bar view controller when we detect it being
    /// added.
    static let tabBarIdentifier: NSUserInterfaceItemIdentifier = .init("_ghosttyTabBar")

    var hasMoreThanOneTabs: Bool {
        /// accessing ``tabGroup?.windows`` here
        /// will cause other edge cases, be careful
        (tabbedWindows?.count ?? 0) > 1
    }

    func isTabBar(_ childViewController: NSTitlebarAccessoryViewController) -> Bool {
        if childViewController.identifier == nil {
            // The good case
            if childViewController.view.contains(className: "NSTabBar") {
                return true
            }

            // When a new window is attached to an existing tab group, AppKit adds
            // an empty NSView as an accessory view and adds the tab bar later. If
            // we're at the bottom and are a single NSView we assume its a tab bar.
            if childViewController.layoutAttribute == .bottom &&
                childViewController.view.className == "NSView" &&
                childViewController.view.subviews.isEmpty {
                return true
            }

            return false
        }

        // View controllers should be tagged with this as soon as possible to
        // increase our accuracy. We do this manually.
        return childViewController.identifier == Self.tabBarIdentifier
    }

    private func tabBarDidAppear() {
        // Remove our reset zoom accessory. For some reason having a SwiftUI
        // titlebar accessory causes our content view scaling to be wrong.
        // Removing it fixes it, we just need to remember to add it again later.
        if let idx = titlebarAccessoryViewControllers.firstIndex(of: resetZoomAccessory) {
            removeTitlebarAccessoryViewController(at: idx)
        }

        // We don't need to do this with the update accessory. I don't know why but
        // everything works fine.
    }

    private func tabBarDidDisappear() {
        if styleMask.contains(.titled) {
            if titlebarAccessoryViewControllers.firstIndex(of: resetZoomAccessory) == nil {
                addTitlebarAccessoryViewController(resetZoomAccessory)
            }
        }
    }

    // MARK: Tab Key Equivalents

    var keyEquivalent: String? {
        didSet {
            // When our key equivalent is set, we must update the tab label.
            guard let keyEquivalent else {
                keyEquivalentLabel.attributedStringValue = NSAttributedString()
                return
            }

            keyEquivalentLabel.attributedStringValue = NSAttributedString(
                string: "\(keyEquivalent) ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: tabForegroundColor ?? (isKeyWindow ? NSColor.labelColor : NSColor.secondaryLabelColor),
                ])
        }
    }

    /// The label that has the key equivalent for tab views.
    private lazy var keyEquivalentLabel: NSTextField = {
        let label = NSTextField(labelWithAttributedString: NSAttributedString())
        label.setContentCompressionResistancePriority(.windowSizeStayPut, for: .horizontal)
        label.postsFrameChangedNotifications = true
        return label
    }()

    // MARK: Surface Zoom

    /// Set to true if a surface is currently zoomed to show the reset zoom button.
    var surfaceIsZoomed: Bool = false {
        didSet {
            // Show/hide our reset zoom button depending on if we're zoomed.
            // We want to show it if we are zoomed.
            resetZoomTabButton.isHidden = !surfaceIsZoomed

            DispatchQueue.main.async {
                self.viewModel.isSurfaceZoomed = self.surfaceIsZoomed
            }
        }
    }

    private lazy var resetZoomTabButton: NSButton = generateResetZoomButton()

    private func generateResetZoomButton() -> NSButton {
        let button = NSButton()
        button.isHidden = true
        button.target = terminalController
        button.action = #selector(TerminalController.splitZoom(_:))
        button.isBordered = false
        button.allowsExpansionToolTips = true
        button.toolTip = "Reset Zoom"
        button.contentTintColor = isMainWindow ? .controlAccentColor : .secondaryLabelColor
        button.state = .on
        button.image = NSImage(named: "ResetZoom")
        button.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    // MARK: Title Text

    override var title: String {
        didSet {
            updateAutomaticTabColor()
            // Whenever we change the window title we must also update our
            // tab title if we're using custom fonts.
            tab.attributedTitle = attributedTitle
            /// We also needs to update this here, just in case
            /// the value is not what we want
            ///
            /// Check ``titlebarFont`` down below
            /// to see why we need to check `hasMoreThanOneTabs` here
            titlebarTextField?.usesSingleLineMode = !hasMoreThanOneTabs
        }
    }

    // Used to set the titlebar font.
    var titlebarFont: NSFont? {
        didSet {
            let font = titlebarFont ?? NSFont.titleBarFont(ofSize: NSFont.systemFontSize)

            titlebarTextField?.font = font
            /// We check `hasMoreThanOneTabs` here because the system
            /// may copy this setting to the tab’s text field at some point(e.g. entering/exiting fullscreen),
            /// which can cause the title to be vertically misaligned (shifted downward).
            ///
            /// This behaviour is the opposite of what happens in the title bar’s text field, which is quite odd...
            titlebarTextField?.usesSingleLineMode = !hasMoreThanOneTabs
            tab.attributedTitle = attributedTitle
        }
    }

    // Find the NSTextField responsible for displaying the titlebar's title.
    private var titlebarTextField: NSTextField? {
        titlebarContainer?
            .firstDescendant(withClassName: "NSTitlebarView")?
            .firstDescendant(withClassName: "NSTextField") as? NSTextField
    }

    // Return a styled representation of our title property.
    var attributedTitle: NSAttributedString? {
        guard titlebarFont != nil || tabForegroundColor != nil else { return nil }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: titlebarFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: tabForegroundColor ??
                (isKeyWindow ? NSColor.labelColor : NSColor.secondaryLabelColor),
        ]
        return NSAttributedString(string: title, attributes: attributes)
    }

    var titlebarContainer: NSView? {
        // If we aren't fullscreen then the titlebar container is part of our window.
        if !styleMask.contains(.fullScreen) {
            return contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        // If we are fullscreen, the titlebar container view is part of a separate
        // "fullscreen window", we need to find the window and then get the view.
        for window in NSApplication.shared.windows {
            // This is the private window class that contains the toolbar
            guard window.className == "NSToolbarFullScreenWindow" else { continue }

            // The parent will match our window. This is used to filter the correct
            // fullscreen window if we have multiple.
            guard window.parent == self else { continue }

            return window.contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        return nil
    }

    // MARK: Positioning And Styling

    /// This is called by the controller when there is a need to reset the window appearance.
    func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        // If our window is not visible, then we do nothing. Some things such as blurring
        // have no effect if the window is not visible. Ultimately, we'll have this called
        // at some point when a surface becomes focused.
        guard isVisible else { return }
        defer { updateColorSchemeForSurfaceTree() }

        // Basic properties
        appearance = surfaceConfig.windowAppearance
        hasShadow = surfaceConfig.macosWindowShadow

        // Window transparency only takes effect if our window is not native fullscreen.
        // In native fullscreen we disable transparency/opacity because the background
        // becomes gray and widgets show through.
        //
        // Also check if the user has overridden transparency to be fully opaque.
        let forceOpaque = terminalController?.isBackgroundOpaque ?? false
        if !styleMask.contains(.fullScreen) &&
            !forceOpaque &&
            (surfaceConfig.backgroundOpacity < 1 || surfaceConfig.backgroundBlur.isGlassStyle) {
            isOpaque = false

            // This is weird, but we don't use ".clear" because this creates a look that
            // matches Terminal.app much more closer. This lets users transition from
            // Terminal.app more easily.
            backgroundColor = .white.withAlphaComponent(0.001)

            // We don't need to set blur when using glass
            if !surfaceConfig.backgroundBlur.isGlassStyle, let appDelegate = NSApp.delegate as? AppDelegate {
                ghostty_set_window_background_blur(
                    appDelegate.ghostty.app,
                    Unmanaged.passUnretained(self).toOpaque())
            }
        } else {
            isOpaque = true

            let backgroundColor = preferredBackgroundColor ?? NSColor(surfaceConfig.backgroundColor)
            self.backgroundColor = backgroundColor.withAlphaComponent(1)
        }
    }

    /// The preferred window background color. The current window background color may not be set
    /// to this, since this is dynamic based on the state of the surface tree.
    ///
    /// This background color will include alpha transparency if set. If the caller doesn't want that,
    /// change the alpha channel again manually.
    var preferredBackgroundColor: NSColor? {
        if let terminalController, !terminalController.surfaceTree.isEmpty {
            let surface: Ghostty.SurfaceView?

            // If our focused surface borders the top then we prefer its background color
            if let focusedSurface = terminalController.focusedSurface,
               let treeRoot = terminalController.surfaceTree.root,
               let focusedNode = treeRoot.node(view: focusedSurface),
               treeRoot.spatial().doesBorder(side: .up, from: focusedNode) {
                surface = focusedSurface
            } else {
                // If it doesn't border the top, we use the top-left leaf
                surface = terminalController.surfaceTree.root?.leftmostLeaf()
            }

            if let surface {
                let backgroundColor = surface.backgroundColor ?? surface.derivedConfig.backgroundColor
                let alpha = surface.derivedConfig.backgroundOpacity.clamped(to: 0.001...1)
                return NSColor(backgroundColor).withAlphaComponent(alpha)
            }
        }

        let alpha = derivedConfig.backgroundOpacity.clamped(to: 0.001...1)
        return derivedConfig.backgroundColor.withAlphaComponent(alpha)
    }

    func updateColorSchemeForSurfaceTree() {
        terminalController?.updateColorSchemeForSurfaceTree()
    }

    func setInitialWindowPosition(x: Int16?, y: Int16?) -> Bool {
        // If we don't have an X/Y then we try to use the previously saved window pos.
        guard let x = x, let y = y else {
            return false
        }

        // Prefer the screen our window is being placed on otherwise our primary screen.
        guard let screen = screen ?? NSScreen.screens.first else {
            return false
        }

        // Convert top-left coordinates to bottom-left origin using our utility extension
        let origin = screen.origin(
            fromTopLeftOffsetX: CGFloat(x),
            offsetY: CGFloat(y),
            windowSize: frame.size)

        // Clamp the origin to ensure the window stays fully visible on screen
        var safeOrigin = origin
        let vf = screen.visibleFrame
        safeOrigin.x = min(max(safeOrigin.x, vf.minX), vf.maxX - frame.width)
        safeOrigin.y = min(max(safeOrigin.y, vf.minY), vf.maxY - frame.height)

        setFrameOrigin(safeOrigin)
        return true
    }

    private func hideWindowButtons() {
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    deinit {
        if let observer = tabMenuObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Config

    struct DerivedConfig {
        let title: String?
        let alwaysShowTabBar: Bool
        let backgroundBlur: Ghostty.Config.BackgroundBlur
        let backgroundColor: NSColor
        let backgroundOpacity: Double
        let macosWindowButtons: Ghostty.MacOSWindowButtons
        let macosTitlebarStyle: Ghostty.Config.MacOSTitlebarStyle
        let windowCornerRadius: CGFloat

        init() {
            self.title = nil
            self.alwaysShowTabBar = false
            self.backgroundColor = NSColor.windowBackgroundColor
            self.backgroundOpacity = 1
            self.macosWindowButtons = .visible
            self.backgroundBlur = .disabled
            self.macosTitlebarStyle = .default
            self.windowCornerRadius = 16
        }

        init(_ config: Ghostty.Config) {
            self.title = config.title
            self.alwaysShowTabBar = config.windowShowTabBar == "always"
            self.backgroundColor = NSColor(config.backgroundColor)
            self.backgroundOpacity = config.backgroundOpacity
            self.macosWindowButtons = config.macosWindowButtons
            self.backgroundBlur = config.backgroundBlur
            self.macosTitlebarStyle = config.macosTitlebarStyle

            // Set corner radius based on macos-titlebar-style
            // Native, transparent, and hidden styles use 16pt radius
            // Tabs style uses 20pt radius
            switch config.macosTitlebarStyle {
            case .tabs:
                self.windowCornerRadius = 20
            default:
                self.windowCornerRadius = 16
            }
        }
    }
}

// MARK: SwiftUI View

extension TerminalWindow {
    class ViewModel: ObservableObject {
        @Published var isSurfaceZoomed: Bool = false
        @Published var hasToolbar: Bool = false
        @Published var isMainWindow: Bool = true

        /// Calculates the top padding based on toolbar visibility and macOS version
        fileprivate var accessoryTopPadding: CGFloat {
            if #available(macOS 26.0, *) {
                return hasToolbar ? 10 : 5
            } else {
                return hasToolbar ? 9 : 4
            }
        }
    }

    struct ResetZoomAccessoryView: View {
        @ObservedObject var viewModel: ViewModel
        let action: () -> Void

        var body: some View {
            if viewModel.isSurfaceZoomed {
                VStack {
                    Button(action: action) {
                        Image("ResetZoom")
                            .foregroundColor(viewModel.isMainWindow ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset Split Zoom")
                    .frame(width: 20, height: 20)
                    Spacer()
                }
                // With a toolbar, the window title is taller, so we need more padding
                // to properly align.
                .padding(.top, viewModel.accessoryTopPadding)
                // We always need space at the end of the titlebar
                .padding(.trailing, 10)
            }
        }
    }

    /// A pill-shaped button that displays update status and provides access to update actions.
    struct UpdateAccessoryView: View {
        @ObservedObject var viewModel: ViewModel
        @ObservedObject var model: UpdateViewModel

        var body: some View {
            // We use the same top/trailing padding so that it hugs the same.
            UpdatePill(model: model)
                .padding(.top, viewModel.accessoryTopPadding)
                .padding(.trailing, viewModel.accessoryTopPadding)
        }
    }

}

/// Keeps the fill attached to the tab that owns this accessory, including after
/// AppKit moves/recreates tab buttons during selection, reordering, or fullscreen.
/// Tahoe's tab content container is private, just like Ghostty's existing native
/// tab layout integration. If it changes, retain the original color dot instead.
private final class TabColorAccessoryView: NSStackView {
    weak var terminalWindow: TerminalWindow?
    weak var indicator: NSView?
    private let background = TabColorBackgroundView()
    private weak var observedTabGroup: NSWindowTabGroup?
    private var selectionObservation: NSKeyValueObservation?

    var hasBackground: Bool { background.superview != nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateBackground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }

    override func layout() {
        super.layout()
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    func updateBackground() {
        let group = terminalWindow?.tabGroup
        if observedTabGroup !== group {
            selectionObservation = nil
            observedTabGroup = group
            selectionObservation = group?.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
                self?.updateBackground()
            }
        }
        guard let terminalWindow,
              let color = terminalWindow.tabColor.backgroundColor(
                selected: terminalWindow.isSelectedTab, for: terminalWindow.effectiveAppearance
              ),
              let button = firstSuperview(withClassName: "NSTabButton"),
              let container = button.firstDescendant(withID: "_tabButtonContainerView")
        else {
            background.removeFromSuperview()
            indicator?.isHidden = false
            terminalWindow?.updateTabColorText()
            return
        }

        if background.superview !== container {
            background.removeFromSuperview()
            // Inside the glass content, behind labels/controls: the native glass
            // and selected-tab treatment remain in place, and input is untouched.
            container.addSubview(background, positioned: .below, relativeTo: container.subviews.first)
            background.autoresizingMask = [.width, .height]
        }
        background.frame = container.bounds
        background.color = color
        indicator?.isHidden = true
        terminalWindow.updateTabColorText()
    }
}

/// A purely decorative fill; never intercept tab selection, drag, or context menus.
private final class TabColorBackgroundView: NSView {
    var color: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override var allowsVibrancy: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
}

/// A small circle indicator displayed in the tab accessory view that shows
/// the user-assigned tab color. When no color is set, the view is hidden.
private struct TabColorIndicatorView: View {
    /// The tab color to display.
    let tabColor: TerminalTabColor

    var body: some View {
        if let color = tabColor.displayColor {
            Circle()
                .fill(Color(color))
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .fill(Color.clear)
                .frame(width: 6, height: 6)
                .hidden()
        }
    }
}

// MARK: - Tab Context Menu

extension TerminalWindow {
    private static let directTabMenuIdentifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.directTabMenu")
    private static let closeTabsOnRightMenuItemIdentifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.closeTabsOnTheRightMenuItem")
    private static let changeTitleMenuItemIdentifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.changeTitleMenuItem")
    private static let tabColorSeparatorIdentifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.tabColorSeparator")

    private static let automaticColorIdentifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.automaticTabColor")
    private static let tabColorPaletteIdentifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.tabColorPalette")

    /// AppKit does not reliably provide a context menu for native tabs on Tahoe.
    /// Handle the tab click directly and reuse the existing rename/color section.
    func showTabContextMenu(for event: NSEvent) -> Bool {
        let isContextClick = event.type == .rightMouseDown ||
            (event.type == .otherMouseDown && event.buttonNumber == 2) ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isContextClick, let sourceWindow = event.window,
              let hit = tabButtonHit(atScreenPoint: sourceWindow.convertPoint(toScreen: event.locationInWindow)),
              let targetWindow = (tabbedWindows ?? [self])[safe: hit.index],
              let target = targetWindow.windowController as? TerminalController
        else { return false }
        if tabTitleEditor.handleRightMouseDown(event) { return true }

        let menu = NSMenu()
        menu.identifier = Self.directTabMenuIdentifier
        for (title, action) in [
            ("Close Tab", "performClose:"),
            ("Close Other Tabs", "performCloseOtherTabs:"),
            ("Move Tab to New Window", "moveTabToNewWindow:"),
            ("Show All Tabs", "toggleTabOverview:")
        ] {
            let item = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: "")
            item.target = targetWindow
            menu.addItem(item)
        }
        let closeRight = NSMenuItem(
            title: "Close Tabs to the Right",
            action: #selector(TerminalController.closeTabsOnTheRight(_:)),
            keyEquivalent: ""
        )
        closeRight.target = target
        menu.addItem(closeRight)
        appendTabModifierSection(to: menu, target: target)
        NSMenu.popUpContextMenu(menu, with: event, for: hit.tabButton)
        return true
    }

    func configureTabContextMenuIfNeeded(_ menu: NSMenu) {
        guard menu.identifier != Self.directTabMenuIdentifier, isTabContextMenu(menu) else { return }

        // On Tahoe the native close item's target can still reference another tab.
        // Resolve mouse-opened menus from the same screen-space hit testing used
        // by inline rename, including the detached fullscreen titlebar window.
        let clickedWindow: NSWindow? = NSApp.currentEvent.flatMap { event in
            let isContextClick = event.type == .rightMouseDown ||
                (event.type == .otherMouseDown && event.buttonNumber == 2) ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextClick, let sourceWindow = event.window,
                  let index = tabIndex(atScreenPoint: sourceWindow.convertPoint(toScreen: event.locationInWindow))
            else { return nil }
            return tabbedWindows?[safe: index]
        }
        let nativeTargetController = menu.items
            .first { $0.action == NSSelectorFromString("performClose:") }
            .flatMap { $0.target as? NSWindow }
            .flatMap { $0.windowController as? TerminalController }
        let targetController = (clickedWindow?.windowController as? TerminalController) ?? nativeTargetController

        // Close tabs to the right
        let item = NSMenuItem(title: "Close Tabs to the Right", action: #selector(TerminalController.closeTabsOnTheRight(_:)), keyEquivalent: "")
        item.identifier = Self.closeTabsOnRightMenuItemIdentifier
        item.target = targetController
        item.setImageIfDesired(systemSymbolName: "xmark")
        if menu.insertItem(item, after: NSSelectorFromString("performCloseOtherTabs:")) == nil,
           menu.insertItem(item, after: NSSelectorFromString("performClose:")) == nil {
            menu.addItem(item)
        }

        // Other close items should have the xmark to match Safari on macOS 26
        for menuItem in menu.items {
            if menuItem.action == NSSelectorFromString("performClose:") ||
                menuItem.action == NSSelectorFromString("performCloseOtherTabs:") {
                menuItem.setImageIfDesired(systemSymbolName: "xmark")
            }
        }

        appendTabModifierSection(to: menu, target: targetController)
    }

    private func isTabContextMenu(_ menu: NSMenu) -> Bool {
        guard NSApp.keyWindow === self else { return false }

        // These selectors must all exist for it to be a tab context menu.
        let requiredSelectors: Set<String> = [
            "performClose:",
            "performCloseOtherTabs:",
            "moveTabToNewWindow:",
            "toggleTabOverview:"
        ]

        let selectorNames = Set(menu.items.compactMap { $0.action }.map { NSStringFromSelector($0) })
        return requiredSelectors.isSubset(of: selectorNames)
    }

    private func appendTabModifierSection(to menu: NSMenu, target: TerminalController?) {
        menu.removeItems(withIdentifiers: [
            Self.tabColorSeparatorIdentifier,
            Self.changeTitleMenuItemIdentifier,
            Self.tabColorPaletteIdentifier,
            Self.automaticColorIdentifier
        ])

        let separator = NSMenuItem.separator()
        separator.identifier = Self.tabColorSeparatorIdentifier
        menu.addItem(separator)

        // Rename Tab...
        let changeTitleItem = NSMenuItem(title: "Rename Tab...", action: #selector(TerminalWindow.renameTabFromContextMenu(_:)), keyEquivalent: "")
        changeTitleItem.identifier = Self.changeTitleMenuItemIdentifier
        changeTitleItem.target = self
        changeTitleItem.representedObject = target?.window
        changeTitleItem.setImageIfDesired(systemSymbolName: "pencil.line")
        menu.addItem(changeTitleItem)

        let automaticItem = NSMenuItem(
            title: "Use Automatic Color",
            action: #selector(useAutomaticTabColor(_:)),
            keyEquivalent: ""
        )
        automaticItem.identifier = Self.automaticColorIdentifier
        automaticItem.target = self
        automaticItem.representedObject = target?.window
        automaticItem.state = (target?.window as? TerminalWindow)?.usesAutomaticTabColor == true ? .on : .off
        menu.addItem(automaticItem)

        let paletteItem = NSMenuItem()
        paletteItem.identifier = Self.tabColorPaletteIdentifier
        paletteItem.view = makeTabColorPaletteView(
            selectedColor: (target?.window as? TerminalWindow)?.tabColor ?? .none
        ) { [weak target] color in
            guard let window = target?.window as? TerminalWindow else { return }
            window.usesAutomaticTabColor = false
            window.tabColor = color
        }
        menu.addItem(paletteItem)
    }
}

private func makeTabColorPaletteView(
    selectedColor: TerminalTabColor,
    selectionHandler: @escaping (TerminalTabColor) -> Void
) -> NSView {
    let hostingView = NSHostingView(rootView: TabColorMenuView(
        selectedColor: selectedColor,
        onSelect: selectionHandler
    ))
    hostingView.frame.size = hostingView.intrinsicContentSize
    return hostingView
}

// MARK: - Inline Tab Title Editing

extension TerminalWindow: TabTitleEditorDelegate {
    func tabTitleEditor(
        _ editor: TabTitleEditor,
        canRenameTabFor targetWindow: NSWindow
    ) -> Bool {
        targetWindow.windowController is BaseTerminalController
    }

    func tabTitleEditor(
        _ editor: TabTitleEditor,
        titleFor targetWindow: NSWindow
    ) -> String {
        guard let targetController = targetWindow.windowController as? BaseTerminalController else {
            return targetWindow.title
        }

        return targetController.titleOverride ?? targetWindow.title
    }

    func tabTitleEditor(
        _ editor: TabTitleEditor,
        didCommitTitle editedTitle: String,
        for targetWindow: NSWindow
    ) {
        guard let targetController = targetWindow.windowController as? BaseTerminalController else { return }
        targetController.titleOverride = editedTitle.isEmpty ? nil : editedTitle
    }

    func tabTitleEditor(
        _ editor: TabTitleEditor,
        performFallbackRenameFor targetWindow: NSWindow
    ) {
        guard let targetController = targetWindow.windowController as? BaseTerminalController else { return }
        targetController.promptTabTitle()
    }

    func tabTitleEditor(_ editor: TabTitleEditor, didFinishEditing targetWindow: NSWindow) {
        // After inline editing, the first responder is the window itself.
        // Restore focus to the terminal surface so keyboard input works.
        guard let controller = windowController as? BaseTerminalController,
              let focusedSurface = controller.focusedSurface
        else { return }
        makeFirstResponder(focusedSurface)
    }
}
