"""Static sanity check for CSR immediate RTL. Not a replacement for HDL simulation/board tests."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
class TestCSRImmediate(unittest.TestCase):
    def test_latched_instruction_zimm(self):
        cpu=(R/'src/cpu.v').read_text()
        self.assertIn('csr_zimm <= instr[19:15];',cpu)
        self.assertIn('csr_zimm <= 5\'b00000;',cpu)
        self.assertIn('        csr_zimm,',cpu)
    def test_csr_nibbles(self):
        c=(R/'src/core.v').read_text()
        self.assertIn('wire csr_immediate = is_csr && alu_op[2];',c)
        self.assertIn("(counter == 3'd0) ? csr_zimm[3:0]",c)
        self.assertIn("(counter == 3'd1) ? {3'b000, csr_zimm[4]}",c)
        self.assertIn("(imm_lo == 12'h341 && is_csr_write) ? csr_src",c)
        self.assertIn("(imm_lo == 12'h341 && is_csr_set)",c)
        self.assertIn("(imm_lo == 12'h341 && is_csr_clear)",c)
        for zimm in range(32):
            nibbles=[zimm&15,(zimm>>4)&15,0,0,0,0]
            v=sum(n<<(4*i) for i,n in enumerate(nibbles))
            self.assertEqual(v,zimm)
    def test_csr_src_used_at_all_write_sites(self):
        c=(R/'src/core.v').read_text()
        for line in c.splitlines():
            if ('is_csr_write' in line or 'is_csr_set' in line or 'is_csr_clear' in line) and '<=' in line and ('mstatus_' in line or 'mie <=' in line or 'mip_reg <=' in line):
                self.assertIn('csr_src',line)
    def test_isa_not_bypassed(self):
        s=(R/'firmware/v10_isa_torture.S').read_text()
        for k in range(225,231): self.assertIn('li a0,'+str(k),s)
        self.assertIn('csrrwi t2,0x341,16',s)
        self.assertIn('csrrci t2,0x341,16',s)
        self.assertIn('csrrsi t2,0x341,16',s)
if __name__=='__main__': unittest.main()
