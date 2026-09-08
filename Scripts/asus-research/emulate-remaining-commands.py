#!/usr/bin/env python3
"""Final bounded command-surface pass, offline only; inherits all harness limitations."""
import runpy,json
from pathlib import Path
m=runpy.run_path(str(Path(__file__).with_name('emulate-usb-handler.py')));run=m['run']
rows=[]
for flags in (0x1000,0x40800,0x20400):
 for opcode in (0x12,0x41,0x43,0x50,0x52,0x53,0xc0):
  for sub in range(256):rows.append(run([opcode,sub,0,0,0],flags))
# Check top-level default dispatch without reset/bootloader entry commands.
for opcode in range(256):
 if opcode not in (0x7b,0xfd):rows.append(run([opcode,0,0,0,0]))
p=m['ROOT']/'.build/asus-research/windows-live/remaining-commands.json'
p.write_text(json.dumps({'limitations':['Selected zero-parameter packets, not arbitrary payloads.','External stubs and lack of main-loop execution exclude delayed side effects.','Reset/bootloader opcodes omitted from default-dispatch pass.'],'cases':rows},indent=2))
print(json.dumps({'artifact':str(p),'cases':len(rows),'completed':sum(c['completed'] for c in rows),'errors':[(c['packet'],c['error']) for c in rows if c['error']],'watched_writes':[(c['packet'],c['writes']) for c in rows if c['writes']],'radio':[(c['packet'],c['radio']) for c in rows if c['radio']],'callees':sorted(set(a['address'] for c in rows for a in c['calls']))},indent=2))
