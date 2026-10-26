import sys,pathlib,concurrent.futures,json
sys.dont_write_bytecode=True
p=pathlib.Path(__file__).resolve().parent;sys.path.insert(0,str(p));import run_abort
jobs=[(n,r+'-final') for r in ('slow','fast') for n in run_abort.CASES]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 futures=[pool.submit(run_abort.run,'corrected',n,r) for n,r in jobs]
 results=[f.result() for f in futures]
assert len(results)==20 and all(r['status']=='PASS' for r in results)
(p/'matrix-results-resume02.json').write_text(json.dumps(dict(status='LOCAL_PASS',final_TB_results=results),indent=2))
print('RESUME02_MATRIX_20_FRESH_PASS',flush=True)
