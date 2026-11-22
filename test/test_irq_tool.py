import pathlib
import sys
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tools'))
from test_irq import irq_test, EVENTS

class FakeSerial:
    def __init__(self, lines): self.lines = iter(lines); self.writes = []
    def write(self, data): self.writes.append(data); return len(data)
    def readline(self): return (next(self.lines, '') + '\n').encode()

class TestIrqTool(unittest.TestCase):
    def test_correct(self):
        ser = FakeSerial(EVENTS); reports = []
        irq_test(ser, reports.append)
        self.assertEqual(reports, list(EVENTS))
        self.assertEqual(ser.writes, [b'IRQ\n'])
    def test_wrong_order(self):
        with self.assertRaises(RuntimeError): irq_test(FakeSerial(['IRQ TX PASS']), lambda _: None)
    def test_esp_error(self):
        with self.assertRaisesRegex(RuntimeError, 'timer'):
            irq_test(FakeSerial(['ERR IRQ timer timeout']), lambda _: None)
