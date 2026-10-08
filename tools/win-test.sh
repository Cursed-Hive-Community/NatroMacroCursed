#!/usr/bin/env bash
#
# Run the AutoHotkey checks in the Windows VM, from the Mac.
#
# Three stages, each a wall the next does not run past:
#
#   1. nm-check.py        the local sieve - the four traps, encoding, dead code
#   2. /Validate          every owned file parsed in the VM; does it load
#   3. the self-tests     do the sockets, the protocol and the roster still work
#
# The point is that a claim becomes a fact without a human closing a dialog.
# Nothing here plays the game - the VM has no Roblox - so a green run means "it
# loads and the plumbing works", never "the macro plays correctly".
#
# Connection details live in tools/vm.env, which is gitignored:
#
#   VM_HOST=192.168.64.4
#   VM_USER=natro
#   VM_REPO=C:/natro          # forward slashes; this script converts them
#
# Usage:  tools/win-test.sh [--no-sync] [--validate-only]

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="tools/vm.env"
[ -f "$CONFIG" ] || { echo "missing $CONFIG - see the header of this script"; exit 2; }
# shellcheck disable=SC1090
source "$CONFIG"
: "${VM_HOST:?set VM_HOST in $CONFIG}"
: "${VM_USER:?set VM_USER in $CONFIG}"
: "${VM_REPO:?set VM_REPO in $CONFIG}"

SYNC=1
VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --no-sync) SYNC=0 ;;
    --validate-only) VALIDATE_ONLY=1 ;;
    *) echo "unknown argument: $arg"; exit 2 ;;
  esac
done

# LogLevel=ERROR hides the post-quantum notice SSH now prints to stderr on
# every connection, which the validate step would otherwise read as a fault
SSH="ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ${VM_USER}@${VM_HOST}"
# a Windows path with backslashes, for use inside cmd on the far end
WIN_REPO="${VM_REPO//\//\\}"

# the files this fork owns and therefore tests - the same set nm-check.py guards
FILES=(
  submacros/natro_macro.ahk
  lib/Socket.ahk lib/FleetProtocol.ahk lib/FleetRoster.ahk
  submacros/Fleet.ahk submacros/FleetSelfTest.ahk submacros/SocketSelfTest.ahk
)
while IFS= read -r f; do FILES+=("$f"); done < <(ls submacros/extensions/*.ahk)

# What to validate. Only the entry points - the scripts that are actually run -
# because #Include inlines a file at parse time, so validating natro_macro.ahk
# parses every library it pulls in. Validating an include-only file on its own
# both duplicates that and, for the extension files, hangs AutoHotkey outright.
ENTRY=(
  submacros/natro_macro.ahk
  submacros/Fleet.ahk
  submacros/SocketSelfTest.ahk
  submacros/FleetSelfTest.ahk
)

echo "== 1. local checks =="
python3 tools/nm-check.py

if [ "$SYNC" -eq 1 ]; then
  echo "== 2. sync to ${VM_USER}@${VM_HOST}:${VM_REPO} =="
  # copy each file to the matching path in the VM; directories already exist
  # because the repo is cloned there. scp one at a time keeps the mapping exact
  # and the failure message useful.
  for f in "${FILES[@]}"; do
    scp -q "$f" "${VM_USER}@${VM_HOST}:${VM_REPO}/${f}"
  done
  echo "   ${#FILES[@]} files copied"
fi

# the tests write their roster and logs into settings\, which is gitignored and
# therefore absent from a fresh checkout - the coordinator cannot load its
# roster without it, so make sure it exists before anything runs
$SSH "cd ${WIN_REPO} && if not exist settings mkdir settings" >/dev/null 2>&1 || true

echo "== 3. /Validate in the VM =="
fail=0
for f in "${ENTRY[@]}"; do
  winf="${f//\//\\}"
  # AHK writes the error to stdout with /ErrorStdOut and exits non-zero on a
  # parse error; silence and a zero code mean the file loads. The timeout guards
  # against a connection or an interpreter that hangs rather than answers.
  out=$(timeout 90 $SSH "cd ${WIN_REPO} && .\\submacros\\AutoHotkey64.exe /script /Validate /ErrorStdOut ${winf}" 2>&1 || true)
  if [ -n "$out" ]; then
    echo "   FAIL  $f"
    echo "$out" | sed 's/^/         /'
    fail=1
  else
    echo "   ok    $f"
  fi
done
[ "$fail" -eq 0 ] || { echo "validation failed - not running the tests"; exit 1; }

if [ "$VALIDATE_ONLY" -eq 1 ]; then
  echo "validation passed (tests skipped)"
  exit 0
fi

echo "== 4. self-tests in the VM =="
run_test() {
  local name="$1" script="$2" diag="$3"
  local code=0
  timeout 120 $SSH "cd ${WIN_REPO} && .\\submacros\\AutoHotkey64.exe /script ${script} /quiet" >/dev/null 2>&1 || code=$?
  if [ "$code" -eq 0 ]; then
    echo "   PASS  $name"
  else
    echo "   FAIL  $name"
    # the diagnostic file is the whole reason a headless failure is readable
    $SSH "type ${WIN_REPO}\\settings\\${diag}" 2>/dev/null | sed 's/^/         /' || true
    fail=1
  fi
}
run_test "socket" ".\\submacros\\SocketSelfTest.ahk" "socket_diag.txt"
run_test "fleet"  ".\\submacros\\FleetSelfTest.ahk"  "fleet_diag.txt"

[ "$fail" -eq 0 ] && echo "== all green ==" || { echo "== failures above =="; exit 1; }
