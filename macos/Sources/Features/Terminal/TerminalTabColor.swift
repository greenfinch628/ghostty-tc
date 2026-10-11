import AppKit
import SwiftUI

enum TerminalTabColor: Int, CaseIterable, Codable {
    case none
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal
    case graphite

    var localizedName: String {
        switch self {
        case .none:
            return "None"
        case .blue:
            return "Blue"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .red:
            return "Red"
        case .orange:
            return "Orange"
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .teal:
            return "Teal"
        case .graphite:
            return "Graphite"
        }
    }

    var displayColor: NSColor? {
        switch self {
        case .none:
            return nil
        case .blue:
            return .systemBlue
        case .purple:
            return .systemPurple
        case .pink:
            return .systemPink
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .teal:
            if #available(macOS 13.0, *) {
                return .systemMint
            } else {
                return .systemTeal
            }
        case .graphite:
            return .systemGray
        }
    }

    /// Choose the higher-contrast monochrome label for the opaque tab fill.
    /// Resolve dynamic system colors in the tab's current appearance first.
    func foregroundColor(for appearance: NSAppearance) -> NSColor? {
        guard let displayColor else { return nil }
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = displayColor.usingColorSpace(.sRGB)
        }
        guard let resolved else { return .labelColor }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(resolved.redComponent) +
            0.7152 * linear(resolved.greenComponent) +
            0.0722 * linear(resolved.blueComponent)
        return luminance > 0.179 ? .black : .white
    }

    func swatchImage(selected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: 1, dy: 1)
            let circlePath = NSBezierPath(ovalIn: circleRect)

            if let fillColor = self.displayColor {
                fillColor.setFill()
                circlePath.fill()
            } else {
                NSColor.clear.setFill()
                circlePath.fill()
                NSColor.quaternaryLabelColor.setStroke()
                circlePath.lineWidth = 1
                circlePath.stroke()
            }

            if self == .none {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: circleRect.minX + 2, y: circleRect.minY + 2))
                slash.line(to: NSPoint(x: circleRect.maxX - 2, y: circleRect.maxY - 2))
                slash.lineWidth = 1.5
                NSColor.secondaryLabelColor.setStroke()
                slash.stroke()
            }

            if selected {
                let highlight = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                highlight.lineWidth = 2
                NSColor.controlAccentColor.setStroke()
                highlight.stroke()
            }

            return true
        }
    }
}

// MARK: - Menu View

/// A SwiftUI view displaying a color palette for tab color selection.
/// Used as a custom view inside an NSMenuItem in the tab context menu.
struct TabColorMenuView: View {
    @State private var currentSelection: TerminalTabColor
    let onSelect: (TerminalTabColor) -> Void

    init(selectedColor: TerminalTabColor, onSelect: @escaping (TerminalTabColor) -> Void) {
        self._currentSelection = State(initialValue: selectedColor)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Tab Color")
                .padding(.bottom, 2)

            ForEach(Self.paletteRows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { color in
                        TabColorSwatch(
                            color: color,
                            isSelected: color == currentSelection
                        ) {
                            currentSelection = color
                            onSelect(color)
                        }
                    }
                }
            }
        }
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    static let paletteRows: [[TerminalTabColor]] = [
        [.none, .blue, .purple, .pink, .red],
        [.orange, .yellow, .green, .teal, .graphite],
    ]

    /// Leading padding to align with the menu's icon gutter.
    /// macOS 26 introduced icons in menus, requiring additional padding.
    private static var leadingPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 40
        } else {
            return 12
        }
    }
}

/// A single color swatch button in the tab color palette.
private struct TabColorSwatch: View {
    let color: TerminalTabColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if color == .none {
                    Image(systemName: isSelected ? "circle.slash" : "circle")
                        .foregroundStyle(.secondary)
                } else if let displayColor = color.displayColor {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(Color(nsColor: displayColor))
                }
            }
            .font(.system(size: 16))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(color.localizedName)
    }
}

/// Explicit SSH title markers avoid matching arbitrary terminal output.
struct TerminalHostColors {
    let colors: [String: TerminalTabColor]

    init(contents: String) {
        var colors: [String: TerminalTabColor] = [:]
        for line in contents.split(separator: "\n") {
            let entry = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let host = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let name = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !host.isEmpty,
                  let color = TerminalTabColor.allCases.first(where: { $0.localizedName.lowercased() == name })
            else { continue }
            colors[host] = color
        }
        self.colors = colors
    }

    func color(forTitle title: String, localHost: String = ProcessInfo.processInfo.hostName) -> TerminalTabColor {
        let marker = "SSH: "
        guard title.hasPrefix(marker) else {
            let host = localHost.lowercased().split(separator: ".").first.map(String.init) ?? ""
            return colors[host] ?? .none
        }
        let host = title.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).lowercased()
        return colors[host] ?? .none
    }

    static func load() -> Self {
        let environment = ProcessInfo.processInfo.environment
        let base = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) } ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        let path = base.appendingPathComponent("ghostty/tc-host-colors")
        return Self(contents: (try? String(contentsOf: path, encoding: .utf8)) ?? "")
    }
}
