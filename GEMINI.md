# Mistia Project Context

## Project Overview
Mistia is a family finance management application. It provides tools for tracking transactions, planning budgets, and managing family-shared finances. The project consists of a native Apple platform application (SwiftUI/SwiftData) and a Supabase-based backend.

### Main Technologies
- **Frontend:** SwiftUI, SwiftData (for local persistence and offline support).
- **Backend:** Supabase (PostgreSQL, Auth, Edge Functions).
- **Authentication:** Supabase Auth with Google Sign-In integration.
- **Synchronization:** Custom sync engine between SwiftData and Supabase.
- **Core Logic:** A Swift Package (`MistiaCoreLogic`) containing platform-independent business logic.

## Project Structure
- `Mistia/`: The main application source code.
    - `App/`: App entry point, main views, and app-level state management.
    - `Shared/`: Core logic, models, persistence, and sync implementation.
    - `Features/`: Feature-specific views and logic (Transactions, Planning, Family, etc.).
- `MistiaCoreLogic/` (defined in `Package.swift`): Targets `Mistia/Shared` to provide a library for business logic.
- `supabase/`: Backend configuration, database migrations, and edge functions.
- `web/`: Web-based components, such as family invite pages.
- `MistiaTests/` & `Tests/`: Unit and integration tests for the app and core logic.

## Building and Running
### iOS/macOS App
- Open `Mistia.xcodeproj` in Xcode.
- Ensure dependencies are resolved via Swift Package Manager.
- Select the appropriate scheme (e.g., `Mistia`) and run on a simulator or device.

### Core Logic & Tests
- Use Swift CLI for library-specific tasks:
  ```bash
  swift build
  swift test
  ```

### Backend (Supabase)
- The backend is managed via the Supabase CLI.
- Migrations are located in `supabase/migrations`.
- To start local development (if Supabase CLI is installed):
  ```bash
  supabase start
  ```

## Development Conventions
- **Persistence:** Use SwiftData models located in `Mistia/Shared/Persistence`.
- **Sync Logic:** Synchronization logic is primarily handled in `MistiaSyncCoordinator` and related classes in `Mistia/Shared/Sync`.
- **Localization:** Localizable strings are managed in `Localizable.xcstrings`.
- **Architecture:** The project follows a modular approach with core logic separated from the UI.
- **Testing:** New features should include tests in `MistiaTests` or the SPM-based `Tests` directory.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tools** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them. `codegraph_node` returns one symbol's source + callers, or reads a whole file with line numbers. If the tools are listed but deferred, load them by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` and `codegraph node <symbol-or-file>` print the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
