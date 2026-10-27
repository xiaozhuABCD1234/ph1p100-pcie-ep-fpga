"""Independent T03 round0 verification; writes only inside this evidence folder."""
from pathlib import Path
import argparse, binascii, hashlib, importlib.util, json, os, struct, subprocess, sys, time

sys.dont_write_bytecode = True
EV = Path(__file__).resolve().parent
RUN = EV.parent.parent
PKG = RUN / 'T03.pcie-byte-replay'
ROOT = RUN.parents[2]
OUT = EV / 'reproduction'
MS = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')

def save(name, value):
    (EV / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

def command(argv, cwd, log, deadline=300, expected_rc=0):
    argv = [x.as_posix() if isinstance(x, Path) else str(x) for x in argv]
    started = time.time()
    proc = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1'))
    timed_out = False
    try:
        output, _ = proc.communicate(timeout=deadline)
    except subprocess.TimeoutExpired:
        timed_out = True
        # This PID was created immediately above. Terminate only its owned tree.
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True, timeout=30)
        output, _ = proc.communicate(timeout=30)
    text = output.decode('utf-8', errors='replace')
    (EV / log).write_text(text, encoding='utf-8')
    row = dict(argv=argv, cwd=str(cwd), pid=proc.pid, deadline_seconds=deadline,
               seconds=time.time()-started, exit_code=proc.returncode, timeout=timed_out,
               expected_exit_code=expected_rc, log=str(EV/log))
    with (EV/'commands.jsonl').open('a', encoding='utf-8') as f:
        f.write(json.dumps(row)+'\n')
    print(json.dumps(row))
    assert not timed_out, 'owned command deadline exceeded'
    assert proc.returncode == expected_rc, text[-2000:]
    return text

def stage(action):
    command([sys.executable, '-B', '-X', 'utf8', PKG/'runner.py', action, '--out', OUT], EV,
            action+'-outer.log')

def oracle():
    # Parse by byte offsets, independently of replay.HEADER and make_record.
    spec = importlib.util.spec_from_file_location('historical_decoder', ROOT/'handoff/rk-a1u1-b18-20261026/decode_sample.py')
    hist = importlib.util.module_from_spec(spec); spec.loader.exec_module(hist)
    expected = json.loads((PKG/'r0/expected.json').read_text(encoding='utf-8'))
    def crc(d): return binascii.crc32(d) & 0xffffffff
    positives=[]
    for exp in expected['cases']:
        p=OUT/exp['name']; frozen=PKG/'r0'/exp['name']; data=(p/'reconstructed.a1u1').read_bytes()
        u=lambda a,b: int.from_bytes(data[a:b], 'little')
        header=dict(version=data[4],flags=data[5],header_bytes=u(6,8),frame_id=u(8,12),width=u(12,14),height=u(14,16),raw_bytes=u(16,20),xform_bytes=u(20,24),zlib_bytes=u(24,28),raw_crc32=u(28,32),xform_crc32=u(32,36),stream_crc32=u(36,40),header_crc32=u(40,44))
        assert data[:4]==b'A1U1' and header['version']==1 and header['header_bytes']==44 and header['flags'] in (0,1,3)
        assert len(data)==44+header['zlib_bytes'] and header['raw_bytes']==header['width']*header['height']*5//4
        for key in ['flags','frame_id','width','height','raw_bytes','xform_bytes','zlib_bytes']:
            assert header[key]==exp[key], (exp['name'],key)
        assert crc(data[:40])==header['header_crc32'] and crc(data[44:])==header['stream_crc32']
        raw,stats=hist.decode_record(data)
        assert raw==(p/'expected.raw10').read_bytes() and hashlib.sha256(raw).hexdigest()==exp['raw_sha256']
        for key in ['raw_crc32','xform_crc32','stream_crc32','header_crc32']:
            assert f'{header[key]:08x}'==exp[key]
        if exp['name'].startswith('synthetic'):
            samples=[]
            for base in range(0,len(raw),5):
                for lane in range(4): samples.append((raw[base+lane]<<2)|((raw[base+4]>>(2*lane))&3))
            assert len(samples)==64
            for index,value in enumerate(samples):
                row,col=divmod(index,16)
                assert value==(197*col+311*row+23*col*row)%1024, (index,value)
        diffs={}
        for filename in ['current-slot.bin','current-dma.bin','reconstructed.a1u1','proposed-a1u1-dma.bin','expected.raw10','replay-metadata.json']:
            a=(p/filename).read_bytes(); b=(frozen/filename).read_bytes()
            diffs[filename]=sum(x!=y for x,y in zip(a,b))+abs(len(a)-len(b))
        assert all(n==0 for n in diffs.values()), diffs
        positives.append(dict(name=exp['name'],header=header,byte_differences=diffs,strict_inverse='historical handoff decoder',unpacked_pixel_formula_pass=exp['name'].startswith('synthetic')))
    # Separate arithmetic oracle does not use runner.R.align.
    rows=[json.loads(l) for l in (OUT/'p2-descriptors.jsonl').read_text().splitlines()]
    assert len(rows)==48
    boundaries=[r for r in rows if r['kind']==1]
    assert [r['zlib_bytes'] for r in boundaries]==list(range(4052,4097))
    for row in rows:
        n=row['zlib_bytes']; pages, rem=divmod(n,4096)
        assert row['frame_bytes']==4096*(pages+bool(rem)) and row['arm']==1
    changed=[r['zlib_bytes'] for r in boundaries if ((r['zlib_bytes']+44+4095)//4096)*4096!=r['frame_bytes']]
    assert changed==list(range(4053,4097))
    actual=(OUT/'rtl-slot-read.bin').read_bytes(); assert actual==(OUT/'synthetic-flags3/current-slot.bin').read_bytes()
    assert actual[:2]==b'\x78\x9c' and actual[:4]!=b'A1U1'
    pad=(OUT/'rtl-slot-word-padding.bin').read_bytes(); assert len(pad)==96 and pad[:70]==actual and pad[70:]==bytes(26)
    # Fresh mutation with all header CRCs valid reaches geometry validation.
    good=(OUT/'synthetic-flags3/reconstructed.a1u1').read_bytes(); bad=bytearray(good)
    bad[12:14]=(20).to_bytes(2,'little'); bad[40:44]=crc(bad[:40]).to_bytes(4,'little')
    (EV/'geometry-with-valid-header-crc.a1u1').write_bytes(bad)
    rejection=None
    try: hist.decode_record(bytes(bad))
    except ValueError as e: rejection=str(e)
    assert rejection is not None, 'strict oracle accepted geometry mutation'
    save('independent-oracle.json',dict(status='pass',cases=positives,descriptor_count=len(rows),length_only_boundaries=45,header_changes_dma_pages=44,real_slot_bytes=70,observed_word_padding=26,dma_page_tail_proven=False,geometry_mutation_rejection=rejection))
    print('INDEPENDENT_ORACLE PASS cases=4 descriptor_count=48 boundary_changed=44 geometry_mutation=rejected')

def mutant():
    # Copy and mutate only the P2 equation inside this evidence directory.
    d=EV/'mutant-header-inclusive'; d.mkdir(exist_ok=False)
    source=ROOT/'workspace/ph1p100/fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v'
    text=source.read_text(encoding='utf-8-sig')
    assert text.count('align_up(slot_stream_len, ALIGN_BYTES)')==2
    text=text.replace('align_up(slot_stream_len, ALIGN_BYTES)', "align_up(slot_stream_len + 32'd44, ALIGN_BYTES)")
    (d/'aplus_pcie_egress_adapter.v').write_text(text,encoding='utf-8')
    for f in ['stream.mem','fixture-config.vh']: (d/f).write_bytes((OUT/f).read_bytes())
    sources=[ROOT/'workspace/ph1p100/fpga/csi2/src/a1/a1_ddr_slot_store.v',d/'aplus_pcie_egress_adapter.v',PKG/'tb_byte_replay.v']
    (d/'sources.f').write_text('\n'.join('"'+x.as_posix()+'"' for x in sources)+'\n',encoding='utf-8')
    command([MS/'vlib.exe','work'],d,'mutant-vlib.log',60)
    (d/'modelsim.ini').write_text('[Library]\nwork = work\n[vsim]\n',encoding='ascii')
    text=command([MS/'vlog.exe','-modelsimini',d/'modelsim.ini','-work','work','+incdir+.','-f','sources.f'],d,'mutant-compile.log')
    assert 'Errors: 0' in text
    text=command([MS/'vsim.exe','-c','-modelsimini',d/'modelsim.ini','-wlf',d/'rtl.wlf','work.tb_byte_replay','-do','run -all; quit -f'],d,'mutant-simulation.log')
    assert 'BYTE_REPLAY_RTL FAIL' in text and 'BYTE_REPLAY_RTL PASS' not in text, 'TB did not reject wrong descriptor equation'
    save('rtl-mutation.json',dict(status='reject',mutation='P2 frame and held length changed from align(zlib) to align(44+zlib)',source_copy=str(d/'aplus_pcie_egress_adapter.v'),real_source_changed=False,sim_exit_code=0,scoreboard_failed=True))
    print('RTL_MUTATION REJECTED despite simulator exit0; scoreboard FAIL observed')

def cli_negative():
    text=command([sys.executable,'-B','-X','utf8',PKG/'replay.py','verify','--case',OUT/'synthetic-flags3','--camera','1','--session','7','--capacity','8192'],EV,'wrong-camera-cli.log',300,1)
    assert json.loads(text)['status']=='reject' and 'camera sidecar mismatch' in text

def versions():
    for name,args in [('python-version',[sys.executable,'--version']),('vlog-version',[MS/'vlog.exe','-version']),('vsim-version',[MS/'vsim.exe','-version'])]:
        command(args,EV,name+'.log',60)

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('action',choices=['prepare','rtl','check','oracle','mutant','cli-negative','versions']); a=ap.parse_args()
    if a.action in ['prepare','rtl','check']: stage(a.action)
    else: {'oracle':oracle,'mutant':mutant,'cli-negative':cli_negative,'versions':versions}[a.action]()
