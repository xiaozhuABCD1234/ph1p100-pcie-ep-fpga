# tools/bringup - R10F offline bring-up kit

Offline only. The kit never touches hardware, never downloads a bit, and writes
only to the `--out` path given by the caller. It is the dump/verdict half of the
board-validation workflow; the board half is the BW/JTAG sequence in
`runbook.md`.

## Files

| file | purpose |
|---|---|
| `parse_dump.py` | register dump / channel log parser and verdict engine (fail-closed) |
| `expected_rules.json` | 17 frozen expectations with source references |
| `registers-plan.md` | full register table, command templates, unavailable items |
| `run_record.schema.json` | frozen JSON schema of one run record |
| `runbook.md` | operator procedure, safety boundary, recovery options |
| `fixtures/dump-positive.txt` | synthetic valid post-capture snapshot (all rules pass) |
| `fixtures/neg-*.txt` | negative fixtures that must be rejected |
| `fixtures/neg-channel-flash.log` | channel log containing a flash command (must fail) |

The real B1 log copy used for the channel dry-run is kept in the run evidence
directory (`bringup-kit/fixtures/b1-real-channel.log`) because it contains local
paths; it is not copied into the repository.

## Requirements

- Python 3.11.5 (standard library only; no packages).
- Optional: PowerShell for the CRC commands below.
- No network, no hardware, no absolute paths inside the scripts.

## Usage

```
python tools/bringup/parse_dump.py regs <dump.txt|dump.json> \
  --rules tools/bringup/expected_rules.json \
  --out run-record.json --run-id <id> --operator <name> --timestamp <ISO-8601>

python tools/bringup/parse_dump.py channel <bw-session.log> \
  --out channel-record.json --run-id <id> --operator <name> --timestamp <ISO-8601>
```

Exit codes: `0` all evaluated checks pass (not_applicable allowed),
`1` at least one FAIL or BLOCKED, `2` invalid input (no record written).
A missing reading is BLOCKED, never PASS; a false `when` precondition is
NOT_APPLICABLE.

Text dump format: one `0xOFFSET = 0xVALUE` line per register (`0xOFFSET VALUE`
and `:`/`,` separators are accepted; bare 3-digit offsets are hexadecimal).
Values without `0x` are decimal. Duplicate offsets are rejected. JSON input may
be `{"readings":[...]}`, `{"registers":{...}}` or a flat offset map.

Deterministic reruns: pass a fixed `--timestamp`; the record then depends only
on the input bytes. Encoding policy: dumps must be UTF-8/ASCII; records are
written as ASCII-only JSON with `\n` newlines and no BOM.

## Dry-run results (2026-10-18, Windows, Python 3.11.5)

Full log: `workflow/runs/20261018-1347_runA_offline_sim/bringup-kit/dryrun.log`.

| case | expected exit | observed | summary |
|---|---|---|---|
| fixtures/dump-positive.txt | 0 | 0 | pass=17 fail=0 blocked=0 |
| fixtures/neg-magic.txt | 1 | 1 | fail=1 (R01) |
| fixtures/neg-len.txt | 1 | 1 | fail=1 (R05) |
| fixtures/neg-reserved.txt | 1 | 1 | fail=1 (R13) |
| fixtures/neg-malformed.txt | 2 | 2 | rejected, no record |
| fixtures/neg-missing.txt | 1 | 1 | blocked=14 (missing readings) |
| fixtures/neg-empty.txt | 2 | 2 | rejected, no record |
| B1 real log (channel) | 0 | 0 | pass=3 fail=0 |
| fixtures/neg-channel-flash.log | 1 | 1 | fail=1 (CH03) |

Determinism: same input and fixed timestamp produced byte-identical records
(`DETERMINISM_OK=True` in the log).

## CRC / length cross-check

```
python tools/pcie_integration/r10f_strict.py check \
  docs/protocol/rka1-r10f-v1/artifacts/r10f-1080p-synthetic.dma \
  --json-out <out.json>
```
Expected: exit 0 and fields `sha256=646ebaedc19bdd6feb595430989b736f01913bb23caee26a132c922cfe5e9bff`,
`size=2592768`, `ok=true`, `header_crc_calc=108710859`,
`payload_crc_calc=3491449518`, `marker=R10F_STRICT_OK`; these must equal
`docs/protocol/rka1-r10f-v1/artifacts/check-1080p.json`. Compare the fields
textually or with the project Python; the reused tool may embed raw Windows
backslash paths in its JSON, so do not rely on a third-party JSON reader.
The reused tools are read-only and are not modified by this kit.

```
python tools/pcie_integration/gen_crc32_flat.py --selfcheck-only
```
Expected: exit 0 (poly `0xEDB88320` self-check of the emitted Verilog CRC
function). Note: this tool emits/verifies a Verilog function; it is **not** a
file CRC calculator.

Length recompute: `128 + 2592000 + 640 = 2592768` bytes (1080p packed RAW10
frame + tail padding). The dry-run log records `LENGTH_RECOMPUTE_OK=True`.

## Scope

`tools/bringup/**` is the only repository path this kit adds. It does not modify
`rtl/`, `constraints/`, `sim/`, `docs/`, `tools/pcie_integration/` or any
existing evidence. Rollback = revert the local commit or discard the directory.
