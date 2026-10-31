-- Read-only observer of the user's R weapon-menu interaction. Never sends input/remotes.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local H=game:GetService("HttpService")
local p=Players.LocalPlayer
local pg=p:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("NerfangelWeaponProbe")
if old then old:Destroy()end
local gui=Instance.new("ScreenGui");gui.Name="NerfangelWeaponProbe";gui.ResetOnSpawn=false;gui.DisplayOrder=270;gui.Parent=pg
local f=Instance.new("Frame");f.Size=UDim2.fromOffset(370,160);f.Position=UDim2.fromOffset(15,220);f.BackgroundColor3=Color3.fromRGB(28,22,42);f.Active=true;f.Draggable=true;f.Parent=gui
local status=Instance.new("TextLabel");status.Size=UDim2.new(1,-16,0,100);status.Position=UDim2.fromOffset(8,8);status.TextWrapped=true;status.TextSize=15;status.TextColor3=Color3.new(1,1,1);status.BackgroundTransparency=1;status.Text="NERFANGEL • MENU R\nPause o farm. Abra R e selecione Crab Hammer; depois R e Pumpkin. Observe por até 60 s.";status.Parent=f
local button=Instance.new("TextButton");button.Size=UDim2.new(1,-16,0,36);button.Position=UDim2.fromOffset(8,115);button.Text="Finalizar e copiar";button.Parent=f
local lines={"NERFANGEL ARMAS R DIAGNOSTICO 1.0","PlaceId="..tostring(game.PlaceId)}
local started=os.clock()
local stopped=false
local untilTime=0
local connections={}
local hooked=setmetatable({},{__mode="k"})
local seen={}
local baseline=setmetatable({},{__mode="k"})
local function attrs(o)
 local out={}
 for k,v in pairs(o:GetAttributes())do
  if type(v)=="string" or type(v)=="number" or type(v)=="boolean" then out[k]=v end
 end
 return out
end
local function add(kind,data)
 if stopped or #lines>=450 then return end
 local ok,text=pcall(H.JSONEncode,H,data)
 if ok then table.insert(lines,string.format("%.2f %s %s",os.clock()-started,kind,text))end
end
local function changed(key,kind,data)
 local text=H:JSONEncode(data)
 if seen[key]~=text then seen[key]=text;add(kind,data)end
end
local function visible(o)
 while o and o~=game do
  if o:IsA("GuiObject") and not o.Visible then return false end
  if o:IsA("ScreenGui") and not o.Enabled then return false end
  o=o.Parent
 end
 return true
end
local function excluded(o)
 if o:IsDescendantOf(gui)then return true end
 local top=o
 while top.Parent and top.Parent~=pg do top=top.Parent end
 local name=top.Name:lower()
 return name:find("chat",1,true) or name:find("nerfangel",1,true) or name=="polylootdungeonv4" or name=="polylootoasisv5"
end
local function describe(o)
 local out={path=o:GetFullName(),class=o.ClassName,attributes=attrs(o)}
 if o:IsA("TextLabel") or o:IsA("TextButton")then out.text=o.Text end
 if o:IsA("ImageLabel") or o:IsA("ImageButton")then out.image=o.Image end
 local parent=o.Parent
 if parent then
  out.parent=parent:GetFullName();out.parentAttributes=attrs(parent)
  if parent.Parent then out.grandparentAttributes=attrs(parent.Parent)end
  local labels={}
  for _,d in ipairs(parent:GetDescendants())do
   if #labels>=20 then break end
   if (d:IsA("TextLabel") or d:IsA("TextButton"))and d.Text~=""then
    table.insert(labels,{path=d:GetFullName(),text=d.Text})
   end
  end
  out.labels=labels
 end
 return out
end
local function snapshot()
 if os.clock()>untilTime then
  baseline=setmetatable({},{__mode="k"})
  for _,o in ipairs(pg:GetDescendants())do
   if o:IsA("GuiObject")and visible(o)then baseline[o]=true end
  end
  return
 end
 local count=0
 for _,o in ipairs(pg:GetDescendants())do
  if not baseline[o]and not excluded(o)and visible(o)and(o:IsA("GuiButton")or o:IsA("TextLabel"))then
   count=count+1
   if count<=220 then
    changed("ui:"..o:GetFullName(),"MENU",describe(o))
    if o:IsA("GuiButton")and not hooked[o]then
     hooked[o]=true
     table.insert(connections,o.Activated:Connect(function()
      if os.clock()<=untilTime then add("CLICK_MANUAL",describe(o))end
     end))
    end
   end
  end
 end
end
local function weapon()
 local char=p.Character
 local tool=char and char:FindFirstChildOfClass("Tool")
 changed("equipped","EQUIPPED",tool and {name=tool.Name,attributes=attrs(tool)}or {name="none"})
end
local function copy()
 local text=table.concat(lines,"\n")
 local ok=type(setclipboard)=="function"and pcall(setclipboard,text)
 if not ok then for _,line in ipairs(lines)do print(line)end end
 if gui.Parent then status.Text=ok and "Relatório copiado. Cole aqui na conversa."or "Relatório no console F9."end
end
local function finish()
 if not stopped then
  add("END",{seconds=os.clock()-started,lines=#lines});stopped=true
  for _,c in ipairs(connections)do c:Disconnect()end
  connections={}
 end
 copy()
end
button.Activated:Connect(finish)
gui.Destroying:Connect(function()stopped=true;for _,c in ipairs(connections)do c:Disconnect()end end)
table.insert(connections,UIS.InputBegan:Connect(function(input,processed)
 if input.KeyCode==Enum.KeyCode.R and not UIS:GetFocusedTextBox()then
  untilTime=os.clock()+12;add("R_MANUAL",{processed=processed})
 end
end))
task.spawn(function()
 local ok,err=pcall(function()
  local scripts=p:FindFirstChild("PlayerScripts")
  local client=scripts and scripts:FindFirstChild("Data_Client")
  local module=client and client:FindFirstChild("PlayerData")
  if not module then return end
  local replica=require(module):WaitFor(nil,2)
  local data=replica and replica.Data
  if type(data)~="table"then return end
  add("HOTBAR",data.Hotbar or {})
  local weapons=data.Inventory and data.Inventory.Weapons
  if type(weapons)=="table"then
   local count=0
   for serial,item in pairs(weapons)do
    if type(item)=="table"and type(item.Id)=="string"then
     local name=item.Id:lower()
     if name:find("crab",1,true)or name:find("hammer",1,true)or name:find("pump",1,true)or name:find("halloween",1,true)then
      count=count+1
      if count<=50 then add("INVENTORY_WEAPON",{serial=serial,Id=item.Id,Rank=item.Rank,Sign=item.Sign})end
     end
    end
   end
  end
 end)
 if not ok then add("DATA_ERROR",{message=tostring(err)})end
end)
task.spawn(function()
 while not stopped and gui.Parent and os.clock()-started<60 do
  local ok,err=pcall(function()weapon();snapshot()end)
  if not ok then changed("error","ERROR",{message=tostring(err)})end
  task.wait(0.4)
 end
 if not stopped then finish()end
end)
