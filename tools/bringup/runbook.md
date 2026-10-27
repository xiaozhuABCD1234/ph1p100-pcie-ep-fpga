# R10F bring-up runbook (offline kit + future read channel)

Scope: this runbook is used only after the planner freezes a task and a channel
is available. The kit itself performs no hardware action. `parse_dump.py`,
`expected_rules.json` and the fixtures are offline.

## 1. Preconditions (all required)

1. Candidate identity is frozen: bit SHA256 `e81d353b284cb4e99ec86bcd7d511691cda187254f801c4832916f0000692b9a`,
   size 5,224,023 bytes, FPGA commit `ab811c8f820c3ae6601507b54ec45a74c6607855`.
2. A read channel from the matrix below has been demonstrated **read-only** in
   this session and recorded with a command log.
3. Safety boundary accepted: SRAM only, never write Flash, no cable/power/camera
   changes by the agent, single download <= 5 min, continuous capture <= 10 min,
   no visual criteria.
4. The board is not shared: no unexpected read-value jumps or link activity.

If a precondition is missing, stop with `blocked`; do not substitute a different
channel or a guessed command.

## 2. Channel matrix

| channel | current status | evidence | usable for |
|---|---|---|---|
| UART command file | unavailable | B1: 0 bytes on COM8; EP top ties uart rx=1 (L155/L757) | nothing |
| BW/JTAG cable | available for chain/device id/SRAM download | B1: `read_device_id`=PH1P100; `PRG-2014` | identity and bit load only |
| BW `JTAG_REG_ACCESS`/`JTAG_AXIS_APB_ACCESS` | unavailable | only command names in B1 log 03; no vendor doc found; no CWC core | nothing until documented |
| PCIe host BAR0 read | not available this round | no host/driver attached | register/memory read (preferred) |
| CWC/debug core | absent | candidate has no CWC product | register read (would need new bit) |

## 3. Procedure

### Step 0 - freeze and verify inputs (agent)
- Record operator, host, start time (Asia/Shanghai), bit path, SHA256 and size.
- Recompute SHA256:
  `Get-FileHash -Algorithm SHA256 <bit>` must equal the frozen value.
- Record "no cable/power/camera change" at the start and end.

### Step 1 - load or confirm the bit (agent, only if authorized)
- Use the B1 sequence: `hwserver` + `connect_cable -open` + `read_device_id` +
  `download -bit <ASCII_PATH> -mode jtag -spd 7 -cable 0` + `connect_cable -close`.
- Accept only `PRG-2014 : Chip validation success: PH1P100`, rc=0.
- Never use a flash/SPI/efuse/SVF command. Any such text in a script is a stop
  condition.

### Step 2 - confirm the read channel (agent)
- Run the channel's own read-only probe first. Record the exact command and raw
  response. Do not try `JTAG_REG_ACCESS` variants without documentation.
- If the probe returns no data twice, stop with `blocked`; do not blind-try.

### Step 3 - capture a register sample (agent)
- Read the offsets in `registers-plan.md` section 1, ideally in offset order.
- Save the raw output unchanged. Then convert it to the accepted dump format:
  one `0xOFFSET = 0xVALUE` line per register, `#` comments allowed.
- One sample per record; use a new record for each time point (duplicates in one
  file are rejected).

### Step 4 - evaluate offline (agent)
```
python tools/bringup/parse_dump.py regs <dump> \
  --rules tools/bringup/expected_rules.json \
  --out <run-record.json> --run-id <id> --operator <name> \
  --timestamp <ISO-8601>
```
Exit 0 = all evaluated rules pass; 1 = FAIL or BLOCKED; 2 = invalid input (no
record written). A missing reading is BLOCKED, not PASS.

### Step 5 - channel evidence (agent, optional)
```
python tools/bringup/parse_dump.py channel <bw-session.log> \
  --out <channel-record.json> --run-id <id> --operator <name> \
  --timestamp <ISO-8601>
```
This only proves device id / SRAM download / no-flash text. It never implies a
register value.

### Step 6 - archive (agent)
- Attach the record, raw dump, command log and SHA256 to the task manifest.
- Record unavailable items explicitly; do not turn "not measured" into a pass.

## 4. User-present items (agent must not perform)

| item | why user only |
|---|---|
| Physical power cycle / power-off | agent has no power control authorization |
| Cable, jumper, camera position or lens change | physical action, out of scope |
| HDMI image / LED / viewfinder observation | visual criteria are forbidden as evidence |
| Confirm camera A is connected | not machine-readable in the current bit |
| Approve a new bit with CWC/debug core | changes the frozen candidate |
| Approve a bring-up bit with rdx/lane loopback | requires wiring work |

## 5. Failure handling

- No read channel after two documented probes: `blocked` (not FAIL of the RTL).
- Identity mismatch (0x040 or 0x118/0x11C): stop, record, do not continue.
- Download failure: retry only with new evidence or corrected parameters; after
  one evidence-based retry, stop.
- Unexpected values on reserved bits: fail-closed; keep the raw dump and report.
- Any request to write Flash or change wiring: stop and escalate.

## 6. Read-channel recovery options (from dev-plan s9)

(a) Attach a PCIe host (RK or PC) and read BAR0; preferred.
(b) Authorize a new candidate bit with CWC/debug core; requires a new freeze and
    G1/G2, and the bit identity changes.
(c) Obtain vendor documentation for a read-only JTAG user-register path; only
    then may the planner dispatch a bounded read-only check.
(d) Authorize a bring-up bit with rdx/lane loopback; requires user wiring work.

Option (c) note: the 2026-10-18 doc check found no documentation for
`JTAG_REG_ACCESS` / `JTAG_AXIS_APB_ACCESS`; they remain unavailable.

## 7. Evidence checklist

- [ ] bit SHA256/size and commit
- [ ] operator, host, timezone, start/end time
- [ ] channel probe command + raw response
- [ ] raw dump unchanged
- [ ] run record (schema `run_record.schema.json`) with input SHA256
- [ ] exit code and summary counts
- [ ] unavailable items listed with reason
- [ ] no flash command, no physical change, no visual claim
- [ ] rollback: reload the same bit (volatile) or reverse the local commit
