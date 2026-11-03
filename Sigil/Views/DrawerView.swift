import SwiftUI

/// The drawer body grows out of the screen edge: concave flares where it meets
/// the edge, rounded corners on the free side.
struct DrawerShape: Shape {
    var side: DrawerSide
    var flare: CGFloat = 20
    var corner: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let f = min(flare, w / 2, h / 4)
        let r = max(0, min(corner, w - f, (h - 2 * f) / 2))

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: f, y: f), control: CGPoint(x: 0, y: f))
        p.addArc(tangent1End: CGPoint(x: w, y: f), tangent2End: CGPoint(x: w, y: h), radius: r)
        p.addArc(tangent1End: CGPoint(x: w, y: h - f), tangent2End: CGPoint(x: 0, y: h - f), radius: r)
        p.addLine(to: CGPoint(x: f, y: h - f))
        p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: 0, y: h - f))
        p.closeSubpath()

        let placed = p.offsetBy(dx: rect.minX, dy: rect.minY)
        guard side == .right else { return placed }
        return placed.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }
}

struct DrawerView<Content: View>: View {
    let state: DrawerState
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var flare: CGFloat { 20 }

    var body: some View {
        GeometryReader { geo in
            let open = state.isOpen || reduceMotion
            let edge: Alignment = state.side == .left ? .leading : .trailing
            let shape = DrawerShape(side: state.side, flare: Self.flare)

            ZStack(alignment: edge) {
                shape
                    .fill(Color(white: 0.035))
                    .overlay(shape.stroke(.white.opacity(0.09), lineWidth: 1))
                    // Width and height on different springs: it stretches out of the edge, then fills in
                    .animation(.spring(response: state.isOpen ? 0.42 : 0.3, dampingFraction: 0.74)) {
                        $0.frame(height: open ? geo.size.height : geo.size.height * 0.28)
                    }
                    .animation(.spring(response: state.isOpen ? 0.34 : 0.26, dampingFraction: 0.8)) {
                        $0.frame(width: open ? geo.size.width : 10)
                    }
                    .opacity(state.isOpen ? 1 : 0)
                    .animation(state.isOpen ? nil : .easeIn(duration: 0.2).delay(0.14), value: state.isOpen)

                content
                    .padding(.top, Self.flare + 10)
                    .padding(.bottom, Self.flare + 6)
                    .padding(state.side == .left ? .leading : .trailing, 6)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(state.isOpen ? 1 : 0)
                    .offset(x: state.isOpen || reduceMotion ? 0 : (state.side == .left ? -28 : 28))
                    .animation(
                        state.isOpen ? .spring(response: 0.4, dampingFraction: 0.86).delay(0.08) : .easeIn(duration: 0.12),
                        value: state.isOpen
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: edge)
        }
        .environment(\.colorScheme, .dark)
    }
}
