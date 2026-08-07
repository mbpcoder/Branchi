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
   or:
   ```powershell
   winget install Flutter.Flutter
   ```
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

## Building the Rust core

The Rust core builds independently of the UI:

```powershell
cargo build
```

Run its tests with:

```powershell
cargo test
```

## Project layout

```
rustgit/
├── Cargo.toml          # Rust workspace
├── core/                # Rust core library (rustgit-core)
│   └── src/lib.rs
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
