# RustGit

RustGit is a git client built the same way as [RustDesk](https://github.com/rustdesk/rustdesk):
a **Rust** core with a **Flutter** UI on top.

- `core/` — Rust library (`rustgit-core`) that will hold the git logic.
- `flutter/` — Flutter application (the UI). Right now it just shows a
  "Welcome to RustGit" screen; this is the starting point for the real client.

## Prerequisites (Windows 11)

1. **Rust** — install via [rustup](https://rustup.rs):
   ```powershell
   winget install Rustlang.Rustup
   ```
2. **Flutter SDK** — install via [flutter.dev](https://docs.flutter.dev/get-started/install/windows)
   or with [Scoop](https://scoop.sh):
   ```powershell
   scoop bucket add extras
   scoop install flutter
   ```
   (There is no official `Flutter.Flutter` winget package — Scoop's `extras`
   bucket is the simplest package-manager route on Windows.)

   Then verify your setup:
   ```powershell
   flutter doctor
   ```
   Make sure the **Windows desktop** toolchain requirements are satisfied
   (Visual Studio 2022 with the "Desktop development with C++" workload).
3. Enable Windows desktop support for Flutter (only needed once):
   ```powershell
   flutter config --enable-windows-desktop
   ```

## First-time setup

The `flutter/` folder contains the Dart source (`pubspec.yaml`, `lib/main.dart`)
but not the generated native platform folders (they aren't checked into the
repo). Generate them once with:

```powershell
cd flutter
flutter create --platforms=windows .
```

This will add a `windows/` folder (and others if you ask for them) without
touching the existing `lib/main.dart`.

## Running the app

```powershell
cd flutter
flutter pub get
flutter run -d windows
```

This opens a desktop window that says **"Welcome to RustGit"**.

## Running the built app (after `flutter build`)

`flutter run` compiles and launches the app in one step. To instead build a
release binary and run it separately:

```powershell
cd flutter
flutter build windows
```

The compiled executable is placed at:

```
flutter\build\windows\x64\runner\Release\rustgit.exe
```

Launch it directly, e.g.:

```powershell
.\build\windows\x64\runner\Release\rustgit.exe
```

or double-click it in File Explorer. The `Release` folder also contains the
`.dll` files the app needs, so keep `rustgit.exe` in that folder (or copy the
whole folder) rather than moving the `.exe` alone.

## Building the Rust core

The Rust core builds independently of the UI:

```powershell
cargo build
```

Run its tests with:

```powershell
cargo test
```

## Local database

RustGit stores its local state (known repos, app settings) in **SQLite**,
accessed through [`sqlx`](https://github.com/launchbadge/sqlx) — the same
combination RustDesk's server uses for its own persistence. This keeps the
door open to later pointing at Postgres/MySQL for a hosted/sync scenario,
since `sqlx` supports all three with the same query API.

- `core/src/db.rs` — the `Database` type (connect, migrate, CRUD for repos
  and settings).
- `core/migrations/` — SQL migration files, run automatically on connect
  via `sqlx::migrate!`.

No `DATABASE_URL` or `sqlx-cli` setup is required to build: the code uses
runtime `sqlx::query(...)` calls rather than the compile-time-checked
`sqlx::query!` macro, so `cargo build`/`cargo test` work offline.

## Project layout

```
rustgit/
├── Cargo.toml          # Rust workspace
├── core/                # Rust core library (rustgit-core)
│   ├── migrations/      # sqlx SQL migrations
│   └── src/
│       ├── lib.rs
│       └── db.rs        # SQLite storage layer (sqlx)
└── flutter/             # Flutter UI application
    ├── pubspec.yaml
    └── lib/main.dart
```

## Roadmap

Once the core and UI are wired together (e.g. via
[`flutter_rust_bridge`](https://github.com/fzyzcjy/flutter_rust_bridge), the
same way RustDesk bridges its Rust core into Flutter), `core/` will grow to
implement the actual git client logic, and the UI in `flutter/` will call
into it.
