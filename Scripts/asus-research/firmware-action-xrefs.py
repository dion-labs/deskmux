#!/usr/bin/env python3
"""Conservative literal-reference audit; candidates need manual instruction alignment review."""
from pathlib import Path
import hashlib
import struct
import capstone
from capstone.arm import ARM_OP_MEM, ARM_REG_PC
root = Path(__file__).resolve().parents[2]
b = next((root / '.build/asus-research/windows-live/keyboard').rglob('X807_KEYBOARD_V12_42_03.bin')).read_bytes()
assert hashlib.sha256(b).hexdigest() == '5ee4e39b9d1ccd4509c2957546e60e198967a78ad057c0505b1910860c18b064'
d = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
d.detail = True
print('PC-relative loads pointing into local action state 200027c4..200027e3:')
for off in range(0x6000, 0x19000, 2):
    ins = next(d.disasm(b[off:off+4], 0x08000000+off, count=1), None)
    if not ins or not ins.mnemonic.startswith('ldr') or len(ins.operands) < 2:
        continue
    m = ins.operands[1]
    if m.type != ARM_OP_MEM or m.mem.base != ARM_REG_PC:
        continue
    p = ((ins.address+4)&~3) + m.mem.disp - 0x08000000
    if 0 <= p <= len(b)-4:
        value = struct.unpack_from('<I', b, p)[0]
        if 0x200027c4 <= value <= 0x200027e3:
            print(f'{ins.address:08x} {ins.mnemonic} {ins.op_str} -> {value:08x}')
print('\nFn numeric-key TBB destinations (HID usages 1e..24):')
for n, value in enumerate(b[0x121e4:0x121eb]):
    print(f'usage {0x1e+n:02x} -> {0x080121e4+2*value:08x}')
print('\nLimit: no MOVW/MOVT, aliased pointers, indirect calls, or other processor images tracked.')
