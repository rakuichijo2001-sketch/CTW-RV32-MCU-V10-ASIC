"""Host script protocol regression; does not simulate RTL or ESP32 hardware."""
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from test_v9 import v9_test


class Stub:
    def __init__(self, lines):
        self.lines = iter(lines)
        self.writes = []

    def write(self, data):
        self.writes.append(data)
        return len(data)

    def readline(self):
        return next(self.lines, b'')


class V9ToolTest(unittest.TestCase):
    def test_valid(self):
        serial = Stub([b'V9 PWM PASS duty0=25% duty1=75%\n',
                       b'V9 I2C WRITE PASS 0x5A\n',
                       b'V9 I2C READ PASS 0xC3\n',
                       b'V9 PASS ALL\n'])
        v9_test(serial, lambda _: None)
        self.assertEqual(serial.writes, [b'V9\n'])

    def test_mismatch(self):
        serial = Stub([b'V9 PWM PASS duty0=25% duty1=75%\n',
                       b'V9 I2C WRITE PASS 0x00\n'])
        with self.assertRaises(RuntimeError):
            v9_test(serial, lambda _: None)


if __name__ == '__main__':
    unittest.main()
