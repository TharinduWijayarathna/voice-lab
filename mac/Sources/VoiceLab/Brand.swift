import SwiftUI

enum Brand {
    /// VoiceLab red (#E0242F).
    static let red = Color(red: 0.878, green: 0.141, blue: 0.184)
}

/// The soft red-and-white glow behind the glass, so there is something for it to bend.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.42], [1, 0.5],
        [0, 1], [0.45, 1], [1, 1],
    ]

    private static let light: [Color] = [
        Color(red: 1.00, green: 0.78, blue: 0.78), Color(red: 1.00, green: 0.95, blue: 0.95), Color(red: 1.00, green: 0.70, blue: 0.71),
        Color(red: 1.00, green: 0.93, blue: 0.93), Color(red: 1.00, green: 1.00, blue: 1.00), Color(red: 1.00, green: 0.87, blue: 0.87),
        Color(red: 1.00, green: 0.68, blue: 0.69), Color(red: 1.00, green: 0.90, blue: 0.90), Color(red: 0.97, green: 0.58, blue: 0.60),
    ]

    private static let dark: [Color] = [
        Color(red: 0.36, green: 0.04, blue: 0.07), Color(red: 0.12, green: 0.04, blue: 0.05), Color(red: 0.42, green: 0.06, blue: 0.09),
        Color(red: 0.10, green: 0.03, blue: 0.04), Color(red: 0.07, green: 0.03, blue: 0.035), Color(red: 0.20, green: 0.04, blue: 0.06),
        Color(red: 0.40, green: 0.05, blue: 0.08), Color(red: 0.14, green: 0.04, blue: 0.05), Color(red: 0.30, green: 0.04, blue: 0.07),
    ]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points, colors: scheme == .dark ? Self.dark : Self.light)
            .ignoresSafeArea()
    }
}

/// A large Liquid Glass panel. A little white tint keeps long text easy to read in light mode.
struct GlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat
    var tint: Double

    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: radius))
            .glassEffect(.regular.tint(Color.white.opacity(scheme == .dark ? 0.02 : tint)), in: .rect(cornerRadius: radius))
    }
}

extension View {
    func glassPanel(radius: CGFloat = 26, tint: Double = 0.28) -> some View {
        modifier(GlassPanel(radius: radius, tint: tint))
    }
}
