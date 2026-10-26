import difflib, pathlib, hashlib
pkg = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b17-paxi-native")
b15 = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b15-ddr-pace\r0\changed-src")
files = ["p2_ddr_bridge.v","camera_a1_uart_top.v","p2_a1_board_top.v","a1_uart_export.v",
         "f9p_camera_display_core.v","a1_ddr_slot_store.v","a1_ddr_arb2.v",
         "a1_frame_top.v","a1_deflate_core.v","a1_raw_crop.v","cam_diag_mailbox.v"]
out = []
hashes = []
for n in files:
    a = (b15/n).read_text(errors="replace").splitlines(keepends=True)
    b = (pkg/"r0/changed-src"/n).read_text(errors="replace").splitlines(keepends=True)
    d = list(difflib.unified_diff(a, b, fromfile="b15/r0/changed-src/"+n, tofile="b17/r0/changed-src/"+n))
    out.append("".join(d) if d else "### %s: byte-identical\n" % n)
    hashes.append("%s  %s" % (hashlib.sha256((pkg/"r0/changed-src"/n).read_bytes()).hexdigest().upper(), n))
(pkg/"r0/rtl-diff-r0.patch").write_text("".join(out))
(pkg/"r0/sim/changed-src-sha256.txt").write_text("\n".join(hashes)+"\n")
print("patch_bytes", (pkg/"r0/rtl-diff-r0.patch").stat().st_size)
print("\n".join(hashes))
