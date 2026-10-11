#!/bin/bash
#
# Production build: Release configuration, verified and packaged for another Mac.
#
# Signing comes from what the project configures (`Signing.xcconfig`, which a machine with a
# certificate overrides through `Signing.local.xcconfig`), or from --identity/--team when given. The
# script reports what the artifact actually carries rather than assuming: an ad-hoc build runs on
# another Mac after a one-time right-click Open and loses its Accessibility grant on every rebuild,
# while a certificate keeps it. Either way the result is not notarised, so the first launch on
# another Mac needs a right-click Open.
#
# Usage:
#   scripts/prod-build.sh [--identity <name>] [--team <id>] [--arch <arm64|x86_64|universal>]
#                         [--out <dir>] [--notarise <keychain-profile>] [--no-package] [--help]
#
# Examples:
#   scripts/prod-build.sh                                  # universal, signed as the project configures
#   scripts/prod-build.sh --arch arm64                     # this Mac's architecture only, smaller
#   scripts/prod-build.sh --team Z98NKJSF69                # sign with that team explicitly
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

# --- reporting ----------------------------------------------------------------------------------

# What a signed artifact is worth, said from what `codesign` reported rather than from the arguments
# that were passed: only a certificate keeps the Accessibility grant across rebuilds.
report_signing() {
  local signed_with="$1" team_id="$2"
  # `codesign` prints "ad-hoc" as the authority when nothing signed the app, so that too means no
  # certificate — the case this function exists to keep out of the certificate branch.
  if [[ -z "$signed_with" || "$signed_with" == "-" || "$signed_with" == "ad-hoc" ]]; then
    echo "    signed with    ad-hoc, no certificate"
    echo "                   Runs on another Mac after a one-time right-click Open, and the Accessibility"
    echo "                   grant is lost on every rebuild. Pass --team <id> to sign with a certificate."
  else
    echo "    signed with    $signed_with${team_id:+ (team $team_id)}"
    echo "                   A certificate keeps the Accessibility grant across rebuilds."
  fi
}

# --- signing ------------------------------------------------------------------------------------

# `project.yml` points both configurations at an xcconfig, which a machine with a certificate
# overrides through `Signing.local.xcconfig`. Passing `--identity` or `--team` overrides that again.
#
# Nothing is assumed about which of the three won: the build is asked to sign, and what it produced is
# read back from the artifact below. Guessing here is what made this script report "ad-hoc" for a build
# it had signed with a certificate.
#
# macOS ships bash 3.2, where an empty array expanded under `set -u` is an error, so every expansion
# below uses the ${arr[@]+...} guard.
signing_args=()
if [[ -n "$identity" || -n "$team" ]]; then
  echo "==> Signing with the identity given on the command line"
  security find-identity -v -p codesigning | sed -n '2,20p' || true
  signing_args+=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="${identity:-Apple Development}" -allowProvisioningUpdates)
  [[ -n "$team" ]] && signing_args+=(DEVELOPMENT_TEAM="$team")
else
  echo "==> Signing as the project's xcconfig configures it; what the artifact carries is reported below."
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

# No `exit` in these awk programs: leaving early closes the pipe while codesign is still writing, and
# with `set -o pipefail` that SIGPIPE (141) becomes the script's own exit status. Each program reads to
# the end instead and remembers the first match it saw.
signed_with="$(codesign -dv --verbose=4 "$app" 2>&1 | awk -F= '/^Authority=/{if (!seen) {print $2; seen=1}}')"
team_id="$(codesign -dv --verbose=4 "$app" 2>&1 | awk -F= '/^TeamIdentifier=/{if (!team) {team=$2}} END {print team}')"
[[ "$team_id" == "not set" ]] && team_id=""   # codesign says "not set" rather than leaving it out
# The version comes from the app itself, so `project.yml` is the only place it is written. Without
# MARKETING_VERSION the plist carries none, and the commit becomes the honest label for the artifact.
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

# Reported from the built app, not from the arguments: a certificate is what allows the Accessibility
# grant to survive a rebuild, so the two cases must not be confused.
report_signing "$signed_with" "$team_id"
echo "    size           $size"

echo
echo "    Not notarised either way: another Mac needs 'xattr -dr com.apple.quarantine <app>'"
echo "    or a right-click Open before it will launch."

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
