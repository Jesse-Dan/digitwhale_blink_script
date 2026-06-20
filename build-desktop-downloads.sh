#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${BLINK_APP_DIR:-$ROOT_DIR/digitwhale_blink}"
TAP_DIR="${BLINK_TAP_DIR:-$ROOT_DIR/digitwhale_blink_desktop}"
DOWNLOADS_DIR="${BLINK_DOWNLOADS_DIR:-$APP_DIR/public/downloads}"
BASE_URL="${BLINK_DOWNLOAD_BASE_URL:-https://blink.digitwhale.com/downloads}"

PLATFORM="current"
SKIP_BUILD=0
COPY_EXISTING=0
UPDATE_CASK=1
CONTINUE_ON_ERROR=0
DRY_RUN=0

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] %q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

usage() {
  cat <<'USAGE'
Build Blink Desktop packages and copy release artifacts into the website downloads folder.

Usage:
  scripts/build-desktop-downloads.sh [options]

Options:
  --platform current|mac|windows|linux|all
      Which Tauri targets to build. "all" is meant for CI matrix runners;
      cross-platform targets still require the correct host/toolchain.
  --skip-build
      Do not run Tauri. Only collect artifacts already present in src-tauri/target.
  --copy-existing
      Copy matching existing artifacts even if a target build fails.
  --no-cask
      Do not update digitwhale_blink_desktop/Casks/blink.rb.
  --continue-on-error
      Keep attempting targets after a build failure.
  --dry-run
      Print commands without running them.
  -h, --help
      Show this help.

Environment:
  BLINK_APP_DIR              Defaults to ./digitwhale_blink
  BLINK_TAP_DIR              Defaults to ./digitwhale_blink_desktop
  BLINK_DOWNLOADS_DIR        Defaults to ./digitwhale_blink/public/downloads
  BLINK_DOWNLOAD_BASE_URL    Defaults to https://blink.digitwhale.com/downloads

Stable output names:
  blink-aarch64.dmg
  blink-x64.dmg
  blink-setup.exe
  blink-x64.msi
  blink.deb
  blink.AppImage
  manifest.json
  SHA256SUMS
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --copy-existing) COPY_EXISTING=1; shift ;;
    --no-cask) UPDATE_CASK=0; shift ;;
    --continue-on-error) CONTINUE_ON_ERROR=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -f "$APP_DIR/package.json" ]] || die "Cannot find frontend package.json at $APP_DIR"
[[ -f "$APP_DIR/src-tauri/tauri.conf.json" ]] || die "Cannot find Tauri config at $APP_DIR/src-tauri/tauri.conf.json"

VERSION="$(node -e "const fs=require('fs'); const p='$APP_DIR/src-tauri/tauri.conf.json'; console.log(JSON.parse(fs.readFileSync(p,'utf8')).version || JSON.parse(fs.readFileSync('$APP_DIR/package.json','utf8')).version || '0.0.0')")"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

case "$PLATFORM" in
  current)
    case "$(uname -s)" in
      Darwin)
        if [[ "$(uname -m)" == "arm64" ]]; then
          TARGETS=("current:mac:aarch64")
        else
          TARGETS=("current:mac:x64")
        fi
        ;;
      Linux) TARGETS=("x86_64-unknown-linux-gnu:linux:x64") ;;
      MINGW*|MSYS*|CYGWIN*) TARGETS=("x86_64-pc-windows-msvc:windows:x64") ;;
      *) die "Unsupported host platform for --platform current. Use an explicit platform." ;;
    esac
    ;;
  mac)
    TARGETS=("aarch64-apple-darwin:mac:aarch64" "x86_64-apple-darwin:mac:x64")
    ;;
  windows)
    TARGETS=("x86_64-pc-windows-msvc:windows:x64")
    ;;
  linux)
    TARGETS=("x86_64-unknown-linux-gnu:linux:x64")
    ;;
  all)
    TARGETS=(
      "aarch64-apple-darwin:mac:aarch64"
      "x86_64-apple-darwin:mac:x64"
      "x86_64-pc-windows-msvc:windows:x64"
      "x86_64-unknown-linux-gnu:linux:x64"
    )
    ;;
  *) die "Invalid platform: $PLATFORM" ;;
esac

build_target() {
  local target="$1"
  if [[ "$SKIP_BUILD" == "1" ]]; then
    return 0
  fi
  pushd "$APP_DIR" >/dev/null
  if [[ "$target" == "current" ]]; then
    log "Building current host Tauri bundle"
    run npm run desktop:build
  else
    log "Building Tauri target $target"
    run npm run desktop:build -- --target "$target"
  fi
  popd >/dev/null
}

latest_file() {
  local target="$1" pattern="$2"
  local base="$APP_DIR/src-tauri/target"
  if [[ "$target" != "current" && -d "$base/$target" ]]; then
    find "$base/$target" -type f -name "$pattern" -print 2>/dev/null | sort | tail -n 1
  else
    find "$base/release" -type f -name "$pattern" -print 2>/dev/null | sort | tail -n 1
  fi
}

copy_artifact() {
  local src="$1"
  local out_name="$2"
  [[ -n "$src" && -f "$src" ]] || return 1
  log "Copying $(basename "$src") -> $out_name"
  run mkdir -p "$DOWNLOADS_DIR"
  run cp "$src" "$DOWNLOADS_DIR/$out_name"
}

collect_for_target() {
  local target="$1" platform="$2" arch="$3"
  case "$platform:$arch" in
    mac:aarch64)
      copy_artifact "$(latest_file "$target" '*.dmg')" "blink-aarch64.dmg"
      ;;
    mac:x64)
      copy_artifact "$(latest_file "$target" '*.dmg')" "blink-x64.dmg"
      ;;
    windows:x64)
      copy_artifact "$(latest_file "$target" '*.exe')" "blink-setup.exe" || true
      copy_artifact "$(latest_file "$target" '*.msi')" "blink-x64.msi" || true
      ;;
    linux:x64)
      copy_artifact "$(latest_file "$target" '*.deb')" "blink.deb" || true
      copy_artifact "$(latest_file "$target" '*.AppImage')" "blink.AppImage" || true
      ;;
    *)
      warn "No collector for $target ($platform/$arch)"
      ;;
  esac
}

for item in "${TARGETS[@]}"; do
  IFS=':' read -r target platform arch <<<"$item"
  if ! build_target "$target"; then
    warn "Build failed for $target"
    if [[ "$CONTINUE_ON_ERROR" != "1" && "$COPY_EXISTING" != "1" ]]; then
      exit 1
    fi
  fi
  collect_for_target "$target" "$platform" "$arch" || {
    warn "No release artifact found for $target"
    [[ "$CONTINUE_ON_ERROR" == "1" || "$COPY_EXISTING" == "1" ]] || exit 1
  }
done

write_manifest() {
  run mkdir -p "$DOWNLOADS_DIR"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would write manifest and SHA256SUMS in $DOWNLOADS_DIR"
    return 0
  fi

  local manifest="$DOWNLOADS_DIR/manifest.json"
  local sums="$DOWNLOADS_DIR/SHA256SUMS"
  : > "$sums"

  DOWNLOADS_DIR="$DOWNLOADS_DIR" BASE_URL="$BASE_URL" VERSION="$VERSION" GENERATED_AT="$GENERATED_AT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const dir = process.env.DOWNLOADS_DIR;
const baseUrl = process.env.BASE_URL;
const version = process.env.VERSION;
const generatedAt = process.env.GENERATED_AT;
const files = [
  ['blink-aarch64.dmg', 'macos', 'aarch64'],
  ['blink-x64.dmg', 'macos', 'x64'],
  ['blink-setup.exe', 'windows', 'x64'],
  ['blink-x64.msi', 'windows', 'x64'],
  ['blink.deb', 'linux', 'x64'],
  ['blink.AppImage', 'linux', 'x64'],
].filter(([name]) => fs.existsSync(path.join(dir, name)));
const artifacts = files.map(([name, platform, arch]) => {
  const file = path.join(dir, name);
  const bytes = fs.readFileSync(file);
  return {
    name,
    platform,
    arch,
    url: `${baseUrl}/${name}`,
    size: bytes.length,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
  };
});
fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ version, generatedAt, artifacts }, null, 2) + '\n');
fs.writeFileSync(path.join(dir, 'SHA256SUMS'), artifacts.map((a) => `${a.sha256}  ${a.name}`).join('\n') + (artifacts.length ? '\n' : ''));
NODE
}

update_cask() {
  [[ "$UPDATE_CASK" == "1" ]] || return 0
  local cask="$TAP_DIR/Casks/blink.rb"
  [[ -f "$cask" ]] || { warn "Homebrew cask not found at $cask"; return 0; }

  log "Updating Homebrew cask version and URL"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would update $cask"
    return 0
  fi

  CASK_PATH="$cask" BASE_URL="$BASE_URL" VERSION="$VERSION" node <<'NODE'
const fs = require('fs');
const cask = process.env.CASK_PATH;
const version = process.env.VERSION;
const baseUrl = process.env.BASE_URL;
let text = fs.readFileSync(cask, 'utf8');
text = text.replace(/version\s+"[^"]+"/, `version "${version}"`);
text = text.replace(/url\s+".*"/, `url "${baseUrl}/blink-#{arch}.dmg"`);
text = text.replace(/homepage\s+".*"/, 'homepage "https://blink.digitwhale.com"');
text = text.replace(/desc\s+".*"/, 'desc "Local operational AI workspace environment"');
fs.writeFileSync(cask, text);
NODE
}

write_manifest
update_cask

log "Desktop release artifacts are in $DOWNLOADS_DIR"
find "$DOWNLOADS_DIR" -maxdepth 1 -type f | sort
