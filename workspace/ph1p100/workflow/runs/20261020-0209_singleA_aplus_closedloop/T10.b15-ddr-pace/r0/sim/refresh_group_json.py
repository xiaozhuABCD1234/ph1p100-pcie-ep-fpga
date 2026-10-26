#!/usr/bin/env python3
"""refresh_group_json.py -- re-import a case's result.json into its group JSON.

Used after a checker-only fix (no RTL / no re-simulation): the simulation evidence
in cases/<group>/<case>/ is untouched, only the interpretation is refreshed.
"""
import json
import pathlib
import sys

SIM = pathlib.Path(__file__).resolve().parent


def main(groupfile, case, case_dir):
    gp = SIM / groupfile
    j = json.loads(gp.read_text())
    r = json.loads((pathlib.Path(case_dir) / "result.json").read_text())
    key = "chain_" + case if "chain_" + case in j else case
    e = j[key]
    e["status"] = r.get("status")
    e["errors"] = r.get("errors")
    e["stats"] = r.get("stats")
    e["b15"] = r.get("b15")
    e["check_rerun"] = True
    gp.write_text(json.dumps(j, indent=2))
    print("%s[%s] -> %s errors=%s" % (groupfile, key, e["status"], e["errors"]))


if __name__ == "__main__":
    main(*sys.argv[1:4])
