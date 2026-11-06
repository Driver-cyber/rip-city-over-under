# Rip City Over/Under

A family pick'em for Portland Trail Blazers games: before each game, pick the winner and ten player stat lines (over or under). Right is +1, wrong is −1, a stat that lands exactly on the line is 0. A season leaderboard tracks who's ahead.

Live at **https://ripcity.chadstewartcpa.com**.

## How it works

One Cloudflare Worker serves the page (`public/index.html`) and a small JSON API (`src/worker.js`), with picks stored in a D1 database.

Every 15 minutes a cron trigger:

1. refreshes the Blazers schedule from ESPN,
2. posts lines for any game within 30 hours: six Blazers and four opponent questions built from season averages, skipping players listed out (`src/lines.js`),
3. grades finished games from ESPN's box score. A player who didn't play is voided.

Picks lock at tip-off. Other players' picks stay hidden until then.

Sign-in is a name plus a shared family passcode. Signing in with the admin passcode makes you the commissioner, who can edit lines, fix final stats, and trigger a sync from the home screen.

## Setup

```sh
npm install
npx wrangler login
npx wrangler d1 create ripcity          # paste the database_id into wrangler.jsonc
npm run db:migrate
npx wrangler secret put PASSCODE        # the family passcode
npx wrangler secret put ADMIN_PASSCODE  # the commissioner's passcode
npx wrangler secret put TOKEN_SECRET    # any long random string
npm run deploy
```

Local development: put `PASSCODE`, `ADMIN_PASSCODE` and `TOKEN_SECRET` in `.dev.vars` (gitignored), run `npx wrangler d1 migrations apply ripcity --local`, then `npm run dev`.

Tests: `npm test`.

Stats come from ESPN's public site API, which is unofficial and may change.
