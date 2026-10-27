"""Independent, read-only system review of the frozen T03 package."""
from pathlib import Path
import datetime
import hashlib
import json
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[5]
RUN = ROOT / 'workflow/runs/20261017-011744-rk-fpga-align'
OUT = Path(__file__).resolve().parent
MANIFEST = RUN / 'candidate-manifest.json'
EXPECTED = '9662167a4af6fcea43a76491a9507b191552fa52209648147de02f91cfd877c5'

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()

def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

result = {
    'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'cwd': str(Path.cwd()), 'python': sys.version,
    'manifest_path': str(MANIFEST), 'expected_manifest_sha256': EXPECTED,
    'actual_manifest_sha256': sha(MANIFEST), 'checks': [],
}

def check(label, value, detail=None):
    result['checks'].append({'label': label, 'pass': bool(value), 'detail': detail})

check('manifest identity', result['actual_manifest_sha256'] == EXPECTED)
m = read_json(MANIFEST)
check('task and round', m['task_ids'] == ['T03.rk-align-freeze'] and m['round'] == 0)
hash_errors = []
for f in m['files']:
    p = Path(f['path'])
    if not p.is_file():
        hash_errors.append({'path': str(p), 'error': 'missing'})
    elif p.stat().st_size != f['bytes'] or sha(p) != f['sha256']:
        hash_errors.append({'path': str(p), 'error': 'size or sha mismatch'})
check('all frozen file bytes and hashes', not hash_errors, {'count': len(m['files']), 'errors': hash_errors})
result['manifest_keys'] = list(m)
result['manifest_non_file_metadata'] = {k: v for k,v in m.items() if k != 'files'}

for n in ['references/provenance.json', 'backup/baseline-manifest.json']:
    data = read_json(RUN/n)
    result[n + ':structure'] = {k: ('list '+str(len(v)) if isinstance(v,list) else 'keys '+str(list(v)) if isinstance(v,dict) else v) for k,v in data.items()}

fpga = 'references/peer-fpga-2a4b253/'
driver = 'references/peer-driver-a0215c5/'
sources = {
    fpga+'rtl/ep_side/img/ep_bar_win.v': [(240,272),(340,412)],
    fpga+'rtl/ep_side/ddr/ddr_frame_pusher.v': [(175,197),(475,495),(640,695),(770,790),(830,842)],
    fpga+'rtl/ep_side/ddr/cam_ddr_writer.v': [(110,125),(180,205)],
    driver+'include/anlogic_pci_ioctl.h': [(20,150),(180,250)],
    driver+'src/anlogic_pci_frame.c': [(110,220)],
    driver+'src/anlogic_pci_link.c': [(240,345),(400,445),(575,635)],
    driver+'app/rs/src/bin/frame_grab.rs': [(365,420)],
    driver+'app/rs/src/bin/cam_grab.rs': [(1,35)],
    'references/local-inputs/fpga/csi2/src/csi/csi_rx_packet_integrity.v': [(1,115)],
    'references/local-inputs/fpga/csi2/src/csi/csi_rx_10bit_unpack_checked.v': [(1,75)],
}
excerpts = []
for rel, spans in sources.items():
    path = RUN / rel
    lines = path.read_text(encoding='utf-8-sig').splitlines()
    excerpts.append('\n## '+rel+' SHA256='+sha(path))
    for start, end in spans:
        excerpts.extend(f'{i}: {lines[i-1]}' for i in range(start,min(end,len(lines))+1))
    check('source excerpt exists: '+rel, all(a <= len(lines) for a,b in spans))
(OUT/'source-excerpts.txt').write_text('\n'.join(excerpts)+'\n', encoding='utf-8')

reg = read_json(RUN/'contract/registers.json')
base_offsets = {x['offset'] for x in reg['registers']}
ext_offsets = [x['offset'] for x in reg['extension_registers']]
check('extension offsets nonconflicting and aligned', len(ext_offsets)==len(set(ext_offsets)) and not base_offsets.intersection(ext_offsets) and all(x%4==0 for x in ext_offsets))
check('extension window end', max(ext_offsets)+4 == 0x120)
check('ARM masks exclude bit4', reg['required_rk_arm_bits']==0x61 and reg['required_rk_arm_bits_b']==0x161 and reg['legacy_driver_arm_bits']==0x71)
abi = reg['host_abi']
check('separate host header, offset and R10F header', abi['slot_header_struct_bytes']==16 and abi['hdr_bytes_transport_offset']==128 and abi['host_prefix_padding_bytes']==112 and abi['r10f_header_bytes']==128)
check('mailbox push doorbell offset', abi['mailbox_push_dbell_offset']==32 and abi['mailbox_bytes']==64)
check('unimplemented safety extension labelled', 'not implemented' in reg['extension_status'])

v = read_json(RUN/'contract/acceptance-vectors.json')
for ds in v['datasets']:
    raw = ds['width']*ds['height']*5//4
    dma = (raw+128+4095)//4096*4096
    stride = (128+dma+4095)//4096*4096
    check('host layout '+ds['name'], ds['raw_bytes']==raw and ds['dma_bytes']==dma and ds['host_hdr_bytes']==128 and ds['host_stride']==stride and ds['host_total_alloc']==stride+4096)
    check('synthetic label '+ds['name'], 'synthetic' in ds['identity'].lower() and 'not CSI' in ds['identity'])
    for host_dma_base in [0x100000000,0xFFFFFF80,0x10000000000]:
        dst = host_dma_base+128
        db = host_dma_base+stride+32
        check('64-bit carry and separated doorbell '+ds['name']+' '+hex(host_dma_base), dst%128==0 and db%4==0 and dst+dma<=host_dma_base+stride and db+4<=host_dma_base+stride+4096)
        packets = [(dst+i*128) & 4095 for i in range(dma//128)]
        check('all fixed MWr stay in 4KiB '+ds['name']+' '+hex(host_dma_base), all(x+128<=4096 for x in packets))

check('manifest unchanged at end', sha(MANIFEST)==EXPECTED)
result['failed_checks'] = [c for c in result['checks'] if not c['pass']]
result['complete_marker'] = 'SYSTEM_AUDIT_COMPLETE'
(OUT/'audit-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n', encoding='utf-8')
print(json.dumps({'marker':result['complete_marker'],'checks':len(result['checks']),'failures':result['failed_checks'],'frozen_files':len(m['files']),'manifest_sha256':sha(MANIFEST)}, ensure_ascii=False))
sys.exit(1 if result['failed_checks'] else 0)
