# 10x

An AI-powered iOS app builder for macOS. Describe the app you want, and 10x generates production-quality SwiftUI code, scaffolds an Xcode project, and previews it on the iOS Simulator — all from a conversational interface. The shipped beta artifact is packaged as **10x.app**.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)

## How It Works

1. **Describe your app** — type what you want to build in natural language
2. **Plan mode** — the AI researches, asks clarifying questions, and creates a project plan
3. **Build mode** — the AI writes SwiftUI code using file tools (create, edit, search, etc.)
4. **Live preview** — the generated app is compiled and launched on the iOS Simulator with a screenshot captured back into the UI

The AI runs a full agentic tool loop client-side: it calls Claude via a thin API proxy, parses `tool_use` blocks, executes file operations locally, and loops until the task is complete.

## Architecture

```
TenXAppApp (@main)
├── AuthManager                 # Token-based auth (Supabase)
├── ContentView                 # Tab management (home + per-project tabs)
│   ├── HomeView                # Project list, creation
│   └── BuilderView            # Main workspace (3-pane)
│       ├── FileExplorerSidebar # VS Code-style file tree
│       ├── ChatPanelView       # Messages, tool steps, inline questions
│       └── PreviewPanelView    # Simulator preview, plan view
│
└── BuilderViewModel (@Observable, state machine)
    ├── GenerationService       # Claude tool loop orchestration
    │   ├── BuilderPrompts      # Mode-aware system prompts
    │   ├── BuilderToolDefs     # Tool schemas for Claude
    │   └── ToolExecutor        # File I/O, search, run_command
    ├── XcodePreviewService     # Project scaffolding (XcodeGen)
    ├── SimulatorPreviewService # Simulator boot, build, screenshot
    ├── LocalProjectStore       # Local persistence (~tenx/)
    └── BuilderService          # API client for projects/messages
```

### Key Services

| Service | Role |
|---------|------|
| **GenerationService** | Owns the Claude tool loop — streams responses, parses tool calls, executes them via ToolExecutor, repeats until done |
| **ToolExecutor** | Executes file operations (create/edit/read/delete/search) against the real filesystem and maintains an in-memory file tree |
| **XcodePreviewService** | Writes generated Swift files to disk, creates `project.yml`, runs XcodeGen to produce `.xcodeproj` |
| **SimulatorPreviewService** | Boots an iPhone simulator, runs `xcodebuild`, installs the app, launches it, captures a screenshot |
| **LocalProjectStore** | Persists messages, file tree, and project plan to `~/Library/Developer/TenXApp/{project}/tenx/` |
| **BuilderPrompts** | Generates mode-aware system prompts — plan mode focuses on research/architecture, build mode on SwiftUI code generation |

### Data Flow

```
User message → BuilderViewModel.sendMessage()
  → GenerationService.runGeneration()
    → POST to Claude proxy (streaming NDJSON)
    → Parse tool_use blocks
    → ToolExecutor writes files to disk
    → Loop until Claude stops or ask_user
  → Events update ViewModel (@Observable)
  → SwiftUI re-renders reactively
  → LocalProjectStore persists state
```

## Project Structure

```
10x-macos/
├── TenXAppApp.swift               # @main entry point
├── ContentView.swift              # Root view, tab management
├── Config.swift                   # API base URL, Supabase config
├── Theme.swift                    # Design tokens (colors, spacing, radii)
│
├── Models/
│   ├── BuilderProject.swift       # Project metadata
│   ├── BuilderStreamEvent.swift   # Stream event parsing
│   ├── ProjectMode.swift          # .plan | .build
│   └── AppTab.swift               # Tab state
│
├── ViewModels/
│   ├── AuthManager.swift          # Auth state
│   └── BuilderViewModel.swift     # Core state machine
│
├── Views/
│   ├── HomeView.swift             # Project list + creation
│   ├── BuilderView.swift          # Main 3-pane workspace
│   ├── NewProjectView.swift       # New project wizard
│   ├── FileExplorerSidebar.swift  # File tree sidebar
│   ├── Auth/LoginView.swift       # Sign-in screen
│   ├── Chat/                      # Chat panel views
│   ├── Preview/                   # Preview + plan views
│   └── Sidebar/                   # Project list sidebar
│
├── Services/
│   ├── APIClient.swift            # HTTP client (GET/POST/stream)
│   ├── BuilderService.swift       # Project/message API calls
│   ├── LocalProjectStore.swift    # Local file persistence
│   ├── XcodePreviewService.swift  # Xcode project scaffolding
│   ├── SimulatorPreviewService.swift  # Simulator control
│   └── Builder/
│       ├── GenerationService.swift     # Claude tool loop
│       ├── BuilderPrompts.swift        # System prompts
│       ├── BuilderToolDefinitions.swift # Tool schemas
│       └── ToolExecutor.swift          # File tool execution
│
└── Assets.xcassets/               # App icon, accent color
```

## Prerequisites

- **macOS 14.0+**
- **Xcode 16+** (for building the macOS app itself)
- **Xcode Simulator runtimes** — install at least one iPhone simulator via Xcode > Settings > Platforms
- **Bundled `xcodegen` binary** — copied from `10x-macos/Resources/xcodegen` into the app/CLI build products and used to generate `.xcodeproj` files for previewed apps

## Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/your-org/10x.git
   cd 10x
   ```

2. Open in Xcode:
   ```bash
   open 10x-macos.xcodeproj
   ```

3. Build and run (`Cmd+R`). The app targets macOS 14+.

4. On first launch, enter your API token on the login screen (or use "Continue without Auth" for local dev).

### Environment

The app reads config from `Config.swift` plus Xcode build settings. Public defaults are placeholders, so replace them before using hosted auth, backend, or updater flows:

| Variable | Default | Purpose |
|----------|---------|---------|
| `apiBaseURL` | `http://localhost:8000` | Backend API proxy |
| `supabaseURL` | `https://your-project-ref.supabase.co` | Supabase project URL |
| `supabaseAnonKey` | `sb_publishable_your_key` | Supabase publishable key |
| `hostedAppsBaseURL` | `https://apps.example.invalid` | Base URL for hosted app pages |
| `sparkleFeedURL` | `https://downloads.example.invalid/appcast.xml` | Sparkle appcast feed |

## Release Channels

The repo now includes a direct-download Sparkle distribution pipeline for notarized DMGs outside the Mac App Store:

- Local release tooling lives in `scripts/release/`
- CI entry workflows live in `.github/workflows/release-beta.yml` and `.github/workflows/release-stable.yml`
- The shared reusable workflow lives in `.github/workflows/release-channel.yml`
- Stable downloads publish under `https://downloads.example.invalid/stable`
- Beta downloads publish under `https://downloads.example.invalid/beta`
- The canonical Sparkle feed is `https://downloads.example.invalid/appcast.xml`
- The release workflows publish DMGs, appcasts, release notes, and channel metadata to Vercel behind `downloads.example.invalid`
- Local publish artifacts default to `build/release/published-site/`
- All builds use Apple web OAuth for Sign in with Apple, so the app does not ship the native `com.apple.developer.applesignin` entitlement

These release defaults are placeholders for the open-source repo. Replace them with your own domain, Sparkle keypair, Apple signing setup, and hosting configuration before publishing binaries.

See [docs/beta-release.md](./docs/beta-release.md) for the release commands, channel rules, and Apple credential requirements.

## CLI Evals

The repo includes eval sources plus shell wrappers for running real end-to-end evals against the existing builder stack. The wrappers make the terminal flow simpler by listing cases, resolving a usable `10x-evals` binary, and running the default smoke suite without having to remember binary paths.

Quick start:

```bash
./scripts/evals list
./scripts/evals smoke
./scripts/evals smoke --case habit_tracker_build
```

See [evals/README.md](./evals/README.md) for the current benchmark apps, binary resolution behavior, suite format, and artifact locations.

## Generated Project Layout

When a user creates an app, 10x writes files to:

```
~/Library/Developer/TenXApp/{project-slug}/
├── ios/
│   └── {TargetName}/
│       ├── App.swift
│       ├── ContentView.swift
│       ├── Views/
│       ├── Models/
│       └── ...
├── project.yml           # XcodeGen spec
├── {TargetName}.xcodeproj/  # Generated by XcodeGen
└── DerivedData/          # Local build artifacts
```

## Tech Stack

- **Swift 5.9** / **SwiftUI** — SwiftUI-first app with a small set of Swift package dependencies
- **Claude API** (via proxy) — agentic tool loop with streaming
- **XcodeGen** — generates Xcode projects from YAML specs
- **xcodebuild + simctl** — builds and previews on iOS Simulator
- **Supabase** — authentication (token-based MVP)

## License

Licensed under PolyForm Noncommercial 1.0.0. See [LICENSE](./LICENSE).
