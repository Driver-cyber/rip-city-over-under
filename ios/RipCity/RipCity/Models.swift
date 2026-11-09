//  Models.swift — the same JSON the web page reads from /api/state, plus the
//  scoring rules. These mirror public/index.html (markQ, markW, scoreGame,
//  standings), which stays the source of truth.

import Foundation

struct Me: Codable, Equatable { let id: String; let name: String; let admin: Bool? }
struct Player: Codable, Identifiable, Equatable { let id: String; let name: String }

struct Question: Codable, Identifiable, Equatable {
    let id: String
    var kind: String?            // nil = player stat, "custom" = commissioner's over/under, "yn" = yes/no
    var team: String?
    var player: String?
    var stat: String?
    var text: String?
    var line: Double?

    enum Kind { case stat, custom, yn }
    var k: Kind { kind == "custom" ? .custom : kind == "yn" ? .yn : .stat }
    var isYN: Bool { k == .yn }
    var title: String { k == .stat ? (player ?? "") : (text ?? "") }
    var lineText: String {
        switch k {
        case .stat: return "\(stat ?? "") \(fmtLine(line))"
        case .yn: return "Yes or no"
        case .custom: return "Over/under \(fmtLine(line))"
        }
    }
}

struct Final: Codable, Equatable {
    var winner: String?
    var porScore: Double?
    var oppScore: Double?
    var values: [String: Double]?
    var voided: [String]?
}

struct Game: Codable, Identifiable, Equatable {
    let id: String
    let tip: String
    let home: Bool
    let opp: String
    let oppName: String
    var questions: [Question]?
    var final: Final?
    var reopened: Bool?          // the commissioner reopened picks after tip-off

    var tipDate: Date { Fmt.parse(tip) }
    var qs: [Question] { questions ?? [] }
    var hasLines: Bool { !qs.isEmpty }
    var started: Bool { Date() >= tipDate }
    var isReopened: Bool { started && reopened == true && !isFinal }
    var locked: Bool { started && !isReopened }
    var isFinal: Bool { final?.winner != nil }
    var isToday: Bool { Fmt.day(tipDate) == Fmt.day(Date()) }
    var vsAt: String { home ? "vs" : "at" }
    /// Commissioner's questions on a started game that still need an answer.
    var unanswered: [Question] { locked ? qs.filter { $0.k != .stat && final?.values?[$0.id] == nil } : [] }
}

struct Pick: Codable, Equatable {
    var winner: String?
    var q: [String: String]?
}

struct AppState: Codable {
    let me: Me
    let players: [Player]
    let games: [Game]
    let picks: [String: [String: Pick]]?
    let pickedBy: [String: [String]]?
}

struct LoginReply: Codable { let token: String; let me: Me }

// MARK: - scoring (same rules as the web page)

enum Score {
    static func markQ(_ pick: String?, _ q: Question, _ fin: Final?) -> Int? {
        guard let pick, let v = fin?.values?[q.id] else { return nil }
        if q.isYN { return (v == 1) == (pick == "yes") ? 1 : -1 }
        guard let line = q.line else { return nil }
        if v == line { return 0 }
        return (v > line) == (pick == "over") ? 1 : -1
    }
    static func markW(_ pick: String?, _ fin: Final?) -> Int? {
        guard let pick, let w = fin?.winner else { return nil }
        return pick == w ? 1 : -1
    }
}

struct Tally: Equatable { var pts = 0, w = 0, l = 0, p = 0, games = 0
    var record: String { p > 0 ? "\(w)–\(l)–\(p)" : "\(w)–\(l)" }
    mutating func add(_ m: Int?) { guard let m else { return }; pts += m; if m > 0 { w += 1 } else if m < 0 { l += 1 } else { p += 1 } }
}

func scoreGame(_ g: Game, _ pick: Pick?) -> Tally? {
    guard let fin = g.final, let pick else { return nil }
    var t = Tally()
    t.add(Score.markW(pick.winner, fin))
    for q in g.qs { t.add(Score.markQ(pick.q?[q.id], q, fin)) }
    return t
}

struct Standing: Identifiable { let id: String; let tally: Tally }

func standings(players: [Player], games: [Game], picks: [String: [String: Pick]]) -> [Standing] {
    players.map { pl in
        var t = Tally()
        for g in games {
            guard let s = scoreGame(g, picks[pl.id]?[g.id]), s.w + s.l + s.p > 0 else { continue }
            t.pts += s.pts; t.w += s.w; t.l += s.l; t.p += s.p; t.games += 1
        }
        return Standing(id: pl.id, tally: t)
    }.sorted { $0.tally.pts != $1.tally.pts ? $0.tally.pts > $1.tally.pts : $0.tally.w > $1.tally.w }
}

// MARK: - formatting (Pacific time, like the web page)

func fmtLine(_ n: Double?) -> String {
    guard let n else { return "–" }
    return n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
}
func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : n < 0 ? "−\(abs(n))" : "0" }
func pickLabel(_ p: String) -> String { ["over": "Over", "under": "Under", "yes": "Yes", "no": "No"][p] ?? p }
func pickShort(_ p: String) -> String { ["over": "O", "under": "U", "yes": "Y", "no": "N"][p] ?? p }
let statNames = ["PTS": "points", "REB": "rebounds", "AST": "assists", "3PM": "threes", "BLK": "blocks", "STL": "steals"]

enum Fmt {
    static let tz = TimeZone(identifier: "America/Los_Angeles")!
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoNoSec: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"; return f }()
    static func parse(_ s: String) -> Date { iso.date(from: s) ?? isoFrac.date(from: s) ?? isoNoSec.date(from: s) ?? .distantFuture }
    private static func f(_ pattern: String) -> DateFormatter { let d = DateFormatter(); d.locale = Locale(identifier: "en_US"); d.timeZone = tz; d.dateFormat = pattern; return d }
    private static let dayF = f("yyyy-MM-dd"), longF = f("EEE, MMM d"), timeF = f("h:mm a"), dowF = f("EEE"), mdF = f("MMM d")
    static func day(_ d: Date) -> String { dayF.string(from: d) }
    static func long(_ d: Date) -> String { longF.string(from: d) }
    static func time(_ d: Date) -> String { timeF.string(from: d) + " PT" }
    static func dow(_ d: Date) -> String { dowF.string(from: d) }
    static func md(_ d: Date) -> String { mdF.string(from: d) }
}

// MARK: - roster yearbook (public/roster.json)

struct Roster: Codable {
    struct Coach: Codable { let name: String; let blurb: String; let src: String }
    struct Person: Codable, Identifiable {
        let id: String; let n: String; let name: String; let pos: String; let ht: String; let age: Int
        let home: String; let role: String; let joined: String; let court: String; let fun: [String]; let src: [String]
        var isNew: Bool { joined.contains("2025") || joined.contains("2026") }
        var headshot: URL { URL(string: "https://a.espncdn.com/i/headshots/nba/players/full/\(id).png")! }
    }
    let updated: String; let season: String; let coach: Coach; let lastSeason: String; let players: [Person]
}
