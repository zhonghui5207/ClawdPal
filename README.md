# ClawdPet

ClawdPet is a native macOS floating pet companion for local AI coding agents.

The first version focuses on Claude Code hook events:

1. `ClawdPetHooks` reads hook JSON from stdin.
2. The hook CLI forwards normalized events to a local Unix socket.
3. `ClawdPetApp` receives events and maps them to one of six Clawd states.
4. A transparent floating window renders the current Clawd and a small status bubble.

This project intentionally reimplements the bridge shape instead of copying GPL code from related projects.

## Run

```sh
swift run ClawdPetApp
```

In another terminal:

```sh
echo '{"hook_event_name":"PreToolUse","tool_name":"Edit","session_id":"demo"}' | swift run ClawdPetHooks
```

Install global Claude Code hooks after building:

```sh
swift build
swift run ClawdPetSetup install-claude
```

Remove them later:

```sh
swift run ClawdPetSetup uninstall-claude
```

If `swift test` cannot find the local test framework while `xcode-select` points at CommandLineTools, run tests through the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Current MVP Scope

- Floating transparent AppKit window
- Six sprite states from the provided sprite sheet
- Claude Code hook JSON decoder
- Unix socket bridge
- Hook CLI fail-open behavior
- Focused unit tests for mood mapping and decoder behavior
