#!/usr/bin/env bash
# Offline test suite: pure model, recovery journal helper, backend protocol
# client, syntax checks, and the Omarchy manifest validator when available.
# Needs node, python3 and Lua. The native backend and the nested-compositor
# scenarios (tests/integration) are run separately; see docs/QUALIFICATION.md.
set -euo pipefail
cd "$(dirname "$0")/.."
node tests/unit/test_model.js
python3 tests/unit/test_journal.py
python3 tests/unit/test_autoload.py
python3 tests/unit/test_loader.py
python3 tests/unit/test_startup_selection.py
python3 tests/unit/test_protocol.py
# Native pure-logic unit tests: the snap zone decider (incl. the strip reserve
# that keeps a snapped strip out from under the Omarchy bar) and the glow
# state machine. Header-only, no Hyprland, no compositor, no session.
g++ -std=c++20 -Wall -Wno-unused-parameter -I native/ohmtabs \
  native/ohmtabs/tests/test_snapfx.cpp -o /tmp/ohmtabs-test_snapfx
/tmp/ohmtabs-test_snapfx
# Window-tab model (TabStore): pure logic, no Hyprland, compiled with -Werror.
bash tests/unit/run_tabs_test.sh
python3 -m py_compile helpers/ohmtabs-journal helpers/ohmtabs_backend.py
bash -n bin/ohmtabs tests/integration/*.sh
# The virtual-pointer tool drives real drags in the nested scenarios; without it
# those tests silently no-op'ed, so build it as part of the suite.
bash tests/integration/vpointer/build.sh
if command -v qmllint >/dev/null 2>&1; then
  # Host modules (qs.Commons, qs.Ui, Quickshell.*) are not resolvable offline;
  # only syntax-level problems are reported.
  for f in Service.qml BarWidget.qml Panel.qml; do
    if qmllint "$f" 2>&1 | grep -E '^Error' | grep -viE 'import|module' | grep -q .; then
      echo "qmllint: $f has syntax problems"; qmllint "$f" 2>&1 | grep -E '^Error' | head -20; exit 1
    fi
  done
fi
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi
echo "ok"
