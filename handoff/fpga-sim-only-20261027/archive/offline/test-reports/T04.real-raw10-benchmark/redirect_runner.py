"""Tester wrapper: only HERE output roots are redirected in memory; source stays frozen."""
import contextlib
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
EVIDENCE = Path(__file__).resolve().parent
PROJECT = EVIDENCE.parents[4]
PACKAGE = EVIDENCE.parent.parent / 'T04.real-raw10-benchmark'

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

def main():
    operation = sys.argv[1]
    b = load('benchmark', PACKAGE / 'benchmark.py')
    assert b.ROOT == PROJECT
    assert Path(b.ref.__file__).resolve() == PROJECT / 'tools/codec/a1_ref.py'
    assert Path(b.strict.__file__).resolve() == PROJECT / 'tools/codec/a1_inflate_strict.py'
    binding = {name: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
               for name, path in [('benchmark', PACKAGE / 'benchmark.py'),
                                  ('verify_controls', PACKAGE / 'verify_controls.py'),
                                  ('reference', PROJECT / 'tools/codec/a1_ref.py'),
                                  ('strict_parser', PROJECT / 'tools/codec/a1_inflate_strict.py')]}
    binding.update(original_HERE=str(b.HERE), redirected_HERE=str(EVIDENCE), unchanged_ROOT=str(b.ROOT),
                   environment_rule='Only benchmark.HERE and verify_controls.HERE globals change; no source, algorithm, threshold, classification, or validator edits.',
                   executable=sys.executable, python_version=sys.version, dont_write_bytecode=sys.dont_write_bytecode)
    if operation == 'controls':
        empty = {'schema_version': 1, 'mode': {'prep': 0, 'pred': 0}, 'samples': []}
        outside = EVIDENCE / 'must-not-exist-original-boundary'
        assert not outside.exists()
        try:
            b.run(empty, PACKAGE / 'inputs', outside)
        except ValueError as exc:
            assert str(exc) == 'output outside task package'
            binding['original_output_boundary_observation'] = {'result': 'reject', 'reason': str(exc), 'output_created': outside.exists()}
        else:
            raise AssertionError('original output boundary accepted outside HERE')
        assert not outside.exists()
    b.HERE = EVIDENCE
    (EVIDENCE / ('redirect-' + operation + '.json')).write_text(json.dumps(binding, indent=2) + '\n', encoding='utf-8')
    if operation == 'controls':
        v = load('verify_controls', PACKAGE / 'verify_controls.py')
        assert v.b is b
        v.HERE = EVIDENCE
        sys.argv = [str(PACKAGE / 'verify_controls.py'), 'controls-rerun']
        v.main()
        return 0
    if operation == 'empty-cli':
        sys.argv = [str(PACKAGE / 'benchmark.py'), '--config', str(PACKAGE / 'inputs/real-inputs.json'), '--output', str(EVIDENCE / 'empty-real-cli')]
        return b.main()
    raise ValueError('unknown operation')

if __name__ == '__main__':
    sys.exit(main())
