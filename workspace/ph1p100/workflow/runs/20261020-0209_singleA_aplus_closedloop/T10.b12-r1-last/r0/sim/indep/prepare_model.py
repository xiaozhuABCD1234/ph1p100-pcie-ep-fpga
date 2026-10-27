"""Copy only the frozen reference model; adapt its address range to b10 CMP_BASE."""
import hashlib, json, pathlib
here = pathlib.Path(__file__).resolve().parent
src = here.parent/'inputs/reference/recovery/ddr_recovery_model.sv'
data = src.read_bytes()
text = data.decode().replace('262143', '524287').replace('262144', '524288')
(here/'ddr_recovery_model.sv').write_text(text, encoding='utf-8')
(here/'model-adaptation.json').write_text(json.dumps({
    'source': str(src), 'source_sha256': hashlib.sha256(data).hexdigest(),
    'change': 'Memory depth and range guard 262144 -> 524288 words only; paired AW/W/read timing unchanged.',
    'output_sha256': hashlib.sha256((here/'ddr_recovery_model.sv').read_bytes()).hexdigest()
}, indent=2), encoding='utf-8')
