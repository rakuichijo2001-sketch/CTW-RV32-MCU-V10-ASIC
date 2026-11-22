import io
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))

from test_sensor import sensor_test, SEQUENCE


class Link(io.BytesIO):
    def __init__(self, replies):
        super().__init__(replies)
        self.tx = b""

    def write(self, value):
        self.tx += value
        return len(value)


class SensorToolTest(unittest.TestCase):
    def test_all_frames(self):
        link = Link("".join(f"SAMPLE {v} {3*v+7}\n" for v in SEQUENCE).encode() + b"SENSOR PASS 8\n")
        output = []
        sensor_test(link, output.append)
        self.assertEqual(link.tx, b"SENSOR\n")
        self.assertEqual(len(output), 8)

    def test_bad_result_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Wrong sensor frame"):
            sensor_test(Link(b"SAMPLE 7 27\n"), lambda s: None)

    def test_early_pass_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "ended before"):
            sensor_test(Link(b"SENSOR PASS 8\n"), lambda s: None)

    def test_esp_error_reported(self):
        with self.assertRaisesRegex(RuntimeError, "SENSOR timeout"):
            sensor_test(Link(b"ERR SENSOR timeout sample=7 bytes=0\n"), lambda s: None)
