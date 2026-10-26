import pathlib,fitz,json,hashlib,re
N=pathlib.Path(__file__).resolve().parents[1];out=[]
for name in ['SWUG105_TCL_Command_User_Guide.pdf','SWUG202_Advanced_Timing_Closure_User_Guide.pdf']:
    p=pathlib.Path('D:/anlogic/TD_Release_2026.2/doc/SWUG')/name;doc=fitz.open(p);hits=[]
    for i,page in enumerate(doc):
        text=page.get_text()
        if 'phys_opt' in text:
            for m in re.finditer('phys_opt',text):hits.append({'page':i+1,'excerpt':text[max(0,m.start()-250):m.start()+2400]})
    out.append({'source':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'hits':hits})
(N/'native-physopt-documentation.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
for d in out:
    print(d['source'])
    for h in d['hits'][-5:]:print(json.dumps(h))
