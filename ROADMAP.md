# ClawdPal Roadmap

## Product Direction

ClawdPal is an AI coding agent work companion, not a generic desktop pet and not a heavy agent console. Its job is to make local Claude Code and Codex activity visible, calm, and easy to return to.

The first user is Ryan. Public distribution, notarization, auto-update, and polished onboarding come later.

## Phase 0: MVP Cleanup

- Remove unstable edge snapping.
- Keep drag, position memory, reset position, and right-click quit.
- Keep the current bridge and hook installer stable.
- Keep `swift build` and Xcode-toolchain tests green.

## Phase 1: Ryan Daily Driver

- Support Claude and Codex hooks in the same app.
- Keep Codex hook installation compatible with existing vibe-island hooks.
- Show source, last event, working directory, and session id in the small panel.
- Build a local `.app` bundle for double-click startup.
- Keep all hook behavior fail-open.

## Phase 2: Session Awareness

- Scan Claude transcripts and Codex session index files.
- Identify recent active sessions.
- Show a compact recent-session list in the panel.
- Upgrade Jump Back from activating a terminal app to choosing the likely matching terminal/workspace.
- Return to idle after long periods without events.

## Phase 3: Expression

- Add subtle animations for idle, thinking, running, editing, and done.
- Improve short bubble copy while keeping it concise.
- Add quiet mode for lower visual noise.
- Support a local skin/resource directory for replacing pet artwork.

## Phase 4: Small Shareable Build

- Package a release zip or DMG.
- Add first-run guidance.
- Add hook install status checks.
- Add exportable diagnostics logs.
- Document privacy clearly: all events are processed locally.
- Consider signing, notarization, and auto-update only after the Ryan-first workflow is stable.

## Non-Goals For Now

- No server.
- No telemetry.
- No approval/deny control surface for agent permissions.
- No public distribution polish.
- No edge snapping unless the window interaction layer is intentionally rebuilt.
