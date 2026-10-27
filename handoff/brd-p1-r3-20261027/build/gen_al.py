#!/usr/bin/env python3
"""Generate brd_board.al (TD project) from the guarded repo-relative filelist.

The template is brd_board.al.tmpl; @REPO_ROOT@ is replaced with the actual
repository root and @SOURCES@ with the expanded source/IP/constraint entries.
Run from the repository root:

    python handoff/brd-p1-r3-20261027/build/gen_al.py

The generated .al contains absolute paths because TD project files do not
expand environment variables; the template itself carries only @REPO_ROOT@
(no T:/Y:/old absolute path).
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PKG = REPO / "handoff" / "brd-p1-r3-20261027"
TMPL = PKG / "build" / "brd_board.al.tmpl"
OUT = PKG / "build" / "brd_board.al"

vars = {"R": str(REPO).replace("\\", "/")}
files = []
for raw in (PKG / "filelist.tcl").read_text().splitlines():
    line = raw.split("#", 1)[0].strip()
    m = re.match(r"set\s+(\w+)\s+\$(\w+)(/.*)?$", line)
    if m:
        vars[m.group(1)] = vars[m.group(2)] + (m.group(3) or "")
        continue
    m = re.match(r"lappend\s+FL\s+\$(\w+)(/.*)?$", line)
    if m:
        files.append(vars[m.group(1)] + (m.group(2) or ""))

def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

v_files, ip_files, adc, sdc = [], [], [], []
for f in files:
    if f.endswith(".xml"):
        ip_files.append(f)
    elif f.endswith(".adc"):
        adc.append(f)
    elif f.endswith(".sdc"):
        sdc.append(f)
    else:
        v_files.append(f)

def entry(path, order, kind):
    if kind == "v":
        return f'''            <File Path="{xml_escape(path)}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{order}"/>
                </FileInfo>
            </File>'''
    return f'''            <File Path="{xml_escape(path)}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{order}"/>
                </FileInfo>
            </File>'''

v_xml = "\n".join(entry(p, i + 1, "v") for i, p in enumerate(v_files))
ip_xml = "\n".join(entry(p, 71 + i, "ip") for i, p in enumerate(ip_files))
adc_xml = "\n".join(entry(p, i + 1, "adc") for i, p in enumerate(adc))
sdc_xml = "\n".join(entry(p, 2 + i, "sdc") for i, p in enumerate(sdc))

out = TMPL.read_text()
out = out.replace("@REPO_ROOT@", str(REPO).replace("\\", "/"))
out = out.replace("@VERILOG_FILES@", v_xml)
out = out.replace("@IP_FILES@", ip_xml)
out = out.replace("@ADC_FILES@", adc_xml)
out = out.replace("@SDC_FILES@", sdc_xml)
OUT.write_text(out)
print(f"GEN_AL={OUT}")
print(f"GEN_AL_V={len(v_files)} IP={len(ip_files)} ADC={len(adc)} SDC={len(sdc)}")

