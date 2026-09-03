# Roadmap

Current state: working MVP — users can describe an app, the AI plans and builds SwiftUI code, and the result previews on the iOS Simulator. Core loop works end-to-end.

---

## Now (Active)

### Build Reliability
- [ ] Automated build-error retry loop — when xcodebuild fails, feed errors back to Claude for self-healing (partially implemented)
- [ ] Improve error extraction from xcodebuild output (filter noise, surface actionable lines)
- [ ] Handle XcodeGen failures gracefully in the UI (show error banner, allow retry)

### Preview Pipeline
- [ ] Auto-refresh preview after code generation completes (no manual "Preview" click)
- [ ] Show build progress/spinner during xcodebuild
- [ ] Display build errors inline in the preview panel (not just chat)

### File Management
- [ ] Detect and prevent duplicate file paths (e.g., `Models/Recipe.swift` vs `models/Recipe.swift`)
- [ ] File rename/move support in the file explorer
- [ ] Syntax-highlighted code viewer in the file explorer

---

## Next

### Authentication & Accounts
- [ ] Sign in with Apple
- [ ] Sign in with Google
- [ ] Replace token-paste login with OAuth flow
- [ ] User profile / account settings screen

### Project Management
- [ ] Project versioning — snapshot and restore previous versions
- [ ] Duplicate project
- [ ] Export project as `.zip`
- [ ] Project thumbnails / screenshots on the home screen

### AI Quality
- [ ] Smarter context management — summarize large file trees instead of sending full content
- [ ] Multi-file edit planning — show a diff preview before applying changes
- [ ] Token usage tracking and display
- [ ] Support for longer conversations (context window management)
- [ ] Image input — let users paste screenshots or mockups for the AI to reference

### Code Generation
- [ ] Asset catalog support — generate colors, images, app icons from prompts
- [ ] Core Data / SwiftData model generation
- [ ] Network layer scaffolding (URLSession, async/await patterns)
- [ ] Third-party package support via SPM (add dependencies to generated projects)

---

## Later

### Collaboration
- [ ] Shared projects — invite collaborators to the same project
- [ ] Real-time presence (who's viewing/editing)
- [ ] Comment threads on generated code

### Advanced Preview
- [ ] Live simulator interaction (not just screenshots — stream the simulator display)
- [ ] Multiple device preview (iPhone, iPad side by side)
- [ ] Dark mode / light mode toggle in preview
- [ ] Accessibility preview (Dynamic Type, VoiceOver hints)

### Platform Expansion
- [ ] iPad app target generation
- [ ] macOS app target generation
- [ ] watchOS complications
- [ ] Widget extensions (WidgetKit)

### Distribution
- [ ] One-click TestFlight upload
- [ ] App Store metadata generation (description, keywords, screenshots)
- [ ] Code signing management

### Developer Experience
- [ ] Undo/redo for AI changes (per-tool-call granularity)
- [ ] Git integration — commit generated code, view diffs
- [ ] Terminal panel for running commands
- [ ] Xcode project settings editor (bundle ID, display name, capabilities)
- [ ] Custom system prompt overrides (power users)

---

## Non-Goals (for now)

- **Cross-platform (Android/web)** — iOS-first, expand later
- **Visual drag-and-drop builder** — conversational interface is the core UX
- **Self-hosted / on-prem** — cloud-first with local file execution
- **Plugin/extension system** — keep the surface area small

---

## Contributing

This is a private repo. If you're on the team:

1. Branch off `main` — use `feature/description` or `fix/description`
2. Keep PRs focused — one feature or fix per PR
3. Test the full loop: create project → chat → generate code → preview on simulator
4. If you touch the build pipeline (`XcodePreviewService`, `SimulatorPreviewService`, `ToolExecutor`), test with a fresh project AND an existing project with files on disk
