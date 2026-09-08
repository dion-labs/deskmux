#!/usr/bin/env python3
"""Offline USB-to-radio boundary capture; queue call recorded, not transmitted."""
import runpy,json
from pathlib import Path
m=runpy.run_path(str(Path(__file__).with_name('emulate-usb-handler.py')));run=m['run']
cases=[]
for flags in (0x1000,0x1080,0x40880):
 for value in range(256):
  cases.append(run([0xfa,0x20,value,0,0x91],flags))
 for sub in (5,0x21,0x22,0x23):
  for value in (0,1,0x91):
   parameter=[0x7b,0x9f] if sub==0x23 else [value,0]
   cases.append(run([0xfa,sub]+parameter+[value,0,0],flags))
controls=[run([],0x40800,entry=0x128f4,argument=slot) for slot in range(3)]
assert all(c['completed'] for c in cases+controls)
assert all(c['radio']==[{'channel':'0x35','payload':f'91 {slot:02x} 00 00 00','length':5}] for slot,c in enumerate(controls))
assert all(p['channel']=='0x34' for c in cases for p in c['radio'])
assert all(p['payload'].startswith('fa ') for c in cases for p in c['radio'])
out={'limitations':['Radio enqueue is intercepted before execution; capture proves arguments, not delivery.','Inherited synthetic state, GPIO and external-call stubs; selected forwarding paths only.'], 'cases':cases,'controls':controls}
p=m['ROOT']/'.build/asus-research/windows-live/radio-forwarding.json';p.write_text(json.dumps(out,indent=2))
print(json.dumps({'artifact':str(p),'cases':len(cases),'captured':sum(len(c['radio']) for c in cases),'channels':sorted(set(p['channel'] for c in cases for p in c['radio'])),'positive_controls':len(controls)},indent=2))
