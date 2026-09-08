#!/usr/bin/env python3
"""Extract selected radio-parser evidence; addresses are radio-local, not main-MCU flash."""
from pathlib import Path
import hashlib,struct
import capstone
root=Path(__file__).resolve().parents[2]
whole=next((root/'.build/asus-research/windows-live/keyboard').rglob('X807_KEYBOARD_V12_42_03.bin')).read_bytes()
assert hashlib.sha256(whole).hexdigest()=='5ee4e39b9d1ccd4509c2957546e60e198967a78ad057c0505b1910860c18b064'
b=whole[0x1f000:]
assert struct.unpack_from('<II',b)==(0x20014000,0x2af81)
d=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB)
print('Radio-local address = package offset - 0x1f000. Literal pools/tables are not code.')
print('FA20 entries 0..5:',[hex(0x15a6e+2*x) for x in struct.unpack_from('<6H',b,0x15a6e)])
for a,z,label in [(0x13768,0x13be4,'Complete bounded RF worker 13768'),(0x13c6c,0x14158,'Complete bounded RF worker 13c6c'),(0x12ae8,0x12b2a,'PER and END packet construction'),(0x12f9c,0x1302e,'RF command handle setup'),(0x17156,0x171e4,'FA21 test worker and task selection'),(0x172a4,0x172c6,'Normal Bluetooth worker object'),(0x173ce,0x17400,'Slot event persistence and relay'),(0x18168,0x18180,'Main event object creation'),(0x17094,0x17156,'Test configuration helper'),(0x16b88,0x16be2,'FA05 iterates and reinitializes slots'),(0x17704,0x17754,'Per-slot identity generation'),(0x181c6,0x182aa,'Event worker including bit 9'),(0x13768,0x13804,'Worker 13768 entry'),(0x13be4,0x13c2a,'Worker 13be4 loop'),(0x13c6c,0x13d04,'Worker 13c6c entry'),(0x1718e,0x171e4,'FA21 additional worker creation'),(0x2af80,0x2af96,'Reset mapping validation'),(0x1569e,0x156f4,'Channel framing'),(0x15a36,0x15a6e,'FA command dispatch'),(0x15a7a,0x15a98,'FA20 early branches'),(0x15b86,0x15d3c,'FA test branches'),(0x15d3c,0x15d66,'Internal Bluetooth dispatch'),(0x15fd2,0x16018,'Pair and slot events'),(0x12340,0x123bc,'Asynchronous worker construction')]:
 print('\n##',label)
 for i in d.disasm(b[a:z],a):print(f'{i.address:08x} {i.mnemonic:9} {i.op_str}')
