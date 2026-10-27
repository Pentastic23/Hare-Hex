# Launcher and releases

Testers run **HareHex-Launcher.exe**. Each time it starts it asks GitHub for the newest release of
`Pentastic23/Hare-Hex`, installs it if it differs from what they have, and starts the game.

## For testers

1. Download `HareHex-Launcher.exe` from any release on https://github.com/Pentastic23/Hare-Hex/releases
   and put it in a folder of its own (e.g. `Documents\Hare&Hex`).
2. Run it. The first time it downloads the game (about 70 MB) into a `game` folder beside it.
3. From then on, start the game with the launcher. It updates when there is a new version and
   starts the game after 3 seconds (untick "Start the game automatically" to read the notes first;
   any click or key also stops the countdown).

Saves are in `%APPDATA%\Godot\app_userdata\Hare&Hex`, not in the game folder, so updates keep them.
Windows SmartScreen may warn about an unsigned exe the first time ("More info" > "Run anyway").

## For you: releasing a version

**From the launcher:** on your PC the launcher has a **RELEASE** button in its header. Type the
version (it suggests the next one) and the notes, then press RELEASE. The first press says what will
happen (uncommitted files, commits to push); press CONFIRM to publish. **Dry run** builds without
uploading. The log shows the script's output; when it's done the launcher installs the new version
itself, like a tester's would. Don't close the launcher while it runs.

The button shows when the launcher knows your project folder: it finds it by itself when run from
`build\` or the editor, and otherwise remembers the one you pick with **Ctrl+Shift+D** (saved as
`project_dir` in `%APPDATA%\Godot\app_userdata\Hare&Hex Launcher\launcher.cfg`). Testers have no
project folder, so they never see it. The panel (`launcher/release_panel.gd`) runs the same
`tools/release.ps1` as below, with `-Yes` and the notes in a file; it passes
`-ExecutionPolicy Bypass` for that one PowerShell process, since Windows blocks scripts by default.
`launcher/tools/release_panel_check.tscn -- <out folder> 0.1.3` drives it through a dry run.

**From PowerShell:**

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1 -Version 0.1.4 -Notes "What changed"
```

It sets the version in `export_presets.cfg`, exports the game (`build\windows\Hare&Hex.exe`) and
the launcher (`build\HareHex-Launcher.exe`), zips the game as `build\HareHex-windows.zip`, creates
the release `v0.1.4` as a draft on the current commit, uploads both files and publishes it. Publishing
also posts to Discord (`.github/workflows/release-discord.yml`). Without `-Notes`, GitHub writes the
notes from the commits. Options: `-DryRun` (build and zip only), `-Full` (a full release instead of a
pre-release; the launcher takes either), `-SkipLauncher`, `-Godot <path>`.

It asks before releasing with uncommitted changes and pushes the branch if GitHub doesn't have
the commit yet.

**Token (once):** make a fine-grained token at https://github.com/settings/personal-access-tokens/new
with access to only this repository and "Contents: Read and write", then put it in
`release_token.txt` at the project root (git-ignored) or in the `GITHUB_TOKEN` environment variable.

Windows blocks scripts by default on this PC, hence `-ExecutionPolicy Bypass` above (it applies to
that one PowerShell process only). Or use the launcher's release panel.

## How the launcher works (`launcher/`)

A separate Godot project (Godot skips a folder with its own `project.godot`, so the game's export
never includes it). `launcher.gd` does everything:

- `GET https://api.github.com/repos/Pentastic23/Hare-Hex/releases` (no token: the repo is public,
  60 checks an hour per IP). Picks the newest non-draft release with an asset named exactly
  `HareHex-windows.zip`; releases without one (the older source zips) are skipped.
- Installed when the release tag **and** the asset id match `game/installed.json`; otherwise it
  downloads to `game/download.part`, checks the size and the SHA-256 that GitHub lists for the asset,
  unpacks into `game/<tag>.tmp`, renames it to `game/<tag>`, writes `installed.json` and removes the
  older version folders (each holds a `.hare_hex_version` marker; one still in use goes next time).
  Deleting a bad release on GitHub rolls testers back to the one before it.
- The game folder is `game/` beside the launcher, or the launcher's user folder
  (`app_userdata/Hare&Hex Launcher/game`) when that can't be written or when run from the editor.
- Offline, rate-limited or a failed download: it says so and still lets them play what they have.
- Command line (after `--`): `--releases-url URL` (a test feed), `--install-dir DIR`.
- `launcher/tools/launcher_shots.tscn -- out.png 2 [launcher args]` saves a picture of it (needs a
  window; excluded from the export).

The launcher doesn't update itself: when `launcher.gd` changes, testers download the new
`HareHex-Launcher.exe` from the release by hand.
