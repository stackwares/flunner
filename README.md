<div align="center">

# Flunner

### *The AI-Agent Sidekick & Native macOS Workbench for Flutter.*

[![CI](https://github.com/stackwares/flunner/actions/workflows/ci.yml/badge.svg)](https://github.com/stackwares/flunner/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/stackwares/flunner?color=2ea44f&logo=github)](https://github.com/stackwares/flunner/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-15.0%2B%20Sequoia-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.x%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<br/>

<p align="center">
  <img src="assets/screenshots/workspace-dark.png#gh-dark-mode-only" alt="Flunner Live Workspace (Dark)" width="850">
  <img src="assets/screenshots/workspace-light.png#gh-light-mode-only" alt="Flunner Live Workspace (Light)" width="850">
</p>

</div>

---

## ⚡ Overview

**Flunner** is the dedicated developer workbench and **runtime sidekick for AI coding agents** on macOS.

While your AI coding assistant (Cursor, Claude Code, Windsurf, GitHub Copilot, Roo Code, Aider, Antigravity) generates code and creates diffs, Flunner lives right alongside as your calm, hyper-responsive runtime cockpit—giving you instant hot-reloads, device orchestration, live diagnostic streams, PTY terminal tasks, and Git checkpoints with zero IDE clutter.

Agents can also connect over **Model Context Protocol (MCP)** to the *running* workbench — not a headless CLI — and inspect or drive projects, devices, sessions, logs, git, and the integrated terminal.

> **"While your AI agent writes the code, Flunner commands the runtime."**

---

## 🤖 Built for the AI Coding Era

* 🔌 **In-app MCP Server** — Cursor, Claude Code, and other MCP clients can inspect and drive the live workbench over localhost (projects, devices, runs, logs, git, and terminal). Enable it in **Settings → Agents**.
* ⚡️ **Zero-Friction Hot Reload & Restart** — Instantly test agent-generated UI and logic modifications (`r` / `R`) with sub-second response times without ever leaving your editor.
* 🪵 **High-Density Diagnostics for Prompts** — Stream structured logs with multi-level filtering (`Info`, `Error`, `Command`), regex search, and 1-click diagnostic export to feed crash dumps directly back into AI prompts.
* 🌿 **Atomic Git Checkpoints** — Built-in native Git sheet to inspect diffs, stage files, and commit agent iterations before running further prompts.
* 📱 **Multi-Device Target Orchestration** — Effortlessly launch and switch between iOS Simulators, Android Virtual Devices (AVDs), macOS Desktop, and Chrome Web targets.
* 🪶 **Calm, Ultra-Lightweight Footprint** — 100% native Swift & SwiftUI architecture with negligible RAM and CPU usage, saving your machine's full power for local LLMs, compilers, and agents.

---

## ✨ Features

- ⚡️ **Instant Runtime Control** — Trigger Hot Reload (`r`) and Hot Restart (`R`) with zero latency. Live session indicators keep you informed of compilation and process state.
- 🪵 **High-Throughput Console** — Smooth multi-line selection, real-time search, timestamp toggling, and fast filtering by log level (`Info`, `Error`, `Command`).
- 💻 **Integrated PTY Terminal** — Built-in interactive terminal tabs powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) with full interactive shell support (`zsh`, `fvm`, `bash`).
- 📱 **Device & Emulator Management** — Automatic detection and launching of iOS Simulators, Android Virtual Devices (AVDs), macOS desktop targets, and Chrome web instances via Flutter daemon.
- 🌿 **Git & Source Control Sheet** — Native source control dialog to stage files, inspect unified diffs, compose commits, switch branches, and push without leaving the workbench.
- 🛠️ **Project Maintenance & SDK Diagnostics** — One-click `flutter pub get`, `flutter clean`, integrated `flutter doctor` diagnostics viewer, and quick access to Flutter / Dart documentation.
- 🎨 **Purpose-Built Design** — Native macOS HIG adherence, custom copper/graphite workbench aesthetics, light/dark appearance support, and custom font scaling.
- 🔌 **In-app MCP Server** — While Flunner is running, AI agents can inspect and drive the live workbench over localhost (projects, devices, runs, logs, git, and terminal).

---

## 📋 Requirements

- **macOS:** 15.0 (Sequoia) or newer
- **Flutter SDK:** 3.0+ (supports standard Flutter installs and [FVM](https://fvm.app))
- **Xcode:** 16.0+ (for building from source)
- **Swift:** 5.9+

---

## 🚀 Quick Start

### Download DMG Installer (Recommended)

1. Download the latest **`Flunner.dmg`** from [GitHub Releases](https://github.com/stackwares/flunner/releases/latest).
2. Open the disk image and drag **Flunner** to your **Applications** folder.
3. Launch Flunner from Applications or Spotlight.

> **Tip:** If macOS Gatekeeper alerts you when launching an ad-hoc signed build for the first time, right-click (or Control-click) `Flunner.app` in `/Applications` and click **Open**.

---

### Install via Homebrew

Install the macOS app via Homebrew Cask:

```bash
brew install --cask stackwares/tap/flunner
```

To upgrade later:
```bash
brew upgrade --cask flunner
```

---

### Building & Running from Source

Clone the repository and run the convenience script:

```bash
# Clone the repository
git clone https://github.com/stackwares/flunner.git
cd flunner

# Build and launch in Debug mode
./script/build_and_run.sh

# Package a Release DMG installer (.dmg & .zip in dist/)
./script/build_dmg.sh
```

### Using Swift Package Manager / Xcode

You can also build directly via SwiftPM or generate the Xcode project:

```bash
# Build via Swift CLI
swift build

# Run unit and integration tests
swift test

# (Optional) Generate Xcode project using XcodeGen
xcodegen generate
open Flunner.xcodeproj
```

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘ R` | Run Project / Active Configuration |
| `r` | Hot Reload |
| `R` | Hot Restart |
| `⌘ .` | Stop Running Session |
| `⌃ \`` | Toggle Integrated Terminal Pane |
| `⌘ 2` | Open Source Control Sheet |
| `⌘ ,` | Settings |

---

## 🤖 MCP Server

Flunner exposes a localhost [Model Context Protocol](https://modelcontextprotocol.io) server while the app is running. Agents talk to the **live** workbench — not a headless CLI — so they can switch devices, run/stop sessions, read logs, and drive git/terminal.

1. Launch Flunner.
2. Open **Settings → Agents**.
3. Click **Connect Selected Agents** for Cursor, Claude Code, or Codex.
4. Enable **Keep in sync when Flunner starts** so URL and bearer token updates apply automatically after each launch.

Manual fallback: copy the JSON snippet from the same tab if you prefer to edit agent config yourself.

Example Cursor / Claude config:

```json
{
  "mcpServers": {
    "flunner": {
      "url": "http://127.0.0.1:47321/mcp",
      "headers": {
        "Authorization": "Bearer <token-from-settings>"
      }
    }
  }
}
```

The server binds `127.0.0.1` only (preferred port `47321`). Discovery is also written to `~/Library/Application Support/Flunner/mcp-server.json`. Call `get_status` first to see the current project, devices, sessions, and whether Pub Get / Clean / Run are available.

---

## 🏗️ Architecture

Flunner is built using modern native Swift and SwiftUI patterns:

- **UI Layer:** Pure SwiftUI targeting macOS 15 with strict concurrency checking enabled.
- **Terminal Engine:** Integrated PTY shell sessions using [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
- **Process Orchestration:** Robust asynchronous process runners communicating with the Flutter daemon JSON-RPC protocol over stdio.
- **Agent Interface:** An in-process localhost MCP server (Streamable HTTP) so editors can call the same workbench APIs as the UI.
- **Project Structure:** Dual-source configuration using `Package.swift` (SPM) and `project.yml` (XcodeGen).

```
Flunner/
├── Sources/
│   └── Flunner/
│       ├── Models/         # App state, devices, launch configs, daemon protocol
│       ├── Services/       # Flutter daemon, runner, Git, terminal, in-app MCP server
│       ├── Views/          # Console, terminal, sidebar, controls, settings
│       └── Design/         # Design tokens, color palette, typography
├── Tests/
│   └── FlunnerTests/       # Unit and integration test suites
└── script/                 # Build, run, and log streaming automation
```

---

## 🤝 Contributing

Contributions from the community are warmly welcomed! Please read our [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before submitting a pull request.

1. Fork the repo and create a feature branch (`git checkout -b feature/amazing-feature`)
2. Commit your changes (`git commit -m 'Add amazing feature'`)
3. Ensure all tests pass (`swift test`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

Flunner is open-source software licensed under the [MIT License](LICENSE).

---

<div align="center">
Crafted with ❤️ by <a href="https://x.com/oliverbytes">Oliver Martinez</a> & <a href="https://github.com/stackwares">Stackwares</a>
</div>
