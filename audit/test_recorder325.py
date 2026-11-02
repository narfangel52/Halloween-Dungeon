from pathlib import Path
import json,re
from lupa import LuaRuntime
s=Path('PolyLoot_Nerfangel_v3.lua').read_text();s=s[s.index('    local R={',s.index('-- Passive, bounded diagnostic recording.')):];s=s[:s.index('    local tab=Window:Tab')]
s=re.sub(r'([\w.]+(?:\[[^\]]+\])?)\s*\+=\s*([^;\n]+)',r'\1=\1+\2',s)
l=LuaRuntime(unpack_returned_tuples=True)
def to_python(v):
 if hasattr(v,'items'):return {str(k):to_python(x)for k,x in v.items()}
 return v
l.globals().encode_json=lambda _,v:json.dumps(to_python(v),ensure_ascii=False,allow_nan=False)
l.execute('''
clock=0;os.clock=function()return clock end
function typeof(v)return type(v)end
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local mt={};function V(x,y,z)return setmetatable({X=x,Y=y,Z=z},mt)end
mt.__sub=function(a,b)return V(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
mt.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)end end
root={Position=V(0,10,0),CFrame={LookVector=V(0,-1,0),UpVector=V(1,0,0)},AssemblyLinearVelocity=V(0,0,0)}
hum={Health=100,MaxHealth=100,PlatformStand=false,AutoRotate=true,GetState=function()return {Name='Running'}end}
weapon={Name='Halloween Greatsword',GetAttributes=function()return {WeaponId='Halloween Greatsword'}end}
function getRoot()return root end;function getCharacter()return 'character'end;function getHumanoid()return hum end;function getWeapon()return weapon end
function getNearbyDrops()return {}end
local event={listeners={}};function event:Connect(fn)local c={connected=true};function c:Disconnect()self.connected=false end;self.listeners[#self.listeners+1]={fn=fn,c=c};return c end
remote={OnClientEvent=event,IsA=function(_,c)return c=='RemoteEvent'end,GetFullName=function()return 'Tower_Engine.Remotes.Push'end}
rs={};workspace={};game={PlaceId=123,GetService=function(_,name)if name=='HttpService'then return {JSONEncode=encode_json}else return rs end end}
playerGui={GetChildren=function()return {}end};gui={Parent=true};frame={Visible=true}
local T={active=false,floor=90,wave=1,waves=3,run='our_run',airHeight=10,noclip=true}
T.node=function(parent,...)if parent==rs then return remote end end
T.readUi=function()return 'fight',90,nil end
T.airTrack=function()return false,nil,'third'end
T.quickSwitchEquip=function()return nil,'missing',nil end
T.click=function()return true,'sent'end
T.start=function()T.active=true;return 'started',nil,5 end
PRO={tower=T,log=function()return 'logged'end}
jobs={};task={spawn=function(fn)jobs[#jobs+1]=fn end,wait=function(n)clock=clock+n end}
''')
l.execute(s+'\nREC=R')
l.execute('''
local R=REC
assert(not R.active and R.events.size==0)
-- Small custom ring verifies retention and chronological extraction.
local q={capacity=3,first=1,size=0,total=0,items={}}
for i=1,7 do R.push(q,{n=i})end
local rows=R.rows(q);assert(q.size==3 and q.total==7 and rows[1].n==5 and rows[3].n==7)
R.start();assert(R.active and #R.connections==3 and #jobs==1)
local cycle={};cycle.self=cycle;assert(R.safe(cycle).self=='<limite>')
assert(#R.safe(string.rep('x',400))==240)
R.changed('test','same',{value=1});local total=R.events.total;R.changed('test','same',{value=1});assert(R.events.total==total)
R.sample();assert(R.samples.size==1);local sample=R.rows(R.samples)[1];assert(sample.data.health==100 and sample.data.weapon=='Halloween Greatsword' and sample.data.tower.floor==90)
local n=select('#',PRO.tower.quickSwitchEquip('Hammer',1));assert(n==3)
assert(select(2,PRO.tower.quickSwitchEquip('Hammer',1))=='missing')
assert(PRO.log('hello')=='logged')
for i=1,1200 do R.add('overflow',{index=i})end
assert(R.events.size==1000 and R.events.total>1200)
local full=R.report(false);local summary=R.report(true)
assert(full:find('NERFANGEL GRAVADOR',1,true) and full:find('samplesRetained',1,true))
assert(#full>#summary)
local old=R.events.total;local connections=R.connections;R.stop('test');assert(not R.active and #R.connections==0)
for _,c in ipairs(connections)do assert(not c.connected)end
old=R.events.total;R.add('after_stop',{});assert(R.events.total==old)
R.start();assert(R.active and R.samples.size==0 and R.events.size==1)
R.timeLimit=true;R.duration=1;R.interval=0.5;jobs[#jobs]();assert(not R.active and R.samples.size==2)
-- Auto-start wrapper preserves Tower.start return arity and values.
local a,b,c=PRO.tower.start();assert(R.active and a=='started' and b==nil and c==5)
R.stop('end')
''')
print('PASS recorder: bounded chronological ring, cycle/depth/string bounds, change suppression, real sample fields, wrapped return arity, log return, overflow retention, full/summary report, disconnect and stopped writes, new-session reset, timed stop, automatic start')
