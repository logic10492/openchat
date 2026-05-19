# OpenChat Quality Plan Execution Context

Date: 2026-05-01
Branch: openchat-quality-plan-implementation
Source request: read `docs/superpowers/plans/openchat_quality_plan_package/00_overview_总览.md` and `03_roadmap_改进路线图.md`, then complete quality improvement work while preserving arch-src-test consistency and running propagation-audit.

## Required Constraints

- Follow `AGENTS.md`: App -> Features -> Core -> Shared, SwiftUI + @Observable, async/await, GRDB migrations append-only, no signing changes.
- Keep source, tests, and arch/docs aligned for any implemented behavior.
- Run verification and write honest blockers if simulator/tooling prevents a full run.
- Run post-change propagation audit/writeback under `arch/AntiEntropy` and `harness/YYYY.MM.DD`.

## Plan Package Evidence

- P0 from `03_roadmap_改进路线图.md`: Keychain API key storage, visible save/model errors, stream cancel DB/UI consistency, explicit `memory_embedding` cleanup, embedding resource test gating, live container failure page.
- `04_task_packages_实施任务包.md` maps these to TP-01 through TP-05 plus live startup failure from overview/F-03.
- `05_testing_acceptance_测试与验收计划.md` requires targeted tests for API key storage, save failure visibility, stream cancellation, sqlite-vec cleanup, and resource gating.
- `06_security_privacy_安全隐私加固.md` requires DB/export/log/error surfaces not expose API keys.

## Current Baseline Observed Before Edits

- `git status --short --branch`: on `main`, only untracked `docs/superpowers/plans/openchat_quality_plan_package/`; switched to branch `openchat-quality-plan-implementation`.
- `OpenChat/Core/Database/Migrations.swift` latest migration is `v12_add_compression_mode_to_conversation`.
- `APIEndpointRecord` still has compatibility field `apiKey`.
- `APIEndpointEditorView` uses plain `TextField` and saves with `try?` then dismiss.
- `ChatViewModel+Support.generateResponse` saves assistant only on normal completion; catch removes only empty placeholder and does not persist non-empty partial content.
- `DatabaseManager.eraseAllData` deletes `memory_entry` via cascade but does not delete sqlite-vec `memory_embedding`.
- `EmbeddingServiceTests` directly requires bundled model/tokenizer with `#require`, so missing resources fail ordinary tests.
- `OpenChatApp` uses `(try? DependencyContainer.live()) ?? DependencyContainer.preview()`, which can hide real database startup failure.

## Intended Implementation Scope

1. Add Core secrets abstraction (`APIKeyStore`, Keychain production store, in-memory test store).
2. Wire `DependencyContainer`, `APIEndpointEditorViewModel`, `SettingsView`, `ChatViewModel`, and `MemoryManager` so API configs read keys from the key store while SQLite stores no new plaintext keys.
3. Replace endpoint save `try?` flow with visible error state and `SecureField`; do not dismiss on failure.
4. Persist non-empty assistant partial content on cancellation/failure and always clear generation state with `defer`.
5. Explicitly clear `memory_embedding` in `eraseAllData`; preserve existing `VectorStore` delete path.
6. Skip real embedding resource tests when model/tokenizer files are absent.
7. Replace silent live-container fallback with a startup error view.
8. Add focused tests and update arch/plan/harness evidence.

## Verification Targets

- Targeted xcodebuild tests for changed areas if simulator is available.
- `ruby scripts/generate_xcodeproj.rb` only if new files are not picked up by generated project or project diff is expected.
- Static scans for stale P0 claims and triangle consistency.
- Propagation audit: OpenChat repo uses `arch/AntiEntropy/propagation-audit.md` / `triangle-consistency.md` rather than Magnum `arch/propagation-audit`; record graph/tooling status honestly.
