#!/usr/bin/env python3
"""Reproduce selected X807 Thumb disassembly; literal pools are not code.
Run with PYTHONPATH=.build/asus-research/python python3 this_script.py.
"""
import hashlib
from pathlib import Path
import capstone
root = Path(__file__).resolve().parents[2]
firmware = next((root / '.build/asus-research/windows-live/keyboard').rglob('X807_KEYBOARD_V12_42_03.bin'))
data = firmware.read_bytes()
assert hashlib.sha256(data).hexdigest() == '5ee4e39b9d1ccd4509c2957546e60e198967a78ad057c0505b1910860c18b064'
blocks = [(0x149d8,0x14b2e,'Shared lighting callback; FA falls through to 14b22'),
          (0x91a0,0x9212,'RGB cleanup called by shared callback'),
          (0x17bd8,0x17c58,'Physical selector sampling'),
          (0x10490,0x10580,'Mode classification'),
          (0x1570c,0x15778,'Demo-mode classification'),
          (0x90f4,0x9138,'Copy physical choice to active flags'),
          (0x127f4,0x128f4,'Local Bluetooth slot and demo toggle actions'),
          (0x128f4,0x12934,'Internal Bluetooth slot packet'),
          (0x11b00,0x11b8a,'Local pending-action reset'),
          (0x7344,0x7400,'Factory gate'),
          (0x756e,0x75a0,'RF factory forwarding'),
          (0x77ce,0x7848,'Reset commands')]
dis = capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB)
print('X807 12.42.03; flash base 0x08000000; literal pools may decode as instructions')
for start,end,label in blocks:
    print(f'\n## {label}')
    for ins in dis.disasm(data[start:end],0x08000000+start):
        print(f'{ins.address:08x}  {ins.mnemonic:9} {ins.op_str}')
