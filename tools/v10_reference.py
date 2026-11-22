"""Independent Python arithmetic reference for the V10 stress firmware."""
MASK = 0xFFFFFFFF
INITIAL_SIGNATURE = 0x31415926

def mix(x: int) -> int:
    x &= MASK
    x ^= (x << 13) & MASK
    x ^= x >> 17
    x ^= (x << 5) & MASK
    return x & MASK

def advance(signature: int, sequence: int, count: int) -> int:
    for round_number in range(sequence, sequence + count):
        seed = mix(signature ^ round_number ^ 0xA512BC34)
        for i in range(32):
            a = mix((seed + i * 0x00010101) & MASK)
            b = (~a) & MASK
            signature = mix(signature ^ a ^ (b >> 3))
    return signature
