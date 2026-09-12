#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: macOS Dylib verification requires macOS" >&2
    exit 1
fi

if (( $# != 1 )); then
    echo "usage: $0 <application.app>" >&2
    exit 1
fi

app=$1
resources_dir="$app/Contents/app/resources"
required_libraries=(
    "libmatrix_sdk_ffi.dylib"
    "libmatrix_rtc_ffi.dylib"
)

if [[ ! -d "$app" ]]; then
    echo "error: app bundle not found: $app" >&2
    exit 1
fi

if [[ ! -d "$resources_dir" ]]; then
    echo "error: resources directory not found: $resources_dir" >&2
    exit 1
fi

for library_name in "${required_libraries[@]}"; do
    expected_library="$resources_dir/$library_name"
    if [[ ! -f "$expected_library" ]]; then
        echo "error: expected library not found at $expected_library" >&2
        exit 1
    fi

    architectures=$(lipo -archs "$expected_library")
    if [[ "$architectures" != "arm64" ]]; then
        echo "error: $library_name has unsupported architecture(s): $architectures" >&2
        exit 1
    fi

    while IFS= read -r dependency; do
        case "$dependency" in
            *"$library_name"*|/System/Library/*|/usr/lib/*)
                ;;
            *)
                echo "error: $library_name has non-system dependency: $dependency" >&2
                exit 1
                ;;
        esac
    done < <(otool -L "$expected_library" | tail -n +2 | sed -E 's/^[[:space:]]*//; s/ \(compatibility version.*$//')

    codesign --verify --strict --verbose=2 "$expected_library"
done

codesign --verify --strict --verbose=2 "$app"

echo "OK: bundled Rust Dylibs (SDK & RTC) are ARM64, correctly placed in app/resources, and validly signed."
