import json, os
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
r = json.load(open(os.path.join(OUT, "evidence-metrics-recompute.json")))
for cls in ("N", "L"):
    m = r[cls]["metrics"]
    print(cls, "metrics:", {k: m.get(k) for k in (
        "S_ss", "tail_mean", "tail_frac", "sink_limited", "G0", "export_cycles_frame1_exact_2clk_per_B",
        "t_exp1_lower_bound", "t_exp1_over_wd", "t_exp1_over_wd_pct", "enc1_minus_t_pub1",
        "enc1_minus_1608000", "stream_len", "compression_ratio", "raw_crc_matches_content_bin")})
    print(cls, "stall:", r[cls]["metrics"]["stall"], "stats_bytes:", r[cls]["stats_bytes"])
print("dev_json_vs_tester:")
for cls, c in r["dev_json_vs_tester"].items():
    print(" ", cls, {k: (v["dev"], v["equal"]) for k, v in c.items()})
print("tester rerun:", json.dumps({k: r["tester_rerun_N"][k] for k in ("metrics", "log")}, default=str)[:900])
print("events equal:", {k: v["equal"] for k, v in r["tester_vs_dev_N_events"].items()})
print("tester header:", r["tester_rerun_N"]["header"])
