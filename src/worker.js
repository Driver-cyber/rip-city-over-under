import { qKind, cleanQuestions, changedQuestionIds, parseAverages, averagesFromBoxes, buildLines, gradeFromSummary } from "./lines.js";

const ESPN = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba";
const AVERAGES = "https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/statistics/byathlete?limit=600";
const LINES_AHEAD_MS = 30 * 3600e3; // post lines once a game is within 30 hours
const MAX_GRADES_PER_RUN = 5;
const BOX_GAMES = 10; // recent games per team for the backup averages
const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (!url.pathname.startsWith("/api/")) return env.ASSETS.fetch(req);
    try {
      return await api(req, env, url);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error(e);
      return json({ error: "Something went wrong on the server." }, 500);
    }
  },
  async scheduled(_evt, env, ctx) {
    ctx.waitUntil(sync(env).then(log => console.log(log.join("\n"))));
  },
};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json", "cache-control": "no-store" },
});
const now = () => new Date().toISOString();

/* ---------- auth: token = playerId.hmac(playerId) ---------- */
async function hmac(env, msg) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.TOKEN_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg));
  return btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/[+/=]/g, c => ({ "+": "-", "/": "_", "=": "" }[c]));
}
function safeEqual(a, b) {
  a = String(a ?? ""); b = String(b ?? "");
  let d = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) d |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return d === 0;
}
async function me(req, env) {
  if (!env.TOKEN_SECRET) throw new HttpError(503, "The game isn't set up yet.");
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  const [id, sig] = tok.split(".");
  if (!id || !sig || !safeEqual(sig, await hmac(env, id))) throw new HttpError(401, "Sign in to play.");
  const p = await env.DB.prepare("SELECT id, name, is_admin FROM players WHERE id = ?").bind(id).first();
  if (!p) throw new HttpError(401, "Sign in to play.");
  return { id: p.id, name: p.name, admin: !!p.is_admin };
}

/* ---------- API ---------- */
async function api(req, env, url) {
  const path = url.pathname.replace(/\/+$/, "");
  const m = req.method;
  const body = async () => { try { return await req.json(); } catch { throw new HttpError(400, "Send JSON."); } };

  if (path === "/api/login" && m === "POST") {
    const { name, passcode } = await body();
    const clean = String(name || "").trim().replace(/\s+/g, " ");
    if (!clean || clean.length > 20) throw new HttpError(400, "Enter a name up to 20 characters.");
    if (!env.PASSCODE || !env.TOKEN_SECRET) throw new HttpError(503, "The game isn't set up yet.");
    if (!passcode) throw new HttpError(403, "Enter the family passcode.");
    const admin = !!env.ADMIN_PASSCODE && safeEqual(passcode, env.ADMIN_PASSCODE);
    if (!admin && !safeEqual(passcode, env.PASSCODE)) throw new HttpError(403, "That passcode isn't right.");
    const key = clean.toLowerCase();
    let p = await env.DB.prepare("SELECT id, name, is_admin FROM players WHERE name_key = ?").bind(key).first();
    if (!p) {
      p = { id: crypto.randomUUID(), name: clean, is_admin: admin ? 1 : 0 };
      await env.DB.prepare("INSERT INTO players (id, name, name_key, is_admin, created_at) VALUES (?, ?, ?, ?, ?)").bind(p.id, clean, key, p.is_admin, now()).run();
    } else if (admin && !p.is_admin) {
      await env.DB.prepare("UPDATE players SET is_admin = 1 WHERE id = ?").bind(p.id).run();
      p.is_admin = 1;
    }
    return json({ token: p.id + "." + await hmac(env, p.id), me: { id: p.id, name: p.name, admin: !!p.is_admin } });
  }

  const who = await me(req, env);

  if (path === "/api/state" && m === "GET") return json(await state(env, who));

  // Promote the signed-in player to commissioner without a second account.
  if (path === "/api/unlock" && m === "POST") {
    const { passcode } = await body();
    if (!env.ADMIN_PASSCODE || !passcode || !safeEqual(passcode, env.ADMIN_PASSCODE)) throw new HttpError(403, "That isn't the commissioner passcode.");
    await env.DB.prepare("UPDATE players SET is_admin = 1 WHERE id = ?").bind(who.id).run();
    return json({ me: { ...who, admin: true } });
  }

  let hit;
  if ((hit = path.match(/^\/api\/picks\/(\d+)$/)) && m === "PUT") {
    const g = await getGame(env, hit[1]);
    if (!g.questions?.length) throw new HttpError(409, "Lines for this game aren't posted yet.");
    if (Date.now() >= Date.parse(g.tip)) throw new HttpError(409, "Picks are locked. The game has started.");
    const b = await body();
    const winner = b.winner === "POR" || b.winner === g.opp ? b.winner : null;
    const kinds = Object.fromEntries(g.questions.map(q => [q.id, qKind(q)]));
    const q = {};
    for (const [k, v] of Object.entries(b.q || {})) {
      if (!kinds[k]) continue;
      if (kinds[k] === "yn" ? v === "yes" || v === "no" : v === "over" || v === "under") q[k] = v;
    }
    await env.DB.prepare(`INSERT INTO picks (player_id, game_id, winner, q, updated_at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT (player_id, game_id) DO UPDATE SET winner = excluded.winner, q = excluded.q, updated_at = excluded.updated_at`)
      .bind(who.id, g.id, winner, JSON.stringify(q), now()).run();
    return json({ ok: true });
  }

  if (path.startsWith("/api/admin/")) {
    if (!who.admin) throw new HttpError(403, "Only the commissioner can do that.");
    if ((hit = path.match(/^\/api\/admin\/lines\/(\d+)$/)) && m === "PUT") {
      const g = await getGame(env, hit[1]);
      if (Date.now() >= Date.parse(g.tip)) throw new HttpError(409, "The game has started, so the lines are locked.");
      const qs = cleanQuestions((await body()).questions, g.opp);
      if (!qs.length) throw new HttpError(400, "Add at least one complete question.");
      const changed = new Set(changedQuestionIds(g.questions, qs));
      const stmts = [env.DB.prepare("UPDATE games SET questions = ?, updated_at = ? WHERE id = ?").bind(JSON.stringify(qs), now(), g.id)];
      let cleared = 0;
      if (changed.size) {
        const rows = (await env.DB.prepare("SELECT player_id, q FROM picks WHERE game_id = ?").bind(g.id).all()).results;
        for (const r of rows) {
          const q = JSON.parse(r.q || "{}"), before = Object.keys(q).length;
          for (const id of changed) delete q[id];
          if (Object.keys(q).length === before) continue;
          cleared += before - Object.keys(q).length;
          stmts.push(env.DB.prepare("UPDATE picks SET q = ?, updated_at = ? WHERE player_id = ? AND game_id = ?").bind(JSON.stringify(q), now(), r.player_id, g.id));
        }
      }
      await env.DB.batch(stmts);
      return json({ ok: true, cleared });
    }
    if ((hit = path.match(/^\/api\/admin\/autolines\/(\d+)$/)) && m === "POST") {
      const g = await getGame(env, hit[1]);
      if (Date.now() >= Date.parse(g.tip)) throw new HttpError(409, "The game has started, so the lines are locked.");
      const log = [];
      const stat = await statLines(g, log);
      if (!stat) throw new HttpError(502, log.join(" ") || "Couldn't build lines from ESPN right now.");
      return json({ questions: stat, log });
    }
    if ((hit = path.match(/^\/api\/admin\/roster\/(\d+)$/)) && m === "GET") {
      const g = await getGame(env, hit[1]);
      const out = {};
      for (const t of ["POR", g.opp]) {
        try {
          const r = await getJSON(`${ESPN}/teams/${t.toLowerCase()}/roster`);
          out[t] = (r.athletes || []).flatMap(a => a.items || [a]).map(a => a.displayName).filter(Boolean).sort();
        } catch { out[t] = []; }
      }
      return json(out);
    }
    if ((hit = path.match(/^\/api\/admin\/final\/(\d+)$/)) && m === "PUT") {
      const g = await getGame(env, hit[1]);
      if (Date.now() < Date.parse(g.tip)) throw new HttpError(409, "The game hasn't started yet.");
      const f = (await body()).final || {};
      // ESPN fills in the player stats after the final buzzer; until it has,
      // a missing stat means "not in yet", not "didn't play".
      const espnGraded = !!(g.final?.espnGraded || g.final?.source === "espn");
      const num = v => (v === null || v === "" || v === undefined || !Number.isFinite(Number(v))) ? null : Number(v);
      const values = {};
      for (const q of g.questions || []) {
        const raw = f.values?.[q.id];
        const v = qKind(q) === "yn" ? (raw === "yes" || raw === 1 ? 1 : raw === "no" || raw === 0 ? 0 : null) : num(raw);
        if (v !== null) values[q.id] = v;
      }
      const final = {
        winner: f.winner === "POR" || f.winner === g.opp ? f.winner : null,
        porScore: num(f.porScore), oppScore: num(f.oppScore), values,
        voided: espnGraded ? (g.questions || []).filter(q => qKind(q) === "stat" && !(q.id in values)).map(q => q.id) : [],
        espnGraded, source: "manual", gradedAt: now(),
      };
      await env.DB.prepare("UPDATE games SET final = ?, updated_at = ? WHERE id = ?").bind(JSON.stringify(final), now(), g.id).run();
      return json({ ok: true });
    }
    if (path === "/api/admin/sync" && m === "POST") return json({ log: await sync(env) });
  }
  throw new HttpError(404, "Not found.");
}

const rowToGame = r => ({
  id: r.id, tip: r.tip, home: !!r.home, opp: r.opp, oppName: r.opp_name,
  questions: r.questions ? JSON.parse(r.questions) : null,
  final: r.final ? JSON.parse(r.final) : null,
});
async function getGame(env, id) {
  const r = await env.DB.prepare("SELECT * FROM games WHERE id = ?").bind(id).first();
  if (!r) throw new HttpError(404, "That game isn't on the schedule.");
  return rowToGame(r);
}

// Everything the page needs. Other players' picks stay hidden until tip-off;
// before that the page only learns that they have picked.
async function state(env, who) {
  const [gs, ps, pk] = await env.DB.batch([
    env.DB.prepare("SELECT * FROM games ORDER BY tip"),
    env.DB.prepare("SELECT id, name FROM players ORDER BY created_at"),
    env.DB.prepare("SELECT player_id, game_id, winner, q FROM picks"),
  ]);
  const games = gs.results.map(rowToGame);
  const tips = Object.fromEntries(games.map(g => [g.id, Date.parse(g.tip)]));
  const t = Date.now();
  const picks = {}, pickedBy = {};
  for (const r of pk.results) {
    const open = t < tips[r.game_id];
    if (r.player_id !== who.id && open) { (pickedBy[r.game_id] ||= []).push(r.player_id); continue; }
    (picks[r.player_id] ||= {})[r.game_id] = { winner: r.winner, q: JSON.parse(r.q || "{}") };
  }
  return { me: who, serverTime: new Date(t).toISOString(), players: ps.results, games, picks, pickedBy };
}

/* ---------- sync: schedule, lines, grading ---------- */
async function getJSON(url) {
  const r = await fetch(url, { headers: { accept: "application/json", "user-agent": UA } });
  if (!r.ok) throw new Error(`ESPN answered ${r.status} for ${new URL(url).pathname}`);
  return r.json();
}

export async function sync(env) {
  const log = [];
  // 1. Schedule: add new games, follow reschedules.
  let sched;
  try { sched = await getJSON(`${ESPN}/teams/por/schedule`); }
  catch (e) { return [`schedule: ${e.message}`]; }
  const stmts = [];
  const finals = new Set();
  for (const e of sched.events || []) {
    const c = e.competitions?.[0];
    const por = c?.competitors?.find(x => x.team?.abbreviation === "POR");
    const opp = c?.competitors?.find(x => x !== por);
    if (!por || !opp) continue;
    if (c.status?.type?.completed) finals.add(e.id);
    stmts.push(env.DB.prepare(`INSERT INTO games (id, tip, home, opp, opp_name, updated_at) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET tip = excluded.tip, home = excluded.home, opp = excluded.opp, opp_name = excluded.opp_name`)
      .bind(e.id, e.date, por.homeAway === "home" ? 1 : 0, opp.team.abbreviation, opp.team.displayName, now()));
  }
  if (stmts.length) await env.DB.batch(stmts);
  log.push(`schedule: ${stmts.length} games`);

  const games = (await env.DB.prepare("SELECT * FROM games ORDER BY tip").all()).results.map(rowToGame);
  const t = Date.now();

  // 2. Lines for the next game, from season averages, skipping players listed out.
  const due = games.filter(g => !(g.questions || []).some(q => qKind(q) === "stat") && Date.parse(g.tip) > t && Date.parse(g.tip) - t < LINES_AHEAD_MS);
  const cache = {};
  for (const g of due) try {
    const stat = await statLines(g, log, cache);
    if (!stat) continue;
    const specials = (g.questions || []).filter(q => qKind(q) !== "stat");
    const r = await env.DB.prepare("UPDATE games SET questions = ?, updated_at = ? WHERE id = ? AND COALESCE(questions, '') = ?")
      .bind(JSON.stringify(stat.concat(specials)), now(), g.id, g.questions ? JSON.stringify(g.questions) : "").run();
    log.push(r.meta?.changes ? `lines vs ${g.opp}: ${stat.length} posted` : `lines vs ${g.opp}: changed while posting, skipped`);
  } catch (e) { log.push(`lines vs ${g.opp}: ${e.message}`); }

  // 3. Grade finished games that have lines and no final yet.
  const toGrade = games.filter(g => g.questions?.length && finals.has(g.id) && !(g.final?.espnGraded || g.final?.source === "espn")).slice(0, MAX_GRADES_PER_RUN);
  for (const g of toGrade) try {
    const final = gradeFromSummary(await getJSON(`${ESPN}/summary?event=${g.id}`), g.questions, g.opp);
    if (!final) { log.push(`grade vs ${g.opp}: box score not final yet`); continue; }
    // Keep any answers the commissioner already entered for their own questions.
    for (const q of g.questions) if (qKind(q) !== "stat" && typeof g.final?.values?.[q.id] === "number") final.values[q.id] = g.final.values[q.id];
    final.espnGraded = true;
    const r = await env.DB.prepare("UPDATE games SET final = ?, updated_at = ? WHERE id = ? AND COALESCE(final, '') = ?")
      .bind(JSON.stringify(final), now(), g.id, g.final ? JSON.stringify(g.final) : "").run();
    if (!r.meta?.changes) { log.push(`grade vs ${g.opp}: changed while grading, will retry`); continue; }
    log.push(`graded vs ${g.opp}: POR ${final.porScore}–${final.oppScore}`);
  } catch (e) { log.push(`grade vs ${g.opp}: ${e.message}`); }
  if (log.length === 1) log.push("nothing else to do right now");
  return log;
}

// Six Blazers and four opponent lines from season averages (or recent box
// scores if that page is refused), skipping players listed out. Null if
// there isn't enough data yet.
async function statLines(g, log, cache = {}) {
  if (cache.averages === undefined) {
    try { cache.averages = parseAverages(await getJSON(AVERAGES)); }
    catch (e) { cache.averages = null; log.push(`season averages: ${e.message}; using recent box scores instead`); }
  }
  const pool = cache.averages || await recentAverages(["POR", g.opp]);
  let out = [];
  try {
    const s = await getJSON(`${ESPN}/summary?event=${g.id}`);
    out = (s.injuries || []).flatMap(t => t.injuries || []).filter(i => /out/i.test(i.status || "")).map(i => i.athlete?.displayName);
  } catch (e) { log.push(`injuries vs ${g.opp}: ${e.message}`); }
  const por = buildLines(pool, "POR", { out });
  const opp = buildLines(pool, g.opp, { out, opponent: true, startId: por.length + 1 });
  if (por.length + opp.length < 4) { log.push(`lines vs ${g.opp}: not enough season data yet`); return null; }
  return por.concat(opp);
}

// Averages from each team's last few finished games, for when ESPN's
// league-wide stats page can't be reached.
async function recentAverages(teams) {
  const out = [];
  for (const team of teams) {
    const sched = await getJSON(`${ESPN}/teams/${team.toLowerCase()}/schedule`);
    const ids = (sched.events || []).filter(e => e.competitions?.[0]?.status?.type?.completed).map(e => e.id).slice(-BOX_GAMES);
    const summaries = await Promise.all(ids.map(id => getJSON(`${ESPN}/summary?event=${id}`).catch(() => null)));
    out.push(...averagesFromBoxes(summaries.filter(Boolean), team));
  }
  return out;
}
