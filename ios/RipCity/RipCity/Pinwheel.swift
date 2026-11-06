//  Pinwheel.swift — the menu, tucked into a pinwheel in the bottom-right
//  corner (the native cousin of Primes' ToolFan).
//
//  Closed, five red blades and five light blades curl around the hub. Opening
//  animates one number, `t`, from 0 to 1: each red blade uncurls, swings
//  round and stretches into a straight spoke that ends at its menu item,
//  while the light blades wind into the centre and fade. While the fan is
//  open, one full-screen layer takes every tap and picks the nearest item.
//  Each label sits just outside its item along the fan's direction, offset by
//  the label's reach along that direction (|ux|·w/2 + |uy|·h/2), so none collide.

import SwiftUI

/// The pinwheel mark, for the menu button and the app icon.
/// Angles are screen angles in degrees (0 = right, 90 = down).
struct Blades: Shape {
    var t: CGFloat                       // 0 = pinwheel, 1 = spokes
    var hub: CGPoint
    var base: [Double]                   // where each blade starts, closed
    var target: [Double]                 // where each spoke points, open
    var inner: CGFloat = 3, outer: CGFloat = 23, curl: Double = 58
    var spokeFrom: CGFloat = 38, spokeTo: CGFloat = 116

    var animatableData: CGFloat { get { t } set { t = newValue } }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, b) in base.enumerated() {
            let goal = i < target.count ? target[i] : b
            // Swing the shortest way round.
            var d = (goal - b).truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 } else if d < -180 { d += 360 }
            let steps = 18
            for k in 0...steps {
                let s = CGFloat(k) / CGFloat(steps)
                let rClosed = inner + (outer - inner) * s
                let rOpen = spokeFrom + (spokeTo - spokeFrom) * s
                let r = rClosed + (rOpen - rClosed) * t
                let aClosed = b + curl * Double(s)
                let aOpen = b + d
                let a = (aClosed + (aOpen - aClosed) * Double(t)) * .pi / 180
                let pt = CGPoint(x: hub.x + cos(a) * r, y: hub.y + sin(a) * r)
                k == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
        }
        return p
    }
}

struct PinwheelMark: View {
    var size: CGFloat = 64
    var body: some View {
        let hub = CGPoint(x: size / 2, y: size / 2), k = size / 64
        ZStack {
            Circle().fill(T.band)
            Blades(t: 0, hub: hub, base: PinwheelMenu.lightBase, target: [], inner: 3 * k, outer: 23 * k)
                .stroke(T.bandInk, style: StrokeStyle(lineWidth: 3.6 * k, lineCap: .round))
            Blades(t: 0, hub: hub, base: PinwheelMenu.redBase, target: [], inner: 3 * k, outer: 23 * k)
                .stroke(T.red, style: StrokeStyle(lineWidth: 3.6 * k, lineCap: .round))
        }.frame(width: size, height: size)
    }
}

struct PinwheelMenu: View {
    @Environment(Store.self) private var store
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = 64                       // screens keep this corner clear
    static let redBase = (0..<5).map { -90 + Double($0) * 72 }
    static let lightBase = (0..<5).map { -54 + Double($0) * 72 }
    private let radius: CGFloat = 150
    private let dot: CGFloat = 50
    private let area = CGSize(width: 300, height: 260)
    private var hub: CGPoint { CGPoint(x: area.width - Self.size / 2, y: area.height - Self.size / 2) }
    /// Offset from the fan's centre to a point in it.
    private func shift(_ p: CGPoint) -> CGSize { CGSize(width: p.x - area.width / 2, height: p.y - area.height / 2) }

    private struct Item: Identifiable {
        let title: String; let symbol: String; let angle: Double   // math degrees; 90 is straight up
        let go: (Store) -> Void
        var id: String { title }
    }

    private var items: [Item] {
        let angles = (0..<5).map { 92 + Double($0) * 23.5 }
        return [
            Item(title: "Tonight", symbol: "basketball.fill", angle: angles[0]) { s in
                if let g = s.featured { s.path = [.game(g.id)] } else { s.path = [.schedule] } },
            Item(title: "Standings", symbol: "trophy.fill", angle: angles[1]) { $0.path = [.results] },
            Item(title: "Schedule", symbol: "calendar", angle: angles[2]) { $0.path = [.schedule] },
            Item(title: "Yearbook", symbol: "book.pages.fill", angle: angles[3]) { $0.path = [.roster] },
            Item(title: "Home", symbol: "house.fill", angle: angles[4]) { $0.path = [] },
        ]
    }

    var body: some View {
        GeometryReader { geo in
            // Where the fan's frame sits in this full-screen layer.
            let origin = CGPoint(x: geo.size.width - 14 - area.width, y: geo.size.height - 6 - area.height)
            ZStack(alignment: .topLeading) {
                if open {
                    T.bg.opacity(0.78).ignoresSafeArea()
                        .transition(.opacity)
                        .accessibilityHidden(true)
                        .zIndex(0)
                }
                fan.frame(width: area.width, height: area.height)
                    .offset(x: origin.x, y: origin.y)
                    .zIndex(1)
                // While open, one layer takes every tap and works out what it hit:
                // an item, the hub, or anywhere else (which folds the fan away).
                // Buttons placed in a fan like this don't reliably get taps of their
                // own, so they stay only for VoiceOver.
                if open {
                    Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                        .onTapGesture(coordinateSpace: .local) { loc in tap(CGPoint(x: loc.x - origin.x, y: loc.y - origin.y)) }
                        .accessibilityHidden(true)
                        .zIndex(2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func spot(_ item: Item) -> CGPoint {
        CGPoint(x: hub.x + cos(item.angle * .pi / 180) * radius, y: hub.y - sin(item.angle * .pi / 180) * radius)
    }

    private func tap(_ p: CGPoint) {
        let near = items.min { hypot(spot($0).x - p.x, spot($0).y - p.y) < hypot(spot($1).x - p.x, spot($1).y - p.y) }
        if let near, hypot(spot(near).x - p.x, spot(near).y - p.y) <= dot / 2 + 10 { choose(near) } else { toggle() }
    }

    private func choose(_ item: Item) {
        item.go(store)
        toggle()
    }

    private var fan: some View {
        ZStack {
            let anchor = UnitPoint(x: hub.x / area.width, y: hub.y / area.height)
            Circle().fill(T.band)
                .overlay(Circle().stroke(T.bandInk.opacity(open ? 0.35 : 0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
                .frame(width: Self.size, height: Self.size)
                .offset(shift(hub))
                .allowsHitTesting(false)
            Blades(t: 0, hub: hub, base: Self.lightBase, target: [])
                .stroke(T.bandInk, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                .rotationEffect(.degrees(open ? 160 : 0), anchor: anchor)
                .scaleEffect(open ? 0.15 : 1, anchor: anchor)
                .opacity(open ? 0 : 1)
                .allowsHitTesting(false)
            // Spokes are drawn in the whole fan's frame so they can reach the items.
            Blades(t: open ? 1 : 0, hub: hub, base: Self.redBase, target: items.map { -$0.angle }, spokeTo: radius - dot / 2 - 5)
                .stroke(T.red, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                .allowsHitTesting(false)
            ForEach(items) { item in itemView(item) }
            Button { toggle() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(T.bandInk)
                    .opacity(open ? 1 : 0).scaleEffect(open ? 1 : 0.3)
                    .frame(width: Self.size, height: Self.size).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(shift(hub))
            .accessibilityLabel(open ? "Close menu" : "Menu")
            .accessibilityHint("Tonight, Standings, Schedule, Yearbook and Home")
        }
    }

    @ViewBuilder private func itemView(_ item: Item) -> some View {
        let ux = cos(item.angle * .pi / 180), uy = -sin(item.angle * .pi / 180)
        let label = CGSize(width: CGFloat(item.title.count) * 8 + 20, height: 28)
        let reach = abs(ux) * label.width / 2 + abs(uy) * label.height / 2
        let out = dot / 2 + 6 + reach
        let at = open ? CGPoint(x: hub.x + ux * radius, y: hub.y + uy * radius) : hub
        Text(item.title)
            .font(T.body(13.5, .semibold))
            .foregroundStyle(T.ink)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: label.height)
            .background(T.panel, in: Capsule())
            .overlay(Capsule().stroke(T.line))
            .offset(shift(CGPoint(x: at.x + ux * out, y: at.y + uy * out)))
            .opacity(open ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        Button { choose(item) } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(T.ink)
                .frame(width: dot, height: dot)
                .background(T.panel, in: Circle())
                .overlay(Circle().stroke(T.red, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .scaleEffect(open || reduceMotion ? 1 : 0.3)
        .offset(shift(at))
        .opacity(open ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(!open)
    }

    private func toggle() {
        Haptics.tick()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.74)) { open.toggle() }
    }
}
