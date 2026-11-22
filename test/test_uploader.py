"""Unit tests of binary preservation, reply validation and error handling."""
import importlib.util
import pathlib
import unittest
import zlib

root = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("upload_esp32", root / "tools/upload_esp32.py")
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


class FakeSerial:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.writes = []

    def write(self, data):
        self.writes.append(data)
        return len(data)

    def readline(self):
        return next(self.replies)

    def flush(self):
        pass


class UploaderTest(unittest.TestCase):
    data = b"\x00\xff\n\x80"
    crc = zlib.crc32(data) & 0xFFFFFFFF

    def test_binary_and_integrity(self):
        s = FakeSerial([b"READY\n", f"OK 0004 {self.crc:08X} RUN\n".encode()])
        self.assertEqual(u.upload(s, self.data), (4, self.crc))
        self.assertEqual(s.writes, [f"CTW3 4 {self.crc:08X}\n".encode(), self.data])

    def test_reject_failed_target(self):
        s = FakeSerial([b"READY\n", b"ERR FLASH readback mismatch\n"])
        with self.assertRaisesRegex(RuntimeError, "readback"):
            u.upload(s, self.data)

    def test_reject_different_crc(self):
        s = FakeSerial([b"READY\n", f"OK 0004 {self.crc ^ 1:08X} RUN\n".encode()])
        with self.assertRaisesRegex(RuntimeError, "different"):
            u.upload(s, self.data)


if __name__ == "__main__":
    unittest.main()
