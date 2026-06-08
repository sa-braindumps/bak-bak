import SwiftUI

// MARK: - Color Palette (Bold Dark)

enum AppColors {
    // Base layers — deep charcoal with warmth
    static let background = Color(white: 0.06)
    static let elevatedBg = Color(white: 0.09)

    // Sidebar — slightly lighter, subtle warmth
    static let sidebarBg = Color(white: 0.08)
    static let sidebarHover = Color(white: 0.13)
    static let sidebarSelected = Color(white: 0.15)

    // Cards — high contrast against background
    static let cardBg = Color(white: 0.11)
    static let cardBgHover = Color(white: 0.14)
    static let cardBorder = Color.white.opacity(0.08)
    static let cardBorderHover = Color.white.opacity(0.14)

    // Accent — a clean steel blue
    static let accent = Color(red: 0.22, green: 0.50, blue: 0.84)
    static let accentBright = Color(red: 0.38, green: 0.62, blue: 0.94)
    static let accentDim = accent.opacity(0.12)
    static let accentGlow = accent.opacity(0.20)
    static let accentGradientStart = Color(red: 0.22, green: 0.50, blue: 0.84)
    static let accentGradientEnd = Color(red: 0.22, green: 0.50, blue: 0.84)

    // Text — clear hierarchy
    static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let textSecondary = Color(red: 0.70, green: 0.70, blue: 0.73)
    static let textMuted = Color(red: 0.42, green: 0.42, blue: 0.46)
    static let textOnAccent = Color.white

    // Dividers & structure
    static let divider = Color.white.opacity(0.06)
    static let dividerStrong = Color.white.opacity(0.10)

    // Timeline
    static let timelineDot = Color(red: 0.35, green: 0.35, blue: 0.40)
    static let timelineLine = Color.white.opacity(0.07)

    // Charts
    static let barFillStart = Color(red: 0.20, green: 0.66, blue: 0.86)
    static let barFillEnd = Color(red: 0.20, green: 0.66, blue: 0.86).opacity(0.15)
    static let barGhost = Color.white.opacity(0.04)

    // Semantic
    static let deleteRed = Color(red: 0.95, green: 0.30, blue: 0.30)
    static let successGreen = Color(red: 0.25, green: 0.82, blue: 0.50)
    static let warningAmber = Color(red: 0.95, green: 0.72, blue: 0.20)

    // Inputs
    static let inputBg = Color(white: 0.07)
    static let inputBorder = Color.white.opacity(0.10)
    static let inputBorderFocus = accent.opacity(0.5)

    // Overlay
    static let overlay = Color.black.opacity(0.60)
}

// MARK: - Spacing

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum AppRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 18
    static let pill: CGFloat = 100
}

// MARK: - Shadows

enum AppShadow {
    static let card = Color.black.opacity(0.25)
    static let cardElevated = Color.black.opacity(0.40)
    static let glow = AppColors.accent.opacity(0.15)
}

// MARK: - Fonts

extension Font {
    static let appLargeTitle = Font.system(size: 20, weight: .semibold)
    static let appTitle = Font.system(size: 14, weight: .semibold)
    static let appSectionTitle = Font.system(size: 11, weight: .semibold)
    static let appHeadline = Font.system(size: 13, weight: .medium)
    static let appBody = Font.system(size: 13, weight: .regular)
    static let appCaption = Font.system(size: 11, weight: .regular)
    static let appCaptionBold = Font.system(size: 11, weight: .semibold)
    static let appMonospaced = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let appStatValue = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let appStatLabel = Font.system(size: 10, weight: .medium)
    static let appChartLabel = Font.system(size: 9, weight: .regular)
    static let appNavIcon = Font.system(size: 14, weight: .medium)
    static let appEmptyIcon = Font.system(size: 32, weight: .light)
    static let appBrand = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let appBrandSub = Font.system(size: 10, weight: .medium, design: .rounded)
}

// MARK: - Card Modifier (with shadow depth)

struct CardStyle: ViewModifier {
    var padding: CGFloat = AppSpacing.md
    var showBorder: Bool = true
    var showShadow: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                showBorder
                    ? RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.cardBorder, lineWidth: 0.5)
                    : nil
            )
            .shadow(color: showShadow ? AppShadow.card : .clear, radius: showShadow ? 8 : 0, y: showShadow ? 2 : 0)
    }
}

extension View {
    func cardStyle(padding: CGFloat = AppSpacing.md, showBorder: Bool = true, showShadow: Bool = true) -> some View {
        modifier(CardStyle(padding: padding, showBorder: showBorder, showShadow: showShadow))
    }
}

// MARK: - App Background Modifier

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.background.ignoresSafeArea())
    }
}

extension View {
    func appBackground() -> some View {
        modifier(AppBackground())
    }
}

// MARK: - Glow Effect

struct GlowEffect: ViewModifier {
    let color: Color
    var radius: CGFloat = 20
    var opacity: Double = 0.3

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func glow(color: Color = AppColors.accent, radius: CGFloat = 20, opacity: Double = 0.3) -> some View {
        modifier(GlowEffect(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Timeline Dot

struct TimelineDot: View {
    var isActive: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? AppColors.accent : AppColors.timelineDot)
                .frame(width: 8, height: 8)
            if isActive {
                Circle()
                    .fill(AppColors.accentGlow)
                    .frame(width: 18, height: 18)
            }
        }
    }
}

// MARK: - Timeline Connector

struct TimelineConnector: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.timelineLine)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.leading, 3.5)
    }
}

// MARK: - Row Hover Modifier (macOS 13+)

struct RowHoverModifier: ViewModifier {
    @State private var isHovering = false
    var hoverColor: Color = AppColors.sidebarHover

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(isHovering ? hoverColor : Color.clear)
                    .animation(.easeOut(duration: 0.15), value: isHovering)
            )
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
    }
}

extension View {
    func rowHover(hoverColor: Color = AppColors.sidebarHover) -> some View {
        modifier(RowHoverModifier(hoverColor: hoverColor))
    }
}

// MARK: - Accent Button Style

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCaptionBold)
            .foregroundColor(AppColors.textOnAccent)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm + 2)
            .background(
                LinearGradient(
                    colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            .shadow(color: AppColors.accent.opacity(0.25), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Pill Badge

struct PillBadge: View {
    let text: String
    var color: Color = AppColors.accent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs + 1)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Gradient Accent Line (decorative top border for cards)

struct AccentLine: View {
    var body: some View {
        LinearGradient(
            colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 2)
        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
    }
}

// MARK: - Section Header with Accent

struct AccentSectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(
                    LinearGradient(
                        colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 14)
            Text(title)
                .font(.appSectionTitle)
                .foregroundColor(AppColors.textPrimary)
                .tracking(0.3)
        }
    }
}
