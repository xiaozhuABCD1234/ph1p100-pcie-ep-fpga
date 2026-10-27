#!/usr/bin/env python3
"""mk_diff_b9.py -- emit r0/rtl-diff-r0.patch (b9 candidate vs the frozen base).

Base per file:
  camera_a1_uart_top.v / a1_uart_export.v / a1_raw_crop.v / cam_diag_mailbox.v
      T10.b8-crop-geom/r0/changed-src/<file>
  a1_ddr_slot_store.v
      fpga/csi2/src/a1/a1_ddr_slot_store.v   (repo file used by the b8 build)
  p2_ddr_bridge.v / p2_a1_board_top.v
      T10.b8-crop-geom/r0/td/src/<file>
"""
import difflib
import pathlib

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
B8 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom"
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore"

PAIRS = [
    ("changed-src/a1_raw_crop.v", B8 / "r0/changed-src/a1_raw_crop.v"),
    ("changed-src/camera_a1_uart_top.v", B8 / "r0/changed-src/camera_a1_uart_top.v"),
    ("changed-src/a1_uart_export.v", B8 / "r0/changed-src/a1_uart_export.v"),
    ("changed-src/cam_diag_mailbox.v", B8 / "r0/changed-src/cam_diag_mailbox.v"),
    ("changed-src/a1_deflate_core.v", B8 / "r0/changed-src/a1_deflate_core.v"),
    ("changed-src/a1_ddr_slot_store.v", ROOT / "fpga/csi2/src/a1/a1_ddr_slot_store.v"),
    ("td/src/p2_ddr_bridge.v", B8 / "r0/td/src/p2_ddr_bridge.v"),
    ("td/src/p2_a1_board_top.v", B8 / "r0/td/src/p2_a1_board_top.v"),
]

out = ["# T10.b9-rawstore r0 -- RTL diff against the frozen b8 baseline",
       "# (unchanged copies are included on purpose: the patch is the complete",
       "#  set of files the b9 build compiles from this package)",
       ""]
for rel, base in PAIRS:
    new = PKG / "r0" / rel
    a = base.read_text(errors="replace").splitlines(keepends=True)
    b = new.read_text(errors="replace").splitlines(keepends=True)
    d = list(difflib.unified_diff(a, b, fromfile="b8-base/" + rel, tofile="b9/" + rel, n=3))
    out.append("## %s  (%s)" % (rel, "UNCHANGED" if not d else "CHANGED"))
    out.extend(d)
    out.append("")

(PKG / "r0/rtl-diff-r0.patch").write_text("".join(out), encoding="utf-8")
changed = [l for l in out if l.startswith("## ")]
print("\n".join(changed))
