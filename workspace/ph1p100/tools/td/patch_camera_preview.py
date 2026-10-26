"""Apply two proven arithmetic fixes and explicit synchronous per-bank RAM reads."""
from pathlib import Path
import hashlib
import json

root = Path(r"D:\TD\work\csi2\prj\camera_peer")
target = root / "uisrc/01_rtl/cam_preview.v"
manifest = json.loads((root / "UPSTREAM_MANIFEST.json").read_text(encoding="utf-8"))
expected = next(f["upstream_sha256"] for f in manifest["files"] if f["path"] == "uisrc/01_rtl/cam_preview.v")
data = target.read_bytes()
assert hashlib.sha256(data).hexdigest() == expected, "Only patch the untouched upstream file"
archive = root / "_evidence" / "upstream_build"
archive.mkdir(parents=True, exist_ok=True)
for rel in ["syn_1/run.log", "syn_1/fpga_prj_gate.area", "phy_1/run.log"]:
    src = root / "fpga_prj_Runs" / rel
    dst = archive / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        assert dst.read_bytes() == src.read_bytes(), "Preserve earlier build evidence"
    else:
        dst.write_bytes(src.read_bytes())
replacements = [
    (b"w_hsum[9:2]", b"w_hsum[10:3]"),
    (b"((r_line_buf[r_col] + w_havg) >> 1)",
     b"(({1'b0, r_line_buf[r_col]} + {1'b0, w_havg}) >> 1)"),
]
for old, new in replacements:
    assert data.count(old) == 1
    data = data.replace(old, new)
for bank in range(4):
    old = f"reg  [7:0] r_fb{bank} [0:RPB*SW-1];".encode()
    assert data.count(old) == 1
    data = data.replace(old, b'(* ram_style = "bram" *) ' + old)
text = data.decode("utf-8")
start = text.index("    // 4 ", text.index("r_raddr <= r_rsbase"))
end = text.index("    // ", text.index("always @(posedge I_pclk) r_rd_data <= w_rd_data;", start) + 1)
replacement = """    // Synchronous read on EACH RAM before the bank mux. TD 6.2.2 cannot
    // robustly infer ERAM without an explicit ram_style and per-bank read FFs.
    // Preserve the existing address->data latency and bank selection cycle.
    reg [7:0] r_rd0, r_rd1, r_rd2, r_rd3;
    reg [1:0] r_rd_bank = 2'd0;
    always @(posedge I_pclk) begin
        r_rd0 <= r_fb0[r_raddr];
        r_rd1 <= r_fb1[r_raddr];
        r_rd2 <= r_fb2[r_raddr];
        r_rd3 <= r_fb3[r_raddr];
        r_rd_bank <= r_rbank;
    end
    wire [7:0] r_rd_data = (r_rd_bank == 2'd0) ? r_rd0 :
                           (r_rd_bank == 2'd1) ? r_rd1 :
                           (r_rd_bank == 2'd2) ? r_rd2 : r_rd3;

"""
# Match upstream line endings; preserve every byte outside these local edits.
replacement = replacement.replace("\n", "\r\n") if "\r\n" in text else replacement
text = text[:start] + replacement + text[end:]
target.write_bytes(text.encode("utf-8"))
print("PATCHED cam_preview.v: horizontal scale, vertical carry, synchronous bank reads")
