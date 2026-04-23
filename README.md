# ClawdPet

ClawdPet is a native macOS floating pet companion for local AI coding agents.

It is currently a Ryan-first MVP for showing Claude Code and Codex activity as a small transparent desktop pet. All events stay local. The app does not upload telemetry or agent data.

## What It Does

- Shows a transparent floating Clawd on the desktop.
- Maps agent activity to six transparent PNG states:
  - classic: idle
  - hoodie: thinking / permission request
  - explorer: reading / searching
  - street: running commands / errors
  - suit: editing code
  - pajama: done
- Receives Claude Code and Codex hook events through a local Unix socket.
- Keeps hooks fail-open so agent work is not blocked when ClawdPet is closed.
- Remembers floating window position and supports reset/quit through the right-click menu.

## Development Run

```sh
swift run ClawdPetApp
```

In another terminal, send a Claude-style test event:

```sh
echo '{"hook_event_name":"PreToolUse","tool_name":"Edit","session_id":"demo","tool_input":{"file_path":"Sources/App.swift"}}' | swift run ClawdPetHooks --source claude
```

Send a Codex-style test event:

```sh
echo '{"hook_event_name":"UserPromptSubmit","session_id":"demo","cwd":"/tmp/project","prompt":"continue implementation"}' | swift run ClawdPetHooks --source codex
```

## Install Hooks

Install both Claude and Codex hooks:

```sh
swift build
swift run ClawdPetSetup install-all
```

Install only one agent:

```sh
swift run ClawdPetSetup install-claude
swift run ClawdPetSetup install-codex
```

Remove hooks:

```sh
swift run ClawdPetSetup uninstall-all
```

The setup tool backs up existing settings before writing. Uninstall only removes hooks whose command contains `ClawdPetHooks`, so existing tools such as vibe-island remain intact.

## Local App Bundle

Build a local double-clickable app:

```sh
scripts/build-app.sh
open .build/ClawdPet.app
```

The local app bundle includes:

- `ClawdPetApp`
- `ClawdPetHooks`
- `ClawdPetSetup`
- Clawd PNG resources

This is an unsigned local app bundle for personal use. It is not notarized and does not include auto-update.

## Tests

```sh
swift build
```

If `swift test` cannot find the local test framework while `xcode-select` points at CommandLineTools, run tests through the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Current Scope

- Native SwiftUI + AppKit floating window
- Claude Code hook decoder and installer
- Codex hook decoder and installer
- Unix socket bridge
- Local `.app` builder
- Focused unit tests for hook decoding, settings merge/uninstall, and bridge envelope encoding

See [ROADMAP.md](ROADMAP.md) for the longer-term plan.
