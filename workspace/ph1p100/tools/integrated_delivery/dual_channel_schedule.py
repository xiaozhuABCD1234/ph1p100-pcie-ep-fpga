#!/usr/bin/env python3
"""INT.P3 dual-channel capture scheduling reference oracle."""
import json


def simulate(events, a_enable=True, b_priority=False):
    a_busy = False
    b_busy = False
    last_sel = 0
    inflight = {"A": None, "B": None}
    accepted = 0
    completed = 0
    failed = 0
    rejected = 0
    held = []

    times = sorted(set(e["t"] for e in events))
    for t in times:
        tevents = [e for e in events if e["t"] == t]
        desc_a = [e for e in tevents if e["kind"] == "desc_a"]
        desc_b = [e for e in tevents if e["kind"] == "desc_b"]
        releases = [e for e in tevents if e["kind"] == "release"]

        a_pending = (not a_busy) and a_enable and len(desc_a) > 0 and (desc_a[0].get("camera_id", 0) == 0)
        b_pending = (not b_busy) and len(desc_b) > 0 and (desc_b[0].get("camera_id", 1) == 1)

        if b_pending and (b_priority or (not a_pending) or (last_sel == 0)):
            e = desc_b[0]
            b_busy = True
            inflight["B"] = {
                "camera_id": 1,
                "slot_id": e["slot_id"],
                "epoch": e["epoch"],
                "session": e["session"],
                "capture_seq": e["capture_seq"],
            }
            held.append(("B", e["capture_seq"]))
            accepted += 1
            last_sel = 1
        elif a_pending:
            e = desc_a[0]
            a_busy = True
            inflight["A"] = {
                "camera_id": 0,
                "slot_id": e["slot_id"],
                "epoch": e["epoch"],
                "session": e["session"],
                "capture_seq": e["capture_seq"],
            }
            held.append(("A", e["capture_seq"]))
            accepted += 1
            last_sel = 0

        for e in releases:
            cam = e["camera_id"]
            key = "A" if cam == 0 else "B"
            inf = inflight[key]
            busy = a_busy if cam == 0 else b_busy
            match = (busy and inf is not None and
                     inf["slot_id"] == e["slot_id"] and
                     inf["epoch"] == e["epoch"] and
                     inf["session"] == e["session"] and
                     inf["capture_seq"] == e["capture_seq"])
            if match:
                if cam == 0:
                    a_busy = False
                else:
                    b_busy = False
                inflight[key] = None
                if e.get("status", 0) == 0:
                    completed += 1
                else:
                    failed += 1
            else:
                rejected += 1

    return {
        "accepted": accepted,
        "completed": completed,
        "failed": failed,
        "rejected": rejected,
        "held": held,
        "a_busy_final": a_busy,
        "b_busy_final": b_busy,
    }


def selftest():
    ev = [{"t": 1, "kind": "desc_b", "camera_id": 1, "slot_id": 1, "epoch": 10, "session": 20, "capture_seq": 30},
          {"t": 2, "kind": "release", "camera_id": 1, "slot_id": 1, "epoch": 10, "session": 20, "capture_seq": 30, "status": 0}]
    r = simulate(ev, a_enable=False)
    assert r["held"] == [("B", 30)], r
    assert r["completed"] == 1, r

    ev = [{"t": 1, "kind": "desc_a", "camera_id": 0, "slot_id": 0, "epoch": 11, "session": 21, "capture_seq": 31},
          {"t": 1, "kind": "desc_b", "camera_id": 1, "slot_id": 1, "epoch": 12, "session": 22, "capture_seq": 32},
          {"t": 2, "kind": "desc_a", "camera_id": 0, "slot_id": 0, "epoch": 11, "session": 21, "capture_seq": 31},
          {"t": 2, "kind": "release", "camera_id": 1, "slot_id": 1, "epoch": 12, "session": 22, "capture_seq": 32, "status": 0},
          {"t": 3, "kind": "release", "camera_id": 0, "slot_id": 0, "epoch": 11, "session": 21, "capture_seq": 31, "status": 0}]
    r = simulate(ev, b_priority=True)
    assert [h[0] for h in r["held"]] == ["B", "A"], r
    assert r["completed"] == 2, r

    ev = [{"t": 1, "kind": "desc_a", "camera_id": 0, "slot_id": 0, "epoch": 13, "session": 23, "capture_seq": 33},
          {"t": 2, "kind": "release", "camera_id": 0, "slot_id": 0, "epoch": 999, "session": 23, "capture_seq": 33, "status": 0}]
    r = simulate(ev)
    assert r["rejected"] == 1, r
    assert r["a_busy_final"] is True, r

    print("DUAL_CHANNEL_SCHEDULE PASS")


if __name__ == "__main__":
    selftest()
    import sys
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            data = json.load(f)
        print(json.dumps(simulate(data.get("events", []), data.get("a_enable", True), data.get("b_priority", False)), indent=2))
