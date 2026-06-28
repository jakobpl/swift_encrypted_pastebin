import SwiftUI

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 28
    var material: Material = .ultraThinMaterial
    var strokeOpacity: Double = 0.42

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(strokeOpacity), lineWidth: 1.15)
            }
    }
}

extension View {
    func glassPanel(
        cornerRadius: CGFloat = 28,
        material: Material = .ultraThinMaterial,
        strokeOpacity: Double = 0.34
    ) -> some View {
        modifier(
            GlassPanel(
                cornerRadius: cornerRadius,
                material: material,
                strokeOpacity: strokeOpacity
            )
        )
    }
}
