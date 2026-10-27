"""Create the sole RTL candidate; do not modify any original RTL."""
import difflib,pathlib
HERE=pathlib.Path(__file__).resolve().parent
original=HERE.parent/'inputs/a1-r5/src/a1_uart_export.v'
raw=original.read_bytes();s=raw.decode().replace('\r\n','\n')
changes=[
('    reg [1:0]   dq_wr, dq_rd, dq_cnt;',
 '    reg         dq_wr, dq_rd;\n    reg [1:0]   dq_cnt;'),
('    reg [1:0]   estate;',
 '    reg [1:0]   estate;\n    wire        dq_push_accept = desc_push && (dq_cnt < 2\'d2);\n    wire        dq_pop_accept = (estate == E_IDLE) && (dq_cnt != 2\'d0);'),
('            dq_wr <= 2\'d0; dq_rd <= 2\'d0; dq_cnt <= 2\'d0;',
 '            dq_wr <= 1\'b0; dq_rd <= 1\'b0; dq_cnt <= 2\'d0;'),
('            // ---------------------------------------------------- descriptor in',
 '            // One occupancy update uses the pre-edge accepted events.\n            case ({dq_push_accept, dq_pop_accept})\n                2\'b10: dq_cnt <= dq_cnt + 2\'d1;\n                2\'b01: dq_cnt <= dq_cnt - 2\'d1;\n                default: dq_cnt <= dq_cnt;\n            endcase\n\n            // ---------------------------------------------------- descriptor in'),
('                if (dq_cnt == 2\'d2) begin','                if (!dq_push_accept) begin'),
('                    dq_wr  <= dq_wr + 2\'d1;\n                    dq_cnt <= dq_cnt + 2\'d1;',
 '                    dq_wr  <= ~dq_wr;'),
('                    if (dq_cnt != 2\'d0) begin','                    if (dq_pop_accept) begin'),
('                        dq_rd <= dq_rd + 2\'d1;\n                        dq_cnt <= dq_cnt - 2\'d1;',
 '                        dq_rd <= ~dq_rd;')]
for old,new in changes:
    assert s.count(old)==1,old
    s=s.replace(old,new)
folder=HERE/'candidate';folder.mkdir(exist_ok=True)
candidate=folder/'a1_uart_export.v';assert not candidate.exists(),'candidate already exists'
candidate.write_bytes(s.replace('\n','\r\n').encode() if b'\r\n' in raw else s.encode())
(HERE/'candidate.diff').write_text(''.join(difflib.unified_diff(raw.decode().splitlines(True),candidate.read_bytes().decode().splitlines(True),fromfile=str(original),tofile=str(candidate))))
print('CANDIDATE_CREATED changed_rtl_files=1 replacements='+str(len(changes)))
