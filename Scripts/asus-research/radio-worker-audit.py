#!/usr/bin/env python3
"""Bounded static audit of two RF workers; not a transitive absence proof."""
from pathlib import Path
import hashlib,json,struct
import capstone
from capstone.arm import ARM_OP_MEM,ARM_REG_PC
root=Path(__file__).resolve().parents[2]
whole=next((root/'.build/asus-research/windows-live/keyboard').rglob('X807_KEYBOARD_V12_42_03.bin')).read_bytes()
assert hashlib.sha256(whole).hexdigest()=='5ee4e39b9d1ccd4509c2957546e60e198967a78ad057c0505b1910860c18b064'
b=whole[0x1f000:];d=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);d.detail=True
out=[]
for start,end in [(0x13768,0x13be4),(0x13c6c,0x14158)]:
 calls=[];literals=[];indirect=[]
 for i in d.disasm(b[start:end],start):
  if i.mnemonic=='bl':calls.append({'site':hex(i.address),'target':i.op_str})
  if i.mnemonic=='blx':indirect.append({'site':hex(i.address),'target':i.op_str})
  if i.mnemonic.startswith('ldr') and len(i.operands)>1:
   m=i.operands[1]
   if m.type==ARM_OP_MEM and m.mem.base==ARM_REG_PC:
    p=((i.address+4)&~3)+m.mem.disp
    value=struct.unpack_from('<I',b,p)[0]
    literals.append({'site':hex(i.address),'value':hex(value)})
 out.append({'start':hex(start),'end_exclusive':hex(end),'direct_calls':calls,'indirect_calls':indirect,'literal_loads':literals})
p=root/'.build/asus-research/windows-live/radio-worker-audit.json'
p.write_text(json.dumps({'limitations':['Linear decoding of bounded worker bodies; excludes callee-internal indirect calls, aliased memory and ROM implementations.','No claim of complete control-flow coverage or hardware behavior.'],'workers':out},indent=2))
for row in out:
 print(row['start'],'targets',sorted(set(x['target'] for x in row['direct_calls'])))
 print('slot/event literal hits',[x for x in row['literal_loads'] if x['value'] in ('0x2000172c','0x20001730','0x200016fc','0x2000d9c4')])
print('Artifact:',p)
