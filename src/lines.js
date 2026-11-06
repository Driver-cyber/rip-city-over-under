// Pure game logic shared by the Worker and the tests: building lines from
// season averages, reading a box score, and scoring picks.

export const STATS = ["PTS", "REB", "AST", "3PM", "BLK", "STL"];

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
export function parseBox(summary) {
  const out = {};
  for (const t of summary?.boxscore?.players || []) {
    const st = t.statistics?.[0];
    if (!st) continue;
    for (const a of st.athletes || []) {
      if (a.didNotPlay || !a.stats?.length) continue;
      const v = {};
      st.keys.forEach((k, i) => {
        const raw = a.stats[i];
        if (k === "points") v.PTS = +raw;
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
    const v = box[q.player]?.[q.stat];
    if (typeof v === "number" && !Number.isNaN(v)) values[q.id] = v;
    else voided.push(q.id); // didn't play: no points either way
  }
  return { winner: porScore > oppScore ? "POR" : oppAbbr, porScore, oppScore, values, voided, source: "espn", gradedAt: new Date().toISOString() };
}

export function markQ(pick, q, fin) {
  if (!pick || !fin || typeof fin.values?.[q.id] !== "number") return null;
  const v = fin.values[q.id];
  if (v === q.line) return 0;
  return (v > q.line) === (pick === "over") ? 1 : -1;
}

export function markW(pick, fin) {
  if (!pick || !fin?.winner) return null;
  return pick === fin.winner ? 1 : -1;
}
