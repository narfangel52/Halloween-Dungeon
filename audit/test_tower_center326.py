from pathlib import Path
import ast,re
from lupa import LuaRuntime
module=ast.parse(Path('audit/test_tower324.py').read_text())
setup=next(n.value.value for n in module.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='setup'for t in n.targets))
s=Path('PolyLoot_Nerfangel_v3.lua').read_text();core=s[s.index('    local T={',s.index('-- Infinite Tower adapter:')):];core=core[:core.index('    local tab=Window:Tab')];core=re.sub(r'(T\.[\w]+)\s*\+=\s*([^;\n]+)',r'\1=\1+\2',core)
world='''
local T=TEST;T.run='ours';T.floor=90;T.active=true;T.token=1;T.readUi=function()return 'fight',90 end
T.updateNoclip=function()end
local folder=obj('Aggressors','Folder');function workspace:FindFirstChild(name)if name=='Animal_Live'then return {FindFirstChild=function()return folder end}end end
local function mob(name,x,z,hp,run)
 local n=obj(name,'Model',folder);n.pos=V(x,600,z);n.attributes={Animal=name,Health=hp,_TowerRun=run,_GroundY=600,Tier='Large',AttackType='Melee'};return n
end
local near=mob('Coral Knight',10,20,100,'ours');local far=mob('Beach Far',50,20,100,'ours');local other=mob('Other Party',10,20,100,'other')
local arena=obj('TowerArena','Model');arena.Parent=true
function arena:GetBoundingBox()return {Position=V(10,608,20),PointToObjectSpace=function(_,p)return p end},V(100,20,100)end
T.resolveArena=function()return arena end;T.inArena=function()return true end
Enum.RaycastFilterType.Include=2;RaycastParams={new=function()return {}end}
local rays=0;function workspace:Raycast(origin,direction,params)rays=rays+1;return {Position=V(10,600,20),Normal=V(0,1,0)}end
root.Position=V(0,603,0)
'''
def run(name,case):
 l=LuaRuntime();l.execute(setup);l.execute(core+'\nTEST=T');l.execute(world+case);print('PASS',name)
run('center uses confirmed arena floor, not bounding-box Y; caches and invalidates per run', '''
other.attributes._GroundY=-9000
local p=T.centerBase();assert(p.X==10 and p.Y==600 and p.Z==20 and rays==1)
assert(T.centerBase()==p and rays==1)
T.run='next';assert(T.centerBase().Y==600 and rays==2)
T.centerAnchor=nil;local count=0;function workspace:Raycast()count=count+1;return {Position=V(10,count==1 and 615 or 600,20),Normal=V(0,1,0)}end
assert(T.centerBase().Y==600 and count==2)
T.centerAnchor=nil;function workspace:Raycast()return nil end;assert(T.centerBase()==nil)
''')
run('fixed center XZ, target-facing hover, rejected teleport backoff and cancellation', '''
local p=V(10,610,20);T.centerAnchor=V(10,600,20)
assert(T.centerHold(p,1,far));assert(root.Position.X==10 and root.Position.Z==20 and root.Position.Y==610)
assert(T.airOrientation.CFrame.target.X==far.pos.X)
far.pos=V(80,600,80);assert(T.centerHold(p,1,far));assert(root.Position.X==10 and root.Position.Z==20)
root.Position=V(0,603,0);clock=20;function char:PivotTo()end
assert(not T.centerHold(p,1,far));assert(T.nextCenterMove==21)
clock=22;afterWait=function()T.stop('cancel')end;assert(not T.centerHold(p,1,near));assert(not T.active and not T.airObjects and hum.AutoRotate and not hum.PlatformStand)
''')
run('nearby-target gate, priorities, disabled types and foreign-run rejection', '''
root.Position=V(10,610,20)
assert(T.centerTarget(root.Position)==near)
local high=mob('Priority',14,20,100,'ours');T.profile(high).priority=10
assert(T.centerTarget(root.Position)==high)
T.profile(high).enabled=false;assert(T.centerTarget(root.Position)==near)
near.pos=V(30,600,20);assert(T.centerTarget(root.Position)==nil)
''')
run('HP loss increases height conservatively with cooldown/ceiling; species observations exclude other runs', '''
root.Position=V(10,610,20);T.centerObserve();assert(T.centerMetrics.mobs['Coral Knight [Large]'] and not T.centerMetrics.mobs['Other Party [Large]'])
clock=11;hum.Health=80;T.centerObserve();assert(T.centerHeight()==12 and T.centerMetrics.healthLost==20)
clock=12;hum.Health=70;near.attributes.Health=90;T.centerObserve();assert(T.centerHeight()==12 and T.centerMetrics.npcHealthDrops==1)
clock=15;hum.Health=60;T.centerObserve();assert(T.centerHeight()==14)
clock=19;hum.Health=50;T.centerObserve();assert(T.centerHeight()==16)
clock=23;hum.Health=40;T.centerObserve();assert(T.centerHeight()==16)
assert(T.centerMetrics.heights['10.0'].damageEvents==1)
T.centerAutoHeight=false;T.centerLift=0;clock=30;hum.Health=30;T.centerObserve();assert(T.centerHeight()==10)
T.centerLift=6;T.airHeight=25;assert(T.centerHeight()==25)
''')
run('center farm waits without chasing, diving or collecting; attacks only after mobs approach', '''
T.centerBase=function()return V(10,600,20)end
T.compareOwnedWeapons=function()return sword end
T.selectEnemy=function()error('old pursuit used')end;T.airTrack=function()error('enemy-following used')end
T.filteredCollect=function()error('combat collection used')end
near.pos=V(40,600,20);root.Position=V(0,603,0)
T.combatLoot=true;T.unstickActive=true;T.unstickTarget=far
T.step(1);assert(root.Position.X==10 and root.Position.Z==20 and root.Position.Y==610 and not attacks and T.airObjects and not T.unstickActive)
near.pos=V(10,600,20);clock=12;T.step(1);assert(attacks==1 and root.Position.X==10 and root.Position.Z==20 and root.Position.Y==610)
near.attributes.Health=0;clock=14;T.step(1);assert(attacks==1 and T.airObjects)
''')
print('All center-mode tests passed with mocked Roblox state; no live damage immunity verification.')
