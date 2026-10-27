# T08 developer local result, round0

This is development evidence for the isolated offline candidate; independent integrated acceptance has not yet run.

Actual compiles: 4/4. Actual case processes: 19/20. All commands ended; no TD, hardware, mapping, download, Flash or production write was performed.

|Case|Observable scenario|Local outcome|
|---|---|---|
|0|normal six pairs and repeated slot reuse|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|1|last-byte I2C NACK, cleanup, restart|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|2|missing B and half-A abort, relock|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|3|common reset during real DDR write|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|4|explicit sync stop/restart and repeated warmup|simulation marker and independent actual-R byte oracle satisfied; 24 reads|
|5|reset after accepted/busy I2C before response|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|6|checked read-mask bit mismatch then common-reset recovery|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|7|non-mask read variation allowed|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|8|I2C never-busy launch timeout and recovery|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|9|I2C busy-never-completes timeout and recovery|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|10|actual AXI payload corruption, CRC fail, drain and good frames|simulation marker and independent actual-R byte oracle satisfied; 14 reads|
|11|abort while registered AR stalls; AR retained and drained|simulation marker and independent actual-R byte oracle satisfied; 14 reads|
|12|abort after accepted AR with delayed R, safe drain|simulation marker and independent actual-R byte oracle satisfied; 14 reads|
|13|permanent missing R locks all held ownership; common reset recovery|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|14|four protected slots full, drop whole frames, active mode change rejected|simulation marker and independent actual-R byte oracle satisfied; 12 reads|
|15|old epoch release rejection|simulation marker and independent actual-R byte oracle satisfied; 12 reads|

Auxiliary tb_dual_contract covers simultaneous A/B publication and descriptor transfer, stable stalled identities, wrong-camera/stale-epoch/duplicate release rejection and exact B/A release routing. Default DUAL_LOCAL_EN=0 original normal top runs and six independent R10F frame dumps are checked.

Normal case: A/B each six complete frames, 12 actual DDR reads, two-slot reuse and zero byte differences. Each sensor produced 201 initialization writes plus the exact sync requests, and 49 random-read replies. Each fault recovery completes another six good pairs; error acceptance is restricted to the explicitly injected case10 bytes.

The first normal attempt failed because the added expectation used word6 (mode) for session. Actual returned bytes and source inspection fixed this to word4, plus the per-frame flags reset. The second compile exposed a repeated-generator duplicate port insertion; generation now reads the verified original. All failed logs remain. The independent checker initially overestimated B role write count; exact pin/request equality and byte checking remain enforced.

G0/G1 are the requested offline scope. Full physical STA, resources/CDC, production IP binding, camera exposure timing, board recovery/stability/performance and G2/G3/G4 are not_run/awaiting_hardware. W8H2 runtime does not prove 1080p throughput; default W1920H1080 length/capacity boundaries are statically executed. The preserved reader processes eight 32-bit words per DDR beat and this candidate makes no production throughput claim.

Detailed sources and modifications: source-closure.json, candidate-changes.json, candidate.diff, sources.f, integration-sources.tcl. Environment replacement and clock/ownership contracts are recorded in interface-map.md. Exact commands, return codes, owned PIDs, deadlines and logs are in commands.json and per-command logs.

Rollback: stop adopting this isolated task directory. Production files and all planning-protected inputs remain unchanged.
