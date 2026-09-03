# Repository Guidelines

## Public Repository Context

Read `README.md` before making changes to understand ViMotes, its scope, and its public promises. This repository is maintained as a public open-source project, even when its visibility is temporarily private. Treat every tracked file, generated artifact, commit message, issue, and example as publishable. Use generic examples and public project URLs; exclude credentials, signing material, personal or professional identifiers, machine-specific paths, private endpoints, and internal-only context. Inspect the staged diff for this material before every commit.

## Project Structure & Module Organization

`Sources/ViMotesCore/` contains the AppKit-independent Vim state machine and recovery policies. Keep deterministic input-to-action behavior here. `Sources/ViMotes/` contains the macOS menu bar app, Accessibility checks, event tap, mode indicators, persisted settings, and native action execution. Core tests live in `Tests/ViMotesCoreTests/`; application tests live in `Tests/ViMotesTests/`. `App/Info.plist` defines the application bundle, while `scripts/build-app.sh` creates the signed bundle under `dist/`.

## Build, Test, and Development Commands

- `swift build` compiles a debug build of all package targets.
- `swift test` runs the complete Swift Testing suite.
- `./scripts/build-app.sh` creates a release build, assembles `dist/ViMotes.app`, and signs it with an available Apple Development identity or an ad hoc fallback.
- `open dist/ViMotes.app` launches the packaged app for manual testing in Apple Notes.

Development requires macOS 13 or newer and Swift 6.2. Grant the built app Accessibility permission before testing keyboard interception.

## Coding Style & Naming Conventions

Use two-space indentation and follow the formatting already present in `Sources/` and `Tests/`. Name types in `UpperCamelCase`, methods and properties in `lowerCamelCase`, and enum cases after the action they represent. Keep Vim semantics and state transitions in `ViMotesCore`; isolate AppKit, Accessibility, and `CGEvent` side effects in `ViMotes`. Prefer small, explicit value types and exhaustive switches. Do not add comments; make names and structure communicate intent.

## Testing Guidelines

Tests use Swift Testing (`import Testing`, `@Test`, and `#expect`). Name test files `<Subject>Tests.swift`, test structs `<Subject>Tests`, and methods after observable behavior, such as `retriesAfterPermissionGrant`. Cover new mode transitions, command mappings, recovery cases, and persisted preferences. There is no declared coverage threshold, but `swift test` must pass before review. Manually verify UI and event-tap changes in Apple Notes.

## Commit & Pull Request Guidelines

History follows Conventional Commit prefixes: `feat:`, `fix:`, and `chore:`. Use a short, imperative subject and keep each commit focused. Pull requests should explain user-visible behavior, link relevant issues, report `swift test` results, and describe manual Apple Notes validation. Include screenshots for menu or mode-indicator changes and call out any Accessibility or signing impact.

## Security & Repository Configuration

Never commit certificates, signing identities, or local permission data. Use `VIMOTES_CODESIGN_IDENTITY` only as a local environment override.
