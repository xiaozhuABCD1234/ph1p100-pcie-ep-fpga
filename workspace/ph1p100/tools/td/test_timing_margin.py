"""Negative controls for the explicit routed-margin gate."""
from pathlib import Path
import datetime
import unittest
from check_timing_margin import measure

BASE = Path('D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820/candidate_timing.rpt')


class ReportIntegrity(unittest.TestCase):
    def test_real_baseline_has_all_groups_and_misses_objective(self):
        result = measure(BASE)
        self.assertEqual(result['endpoint_groups'], 66)
        self.assertEqual(result['setup_ns'], 0)

    def test_truncated_report_is_rejected(self):
        raw = BASE.read_text().split('Max Paths', 1)[0]
        raw = raw.replace('SWNS: 0.000ns', 'SWNS: 0.300ns')
        folder = Path('D:/TD/work/csi2/_validation')/('timing_gate_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
        folder.mkdir()
        path = folder/'truncated.rpt'
        path.write_text(raw)
        with self.assertRaisesRegex(ValueError, 'endpoint groups'):
            measure(path)

    def test_invalid_expected_group_count_is_rejected(self):
        folder = Path('D:/TD/work/csi2/_validation')/('timing_gate_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
        folder.mkdir()
        path = folder/'header_only.rpt'
        path.write_text(BASE.read_text().split('Intra clock domain timing', 1)[0])
        with self.assertRaises(ValueError):
            measure(path, 0)


if __name__ == '__main__':
    unittest.main()
