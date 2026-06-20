# Blink Release Scripts

This folder contains release orchestration scripts for Blink.

## Desktop Downloads

Use `build-desktop-downloads.sh` to build Blink Desktop packages, copy stable release files into the website downloads folder, generate checksums/manifest metadata, and update the Homebrew cask used by the macOS Method A flow.

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform current
```

Run commands from the BLINK repository root:

```bash
cd /Users/jesseoyofodan/Development/Projects/Digitwhale/BLINK
```

## Common Commands

Build for the current machine and publish local artifacts:

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform current
```

Build macOS DMGs for the Homebrew cask flow:

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform mac
```

Build Windows installer artifacts on a Windows runner:

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform windows --no-cask
```

Build Linux artifacts on a Linux runner:

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform linux --no-cask
```

Collect already-built artifacts without running Tauri again:

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform all --skip-build --copy-existing
```

## Output

Artifacts are copied to:

```text
digitwhale_blink/public/downloads/
```

Stable public filenames:

```text
blink-aarch64.dmg
blink-x64.dmg
blink-setup.exe
blink-x64.msi
blink.deb
blink.AppImage
manifest.json
SHA256SUMS
```

The website deploy should include `digitwhale_blink/public/downloads/` so these files resolve under:

```text
https://blink.digitwhale.com/downloads/
```

## Homebrew Tap

The script updates:

```text
digitwhale_blink_desktop/Casks/blink.rb
```

It sets the cask version from `digitwhale_blink/src-tauri/tauri.conf.json` and points the cask to:

```text
https://blink.digitwhale.com/downloads/blink-#{arch}.dmg
```

Use `--no-cask` for non-mac runners or when you only want to collect artifacts.

## Options

```text
--platform current|mac|windows|linux|all
--skip-build
--copy-existing
--no-cask
--continue-on-error
--dry-run
-h, --help
```

## Environment Overrides

```bash
BLINK_APP_DIR=/path/to/digitwhale_blink
BLINK_TAP_DIR=/path/to/digitwhale_blink_desktop
BLINK_DOWNLOADS_DIR=/path/to/public/downloads
BLINK_DOWNLOAD_BASE_URL=https://blink.digitwhale.com/downloads
```

Example:

```bash
BLINK_DOWNLOAD_BASE_URL=https://cdn.example.com/blink \
  digitwhale_blink_script/build-desktop-downloads.sh --platform current
```

## CI Notes

Tauri desktop packages should be built on native platform runners:

```text
macOS runner   -> digitwhale_blink_script/build-desktop-downloads.sh --platform mac
Windows runner -> digitwhale_blink_script/build-desktop-downloads.sh --platform windows --no-cask
Linux runner   -> digitwhale_blink_script/build-desktop-downloads.sh --platform linux --no-cask
```

After CI uploads or merges artifacts, run the collection mode to regenerate the manifest and checksums:

```bash
digitwhale_blink_script/build-desktop-downloads.sh --platform all --skip-build --copy-existing
```
