#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

read -r -a flutter_command <<< "${FLUTTER_CMD:-flutter}"
read -r -a dart_command <<< "${DART_CMD:-dart}"
read -r -a npm_command <<< "${NPM_CMD:-npm}"
read -r -a pdf_python_command <<< "${PDF_PYTHON:-python3}"

database_started_here=0

cleanup() {
  if [[ "$database_started_here" == "1" ]]; then
    "${npm_command[@]}" exec -- supabase stop --no-backup
  fi
}
trap cleanup EXIT

step() {
  printf '\n== %s ==\n' "$1"
}

step "固定ツールバージョン"
FLUTTER_CMD="${FLUTTER_CMD:-flutter}" \
  DART_CMD="${DART_CMD:-dart}" \
  NPM_CMD="${NPM_CMD:-npm}" \
  bash scripts/check_tool_versions.sh

step "Flutter format"
(
  cd apps/kiwi_inventory
  "${dart_command[@]}" format --output=none --set-exit-if-changed lib test
)

step "Flutter analyze"
(
  cd apps/kiwi_inventory
  "${flutter_command[@]}" analyze
)

step "Flutter tests"
(
  cd apps/kiwi_inventory
  "${flutter_command[@]}" test --exclude-tags golden
)

step "Flutter Golden tests"
(
  cd apps/kiwi_inventory
  TZ=UTC "${flutter_command[@]}" test test/home_golden_test.dart
)

step "Flutter Web release build"
(
  cd apps/kiwi_inventory
  "${flutter_command[@]}" build web --release
)

if [[ "${STAGE1_SKIP_DATABASE:-0}" != "1" ]]; then
  step "Supabase local database"
  if ! "${npm_command[@]}" exec -- supabase status >/dev/null 2>&1; then
    "${npm_command[@]}" exec -- supabase start
    database_started_here=1
  fi
  "${npm_command[@]}" exec -- supabase db reset
  "${npm_command[@]}" exec -- supabase db lint --local --fail-on warning
  "${npm_command[@]}" exec -- supabase test db
else
  step "Supabase local database (skipped)"
fi

if [[ "${STAGE1_SKIP_PDF:-0}" != "1" ]]; then
  step "A5 label PDF"
  "${pdf_python_command[@]}" experiments/fnd-07/verify_a5_label.py
else
  step "A5 label PDF (skipped)"
fi

printf '\nStage 1 automated acceptance checks passed.\n'
