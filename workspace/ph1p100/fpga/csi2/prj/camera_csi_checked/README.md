# RAW10 CSI checked candidate

Isolated A-camera candidate generated on 2026-10-12. The original camera source and previously tested bitstreams are retained. Only the CSI packet/unpack modules and byte-keep wiring are overlaid; sensor mode, soft PHY, preview, DDR and 1080p60 display remain as before.

`LOCAL_STATE.json` identifies the actual D-drive project, final bit hash and validation boundary. No bitstream or TD database is tracked here. The candidate has passed RTL regressions and selected implementation gates; it has not been downloaded or board-verified.

- [Review and rework](../../../../docs/审查响应与返工_2026-10-12.md)
- [Single-camera download steps](../../../../docs/CSI接收返工_操作与预期_2026-10-12.md)
- [Evidence](../../../../docs/evidence/csi_review_rework_20261012.json)

CSI CRC16, late bad-frame rejection, full-resolution RAW10 addressing and dual-camera synchronization remain open. Positive STA has only 0.003 ns setup margin, and the route/reimport coverage difference and external HDMI electrical limits remain unresolved.
