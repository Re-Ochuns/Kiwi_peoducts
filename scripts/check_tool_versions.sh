#!/usr/bin/env bash
set -euo pipefail

EXPECTED_FLUTTER="3.47.2"
EXPECTED_DART="3.13.2"
EXPECTED_NODE="24.19.0"
EXPECTED_SUPABASE="2.117.0"

read -r -a flutter_command <<< "${FLUTTER_CMD:-flutter}"
read -r -a dart_command <<< "${DART_CMD:-dart}"
read -r -a npm_command <<< "${NPM_CMD:-npm}"

flutter_output="$("${flutter_command[@]}" --version)"
flutter_version="$(awk 'NR == 1 {print $2}' <<< "$flutter_output")"
dart_version="$("${dart_command[@]}" --version 2>&1 | awk '{print $4}')"
node_version="$(node --version | sed 's/^v//')"
supabase_version="$("${npm_command[@]}" exec -- supabase --version)"

check_version() {
  local tool="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf '%s version mismatch: expected %s, got %s\n' "$tool" "$expected" "$actual" >&2
    return 1
  fi

  printf '%s %s OK\n' "$tool" "$actual"
}

check_version "Flutter" "$EXPECTED_FLUTTER" "$flutter_version"
check_version "Dart" "$EXPECTED_DART" "$dart_version"
check_version "Node.js" "$EXPECTED_NODE" "$node_version"
check_version "Supabase CLI" "$EXPECTED_SUPABASE" "$supabase_version"
