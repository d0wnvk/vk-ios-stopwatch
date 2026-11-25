#!/bin/bash

set -Eeuo pipefail

readonly DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

readonly XCRUN="/usr/bin/xcrun"
readonly XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly APPS_DIR="$(dirname -- "$SCRIPT_DIR")"
readonly BUILD_ROOT="${TMPDIR%/}/vk-iphone-app-refresh"
readonly COCOAPODS="/opt/homebrew/bin/pod"

DEVICE_ID="${DEVICE_ID:-}"
ONLY=""

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") [--device DEVICE_ID] [APP]" \
    "" \
    "Refreshes the free development signatures, builds, and installs:" \
    "  - stopwatch" \
    "  - videorecorder" \
    "  - videoplayer" \
    "  - insta360-recorder" \
    "" \
    "If more than one iPhone is paired, pass its identifier with --device" \
    "or set the DEVICE_ID environment variable." \
    "APP: stopwatch, videorecorder, videoplayer, or insta360-recorder." \
    "Omit APP to refresh stopwatch."
}

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --device)
      (($# >= 2)) || die "--device requires an identifier"
      DEVICE_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    stopwatch|videorecorder|videoplayer|insta360-recorder)
      [[ -z "$ONLY" ]] || die "only one app may be specified"
      ONLY="$1"
      shift
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

ONLY="${ONLY:-stopwatch}"

[[ -x "$XCODEBUILD" ]] ||
  die "Xcode was not found at /Applications/Xcode.app"

discover_device() {
  local json_file
  json_file="$(mktemp "${TMPDIR%/}/vk-devices.XXXXXX")"
  trap 'rm -f "$json_file"' RETURN

  "$XCRUN" devicectl list devices \
    --filter "hardwareProperties.platform == 'iOS'" \
    --timeout 15 \
    --quiet \
    --json-output "$json_file" >/dev/null

  /usr/bin/python3 - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)

devices = document.get("result", {}).get("devices", [])
devices = [
    device for device in devices
    if (
        device.get("properties", {}).get("hardware", {}).get("deviceType")
        or device.get("hardwareProperties", {}).get("deviceType")
    ) == "iPhone"
    and (
        device.get("properties", {}).get("hardware", {}).get("reality")
        or device.get("hardwareProperties", {}).get("reality")
        or "physical"
    ) != "simulated"
]
if not devices:
    raise SystemExit(1)

def identifier(device):
    return (
        device.get("properties", {}).get("hardware", {}).get("udid")
        or device.get("hardwareProperties", {}).get("udid")
        or device.get("identifier")
        or ""
    )

ids = [identifier(device) for device in devices]
ids = [value for value in ids if value]
if not ids:
    raise SystemExit(1)

print(ids[0])
PY
}

if [[ -z "$DEVICE_ID" ]]; then
  log "Looking for a paired iPhone"
  DEVICE_ID="$(discover_device)" ||
    die "no paired iPhone was found; connect and unlock it, then try again"
fi

should_run() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

build_and_install() {
  local name="$1"
  local container="$2"
  local scheme="$3"
  local app_name="$4"
  local derived_data="${BUILD_ROOT}/${name}"
  local app_path="${derived_data}/Build/Products/Debug-iphoneos/${app_name}.app"
  local container_option="-project"

  [[ -d "$container" ]] || die "Xcode project or workspace not found: $container"
  if [[ "$container" == *.xcworkspace ]]; then
    container_option="-workspace"
  fi

  log "Building ${name}"
  "$XCODEBUILD" \
    "$container_option" "$container" \
    -scheme "$scheme" \
    -configuration Debug \
    -destination "platform=iOS,id=${DEVICE_ID}" \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build

  [[ -d "$app_path" ]] ||
    die "build succeeded but the app was not found at: $app_path"

  log "Installing ${name}"
  "$XCRUN" devicectl device install app \
    --device "$DEVICE_ID" \
    --timeout 60 \
    "$app_path"
}

if should_run stopwatch; then
  [[ -x "$COCOAPODS" ]] ||
    die "CocoaPods was not found; install it with: brew install cocoapods"

  log "Installing stopwatch dependencies"
  "$COCOAPODS" install --project-directory="$SCRIPT_DIR"

  build_and_install \
    "stopwatch" \
    "${SCRIPT_DIR}/stopwatch.xcworkspace" \
    "stopwatch" \
    "stopwatch"
fi

if should_run videorecorder; then build_and_install \
  "videorecorder" \
  "${APPS_DIR}/videorecorder/videorecorder.xcodeproj" \
  "videorecorder" \
  "videorecorder"; fi

if should_run videoplayer; then
[[ -x "$COCOAPODS" ]] ||
  die "CocoaPods was not found; install it with: brew install cocoapods"

log "Installing videoplayer dependencies"
"$COCOAPODS" install --project-directory="${APPS_DIR}/videoplayer"

build_and_install \
  "videoplayer" \
  "${APPS_DIR}/videoplayer/videoplayer.xcworkspace" \
  "videoplayer" \
  "videoplayer"
fi

if should_run insta360-recorder; then build_and_install \
  "insta360-recorder" \
  "${APPS_DIR}/insta360-recorder/Insta360Recorder.xcodeproj" \
  "Insta360Recorder" \
  "Insta360Recorder"; fi

log "All apps were refreshed successfully"
