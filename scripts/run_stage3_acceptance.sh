#!/usr/bin/env bash
set -euo pipefail

stage3_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$stage3_repo_root"

read -r -a stage3_flutter_command <<< "${FLUTTER_CMD:-flutter}"
read -r -a stage3_dart_command <<< "${DART_CMD:-dart}"
read -r -a stage3_npm_command <<< "${NPM_CMD:-npm}"

stage3_database_started_here=0
stage3_database_result="not-run"
stage3_edge_result="not-run"
stage3_golden_result="not-run"
stage3_staging_result="not-run"

stage3_cleanup() {
  if [[ "$stage3_database_started_here" == "1" ]]; then
    "${stage3_npm_command[@]}" exec -- supabase stop --no-backup
  fi
}
trap stage3_cleanup EXIT

stage3_step() {
  printf '\n== %s ==\n' "$1"
}

stage3_step "固定ツールバージョン"
FLUTTER_CMD="${FLUTTER_CMD:-flutter}" \
  DART_CMD="${DART_CMD:-dart}" \
  NPM_CMD="${NPM_CMD:-npm}" \
  bash scripts/check_tool_versions.sh

stage3_step "Flutter format"
(
  cd apps/kiwi_inventory
  "${stage3_dart_command[@]}" format --output=none --set-exit-if-changed lib test
)

stage3_step "Flutter analyze"
(
  cd apps/kiwi_inventory
  "${stage3_flutter_command[@]}" analyze
)

stage3_step "Flutter回帰テスト"
(
  cd apps/kiwi_inventory
  "${stage3_flutter_command[@]}" test --exclude-tags golden
)

if [[ "$(uname -s)" == "Linux" ]]; then
  stage3_step "Flutter Golden（Linux）"
  (
    cd apps/kiwi_inventory
    TZ=UTC "${stage3_flutter_command[@]}" test test/home_golden_test.dart
  )
  stage3_golden_result="pass"
else
  stage3_step "Flutter Golden（Not Run）"
  printf 'Goldenの正本はUbuntu GitHub Actionsです。非Linux環境では合格扱いにしません。\n'
fi

stage3_step "Flutter Web release build"
(
  cd apps/kiwi_inventory
  "${stage3_flutter_command[@]}" build web --release
)

if command -v deno >/dev/null 2>&1; then
  stage3_step "Edge Functions"
  (
    cd supabase/functions
    deno check label-pdf/index.ts calendar-sync/index.ts
    deno test --allow-read tests/
  )
  stage3_edge_result="pass"
else
  stage3_step "Edge Functions（Not Run）"
  printf 'Denoが見つからないため、GitHub Actionsの結果で補完してください。\n'
fi

if [[ "${STAGE3_RUN_DATABASE:-0}" == "1" ]]; then
  stage3_step "Supabase local database"
  if ! "${stage3_npm_command[@]}" exec -- supabase status >/dev/null 2>&1; then
    "${stage3_npm_command[@]}" exec -- supabase start
    stage3_database_started_here=1
  fi
  stage3_status_json="$("${stage3_npm_command[@]}" exec -- supabase status -o json)"
  STAGE3_STATUS_JSON="$stage3_status_json" python3 - <<'PY'
import json
import os
from urllib.parse import urlparse

status = json.loads(os.environ["STAGE3_STATUS_JSON"])
api_url = status.get("API_URL", "")
parsed = urlparse(api_url)
if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
    raise SystemExit("Refusing to reset a non-local Supabase environment")
PY
  "${stage3_npm_command[@]}" exec -- supabase db reset
  "${stage3_npm_command[@]}" exec -- supabase db lint --local --fail-on warning
  "${stage3_npm_command[@]}" exec -- supabase test db
  stage3_database_result="pass"
else
  stage3_step "Supabase local database（Not Run）"
  printf '専用ローカル環境を確認後、STAGE3_RUN_DATABASE=1で明示的に実行してください。\n'
fi

if [[ -n "${FIREBASE_PROJECT_ID:-}" && -n "${GITHUB_SHA:-}" && \
      -n "${STAGING_SUPABASE_URL:-}" && -n "${STAGING_SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  stage3_step "Staging読み取り専用スモーク"
  python3 scripts/staging_smoke.py
  stage3_staging_result="pass"
else
  stage3_step "Staging読み取り専用スモーク（Not Run）"
  printf '公開設定が未指定です。GitHub Actionsまたは記録済みの実測で補完してください。\n'
fi

printf '\nStage 3 automated checks completed.\n'
printf 'Golden: %s / Edge: %s / Database: %s / Staging: %s\n' \
  "$stage3_golden_result" "$stage3_edge_result" \
  "$stage3_database_result" "$stage3_staging_result"
printf 'Not RunはPassではありません。実機、複数端末、印刷、現場確認も別途必要です。\n'
