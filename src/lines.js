// Pure game logic shared by the Worker and the tests: building lines from
// season averages, reading a box score, and scoring picks.

export const STATS = ["PTS", "REB", "AST", "3PM", "BLK", "STL"];

// Question kinds: "stat" (a player's box-score stat, graded from ESPN),
// "custom" (commissioner's own over/under) and "yn" (yes/no). The last two
// are graded by the commissioner; a yes/no result is stored as 1 or 0.
export const qKind = q => (q.kind === "custom" || q.kind === "yn" ? q.kind : "stat");

// Clean up questions sent by the commissioner; drops incomplete ones.
export function cleanQuestions(list, opp) {
  return (list || []).map((q, i) => {
    const id = /^q\w+$/.test(q.id) ? q.id : "q" + (i + 1);
    const kind = qKind(q);
    const line = q.line === "" || q.line == null ? NaN : Number(q.line);
    if (kind === "stat") return { id, team: q.team === opp ? opp : "POR", player: String(q.player || "").trim().slice(0, 40), stat: STATS.includes(q.stat) ? q.stat : "PTS", line };
    const text = String(q.text || "").trim().replace(/\s+/g, " ").slice(0, 140);
    return kind === "custom" ? { id, kind, team: "FUN", text, line } : { id, kind, team: "FUN", text };
  }).filter(q => qKind(q) === "yn" ? q.text : (q.player || q.text) && Number.isFinite(q.line));
}

// Ids of old questions whose wording or line changed (or that were removed):
// picks on those are cleared so nobody keeps an answer to a different question.
export function changedQuestionIds(oldQs, newQs) {
  const sig = q => JSON.stringify([qKind(q), q.team, q.player, q.stat, q.text, q.line]);
  const now = Object.fromEntries((newQs || []).map(q => [q.id, sig(q)]));
  return (oldQs || []).filter(q => now[q.id] !== sig(q)).map(q => q.id);
}

const AVG_KEY = { PTS: "pts", REB: "reb", AST: "ast", "3PM": "tpm", BLK: "blk", STL: "stl" };

// Which questions to ask, in order. Each slot takes the best remaining
// player for that stat; `min` skips the slot when nobody averages enough.
const POR_SLOTS = [
  { stat: "PTS" }, { stat: "PTS" }, { stat: "REB" }, { stat: "AST" },
  { stat: "3PM", min: 1.5 }, { stat: "BLK", min: 1, fallback: "PTS" },
];
const OPP_SLOTS = [
  { stat: "PTS" }, { stat: "PTS" }, { stat: "REB" }, { stat: "AST", min: 4, fallback: "3PM" },
];

// ESPN's league-wide byathlete payload -> [{name, team, gp, min, pts, ...}]
export function parseAverages(json) {
  const cats = json.categories || [];
  const idx = {};
  cats.forEach(c => { idx[c.name] = c.names || []; });
  const pick = (a, cat, name) => {
    const c = (a.categories || []).find(x => x.name === cat);
    const i = (idx[cat] || []).indexOf(name);
    return c && i >= 0 ? Number(c.values[i]) || 0 : 0;
  };
  return (json.athletes || []).map(a => ({
    name: a.athlete.displayName,
    team: a.athlete.teamShortName,
    gp: pick(a, "general", "gamesPlayed"),
    min: pick(a, "general", "avgMinutes"),
    pts: pick(a, "offensive", "avgPoints"),
    reb: pick(a, "general", "avgRebounds"),
    ast: pick(a, "offensive", "avgAssists"),
    tpm: pick(a, "offensive", "avgThreePointFieldGoalsMade"),
    stl: pick(a, "defensive", "avgSteals"),
    blk: pick(a, "defensive", "avgBlocks"),
  }));
}

export function buildLines(averages, team, { out = [], opponent = false, startId = 1 } = {}) {
  const outSet = new Set(out);
  const pool = averages.filter(p => p.team === team && p.gp >= 1 && p.min >= 18 && !outSet.has(p.name));
  const used = new Set(), perPlayer = {};
  const qs = [];
  for (const slot of opponent ? OPP_SLOTS : POR_SLOTS) {
    const choose = stat => pool
      .filter(p => !used.has(p.name + "|" + stat) && (perPlayer[p.name] || 0) < 2)
      .sort((a, b) => b[AVG_KEY[stat]] - a[AVG_KEY[stat]])[0];
    let stat = slot.stat, p = choose(stat);
    if (!p || (slot.min && p[AVG_KEY[stat]] < slot.min)) {
      if (!slot.fallback) continue;
      stat = slot.fallback; p = choose(stat);
      if (!p) continue;
    }
    used.add(p.name + "|" + stat);
    perPlayer[p.name] = (perPlayer[p.name] || 0) + 1;
    qs.push({ id: "q" + (startId + qs.length), team, player: p.name, stat, line: Math.max(1, Math.round(p[AVG_KEY[stat]])) });
  }
  return qs;
}

// ESPN summary boxscore -> { "Player Name": {PTS, REB, ...} } for everyone who played.
export function parseBox(summary, team) {
  const out = {};
  for (const t of summary?.boxscore?.players || []) {
    if (team && t.team?.abbreviation !== team) continue;
    const st = t.statistics?.[0];
    if (!st) continue;
    for (const a of st.athletes || []) {
      if (a.didNotPlay || !a.stats?.length) continue;
      const v = {};
      st.keys.forEach((k, i) => {
        const raw = a.stats[i];
        if (k === "minutes") v.MIN = +raw || 0;
        else if (k === "points") v.PTS = +raw;
        else if (k === "rebounds") v.REB = +raw;
        else if (k === "assists") v.AST = +raw;
        else if (k === "steals") v.STL = +raw;
        else if (k === "blocks") v.BLK = +raw;
        else if (k.startsWith("threePointFieldGoalsMade")) v["3PM"] = +String(raw).split("-")[0];
      });
      out[a.athlete.displayName] = v;
    }
  }
  return out;
}

// Backup for parseAverages: per-game averages from a team's recent box scores.
export function averagesFromBoxes(summaries, team) {
  const sum = {};
  for (const s of summaries) {
    for (const [name, v] of Object.entries(parseBox(s, team))) {
      const a = sum[name] ||= { name, team, gp: 0, min: 0, pts: 0, reb: 0, ast: 0, tpm: 0, stl: 0, blk: 0 };
      a.gp++; a.min += v.MIN || 0; a.pts += v.PTS || 0; a.reb += v.REB || 0; a.ast += v.AST || 0;
      a.tpm += v["3PM"] || 0; a.stl += v.STL || 0; a.blk += v.BLK || 0;
    }
  }
  return Object.values(sum).map(a => {
    const r = { name: a.name, team, gp: a.gp };
    for (const k of ["min", "pts", "reb", "ast", "tpm", "stl", "blk"]) r[k] = a[k] / a.gp;
    return r;
  });
}

// Final result for a game from its ESPN summary, or null if not final yet.
export function gradeFromSummary(summary, questions, oppAbbr) {
  const comp = summary?.header?.competitions?.[0];
  if (!comp || !comp.status?.type?.completed) return null;
  const teams = comp.competitors || [];
  const por = teams.find(c => c.team?.abbreviation === "POR");
  const opp = teams.find(c => c !== por);
  if (!por || !opp) return null;
  const porScore = +por.score, oppScore = +opp.score;
  const box = parseBox(summary);
  const values = {}, voided = [];
  for (const q of questions) {
    if (qKind(q) !== "stat") continue; // the commissioner grades these
    const v = box[q.player]?.[q.stat];
    if (typeof v === "number" && !Number.isNaN(v)) values[q.id] = v;
    else voided.push(q.id); // didn't play: no points either way
  }
  return { winner: porScore > oppScore ? "POR" : oppAbbr, porScore, oppScore, values, voided, source: "espn", gradedAt: new Date().toISOString() };
}

export function markQ(pick, q, fin) {
  if (!pick || !fin || typeof fin.values?.[q.id] !== "number") return null;
  const v = fin.values[q.id];
  if (qKind(q) === "yn") return (v === 1) === (pick === "yes") ? 1 : -1;
  if (v === q.line) return 0;
  return (v > q.line) === (pick === "over") ? 1 : -1;
}

export function markW(pick, fin) {
  if (!pick || !fin?.winner) return null;
  return pick === fin.winner ? 1 : -1;
}
