# Local patches to flutter_pty 0.4.2

Vendored from pub.dev (MIT, see LICENSE) because the upstream bug below is
not fixed in any released version. The `example/` directory was removed.

1. `src/flutter_pty_win.c` `build_command`: skip `arguments[0]`. The Dart
   side passes argv with argv[0] set to the executable, and the Windows code
   also writes the executable first, so the shell received its own path as
   its first argument. PowerShell then failed with "Processing -File
   '...pwsh.exe' failed because the file does not have a '.ps1' extension".

Drop this copy and go back to the pub.dev package once upstream fixes it.
