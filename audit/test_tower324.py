from pathlib import Path
import re
from lupa import LuaRuntime
source=Path('PolyLoot_Nerfangel_v3.lua').read_text()
core=source[source.index('    local T={',source.index('-- Infinite Tower adapter:')):]
core=core[:core.index('    local tab=Window:Tab')]
core=re.sub(r'(T\.[\w]+)\s*\+=\s*([^;\n]+)',r'\1=\1+\2',core)
setup='''
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
clock=10;os.clock=function()return clock end
PRO={log=function()end};MW={worldFarmRunning=false};gui={Parent=true};frame={Visible=true};running=false
CFG={ATTACK_INTERVAL=0.65};RegistryAS={};task={wait=function(n)clock=clock+(n or 0.01);if afterWait then afterWait()end end}
function event()
 local e={entries={}};function e:Connect(fn)local c={connected=true};function c:Disconnect()self.connected=false end;table.insert(self.entries,{fn=fn,c=c});return c end
 function e:fire(...)for _,entry in ipairs(self.entries)do if entry.c.connected then entry.fn(...)end end end;return e
end
local mt={};function V(x,y,z)return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},mt)end
mt.__add=function(a,b)return V(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end;mt.__sub=function(a,b)return V(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
mt.__mul=function(a,n)return V(a.X*n,a.Y*n,a.Z*n)end
mt.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then local m=v.Magnitude;return V(v.X/m,v.Y/m,v.Z/m)end end
Vector3={new=V};Vector2={new=V}
CFrame={new=function(pos)return {pos=pos}end,lookAt=function(pos,target,up)return {pos=pos,target=target,up=up}end}
function obj(name,class,parent,text)
 local o={Name=name,ClassName=class,Parent=parent,children={},attributes={},Text=text or '',Visible=true,Enabled=true,Active=true,Interactable=true,AbsolutePosition=V(0,0),AbsoluteSize=V(40,40),Activated=event(),DescendantAdded=event(),DescendantRemoving=event()}
 function o:IsA(c)return self.ClassName==c or c=='GuiObject'and (self.ClassName=='Frame'or self.ClassName=='TextLabel'or self.ClassName=='TextButton')or c=='GuiButton'and self.ClassName=='TextButton'end
 function o:FindFirstChild(n)return self.children[n]end;function o:GetChildren()local t={};for _,c in pairs(self.children)do t[#t+1]=c end;return t end
 function o:GetDescendants()local t={};for _,c in pairs(self.children)do t[#t+1]=c;for _,d in ipairs(c:GetDescendants())do t[#t+1]=d end end;return t end
 function o:FindFirstAncestorOfClass(c)local n=self.Parent;while n do if n:IsA(c)then return n end;n=n.Parent end end
 function o:GetAttribute(k)return self.attributes[k]end;function o:GetFullName()return self.Parent and self.Parent:GetFullName()..'.'..self.Name or self.Name end
 if parent then parent.children[name]=o end;return o
end
playerGui=obj('PlayerGui','PlayerGui');char=obj('char','Model');bag=obj('Backpack','Folder');player={FindFirstChild=function(_,n)return n=='Backpack'and bag or nil end}
root={Position=V(0,10,0),AssemblyMass=10};hum={Health=100,Parent=true,AutoRotate=true,PlatformStand=false}
equipped=nil;function getWeapon()return equipped end;function getRoot()return root end;function getCharacter()return char end;function getHumanoid()return hum end
function hum:EquipTool(t)equipped=t end;function hum:ChangeState()end
function char:PivotTo(cf)root.Position=cf.pos end
function enemyPosition(n)return n.pos or V(0,0,0)end
function horizontalDistance(a,b)return math.sqrt((a.X-b.X)^2+(a.Z-b.Z)^2)end
function stopMovement()end;function MW.equipWeapon()return equipped end
function getNearbyDrops()return {}end
function getNativeMouseFocus()return true end
Enum={KeyCode={R='R',Escape='Escape',One=1,Two=2,Zero=0},RaycastFilterType={Exclude=1},PositionAlignmentMode={OneAttachment=1},OrientationAlignmentMode={OneAttachment=1},HumanoidStateType={GettingUp=1}}
OverlapParams={new=function()return {}end};Instance={new=function(c)return {Destroy=function()end}end}
MW.regionalLandingClear=function()return true end
workspace={Gravity=196.2,GetDescendants=function()return {}end}
function tool(name)local t=obj(name,'Tool',char);t.attributes.WeaponId=name;t.Enabled=true;function t:Activate()attacks=(attacks or 0)+1 end;return t end
hammer=tool('Crab Hammer');sword=tool('Halloween Greatsword');equipped=sword
UIS={GetFocusedTextBox=function()return nil end};VIM={};game={GetService=function(_,n)if n=='UserInputService'then return UIS elseif n=='GuiService'then return {GetGuiInset=function()return V(0,0)end}else return VIM end end}
'''
def run(name,case):
 l=LuaRuntime();l.execute(setup);l.execute(core+'\nTEST=T;realReadUi=T.readUi');l.execute('TEST.active=true;TEST.token=1;TEST.floor=90;TEST.readUi=function()return "fight"end');l.execute(case);print('PASS',name)
run('R radial caption alias, release selection, equipment confirmation, cancellation and focus', '''
local T=TEST;local r=obj('QuickSwitch','ScreenGui',playerGui);r.Enabled=false;r.IgnoreGuiInset=true
local canvas=obj('canvas','Frame',r);local w=obj('wheel','Frame',canvas);local caption=obj('Caption','TextLabel',w)
local names={'left','bottom','right','top'}
for i,n in ipairs(names)do local o=obj(n,'Frame',w);o.AbsolutePosition=V(i*100,100)end
local selected;local downs,ups=0,0
function VIM:SendMouseMoveEvent(x,y)
 selected=nil
 for i,n in ipairs(names)do if x==i*100+20 then selected=n end end
 caption.Text=selected=='left'and 'Crab Hammer'or selected=='top'and 'Pumpkin Reaper Greatsword'or ''
end
function VIM:SendKeyEvent(down,key)
 if key=='R'then
  if down then downs=downs+1;r.Enabled=true else ups=ups+1;r.Enabled=false;if selected=='left'then equipped=hammer elseif selected=='top'then equipped=sword end end
 elseif key=='Escape'then selected=nil;r.Enabled=false end
end
assert(T.quickSwitchEquip('Crab Hammer',1)==hammer);assert(downs==1 and ups==1 and frame.Visible and not T.pendingR)
assert(T.quickSwitchEquip('Halloween Greatsword',1)==sword);assert(downs==2 and ups==2)
local current=equipped;local result=T.quickSwitchEquip('Unknown Weapon',1);assert(result==nil and equipped==current and downs==ups)
afterWait=function()T.active=false end
assert(T.quickSwitchEquip('Crab Hammer',1)==nil);assert(downs==ups and frame.Visible and not T.pendingR)
T.active=true;afterWait=nil;UIS.GetFocusedTextBox=function()return {}end;local before=downs
assert(T.quickSwitchEquip('Crab Hammer',1)==nil and downs==before)
''')
run('owned weapon groups, best measured multiplier and Pumpkin tie preference', '''
local T=TEST;T.weaponInventory=function()return {a={Id='Crab Hammer'},b={Id='Halloween Greatsword'},c={Id='Spear'}}end
RegistryAS={['Crab Hammer']={WeaponType='Hammer'},['Halloween Greatsword']={WeaponType='Great Sword'},Spear={WeaponType='Spear'}}
T.selectedWeapons={Hammer=true,['Great Sword']=true}
local calls=0;local scores={['Crab Hammer']=1,['Halloween Greatsword']=0.25}
T.equipWeaponId=function(name)calls=calls+1;equipped=name=='Crab Hammer'and hammer or sword;return equipped end
T.heldMultiplier=function()return scores[equipped.Name]end
assert(T.compareOwnedWeapons(1)==hammer);local old=calls
T.compareOwnedWeapons(1);assert(calls==old+1)
T.floor=91;scores['Halloween Greatsword']=3;assert(T.compareOwnedWeapons(1)==sword)
T.floor=92;scores['Crab Hammer']=3;assert(T.compareOwnedWeapons(1)==sword)
T.selectedWeapons={Nonexistent=true};assert(#T.weaponCandidates()==0)
''')
run('profile priority, target stability, excluded tiers/runs, height and aura filtering', '''
local T=TEST;T.run='ours';T.resolveArena=function()return {}end;T.inArena=function()return true end
local a=obj('a','Model');a.Parent=true;a.pos=V(1,0,0);a.attributes={Animal='Hellhound',Tier='Large',Health=10,_TowerRun='ours'}
local b=obj('b','Model');b.Parent=true;b.pos=V(2,0,0);b.attributes={Animal='Boss',Health=10,_TowerRun='ours'}
local other=obj('other','Model');other.Parent=true;other.pos=V(0,0,0);other.attributes={Animal='Other',Health=10,_TowerRun='other'}
local folder={GetChildren=function()return {a,b,other}end};T.node=function()return folder end
local pa=T.profile(a);local pb=T.profile(b);pa.priority=4;pb.priority=10;pb.height=35
assert(T.selectEnemy()==b and T.targetHeight(b)==35)
T.unstickTarget=b;T.unstickActive=true;assert(T.targetHeight(b)==2.5)
pb.enabled=false;T.nextPriorityScan=0;assert(T.selectEnemy()==a and not T.unstickActive)
T.auraRadius=12;assert(T.auraEnemy(root.Position)==a and T.auraNearby==1)
pa.enabled=false;T.nextPriorityScan=0;assert(T.selectEnemy()==nil and T.auraEnemy(root.Position)==nil)
''')
run('target-specific air height, direct teleport, relative floor and unstick descent', '''
local T=TEST;local n={pos=V(0,5,0)};T.airNoclip=false;T.updateNoclip=function()end;T.ground=function()return V(0,0,0)end
T.profile=function()return {height=20}end;root.Position=V(30,5,0)
assert(T.airTrack(n,1));assert(root.Position.Y==25 and T.airOrientation.CFrame.target.Y==5)
T.relativeHeight=false;root.Position=V(30,5,0);clock=12
assert(T.airTrack(n,1));assert(root.Position.Y==20)
T.relativeHeight=true;T.unstickTarget=n;T.unstickActive=true;root.Position=V(30,5,0);clock=15
assert(T.airTrack(n,1));assert(root.Position.Y==7.5)
''')
run('loot filters, live collection phase and cancellation after relocation', '''
local T=TEST;local model=obj('drop','Model');model.attributes.ItemId='Apple';local aura={Parent=true,Position=V(1,0,0)}
local prompt={Parent=true,Enabled=true,MaxActivationDistance=10};local d={model=model,aura=aura,prompt=prompt}
T.collectAll=false;T.collectNames={Apple=true};assert(T.dropAllowed(d));T.collectNames={Sword=true};assert(not T.dropAllowed(d))
T.collectNames={Apple=true};T.inArena=function()return true end;function getNearbyDrops()return {d}end
local pickups=0;function fireproximityprompt()pickups=pickups+1 end
T.filteredCollect(1,true);assert(pickups==1)
T.nextLootAt=0;afterWait=function()T.active=false end;T.filteredCollect(1,true);assert(pickups==1)
''')
run('defeat retry excludes paid/unknown result; manual exit does not auto-reenter', '''
local T=TEST;T.combatLoot=false;local btn={};T.readUi=function()return 'defeated',90,btn end
local clicks=0;T.click=function(b,id,phase)assert(b==btn and phase=='defeated');clicks=clicks+1;return true end
T.repeatDefeat=true;hum.Health=0;T.step(1);assert(clicks==1 and T.active)
T.repeatDefeat=false;T.step(1);assert(not T.active)
T.active=true;T.repeatDefeat=true;hum.Health=100;T.readUi=function()return 'fight'end
T.onPush('state',{inRun=false});assert(not T.active)
T.active=true;hum.Health=0;T.onPush('state',{inRun=false});assert(T.active and T.waitingReturn)
''')
run('entry proximity switch, explicit far-door permission, no unknown prompt', '''
local T=TEST;T.entryEnabled=true
local part=obj('TowerGate','BasePart');part.Position=V(100,0,0)
local prompt=obj('Prompt','ProximityPrompt',part);prompt.ObjectText='Infinite Tower';prompt.MaxActivationDistance=10
workspace.GetDescendants=function()return {prompt}end
local fired=0;function fireproximityprompt()fired=fired+1 end
T.entryButton=function()return nil end;root.Position=V(0,0,0);T.launchStep(1);assert(fired==0 and root.Position.X==0)
T.nextEntryAt=0;T.launchAnywhere=true;T.launchStep(1);assert(fired==1 and root.Position.X==100)
T.nextEntryAt=0;part.Name='Unknown';prompt.ObjectText='Unknown';T.launchStep(1);assert(fired==1)
''')
run('actual HUD ready/clear lifecycle, one dispatch, dynamic waves and floor limit', """
local T=TEST;T.readUi=realReadUi;T.combatLoot=false;T.autoLoot=false
local hud=obj('TowerRunV5','ScreenGui',playerGui)
local intro=obj('Intro','Frame',hud);local ih=obj('Head','Frame',intro);obj('Title','TextLabel',ih,'FLOOR 90')
local ready=obj('Ready','Frame',intro);local rb=obj('Btn','TextButton',ready);local bg=obj('Background','Frame',ready);local f=obj('Frame','Frame',bg);obj('Label','TextLabel',f,'READY')
local result=obj('Result','Frame',hud);result.Visible=false;local rh=obj('Head','Frame',result);local rt=obj('Title','TextLabel',rh,'CLEARED!');obj('Floor','TextLabel',rh,'FLOOR 90')
local again=obj('Again','Frame',result);local ab=obj('Btn','TextButton',again);bg=obj('Background','Frame',again);f=obj('Frame','Frame',bg);local al=obj('Label','TextLabel',f,'NEXT FLOOR')
local bar=obj('Bar','Frame',hud);bar.Visible=false;local crest=obj('Crest','Frame',hud);obj('Words','TextLabel',crest,'Floor 90')
local calls=0;function replayMethodOrder()return {'signal'}end;function tryFireSignalReplay()calls=calls+1;return true end
T.step(1);T.step(1);assert(calls==1)
intro.Visible=false;bar.Visible=true;T.selectEnemy=function()return nil end
T.step(1);assert(calls==1 and T.active)
T.onPush('wave',{run='ours',wave=2,waves=5});assert(T.wave==2 and T.waves==5)
T.onPush('wave',{run='other',wave=99,waves=99});assert(T.waves==5)
result.Visible=true;bar.Visible=false;T.step(1);T.step(1);assert(calls==2 and T.cleared==1)
rt.Text='DEFEATED!';al.Text='REVIVE';local phase,_,button=T.readUi();assert(phase=='defeated' and button==nil)
al.Text='TRY AGAIN';assert(select(3,T.readUi())==ab)
rt.Text='CLEARED!';al.Text='NEXT FLOOR';T.floorLimit=90;T.step(1);assert(not T.active and calls==2)
""")
run('unstick remains until target changes and drives attack-close altitude', """
local T=TEST;T.combatLoot=false;T.autoWeapon=false;T.updateNoclip=function()end
local npc=obj('mob','Model');npc.Parent=true;npc.pos=V(0,0,0);npc.attributes={Animal='Monster',Health=100}
T.selectEnemy=function()return npc end;T.lastHp=100;T.lastDamage=0;root.Position=V(0,10,0)
T.step(1);assert(T.unstickActive and T.unstickTarget==npc and root.Position.Y==2.5 and attacks==1)
npc.attributes.Health=50;clock=12;T.step(1);assert(T.unstickTarget==npc)
""")
run('general owned weapon can use a verified hotbar slot before R', """
local T=TEST;local spear=tool('Spear');char.children.Spear=nil
T.weaponInventory=function()return {serial={Id='Spear'}},{Hotbar={[3]='serial'}}end
Enum.KeyCode.Three=3;local down,up=0,0
function VIM:SendKeyEvent(pressed,key)assert(key==3);if pressed then down=down+1;equipped=spear else up=up+1 end end
assert(T.equipWeaponId('Spear',1)==spear and down==1 and up==1)
""")
run('unstick forces scoped noclip and restores original true/false collisions', """
local T=TEST;T.airMode=false;T.airNoclip=false;T.unstickActive=true
local a=obj('Leg','BasePart',char);a.CanCollide=true;local b=obj('Accessory','BasePart',char);b.CanCollide=false
local rs={PreSimulation=event()};local get=game.GetService;game.GetService=function(g,n)if n=='RunService'then return rs else return get(g,n)end end
T.updateNoclip(char,1);assert(not a.CanCollide and not b.CanCollide)
a.CanCollide=true;rs.PreSimulation:fire();assert(not a.CanCollide)
T.unstickActive=false;rs.PreSimulation:fire();assert(a.CanCollide and not b.CanCollide and not T.noclipState)
""")
print('All V3.24 mocked tests passed; no live Roblox/executor verification.')
