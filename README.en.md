# NoSleepMenu

A macOS menu-bar app for sleep prevention and weekly Codex / Claude allowance.

[한국어](README.md) · [Downloads](https://github.com/weavermensch92/NoSleepMenu/releases) · [MIT](LICENSE)

![Settings](docs/settings-en.png)

## Features

- **One menu-bar item** containing `Codex remaining % → ChatGPT logo → Claude remaining % → Claude logo`. Both values move together.
- Korean, English, or system language; apply changes immediately in Settings.
- Provider visibility, a custom Codex executable path, and optional launch at login.
- Idle and lid sleep prevention; optional Sunshine display compatibility and lid-close dimming/muting.
- Right-aligned switches. No personal remote tunnel, gesture server, web server, or Moonlight fork.

## Install

Requires macOS 13+ on Apple silicon or Intel. Release builds contain both architectures.

Download a DMG or PKG from [Releases](https://github.com/weavermensch92/NoSleepMenu/releases).
Quit an existing copy first. Drag the app from the DMG into Applications, or use
the PKG to install `/Applications/NoSleepMenu.app`. Open it and choose **Settings…**.
Installation does not change power settings or enable launch at login. Enable login
launch only after moving the app to its final location; toggle it off/on after moving it.

**Initial v1.0.0 artifacts have an ad-hoc signed app, an unsigned PKG, and no Apple
notarization.** A Developer ID distribution certificate was not available. Verify
the source and `SHA256SUMS`, then use macOS's per-app approval flow or build from source.
No global security changes are needed.

## Accounts and usage

**Codex:** sign in to Codex CLI or the desktop app with a ChatGPT account. The app
calls [Codex App Server](https://developers.openai.com/codex/app-server)
`account/rateLimits/read` every minute, preferring the `codex` bucket and a 10,080-minute
window. Remaining means `100 - usedPercent`. This is Codex allowance, not ChatGPT
conversation allowance. It never requests a model turn. Common application and CLI
locations are detected; Settings accepts a custom absolute executable path.

**Claude:** sign in to Claude Code with a subscription account using its standard
macOS Keychain storage. The app reads the existing `Claude Code-credentials` entry
and polls `https://api.anthropic.com/api/oauth/usage` every five minutes. It displays
`100 - seven_day.utilization`, the all-model weekly allowance. It does not display
five-hour or model-specific limits. This is an internal endpoint and may change.
Custom Keychain service names / `CLAUDE_CONFIG_DIR` credential profiles are not supported.
The app neither refreshes nor separately stores tokens. If authentication expires,
run `/usage` in Claude Code, then **Refresh status** in NoSleepMenu. If needed, log in
again through Claude Code first.

Errors and missing quotas display `—%` with a reason in the menu. Missing credentials
never prevent the sleep controls from working.

Official template logos are loaded from installed vendor desktop apps. They are
**not distributed in the source or packages**. Provider names are the fallback.
The app and its MIT license do not grant rights to vendor trademarks.

## Power behavior

Sleep prevention uses IOKit assertions and `pmset -a disablesleep`; changing the
system setting prompts for administrator authentication. **The system setting can
remain after quitting the app.** Turn sleep prevention OFF before quitting or
uninstalling. To recover manually, run `sudo pmset -a disablesleep 0`.

Sunshine compatibility changes only display assertions; it does not manage Sunshine
services or open network ports. Lid features need suitable hardware. Optional
brightness, display and media controls use dynamically discovered private macOS
APIs and may be unavailable or change between releases. Unsupported controls are
skipped. Closed-lid operation is not guaranteed on every Mac. This app does not
prevent logout or WindowServer crashes.

## Privacy and portability

No credentials, private addresses, personal paths, conversations, logs, or bundled
remote-control tools are included. Preferences use `io.github.nosleepmenu.NoSleepMenu`.
Only power-related preferences can migrate from the older local version. Launch at
login creates a per-user LaunchAgent using the app's actual installation path.
NoSleepMenu has no telemetry service; usage requests go directly to each provider.
See [third-party notices](THIRD_PARTY_NOTICES.md).

## Build

Swift 6+ and a macOS SDK are required. Tests require full Xcode 16+ with XCTest.
If Command Line Tools are selected globally, set `DEVELOPER_DIR` for the test command only.

```sh
git clone https://github.com/weavermensch92/NoSleepMenu.git
cd NoSleepMenu
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash Scripts/build-app.sh
open build/NoSleepMenu.app
bash Scripts/package.sh
```

The scripts build arm64 and x86_64 separately, combine them with `lipo`, and produce
DMG / PKG / SHA256SUMS in `dist/`. Use `NOSLEEPMENU_ARCHS=arm64` for a local single-CPU
build; do not label that artifact universal. Set `NOSLEEPMENU_BUILD_CACHE` to override
the default `~/Library/Caches/NoSleepMenu-release` cache.

Release maintainers can set `DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_INSTALLER`, and
`NOTARY_PROFILE` to sign and notarize with their own credentials. Never commit these
credentials. CI runs offline tests and builds universal packages.

## Uninstall

Disable sleep prevention and launch at login, quit, and move the app to Trash.
Optionally remove preferences with `defaults delete io.github.nosleepmenu.NoSleepMenu`.

## Contribute

Use `Sources/NoSleepMenu/Localization.swift` for translations. Add matching settings
choices and tests for new languages. Run tests and check both menus and Settings before
submitting changes. The public source scan is `bash Scripts/check-public-source.sh`.

MIT license; independent of OpenAI, Anthropic, and Sunshine.
