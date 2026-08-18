set quiet

# Build the macOS DMG and verify its declared minimum system version against every bundled Mach-O binary.
checkminversion:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "error: checkminversion requires macOS" >&2
        exit 1
    fi

    for tool in file lipo vtool /usr/libexec/PlistBuddy; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "error: required macOS tool not found: $tool" >&2
            exit 1
        fi
    done

    ./gradlew :composeApp:packageReleaseDmg

    app_directory="composeApp/build/compose/binaries/main-release/app"
    shopt -s nullglob
    apps=("$app_directory"/*.app)
    shopt -u nullglob
    if (( ${#apps[@]} != 1 )); then
        echo "error: expected exactly one .app bundle in $app_directory, found ${#apps[@]}" >&2
        exit 1
    fi
    app="${apps[0]}"

    info_plist="$app/Contents/Info.plist"
    declared_version=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")

    version_key() {
        local version="$1"
        if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
            echo "error: unsupported macOS version format: $version" >&2
            return 1
        fi
        awk -F. '{ printf "%010d%010d%010d\n", $1, $2, $3 }' <<<"$version"
    }

    declared_key=$(version_key "$declared_version")
    maximum_version=""
    maximum_key=""
    maximum_path=""
    macho_count=0

    while IFS= read -r -d '' candidate; do
        if [[ "$(file -b "$candidate")" != Mach-O* ]]; then
            continue
        fi

        relative_path="${candidate#"$app/"}"
        architectures=$(lipo -archs "$candidate")
        if [[ "$architectures" != "arm64" ]]; then
            echo "error: $relative_path has unsupported architecture(s): $architectures" >&2
            exit 1
        fi

        min_versions=$(vtool -show-build "$candidate" | awk '$1 == "platform" && $2 == "MACOS" { macos = 1; next } macos && $1 == "minos" { print $2; macos = 0 }')
        min_version_count=$(awk 'NF { count++ } END { print count + 0 }' <<<"$min_versions")
        if (( min_version_count != 1 )); then
            echo "error: expected one macOS minimum version in $relative_path, found $min_version_count" >&2
            exit 1
        fi

        min_version="$min_versions"
        min_key=$(version_key "$min_version")
        (( macho_count += 1 ))
        if [[ -z "$maximum_key" || "$min_key" > "$maximum_key" ]]; then
            maximum_version="$min_version"
            maximum_key="$min_key"
            maximum_path="$relative_path"
        fi
    done < <(find "$app" -type f -print0)

    if (( macho_count == 0 )); then
        echo "error: no Mach-O binaries found in $app" >&2
        exit 1
    fi

    if [[ "$declared_key" != "$maximum_key" ]]; then
        echo "error: LSMinimumSystemVersion is $declared_version, but bundled Mach-O binaries require $maximum_version" >&2
        echo "       highest requirement found in: $maximum_path" >&2
        exit 1
    fi

    echo "OK: LSMinimumSystemVersion $declared_version matches all $macho_count arm64 Mach-O binaries."
