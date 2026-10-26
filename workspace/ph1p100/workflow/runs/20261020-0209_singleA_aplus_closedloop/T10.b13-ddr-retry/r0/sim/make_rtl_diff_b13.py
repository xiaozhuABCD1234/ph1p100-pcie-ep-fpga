"""Regenerate r0/rtl-diff-r0.patch (b12 r0 baseline -> b13 r0 changed-src)."""
import difflib
import pathlib

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b13-ddr-retry"
CS = PKG / "r0/changed-src"
B12 = RUN / "T10.b12-r1-last/r0/changed-src"

PAIRS = [
    ("a1_ddr_slot_store.v", B12 / "a1_ddr_slot_store.v"),
    ("a1_uart_export.v", B12 / "a1_uart_export.v"),
    ("camera_a1_uart_top.v", B12 / "camera_a1_uart_top.v"),
    ("p2_ddr_bridge.v", B12 / "p2_ddr_bridge.v"),
    ("p2_a1_board_top.v", B12 / "p2_a1_board_top.v"),
    ("a1_ddr_arb2.v", ROOT / "fpga/csi2/src/a1/a1_ddr_arb2.v"),
]
out = []
for name, base in PAIRS:
    a = base.read_text(errors="replace").splitlines(keepends=True)
    b = (CS / name).read_text(errors="replace").splitlines(keepends=True)
    out.extend(difflib.unified_diff(a, b, fromfile="b12-r0/" + name,
                                    tofile="b13-r0/" + name))
(PKG / "r0/rtl-diff-r0.patch").write_text("".join(out))
print("diff lines:", len(out))
