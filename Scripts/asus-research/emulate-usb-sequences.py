#!/usr/bin/env python3
"""Stateful offline record-write sequences. No HID access; inherits harness limitations."""
import runpy,struct,json
from pathlib import Path
m=runpy.run_path(str(Path(__file__).with_name('emulate-usb-handler.py')))
run=m['run']; initial=m['INITIAL_RAM']; firmware=m['b']
pointers=struct.unpack_from('<10I',initial,0x1bc)
# Length lookup used by dispatcher at 6f38: literal at 7288 minus ten.
length_base=struct.unpack_from('<I',firmware,0x7288)[0]-10-0x08000000
lengths=list(firmware[length_base:length_base+10])
results=[]
for flags in (0x1000,0x40800,0x20400):
 for factory in (False,True):
  for idx,ptr in enumerate(pointers):
   record=bytearray(initial[ptr-0x20000000:ptr-0x20000000+lengths[idx]])
   record[1]=25 # Valid-range brightness variation; not a switching payload.
   if idx in (4,5):parts=[(2,record[:14]),(1,record[14:30]),(0,record[30:37])]
   elif idx==7:parts=[(1,record[:14]),(0,record[14:26])]
   else:parts=[(0,record)]
   packets=([[0xfa,0,0xd6,0xa5]] if factory else [])
   packets += [[0x51,0x2c,idx,part]+list(data) for part,data in parts]
   packets += [[0x12,3]]
   if factory:packets += [[0xfa,0,0,0]]
   state=None;steps=[]
   for packet in packets:
    result,state=run(packet,flags,state,True);steps.append(result)
    if not result['completed']:break
   actual=state[ptr-0x20000000:ptr-0x20000000+len(record)]
   results.append({'flags':hex(flags),'factory':factory,'index':idx,'length':lengths[idx],
    'record_matches':actual==record,'final_flags':hex(int.from_bytes(state[0x2a4:0x2a8],'little')),
    'final_action':state[0x27de],'steps':steps})
assert all(all(s['completed'] for s in r['steps']) for r in results)
assert all(r['record_matches'] for r in results), 'Record sequence did not reproduce intended bytes'
assert all(r['final_flags']==r['flags'] and r['final_action']==0 for r in results)
out={'limitations':m.get('__doc__'),'lengths':lengths,'sequences':results}
p=m['ROOT']/'.build/asus-research/windows-live/usb-sequences.json';p.write_text(json.dumps(out,indent=2))
print(json.dumps({'artifact':str(p),'sequences':len(results),'packets':sum(len(r['steps']) for r in results),'all_records_match':all(r['record_matches'] for r in results),'lengths':lengths},indent=2))
