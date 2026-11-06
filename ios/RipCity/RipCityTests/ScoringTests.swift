//  ScoringTests.swift — the app must score exactly like the web page
//  (public/index.html and src/lines.js, which stay the source of truth).

import XCTest
@testable import RipCity

final class ScoringTests: XCTestCase {
    private func q(_ id: String, line: Double? = 20, kind: String? = nil) -> Question {
        Question(id: id, kind: kind, team: "POR", player: "A", stat: "PTS", text: "T?", line: line)
    }

    func testRightWrongAndOnTheLine() {
        let a = q("a")
        XCTAssertEqual(Score.markQ("over", a, Final(values: ["a": 25])), 1)
        XCTAssertEqual(Score.markQ("under", a, Final(values: ["a": 25])), -1)
        XCTAssertEqual(Score.markQ("under", a, Final(values: ["a": 20])), 0)
        XCTAssertNil(Score.markQ(nil, a, Final(values: ["a": 20])))
        XCTAssertNil(Score.markQ("over", a, Final(values: [:])), "no value yet (or didn't play) scores nothing")
        XCTAssertEqual(Score.markW("POR", Final(winner: "POR")), 1)
        XCTAssertEqual(Score.markW("LAL", Final(winner: "POR")), -1)
        XCTAssertNil(Score.markW("POR", nil))
    }

    func testYesNo() {
        let b = q("b", line: nil, kind: "yn")
        XCTAssertEqual(Score.markQ("yes", b, Final(values: ["b": 1])), 1)
        XCTAssertEqual(Score.markQ("no", b, Final(values: ["b": 1])), -1)
        XCTAssertEqual(Score.markQ("no", b, Final(values: ["b": 0])), 1)
    }

    func testDecodesServerState() throws {
        let json = #"""
        {"me":{"id":"u1","name":"Chad","admin":false},"serverTime":"2026-11-06T20:00:00.000Z",
         "players":[{"id":"u1","name":"Chad"},{"id":"u2","name":"Joelle"}],
         "games":[{"id":"401909932","tip":"2026-11-05T03:00Z","home":false,"opp":"PHX","oppName":"Phoenix Suns",
           "questions":[{"id":"q1","team":"POR","player":"Deni Avdija","stat":"PTS","line":23},
                        {"id":"qa","kind":"custom","team":"FUN","text":"Sweaters","line":3},
                        {"id":"qb","kind":"yn","team":"FUN","text":"Tech?"}],
           "final":{"winner":"POR","porScore":132,"oppScore":119,"values":{"q1":30,"qa":4,"qb":1},"voided":[],"espnGraded":true,"source":"espn"}},
          {"id":"401909294","tip":"2026-11-07T03:00Z","home":false,"opp":"LAL","oppName":"Los Angeles Lakers","questions":null,"final":null}],
         "picks":{"u1":{"401909932":{"winner":"POR","q":{"q1":"under","qa":"over","qb":"no"}}},
                  "u2":{"401909932":{"winner":"POR","q":{"q1":"over","qa":"over","qb":"yes"}}}},
         "pickedBy":{}}
        """#
        let s = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        XCTAssertEqual(s.games.count, 2)
        XCTAssertEqual(s.games[0].tipDate, ISO8601DateFormatter().date(from: "2026-11-05T03:00:00Z"))
        XCTAssertEqual(s.games[0].qs.map(\.k), [.stat, .custom, .yn])
        let table = standings(players: s.players, games: s.games, picks: s.picks ?? [:])
        XCTAssertEqual(table.map(\.id), ["u2", "u1"])
        XCTAssertEqual(table[0].tally, Tally(pts: 4, w: 4, l: 0, p: 0, games: 1))
        XCTAssertEqual(table[1].tally, Tally(pts: 0, w: 2, l: 2, p: 0, games: 1))
    }

    func testFormatting() {
        XCTAssertEqual(fmtLine(23), "23")
        XCTAssertEqual(fmtLine(22.5), "22.5")
        XCTAssertEqual(signed(3), "+3")
        XCTAssertEqual(signed(-2), "−2")
        XCTAssertEqual(signed(0), "0")
    }
}
