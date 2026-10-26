import sys, xml.etree.ElementTree as ET
bid = ET.parse(sys.argv[1]).getroot()
tags = [e.tag for e in bid.iter()]
inst = [t for t in tags if t.startswith("INST_")]
print("TOTAL_ELEMENTS=", len(tags), "INST_TAGS=", len(inst))
print("FIRST_TAGS=", tags[:6])
print("FIRST_INST=", inst[:2])
cwc = ET.parse(sys.argv[2]).getroot()
for i, ins in enumerate(cwc.findall("instance")):
    if ins.get("inst_enable") != "true":
        continue
    ram = ins.findall("logic_eram")[0]
    print("INST=%s W=%s D=%s pieces=%d" % (ins.get("name"), ram.get("width"), ram.get("depth"), len(ram.findall("phy_eram"))))
    ents = {}
    for e in bid.iter():
        if e.tag.startswith("INST_"):
            ents[(e.findtext("rid"), e.findtext("name"))] = e
    for p in ram.findall("phy_eram"):
        key = (p.get("rid"), p.get("name"))
        e = ents.get(key)
        print("  piece rid=%s name=%s width=%s off=%s depth=%s addr_off=%s | bid_lw=%s bid_ld=%s" % (
            p.get("rid"), p.get("name").split("/")[-1], p.get("width"), p.get("data_offset"),
            p.get("depth"), p.get("address_offset"),
            (e.findtext("logic_width") if e is not None else "MISSING"),
            (e.findtext("logic_depth") if e is not None else "MISSING")))