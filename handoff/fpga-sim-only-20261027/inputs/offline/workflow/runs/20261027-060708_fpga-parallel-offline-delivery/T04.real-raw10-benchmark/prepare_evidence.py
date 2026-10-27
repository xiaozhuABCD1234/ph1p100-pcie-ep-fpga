"""One-shot finite inventory and input documentation; writes this task package only."""
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
RUN=HERE.parent

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,obj):
    p=HERE/name;p.parent.mkdir(parents=True,exist_ok=True)
    if p.exists():raise ValueError('refuse overwrite '+str(p))
    p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

source_paths=[ROOT/'AGENTS.md',ROOT/'docs/PROJECT_SYNC_20261027.md',
 ROOT/'workspace/ph1p100/.agents/skills/fpga-dev/SKILL.md',
 *(ROOT/'workspace/ph1p100/.agents/skills/fpga-orchestrator/references'/n for n in ['work-limits.md','report-contract.md','relay-contract.md']),
 *(RUN/n for n in ['dispatch-t04-ready.json','request.md','dev-plan.md','fpga-design-guide.md','input-index.md']),
 *(ROOT/'tools/codec'/n for n in ['a1_ref.py','a1_inflate_strict.py']),
 *(ROOT/'handoff/rk-a1u1-b18-20261026'/n for n in ['README.md','expected.json','provenance.json','SHA256SUMS','decode_sample.py','samples/b18_b_1080p.a1u1'])]
write('inputs/source-binding.json',{'project_root':str(ROOT),'dispatch':str(RUN/'dispatch-t04-ready.json'),
 'binding_policy':'absolute resolved read-only sources; exact source bytes, no copied production files',
 'sources':[{'path':str(p.resolve(strict=True)),'bytes':p.stat().st_size,'sha256':sha(p),
             'role':'encoder' if p.name=='a1_ref.py' else 'strict_parser' if p.name=='a1_inflate_strict.py' else 'planning_or_historical_evidence'} for p in source_paths]})
base=ROOT/'handoff/rk-a1u1-b18-20261026'
entries=[]
for folder in [base,base/'samples',ROOT/'tools/codec']:
    entries.append({'directory':str(folder),'files':[{'name':p.name,'bytes':p.stat().st_size}
        for p in sorted(folder.iterdir()) if p.is_file()]})
expected=json.loads((base/'expected.json').read_text(encoding='utf-8-sig'))
write('inputs/inventory.json',{'inventory_type':'finite explicit input-index sources, immediate files only',
 'searched_directories':entries,'not_a_full_disk_or_repository_search':True,
 'qualified_real_count':0,'real_sample_count':0,
 'candidates':[{'path':str(base/'samples/b18_b_1080p.a1u1'),'category':'historical_control',
    'source_kind':expected['source_kind'],'sha256':sha(base/'samples/b18_b_1080p.a1u1'),
    'accept_for_historical_transport_control':True,'accept_for_real_summary':False,
    'reasons':['A1U1 encoded capture, not a provenance-qualified raw sensor frame',
      'sensor_pixel_oracle_verified=false','physical_bayer_phase=unknown',
      '540 stored blocks do not establish sensor pixel correctness or representative compression benefit']}],
 'blocked_inputs':[{'required':'sensor RAW10 frame paths','found':0},
   {'required':'per frame sensor/device, capture/source and license basis, W/H/stride, ROI, encoding/normalization declaration','found':False},
   {'required':'independent sensor pixel-correctness evidence binding normalized raw SHA, reviewer and qualified review','found':False}],
 'excluded_labels':['N','L','CONTENT=2','synthetic ramp','generated random/flat controls'],
 'source_note':'input-index explicitly reports prior bounded searches found no qualified local dataset; this inventory does not claim an exhaustive absence'})
write('inputs/real-inputs.json',{'schema_version':1,'mode':{'prep':0,'pred':0},'samples':[]})
str_nonempty={'type':'string','minLength':1}
sha_spec={'type':'string','pattern':'^[0-9a-fA-F]{64}$'}
schema={'$schema':'https://json-schema.org/draft/2020-12/schema','title':'T04 RAW10 software benchmark input v1',
 'type':'object','required':['schema_version','mode','samples'],
 'properties':{'schema_version':{'const':1},'mode':{'type':'object','required':['prep','pred'],
 'properties':{'prep':{'type':'integer','enum':[0,1]},'pred':{'type':'integer','enum':[0,1]}}},
 'samples':{'type':'array','maxItems':32,'items':{'$ref':'#/$defs/sample'}}},
 '$defs':{'sample':{'type':'object','required':['sample_id','category','path','sha256','format','width','height','stride','roi','bayer_phase','normalized_raw_sha256','provenance','content_id'],
 'properties':{'sample_id':{'type':'string','pattern':'^[A-Za-z0-9_-]{1,80}$'},
 'category':{'enum':['sensor_capture','synthetic_control','historical_control']},'path':str_nonempty,'sha256':sha_spec,
 'format':{'enum':['packed_raw10','u16']},'width':{'type':'integer','minimum':4,'maximum':1920,'multipleOf':4},
 'height':{'type':'integer','minimum':2,'maximum':65535},'stride':{'type':'integer','minimum':5},
 'bayer_phase':{'enum':['unknown','RGGB','GRBG','GBRG','BGGR']},'phase_evidence':str_nonempty,
 'normalized_raw_sha256':sha_spec,'content_id':str_nonempty,
 'normalization':{'type':'object','required':['byte_order','valid_bits','right_shift'],
   'properties':{'byte_order':{'enum':['little','big']},'valid_bits':{'const':10},'right_shift':{'type':'integer','minimum':0,'maximum':6}}},
 'roi':{'type':'object','required':['x','y','width','height','source_width','source_height'],
   'properties':{k:{'type':'integer','minimum':0} for k in ['x','y','width','height','source_width','source_height']}},
 'provenance':{'type':'object','required':['source_kind','source','device','captured_at','license_basis','format_basis','sensor_pixel_oracle_verified'],
   'properties':{**{k:str_nonempty for k in ['source_kind','source','device','captured_at','license_basis','format_basis']},
      'sensor_pixel_oracle_verified':{'type':'boolean'},'pixel_oracle':{'type':'object',
       'required':['method','reviewer','correctness_basis','evidence_path','evidence_sha256','normalized_raw_sha256','review_decision'],
       'properties':{**{k:str_nonempty for k in ['method','reviewer','correctness_basis','evidence_path']},'evidence_sha256':sha_spec,'normalized_raw_sha256':sha_spec,'review_decision':{'const':'qualified'}}}}},
 },'allOf':[{'if':{'properties':{'format':{'const':'u16'}}},'then':{'required':['normalization']}},
 {'if':{'properties':{'category':{'const':'sensor_capture'}}},'then':{'properties':{'provenance':{'required':['pixel_oracle'],'properties':{'source_kind':{'const':'sensor_capture'},'sensor_pixel_oracle_verified':{'const':True}}}}}}]}}}
write('inputs/input-schema.json',schema)
write('inputs/deepseek-advice-review.json',{'task_id':'d70c71b8e82f440c9e15fd022ade8f91',
 'status':'completed_advice_only','project_root':str(ROOT),'operations_requested':0,'commands_executed_for_worker':0,
 'accepted_advice':['single-field missing/placeholder mutations','stride and group-length mismatch','u16 range and padding','phase mode rejection','control exclusion and null real summary'],
 'codex_review_limits':['endian declaration alone cannot detect all endian errors; normalized SHA/pixel evidence is required',
  'SHA proves byte binding, not factual provenance or sensor pixel correctness; independent review remains required'],
 'no_worker_final_verification':True})
write('inputs/runtime.json',{'python_executable':sys.executable,'python_version':sys.version,
 'dont_write_bytecode':sys.dont_write_bytecode,'third_party_dependencies':[]})
print('PREPARE_EVIDENCE_OK sources='+str(len(source_paths))+' real_sample_count=0')
