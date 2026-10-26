from pathlib import Path
import datetime
import hashlib
import io
import json
import subprocess
import tarfile

ROOT=Path(__file__).resolve().parents[5]
RUN=ROOT/'workflow/runs/20261017-011744-rk-fpga-align'
OUT=Path(__file__).resolve().parent
def sha(b): return hashlib.sha256(b).hexdigest()
upstreams=json.loads((RUN/'references/provenance.json').read_text(encoding='utf-8-sig'))['upstreams']
results=[]
failures=[]
for u in upstreams:
    cmd=['git','-C',u['source_git'],'archive','--format=tar',u['commit']]
    p=subprocess.run(cmd,capture_output=True)
    if p.returncode:
        failures.append({'name':u['name'],'error':p.stderr.decode('utf-8',errors='replace')})
        continue
    saved=Path(u['archive']).read_bytes()
    with tarfile.open(fileobj=io.BytesIO(p.stdout)) as fresh,tarfile.open(fileobj=io.BytesIO(saved)) as frozen:
        fresh_files={m.name:fresh.extractfile(m).read() for m in fresh.getmembers() if m.isfile()}
        frozen_files={m.name:frozen.extractfile(m).read() for m in frozen.getmembers() if m.isfile()}
    bad=[]
    for rel,data in fresh_files.items():
        snapshot=(RUN/'references'/u['name']/rel).read_bytes()
        if rel not in frozen_files or data!=frozen_files[rel] or data!=snapshot:
            bad.append(rel)
    if set(fresh_files)!=set(frozen_files): bad.append('member set differs')
    if bad: failures.append({'name':u['name'],'mismatches':bad})
    selected=('rtl/ep_side/img/ep_bar_win.v','rtl/ep_side/ddr/ddr_frame_pusher.v','rtl/ep_side/ddr/cam_ddr_writer.v') if 'fpga' in u['name'] else ('include/anlogic_pci_ioctl.h','src/anlogic_pci_link.c','src/anlogic_pci_frame.c','app/rs/src/bin/frame_grab.rs')
    eol=[]
    for rel in selected:
        blobcmd=['git','-C',u['source_git'],'show',u['commit']+':'+rel]
        blob=subprocess.run(blobcmd,capture_output=True)
        export=fresh_files[rel]
        normalized=export.replace(b'\r\n',b'\n')==blob.stdout.replace(b'\r\n',b'\n')
        eol.append({'path':rel,'raw_blob_sha256':sha(blob.stdout),'export_sha256':sha(export),'raw_blob_bytes':len(blob.stdout),'export_bytes':len(export),'blob_crlf':blob.stdout.count(b'\r\n'),'export_crlf':export.count(b'\r\n'),'normalized_lf_equal':normalized,'blob_command_exit':blob.returncode})
        if not normalized: failures.append({'name':u['name'],'path':rel,'non_eol_difference':True})
    results.append({'name':u['name'],'argv':cmd,'exit_code':p.returncode,'fresh_archive_sha256':sha(p.stdout),'frozen_archive_sha256':sha(saved),'archive_bytes_identical':p.stdout==saved,'all_members_and_snapshot_bytes_equal':not bad,'files_checked':len(fresh_files),'line_endings':eol})
result={'marker':'SOURCE_ARCHIVE_IDENTITY_COMPLETE','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'upstreams':results,'failures':failures}
(OUT/'source-identity-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'marker':result['marker'],'upstreams':[{'name':x['name'],'file_count':x['files_checked'],'archive_bytes_identical':x['archive_bytes_identical'],'all_members_and_snapshot_bytes_equal':x['all_members_and_snapshot_bytes_equal']} for x in results],'failures':failures},ensure_ascii=False))
raise SystemExit(1 if failures else 0)
