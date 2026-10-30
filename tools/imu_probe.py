import ctypes, ctypes.util, struct, time, statistics as st, sys
io=ctypes.cdll.LoadLibrary(ctypes.util.find_library('IOKit'))
cf=ctypes.cdll.LoadLibrary(ctypes.util.find_library('CoreFoundation'))
io.IOHIDCheckAccess.restype=ctypes.c_uint32; io.IOHIDCheckAccess.argtypes=[ctypes.c_uint32]
acc=io.IOHIDCheckAccess(0)
print("IOHIDCheckAccess(ListenEvent) =",acc,"(0=granted,1=denied,2=unknown)")
if acc!=0 and '--force' not in sys.argv: sys.exit(0)
V=ctypes.c_void_p
io.IOServiceMatching.restype=V; io.IOServiceMatching.argtypes=[ctypes.c_char_p]
io.IOServiceGetMatchingServices.argtypes=[ctypes.c_uint,V,ctypes.POINTER(ctypes.c_uint)]
io.IOIteratorNext.restype=ctypes.c_uint; io.IOIteratorNext.argtypes=[ctypes.c_uint]
io.IORegistryEntryCreateCFProperty.restype=V; io.IORegistryEntryCreateCFProperty.argtypes=[ctypes.c_uint,V,V,ctypes.c_uint]
io.IORegistryEntrySetCFProperty.restype=ctypes.c_int; io.IORegistryEntrySetCFProperty.argtypes=[ctypes.c_uint,V,V]
io.IOHIDDeviceCreate.restype=V; io.IOHIDDeviceCreate.argtypes=[V,ctypes.c_uint]
io.IOHIDDeviceOpen.restype=ctypes.c_int; io.IOHIDDeviceOpen.argtypes=[V,ctypes.c_int]
io.IOHIDDeviceRegisterInputReportWithTimeStampCallback.argtypes=[V,V,ctypes.c_long,V,V]
io.IOHIDDeviceScheduleWithRunLoop.argtypes=[V,V,V]
io.IOHIDDeviceGetReport.restype=ctypes.c_int; io.IOHIDDeviceGetReport.argtypes=[V,ctypes.c_int,ctypes.c_long,ctypes.c_void_p,ctypes.POINTER(ctypes.c_long)]
cf.CFStringCreateWithCString.restype=V; cf.CFStringCreateWithCString.argtypes=[V,ctypes.c_char_p,ctypes.c_uint32]
cf.CFNumberCreate.restype=V; cf.CFNumberCreate.argtypes=[V,ctypes.c_int,V]
cf.CFNumberGetValue.argtypes=[V,ctypes.c_int,V]
cf.CFRunLoopGetCurrent.restype=V; cf.CFRunLoopRunInMode.argtypes=[V,ctypes.c_double,ctypes.c_bool]
mode=V.in_dll(cf,'kCFRunLoopDefaultMode')
s=lambda x: cf.CFStringCreateWithCString(None,x.encode(),0x08000100)
def n(v): c=ctypes.c_int32(v); return cf.CFNumberCreate(None,3,ctypes.byref(c))
def pi(svc,k):
    r=io.IORegistryEntryCreateCFProperty(svc,s(k),None,0)
    if not r: return None
    v=ctypes.c_long(); cf.CFNumberGetValue(r,4,ctypes.byref(v)); return v.value
def svcs(c):
    it=ctypes.c_uint(); io.IOServiceGetMatchingServices(0,io.IOServiceMatching(c),ctypes.byref(it)); out=[]
    while True:
        x=io.IOIteratorNext(it.value)
        if not x: break
        out.append(x)
    return out
for d in svcs(b'AppleSPUHIDDriver'):
    for k,v in (('SensorPropertyReportingState',1),('SensorPropertyPowerState',1),('ReportInterval',1000)):
        io.IORegistryEntrySetCFProperty(d,s(k),n(v))
data={'accel':[], 'gyro':[]}
CB=ctypes.CFUNCTYPE(None,V,ctypes.c_int,V,ctypes.c_int,ctypes.c_uint32,ctypes.POINTER(ctypes.c_uint8),ctypes.c_long,ctypes.c_uint64)
def mk(name):
    def f(ctx,res,snd,rt,rid,rpt,ln,ts):
        if ln==22:
            b=bytes(rpt[:22]); seq=struct.unpack_from('<H',b,0)[0]; x,y,z,t=struct.unpack_from('<iiii',b,6)
            data[name].append((ts,seq,x,y,z,t))
    return CB(f)
cbs={'accel':mk('accel'),'gyro':mk('gyro')}; bufs=[]; lid=None
for d in svcs(b'AppleSPUHIDDevice'):
    up,u,sz=pi(d,'PrimaryUsagePage'),pi(d,'PrimaryUsage'),pi(d,'MaxInputReportSize')
    name={(0xff00,3):'accel',(0xff00,9):'gyro'}.get((up,u))
    if (up,u)==(0x20,0x8a): lid=io.IOHIDDeviceCreate(None,d); print("lid open:",io.IOHIDDeviceOpen(lid,0)); continue
    if not name or sz!=22: continue
    h=io.IOHIDDeviceCreate(None,d); r=io.IOHIDDeviceOpen(h,0); print(name,"open kr=",hex(r&0xffffffff))
    b=ctypes.create_string_buffer(4096); bufs.append(b)
    io.IOHIDDeviceRegisterInputReportWithTimeStampCallback(h,b,4096,cbs[name],None)
    io.IOHIDDeviceScheduleWithRunLoop(h,cf.CFRunLoopGetCurrent(),mode)
T=4.0; t0=time.time(); lids=[]
while time.time()-t0<T:
    cf.CFRunLoopRunInMode(mode,0.05,False)
    if lid:
        rb=(ctypes.c_uint8*8)(); ln=ctypes.c_long(8)
        kr=io.IOHIDDeviceGetReport(lid,2,1,rb,ctypes.byref(ln))
        if kr==0: lids.append((rb[1]|rb[2]<<8, list(rb[:ln.value])))
tb=ctypes.c_uint32*2
for name,L in data.items():
    if len(L)<10: print(name,"samples",len(L)); continue
    dt=(L[-1][0]-L[0][0])*125/3/1e9  # mach ticks 24MHz on Apple Silicon (125/3 ns)
    gaps=sum(((L[i][1]-L[i-1][1])&0xffff)-1 for i in range(1,len(L)))
    ax=[[r[k]/65536 for r in L] for k in (2,3,4)]
    print(f"{name}: n={len(L)} rate={len(L)/dt:.1f}Hz seqgaps={gaps} mean={[round(st.mean(a),4) for a in ax]} std={[round(st.pstdev(a),5) for a in ax]} lsb_min_step={min(abs(L[i][2]-L[i-1][2]) for i in range(1,len(L)) if L[i][2]!=L[i-1][2])} temp={L[-1][5]/65536:.2f}")
print("lid reads:",len(lids), "unique angles:",sorted(set(a for a,_ in lids))[:10], "example raw:", lids[0][1] if lids else None)
from math import gcd
from functools import reduce
for name,L in data.items():
    for k,ax in ((2,'x'),(3,'y'),(4,'z')):
        d=[abs(L[i][k]-L[i-1][k]) for i in range(1,len(L)) if L[i][k]!=L[i-1][k]]
        g=reduce(gcd,d) if d else 0
        v=[r[k]/65536 for r in L]
        # high-pass: first difference / sqrt2 as HF noise estimate
        hf=st.pstdev([(v[i]-v[i-1]) for i in range(1,len(v))])/2**0.5
        print(f"{name}.{ax}: raw step gcd={g} ({g/65536:.6g} units) hf_noise_rms={hf:.5f} p2p={max(v)-min(v):.4f}")
