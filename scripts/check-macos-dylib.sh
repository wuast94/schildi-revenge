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
library_name=libmatrix_sdk_ffi.dylib
expected_library="$app/Contents/Frameworks/$library_name"
expected_install_name="@rpath/$library_name"

if [[ ! -d "$app" ]]; then
    echo "error: app bundle not found: $app" >&2
    exit 1
fi

libraries=()
while IFS= read -r library; do
    libraries+=("$library")
done < <(find "$app/Contents" -type f -name "$library_name" -print)

if (( ${#libraries[@]} != 1 )); then
    echo "error: expected exactly one $library_name in the app bundle, found ${#libraries[@]}" >&2
    exit 1
fi

if [[ "${libraries[0]}" != "$expected_library" ]]; then
    echo "error: $library_name must be located at Contents/Frameworks/$library_name" >&2
    echo "       found at: ${libraries[0]#"$app/"}" >&2
    exit 1
fi

architectures=$(lipo -archs "$expected_library")
if [[ "$architectures" != "arm64" ]]; then
    echo "error: $library_name has unsupported architecture(s): $architectures" >&2
    exit 1
fi

install_names=()
while IFS= read -r install_name; do
    [[ -n "$install_name" ]] && install_names+=("$install_name")
done < <(otool -D "$expected_library" | tail -n +2)

if (( ${#install_names[@]} != 1 )) || [[ "${install_names[0]}" != "$expected_install_name" ]]; then
    echo "error: expected install name $expected_install_name" >&2
    printf '       found: %s\n' "${install_names[*]:-<none>}" >&2
    exit 1
fi

while IFS= read -r dependency; do
    case "$dependency" in
        "$expected_install_name"|/System/Library/*|/usr/lib/*)
            ;;
        *)
            echo "error: $library_name has non-system dependency: $dependency" >&2
            exit 1
            ;;
    esac
done < <(otool -L "$expected_library" | tail -n +2 | sed -E 's/^[[:space:]]*//; s/ \(compatibility version.*$//')

codesign --verify --strict --verbose=2 "$expected_library"
codesign --verify --strict --verbose=2 "$app"

echo "OK: bundled Rust Dylib is ARM64, relocatable, correctly placed, and validly signed."
