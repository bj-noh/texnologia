import AppKit
import SwiftUI

enum FolioTheme {
    static let accent = adaptive(0x2F6FD0, dark: 0x81B7F2)
    static let accentHover = adaptive(0x245BB0, dark: 0xA0CCFA)
    static let accentSoft = adaptive(0xEAF2FC, dark: 0x233750)
    static let canvas = Color(nsColor: nsCanvas)
    static let surface = Color(nsColor: nsSurface)
    static let sidebar = Color(nsColor: nsSidebar)
    static let border = adaptive(0xE2E9F1, dark: 0x304052)
    static let text = adaptive(0x2B3543, dark: 0xE6EDF5)
    static let muted = adaptive(0x748295, dark: 0xA6B7CA)
    static let subtle = adaptive(0x8D9BAE, dark: 0x8296AC)
    static let onAccent = adaptive(0xFFFFFF, dark: 0x102844)

    static let nsCanvas = dynamicColor(0xF7F9FC, dark: 0x161E29)
    static let nsSurface = dynamicColor(0xFFFFFF, dark: 0x1E2936)
    static let nsSidebar = dynamicColor(0xF4F7FB, dark: 0x1B2531)

    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: dynamicColor(light, dark: dark))
    }

    private static func dynamicColor(_ light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

struct FolioIconButtonStyle: ButtonStyle {
    var isSelected = false
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        FolioButtonSurface(configuration: configuration, kind: .icon, isSelected: isSelected, height: size)
    }
}

struct FolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FolioButtonSurface(configuration: configuration, kind: .primary)
    }
}

struct FolioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FolioButtonSurface(configuration: configuration, kind: .secondary)
    }
}

private struct FolioButtonSurface: View {
    enum Kind {
        case icon, primary, secondary
    }

    let configuration: ButtonStyleConfiguration
    let kind: Kind
    var isSelected = false
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .icon ? 0 : 13)
            .frame(width: kind == .icon ? height : nil, height: height)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(FolioTheme.border, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return FolioTheme.onAccent
        case .secondary: return FolioTheme.text
        case .icon: return isSelected || isHovered ? FolioTheme.accent : FolioTheme.muted
        }
    }

    private var background: Color {
        let isActive = isEnabled && (isHovered || configuration.isPressed)
        switch kind {
        case .primary: return isActive ? FolioTheme.accentHover : FolioTheme.accent
        case .secondary: return isActive ? FolioTheme.accentSoft : FolioTheme.surface
        case .icon: return isSelected || isActive ? FolioTheme.accentSoft : .clear
        }
    }
}

struct FolioDocumentMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(FolioTheme.accent)

            FolioPageOutline()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.048, lineCap: .round, lineJoin: .round))
                .padding(size * 0.245)

            HStack(alignment: .firstTextBaseline, spacing: -size * 0.018) {
                Text("T")
                Text("E").baselineOffset(-size * 0.039)
                Text("X")
            }
            .font(.custom("TimesNewRomanPS-BoldMT", fixedSize: size * 0.176))
            .foregroundStyle(.white)
            .fixedSize()
            .offset(x: size * 0.005, y: size * 0.055)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct FolioPageOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let width = rect.width
        let height = rect.height
        return Path { path in
            path.move(to: CGPoint(x: x + width * 0.10, y: y))
            path.addLine(to: CGPoint(x: x + width * 0.66, y: y))
            path.addLine(to: CGPoint(x: x + width * 0.92, y: y + height * 0.25))
            path.addLine(to: CGPoint(x: x + width * 0.92, y: y + height))
            path.addLine(to: CGPoint(x: x + width * 0.10, y: y + height))
            path.closeSubpath()

            path.move(to: CGPoint(x: x + width * 0.66, y: y))
            path.addLine(to: CGPoint(x: x + width * 0.66, y: y + height * 0.25))
            path.addLine(to: CGPoint(x: x + width * 0.92, y: y + height * 0.25))
        }
    }
}
