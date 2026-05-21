# OpenChat

OpenChat is an iOS role-playing chat client for OpenAI-compatible APIs. It is built for character-card based conversations, world-book recall, long-running role-play context, and local-first experimentation with small or self-hosted models.

The app is written in SwiftUI and uses native Swift Concurrency, SQLite via GRDB, URLSession streaming, and a small CoreML embedding model for semantic memory and world-book retrieval.

## Features

- OpenAI-compatible Chat Completions and Responses API modes
- Multiple API endpoints and per-conversation model parameters
- Character cards with persona, scenario, example dialog, import, and export support
- World books with keyword and semantic recall
- Streaming chat UI with markdown rendering and visible reasoning/thinking support
- Persistent conversation history in SQLite
- Context management with truncation and checkpoint-style compression
- Cross-conversation character memory with vector retrieval
- Stage mode for multi-character scenes, speaker metadata, and user-controlled response order
- Background source tooling for memory, world-book, and conversation-state context packets

## Requirements

- macOS with Xcode 17 or newer
- iOS 17 or newer
- Swift 6 toolchain from Xcode
- An OpenAI-compatible API endpoint

The project is an Xcode project, not a Swift Package. Use `xcodebuild` or open `OpenChat.xcodeproj` in Xcode.

## Repository Setup

Clone with submodules:

```bash
git clone --recurse-submodules git@github.com:logic10492/openchat.git
cd openchat
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

`OpenChat/Resources/Models` is a submodule that contains the local embedding model assets used by semantic memory and world-book retrieval. The app can still be inspected without those assets, but model-backed embedding tests and semantic recall need the submodule present.

## Build

Open the project:

```bash
open OpenChat.xcodeproj
```

Or build from the command line:

```bash
xcodebuild \
  -project OpenChat.xcodeproj \
  -scheme OpenChat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

The exact simulator name depends on your installed Xcode runtime. Use this command to list available devices:

```bash
xcrun simctl list devices available
```

## Test

Run the unit test target:

```bash
xcodebuild test \
  -project OpenChat.xcodeproj \
  -scheme OpenChat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OpenChatTests \
  -skip-testing:OpenChatUITests
```

UI tests are under `OpenChatUITests` and can be run separately from Xcode or with `xcodebuild` when a suitable simulator is available.

## Project Structure

```text
OpenChat/
|-- App/            App entry, dependency container, global app state
|-- Core/           Database, networking, prompt engine, context, memory, stage, background
|-- Features/       Chat, character cards, world books, conversations, settings, stage UI
|-- Resources/      Assets, localization, model submodule
`-- Shared/         Shared SwiftUI components and utilities

OpenChatTests/      Swift Testing unit tests
OpenChatUITests/    UI tests
arch/               Architecture notes and implementation evidence
scripts/            Project generation and maintenance scripts
```

The architecture follows a one-way dependency rule:

```text
App -> Features -> Core -> Shared
```

Features should not directly depend on each other. Cross-feature coordination should live in the App layer or in Core services.

## API Configuration

Configure API endpoints inside the app settings. OpenChat stores endpoint metadata locally and keeps API keys outside the main SQLite database through the app's key storage layer.

Supported provider shapes include:

- OpenAI-compatible Chat Completions
- OpenAI Responses-style requests
- DeepSeek-compatible reasoning content and thinking-parameter handling
- Local servers that expose compatible `/chat/completions` APIs

## Documentation

The `arch/` folder contains implementation-oriented architecture docs:

- `arch/index.md` - project overview
- `arch/source-tree.md` - source layout
- `arch/data-model.md` - SQLite tables and records
- `arch/modules/chat.md` - chat runtime and UI
- `arch/modules/prompt-assembly.md` - prompt assembly flow
- `arch/modules/context-manager.md` - truncation and compression
- `arch/modules/memory/index.md` - character memory system
- `arch/modules/stage/index.md` - multi-character stage mode
- `arch/modules/background/index.md` - background context sources and workers
- `arch/modules/settings/index.md` - settings and endpoint management

## Notes For Contributors

- Keep SwiftUI view models on `@Observable`; do not introduce Combine-based `ObservableObject` for new app view models.
- Use Swift Concurrency (`async` / `await`, `AsyncSequence`) for asynchronous work.
- Keep database changes append-only through GRDB migrations.
- Do not edit signing settings casually. Signing values are generated by `scripts/generate_xcodeproj.rb`.
- Keep architecture docs, source, and tests in sync when changing runtime behavior.

## License

No license has been selected yet.
