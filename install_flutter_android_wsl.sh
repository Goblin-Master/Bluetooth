#!/usr/bin/env bash
set -euo pipefail

# User-level Flutter + Android SDK + Go installer for WSL/Ubuntu.

TOOLS_ROOT="${TOOLS_ROOT:-$HOME/development}"
FLUTTER_DIR="${FLUTTER_DIR:-$TOOLS_ROOT/flutter}"
GO_ROOT="${GO_ROOT:-$TOOLS_ROOT/go}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-36}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
NO_CHINA_MIRRORS="${NO_CHINA_MIRRORS:-0}"
SKIP_ANDROID_LICENSES="${SKIP_ANDROID_LICENSES:-0}"
CMDLINE_TOOLS_ZIP_URL="${CMDLINE_TOOLS_ZIP_URL:-}"
TMP_DIRS=()

cleanup() {
  if [ "${#TMP_DIRS[@]}" -gt 0 ]; then
    rm -rf "${TMP_DIRS[@]}"
  fi
}

trap cleanup EXIT

step() {
  printf '\n\033[1;36m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

is_true() {
  case "${1,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

make_temp_dir() {
  local dir
  dir="$(mktemp -d)"
  TMP_DIRS+=("$dir")
  printf '%s\n' "$dir"
}

append_once() {
  local line="$1"
  local file="$2"

  touch "$file"
  if ! grep -Fxq "$line" "$file"; then
    printf '\n%s\n' "$line" >> "$file"
  fi
}

download_first() {
  local out_file="$1"
  shift

  local url
  local last_status=1
  for url in "$@"; do
    [ -n "$url" ] || continue
    step "Downloading $url"
    if curl -fL --retry 3 --connect-timeout 20 "$url" -o "$out_file"; then
      return 0
    fi
    last_status=$?
    rm -f "$out_file"
    warn "Download failed, trying next source"
  done

  return "$last_status"
}

detect_go_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64' ;;
    aarch64 | arm64) printf 'arm64' ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

if is_true "$NO_CHINA_MIRRORS"; then
  USE_CHINA_MIRRORS=0
else
  USE_CHINA_MIRRORS=1
fi

if [ "$USE_CHINA_MIRRORS" -eq 1 ]; then
  FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
  GO_RELEASE_JSON_URL="https://golang.google.cn/dl/?mode=json"
  GO_DOWNLOAD_BASE_URL="https://mirrors.aliyun.com/golang"
  PUB_HOSTED_URL_VALUE="https://pub.flutter-io.cn"
else
  FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"
  GO_RELEASE_JSON_URL="https://go.dev/dl/?mode=json"
  GO_DOWNLOAD_BASE_URL="https://go.dev/dl"
  PUB_HOSTED_URL_VALUE=""
fi

install_apt_deps() {
  if ! need_cmd apt-get; then
    warn "apt-get not found. Install git, curl, unzip, xz-utils, zip, tar, python3, and openjdk-17-jdk manually."
    return
  fi

  step "Installing system packages"
  sudo apt-get update
  sudo apt-get install -y \
    ca-certificates \
    curl \
    git \
    libglu1-mesa \
    openjdk-17-jdk \
    python3 \
    tar \
    unzip \
    xz-utils \
    zip
}

install_flutter() {
  local flutter_bin="$FLUTTER_DIR/bin/flutter"
  if [ -x "$flutter_bin" ]; then
    step "Flutter already exists"
    "$flutter_bin" --version
    return
  fi

  if [ -e "$FLUTTER_DIR" ]; then
    die "Directory exists but is not a Flutter SDK: $FLUTTER_DIR"
  fi

  step "Installing Flutter stable"
  mkdir -p "$(dirname "$FLUTTER_DIR")"

  local tmp_dir
  tmp_dir="$(make_temp_dir)"

  local releases_json="$tmp_dir/flutter-releases.json"
  download_first \
    "$releases_json" \
    "$FLUTTER_STORAGE_BASE_URL/flutter_infra_release/releases/releases_linux.json" \
    "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" \
    || die "Could not download Flutter release metadata."

  local archive
  archive="$(python3 - "$releases_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

stable_hash = data["current_release"]["stable"]
for release in data["releases"]:
    if release.get("hash") == stable_hash:
        print(release["archive"])
        break
else:
    raise SystemExit("stable Flutter release not found")
PY
)"

  local flutter_archive="$tmp_dir/flutter.tar.xz"
  download_first \
    "$flutter_archive" \
    "$FLUTTER_STORAGE_BASE_URL/flutter_infra_release/releases/$archive" \
    "https://storage.googleapis.com/flutter_infra_release/releases/$archive" \
    || die "Could not download Flutter SDK."

  tar -xf "$flutter_archive" -C "$tmp_dir"
  [ -d "$tmp_dir/flutter" ] || die "Unexpected Flutter archive layout."
  mv "$tmp_dir/flutter" "$FLUTTER_DIR"

  "$flutter_bin" --version
}

install_go() {
  local go_bin="$GO_ROOT/bin/go"
  if [ -x "$go_bin" ]; then
    step "Go already exists"
    "$go_bin" version
    return
  fi

  if [ -e "$GO_ROOT" ]; then
    die "Directory exists but is not a Go SDK: $GO_ROOT"
  fi

  step "Installing Go stable"
  mkdir -p "$(dirname "$GO_ROOT")"

  local tmp_dir
  tmp_dir="$(make_temp_dir)"

  local releases_json="$tmp_dir/go-releases.json"
  download_first \
    "$releases_json" \
    "$GO_RELEASE_JSON_URL" \
    "https://go.dev/dl/?mode=json" \
    || die "Could not download Go release metadata."

  local go_arch
  go_arch="$(detect_go_arch)"

  local filename
  filename="$(python3 - "$releases_json" "$go_arch" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    releases = json.load(f)

arch = sys.argv[2]
for release in releases:
    if not release.get("stable"):
        continue
    for item in release.get("files", []):
        if item.get("os") == "linux" and item.get("arch") == arch and item.get("kind") == "archive":
            print(item["filename"])
            raise SystemExit(0)

raise SystemExit(f"Go archive for linux/{arch} not found")
PY
)"

  local go_archive="$tmp_dir/$filename"
  download_first \
    "$go_archive" \
    "$GO_DOWNLOAD_BASE_URL/$filename" \
    "https://golang.google.cn/dl/$filename" \
    "https://go.dev/dl/$filename" \
    || die "Could not download Go SDK."

  tar -C "$tmp_dir" -xzf "$go_archive"
  [ -d "$tmp_dir/go" ] || die "Unexpected Go archive layout."
  mv "$tmp_dir/go" "$GO_ROOT"

  "$go_bin" version
}

install_android_sdk() {
  local sdkmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools" "$ANDROID_SDK_ROOT/platforms" "$ANDROID_SDK_ROOT/platform-tools"

  if [ -x "$sdkmanager" ]; then
    step "Android command-line tools already exist"
  else
    step "Installing Android command-line tools"
    local tmp_dir
    tmp_dir="$(make_temp_dir)"

    local zip_file="$tmp_dir/cmdline-tools.zip"
    local default_zip="commandlinetools-linux-14742923_latest.zip"
    if [ -n "$CMDLINE_TOOLS_ZIP_URL" ]; then
      download_first "$zip_file" "$CMDLINE_TOOLS_ZIP_URL" || die "Could not download Android command-line tools."
    elif [ "$USE_CHINA_MIRRORS" -eq 1 ]; then
      download_first \
        "$zip_file" \
        "https://mirrors.ustc.edu.cn/android/repository/$default_zip" \
        "https://dl.google.com/android/repository/$default_zip" \
        || die "Could not download Android command-line tools."
    else
      download_first \
        "$zip_file" \
        "https://dl.google.com/android/repository/$default_zip" \
        || die "Could not download Android command-line tools."
    fi

    unzip -q "$zip_file" -d "$tmp_dir"
    [ -d "$tmp_dir/cmdline-tools" ] || die "Unexpected Android command-line tools archive layout."
    rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    mv "$tmp_dir/cmdline-tools/"* "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
  fi

  step "Installing Android SDK packages"
  yes | "$sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" \
    "platform-tools" \
    "platforms;android-$ANDROID_API_LEVEL" \
    "build-tools;$ANDROID_BUILD_TOOLS" \
    "cmdline-tools;latest"

  if ! is_true "$SKIP_ANDROID_LICENSES"; then
    step "Accepting Android licenses"
    yes | "$sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
  fi
}

write_shell_env() {
  step "Writing shell environment"
  local bashrc="$HOME/.bashrc"

  append_once "export FLUTTER_HOME=\"$FLUTTER_DIR\"" "$bashrc"
  append_once "export GOROOT=\"$GO_ROOT\"" "$bashrc"
  append_once 'export GOPATH="$HOME/go"' "$bashrc"
  append_once "export ANDROID_HOME=\"$ANDROID_SDK_ROOT\"" "$bashrc"
  append_once "export ANDROID_SDK_ROOT=\"$ANDROID_SDK_ROOT\"" "$bashrc"
  append_once 'export PATH="$FLUTTER_HOME/bin:$GOROOT/bin:$GOPATH/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"' "$bashrc"

  if [ "$USE_CHINA_MIRRORS" -eq 1 ]; then
    append_once "export PUB_HOSTED_URL=\"$PUB_HOSTED_URL_VALUE\"" "$bashrc"
    append_once "export FLUTTER_STORAGE_BASE_URL=\"$FLUTTER_STORAGE_BASE_URL\"" "$bashrc"
  fi

  export FLUTTER_HOME="$FLUTTER_DIR"
  export GOROOT="$GO_ROOT"
  export GOPATH="${GOPATH:-$HOME/go}"
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export PATH="$FLUTTER_HOME/bin:$GOROOT/bin:$GOPATH/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

  if [ "$USE_CHINA_MIRRORS" -eq 1 ]; then
    export PUB_HOSTED_URL="$PUB_HOSTED_URL_VALUE"
    export FLUTTER_STORAGE_BASE_URL="$FLUTTER_STORAGE_BASE_URL"
  fi
}

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  warn "This does not look like WSL. Continuing as Linux."
fi

step "Starting install"
if [ "$USE_CHINA_MIRRORS" -eq 1 ]; then
  printf 'Using China mirrors. Set NO_CHINA_MIRRORS=1 to use upstream sources.\n'
else
  printf 'Using upstream sources.\n'
fi

install_apt_deps
install_flutter
install_go
write_shell_env
install_android_sdk

step "Configuring Flutter and Go"
flutter config --android-sdk "$ANDROID_SDK_ROOT"
if [ "$USE_CHINA_MIRRORS" -eq 1 ]; then
  go env -w GOPROXY=https://goproxy.cn,direct
fi
flutter precache --android

step "Final checks"
flutter doctor
go version

printf '\nDone. See README.md for next steps.\n'
