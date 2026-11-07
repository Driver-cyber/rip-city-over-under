//  GameView.swift — one game's picks, as a list or as a deck of cards you
//  swipe (right = Blazers / Over / Yes, left = the other team / Under / No).
//  After tip-off it shows everyone's picks, the finals and the points.

import SwiftUI

struct GameView: View {
    @Environment(Store.self) private var store
    @AppStorage("ripcity.view") private var mode = "cards"
    let id: String

    var body: some View {
        if let g = store.game(id) {
            if g.hasLines && !g.locked && mode == "cards" {
                DeckView(g: g, mode: $mode)
            } else {
                ListPicks(g: g, mode: $mode)
            }
        } else {
            Page { Card { Text("That game isn't on the schedule.") } }
        }
    }
}

struct ModeToggle: View {
    @Binding var mode: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(["cards", "list"], id: \.self) { m in
                Button { mode = m; Haptics.tick() } label: {
                    Text(m.capitalized).font(T.body(13, .bold)).padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(mode == m ? T.bg : T.muted)
                        .background(mode == m ? T.ink : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(3).overlay(Capsule().stroke(T.line, lineWidth: 1.5))
    }
}

// MARK: - list

struct ListPicks: View {
    @Environment(Store.self) private var store
    let g: Game
    @Binding var mode: String

    var body: some View {
        let mine = store.myPick(g.id) ?? Pick(winner: nil, q: [:])
        let fin = g.final
        let pickers = store.players.map(\.id).filter { store.picks[$0]?[g.id] != nil }
        let others = g.locked ? pickers.filter { $0 != store.uid } : (store.pickedBy[g.id] ?? [])
        let done = (mine.winner != nil ? 1 : 0) + g.qs.filter { mine.q?[$0.id] != nil }.count
        Page {
            Board(g: g)
            OfflineBanner()
            if !g.hasLines {
                Card { Text("Lines for this game go up automatically the day before.") }
            } else {
                if !g.locked { ModeToggle(mode: $mode) }
                if g.locked {
                    if let fin, fin.winner != nil, let s = scoreGame(g, store.myPick(g.id)) {
                        HStack(spacing: 6) { Text("Your game:"); Points(n: s.pts); Text("(\(s.record))").foregroundStyle(T.muted) }.font(T.body(15))
                    } else {
                        Text(fin == nil ? "Picks locked at tip-off. Results go up automatically after the game." : "Final.").font(T.body(14)).foregroundStyle(T.muted)
                    }
                } else {
                    Progress(done: done, total: g.qs.count + 1, note: others.isEmpty ? "Locks at tip-off" : "\(others.map(store.name).joined(separator: ", ")) \(others.count > 1 ? "have" : "has") picked")
                }
                winnerCard(mine: mine, fin: fin, pickers: pickers)
                let por = g.qs.filter { $0.k == .stat && $0.team == "POR" }
                let opp = g.qs.filter { $0.k == .stat && $0.team != "POR" }
                let fun = g.qs.filter { $0.k != .stat }
                section("Blazers", por, mine, fin, pickers)
                section(g.oppName, opp, mine, fin, pickers)
                section("Commissioner's specials", fun, mine, fin, pickers)
                if !g.locked {
                    Text("Picks save as you tap. Tap a pick again to clear it. Everyone's picks show here after tip-off.").font(T.body(14)).foregroundStyle(T.muted)
                } else if fin == nil {
                    BigButton(title: "See the leaderboard", ghost: true) { store.path.append(.results) }
                }
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func section(_ title: String, _ qs: [Question], _ mine: Pick, _ fin: Final?, _ pickers: [String]) -> some View {
        if !qs.isEmpty {
            Kicker(title)
            ForEach(qs) { q in qCard(q, mine, fin, pickers) }
        }
    }

    private func winnerCard(mine: Pick, fin: Final?, pickers: [String]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) { Text("Who wins?").font(T.body(17, .bold)); Text("Straight up, no spread").font(T.body(13)).foregroundStyle(T.muted) }
                HStack(spacing: 8) {
                    ForEach([("POR", "Trail Blazers"), (g.opp, g.oppName)], id: \.0) { abbr, name in
                        SegButton(on: mine.winner == abbr, enabled: !g.locked) {
                            VStack(spacing: 0) { Text(abbr).font(T.display(30)); Text(name).font(T.body(12)).opacity(0.8).lineLimit(1) }
                        } action: { Haptics.tick(); store.setPick(g.id, .winner, abbr) }
                    }
                }
                if let w = fin?.winner {
                    FinalRow(text: "Winner: \(w)\(fin?.porScore != nil ? "  \(fmtLine(fin?.porScore))–\(fmtLine(fin?.oppScore))" : "")", mark: Score.markW(mine.winner, fin))
                }
                if g.locked { OthersRow(pickers: pickers, pick: { store.picks[$0]?[g.id]?.winner }, mark: { Score.markW($0, fin) }) }
            }
        }
    }

    private func qCard(_ q: Question, _ mine: Pick, _ fin: Final?, _ pickers: [String]) -> some View {
        let pk = mine.q?[q.id], v = fin?.values?[q.id], voided = fin?.voided?.contains(q.id) ?? false
        let opts = q.isYN ? [("yes", "Yes", "checkmark"), ("no", "No", "xmark")] : [("over", "Over", "arrowtriangle.up.fill"), ("under", "Under", "arrowtriangle.down.fill")]
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.title).font(T.body(17, .bold))
                        Text(q.k == .stat ? "\(q.team ?? "") · \(statNames[q.stat ?? ""] ?? q.stat ?? "")" : q.isYN ? "Commissioner's special · yes or no" : "Commissioner's special")
                            .font(T.body(13)).foregroundStyle(T.muted)
                    }
                    Spacer()
                    if !q.isYN {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(fmtLine(q.line)).font(.system(size: 28, weight: .bold, design: .monospaced))
                            Text(q.k == .stat ? (q.stat ?? "") : "line").font(T.body(12)).foregroundStyle(T.muted)
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(opts, id: \.0) { val, label, icon in
                        SegButton(on: pk == val, enabled: !g.locked) {
                            HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 12, weight: .bold)); Text(label).font(T.body(16, .bold)) }
                        } action: { Haptics.tick(); store.setPick(g.id, .question(q.id), val) }
                    }
                }
                if let v {
                    FinalRow(text: "\(q.isYN ? "Result" : "Final"): \(q.isYN ? (v == 1 ? "Yes" : "No") : fmtLine(v)) \(q.k == .stat ? (q.stat ?? "") : "")", mark: Score.markQ(pk, q, fin))
                } else if voided {
                    Text("Didn't play. No points either way.").font(T.body(14)).foregroundStyle(T.muted)
                } else if fin != nil && q.k != .stat {
                    Text("Waiting on the commissioner to grade this one.").font(T.body(14)).foregroundStyle(T.muted)
                }
                if g.locked { OthersRow(pickers: pickers, pick: { store.picks[$0]?[g.id]?.q?[q.id] }, mark: { Score.markQ($0, q, fin) }) }
            }
        }
        .overlay(q.k != .stat ? RoundedRectangle(cornerRadius: 16).strokeBorder(T.ink, style: StrokeStyle(lineWidth: 1, dash: [5, 4])) : nil)
    }
}

struct SegButton<Label: View>: View {
    let on: Bool; let enabled: Bool
    @ViewBuilder let label: Label
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            label.frame(maxWidth: .infinity, minHeight: 50).padding(.vertical, 4)
                .foregroundStyle(on ? T.bg : T.ink)
                .background(on ? T.ink : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? T.ink : T.line, lineWidth: 1.5))
                .opacity(!enabled && !on ? 0.45 : 1)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct FinalRow: View {
    let text: String; let mark: Int?
    var body: some View {
        HStack { Text(text).font(T.body(15, .semibold)); Spacer(); if let mark { Points(n: mark) } }
            .padding(.top, 10).overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 1) }
    }
}

struct OthersRow: View {
    @Environment(Store.self) private var store
    let pickers: [String]
    let pick: (String) -> String?
    let mark: (String) -> Int?
    var body: some View {
        if !pickers.isEmpty {
            FlowRow {
                ForEach(pickers, id: \.self) { p in
                    let pk = pick(p), m = pk.flatMap(mark)
                    HStack(spacing: 4) {
                        Text("\(store.name(p)): \(pk.map(pickLabel) ?? "—")")
                        if let m { Text(signed(m)).font(.system(size: 13, weight: .bold, design: .monospaced)) }
                    }
                    .font(T.body(13, .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(m == 1 ? T.good : m == 0 ? T.push : T.ink)
                    .background(m == 1 ? T.goodBg : T.badBg, in: Capsule())
                }
            }
        }
    }
}

/// Wraps chips onto as many rows as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320; var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }; x += z.width + spacing; row = max(row, z.height) }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > b.maxX, x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += z.width + spacing; row = max(row, z.height) }
    }
}

struct Progress: View {
    let done: Int; let total: Int; let note: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(done)/\(total)").font(.system(size: 14, weight: .bold, design: .monospaced))
            GeometryReader { geo in
                ZStack(alignment: .leading) { Capsule().fill(T.line); Capsule().fill(T.accent).frame(width: geo.size.width * CGFloat(done) / CGFloat(max(total, 1))) }
            }.frame(height: 6)
            Text(note).font(T.body(13)).foregroundStyle(T.muted).lineLimit(1)
        }
    }
}

// MARK: - cards

struct DeckView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let g: Game
    @Binding var mode: String
    @State private var index: Int? = nil
    @State private var drag: CGSize = .zero
    @State private var flying = false

    private enum Item: Identifiable { case winner, q(Question)
        var id: String { if case .q(let q) = self { return q.id }; return "winner" } }
    private var items: [Item] { [.winner] + g.qs.map { .q($0) } }
    private func pick(_ it: Item) -> String? {
        let m = store.myPick(g.id)
        if case .q(let q) = it { return m?.q?[q.id] }
        return m?.winner
    }

    var body: some View {
        let i = index ?? items.firstIndex { pick($0) == nil } ?? items.count
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.home ? "\(g.opp) at POR" : "POR at \(g.opp)").font(T.display(24))
                    Text("\(g.isToday ? "Tonight" : Fmt.long(g.tipDate)) · \(Fmt.time(g.tipDate))").font(T.body(13)).foregroundStyle(T.muted)
                }
                Spacer()
                ModeToggle(mode: $mode)
            }
            OfflineBanner()
            if i >= items.count {
                recap
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { k, it in
                        Capsule().fill(k == i ? T.accent : pick(it) != nil ? T.ink : T.line).frame(height: 4)
                    }
                }
                ZStack {
                    if i + 1 < items.count { card(items[i + 1], lean: 0).scaleEffect(0.94).offset(y: 10).opacity(0.7).allowsHitTesting(false) }
                    card(items[i], lean: drag.width)
                        .offset(x: drag.width, y: drag.height * 0.25)
                        .rotationEffect(.degrees(Double(drag.width) / 18))
                        .gesture(DragGesture()
                            .onChanged { v in if !flying { drag = v.translation } }
                            .onEnded { v in
                                let dx = v.translation.width, fast = abs(v.predictedEndTranslation.width) > 260
                                if abs(dx) > 90 || fast { fly(dx > 0 ? 1 : -1, at: i) }
                                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { drag = .zero } }
                            })
                        .id(items[i].id)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 10) {
                    let (yes, no) = labels(items[i])
                    deckButton("← \(no)", primary: false) { fly(-1, at: i) }
                    deckButton("\(yes) →", primary: true) { fly(1, at: i) }
                }
                HStack {
                    Button("Back") { if i > 0 { index = i - 1 } }.disabled(i == 0)
                    Spacer()
                    Button("Skip") { index = min(items.count, i + 1) }
                }
                .font(T.body(15, .semibold)).foregroundStyle(T.muted)
                .padding(.trailing, PinwheelMenu.size + 12)
                .frame(height: PinwheelMenu.size)       // shares the row with the pinwheel
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .background(T.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .onChange(of: g.locked) { _, _ in index = nil }
    }

    private func labels(_ it: Item) -> (String, String) {
        switch it {
        case .winner: return ("Blazers", g.opp)
        case .q(let q): return q.isYN ? ("Yes", "No") : ("Over", "Under")
        }
    }

    private func deckButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(T.body(17, .bold)).frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(primary ? T.accentInk : T.ink)
                .background(primary ? T.accent : T.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(primary ? .clear : T.ink, lineWidth: 1.5))
        }.buttonStyle(.plain).disabled(flying)
    }

    /// Throw the top card off one side, then record the pick.
    private func fly(_ dir: CGFloat, at i: Int) {
        guard !flying, i < items.count else { return }
        if g.locked { return }
        flying = true
        Haptics.thunk()
        let it = items[i]
        let commit = {
            let val: String
            switch it {
            case .winner: val = dir > 0 ? "POR" : g.opp
            case .q(let q): val = q.isYN ? (dir > 0 ? "yes" : "no") : (dir > 0 ? "over" : "under")
            }
            switch it {
            case .winner: store.setPick(g.id, .winner, val, toggle: false)
            case .q(let q): store.setPick(g.id, .question(q.id), val, toggle: false)
            }
            index = i + 1; drag = .zero; flying = false
        }
        if reduceMotion { commit(); return }
        withAnimation(.easeIn(duration: 0.26)) { drag = CGSize(width: dir * 520, height: -40) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { commit() } }
    }

    /// `lean` is how far the card is being dragged; only the top card leans.
    @ViewBuilder private func card(_ it: Item, lean: CGFloat) -> some View {
        let pk = pick(it)
        let special: Bool = { if case .q(let q) = it { return q.k != .stat }; return false }()
        VStack(alignment: .leading) {
            switch it {
            case .winner:
                Kicker("Who wins? · straight up")
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) { Text(g.opp).font(T.display(76)); Text(g.oppName).font(T.body(14)).foregroundStyle(T.muted) }
                    Spacer()
                    Text("or").font(T.display(28, .bold)).foregroundStyle(T.muted)
                    Spacer()
                    VStack(alignment: .trailing) { Text("POR").font(T.display(76)).foregroundStyle(T.red); Text("Trail Blazers").font(T.body(14)).foregroundStyle(T.muted) }
                }
                Spacer()
                if let pk { Text("Your pick: \(pk)").font(T.body(14, .semibold)).foregroundStyle(T.muted) }
                HStack { Text("← \(g.opp)"); Spacer(); Text("Blazers →") }.font(T.body(14, .semibold)).foregroundStyle(T.muted)
            case .q(let q):
                Kicker(q.k == .stat ? "\(q.team == "POR" ? "Blazers" : g.oppName) · \(statNames[q.stat ?? ""] ?? "")" : "Commissioner's special")
                Text(q.k == .stat ? q.title.uppercased() : q.title)
                    .font(q.k == .stat ? T.display(52) : T.body(28, .bold)).lineLimit(4).minimumScaleFactor(0.6)
                Spacer()
                HStack {
                    Spacer()
                    if q.isYN { Text("YES OR NO?").font(T.display(64)) }
                    else {
                        VStack(spacing: 0) {
                            Text(fmtLine(q.line)).font(.system(size: 110, weight: .bold, design: .monospaced)).minimumScaleFactor(0.5)
                            Text(q.k == .stat ? (q.stat ?? "") : "line").font(T.body(16, .semibold)).foregroundStyle(T.muted)
                        }
                    }
                    Spacer()
                }
                Spacer()
                if let pk { Text("Your pick: \(pickLabel(pk))").font(T.body(14, .semibold)).foregroundStyle(T.muted) }
                let (yes, no) = q.isYN ? ("Yes", "No") : ("Over", "Under")
                HStack { Text("← \(no)"); Spacer(); Text("\(yes) →") }.font(T.body(14, .semibold)).foregroundStyle(T.muted)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The shadow belongs to the card's shape only, not to the text on it.
        .background(RoundedRectangle(cornerRadius: 26).fill(T.panel).shadow(color: .black.opacity(0.18), radius: 18, y: 12))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(special ? T.ink : T.line, style: StrokeStyle(lineWidth: special ? 2 : 1, dash: special ? [6, 5] : [])))
        .overlay(alignment: .topLeading) { stamp(labels(it).0.uppercased(), color: T.good).opacity(Double(max(0, lean) / 90)).rotationEffect(.degrees(-12)).padding(26) }
        .overlay(alignment: .topTrailing) { stamp(labels(it).1.uppercased(), color: T.accent).opacity(Double(max(0, -lean) / 90)).rotationEffect(.degrees(12)).padding(26) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: labels(it).0) { if let i = items.firstIndex(where: { $0.id == it.id }) { fly(1, at: i) } }
        .accessibilityAction(named: labels(it).1) { if let i = items.firstIndex(where: { $0.id == it.id }) { fly(-1, at: i) } }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text).font(T.display(34)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
    }

    private var recap: some View {
        let done = items.filter { pick($0) != nil }.count
        let others = store.pickedBy[g.id] ?? []
        return ScrollView {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Kicker(done == items.count ? "All picked" : "\(done) of \(items.count) picked")
                    Text(done == items.count ? "YOU'RE LOCKED IN." : "ALMOST THERE.").font(T.display(34))
                    Text("You can change picks until tip-off. \(others.isEmpty ? "" : "\(others.map(store.name).joined(separator: ", ")) \(others.count > 1 ? "have" : "has") picked too.")")
                        .font(T.body(14)).foregroundStyle(T.muted)
                    VStack(spacing: 0) {
                        ForEach(items) { it in
                            HStack {
                                switch it {
                                case .winner: Text("Who wins?")
                                case .q(let q): Text(q.title) + Text("  \(q.lineText)").foregroundStyle(T.muted)
                                }
                                Spacer()
                                Text(pick(it).map { it.id == "winner" ? $0 : pickLabel($0) } ?? "—").bold()
                            }
                            .font(T.body(15)).padding(.vertical, 10)
                            .overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 1) }
                        }
                    }
                    HStack(spacing: 10) {
                        BigButton(title: "Start over", ghost: true) { index = 0 }
                        BigButton(title: "See the list", ghost: true) { mode = "list" }
                    }
                }
            }
            .padding(.bottom, PinwheelMenu.size + 30)
        }
        .scrollIndicators(.hidden)
    }
}
