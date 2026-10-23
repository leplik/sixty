# Sixty — design spec

Status: v0.1 draft, 2026-10-23. Owner: Aliaksei Smirnou.

## 1. Purpose

Sixty makes you stand up once an hour. After 60 minutes of work it locks every screen for 60 seconds and shows two short exercises: one for the spine and the lower back, then another. It does not lock while you are in a call.

Sixty exists because break reminders with a "Skip" or "Postpone" button get skipped on autopilot. Sixty has no such button and no settings.

## 2. Principles

- **No settings.** One fixed cycle: 60 min of work, 60 s warning, 60 s break. No preferences window.
- **No easy way out.** No Skip, no Postpone, no Quit. The only exit from a break is an emergency phrase that changes every time.
- **Never interrupt a call.** If a call is active, the break waits.
- **Private by design.** No telemetry, no audio capture. Sixty reads only the "device is in use" flags of the microphone, the speaker and the camera. Its only network request is the update check (section 12).
- **Small and native.** Swift 6, AppKit + SwiftUI, macOS 14+, no third-party dependencies.

## 3. Behaviour

### 3.1 State machine

```
WORKING ──60 min of work──▶ in a call? ──no──▶ WARNING ──60 s──▶ BREAK ──60 s──▶ WORKING
   ▲                            │ yes            ▲       │
   │                            ▼                │       │ call started
   │                        POSTPONED ◀──────────┼───────┘
   │                            │                │
   │                            └────────────────┘ call ended + 2 min
   │
   └── away ≥ 20 min (no input and no call) or Mac asleep ≥ 20 min → work counter = 0
```

### 3.2 Rules

| Rule | Value |
|---|---|
| Work interval | 60 min of active time |
| Warning | 60 s, small panel in the top-right corner, no buttons, click-through |
| Break | 60 s, all screens locked |
| Away threshold | 20 min without keyboard or mouse input, outside a call (was 5 min until 0.1.2: reading or watching reset the hour) |
| Grace after a call | 2 min, then the normal 60 s warning |
| Watchdog | a break never lasts more than 90 s, even if the state machine fails |
| Emergency exits | 2 per day |

- Sixty counts only active time. If you are away for 20 min or more, the counter goes back to 0. You already took a break. Shorter idle time counts as work: reading or watching is still sitting.
- No input during a call does not count as "away". You can listen to a meeting without touching the keyboard.
- If the screen is locked, the time since the lock counts as idle time.
- If the Mac sleeps for 20 min or more, the counter goes back to 0.
- If a call starts during the warning, the break is postponed.
- A call that starts during a break does not end the break. You cannot answer it. You call back after 60 s.
- There are no working hours. Sixty only counts time at the computer, so weekends need no special rule.

## 4. Call detection

A call is active if one of these signals is present:

1. **Camera.** Any app uses any camera (CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere`).
2. **Microphone.** A known call app records from the microphone. Since macOS 14, CoreAudio lists every audio client process with its bundle ID (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunningInput`).
3. **Speaker.** A dedicated meeting app plays audio (`kAudioProcessPropertyIsRunningOutput`): Teams, Zoom, Webex, FaceTime, phone calls. This covers "I listen with my microphone muted". Browsers, Slack and Telegram are not on this list, because they also play videos and notification sounds.

A bundle ID matches an app if it is equal to one of the app's IDs or starts with that ID plus a dot. So `com.google.Chrome` also matches `com.google.Chrome.helper`. The comparison ignores case.

Known call apps (v1):

| App | Bundle IDs | Speaker counts |
|---|---|---|
| Google Chrome | `com.google.Chrome` | no |
| Arc | `company.thebrowser.Browser` | no |
| Dia | `company.thebrowser.dia` | no |
| Safari and WebKit apps | `com.apple.Safari`, `com.apple.WebKit.GPU` | no |
| Microsoft Edge | `com.microsoft.edgemac` | no |
| Brave | `com.brave.Browser` | no |
| Firefox | `org.mozilla.firefox`, `org.mozilla.plugincontainer` | no |
| Vivaldi | `com.vivaldi.Vivaldi` | no |
| Opera | `com.operasoftware.Opera` | no |
| Microsoft Teams | `com.microsoft.teams`, `com.microsoft.teams2` | yes |
| Zoom | `us.zoom.xos` | yes |
| Webex | `Cisco-Systems.Spark`, `com.webex.meetingmanager` | yes |
| FaceTime and phone calls | `com.apple.FaceTime`, `com.apple.avconferenced`, `com.apple.TelephonyUtilities` | yes |
| Slack | `com.tinyspeck.slackmacgap` | no |
| Telegram | `com.tdesktop.Telegram`, `ru.keepcoder.Telegram` | no |
| WhatsApp | `net.whatsapp.WhatsApp`, `desktop.WhatsApp` | no |
| Discord | `com.hnc.Discord` | no |
| Signal | `org.whispersystems.signal-desktop` | no |
| Viber | `com.viber.osx` | no |
| Skype | `com.skype.skype` | no |
| Granola | `com.granola.app` | no |

Why process-level signals and not window titles:

- No permission prompts. Reading "device in use" flags needs no microphone, camera or Accessibility access. A spike on macOS 26.5 confirmed this.
- It works with any call app, also in a browser tab. Nothing breaks when an app changes its UI.
- Dictation tools (for example Handy, Superwhisper) and recorders (OBS) also hold the microphone. They are not on the list, so they do not postpone breaks.

The menu always shows why a break waits ("Waiting for your call in Microsoft Teams to end"). So a stuck signal is visible, not silent.

Sixty reads the signals every 2 s. It does not read audio data.

## 5. The lock

- One borderless window per screen at `CGShieldingWindowLevel()`. It is on all Spaces and above full-screen apps.
- Kiosk mode through `NSApplication.presentationOptions`: `hideDock`, `hideMenuBar`, `disableProcessSwitching` (no Cmd+Tab), `disableForceQuit` (no Cmd+Opt+Esc), `disableSessionTermination`, `disableHideApplication`, `disableAppleMenu`.
- Sixty activates itself and makes the main lock window key. Every second it checks this again and corrects it.
- If a screen is connected during a break, the lock window appears on it too.
- After the break, Sixty gives the focus back to the app that was active before.
- If Sixty crashes, the windows disappear. The lock fails open; it never freezes the Mac.
- Out of scope: the power button and `kill` over SSH. Blocking them needs root. That is acceptable.

Lock screen content:

- "Time to move" and two exercises, 30 s each: first one for the spine and the lower back, then another (`Exercises.plan`). Nothing repeats from the previous break. Every exercise is done standing.
- An animated stick figure shows the current exercise; the ring counts down its 30 s; two dots show "1 of 2".
- On the main screen only: the emergency exit.
- Other screens show the countdown only.

## 6. Emergency exit

- The main lock window shows a phrase of 4 random words, for example `river candle orbit maple`, and a text field.
- If you type the phrase, the break ends at once. The phrase is new for every break, so you cannot learn it and type it on autopilot.
- 2 exits per day. After that, the field is gone and the window says so.
- The text field accepts only Latin input sources (`NSAllRomanInputSourcesLocaleIdentifier`), so the phrase can be typed whatever keyboard layout is active.
- Case and extra spaces are ignored.

## 7. Menu bar

- Icon and minutes to the next break, for example `42m`. During the warning: seconds. During a postponed break: a phone icon.
- Menu items (read-only): status line, "Breaks today: N", "Emergency exits left today: N of 2".
- "About Sixty" opens the website. "How to turn Sixty off" opens the README section.
- There is no Quit item.

## 8. Turning Sixty off

There is no Quit, on purpose: Quit can also be clicked on autopilot.

- Sixty runs as a LaunchAgent registered through `SMAppService.agent` with `KeepAlive`. If the process is killed, launchd starts it again.
- The work counter is saved every 10 s. After a restart Sixty continues the same cycle, so killing it during the warning does not skip the break.
- To turn it off: `/Applications/Sixty.app/Contents/MacOS/Sixty --disable` in Terminal, or switch Sixty off in System Settings → General → Login Items & Extensions.
- To turn it on again: open Sixty.app.

## 9. Launch logic

```
process starts
   │
   ├─ `--disable` ───────────────▶ unregister the agent, exit
   ├─ `--reregister` ────────────▶ unregister + register the agent for the app on disk (new signature), exit
   ├─ `--probe` ─────────────────▶ print the apps on the microphone / speaker, the camera state and the verdict, exit
   ├─ SIXTY_DEMO=1 ──────────────▶ run here with the short demo cycle, no agent
   ├─ not inside an .app ────────▶ run here (development with `swift run`)
   ├─ started by launchd (XPC_SERVICE_NAME = agent label) ──▶ run
   ├─ another Sixty runs ────────▶ exit
   ├─ agent already enabled ─────▶ run here (agent was booted out until next login)
   └─ register agent ──ok──▶ run here; exit after 3 s if the agent instance appeared
                     └─fail─▶ run here; open Login Items settings if approval is needed
```

## 9a. Diagnostics

Sixty writes to the macOS unified log, subsystem `pro.saac.sixty`, level `notice`, so the lines are kept:

- `cycle`: start (version, restored work), warning (with the two exercises), break started and finished, postponed (with the call signal), every reset with its reason (`no input for N min`, `screen locked`, `the Mac slept`), "Take a Break Now", emergency exits, watchdog; plus a heartbeat every 10 minutes (phase, minutes worked, idle seconds, call signal, breaks today).
- `calls`: every change of the call signal (`none -> Telegram (microphone)`).
- `update`, `agent`: update checks and installs, login agent registration.

`Sixty --log` prints the last 6 hours. Everything logged is public: phases, timings, app and exercise names; never personal data.

## 10. Localisation

English only: the app, the website, the docs and the store listing. UI strings go through `L()` with the English text as the key.

## 11. Project layout

```
Package.swift                 SwiftPM, macOS 14+, Swift 6 language mode
Sources/SixtyCore/            pure logic, fully unit-tested
  BreakMachine.swift          state machine (section 3)
  CallPolicy.swift            call apps and signal rules (section 4)
  EscapePhrase.swift          phrase generator and matcher (section 6)
  DailyStats.swift            breaks and exits per day
  Exercises.swift             exercise list
  Timing.swift                fixed durations, demo durations
Sources/Sixty/                macOS adapters and UI
Tests/SixtyCoreTests/         Swift Testing
Resources/                    Info.plist, LaunchAgent plist, entitlements, icon
scripts/build-app.sh          builds, bundles and signs Sixty.app
site/                         GitHub Pages website
.github/workflows/            CI, release, pages
```

## 12. Build and release

- `make test` runs the unit tests. `make app` builds `build/Sixty.app` (ad-hoc signed). `make demo` runs the short cycle: 20 s work, 5 s warning, 10 s break.
- Releases are automatic: [release-please](https://github.com/googleapis/release-please) reads Conventional Commits on `main` and keeps a release PR with the next version and the changelog. Merging that PR creates the tag and the GitHub Release.
- The release job then builds a universal binary (arm64 + x86_64), signs it with the Developer ID of SAAC sp. z o.o. (hardened runtime), notarizes the DMG with `notarytool`, staples the DMG and the app, and uploads `Sixty-<version>.dmg` and `Sixty-<version>.zip` to the release.
- In-app updates: see below.
- Homebrew: the release job updates `Casks/sixty.rb` in the tap `leplik/homebrew-tap` with a write deploy key (secret `HOMEBREW_TAP_DEPLOY_KEY`). Install: `brew install --cask leplik/tap/sixty`.
- Required GitHub secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `HOMEBREW_TAP_DEPLOY_KEY`. See `docs/RELEASING.md`.

### In-app updates

Silent, no Sparkle, no UI. `Sources/Sixty/Updater.swift`, rules in `Sources/SixtyCore/Updates.swift`.

```
every 12 h (1 h after a failed check)
  GET api.github.com/repos/leplik/sixty/releases/latest
  newer, not draft, not prerelease, has Sixty-<v>.zip on github.com?  ──no──▶ done
  download → ~/Library/Application Support/Sixty/Updates → ditto -x -k
  Developer ID, team JVW2N74WL3, identifier pro.saac.sixty, strict, all archs?  ──no──▶ delete, done
  CFBundleShortVersionString == <v>?  ──no──▶ delete, done
  wait until phase == WORKING (never during a warning, a break or a postponed break)
  save the work counter → replace /Applications/Sixty.app
  → `open -n Sixty.app --args --reregister` → exit(0) → launchd starts the new version
```

- Runs only in an installed copy (`/Applications` or `~/Applications`) that launchd started. Never in `build/`, `swift run` or the demo.
- Trust comes from Apple code signing, not from the download channel: a tampered or foreign archive fails the signature check.
- Forks change `Updater.teamID`, `UpdatePolicy.latestReleaseURL` and the bundle ID.
- The work counter survives the restart, so an update never skips or shifts a break.
- launchd may refuse to start the agent right after the bundle changed (exit 78, EX_CONFIG): always when the designated requirement changed (an ad-hoc build's requirement is its cdhash), sometimes on the first launch of a freshly copied bundle. So `--reregister` checks that the agent runs, retries 3 times with a growing pause, and otherwise keeps running as a stand-in that hands over once the agent starts (at the latest at the next login).

## 13. Website, SEO and GEO

- Static site in `site/`, deployed to GitHub Pages by a workflow. Default URL: `https://leplik.github.io/sixty/`.
- One fast English page plus a privacy page. No frameworks, no trackers.
- SEO: unique title and description, canonical URL, Open Graph and Twitter cards, `sitemap.xml`, `robots.txt`, JSON-LD `SoftwareApplication` (free, macOS) and `FAQPage`.
- GEO (answers in AI assistants): `llms.txt` with a plain-text summary, short factual answers in the FAQ, a clear "how it works" section, and explicit facts (price, platform, permissions, licence). The README repeats the same facts.
- Repository metadata: description, homepage and topics (`macos`, `break-reminder`, `stand-up-reminder`, `stretch`, `screen-lock`, `menu-bar-app`, `swift`, `productivity`, `health`).

## 14. Mac App Store edition

Same code, built with `-DAPP_STORE` by `scripts/build-appstore.sh`. Store name: "Sixty — Move Every Hour"; bundle ID `pro.saac.sixty.mas`, so both editions can live on one Mac without sharing an agent or preferences.

| | GitHub edition | App Store edition |
|---|---|---|
| Sandbox | no | yes, no entitlements besides `app-sandbox` (no network, no files) |
| Start at login | KeepAlive LaunchAgent, restarts if killed | login item, only after the user agreed (first-launch question, menu toggle) |
| Quit | none (`--disable` in Terminal) | "Quit Sixty…" asks for a fresh random phrase |
| Lock | full kiosk | full kiosk (owner's decision; App Review may object under 2.5.9) |
| Updates | silent self-updater | the App Store |
| Call signals | camera, microphone, speaker | microphone, speaker. In the sandbox CoreMediaIO lists no cameras (tested), and a camera entitlement is not worth a review question: a call with the camera on also uses the microphone |

Both editions have "Take a Break Now" in the menu. It adds a break and never skips one; App Review uses it to see the lock without waiting an hour.

Release steps: `docs/RELEASING.md`, section "Mac App Store".

## 15. Known limitations

- Watching a video without input outside a call counts as "away" after 20 min. The counter resets and that break is skipped.
- A short absence (under 20 min) counts as work, so the next break comes a little early. That errs on the safe side.
- A browser that records from the microphone for something that is not a call (for example voice input on a website) postpones the break.
- If a meeting app keeps its audio output open when no call is active, every break waits. The menu shows the reason. Check this for Teams before v1.
- macOS 14 made app activation cooperative. If `activate(ignoringOtherApps:)` does not take the focus, the screens are still covered, but keystrokes may go to the app below until the first click. Verify on macOS 14, 15 and 26.

## 16. Manual QA before v1

- [ ] `make demo`: the warning shows, then all screens lock, then they unlock after 10 s.
- [ ] During a break: Cmd+Tab, Cmd+Opt+Esc, Cmd+Space, Mission Control (keys and trackpad), hot corners, Cmd+Q.
- [ ] Two screens; connect a screen during a break.
- [ ] A full-screen app on its own Space.
- [ ] A call in Google Meet (Chrome, Arc, Safari), Teams, Telegram: no break during the call; a break 2 min + 60 s after the call.
- [ ] Meet with both microphone and camera off: does Chrome still hold the microphone?
- [ ] Teams open without a call: is the speaker signal off?
- [ ] Dictation in Handy at break time: the break is not postponed.
- [ ] Emergency phrase with a non-Latin keyboard layout active; the limit of 2 per day.
- [ ] `kill` during the warning: launchd starts Sixty again and the warning comes back.
- [ ] `--disable` turns it off; opening Sixty.app turns it on.

## 17. Open questions

- GitHub owner: personal account `leplik` or an organisation? Custom domain for the site?
