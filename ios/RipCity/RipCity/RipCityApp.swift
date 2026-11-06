//  RipCityApp.swift — Rip City Over/Under on iPhone. Same game, same server and
//  same leaderboard as ripcity.chadstewartcpa.com; commissioner tools stay on
//  the website for now.

import SwiftUI

@main
struct RipCityApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { RootView().environment(store).tint(T.accent) }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var store = store
        ZStack {
            T.bg.ignoresSafeArea()
            if store.token == nil {
                LoginView()
            } else if !store.loaded {
                VStack(spacing: 14) {
                    PinwheelMark(size: 72)
                    Text(store.offline ? "Can't reach the server. Check your connection." : "Loading…").foregroundStyle(T.muted)
                    if store.offline { Button("Try again") { Task { await store.load() } } }
                }.padding(32)
            } else {
                NavigationStack(path: $store.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { r in
                            switch r {
                            case .game(let id): GameView(id: id)
                            case .results: ResultsView()
                            case .schedule: ScheduleView()
                            case .roster: RosterView()
                            }
                        }
                }
                .overlay { PinwheelMenu() }
            }
            if let msg = store.toast {
                VStack { Spacer()
                    Text(msg).font(T.body(14, .semibold)).foregroundStyle(T.bg)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(T.ink, in: Capsule())
                        .padding(.bottom, 90).padding(.horizontal, 24)
                }
                .transition(.opacity).allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .task { await store.load() }
        .onChange(of: phase) { _, p in if p == .active { Task { await store.load() } } }
        .task(id: store.token) {
            // Keep the board fresh while the app is open, like the web page.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if phase == .active { await store.load() }
            }
        }
    }
}

/// A scrolling screen with the page gutter and room for the pinwheel.
struct Page<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(Store.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 16).padding(.top, 8)
                .padding(.bottom, PinwheelMenu.size + 40)
        }
        .scrollIndicators(.hidden)
        .background(T.bg)
        .refreshable { await store.load() }
    }
}

struct OfflineBanner: View {
    @Environment(Store.self) private var store
    var body: some View {
        if store.offline {
            Text("Can't reach the server right now. What you see may be out of date.")
                .font(T.body(14)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(T.badBg, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct LoginView: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var passcode = ""
    @State private var error = ""
    @State private var busy = false
    @FocusState private var focus: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Stripes(); Spacer(); PinwheelMark(size: 44) }
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("Blazers · 2026–27 season")
                    Text("RIP CITY\nOVER/UNDER").font(T.display(58)).lineSpacing(-8)
                    Text("Pick the winner and ten stat lines for each game. Right is +1, wrong is −1, landing exactly on the line is 0.")
                        .foregroundStyle(T.muted)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your name").font(T.body(14, .semibold))
                        TextField("First name", text: $name).textContentType(.nickname).autocorrectionDisabled()
                            .focused($focus, equals: 0).submitLabel(.next).onSubmit { focus = 1 }
                            .modifier(Field())
                        Text("Family passcode").font(T.body(14, .semibold))
                        SecureField("", text: $passcode).textContentType(.password)
                            .focused($focus, equals: 1).submitLabel(.go).onSubmit(go)
                            .modifier(Field())
                        if !error.isEmpty { Text(error).font(T.body(14, .semibold)).foregroundStyle(T.accent) }
                        BigButton(title: busy ? "Signing in…" : "Let's play", action: go).disabled(busy)
                        Text("Use the same name as on the website so your picks and points carry over.")
                            .font(T.body(14)).foregroundStyle(T.muted)
                    }
                }
            }.padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func go() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !passcode.isEmpty else { error = "Enter your name and the family passcode."; return }
        busy = true; error = ""
        Task {
            do { try await store.login(name: n, passcode: passcode) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct Field: ViewModifier {
    func body(content: Content) -> some View {
        content.font(T.body(17)).padding(.horizontal, 14).frame(minHeight: 50)
            .background(T.bg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
    }
}

// MARK: - home

struct HomeView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let f = store.featured
        let now = Date()
        let upcoming = store.games.filter { $0.id != f?.id && $0.tipDate > now }.prefix(5)
        let recent = store.games.filter { $0.id != f?.id && $0.tipDate <= now && $0.hasLines }.suffix(4).reversed()
        let ranked = store.table.filter { $0.tally.games > 0 }
        Page {
            HStack { Stripes(); Spacer() }.frame(height: 30)
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Blazers · 2026–27 season")
                Text("RIP CITY\nOVER/UNDER").font(T.display(56)).lineSpacing(-8)
                Text("Hi \(store.me?.name ?? ""). Pick the winner and ten stat lines for each game.").foregroundStyle(T.muted)
            }
            OfflineBanner()
            if let f {
                Board(g: f) {
                    if f.hasLines {
                        let st = store.status(f)
                        BigButton(title: f.locked ? "See everyone's picks" : st == .picked ? "Review your picks" : "Make your picks") {
                            store.path.append(.game(f.id))
                        }
                    } else {
                        Text("Lines go up automatically the day before the game.").font(T.body(14)).opacity(0.75)
                    }
                }
            } else {
                Card { Text("No games left on the schedule.") }
            }
            NavCard(kicker: "Season leaderboard") {
                if ranked.isEmpty { Text("No graded games yet.").foregroundStyle(T.muted) }
                else {
                    HStack(spacing: 10) {
                        ForEach(ranked.prefix(3)) { r in
                            HStack(spacing: 4) { Text(store.name(r.id)).bold(); Text(signed(r.tally.pts)).font(.system(.body, design: .monospaced)) }
                        }
                    }
                }
            } action: { store.path.append(.results) }
            NavCard(kicker: "Roster yearbook") {
                Text("Wait, who's #91? Meet the new faces.")
            } action: { store.path.append(.roster) }
            if !upcoming.isEmpty { GameList(title: "Coming up", games: Array(upcoming)) }
            if !recent.isEmpty { GameList(title: "Recent", games: Array(recent)) }
            BigButton(title: "Full schedule", ghost: true) { store.path.append(.schedule) }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct NavCard<Content: View>: View {
    let kicker: String
    @ViewBuilder let content: Content
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Kicker(kicker); content }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold))
                }
            }
        }.buttonStyle(.plain)
    }
}

struct GameList: View {
    let title: String
    let games: [Game]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(title)
            VStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { Divider().overlay(T.line) }
                    GameRow(g: g)
                }
            }
            .background(T.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(T.line))
        }
    }
}

struct GameRow: View {
    @Environment(Store.self) private var store
    let g: Game
    var body: some View {
        let st = store.status(g)
        Button { store.path.append(.game(g.id)) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.dow(g.tipDate).uppercased()).font(T.display(22, .heavy))
                    Text(Fmt.md(g.tipDate)).font(T.body(13)).foregroundStyle(T.muted)
                }.frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(g.vsAt) \(g.oppName)").font(T.body(16, .medium)).multilineTextAlignment(.leading)
                    Text(Fmt.time(g.tipDate)).font(T.body(13)).foregroundStyle(T.muted)
                }
                Spacer(minLength: 8)
                Chip(text: st.label, hot: st == .tonight, done: st == .picked || st == .final)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct ScheduleView: View {
    @Environment(Store.self) private var store
    var body: some View {
        Page {
            Text("SCHEDULE").font(T.display(34))
            GameList(title: "2026–27 season", games: store.games)
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
}
