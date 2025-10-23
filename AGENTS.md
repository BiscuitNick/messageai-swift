# Repository Guidelines

## Project Structure & Module Organization
- `messageai-swift/`: SwiftUI app; views (`ChatView.swift`, `ProfileView.swift`), shared models in `Models.swift`, and Firebase services inside `Services/`. Group features by folder and colocate view models with their views.
- `messageai-swiftTests/` and `messageai-swiftUITests/`: XCTest targets for entities, services, and UI flows. Mirror production filenames and drop a `SUMMARY.md` at each updated folder’s root describing the change set.
- `functions/`: Firebase Functions in TypeScript (`src/index.ts` → `lib/`) targeting Node 20. Keep generated artifacts ignored and refresh Firebase config files at the repo root whenever backend behavior changes.

## Build, Test, and Development Commands
- `xcodebuild -scheme messageai-swift -destination 'platform=iOS Simulator,name=iPhone 15' build`: SwiftUI app build plus warnings.
- `xcodebuild test -scheme messageai-swift -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`: XCTest suite for `messageai-swiftTests`.
- `cd functions && npm install`: Install Firebase backend deps (Node 20).
- `cd functions && npm run lint && npm run build`: ESLint + TypeScript compile to `lib/`.
- `cd functions && npm run serve`: Firebase emulators after a clean build.

## Coding Style & Naming Conventions
- Swift: 4-space indent, API design guidelines, PascalCase types, camelCase members, async methods suffixed `Async`. Prefer `final` services, inject dependencies through initializers, and keep `@Model` SwiftData entities in `Models.swift` with persistence logic in services.
- TypeScript: Run ESLint/Prettier via `npm run lint`, keep modules in `src/` exporting named handlers, use camelCase for functions, and ALL_CAPS for env keys.

- Add XCTest suites beside related code and name classes `<Feature>Tests`. Reuse `TestFixtures` for deterministic SwiftData and Firestore mocks, and extend `messageai-swiftUITests` when UI changes warrant assertions or snapshots. Update each touched test folder’s `SUMMARY.md` with new cases and data builders.
- For Functions, cover critical handlers with `firebase-functions-test` suites and run them before emulator sessions or deploys.

## Commit & Pull Request Guidelines
- Match the numbered history (`3.1 - add typing indicator fixes`), keeping commits scoped and imperative.
- PRs need a concise summary, test notes (`xcodebuild test`, emulator findings), links to tasks/issues, and simulator screenshots for UI tweaks. Highlight Firebase rules or indexes and loop in both iOS and backend reviewers when relevant.

## Security & Configuration Tips
- Keep secrets out of git; manage `GoogleService-Info.plist` through Xcode, load Functions config via `.env` per `API_KEY_SETUP.md`, and strip device tokens from shared logs.
- After editing rules or indexes, run `firebase emulators:start --only firestore,functions` to validate access control before pushing.
