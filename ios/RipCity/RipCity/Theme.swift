//  Theme.swift — the web page's colors and type, rebuilt with built-in fonts:
//  a compressed heavy San Francisco stands in for Big Shoulders Display.

import SwiftUI
import UIKit

extension Color {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum T {
    static let bg = Color.dyn(0xEEEDEA, 0x101012)
    static let panel = Color.dyn(0xFFFFFF, 0x1A1A1E)
    static let ink = Color.dyn(0x141416, 0xF2F0EC)
    static let muted = Color.dyn(0x68666C, 0x9C99A0)
    static let line = Color.dyn(0xD9D6D0, 0x2E2D33)
    static let accent = Color.dyn(0xD3202F, 0xFF4655)
    static let accentInk = Color.dyn(0xFFFFFF, 0x16080A)
    static let band = Color.dyn(0x141416, 0x000000)
    static let bandInk = Color.dyn(0xF4F2EE, 0xF2F0EC)
    static let good = Color.dyn(0x1D8048, 0x5BD28A)
    static let goodBg = Color.dyn(0xE3F1E8, 0x16301F)
    static let badBg = Color.dyn(0xECEAE7, 0x232227)
    static let push = Color.dyn(0x6A5A2A, 0xD8C27A)
    /// Pinwheel red: the stripe color, the same in both modes.
    static let red = Color(UIColor(hex: 0xE03A3E))

    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font { .system(size: size, weight: weight).width(.compressed) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static let kicker = Font.system(size: 12, weight: .bold)
}

struct Kicker: View {
    let text: String; var color: Color = T.muted
    init(_ text: String, color: Color = T.muted) { self.text = text; self.color = color }
    var body: some View { Text(text.uppercased()).font(T.kicker).tracking(1.4).foregroundStyle(color) }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(padding)
            .background(T.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(T.line))
    }
}

struct Chip: View {
    let text: String; var hot = false; var done = false
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11.5, weight: .bold)).tracking(0.6).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(hot ? T.accentInk : done ? T.good : T.muted)
            .background(hot ? T.accent : done ? T.goodBg : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(hot ? T.accent : done ? .clear : T.line))
    }
}

/// +1 / −1 / 0 badge.
struct Points: View {
    let n: Int
    var body: some View {
        Text(signed(n)).font(.system(size: 14, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(n > 0 ? T.good : n < 0 ? T.muted : T.push)
            .background(n > 0 ? T.goodBg : T.badBg, in: Capsule())
    }
}

struct Stripes: View {
    var width: CGFloat = 84
    var body: some View {
        HStack(spacing: 5) { ForEach(0..<3) { i in Capsule().fill(i == 1 ? T.accent : T.ink).frame(height: 6) } }.frame(width: width)
    }
}

/// The black scoreboard band with both teams.
struct Board<Extra: View>: View {
    let g: Game
    @ViewBuilder var extra: Extra
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("\(g.isToday ? "Tonight" : Fmt.long(g.tipDate)) · \(Fmt.time(g.tipDate))\(g.final != nil ? " · Final" : "")", color: T.bandInk.opacity(0.62))
            HStack(alignment: .center) {
                team(g.home ? g.opp : "POR", g.home ? g.oppName : "Trail Blazers", score: g.home ? g.final?.oppScore : g.final?.porScore, por: !g.home, trailing: false)
                Spacer()
                Text("at").font(T.display(26, .bold)).foregroundStyle(T.bandInk.opacity(0.5))
                Spacer()
                team(g.home ? "POR" : g.opp, g.home ? "Trail Blazers" : g.oppName, score: g.home ? g.final?.porScore : g.final?.oppScore, por: g.home, trailing: true)
            }
            extra
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(T.bandInk)
        .background(T.band, in: RoundedRectangle(cornerRadius: 18))
    }
    private func team(_ abbr: String, _ name: String, score: Double?, por: Bool, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(abbr).font(T.display(58)).foregroundStyle(por ? T.red : T.bandInk)
            Text(name).font(T.body(13)).foregroundStyle(T.bandInk.opacity(0.75)).lineLimit(1)
            if let score { Text(fmtLine(score)).font(.system(size: 22, weight: .bold, design: .monospaced)) }
        }
    }
}

extension Board where Extra == EmptyView { init(g: Game) { self.g = g; self.extra = EmptyView() } }

struct BigButton: View {
    let title: String; var ghost = false; var onBand = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(T.body(17, .bold)).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(ghost ? (onBand ? T.bandInk : T.ink) : T.accentInk)
                .background(ghost ? Color.clear : T.accent, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ghost ? (onBand ? T.bandInk.opacity(0.4) : T.ink) : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
}

enum Haptics {
    static func tick() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thunk() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}
