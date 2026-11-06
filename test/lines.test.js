import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseAverages, averagesFromBoxes, buildLines, parseBox, gradeFromSummary, markQ, markW, cleanQuestions, changedQuestionIds } from "../src/lines.js";

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

test("backup averages from box scores build lines", () => {
  const avg = averagesFromBoxes([summary, summary], "POR");
  assert.ok(avg.every(p => p.team === "POR" && p.gp === 2));
  const deni = avg.find(p => p.name === "Deni Avdija");
  assert.equal(deni.pts, parseBox(summary)["Deni Avdija"].PTS);
  assert.ok(deni.min > 0);
  assert.equal(buildLines(avg, "POR").length, 6);
});

test("commissioner questions: stat, custom over/under, yes/no", () => {
  const qs = cleanQuestions([
    { id: "q1", team: "POR", player: " Deni Avdija ", stat: "PTS", line: "23" },
    { id: "qa", kind: "custom", text: "Players in sweaters on the walk-in", line: "3" },
    { id: "qb", kind: "yn", text: "Will Donovan Clingan get a technical?" },
    { id: "qc", kind: "yn", text: "   " },
    { id: "qd", kind: "custom", text: "No line", line: "" },
  ], "LAL");
  assert.deepEqual(qs.map(q => q.id), ["q1", "qa", "qb"]);
  assert.equal(qs[0].player, "Deni Avdija");
  assert.equal(qs[1].team, "FUN");
  assert.equal(markQ("yes", qs[2], { values: { qb: 1 } }), 1);
  assert.equal(markQ("no", qs[2], { values: { qb: 1 } }), -1);
  assert.equal(markQ("no", qs[2], { values: { qb: 0 } }), 1);
  assert.equal(markQ("under", qs[1], { values: { qa: 3 } }), 0);
});

test("only changed or removed questions clear picks", () => {
  const old = [{ id: "q1", player: "A", stat: "PTS", line: 20 }, { id: "q2", player: "B", stat: "REB", line: 5 }, { id: "q3", kind: "yn", text: "T?" }];
  const now = [{ id: "q1", player: "A", stat: "PTS", line: 20 }, { id: "q2", player: "B", stat: "REB", line: 6 }, { id: "q4", kind: "yn", text: "New?" }];
  assert.deepEqual(changedQuestionIds(old, now), ["q2", "q3"]);
});

test("ESPN grading leaves commissioner questions alone", () => {
  const f = gradeFromSummary(summary, [{ id: "q1", player: "Deni Avdija", stat: "PTS", line: 1 }, { id: "qa", kind: "custom", text: "Sweaters", line: 3 }], "PHX");
  assert.ok("q1" in f.values);
  assert.ok(!("qa" in f.values));
  assert.deepEqual(f.voided, []);
});
