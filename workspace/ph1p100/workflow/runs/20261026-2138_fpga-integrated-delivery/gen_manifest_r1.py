import hashlib, json, os

root = "D:/fpga/ph1p100"
prod = [
    "fpga/csi2/src/integrated_delivery/dual_channel_capture_scheduler.v",
    "fpga/csi2/src/integrated_delivery/tb_dual_channel_capture_scheduler.v",
]
tools = [
    "tools/integrated_delivery/dual_channel_schedule.py",
    "tools/integrated_delivery/gen_manifest_intp3.py",
]

def sha(p):
    h = hashlib.sha256()
    full = os.path.join(root, p.replace("/", os.sep))
    with open(full, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest(), os.path.getsize(full)

manifest = {
    "schema": 1,
    "task_id": "INT.P3",
    "round": 1,
    "candidate_root": "fpga/csi2/src/integrated_delivery",
    "production_inputs": [],
    "tool_inputs": [],
    "test_inputs": [],
    "local_checks": {
        "rtl_compile": "vlog -lint dual_channel_capture_scheduler.v -> 0 errors 0 warnings",
        "tb_sim_dev": "vsim tb_dual_channel_capture_scheduler -> TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS",
        "tb_sim_bp": "vsim tb_bp -> o_capture_seq held at 3 under stall; BP DONE accepted=1",
        "tb_sim_independent": "vsim tb_independent -> TB_INDEPENDENT PASS",
        "schedule_oracle": "python tools/integrated_delivery/dual_channel_schedule.py -> DUAL_CHANNEL_SCHEDULE PASS"
    },
    "stopped_modifying": True,
    "notes": [
        "INT.P3 round1: fixed valid/ready stall gating: a_can/b_can now require !(o_valid && !o_ready); accept block held while output stalled.",
        "A real b20 timing result still not available; A path remains gated by a_enable, marked pending (待 b20 有效结果).",
        "G2 synthesis/STA/CDC/resources deferred to INT.P4; G3/G4 not applicable (no board window)."
    ]
}

for p in prod:
    s, z = sha(p)
    manifest["production_inputs"].append({"path": p, "sha256": s, "size": z})
for p in tools:
    s, z = sha(p)
    manifest["tool_inputs"].append({"path": p, "sha256": s, "size": z})

out = "workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P3-r1-manifest.json"
with open(os.path.join(root, out), "w") as f:
    json.dump(manifest, f, indent=2)
print(out)