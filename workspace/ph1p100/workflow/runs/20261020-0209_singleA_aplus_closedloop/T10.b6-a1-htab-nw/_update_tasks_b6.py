import json
import shutil

p = r'D:\fpga\ph1p100\workflow\tasks.json'
b = r'D:\fpga\ph1p100\workflow\tasks.json.before-20261024-b6.json'
shutil.copyfile(p, b)
with open(p, encoding='utf-8') as f:
    d = json.load(f)
t = next(x for x in d['tasks'] if x['id'] == 'T10')
t['state'] = 'active'
note = (
    " | 2026-10-24: T10.b6-a1-htab-nw r0 frozen and dispatched (throughput repair after b5 r0; "
    "b5 P2 comp 374,461 cycles / 76.91 MB/s FAIL, +19,200 cycles = +1/match). "
    "Plan: one-cycle-early htab p3v shadow read (plus one bm_a prefetch stage if needed) feeding bm_b_spec_q, "
    "restore r4 hit-cycle first-byte compare, remove S_EXT ext_first wait; only a1_deflate_core.v changes. "
    "Acceptance: P2 comp exactly 355,261 cycles / 81.067 MB/s and stream SHA 2601d57c...a7c05; "
    "P2 rand SHA 54f262f2...496dd; P1 three byte-identical (fa513a2b/ee61e620/b992a8ad); "
    "Routed zero violations WNS >= +0.05 (caveat), 1 bitgen + 1 CWC, no download. "
    "Budget: dev 90 min/50 calls; TD 3 sessions/150 min, synth <=3, route <=2, bitgen 1, CWC 1, download 0; tester 45/30. "
    "Camera cap_frames=0 is a separate issue and is not mixed in. "
    "Paths: workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/"
    "{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json,user-summary.md,final-summary.md}."
)
if 'T10.b6-a1-htab-nw' not in t.get('status_note', ''):
    t['status_note'] = t.get('status_note', '') + note
old_blocker = t.get('blocker', '')
if 'T10.b6-a1-htab-nw' not in old_blocker:
    t['blocker'] = (
        'b6 active (throughput repair; P2 comp 355,261 target, Routed >= +0.05, no download); '
        + old_blocker
    )
ev = t.setdefault('latest_evidence', [])
for x in [
    'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/dev-plan.md',
    'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/dispatch.json',
    'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/result-r0.md',
]:
    if x not in ev:
        ev.append(x)
with open(p, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print('T10 state:', t['state'])
print('note appended:', 'T10.b6-a1-htab-nw' in t['status_note'])
print('blocker has b6:', 'T10.b6-a1-htab-nw' in t['blocker'])
print('evidence count:', len(ev))
