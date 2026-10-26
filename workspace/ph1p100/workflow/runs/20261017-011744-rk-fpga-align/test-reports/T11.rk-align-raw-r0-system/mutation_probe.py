# T11.rk-align-raw r0 / system tester — independent fail-closed mutation probes
# Creates mutated copies of the small synthetic sample and checks r10f_strict.py rejects each.
import json, os, subprocess, sys

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
EV = os.path.join(RUN, "test-reports", "T11.rk-align-raw-r0-system")
MUT = os.path.join(EV, "mutations")
os.makedirs(MUT, exist_ok=True)

src = open(os.path.join(RUN, "raw", "samples", "r10f-small-synthetic.dma"), "rb").read()
assert len(src) == 4096, len(src)

def w(name, data):
    p = os.path.join(MUT, name)
    open(p, "wb").write(data)
    return p

cases = {}
# M1 truncated (one byte short of dma_bytes)
cases["truncated"] = w("truncated.dma", src[:-1])
# M2 wrong magic
d = bytearray(src); d[0:4] = b"R0FR"; cases["bad_magic"] = w("bad_magic.dma", bytes(d))
# M3 non-zero tail (last byte of 640B tail)
d = bytearray(src); d[-1] = 0x01; cases["nonzero_tail"] = w("nonzero_tail.dma", bytes(d))
# M4 payload bit flip (middle of payload)
d = bytearray(src); d[128 + 1024] ^= 0x01; cases["payload_flip"] = w("payload_flip.dma", bytes(d))
# M5 header bit flip (roi_x low byte at 0x24)
d = bytearray(src); d[0x24] ^= 0x01; cases["header_flip"] = w("header_flip.dma", bytes(d))
# M6 codec != 0
d = bytearray(src); d[0x0C] = 1; cases["bad_codec"] = w("bad_codec.dma", bytes(d))

results = []
for name, path in cases.items():
    out = os.path.join(MUT, f"{name}.json")
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pcie_integration", "r10f_strict.py"),
                        "check", path, "--json-out", out],
                       capture_output=True, text=True)
    j = {}
    try:
        j = json.load(open(out, encoding="utf-8"))
    except Exception:
        pass
    results.append({"case": name, "exit": r.returncode, "ok": j.get("ok"), "errors": j.get("errors")})
    print(f"{name:14s} exit={r.returncode} ok={j.get('ok')} errors={j.get('errors')}")

# M7 wrong session (valid file, but caller expects different session)
r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pcie_integration", "r10f_strict.py"),
                    "check", os.path.join(RUN, "raw", "samples", "r10f-small-synthetic.dma"),
                    "--session", "0xDEADBEEF",
                    "--json-out", os.path.join(MUT, "wrong_session.json")],
                   capture_output=True, text=True)
j = json.load(open(os.path.join(MUT, "wrong_session.json"), encoding="utf-8"))
results.append({"case": "wrong_session", "exit": r.returncode, "ok": j.get("ok"), "errors": j.get("errors")})
print(f"{'wrong_session':14s} exit={r.returncode} ok={j.get('ok')} errors={j.get('errors')}")

json.dump(results, open(os.path.join(EV, "mutation-probes.json"), "w", encoding="utf-8"), indent=1)
all_rejected = all(x["exit"] != 0 and x["ok"] is False and x["errors"] for x in results)
print("ALL_REJECTED" if all_rejected else "SOME_ACCEPTED")
sys.exit(0 if all_rejected else 1)
