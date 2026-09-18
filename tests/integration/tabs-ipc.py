#!/usr/bin/env python3
"""Instance-scoped IPC client for the plugin's tabs/snap verbs.

Why this exists: the documented CLI (`omarchy-shell tech.loopedmatrix.ohmtabs <verb>`)
forwards to the RUNNING Omarchy shell, so it can only ever address the plugin in
the user's live session. A nested-rig test must not do that -- it would drive the
live desktop instead of the instance under test. This talks to the plugin's own
backend socket, which is resolved from HYPRLAND_INSTANCE_SIGNATURE.

Usage:
  tabs-ipc.py tabs.list
  tabs-ipc.py tabs.join '{"source":"<token>","host":"<token>"}'
  tabs-ipc.py tabs.activate '{"group":1,"index":0}'
  tabs-ipc.py tabs.detach '{"token":"<token>"}'
  tabs-ipc.py tabs.ungroup '{"group":1}'
  tabs-ipc.py tabs.closeAll '{"group":1,"confirm":true}'
  tabs-ipc.py snap.status
  tabs-ipc.py status
  tabs-ipc.py windows

Prints one JSON line: the reply's json= payload where the verb carries one
(tabs.list, snap.status, status), the window records for `windows`, or an
{"error": ...} object. Exit code 0 on success, 4 on an error reply, 3 on no reply.

Wire contract (frozen):
  tabs   verb=list           -> tabsList {"groups":[{id,host,active,tabs:[...]}]}
  tabs   verb=<other>        -> result   {verb,status,error}
  snap.status                -> snapStatus {"dragging":bool,"zone":"...","glow":bool}
  snapshot                   -> window* then snapshotEnd
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "helpers"))

import ohmtabs_backend as gb  # noqa: E402

TABS_VERBS = {"list", "join", "activate", "detach", "ungroup", "closeAll"}


def out(obj):
    sys.stdout.write(json.dumps(obj, sort_keys=True) + "\n")


def main(argv):
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        out({"error": "HYPRLAND_INSTANCE_SIGNATURE is not set - refusing to guess the instance"})
        return 2

    verb = argv[0]
    payload = json.loads(argv[1]) if len(argv) > 1 and argv[1].strip() else {}

    c = gb.BackendClient(timeout=float(os.environ.get("TABS_TIMEOUT", "5")))
    c.connect(role=os.environ.get("TABS_ROLE", "observer"))
    try:
        if verb == "windows":
            c.send("snapshot")
            while True:
                m = c.wait("window", alt=("snapshotEnd", "error"))
                if m is None:
                    out({"error": "no reply"})
                    return 3
                if m.get("type") == "snapshotEnd":
                    return 0
                if m.get("type") == "error":
                    out({"error": m})
                    return 4
                out(m)

        if verb.startswith("tabs."):
            name = verb.split(".", 1)[1]
            if name not in TABS_VERBS:
                out({"error": "unknown tabs verb %r" % name})
                return 2
            c.send("tabs", verb=name, **{k: v for k, v in payload.items()})
            m = c.wait("tabsList" if name == "list" else "result", alt=("error",))
        elif verb == "snap.status":
            c.send("snap.status")
            m = c.wait("snapStatus", alt=("error",))
        elif verb == "status":
            c.send("status")
            m = c.wait("status", alt=("error",))
        else:
            out({"error": "unknown verb %r" % verb})
            return 2

        if m is None:
            out({"error": "no reply"})
            return 3
        if m.get("type") == "error":
            out({"error": m.get("reason", "error")})
            return 4
        if m.get("json"):
            sys.stdout.write(m["json"] + "\n")
            return 0
        out({k: v for k, v in m.items() if k != "type"})
        return 0
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
