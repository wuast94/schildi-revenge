#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: MACOS_TEAM_ID=<team id> check-macos-signature.sh <mode> <path>

modes:
  app <application.app>         Developer ID signature of the bundle and every Mach-O binary in it
  dmg <image.dmg>               Developer ID signature, stapled ticket and Gatekeeper assessment of the DMG
  gatekeeper <application.app>  Gatekeeper assessment of a notarized app
EOF
    exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: macOS signature verification requires macOS" >&2
    exit 1
fi

(( $# == 2 )) || usage
mode=$1
target=$2
team_id=${MACOS_TEAM_ID:?MACOS_TEAM_ID must name the expected Developer ID team}

if [[ ! -e "$target" ]]; then
    echo "error: not found: $target" >&2
    exit 1
fi

# Fails unless the code object carries a timestamped Developer ID signature of the expected team.
require_developer_id() {
    local path=$1 label=$2 info
    if ! info=$(codesign --display --verbose=2 "$path" 2>&1); then
        echo "error: $label is not signed" >&2
        return 1
    fi
    if ! grep -q '^Authority=Developer ID Application: ' <<<"$info"; then
        echo "error: $label is not signed with a Developer ID Application certificate" >&2
        return 1
    fi
    if ! grep -Fxq "TeamIdentifier=$team_id" <<<"$info"; then
        echo "error: $label is not signed by team $team_id" >&2
        return 1
    fi
    if ! grep -q '^Timestamp=' <<<"$info"; then
        echo "error: $label has no secure timestamp" >&2
        return 1
    fi
}

require_hardened_runtime() {
    local path=$1 label=$2 info
    info=$(codesign --display --verbose=2 "$path" 2>&1) || true
    if ! grep -Eq '^CodeDirectory .*flags=[^ ]*runtime' <<<"$info"; then
        echo "error: $label does not use the hardened runtime" >&2
        return 1
    fi
}

require_notarized() {
    local assessment_type=$1 path=$2 result
    shift 2
    if ! result=$(spctl --assess --verbose=2 --type "$assessment_type" "$@" "$path" 2>&1); then
        echo "error: Gatekeeper rejects $path" >&2
        echo "$result" >&2
        return 1
    fi
    if ! grep -Fxq 'source=Notarized Developer ID' <<<"$result"; then
        echo "error: $path is accepted, but not as notarized Developer ID software" >&2
        echo "$result" >&2
        return 1
    fi
}

check_app() {
    local app=$1 failures=0 macho_count=0 candidate kind relative_path entitlements

    while IFS= read -r -d '' candidate; do
        kind=$(file -b "$candidate")
        [[ "$kind" == Mach-O* ]] || continue
        relative_path="${candidate#"$app/"}"
        (( macho_count += 1 ))
        require_developer_id "$candidate" "$relative_path" || (( failures += 1 ))
        if [[ "$kind" == *executable* ]]; then
            require_hardened_runtime "$candidate" "$relative_path" || (( failures += 1 ))
        fi
    done < <(find "$app" -type f -print0)

    if (( macho_count == 0 )); then
        echo "error: no Mach-O binaries found in $app" >&2
        exit 1
    fi
    if (( failures > 0 )); then
        echo "error: $failures signature problem(s) in $macho_count Mach-O binaries" >&2
        exit 1
    fi

    require_developer_id "$app" "app bundle"
    require_hardened_runtime "$app" "app bundle"
    codesign --verify --deep --strict "$app"

    entitlements=$(codesign --display --entitlements - --xml "$app" 2>/dev/null | tr -d '\0')
    if grep -q 'com.apple.security.get-task-allow' <<<"$entitlements"; then
        echo "error: app bundle carries the get-task-allow entitlement" >&2
        exit 1
    fi

    echo "OK: app bundle and all $macho_count Mach-O binaries are signed by Developer ID team $team_id."
}

check_dmg() {
    local dmg=$1
    require_developer_id "$dmg" "DMG"
    codesign --verify --strict "$dmg"
    xcrun stapler validate "$dmg"
    require_notarized open "$dmg" --context context:primary-signature
    echo "OK: DMG is signed by Developer ID team $team_id, notarized and stapled."
}

case "$mode" in
    app)
        check_app "$target"
        ;;
    dmg)
        check_dmg "$target"
        ;;
    gatekeeper)
        require_notarized exec "$target"
        echo "OK: Gatekeeper accepts the app as notarized Developer ID software."
        ;;
    *)
        usage
        ;;
esac
