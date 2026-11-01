from pathlib import Path
import ast,re
from lupa import LuaRuntime
shared=ast.parse(Path('audit/test_tower324.py').read_text())
setup=next(n.value.value for n in shared.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='setup'for t in n.targets))
source=Path('PolyLoot_Torre_Simples.lua').read_text();core=source[:source.index('-- Interface:')]
core=re.sub(r'([\w.]+)\s*\+=\s*([^;\n]+)',r'\1=\1+\2',core)
extra='''
rs={PreSimulation=event()};storage={}
player.Character=char;char.children.HumanoidRootPart=root;root.Parent=char;root.CanCollide=true
function root:IsA(c)return c=='BasePart'end;function root:GetDescendants()return {}end
function char:FindFirstChildOfClass(c)if c=='Humanoid'then return hum end;for _,o in ipairs(self:GetChildren())do if o:IsA(c)then return o end end end
function player:WaitForChild(n)return playerGui end
local get=game.GetService;game.GetService=function(g,n)if n=='Players'then return {LocalPlayer=player}elseif n=='RunService'then return rs elseif n=='ReplicatedStorage'then return storage else return get(g,n)end end
function getWeapon()return equipped end
jobs={};task.spawn=function(fn)jobs[#jobs+1]=fn end
'''
exports='''
gui={Parent=true,Enabled=true}
TEST={state=S,phase=phase,eligible=eligible,target=target,weapon=weapon,move=moveAbove,stop=stop,start=start,step=step,click=click,push=onPush,release=releaseHover,hover=hover}
'''
def run(name,case):
 l=LuaRuntime();l.execute(setup);l.execute(extra);l.execute(core+exports);l.execute(case);print('PASS',name)
ui='''
local hud=obj('TowerRunV5','ScreenGui',playerGui)
local intro=obj('Intro','Frame',hud);intro.Visible=false;local ih=obj('Head','Frame',intro);obj('Title','TextLabel',ih,'FLOOR 90')
local ready=obj('Ready','Frame',intro);local rb=obj('Btn','TextButton',ready);local bg=obj('Background','Frame',ready);local f=obj('Frame','Frame',bg);local rl=obj('Label','TextLabel',f,'READY')
local result=obj('Result','Frame',hud);result.Visible=false;local rh=obj('Head','Frame',result);local rt=obj('Title','TextLabel',rh,'CLEARED!');obj('Floor','TextLabel',rh,'FLOOR 90')
local again=obj('Again','Frame',result);local ab=obj('Btn','TextButton',again);bg=obj('Background','Frame',again);f=obj('Frame','Frame',bg);local al=obj('Label','TextLabel',f,'NEXT FLOOR')
local bar=obj('Bar','Frame',hud);local crest=obj('Crest','Frame',hud);obj('Words','TextLabel',crest,'Floor 90')
'''
world='''
local runs=obj('TowerRuns','Folder');local ar=obj('TowerArena_LongHall','Model',runs);ar.attributes.TowerFloor=90
function ar:GetBoundingBox()return {Position=V(0,0,0),PointToObjectSpace=function(_,v)return v end},V(200,20,200)end
local live=obj('Animal_Live','Folder');local folder=obj('Aggressors','Folder',live)
function workspace:FindFirstChild(n)if n=='TowerRuns'then return runs elseif n=='Animal_Live'then return live end end
local function npc(name,x,hp,run)
 local o=obj(name,'Model',folder);o.attributes={Animal=name,Health=hp,_TowerRun=run};o.pos=V(x,0,0);function o:GetPivot()return {Position=self.pos}end;return o
end
local a=npc('Coral Knight',0,100,'ours');local b=npc('Beach Monster',20,100,'ours');local foreign=npc('Other Party',1,100,'other')
'''
run('manual entry required; weapon retained; only current arena/run live NPCs; stable target', ui+world+'''
local S=TEST.state;S.active=true;S.token=1;S.floor=90;S.run='ours'
local chosen=TEST.target();assert(chosen==a)
b.pos=V(0,0,0);assert(TEST.target()==a)
a.attributes.Health=0;assert(TEST.target()==b)
b.pos=V(1000,0,0);assert(TEST.target()==nil)
assert(TEST.weapon()==sword or TEST.weapon()==hammer)
assert(#jobs==0);hud.Enabled=false;S.active=false;TEST.start();assert(not S.active and #jobs==0)
''')
run('hover, teleport above target, downward aim, no duplicate pivot, rejected movement backoff',ui+world+'''
local S=TEST.state;S.active=true;S.token=1;S.floor=90;S.run='ours';S.height=10
root.Position=V(50,3,0);local moves=0
function char:PivotTo(cf)moves=moves+1;root.Position=cf.pos end
assert(TEST.move(a,1));assert(moves==1 and root.Position.Y==10 and S.hover.orientation.CFrame.target.Y==0)
assert(TEST.move(a,1)and moves==1)
root.Position=V(50,3,0);clock=20;function char:PivotTo(cf)moves=moves+1 end
assert(not TEST.move(a,1)and S.moveFailures==1);local old=moves
assert(not TEST.move(a,1)and moves==old)
TEST.stop('test');assert(not S.active and hum.AutoRotate and not hum.PlatformStand and not S.hover)
''')
run('cancellation after teleport prevents attack and preserves original Humanoid flags',ui+world+'''
local S=TEST.state;S.active=true;S.token=1;S.floor=90;S.run='ours'
hum.AutoRotate=false;hum.PlatformStand=true;root.Position=V(50,3,0)
afterWait=function()TEST.stop('cancelled')end
assert(not TEST.move(a,1));assert(not S.active and not S.hover and not hum.AutoRotate and hum.PlatformStand)
''')
run('scoped noclip restores original and removed part collision values',ui+'''
local S=TEST.state;S.active=true;S.token=1
local solid=obj('Leg','BasePart',char);solid.CanCollide=true
local ghost=obj('Ghost','BasePart',char);ghost.CanCollide=false
TEST.hover(root,hum,1,V(0,10,0));assert(not solid.CanCollide and not ghost.CanCollide)
solid.CanCollide=true;rs.PreSimulation:fire();assert(not solid.CanCollide)
local added=obj('Blade','BasePart',char);added.CanCollide=true;char.DescendantAdded:fire(added);assert(not added.CanCollide)
char.DescendantRemoving:fire(added);assert(added.CanCollide)
TEST.release();assert(solid.CanCollide and not ghost.CanCollide and hum.AutoRotate and not hum.PlatformStand)
''')
run('one click per verified ready/clear screen; no progression on empty wave; dynamic events',ui+world+'''
local S=TEST.state;S.active=true;S.token=1;S.floor=90;S.run='ours'
local clicks=0;function firesignal()clicks=clicks+1 end
intro.Visible=true;bar.Visible=false;assert(TEST.click(rb,1,'intro'));assert(not TEST.click(rb,1,'intro')and clicks==1)
rl.Text='BUY';S.clicks={};assert(not TEST.click(rb,1,'intro')and clicks==1)
intro.Visible=false;bar.Visible=true;a.attributes.Health=0;b.attributes.Health=0;foreign.attributes.Health=0
TEST.step(1);assert(clicks==1 and S.active)
TEST.push('wave',{run='ours',wave=2,waves=5});assert(S.wave==2 and S.waves==5)
TEST.push('wave',{run='other',wave=99,waves=99});assert(S.waves==5)
result.Visible=true;bar.Visible=false;TEST.step(1);TEST.step(1);assert(clicks==2)
rt.Text='DEFEATED!';TEST.step(1);assert(not S.active and clicks==2)
''')
run('attacks equipped weapon, respects cooldown/Enabled, sideways recovery never descends',ui+world+'''
local S=TEST.state;S.active=true;S.token=1;S.floor=90;S.run='ours';root.Position=V(0,10,0)
-- Keep exactly one combat Tool equipped in the character fixture.
char.children['Crab Hammer']=nil;equipped=sword;sword.attributes.AttackCooldown=0.8
TEST.step(1);assert(attacks==1 and S.nextAttack==clock+0.8)
TEST.step(1);assert(attacks==1)
clock=20;S.lastDamage=0;S.repositionAt=0;TEST.step(1);assert(root.Position.Y==10 and S.side)
local count=attacks;sword.Enabled=false;clock=30;TEST.step(1);assert(attacks==count)
''')
for forbidden in [':EquipTool(', 'loadstring(', 'HttpGet(', 'FireServer(', 'InvokeServer(', 'fireproximityprompt(', 'script_key']:
 assert forbidden not in source,forbidden
print('PASS source scope: no weapon equip/selection, external dependencies, server requests, pickup or key verification')
