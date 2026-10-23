# Contributing

Thank you for helping. Sixty is small on purpose, so please read the principles in [docs/SPEC.md](docs/SPEC.md) first.

## Scope

- **Welcome:** call apps that Sixty does not detect, bugs, exercises, accessibility, macOS compatibility.
- **Not wanted:** settings, a Skip or Postpone button, a Quit item, configurable timings. Sixty exists because those features get used on autopilot. Please open an issue first if you are not sure.

## Add a call app

1. Start a call in the app.
2. Run `make probe` (or `/Applications/Sixty.app/Contents/MacOS/Sixty --probe`).
3. Add the bundle ID to `CallPolicy.standard` in `Sources/SixtyCore/CallPolicy.swift`. Set `speakerMeansCall: true` only for apps that play audio during calls and nowhere else.
4. Add a case to `knownAppsOnTheMicrophone` in `Tests/SixtyCoreTests/CallPolicyTests.swift`.

## Develop

- `make test` runs the unit tests (Swift Testing). All logic lives in `SixtyCore` and has tests; write the test first.
- `make demo` runs a short cycle (20 s work, 5 s warning, 10 s break) without the login agent. Stop it with Ctrl+C in the terminal.
- UI text goes through `L()`; the key is the English text. Sixty is English only.

## Commits and releases

Use [Conventional Commits](https://www.conventionalcommits.org): `feat: …`, `fix: …`, `docs: …`, `chore: …`. release-please reads them, writes the changelog and picks the next version. See [docs/RELEASING.md](docs/RELEASING.md).
