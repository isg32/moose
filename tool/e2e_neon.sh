#!/usr/bin/env bash
# One phone, end to end on Neon and Firebase: Aatika is emulated in Python
# on this computer (tool/partner/partner.py), Moose runs on the connected
# phone, and they meet only through the deployed backend.
#
#   tool/e2e_neon.sh      (needs env.json, backend/.env.local, a phone on adb)
set -euo pipefail
cd "$(dirname "$0")/.."

py=tool/partner/.venv/bin/python
if [[ ! -x $py ]]; then
  python3 -m venv tool/partner/.venv
  $py -m pip install -q pynacl cryptography requests websocket-client pillow
fi
mkdir -p build
code_file=$(mktemp -u)

cleanup() {
  (cd backend && npm run --silent cleanup) || true
  rm -f "$code_file"
  kill "${granter:-0}" 2>/dev/null || true
}
trap cleanup EXIT

# The screen must stay on for the whole run (frames stop when it sleeps).
adb shell svc power stayon usb
adb shell input keyevent KEYCODE_WAKEUP
echo "· starting Aatika (Python)"
$py tool/partner/partner.py --code-file "$code_file" > build/e2e_partner.log 2>&1 &
partner=$!

for _ in $(seq 120); do [[ -s "$code_file" ]] && break; sleep 1; done
[[ -s "$code_file" ]] || { echo "Aatika never made a code"; cat build/e2e_partner.log; exit 1; }
code=$(cat "$code_file")
echo "· her code: $code. Running Moose on the phone"

# Android 13+ asks before showing notifications; a test can't tap the
# system dialog, so grant it as soon as the build is installed.
( for _ in $(seq 600); do
    adb shell pm grant com.isg32.moose android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 &&
      adb shell pm grant com.isg32.moose android.permission.RECORD_AUDIO >/dev/null 2>&1 &&
      adb shell pm grant com.isg32.moose android.permission.CAMERA >/dev/null 2>&1 && break
    sleep 1
  done ) &
granter=$!

phone=0
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/neon_test.dart \
  --dart-define-from-file=env.json \
  --dart-define=PARTNER_CODE="$code" || phone=$?

# If the phone gave up, Aatika has no one to talk to.
[[ $phone == 0 ]] || kill "$partner" 2>/dev/null || true
echo "· waiting for Aatika"
status=0
wait "$partner" || status=$?
grep '\[aatika' build/e2e_partner.log || true
echo "· phone: $([[ $phone == 0 ]] && echo passed || echo FAILED) · Aatika: $([[ $status == 0 ]] && echo passed || echo FAILED)"
[[ $phone == 0 && $status == 0 ]]
