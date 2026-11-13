#!/usr/bin/env bash
# One phone, end to end on Neon: the partner bot (Aatika) runs here, the
# app runs on the connected phone, and they meet through the backend.
#
#   tool/e2e_neon.sh            (needs env.json, backend/.env.local, a phone)
set -euo pipefail
cd "$(dirname "$0")/.."

code_file=$(mktemp)
rm -f "$code_file"
export MOOSE_API_URL=$(python3 -c 'import json;print(json.load(open("env.json"))["MOOSE_API_URL"])')
export MOOSE_AUTH_URL=$(python3 -c 'import json;print(json.load(open("env.json"))["MOOSE_AUTH_URL"])')

cleanup() { (cd backend && npm run --silent cleanup) || true; rm -f "$code_file"; }
trap cleanup EXIT

echo "· starting the partner bot"
BOT_CODE_FILE="$code_file" flutter test test/neon/partner_bot_test.dart \
  --reporter expanded > build/e2e_bot.log 2>&1 &
bot=$!

for _ in $(seq 120); do [[ -s "$code_file" ]] && break; sleep 1; done
[[ -s "$code_file" ]] || { echo "the bot never made a code"; cat build/e2e_bot.log; exit 1; }
code=$(cat "$code_file")
echo "· bot's code: $code — running the app on the phone"

phone=0
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/neon_test.dart \
  --dart-define-from-file=env.json \
  --dart-define=PARTNER_CODE="$code" || phone=$?

echo "· waiting for the bot"
botstatus=0
wait "$bot" || botstatus=$?
grep '\[bot' build/e2e_bot.log || true
tail -3 build/e2e_bot.log
echo "· phone: $([[ $phone == 0 ]] && echo passed || echo FAILED) · bot: $([[ $botstatus == 0 ]] && echo passed || echo FAILED)"
[[ $phone == 0 && $botstatus == 0 ]]
