"""Unit sanity checks; never claim these replace actual board or RTL testing."""
import csv, pathlib, unittest, zlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
MASK=0xffffffff
class TestISAArtifact(unittest.TestCase):
    def test_random_vectors_manifest(self):
        with (ROOT/'docs/ISA_TORTURE_VECTOR_MAP.csv').open() as f: cases=list(csv.DictReader(f))
        self.assertEqual(len(cases),75)
        self.assertEqual([int(v['id']) for v in cases],list(range(41,116)))
        self.assertEqual({v['opcode'] for v in cases},
            {'add','sub','sll','slt','sltu','xor','srl','sra','or','and',
             'addi','slti','sltiu','xori','ori','andi','slli','srli','srai'})
    def test_assembled_lengths(self):
        for name in ['v10_isa_torture','v10_isa_strict_gp_tp']:
            b=(ROOT/f'firmware/{name}.bin').read_bytes()
            self.assertGreater(len(b),200)
            self.assertLessEqual(len(b),4096)
            self.assertNotEqual(zlib.crc32(b),0)
    def test_clock_metadata(self):
        self.assertIn('clock_hz: 50000000',(ROOT/'info.yaml').read_text())
        self.assertIn('"CLOCK_PERIOD": 20,',(ROOT/'src/config.json').read_text())
        self.assertIn('CLK_HZ=50000000',(ROOT/'src/tt_um_ctw_rv32_mcu.v').read_text())
        self.assertIn('CLK_HZ(50000000)',(ROOT/'ctw_de10_top.sv').read_text())
    def test_gp_tp_implemented_as_writable_gprs(self):
        s=(ROOT/'src/register.v').read_text()
        # x3 and x4 must use the same nibble-serial register storage as x5.
        self.assertNotIn('end else if (i == 3)',s)
        self.assertNotIn('end else if (i == 4)',s)
        self.assertNotIn('gen_reg_gp',s)
        self.assertNotIn('gen_reg_tp',s)
        self.assertIn('end else begin : gen_reg_normal',s)
        self.assertIn('registers[i][3:0] <= data_rd;',s)
        self.assertIn('assign reg_access[i] = registers[i][7:4];',s)
        self.assertIn('231', (ROOT/'firmware/v10_isa_strict_gp_tp.S').read_text())
        self.assertIn('232', (ROOT/'firmware/v10_isa_strict_gp_tp.S').read_text())
if __name__=='__main__':unittest.main()
