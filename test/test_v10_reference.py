import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from v10_reference import mix,advance,INITIAL_SIGNATURE
from test_v10 import request

class FakeSer:
    def __init__(self,lines):self.lines=iter(lines);self.sent=[]
    def write(self,data):self.sent.append(data);return len(data)
    def readline(self):return next(self.lines,b'')

class StressReferenceTest(unittest.TestCase):
    def test_prng_is_bounded(self):
        self.assertEqual(mix(0),0)
        self.assertTrue(0<=mix(0xffffffff)<=0xffffffff)
    def test_advancement_matches_sequential_chunks(self):
        a=advance(INITIAL_SIGNATURE,0,4)
        b=advance(a,4,16)
        c=advance(INITIAL_SIGNATURE,0,20)
        self.assertEqual(b,c)
    def test_frame_parse(self):
        port=FakeSer([b'V10 H seq=00000010 sig=12345678 wd=1\n'])
        self.assertEqual(request(port,'H'),(16,0x12345678,1))
        self.assertEqual(port.sent,[b'V10H\n'])
    def test_frame_rejects_wrong_opcode(self):
        port=FakeSer([b'V10 S seq=00000010 sig=12345678 wd=1\n'])
        with self.assertRaises(RuntimeError):request(port,'H',timeout=.01)
if __name__=='__main__': unittest.main()
