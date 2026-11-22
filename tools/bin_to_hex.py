"""Padded byte-hex for the DE10-Nano Flash model. The .bin itself is unpadded."""
from pathlib import Path
import sys

image = Path(sys.argv[1]).read_bytes()
if len(image) > 4096 or not image:
    raise SystemExit("Expected a nonempty binary <= 4096 bytes")
Path(sys.argv[2]).write_text("".join(f"{b:02x}\n" for b in image.ljust(4096 if len(image)>2048 else 2048, b"\xff")))
