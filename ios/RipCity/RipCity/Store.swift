//  Store.swift — talks to the same Worker as the web page
//  (ripcity.chadstewartcpa.com), so picks and the leaderboard are shared with
//  the website. The token lives in the Keychain; picks save as you tap.

import Foundation
import Security
import SwiftUI

enum Route: Hashable { case game(String), results, schedule, roster }

@MainActor @Observable
final class Store {
    static let base: URL = {
        #if DEBUG
        // UI tests point the app at a local `wrangler dev` with a test token.
        if let b = ProcessInfo.processInfo.environment["RIPCITY_BASE"], let u = URL(string: b) { return u }
        #endif
        return URL(string: "https://ripcity.chadstewartcpa.com")!
    }()

    var token: String? = {
        #if DEBUG
        if let t = ProcessInfo.processInfo.environment["RIPCITY_TOKEN"] { return t }
        #endif
        return Keychain.read()
    }()
    var me: Me?
    var games: [Game] = []
    var players: [Player] = []
    var picks: [String: [String: Pick]] = [:]
    var pickedBy: [String: [String]] = [:]
    var loaded = false
    var offline = false
    var toast: String?
    var path: [Route] = []
    var roster: Roster?
    var rosterFailed = false

    private var pending: [String] = []
    private var writing = false
    private var saveTask: Task<Void, Never>?

    var uid: String? { me?.id }
    func game(_ id: String) -> Game? { games.first { $0.id == id } }
    func name(_ id: String) -> String { players.first { $0.id == id }?.name ?? "Player" }
    func myPick(_ gid: String) -> Pick? { uid.flatMap { picks[$0]?[gid] } }
    var table: [Standing] { standings(players: players, games: games, picks: picks) }

    /// The game to feature: the next one that hasn't been over for long.
    var featured: Game? { games.first { $0.tipDate.addingTimeInterval(3.5 * 3600) > Date() } }

    enum Status { case final, locked, noLines, linesSoon, picked, tonight, open
        var label: String { switch self {
            case .final: "Final"; case .locked: "Picks locked"; case .noLines: "No lines"; case .linesSoon: "Lines soon"
            case .picked: "Picked"; case .tonight: "Tonight"; case .open: "Picks open" } }
    }
    func status(_ g: Game) -> Status {
        if g.isFinal { return .final }
        if g.locked { return g.hasLines ? .locked : .noLines }
        if !g.hasLines { return .linesSoon }
        let m = myPick(g.id)
        let n = (m?.winner != nil ? 1 : 0) + (m?.q?.count ?? 0)
        if n >= g.qs.count + 1 { return .picked }
        return g.isToday ? .tonight : .open
    }

    // MARK: network

    struct APIError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var r = URLRequest(url: Self.base.appendingPathComponent(path))
        r.httpMethod = method
        r.httpBody = body
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "authorization") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        if code == 401 { signOut(); throw APIError(message: msg ?? "Sign in to play.") }
        guard (200..<300).contains(code) else { throw APIError(message: msg ?? "Something went wrong. Try again.") }
        return data
    }

    func login(name: String, passcode: String) async throws {
        let body = try JSONEncoder().encode(["name": name, "passcode": passcode])
        let r = try JSONDecoder().decode(LoginReply.self, from: try await request("api/login", method: "POST", body: body))
        token = r.token; me = r.me; Keychain.save(r.token)
        await load()
    }

    func signOut() {
        token = nil; me = nil; loaded = false; games = []; picks = [:]; path = []
        Keychain.save(nil)
    }

    func load() async {
        guard token != nil else { return }
        do {
            let s = try JSONDecoder().decode(AppState.self, from: try await request("api/state"))
            // Keep picks made since the last save until the server has them.
            let mine = uid.flatMap { picks[$0] }
            me = s.me; games = s.games; players = s.players; pickedBy = s.pickedBy ?? [:]
            picks = s.picks ?? [:]
            if let mine, let id = uid { for gid in pending { picks[id, default: [:]][gid] = mine[gid] } }
            loaded = true; offline = false
        } catch {
            if token != nil { offline = true }
        }
    }

    func loadRoster() async {
        guard roster == nil else { return }
        do {
            var r = URLRequest(url: Self.base.appendingPathComponent("roster.json"))
            r.cachePolicy = .reloadRevalidatingCacheData
            let (data, _) = try await URLSession.shared.data(for: r)
            roster = try JSONDecoder().decode(Roster.self, from: data); rosterFailed = false
        } catch { rosterFailed = true }
    }

    // MARK: picks

    enum PickTarget: Equatable { case winner, question(String) }

    /// Tapping a pick again clears it in the list; a swipe always sets it.
    func setPick(_ gid: String, _ target: PickTarget, _ value: String, toggle: Bool = true) {
        guard let g = game(gid), !g.locked, let id = uid else { return }
        var p = picks[id]?[gid] ?? Pick(winner: nil, q: [:])
        var q = p.q ?? [:]
        switch target {
        case .winner: p.winner = toggle && p.winner == value ? nil : value
        case .question(let qid): q[qid] = toggle && q[qid] == value ? nil : value
        }
        p.q = q
        picks[id, default: [:]][gid] = p
        if !pending.contains(gid) { pending.append(gid) }
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(400)); await self.savePicks() }
    }

    private func savePicks() async {
        guard !writing, !pending.isEmpty, let id = uid else { return }
        writing = true
        let gid = pending.removeFirst()
        let p = picks[id]?[gid] ?? Pick(winner: nil, q: [:])
        do {
            let body = try JSONEncoder().encode(p)
            _ = try await request("api/picks/\(gid)", method: "PUT", body: body)
        } catch {
            show(error.localizedDescription); await load()
        }
        writing = false
        if !pending.isEmpty { await savePicks() }
    }

    func show(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(2.2)); if toast == message { toast = nil } }
    }
}

enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "ripcity", kSecAttrAccount as String: "token"]
    static func read() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func save(_ value: String?) {
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var q = query; q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
