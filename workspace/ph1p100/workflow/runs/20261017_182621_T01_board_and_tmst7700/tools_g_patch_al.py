# G follow-up helper: normalize the copied project file's Path attribute to forward slashes (COPY only).
from pathlib import Path
import re, sys

copy = Path(sys.argv[1])
al = copy / 'camera_ddr_display.al'
b = al.read_bytes()
old = b'C:\\Users\\czz\\AppData\\Local\\Temp\\opencode\\tmst7700_detail_20261017\\prj_1333_copy'
new = b'C:/Users/czz/AppData/Local/Temp/opencode/tmst7700_detail_20261017/prj_1333_copy'
n = b.count(old)
b = b.replace(old, new)
al.write_bytes(b)
m = re.search(rb'<Project[^>]*>', b)
print('replaced_backslash_refs=', n)
print('project_tag_ascii=', m.group(0).decode())
# also echo any remaining absolute D: refs inside the .al
print('remaining_D_colon_refs=', len(re.findall(rb'[A-Za-z]:[\\\\/]', b)))
