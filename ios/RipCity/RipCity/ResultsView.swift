//  ResultsView.swift — the season leaderboard and every graded game's picks,
//  plus the roster yearbook (public/roster.json on the website).

import SwiftUI

struct ResultsView: View {
    @Environment(Store.self) private var store
    @State private var openGame: String?

    var body: some View {
        let table = store.table
        let ranked = table.filter { $0.tally.games > 0 }
        let played = store.games.filter { $0.hasLines && $0.locked }.reversed()
        let users = table.map(\.id).filter { p in played.contains { store.picks[p]?[$0.id] != nil } }
        Page {
            VStack(alignment: .leading, spacing: 6) { Kicker("2026–27 season"); Text("LEADERBOARD").font(T.display(34)) }
            OfflineBanner()
            if ranked.isEmpty {
                Card { Text("The leaderboard fills in after the first game is graded.") }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(T.display(30)).frame(width: 34)
                                .foregroundStyle(i == 0 ? T.accent : T.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(store.name(r.id)).font(T.body(17, .bold))
                                    if r.id == store.uid { Chip(text: "You") }
                                }
                                Text("\(r.tally.record) · \(r.tally.games) game\(r.tally.games == 1 ? "" : "s") graded").font(T.body(13)).foregroundStyle(T.muted)
                            }
                            Spacer()
                            Text(signed(r.tally.pts)).font(.system(size: 30, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(T.panel, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(i == 0 ? T.accent : T.line, lineWidth: i == 0 ? 1.5 : 1))
                    }
                }
            }
            Text("+1 for each right pick, −1 for each wrong one, 0 when the stat lands exactly on the line. A player who doesn't play counts for nothing.")
                .font(T.body(14)).foregroundStyle(T.muted)
            if !played.isEmpty {
                Kicker("Game by game")
                ForEach(Array(played)) { g in gameBlock(g, users: users, open: (openGame ?? played.first?.id) == g.id) }
            }
            HStack(spacing: 4) {
                Text("Signed in as \(store.me?.name ?? "").").foregroundStyle(T.muted)
                Button("Sign out") { store.signOut() }.foregroundStyle(T.muted).underline()
            }.font(T.body(14))
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }

    private func gameBlock(_ g: Game, users: [String], open: Bool) -> some View {
        let fin = g.final
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { openGame = open ? "" : g.id } } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Fmt.dow(g.tipDate).uppercased()).font(T.display(20, .heavy))
                        Text(Fmt.md(g.tipDate)).font(T.body(13)).foregroundStyle(T.muted)
                    }.frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(g.vsAt) \(g.oppName)").font(T.body(16, .medium)).multilineTextAlignment(.leading)
                        Text(g.isFinal ? "Final\(fin?.porScore != nil ? " · POR \(fmtLine(fin?.porScore))–\(fmtLine(fin?.oppScore))" : "")\(g.unanswered.isEmpty ? "" : " · specials still being graded")" : "Waiting on final stats")
                            .font(T.body(13)).foregroundStyle(T.muted).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(users, id: \.self) { p in
                            if let s = scoreGame(g, store.picks[p]?[g.id]) {
                                HStack(spacing: 4) { Text(store.name(p)).font(T.body(13)); Points(n: s.pts) }
                            }
                        }
                    }
                }
                .padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                Divider().overlay(T.line)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Text("Line"); Text("Final")
                            ForEach(users, id: \.self) { Text(store.name($0)).gridColumnAlignment(.center) }
                        }.font(T.kicker).foregroundStyle(T.muted)
                        GridRow {
                            Text("Winner").font(T.body(14))
                            Text(fin?.winner ?? "—").font(.system(size: 14, design: .monospaced))
                            ForEach(users, id: \.self) { p in let pk = store.picks[p]?[g.id]?.winner; cell(pk, Score.markW(pk, fin)) }
                        }
                        ForEach(g.qs) { q in
                            GridRow {
                                (Text(q.title) + Text("  \(q.lineText)").foregroundStyle(T.muted)).font(T.body(14)).frame(maxWidth: 190, alignment: .leading)
                                Text(fin?.values?[q.id].map { q.isYN ? ($0 == 1 ? "Yes" : "No") : fmtLine($0) } ?? (fin?.voided?.contains(q.id) == true ? "DNP" : "—"))
                                    .font(.system(size: 14, design: .monospaced))
                                ForEach(users, id: \.self) { p in let pk = store.picks[p]?[g.id]?.q?[q.id]; cell(pk, Score.markQ(pk, q, fin)) }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(T.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.line))
    }

    @ViewBuilder private func cell(_ pk: String?, _ m: Int?) -> some View {
        if let pk {
            Text("\(pickShort(pk))\(m.map { " " + signed($0) } ?? "")")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(m == 1 ? T.good : m == 0 ? T.push : T.ink)
                .background(m == 1 ? T.goodBg : m == nil ? Color.clear : T.badBg, in: Capsule())
                .gridColumnAlignment(.center)
        } else {
            Text("—").foregroundStyle(T.muted).gridColumnAlignment(.center)
        }
    }
}

// MARK: - roster yearbook

struct RosterView: View {
    @Environment(Store.self) private var store
    @State private var flash: String?

    var body: some View {
        ScrollViewReader { proxy in
            Page {
                if let d = store.roster {
                    cover(d)
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker("Wait, who's number…?")
                        let nums = d.players.sorted { (Int($0.n) ?? 0, $0.n.count) < (Int($1.n) ?? 0, $1.n.count) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
                            ForEach(nums) { p in
                                Button {
                                    Haptics.tick()
                                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(p.id, anchor: .top) }
                                    flash = p.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if flash == p.id { flash = nil } }
                                } label: {
                                    Text(p.n).font(T.display(24)).frame(maxWidth: .infinity, minHeight: 52)
                                        .background(T.panel, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.isNew ? T.accent : T.line, lineWidth: 1.5))
                                }.buttonStyle(.plain).accessibilityLabel("Number \(p.n), \(p.name)")
                            }
                        }
                        Text("Red outline = new since the 2024–25 season.").font(T.body(14)).foregroundStyle(T.muted)
                    }
                    section("The starting five", d.players.filter { $0.role == "Starter" })
                    section("Off the bench", d.players.filter { $0.role == "Sixth man" || $0.role == "Bench" })
                    section("On the mend", d.players.filter { $0.role == "Injured" })
                    section("End of the bench", d.players.filter { $0.role == "Deep bench" }, mini: true)
                    Kicker("The coach")
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.coach.name.uppercased()).font(T.display(28))
                            Text(d.coach.blurb)
                            if let u = URL(string: d.coach.src) { Link("Source", destination: u).font(T.body(13)).foregroundStyle(T.muted) }
                        }
                    }
                    Text("Fun facts come from news stories and interviews (sources on each card). Relationships are only listed when they're public and confirmed.")
                        .font(T.body(14)).foregroundStyle(T.muted)
                } else if store.rosterFailed {
                    Card { Text("Couldn't load the roster. Pull down to try again.") }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
        }
        .task { await store.loadRoster() }
        .refreshable { store.roster = nil; await store.loadRoster() }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }

    private func cover(_ d: Roster) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Rip City Over/Under presents", color: T.bandInk.opacity(0.62))
            VStack(alignment: .leading, spacing: -10) {
                Text("ROSTER").font(T.display(70))
                Text("YEARBOOK").font(T.display(70)).foregroundStyle(T.red)
            }
            Text("Everyone on the \(d.season) Blazers, with the stuff they don't put on the scoreboard. \(d.lastSeason)")
                .font(T.body(15)).foregroundStyle(T.bandInk.opacity(0.8))
            Kicker("Updated \(Fmt.md(Fmt.parse(d.updated + "T20:00:00Z")))", color: T.bandInk.opacity(0.62))
        }
        .padding(.horizontal, 18).padding(.vertical, 22).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(T.bandInk)
        .background(T.band, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func section(_ title: String, _ list: [Roster.Person], mini: Bool = false) -> some View {
        if !list.isEmpty {
            Kicker(title)
            ForEach(list) { p in PlayerCard(p: p, mini: mini, flash: flash == p.id).id(p.id) }
        }
    }
}

struct PlayerCard: View {
    let p: Roster.Person
    var mini = false
    var flash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                T.band
                Text(p.n).font(T.display(mini ? 96 : 150)).foregroundStyle(T.red.opacity(0.92))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 12).offset(y: mini ? -10 : -18)
                AsyncImage(url: p.headshot) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: mini ? 110 : 170, height: mini ? 80 : 124, alignment: .top).clipped()
                    .padding(.leading, 16)
            }
            .frame(height: mini ? 96 : 150).clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(p.name.uppercased()).font(T.display(mini ? 26 : 34))
                Text("#\(p.n) · \(p.pos) · \(p.ht) · \(p.age) · \(p.home)").font(T.body(14)).foregroundStyle(T.muted)
                FlowRow { Chip(text: p.role); Chip(text: p.joined, hot: p.isNew) }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            VStack(alignment: .leading, spacing: 8) {
                Kicker("On the court")
                Text(p.court)
                if !p.fun.isEmpty {
                    Kicker("Off the court").padding(.top, 4)
                    ForEach(p.fun, id: \.self) { f in
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(f) }
                    }
                }
            }
            .font(T.body(16)).padding(16)
            FlowRow(spacing: 14) {
                if let ig = URL(string: "https://www.google.com/search?q=" + (p.name + " instagram").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
                    Link("Find their Instagram ↗", destination: ig).font(T.body(14, .bold)).foregroundStyle(T.ink)
                }
                ForEach(Array(p.src.enumerated()), id: \.offset) { i, s in
                    if let u = URL(string: s) { Link("Source \(i + 1)", destination: u).font(T.body(13)).foregroundStyle(T.muted) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 1) }
        }
        .background(T.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(flash ? T.accent : T.line, lineWidth: flash ? 4 : 1))
        .animation(.easeOut(duration: 0.6), value: flash)
    }
}
