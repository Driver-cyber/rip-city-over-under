import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseAverages, buildLines, parseBox, gradeFromSummary, markQ, markW } from "../src/lines.js";

const fixture = name => JSON.parse(readFileSync(new URL("./fixtures/" + name, import.meta.url)));
const averages = parseAverages(fixture("averages.json"));
const summary = fixture("summary-401909932.json"); // POR 132, PHX 119 (Nov 4, 2026)

test("parses season averages with team", () => {
  const luka = averages.find(p => p.name === "Luka Doncic");
  assert.equal(luka.team, "LAL");
  assert.ok(luka.pts > 30 && luka.gp >= 1);
});

test("builds six Blazers lines and four opponent lines", () => {
  const por = buildLines(averages, "POR", { out: ["Ja Morant"] });
  const lal = buildLines(averages, "LAL", { opponent: true, startId: por.length + 1 });
  assert.equal(por.length, 6);
  assert.equal(lal.length, 4);
  assert.ok(por.every(q => q.team === "POR" && Number.isInteger(q.line) && q.line >= 1));
  assert.ok(!por.some(q => q.player === "Ja Morant"));
  assert.deepEqual(por.concat(lal).map(q => q.id), ["q1", "q2", "q3", "q4", "q5", "q6", "q7", "q8", "q9", "q10"]);
  const pairs = por.concat(lal).map(q => q.player + q.stat);
  assert.equal(new Set(pairs).size, pairs.length, "no repeated player+stat");
  const counts = {};
  por.forEach(q => counts[q.player] = (counts[q.player] || 0) + 1);
  assert.ok(Object.values(counts).every(n => n <= 2));
});

test("reads a box score", () => {
  const box = parseBox(summary);
  const deni = box["Deni Avdija"];
  assert.ok(deni && typeof deni.PTS === "number" && typeof deni["3PM"] === "number");
});

test("grades a final game, voiding players who didn't play", () => {
  const qs = [
    { id: "q1", team: "POR", player: "Deni Avdija", stat: "PTS", line: 1 },
    { id: "q2", team: "POR", player: "Nobody Here", stat: "PTS", line: 10 },
  ];
  const f = gradeFromSummary(summary, qs, "PHX");
  assert.equal(f.winner, "POR");
  assert.equal(f.porScore, 132);
  assert.equal(f.oppScore, 119);
  assert.equal(typeof f.values.q1, "number");
  assert.deepEqual(f.voided, ["q2"]);
  assert.equal(markQ("over", qs[0], f), 1);
  assert.equal(markQ("over", qs[1], f), null);
});

test("not final yet returns null", () => {
  const live = structuredClone(summary);
  live.header.competitions[0].status.type.completed = false;
  assert.equal(gradeFromSummary(live, [], "PHX"), null);
});

test("scoring: right +1, wrong -1, on the line 0", () => {
  const q = { id: "a", line: 20 };
  assert.equal(markQ("over", q, { values: { a: 25 } }), 1);
  assert.equal(markQ("under", q, { values: { a: 25 } }), -1);
  assert.equal(markQ("under", q, { values: { a: 20 } }), 0);
  assert.equal(markQ(undefined, q, { values: { a: 20 } }), null);
  assert.equal(markW("POR", { winner: "POR" }), 1);
  assert.equal(markW("LAL", { winner: "POR" }), -1);
});
