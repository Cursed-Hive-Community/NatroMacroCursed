#!/usr/bin/env bash
#
# Run the AutoHotkey checks in the Windows VM, from the Mac.
#
#   tools/win-test.sh                      everything: validate all entry points,
#                                          run both self-tests
#   tools/win-test.sh lib/Socket.ahk ...   only what those files can break
#   tools/win-test.sh --changed            whatever git says is modified
#   tools/win-test.sh --no-sync            skip the copy when the VM is current
#   tools/win-test.sh --validate-only      stop before the self-tests
#
# Targeting is the point of the file arguments. A change to an include is a
# change to everything that pulls it in, so the script maps each file to the
# entry points that validate it and the self-tests that exercise it, and runs
# only those. Touch one extension and it re-validates natro_macro.ahk alone,
# runs no test, and is done in a fraction of the time.
#
# Why entry points and not every file: #Include inlines a library at parse time,
# so validating natro_macro.ahk parses everything it pulls in. Validating an
# include-only file on its own is redundant and, for the extension files, hangs
# AutoHotkey outright.
#
# The VM proves the code loads and the plumbing works. It has no Roblox, so it
# never proves the macro plays correctly - that stays the user's to check.
#
# Connection details live in tools/vm.env, gitignored:
#   VM_HOST=192.168.64.7
#   VM_USER=Jchaipas
#   VM_REPO=C:/natro

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="tools/vm.env"
[ -f "$CONFIG" ] || { echo "missing $CONFIG - see the header of this script"; exit 2; }
# shellcheck disable=SC1090
source "$CONFIG"
: "${VM_HOST:?set VM_HOST in $CONFIG}"
: "${VM_USER:?set VM_USER in $CONFIG}"
: "${VM_REPO:?set VM_REPO in $CONFIG}"

# --- what covers what -------------------------------------------------------
# For each entry point and each self-test, the owned files it depends on. A
# changed file selects every entry/test whose list contains it. Update these
# when an #Include changes - nm-check.py's own file list is the full set.

COVER_natro="submacros/natro_macro.ahk lib/Socket.ahk lib/FleetProtocol.ahk lib/FleetRoster.ahk submacros/extensions/boostlease.ahk submacros/extensions/interrupts.ahk submacros/extensions/fleet.ahk"
COVER_fleet="submacros/Fleet.ahk lib/Socket.ahk lib/FleetProtocol.ahk lib/FleetRoster.ahk"
COVER_sockettest="submacros/SocketSelfTest.ahk lib/Socket.ahk"
COVER_fleettest="submacros/FleetSelfTest.ahk lib/Socket.ahk lib/FleetProtocol.ahk lib/FleetRoster.ahk submacros/Fleet.ahk"

# entry point -> coverage var
ENTRY_FILES="submacros/natro_macro.ahk:COVER_natro submacros/Fleet.ahk:COVER_fleet submacros/SocketSelfTest.ahk:COVER_sockettest submacros/FleetSelfTest.ahk:COVER_fleettest"
# self-test -> name:script:diagfile:coverage var
TEST_SPECS="socket:submacros/SocketSelfTest.ahk:socket_diag.txt:COVER_sockettest fleet:submacros/FleetSelfTest.ahk:fleet_diag.txt:COVER_fleettest"

# every owned file, for the full-run default
ALL_FILES=(
  submacros/natro_macro.ahk
  lib/Socket.ahk lib/FleetProtocol.ahk lib/FleetRoster.ahk
  submacros/Fleet.ahk submacros/FleetSelfTest.ahk submacros/SocketSelfTest.ahk
  submacros/extensions/boostlease.ahk submacros/extensions/interrupts.ahk submacros/extensions/fleet.ahk
)

# --- arguments --------------------------------------------------------------
SYNC=1
VALIDATE_ONLY=0
USE_GIT=0
TARGETS=()
for arg in "$@"; do
  case "$arg" in
    --no-sync) SYNC=0 ;;
    --validate-only) VALIDATE_ONLY=1 ;;
    --changed) USE_GIT=1 ;;
    --*) echo "unknown flag: $arg"; exit 2 ;;
    *) TARGETS+=("$arg") ;;
  esac
done

# whether the caller asked for a subset at all - a bare invocation means the
# whole suite, but "--changed" or named files that resolve to nothing means
# nothing, not everything
EXPLICIT=0
[ "${#TARGETS[@]}" -gt 0 ] && EXPLICIT=1
if [ "$USE_GIT" -eq 1 ]; then
  EXPLICIT=1
  while IFS= read -r f; do [ -n "$f" ] && TARGETS+=("$f"); done \
    < <(git diff --name-only HEAD -- '*.ahk')
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  if [ "$EXPLICIT" -eq 1 ]; then
    echo "nothing changed - nothing to test"
    exit 0
  fi
  TARGETS=("${ALL_FILES[@]}")   # bare invocation: the whole suite
fi

# keep only owned files; anything else these tests cannot cover
CHANGED=()
for t in "${TARGETS[@]}"; do
  for o in "${ALL_FILES[@]}"; do
    [ "$t" = "$o" ] && CHANGED+=("$t")
  done
done
if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "none of the given files are tested here - nothing to do"
  echo "  (the suite covers: ${ALL_FILES[*]})"
  exit 0
fi

# does a space-separated list share any element with CHANGED?
intersects() {
  local item changed
  for item in $1; do
    for changed in "${CHANGED[@]}"; do
      [ "$item" = "$changed" ] && return 0
    done
  done
  return 1
}

echo "targeting: ${CHANGED[*]}"

# --- run --------------------------------------------------------------------
SSH="ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ${VM_USER}@${VM_HOST}"
WIN_REPO="${VM_REPO//\//\\}"

echo "== 1. local checks =="
python3 tools/nm-check.py

if [ "$SYNC" -eq 1 ]; then
  echo "== 2. sync the changed files =="
  for f in "${CHANGED[@]}"; do
    scp -q -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new "$f" "${VM_USER}@${VM_HOST}:${VM_REPO}/${f}"
  done
  echo "   ${#CHANGED[@]} copied"
fi

# the tests write their roster and logs into settings\, gitignored and so absent
# from a fresh checkout; the coordinator cannot load its roster without it
$SSH "cd ${WIN_REPO} && if not exist settings mkdir settings" >/dev/null 2>&1 || true

echo "== 3. /Validate the affected entry points =="
fail=0
ran_validate=0
for spec in $ENTRY_FILES; do
  entry="${spec%%:*}"; covervar="${spec##*:}"
  intersects "${!covervar}" || continue
  ran_validate=1
  winf="${entry//\//\\}"
  out=$(timeout 90 $SSH "cd ${WIN_REPO} && .\\submacros\\AutoHotkey64.exe /script /Validate /ErrorStdOut ${winf}" 2>&1 || true)
  if [ -n "$out" ]; then
    echo "   FAIL  $entry"
    echo "$out" | sed 's/^/         /'
    fail=1
  else
    echo "   ok    $entry"
  fi
done
[ "$ran_validate" -eq 1 ] || echo "   (no entry point depends on these files)"
[ "$fail" -eq 0 ] || { echo "validation failed - not running the tests"; exit 1; }

if [ "$VALIDATE_ONLY" -eq 1 ]; then
  echo "validation passed (tests skipped)"
  exit 0
fi

echo "== 4. the affected self-tests =="
ran_test=0
for spec in $TEST_SPECS; do
  IFS=: read -r name script diag covervar <<<"$spec"
  intersects "${!covervar}" || continue
  ran_test=1
  winscript="${script//\//\\}"
  code=0
  timeout 120 $SSH "cd ${WIN_REPO} && .\\submacros\\AutoHotkey64.exe /script .\\${winscript} /quiet" >/dev/null 2>&1 || code=$?
  if [ "$code" -eq 0 ]; then
    echo "   PASS  $name"
  else
    echo "   FAIL  $name"
    $SSH "type ${WIN_REPO}\\settings\\${diag}" 2>/dev/null | sed 's/^/         /' || true
    fail=1
  fi
done
[ "$ran_test" -eq 1 ] || echo "   (no self-test exercises these files - validation only)"

[ "$fail" -eq 0 ] && echo "== all green ==" || { echo "== failures above =="; exit 1; }
