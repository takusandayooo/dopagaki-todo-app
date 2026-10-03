import SwiftUI

enum DopaTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.12)
    static let surface = Color(red: 0.075, green: 0.105, blue: 0.19)
    static let elevated = Color(red: 0.12, green: 0.16, blue: 0.27)
    static let blue = Color(red: 0.2, green: 0.43, blue: 1)
    static let green = Color(red: 0.32, green: 0.9, blue: 0.48)
    static let gold = Color(red: 1, green: 0.77, blue: 0.22)
    static let secondary = Color(red: 0.61, green: 0.67, blue: 0.79)
    static let border = Color.white.opacity(0.08)
    static let grass: [Color] = [
        elevated, Color(red: 0.07, green: 0.29, blue: 0.2),
        Color(red: 0.09, green: 0.48, blue: 0.29),
        Color(red: 0.13, green: 0.7, blue: 0.36), green
    ]

    static func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value >= 3600 { return "\(value / 3600)時間\((value % 3600) / 60)分" }
        if value >= 60 { return "\(value / 60)分\(value % 60)秒" }
        return "\(value)秒"
    }

    static func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value >= 3600 { return String(format: "%02d:%02d:%02d", value / 3600, value % 3600 / 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct DopaCard<Content: View>: View {
    var color: Color = DopaTheme.surface
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DopaTheme.border, lineWidth: 1))
    }
}

struct DopaButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = DopaTheme.blue
    var foreground: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(color, in: RoundedRectangle(cornerRadius: 17))
            .shadow(color: color.opacity(0.3), radius: 0, y: configuration.isPressed ? 1 : 5)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Opt in only for primary task and timer controls; content cards stay opaque.
struct DopaGlassButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var color: Color = DopaTheme.blue
    var foreground: Color = .white
    var prominent = true

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            if prominent {
                glassButton(configuration)
                    .buttonStyle(.glassProminent)
                    .tint(color)
                    .foregroundStyle(foreground)
            } else {
                glassButton(configuration)
                    .buttonStyle(.glass)
                    .foregroundStyle(foreground)
            }
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(DopaButtonStyle(color: color, foreground: foreground))
        }
    }

    private func glassButton(_ configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.system(.headline, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32)
                .padding(.horizontal, 4)
        }
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 17))
    }
}

/// Preserve the reward button's gold color and layout on every supported OS.
struct DopaRewardSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.tint(DopaTheme.gold).interactive(!reduceMotion),
                                in: RoundedRectangle(cornerRadius: 18))
        } else {
            content.background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 1, green: 0.85, blue: 0.2))
                    .shadow(color: Color(red: 0.75, green: 0.44, blue: 0.01), radius: 0, y: 5)
            }
        }
    }
}

struct DopaPageModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            page(content)
        } else {
            page(content)
                .toolbarBackground(DopaTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func page(_ content: Content) -> some View {
        content
            .fontDesign(.rounded)
            .foregroundStyle(.white)
            .background(DopaTheme.background.ignoresSafeArea())
            .tint(DopaTheme.green)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func dopaPage() -> some View { modifier(DopaPageModifier()) }
}

struct DopaEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(DopaTheme.green)
                .padding(20)
                .background(DopaTheme.green.opacity(0.09), in: Circle())
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(DopaTheme.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }
}

struct DopaSectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let detail { Text(detail).font(.caption.bold()).foregroundStyle(DopaTheme.secondary) }
        }
    }
}

struct DopaMetric: View {
    let symbol: String
    let value: String
    let label: String
    var accent: Color = DopaTheme.green
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(value).font(.system(.title2, design: .rounded, weight: .heavy)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DopaTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
