#!/usr/bin/env python3
"""Offline dispatcher harness, NOT full-device emulation. Never opens HID devices.
External callees are recorded/stubbed except memcpy/memzero. RAM comes from the firmware scatter loader, with synthetic mode flags.
Run with PYTHONPATH=.build/asus-research/python python3 this_script.py.
"""
import hashlib,json
from pathlib import Path
from unicorn import Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.arm_const import UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_PC
ROOT=Path(__file__).resolve().parents[2]
BIN=next((ROOT/'.build/asus-research/windows-live/keyboard').rglob('X807_KEYBOARD_V12_42_03.bin'))
b=BIN.read_bytes()
assert hashlib.sha256(b).hexdigest()=='5ee4e39b9d1ccd4509c2957546e60e198967a78ad057c0505b1910860c18b064'
FLASH=0x08000000; RAM=0x20000000; FLAGS=RAM+0x2a4; ACTION=RAM+0x27de

def startup_ram():
 u=Uc(UC_ARCH_ARM,UC_MODE_THUMB);u.mem_map(FLASH,0x80000);u.mem_write(FLASH,b)
 u.mem_map(RAM,0x10000);u.reg_write(UC_ARM_REG_SP,RAM+0xe000)
 u.emu_start(FLASH+0x631d,FLASH+0x6194,count=100000)
 assert u.reg_read(UC_ARM_REG_PC)==FLASH+0x6194, 'Scatter initialization did not finish'
 return bytes(u.mem_read(RAM,0x4000))

INITIAL_RAM=startup_ram()

def run(packet,flags=0x1000,state=None,return_state=False,entry=0x6a04,argument=None):
 u=Uc(UC_ARCH_ARM,UC_MODE_THUMB);u.mem_map(FLASH,0x80000);u.mem_write(FLASH,b)
 u.mem_map(RAM,0x10000);u.mem_write(RAM,INITIAL_RAM if state is None else state);u.mem_map(0x48000000,0x1000);u.mem_write(FLAGS,flags.to_bytes(4,'little')) if state is None else None
 u.mem_write(RAM+0xf000,bytes(packet).ljust(64,b'\0'))
 u.reg_write(UC_ARM_REG_R0,RAM+0xf000 if argument is None else argument);u.reg_write(UC_ARM_REG_SP,RAM+0xe000);u.reg_write(UC_ARM_REG_LR,FLASH+0x1f001)
 calls=[];writes=[];radio=[];count=0;done=False
 def write(uc,access,address,size,value,user):
  if address<FLAGS+4 and address+size>FLAGS or address<ACTION+1 and address+size>ACTION:
   writes.append({'pc':hex(uc.reg_read(UC_ARM_REG_PC)),'address':hex(address),'size':size,'value':hex(value)})
 def code(uc,address,size,user):
  nonlocal count,done
  count+=1
  if address==FLASH+0x1f000:done=True;uc.emu_stop();return
  if any(FLASH+lo<=address<FLASH+hi for lo,hi in ((0x6a04,0x7848),(0x7874,0x787a),(0x6894,0x68f2),(0x12f4c,0x1300c),(0x128f4,0x12924))):return
  args=[uc.reg_read(r) for r in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2)]
  calls.append({'address':hex(address),'args':[hex(x) for x in args]})
  if address==FLASH+0x174f4:
   radio.append({'channel':hex(args[0]),'payload':bytes(uc.mem_read(args[1],args[2])).hex(' '),'length':args[2]})
  if address==FLASH+0x6250:
   if args[2]>4096:raise ValueError('oversized memcpy')
   uc.mem_write(args[0],bytes(uc.mem_read(args[1],args[2])))
  elif address==FLASH+0x6282:
   if args[1]>4096:raise ValueError('oversized zero')
   uc.mem_write(args[0],bytes(args[1]))
  else:uc.reg_write(UC_ARM_REG_R0,0)
  uc.reg_write(UC_ARM_REG_PC,uc.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_MEM_WRITE,write)
 error=None
 try:u.emu_start(FLASH+entry+1,FLASH+0x1f002,count=10000)
 except (UcError,ValueError) as e:error=str(e)
 result = {'packet':bytes(packet).hex(' '),'initial_flags':hex(flags),'final_flags':hex(int.from_bytes(u.mem_read(FLAGS,4),'little')),'action':u.mem_read(ACTION,1)[0],'completed':done,'error':error,'instructions':count,'writes':writes,'calls':calls,'radio':radio}
 return (result,bytes(u.mem_read(RAM,0x4000))) if return_state else result

if __name__=='__main__':
 cases=[]
 for flags in (0x1000,0x40800,0x20400,0x1000|0x80):
  for sub in range(256):cases.append(run([0x51,sub,0,0,0],flags))
 for idx in range(10):cases.append(run([0x51,0x2c,idx,0,1,2,3,4]))
 controls=[run([0xfa,0,0xd6,0xa5]),run([0xfa,0,0,0],0x1080),run([0x51,0x20,4,0,5]),run([0x12,3])]
 assert all(c['completed'] and not c['error'] for c in controls), 'Control did not return'
 assert controls[0]['final_flags']=='0x1080' and controls[1]['final_flags']=='0x1000', 'Factory flag controls failed'
 assert not controls[2]['writes'] and not controls[3]['writes'], 'Unexpected mode-state control write'
 out={'limitations':['RAM initialized by real firmware scatter loader; application initialization and peripherals not modeled.','Dispatcher, configuration callback 6894, and brightness helpers 12f4c/12fd0 execute; remaining external calls return zero except modeled memcpy/memzero.','GPIO page 48000000 is synthetic zero memory; completion is harness completion, not hardware acceptance.','No coverage claim for external callee side effects or arbitrary payload values.'], 'controls':controls,'cases':cases}
 target=ROOT/'.build/asus-research/windows-live/usb-emulation.json';target.write_text(json.dumps(out,indent=2))
 print(json.dumps({'artifact':str(target),'cases':len(cases),'completed':sum(x['completed'] for x in cases),'errors':sum(x['error'] is not None for x in cases),'action_writes':sum(any(w['address']==hex(ACTION) for w in x['writes']) for x in cases),'controls':controls},indent=2))
