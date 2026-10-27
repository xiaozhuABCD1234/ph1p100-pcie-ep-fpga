#!/usr/bin/env python3
"""Offline R10F bring-up dump parser and verdict engine (fail-closed).

Subcommands
  regs     Evaluate a register dump against expected_rules.json.
  channel  Extract channel evidence from a B1/bw session log.

Exit codes
  0  all evaluated checks pass (not_applicable is allowed)
  1  at least one FAIL or BLOCKED verdict
  2  invalid input or unusable rules (no run record is written)

Text dump format (ASCII, one register per line)
  0x040 = 0x50434946
  0x044 0x00000061
  # comment lines start with '#' or ';'
  // C++ style comments are also ignored
Bare offsets such as `040 0x50434946` are accepted as hexadecimal offsets.
Values without a 0x prefix are decimal. Offsets must be 4-byte aligned.
Duplicate offsets are rejected (single sample per record; use one record per
time point).

JSON input accepts any of:
  {"readings": [{"offset": "0x040", "value": "0x50434946"}]}
  {"registers": {"0x040": "0x50434946"}}
  {"0x040": "0x50434946"}

The tool never touches hardware and never writes outside the --out path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

TOOL_NAME = "parse_dump.py"
TOOL_VERSION = "1.0.0"
EXPECTED_DEVICE_ID = "PH1P100"
MIN_RULES = 8

REGISTER_NAMES = {
    0x040: "MAGIC",
    0x044: "CTRL",
    0x048: "IMG_STATUS",
    0x04C: "TEST_FRAME_CNT",
    0x064: "LEGACY_VERSION",
    0x080: "CAM_STAT_080",
    0x084: "CAM_STAT_084",
    0x088: "CAM_STAT_088",
    0x08C: "CAM_STAT_08C",
    0x090: "CAM_STAT_090",
    0x094: "CAM_STAT_094",
    0x098: "CAM_STAT_098",
    0x0A0: "DDR_SEQ_A",
    0x0A4: "DDR_BASE_A",
    0x0A8: "DDR_STATUS_A",
    0x0AC: "DDR_LEN_A",
    0x0B0: "PUSH_DST_LO",
    0x0B4: "PUSH_DST_HI",
    0x0B8: "PUSH_DB_LO",
    0x0BC: "PUSH_DB_HI",
    0x0C0: "PUSH_DONE",
    0x0C4: "PUSH_STATUS",
    0x0C8: "PUSH_ERR",
    0x0CC: "PUSH_TLP_CNT",
    0x0D0: "CAM_DIAG_A",
    0x0D4: "CAM_TAP_B",
    0x0D8: "CAM_DIAG_B",
    0x0DC: "CAM_DROP_A",
    0x0E0: "DDR_SEQ_B",
    0x0E4: "DDR_BASE_B",
    0x0E8: "DDR_STATUS_B",
    0x0EC: "DDR_LEN_B",
    0x0F0: "CAM_DROP_A2",
    0x0F4: "CAM_DROP_A3",
    0x100: "DMA_CAP_BYTES",
    0x104: "SESSION_ID",
    0x108: "TX_CMD",
    0x10C: "ACK_SEQ",
    0x110: "ACK_SESSION",
    0x114: "TX_STATUS",
    0x118: "EXT_MAGIC",
    0x11C: "EXT_VERSION",
    0x120: "CSI_DIAG_A",
    0x124: "CSI_DIAG_A2",
    0x128: "CSI_DIAG_B",
    0x12C: "CSI_DIAG_B2",
}

TEXT_RE = re.compile(
    r"^\s*0x([0-9A-Fa-f]{1,8})\s*(?:=|:|,|\s)\s*"
    r"(0x[0-9A-Fa-f]{1,8}|[0-9]{1,10})\s*$"
)
BARE_RE = re.compile(
    r"^\s*([0-9A-Fa-f]{3})\s*(?:=|:|,|\s)\s*"
    r"(0x[0-9A-Fa-f]{1,8}|[0-9]{1,10})\s*$"
)
FLASH_RE = re.compile(
    r"(?i)\b(program_spi|erase_spi|program_efuse|read_flash|program_svf|flash)\b"
)
DOWNLOAD_RE = re.compile(r"(?i)\bdownload\b[^\r\n]*-mode\s+jtag\b")
PRG_OK_RE = re.compile(r"PRG-2014\s*:\s*Chip validation success:\s*(PH1P[0-9A-Z]+)")
DEV_LINE_RE = re.compile(r"(?m)^\s*(PH1P[0-9A-Z]+)\s*$")
DEV_ENV_RE = re.compile(r"RUNA_DL_DEVICE_ID\s*=\s*(PH1P[0-9A-Z]+)")

RULE_TYPES = {"eq", "mask_zero", "range", "aligned", "nonzero", "distinct"}
WHEN_OPS = {"gt", "ge", "eq", "ne"}


class InputError(Exception):
    """Raised when input or rules are not usable (exit code 2)."""


def _u32(value, what):
    if isinstance(value, bool):
        raise InputError("%s: boolean is not a 32-bit value" % what)
    if isinstance(value, int):
        out = value
    elif isinstance(value, str):
        text = value.strip()
        if not text:
            raise InputError("%s: empty value" % what)
        try:
            out = int(text, 16) if text.lower().startswith("0x") else int(text, 10)
        except ValueError:
            raise InputError("%s: not an integer: %r" % (what, value))
    else:
        raise InputError("%s: unsupported type %s" % (what, type(value).__name__))
    if out < 0 or out > 0xFFFFFFFF:
        raise InputError("%s: out of 32-bit range: %r" % (what, value))
    return out


def parse_offset(value):
    if isinstance(value, bool):
        raise InputError("offset: boolean is not allowed")
    if isinstance(value, int):
        off = value
    elif isinstance(value, str):
        text = value.strip()
        if not text:
            raise InputError("offset: empty")
        try:
            if text.lower().startswith("0x"):
                off = int(text, 16)
            elif re.fullmatch(r"[0-9A-Fa-f]{1,3}", text):
                off = int(text, 16)
            else:
                off = int(text, 10)
        except ValueError:
            raise InputError("offset: not an integer: %r" % value)
    else:
        raise InputError("offset: unsupported type")
    if off < 0 or off > 0xFFC:
        raise InputError("offset out of BAR0 window: 0x%X" % off)
    if off % 4:
        raise InputError("offset not 4-byte aligned: 0x%X" % off)
    return off


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _strip_comment(line):
    for marker in ("//", "#", ";"):
        pos = line.find(marker)
        if pos >= 0:
            line = line[:pos]
    return line


def load_text_dump(text):
    regs = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw).strip()
        if not line:
            continue
        match = TEXT_RE.match(line) or BARE_RE.match(line)
        if not match:
            raise InputError("line %d is not a register dump line: %r" % (lineno, raw))
        off = parse_offset("0x" + match.group(1))
        val = _u32(match.group(2), "line %d value" % lineno)
        if off in regs:
            raise InputError("duplicate offset 0x%03X at line %d" % (off, lineno))
        regs[off] = (val, raw.strip())
    if not regs:
        raise InputError("no register readings found")
    return regs


def load_json_dump(text):
    try:
        obj = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InputError("invalid JSON: %s" % exc)
    if isinstance(obj, list):
        items = obj
    elif isinstance(obj, dict) and "readings" in obj:
        items = obj["readings"]
        if not isinstance(items, list):
            raise InputError("readings must be a list")
    elif isinstance(obj, dict) and "registers" in obj:
        table = obj["registers"]
        if not isinstance(table, dict):
            raise InputError("registers must be an object")
        items = [{"offset": key, "value": val} for key, val in table.items()]
    elif isinstance(obj, dict):
        items = [{"offset": key, "value": val} for key, val in obj.items()]
    else:
        raise InputError("unsupported JSON root type")
    regs = {}
    for index, item in enumerate(items):
        if not isinstance(item, dict) or "offset" not in item or "value" not in item:
            raise InputError("reading %d must contain offset and value" % index)
        off = parse_offset(item["offset"])
        val = _u32(item["value"], "reading %d value" % index)
        if off in regs:
            raise InputError("duplicate offset 0x%03X" % off)
        regs[off] = (val, "offset=%s value=%s" % (item["offset"], item["value"]))
    if not regs:
        raise InputError("no register readings found")
    return regs


def load_dump(path):
    data = path.read_bytes()
    if not data.strip():
        raise InputError("empty input file: %s" % path)
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise InputError("input is not UTF-8/ASCII: %s" % exc)
    stripped = text.lstrip()
    if stripped.startswith("{") or stripped.startswith("["):
        return load_json_dump(text)
    return load_text_dump(text)


def load_rules(path):
    try:
        obj = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise InputError("cannot load rules %s: %s" % (path, exc))
    rules = obj.get("rules") if isinstance(obj, dict) else None
    if not isinstance(rules, list) or not rules:
        raise InputError("rules file has no rules array")
    if len(rules) < MIN_RULES:
        raise InputError("rules file has %d rules; at least %d required" % (len(rules), MIN_RULES))
    seen_ids = set()
    seen_offsets = set()
    for rule in rules:
        if not isinstance(rule, dict):
            raise InputError("rule entry is not an object")
        for field in ("id", "offset", "name", "type", "source"):
            if field not in rule:
                raise InputError("rule missing field %s: %r" % (field, rule.get("id")))
        rid = str(rule["id"])
        if rid in seen_ids:
            raise InputError("duplicate rule id %s" % rid)
        seen_ids.add(rid)
        if rule["type"] not in RULE_TYPES:
            raise InputError("%s: unknown rule type %r" % (rid, rule["type"]))
        parse_offset(rule["offset"])
        rtype = rule["type"]
        if rtype == "eq" and "expected" not in rule:
            raise InputError("%s: eq requires expected" % rid)
        if rtype == "mask_zero" and "mask" not in rule:
            raise InputError("%s: mask_zero requires mask" % rid)
        if rtype == "range" and ("min" not in rule or "max" not in rule):
            raise InputError("%s: range requires min and max" % rid)
        if rtype == "aligned" and "alignment" not in rule:
            raise InputError("%s: aligned requires alignment" % rid)
        if rtype == "distinct" and "other_offset" not in rule:
            raise InputError("%s: distinct requires other_offset" % rid)
        when = rule.get("when")
        if when is not None:
            if not isinstance(when, dict) or "offset" not in when or "value" not in when:
                raise InputError("%s: when requires offset and value" % rid)
            if when.get("op", "gt") not in WHEN_OPS:
                raise InputError("%s: when op not supported" % rid)
            parse_offset(when["offset"])
    return rules


def _compare(value, op, target):
    if op == "gt":
        return value > target
    if op == "ge":
        return value >= target
    if op == "eq":
        return value == target
    if op == "ne":
        return value != target
    raise InputError("unsupported comparison %r" % op)


def evaluate_rule(rule, regs):
    rid = rule["id"]
    when = rule.get("when")
    if when:
        woff = parse_offset(when["offset"])
        if woff not in regs:
            return "blocked", "precondition reading 0x%03X missing" % woff
        wval = regs[woff][0]
        if not _compare(wval, when.get("op", "gt"), _u32(when["value"], "%s when" % rid)):
            return "not_applicable", "precondition false: 0x%03X=%d" % (woff, wval)
    off = parse_offset(rule["offset"])
    if off not in regs:
        return "blocked", "reading 0x%03X missing" % off
    value = regs[off][0]
    rtype = rule["type"]
    if rtype == "eq":
        expect = _u32(rule["expected"], "%s expected" % rid)
        if value == expect:
            return "pass", "0x%08X == 0x%08X" % (value, expect)
        return "fail", "0x%08X != 0x%08X" % (value, expect)
    if rtype == "mask_zero":
        mask = _u32(rule["mask"], "%s mask" % rid)
        bad = value & mask
        if bad == 0:
            return "pass", "reserved bits clear (mask 0x%08X)" % mask
        return "fail", "reserved bits set: 0x%08X (mask 0x%08X)" % (bad, mask)
    if rtype == "range":
        low = _u32(rule["min"], "%s min" % rid)
        high = _u32(rule["max"], "%s max" % rid)
        if low <= value <= high:
            return "pass", "%d in [%d, %d]" % (value, low, high)
        return "fail", "%d outside [%d, %d]" % (value, low, high)
    if rtype == "aligned":
        alignment = _u32(rule["alignment"], "%s alignment" % rid)
        if alignment == 0:
            raise InputError("%s: alignment must be nonzero" % rid)
        if value % alignment == 0:
            return "pass", "0x%08X aligned to %d" % (value, alignment)
        return "fail", "0x%08X not aligned to %d" % (value, alignment)
    if rtype == "nonzero":
        if value != 0:
            return "pass", "0x%08X nonzero" % value
        return "fail", "value is zero"
    if rtype == "distinct":
        other = parse_offset(rule["other_offset"])
        if other not in regs:
            return "blocked", "comparison reading 0x%03X missing" % other
        other_value = regs[other][0]
        if value != other_value:
            return "pass", "0x%08X != 0x%08X" % (value, other_value)
        return "fail", "0x%08X == 0x%08X (buffers alias)" % (value, other_value)
    raise InputError("%s: unsupported rule type" % rid)


def _timestamp_or_now(value):
    if value:
        if not re.fullmatch(r"[0-9T:+\-Z.]{10,40}", value):
            raise InputError("timestamp is not ISO-8601-like: %r" % value)
        return value
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_record(path, record):
    text = json.dumps(record, indent=2, ensure_ascii=True) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def run_regs(args):
    input_path = Path(args.input)
    if not input_path.is_file():
        raise InputError("input not found: %s" % input_path)
    regs = load_dump(input_path)
    rules = load_rules(Path(args.rules))
    verdicts = []
    counts = {"pass": 0, "fail": 0, "blocked": 0, "not_applicable": 0}
    print("[regs] input=%s sha256=%s" % (input_path, sha256_file(input_path)))
    for rule in rules:
        verdict, detail = evaluate_rule(rule, regs)
        counts[verdict] += 1
        verdicts.append({
            "rule_id": rule["id"],
            "offset": "0x%03X" % parse_offset(rule["offset"]),
            "name": rule["name"],
            "verdict": verdict,
            "detail": detail,
            "source": rule["source"],
        })
        print("[rule] %-18s %-8s %s" % (rule["id"], verdict.upper(), detail))
    for off in sorted(regs):
        print("[read] 0x%03X %-16s 0x%08X" % (off, REGISTER_NAMES.get(off, "UNKNOWN"), regs[off][0]))
    if counts["fail"]:
        summary = "fail"
    elif counts["blocked"]:
        summary = "blocked"
    else:
        summary = "pass"
    record = {
        "schema_version": 1,
        "run_id": args.run_id,
        "timestamp": _timestamp_or_now(args.timestamp),
        "operator": args.operator,
        "channel": "offline-register-dump",
        "tool": {"name": TOOL_NAME, "version": TOOL_VERSION},
        "input": {"path": str(input_path), "sha256": sha256_file(input_path)},
        "readings": [
            {
                "offset": off,
                "offset_hex": "0x%03X" % off,
                "name": REGISTER_NAMES.get(off, "UNKNOWN"),
                "value": regs[off][0],
                "value_hex": "0x%08X" % regs[off][0],
                "raw": regs[off][1],
            }
            for off in sorted(regs)
        ],
        "verdicts": verdicts,
        "summary": {
            "pass": counts["pass"],
            "fail": counts["fail"],
            "blocked": counts["blocked"],
            "not_applicable": counts["not_applicable"],
            "verdict": summary,
        },
        "notes": [
            "single register sample; duplicate offsets are rejected",
            "not_applicable means a rule precondition was false, not that the claim was verified",
            "register plan is usable only after a read channel is established (B1: blocked)",
        ],
    }
    _write_record(Path(args.out), record)
    print("[summary] pass=%d fail=%d blocked=%d na=%d verdict=%s" % (
        counts["pass"], counts["fail"], counts["blocked"], counts["not_applicable"], summary))
    print("[record] %s" % args.out)
    return 0 if summary == "pass" else 1


def run_channel(args):
    input_path = Path(args.input)
    if not input_path.is_file():
        raise InputError("input not found: %s" % input_path)
    data = input_path.read_bytes()
    if not data.strip():
        raise InputError("empty input file: %s" % input_path)
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise InputError("log is not UTF-8/ASCII: %s" % exc)

    dev_ids = set(DEV_LINE_RE.findall(text)) | set(DEV_ENV_RE.findall(text)) | set(PRG_OK_RE.findall(text))
    prg_ok = bool(PRG_OK_RE.search(text))
    jtag_download = bool(DOWNLOAD_RE.search(text))
    forbidden = sorted(set(match.group(0).lower() for match in FLASH_RE.finditer(text)))

    verdicts = []
    counts = {"pass": 0, "fail": 0, "blocked": 0, "not_applicable": 0}

    def add(rule_id, name, verdict, detail, source):
        counts[verdict] += 1
        verdicts.append({
            "rule_id": rule_id,
            "offset": "-",
            "name": name,
            "verdict": verdict,
            "detail": detail,
            "source": source,
        })
        print("[check] %-10s %-8s %s" % (rule_id, verdict.upper(), detail))

    if not dev_ids:
        add("CH01", "device_id", "blocked", "no PH1P device id found", "B1 channel-notes.md s3")
    elif dev_ids == {EXPECTED_DEVICE_ID}:
        add("CH01", "device_id", "pass", "device id %s" % EXPECTED_DEVICE_ID, "B1 channel-notes.md s3")
    else:
        add("CH01", "device_id", "fail", "unexpected device id(s): %s" % ",".join(sorted(dev_ids)),
            "B1 channel-notes.md s3")

    if prg_ok and jtag_download:
        add("CH02", "sram_download", "pass", "PRG-2014 success with -mode jtag", "B1 channel-notes.md s3")
    elif not prg_ok and not jtag_download:
        add("CH02", "sram_download", "blocked", "no SRAM download evidence", "B1 channel-notes.md s3")
    else:
        add("CH02", "sram_download", "fail",
            "incomplete evidence: prg_ok=%s jtag_download=%s" % (prg_ok, jtag_download),
            "B1 channel-notes.md s3")

    if forbidden:
        add("CH03", "flash_absent", "fail", "forbidden flash/SPI/efuse command(s): %s" % ",".join(forbidden),
            "dev-plan s1 safety boundary")
    else:
        add("CH03", "flash_absent", "pass", "no flash/SPI/efuse command text", "dev-plan s1 safety boundary")

    if counts["fail"]:
        summary = "fail"
    elif counts["blocked"]:
        summary = "blocked"
    else:
        summary = "pass"
    record = {
        "schema_version": 1,
        "run_id": args.run_id,
        "timestamp": _timestamp_or_now(args.timestamp),
        "operator": args.operator,
        "channel": "bw-jtag-session-log",
        "tool": {"name": TOOL_NAME, "version": TOOL_VERSION},
        "input": {"path": str(input_path), "sha256": sha256_file(input_path)},
        "readings": [],
        "verdicts": verdicts,
        "summary": {
            "pass": counts["pass"],
            "fail": counts["fail"],
            "blocked": counts["blocked"],
            "not_applicable": counts["not_applicable"],
            "verdict": summary,
        },
        "notes": [
            "channel evidence only; no user register readings are implied",
            "JTAG register access semantics remain undocumented (KIT doc check: unavailable)",
        ],
    }
    _write_record(Path(args.out), record)
    print("[summary] pass=%d fail=%d blocked=%d verdict=%s" % (
        counts["pass"], counts["fail"], counts["blocked"], summary))
    print("[record] %s" % args.out)
    return 0 if summary == "pass" else 1


def build_parser():
    parser = argparse.ArgumentParser(description="Offline R10F bring-up dump parser (fail-closed).")
    sub = parser.add_subparsers(dest="command", required=True)

    regs = sub.add_parser("regs", help="evaluate a register dump against expected_rules.json")
    regs.add_argument("input", help="register dump (.txt or .json)")
    regs.add_argument("--rules", default=str(Path(__file__).with_name("expected_rules.json")))
    regs.add_argument("--out", required=True, help="run-record.json output path")
    regs.add_argument("--run-id", default="adhoc")
    regs.add_argument("--operator", default="unknown")
    regs.add_argument("--timestamp", default=None, help="ISO-8601 override for deterministic reruns")
    regs.set_defaults(func=run_regs)

    channel = sub.add_parser("channel", help="extract channel evidence from a B1/bw session log")
    channel.add_argument("input", help="bw session log text")
    channel.add_argument("--out", required=True, help="run-record.json output path")
    channel.add_argument("--run-id", default="adhoc")
    channel.add_argument("--operator", default="unknown")
    channel.add_argument("--timestamp", default=None, help="ISO-8601 override for deterministic reruns")
    channel.set_defaults(func=run_channel)
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except InputError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 2
    except OSError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
