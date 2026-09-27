#!/bin/bash
#
# Production build: Release configuration, verified and packaged for another Mac.
#
# Ad-hoc signing is the default, because that is what this repository can do without an Apple
# account session. It runs on another Mac after a one-time right-click Open, and its Accessibility
# permission is lost on every rebuild. Pass --team (or set OWLET_TEAM) once a certificate exists:
# a signed build keeps the same permission across rebuilds, but still needs notarisation before it
# opens without a warning.
#
# Usage:
#   scripts/prod-build.sh [--identity <name>] [--team <id>] [--arch <arm64|x86_64|universal>]
#                         [--out <dir>] [--notarise <keychain-profile>] [--no-package] [--help]
#
# Examples:
#   scripts/prod-build.sh                                  # ad-hoc, universal, packaged
#   scripts/prod-build.sh --arch arm64                     # faster, this Mac only
#   scripts/prod-build.sh --team Z98NKJSF69                # Apple Development (free account)
#   scripts/prod-build.sh --team ABCDE12345 --notarise owlet-notary
#
set -euo pipefail

readonly bundle_id="dev.fahchen.owlet"
readonly minimum_macos="26.0"
readonly app_name="Owlet"
readonly scheme="Owlet"
readonly project="Owlet.xcodeproj"

identity="${OWLET_SIGN_IDENTITY:-}"
team="${OWLET_TEAM:-}"
arch="universal"
out_dir="dist"
notarise_profile=""
package=true

usage() { sed -n '3,20p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) identity="${2:?--identity needs a name}"; shift 2 ;;
    --team) team="${2:?--team needs a team id}"; shift 2 ;;
    --arch) arch="${2:?--arch needs a value}"; shift 2 ;;
    --out) out_dir="${2:?--out needs a path}"; shift 2 ;;
    --notarise) notarise_profile="${2:?--notarise needs a keychain profile}"; shift 2 ;;
    --no-package) package=false; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

case "$arch" in
  universal) architectures="arm64 x86_64" ;;
  arm64|x86_64) architectures="$arch" ;;
  *) echo "--arch must be arm64, x86_64 or universal" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
readonly root="$PWD"
readonly derived="$root/.build/prod"
readonly app="$derived/Build/Products/Release/$app_name.app"

# --- signing ------------------------------------------------------------------------------------

# macOS ships bash 3.2, where an empty array expanded under `set -u` is an error, so every
# expansion below uses the ${arr[@]+...} guard.
signing_args=()
if [[ -n "$identity" || -n "$team" ]]; then
  echo "==> Signing identity"
  if ! security find-identity -v -p codesigning | grep -q "valid identities found" \
     || security find-identity -v -p codesigning | grep -q "0 valid identities found"; then
    echo "No valid codesigning identity is in this keychain." >&2
    echo "Renew or create one in Xcode: Settings → Accounts → Manage Certificates… → + → Apple Development." >&2
    echo "Without it, run this script with no --team to build ad-hoc." >&2
    exit 1
  fi
  security find-identity -v -p codesigning | sed -n '2,20p'
  identity="${identity:-Apple Development}"
  signing_args+=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="$identity" -allowProvisioningUpdates)
  [[ -n "$team" ]] && signing_args+=(DEVELOPMENT_TEAM="$team")
else
  echo "==> Signing ad-hoc (no certificate). The result runs on another Mac after a one-time"
  echo "    right-click Open, and asks for Accessibility again after every rebuild."
fi

# --- provenance ---------------------------------------------------------------------------------

revision="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
dirty=""
git diff --quiet HEAD 2>/dev/null || dirty=" (dirty working tree)"
echo "==> Building $revision$dirty, $arch"

# --- build --------------------------------------------------------------------------------------

xcodegen generate --quiet
xcodebuild \
  -project "$project" -scheme "$scheme" -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  ARCHS="$architectures" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ${signing_args[@]+"${signing_args[@]}"} \
  build | tail -5

[[ -d "$app" ]] || { echo "build produced no app at $app" >&2; exit 1; }

# Xcode injects the base entitlements (get-task-allow) for ad-hoc and development signatures, which
# is why a Release build can still carry a debug entitlement; a production build must not.

# --- verify -------------------------------------------------------------------------------------

echo "==> Verifying"
fail() { echo "FAILED: $1" >&2; exit 1; }

plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" | grep -qx "$bundle_id" \
  || fail "bundle identifier is not $bundle_id"
plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist" | grep -qx "$minimum_macos" \
  || fail "minimum macOS is not $minimum_macos"
plutil -extract CFBundleIconName raw "$app/Contents/Info.plist" | grep -qx "AppIcon" \
  || fail "the app icon is missing"
codesign --verify --deep --strict "$app" 2>/dev/null || fail "the signature does not verify"
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q "get-task-allow"; then
  fail "a Release build carries get-task-allow, so it is signed like a debug build"
fi

signed_with="$(codesign -dv --verbose=4 "$app" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"
team_id="$(codesign -dv --verbose=4 "$app" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ "$team_id" == "not set" ]] && team_id=""   # codesign says "not set" rather than leaving it out
# project.yml sets no MARKETING_VERSION, so Xcode's generated Info.plist may carry no version at
# all; the commit is then the honest label for the artifact rather than an invented number.
short_version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" 2>/dev/null || true)"
versioned=true
[[ -n "$short_version" ]] || { short_version="$revision"; versioned=false; }
built_archs="$(lipo -archs "$app/Contents/MacOS/$app_name")"
size="$(du -sh "$app" | cut -f1)"

if [[ "$versioned" == true ]]; then
  echo "    bundle id      $bundle_id $short_version"
else
  echo "    bundle id      $bundle_id (no MARKETING_VERSION, labelled with the commit)"
fi
echo "    architectures  $built_archs"
echo "    minimum macOS  $minimum_macos"
echo "    signed with    ${signed_with:-ad-hoc (no Team ID)}${team_id:+ (team $team_id)}"
echo "    size           $size"

if [[ -z "$team_id" ]]; then
  echo
  echo "    Ad-hoc: not notarised and not attributable. Another Mac will need"
  echo "    'xattr -dr com.apple.quarantine <app>' or a right-click Open, and Accessibility"
  echo "    must be granted again on that Mac and after every rebuild here."
fi

# --- notarise (opt-in) --------------------------------------------------------------------------

if [[ -n "$notarise_profile" ]]; then
  echo "==> Notarising with keychain profile $notarise_profile"
  [[ -n "$team_id" ]] || fail "notarisation needs a Developer ID signature, not ad-hoc"
  zip_for_notary="$(mktemp -d)/$app_name.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_for_notary"
  xcrun notarytool submit "$zip_for_notary" --keychain-profile "$notarise_profile" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
fi

# --- package ------------------------------------------------------------------------------------

if [[ "$package" == true ]]; then
  mkdir -p "$out_dir"
  suffix="$arch"
  [[ "$built_archs" == "arm64 x86_64" || "$built_archs" == "x86_64 arm64" ]] && suffix="universal"
  artifact="$out_dir/$app_name-$short_version-$suffix.zip"
  rm -f "$artifact"
  # ditto, not zip: it keeps the bundle's permissions, symlinks and extended attributes.
  ditto -c -k --sequesterRsrc --keepParent "$app" "$artifact"
  echo "==> Packaged"
  echo "    $artifact"
  echo "    sha256 $(shasum -a 256 "$artifact" | cut -d' ' -f1)"
  echo "    copy with scp or rsync, not AirDrop: that avoids the quarantine flag Gatekeeper"
  echo "    checks for, so a right-click Open is only needed once."
fi
