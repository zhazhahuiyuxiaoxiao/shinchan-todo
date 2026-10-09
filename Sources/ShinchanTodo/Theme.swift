import SwiftUI

enum Crayon {
    static let cream = Color(red: 1, green: 0.973, blue: 0.906)
    static let ink = Color(red: 0.125, green: 0.129, blue: 0.169)
    static let red = Color(red: 0.808, green: 0.231, blue: 0.231)
    static let yellow = Color(red: 0.965, green: 0.839, blue: 0.420)
    static let sky = Color(red: 0.788, green: 0.910, blue: 0.937)
    static let paper = Color(red: 1, green: 0.988, blue: 0.953)
    static let muted = Color(red: 0.33, green: 0.33, blue: 0.31)
}
struct CrayonButton: ButtonStyle {
    var fill: Color = Crayon.yellow
    var foreground: Color = Crayon.ink
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .bold, design: .rounded))
            .padding(.horizontal, 16).padding(.vertical, 11).foregroundStyle(foreground)
            .background {
                // 阴影仅由背景形状绘制，不能让文字和图标也产生偏移副本。
                RoundedRectangle(cornerRadius: 12).fill(fill)
                    .shadow(color: Crayon.ink, radius: 0, x: configuration.isPressed ? 0 : 2, y: configuration.isPressed ? 0 : 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Crayon.ink, lineWidth: 2))
            .offset(y: configuration.isPressed ? 2 : 0).opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct PaperPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18).background(Crayon.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crayon.ink, lineWidth: 1.5))
    }
}
extension View { func paperPanel() -> some View { modifier(PaperPanel()) } }
struct ShinchanDecoration: View {
    var width: CGFloat = 110
    var body: some View {
        Group {
            if let image = loadImage() { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "face.smiling").resizable().scaledToFit().foregroundStyle(Crayon.yellow) }
        }.frame(width: width, height: width * 0.75).accessibilityHidden(true)
    }
    private func loadImage() -> NSImage? {
        // .app 使用标准 Resources 路径；swift run 使用 SwiftPM 资源目录。
        if let url = Bundle.main.url(forResource: "Shinchan", withExtension: "png") { return NSImage(contentsOf: url) }
        return Bundle.module.url(forResource: "Shinchan", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
}
