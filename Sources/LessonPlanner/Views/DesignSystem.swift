import SwiftUI

/// "Sunrise Planner" — the warm-morning design system from the 2026-07-29 design handoff
/// (`Design Reference/warm-morning-2026-07-29/`). Token values are transcribed directly from
/// that handoff's `:root` custom properties; see its README for the full written spec.
enum DS {
    // MARK: Colors

    static let bg = Color(hex: 0xFAF1E2)
    static let surface = Color(hex: 0xFFFAF1)
    static let text = Color(hex: 0x2F2415)
    static let divider = DS.text.opacity(0.14)

    static let accent = Color(hex: 0xDD7E2C)
    static let accent100 = Color(hex: 0xFDECD2)
    static let accent200 = Color(hex: 0xFBD9A8)
    static let accent300 = Color(hex: 0xF6C078)
    static let accent400 = Color(hex: 0xEDA552)
    static let accent500 = Color(hex: 0xE08A3C)
    static let accent600 = Color(hex: 0xC96F28)
    static let accent700 = Color(hex: 0xA85720)
    static let accent800 = Color(hex: 0x7C3F19)
    static let accent900 = Color(hex: 0x4A2510)

    static let accent2 = Color(hex: 0xD1573F)
    static let accent2_100 = Color(hex: 0xFBE2DA)
    static let accent2_200 = Color(hex: 0xF6C4B4)
    static let accent2_300 = Color(hex: 0xEEA08A)
    static let accent2_400 = Color(hex: 0xE07C60)
    static let accent2_500 = Color(hex: 0xD1573F)
    static let accent2_600 = Color(hex: 0xB23F2B)
    static let accent2_700 = Color(hex: 0x8F2F20)
    static let accent2_800 = Color(hex: 0x642015)
    static let accent2_900 = Color(hex: 0x3A130C)

    static let neutral100 = Color(hex: 0xFBF6EE)
    static let neutral200 = Color(hex: 0xF2E9D9)
    static let neutral300 = Color(hex: 0xE3D6C0)
    static let neutral400 = Color(hex: 0xCDBC9E)
    static let neutral500 = Color(hex: 0xAB9878)
    static let neutral600 = Color(hex: 0x8A765A)
    static let neutral700 = Color(hex: 0x6B5A42)
    static let neutral800 = Color(hex: 0x493D2C)
    static let neutral900 = Color(hex: 0x2C2417)

    // MARK: Radii

    static let radiusSM: CGFloat = 10
    static let radiusMD: CGFloat = 14
    static let radiusLG: CGFloat = 22

    // MARK: Shadows

    /// Matches the handoff's `--shadow-sm`/`--shadow-md` (a single representative shadow
    /// layer each — SwiftUI's `.shadow` doesn't support the CSS multi-layer syntax, so the
    /// larger, more visually load-bearing layer of each was kept).
    enum ShadowLevel {
        case sm, md

        var color: Color {
            switch self {
            case .sm: Color(hex: 0x784814).opacity(0.10)
            case .md: Color(hex: 0x784814).opacity(0.26)
            }
        }

        var radius: CGFloat {
            switch self {
            case .sm: 2
            case .md: 16
            }
        }

        var y: CGFloat {
            switch self {
            case .sm: 1
            case .md: 8
            }
        }
    }

    // MARK: Typography

    /// Source Serif 4 (the handoff's typeface) ships as a Google Fonts web font only — no
    /// files were included in the design handoff, so this uses SwiftUI's system serif design
    /// (renders as New York) rather than bundling a new font dependency.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Shadow + hover-lift modifiers

private struct DSShadowModifier: ViewModifier {
    var level: DS.ShadowLevel

    func body(content: Content) -> some View {
        content.shadow(color: level.color, radius: level.radius, x: 0, y: level.y)
    }
}

extension View {
    func dsShadow(_ level: DS.ShadowLevel) -> some View {
        modifier(DSShadowModifier(level: level))
    }

    /// Rests at shadow-sm; lifts to shadow-md plus a small upward offset on pointer hover.
    /// Mirrors the handoff's CSS `:hover` depth pattern using macOS's native `.onHover`,
    /// since this is a pointer-driven app, not a touch one.
    func dsLiftOnHover() -> some View {
        modifier(DSHoverLiftModifier())
    }
}

private struct DSHoverLiftModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .dsShadow(isHovering ? .md : .sm)
            .offset(y: isHovering ? -2 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Card

struct DSCard<Content: View>: View {
    var radius: CGFloat = DS.radiusLG
    var padding: CGFloat = 16
    var liftsOnHover = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(DS.divider, lineWidth: 1)
            }
            .modifier(liftsOnHover ? AnyViewModifier(DSHoverLiftModifier()) : AnyViewModifier(DSShadowModifier(level: .sm)))
    }
}

/// Type-erases between the two mutually-exclusive shadow behaviors `DSCard` needs (a plain
/// resting shadow vs. the animated hover-lift) without duplicating `DSCard`'s body per case.
private struct AnyViewModifier: ViewModifier {
    private let apply: (AnyView) -> AnyView
    init<M: ViewModifier>(_ modifier: M) {
        apply = { AnyView($0.modifier(modifier)) }
    }
    func body(content: Content) -> some View {
        apply(AnyView(content))
    }
}

// MARK: - Tag

struct DSTag: View {
    enum Variant {
        case accent, accent2, neutral, outline
    }

    var text: String
    var variant: Variant = .neutral

    var body: some View {
        Text(text)
            .font(DS.font(11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .overlay {
                if variant == .outline {
                    Capsule().stroke(DS.accent300, lineWidth: 1)
                }
            }
    }

    private var background: Color {
        switch variant {
        case .accent: DS.accent100
        case .accent2: DS.accent2_100
        case .neutral: DS.neutral200
        case .outline: .clear
        }
    }

    private var foreground: Color {
        switch variant {
        case .accent: DS.accent800
        case .accent2: DS.accent2_800
        case .neutral: DS.neutral700
        case .outline: DS.accent700
        }
    }
}

// MARK: - Buttons

struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(DS.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundStyle(DS.bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSM))
            .dsShadow(.sm)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(DS.surface.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(DS.neutral700)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSM))
            .overlay {
                RoundedRectangle(cornerRadius: DS.radiusSM).stroke(DS.divider, lineWidth: 1)
            }
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

// MARK: - Text field

struct DSTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DS.font(14))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSM))
            .overlay {
                RoundedRectangle(cornerRadius: DS.radiusSM).stroke(DS.divider, lineWidth: 1)
            }
    }
}

extension TextFieldStyle where Self == DSTextFieldStyle {
    static var ds: DSTextFieldStyle { DSTextFieldStyle() }
}
