"""G1 arithmetic/static witness; does not simulate PHY, DDR, or the full RTL.
Run with --out in the tester's own allowed directory for independent replay.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

RUN = Path('D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review')
TASK = RUN / 'T02.chain-input-review'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text(path):
    return path.read_text(encoding='utf-8-sig', errors='replace')


def packed(pixels):
    """Canonical CSI RAW10 byte construction, low byte first."""
    values = [p >> 2 for p in pixels]
    values.append(sum((p & 3) << (2*i) for i, p in enumerate(pixels)))
    return sum(b << (8*i) for i, b in enumerate(values))


def canonical_decode(word):
    return [(((word >> (8*i)) & 255) << 2) | ((word >> (32+2*i)) & 3) for i in range(4)]


def producer_from_source(word, terms):
    """Evaluate the frozen producer's concatenation as generic bit slices."""
    result = 0
    for high, low in terms:
        width = high-low+1
        result = (result << width) | ((word >> low) & ((1 << width)-1))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    producer = TASK / 'inputs/csi_rx_10bit_unpack_checked.v'
    consumer = RUN / 'baseline/snapshot/0146.v'
    crop = RUN / 'baseline/snapshot/0147.v'
    board = RUN / 'baseline/snapshot/0152.v'
    integration = RUN / 'baseline/snapshot/0150.v'
    store = RUN / 'baseline/snapshot/0144.v'
    pcode = re.sub(r'//[^\n]*', '', text(producer))
    match = re.search(r'O_data_out\s*<=\s*\{(.*?)\}\s*;', pcode, re.S)
    assert match, 'producer expression missing'
    terms = [tuple(map(int, t)) for t in re.findall(r'group_data\[(\d+):(\d+)\]', match.group(1))]
    assert len(terms) == 8 and sum(a-b+1 for a, b in terms) == 40
    compact = lambda s: re.sub(r'\s+', '', re.sub(r'//[^\n]*', '', s))
    assert 'samp_t={b_t,2\'b00}|((pix_r>>(32+2*byte_k))&2\'b11);' in compact(text(consumer))
    assert '.cap_frame_good(),.cap_frame_abort()' in compact(text(board))
    assert '.out_pix(crop_pix)' in compact(text(integration))
    assert '.w_data({fifo_wabort,crop_last,crop_sof,crop_pix})' in compact(text(integration))
    assert '.wr_data(skid_pix)' in compact(text(integration))
    assert 'wcnt*8\'d40' in compact(text(store))
    assert 'wbuf[39:0]' in compact(text(integration))
    assert '.in_pix(a1_in_pix)' in compact(text(integration))
    vectors = [[0,1,2,3], [1023,0,341,682], [17,261,509,777], [0,0,0,0], [1023]*4]
    rows = []
    for pixels in vectors:
        raw = packed(pixels)
        lanes = producer_from_source(raw, terms)
        observed = canonical_decode(lanes)
        restored = packed([(lanes >> (10*i)) & 1023 for i in range(4)])
        assert canonical_decode(raw) == pixels
        assert canonical_decode(restored) == pixels
        rows.append({'pixels':pixels, 'canonical_wire_word':f'{raw:010x}',
                     'producer_word':f'{lanes:010x}', 'consumer_samples':observed,
                     'direct_boundary_preserves_pixels':observed == pixels,
                     'repack_control_preserves_pixels':canonical_decode(restored) == pixels})
    assert rows[0]['consumer_samples'] == [0,16,128,768]
    assert all(not row['direct_boundary_preserves_pixels'] for row in rows[:3])
    mismatches = 0
    for lane in range(4):
        for value in range(1024):
            pixels = [0]*4
            pixels[lane] = value
            output = producer_from_source(packed(pixels), terms)
            mismatches += canonical_decode(output) != pixels
    assert mismatches > 0
    # A source-anchored chronology, not a cycle-accurate crop/CRC simulation.
    last_row = 556+1080-1
    last_group = 972//4 + 1920//4 - 1
    remaining_groups = 3864//4-last_group-1
    assert remaining_groups == 243 and last_row == 1635
    crop_code = compact(text(crop))
    assert 'if(frame_fall&&active&&!done)' in crop_code
    assert 'if(active&&!done&&need_check&&(grp_idx!=CG[15:0]))' in crop_code
    assert 'if(out_cnt==(NGRP-1))beginout_last<=1\'b1;done<=1\'b1;' in crop_code
    trace = [
        {'event':'last_ROI_group', 'row_zero_based':last_row,'group_zero_based':last_group,
         'crop_out_last':1,'crop_done_after_edge':1,'selected_FE_seen':False},
        {'event':'remaining_source_line_payload','remaining_groups':remaining_groups,
         'crop_can_revoke_via_frame_fall':False},
        {'event':'same_ROI_line_CRC_error','receiver_abort':1,
         'board_has_connected_abort_to_A1':False},
        {'event':'selected_FE_bad','crop_done':1,'crop_frame_fall_abort_guard':False}]
    result = {'marker':'T02_INPUT_WITNESS_COMPLETE','status':'witness_reproduced',
              'method':'generic source-slice evaluation plus independent RAW10 arithmetic and static chronology',
              'scope':'G1 audit evidence only; no RTL execution or board/DDR inference',
              'vectors':rows,'single_lane_sweep':{'cases':4096,'mismatches':mismatches},
              'late_verdict_trace':trace,
              'source_bindings':[{'path':str(p),'sha256':sha(p)} for p in [producer,consumer,crop,board,integration,store]]}
    (args.out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('T02_INPUT_WITNESS_COMPLETE cases=4096 mismatches='+str(mismatches))


if __name__ == '__main__':
    main()
