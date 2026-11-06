# Rip City Over/Under for iPhone

A native SwiftUI version of the player screens: home, picks (swipe cards or
list), leaderboard, schedule and the roster yearbook. It talks to the same
Worker as the website (`ripcity.chadstewartcpa.com`), so picks and the
leaderboard are shared. Commissioner tools stay on the website for now.

The menu is the pinwheel in the bottom-right corner: tap it and the red blades
uncurl into spokes pointing at Tonight, Standings, Schedule, Yearbook and Home.

## Build

The Xcode project is generated from `project.yml`:

```sh
cd ios/RipCity
xcodegen generate
open RipCity.xcodeproj
```

Team `Y3D7LWWL56`, bundle id `com.chadstewartcpa.ripcity`, automatic signing.

## Put it on a phone

- **Cable or Wi-Fi from Xcode:** pick the phone as the run destination and press
  Run. Builds signed this way last a year on that phone.
- **TestFlight (over the air):** Product → Archive, then Distribute App →
  App Store Connect → Upload. In App Store Connect, add the app's testers under
  TestFlight → Internal Testing; they install it from the TestFlight app. Each
  build lasts 90 days. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload.

## Tests

- `RipCityTests` checks that scoring and decoding match the web page
  (`public/index.html` stays the source of truth).
- `RipCityUITests` walks the screens against a local `wrangler dev` and saves
  screenshots. It skips itself unless given a test token:

```sh
npx wrangler dev --port 8799 --ip 127.0.0.1      # from the repo root, with .dev.vars
TOKEN=$(curl -s 127.0.0.1:8799/api/login -H 'content-type: application/json' \
  -d '{"name":"Joelle","passcode":"family"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
TEST_RUNNER_RIPCITY_TOKEN=$TOKEN TEST_RUNNER_RIPCITY_SHOTS=/tmp/shots \
  xcodebuild test -project RipCity.xcodeproj -scheme RipCity -destination 'platform=iOS Simulator,name=iPhone 17'
```

The app icon is drawn by `swift tools/make-icon.swift`.
