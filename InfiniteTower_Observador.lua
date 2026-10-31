-- Nerfangel Tower observer 1.0: samples state only; never moves/equips/attacks or sends remotes.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local RS=game:GetService("ReplicatedStorage")
local p=Players.LocalPlayer
local pg=p:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("NerfangelTowerObserver")
if old then old:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="NerfangelTowerObserver";gui.ResetOnSpawn=false;gui.DisplayOrder=260;gui.Parent=pg
local panel=Instance.new("Frame")
panel.Size=UDim2.fromOffset(360,190);panel.Position=UDim2.fromOffset(15,230)
panel.BackgroundColor3=Color3.fromRGB(27,22,40);panel.Active=true;panel.Draggable=true;panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,12)
local function text(class,s,y,h)
 local o=Instance.new(class);o.Text=s;o.TextWrapped=true;o.TextSize=14;o.TextColor3=Color3.fromRGB(240,235,255)
 o.Size=UDim2.new(1,-20,0,h);o.Position=UDim2.fromOffset(10,y);o.BackgroundColor3=Color3.fromRGB(58,43,85);o.Parent=panel
 return o
end
text("TextLabel","NERFANGEL • OBSERVADOR DA TORRE",8,25)
local status=text("TextLabel","90 segundos. Ative o outro script e deixe combater, avançar e trocar armas.",38,54)
local stopButton=text("TextButton","Finalizar e copiar",100,34)
local copyButton=text("TextButton","Copiar relatório novamente",142,34)
local started=os.clock()
local lines={"NERFANGEL TOWER OBSERVER 1.0","PlaceId="..tostring(game.PlaceId),"NPC mostrado é o mais próximo; não confirma o alvo do outro script."}
local stopped=false
local connections={}
local previous={}
local seenTools=setmetatable({},{__mode="k"})
local lastHp=setmetatable({},{__mode="k"})
local function round(n)return math.floor(n*100+0.5)/100 end
local function vec(v)return {round(v.X),round(v.Y),round(v.Z)}end
local function path(o)return o and o:GetFullName() or "nil"end
local function scalar(a)
 local out={}
 for k,v in pairs(a) do
  if type(v)=="number" or type(v)=="boolean" or type(v)=="string" then out[k]=v
  elseif typeof(v)=="Vector3" then out[k]=vec(v) end
 end
 return out
end
local function add(kind,data)
 if stopped or #lines>=650 then return end
 local ok,s=pcall(Http.JSONEncode,Http,data)
 if ok then table.insert(lines,string.format("%.2f %s %s",os.clock()-started,kind,s)) end
end
local function changed(key,kind,data)
 local encoded=Http:JSONEncode(data)
 if previous[key]~=encoded then previous[key]=encoded;add(kind,data) end
end
local function visible(o)
 if not o or not o.Parent then return false end
 while o and o~=game do
  if o:IsA("GuiObject") and not o.Visible then return false end
  if o:IsA("ScreenGui") and not o.Enabled then return false end
  o=o.Parent
 end
 return true
end
local function node(o,...)
 for _,name in ipairs({...})do o=o and o:FindFirstChild(name)end
 return o
end
local function copy()
 local report=table.concat(lines,"\n")
 local ok=false
 if type(setclipboard)=="function" then ok=pcall(setclipboard,report) end
 if not ok then
  print("NERFANGEL OBSERVER BEGIN")
  for _,line in ipairs(lines)do print(line)end
  print("NERFANGEL OBSERVER END")
 end
 if gui.Parent then status.Text=ok and "Relatório copiado. Cole aqui na conversa." or "Relatório no console F9. Copie o texto." end
end
local function finish()
 if stopped then copy();return end
 add("FIM",{seconds=round(os.clock()-started),lines=#lines})
 stopped=true
 for _,c in ipairs(connections)do c:Disconnect()end
 connections={}
 copy()
end
stopButton.Activated:Connect(finish)
copyButton.Activated:Connect(copy)
gui.Destroying:Connect(function()
 stopped=true
 for _,c in ipairs(connections)do c:Disconnect()end
end)
local function tools(char)
 for _,container in ipairs({char,p:FindFirstChild("Backpack")})do
  if container then
   for _,tool in ipairs(container:GetChildren())do
    if tool:IsA("Tool") and not seenTools[tool] then
     seenTools[tool]=true
     local values={}
     local count=0
     for _,d in ipairs(tool:GetDescendants())do
      if d:IsA("ValueBase") then
       count=count+1
       if count<=35 then values[d.Name]=tostring(d.Value) end
      end
     end
     add("TOOL",{name=tool.Name,attributes=scalar(tool:GetAttributes()),values=values,grip={tool.Grip:GetComponents()}})
    end
   end
  end
 end
end
local function ui()
 local hud=pg:FindFirstChild("TowerRunV5")
 if not hud then changed("hud","HUD",{present=false});return end
 changed("hud","HUD",{present=true,enabled=hud.Enabled})
 local labels={}
 local count=0
 for _,o in ipairs(hud:GetDescendants())do
  if (o:IsA("TextLabel") or o:IsA("TextButton")) and visible(o) and o.Text~="" then
   count=count+1
   if count<=130 then labels[path(o)]=o.Text end
  end
 end
 changed("labels","UI",labels)
 for _,name in ipairs({"Intro","Result","Crest","Bar"})do
  local o=hud:FindFirstChild(name)
  changed("attributes:"..name,"HUD_ATTRIBUTES",{name=name,visible=visible(o),attributes=o and scalar(o:GetAttributes()) or {}})
 end
end
local function sample()
 local char=p.Character
 local root=char and char:FindFirstChild("HumanoidRootPart")
 local hum=char and char:FindFirstChildOfClass("Humanoid")
 if not root or not hum then changed("character","CHARACTER",{available=false});return end
 tools(char)
 local equipped=char:FindFirstChildOfClass("Tool")
 local data={position=vec(root.Position),look=vec(root.CFrame.LookVector),up=vec(root.CFrame.UpVector),velocity=vec(root.AssemblyLinearVelocity),health=hum.Health,maxHealth=hum.MaxHealth,state=hum:GetState().Name,platformStand=hum.PlatformStand,autoRotate=hum.AutoRotate,weapon=equipped and equipped.Name or "none"}
 local folder=node(workspace,"Animal_Live","Aggressors")
 local nearest,nearestPos,distance
 local species={}
 if folder then
  for _,npc in ipairs(folder:GetChildren())do
   local hp=npc:GetAttribute("Health")
   if npc:IsA("Model") and type(hp)=="number" and hp>0 then
    local pos=npc:GetPivot().Position
    local d=(pos-root.Position).Magnitude
    if d<220 then
     local name=tostring(npc:GetAttribute("Animal") or npc.Name)
     species[name]=(species[name] or 0)+1
     if not distance or d<distance then nearest,nearestPos,distance=npc,pos,d end
    end
   end
  end
 end
 changed("species","NEARBY_SPECIES",species)
 if nearest then
  local hp=nearest:GetAttribute("Health")
  data.nearest={name=tostring(nearest:GetAttribute("Animal") or nearest.Name),path=path(nearest),position=vec(nearestPos),health=hp,distance=round(distance),heightDifference=round(root.Position.Y-nearestPos.Y),horizontalDistance=round((Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(nearestPos.X,0,nearestPos.Z)).Magnitude),observedHealthDrop=lastHp[nearest] and round(lastHp[nearest]-hp) or nil}
  lastHp[nearest]=hp
 end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances=folder and {char,folder} or {char};params.RespectCanCollide=true
 local hit=workspace:Raycast(root.Position,Vector3.new(0,-100,0),params)
 if hit then data.groundDistance=round(root.Position.Y-hit.Position.Y) end
 local physics={}
 for _,o in ipairs(char:GetDescendants())do
  if o:IsA("BodyMover") or o:IsA("AlignPosition") or o:IsA("AlignOrientation") or o:IsA("LinearVelocity") or o:IsA("VectorForce") then
   if #physics<16 then
    local row={class=o.ClassName,path=path(o)}
    for _,prop in ipairs({"Enabled","MaxForce","MaxTorque","Responsiveness","Position","Velocity","VectorVelocity","CFrame"})do
     local ok,v=pcall(function()return o[prop]end)
     if ok then row[prop]=typeof(v)=="Vector3" and vec(v) or tostring(v) end
    end
    table.insert(physics,row)
   end
  end
 end
 changed("physics","PHYSICS",physics)
 add("SAMPLE",data)
end
local push=node(RS,"Tower_Engine","Remotes","Push")
if push and push:IsA("RemoteEvent") then
 table.insert(connections,push.OnClientEvent:Connect(function(action,data)
  if type(data)=="table" then add("PUSH",{action=tostring(action),data=scalar(data)})end
 end))
end
add("START",{duration=90,sampleInterval=0.5})
task.spawn(function()
 local n=0
 while not stopped and gui.Parent and os.clock()-started<90 do
  local ok,err=pcall(sample)
  if not ok then changed("sampleError","ERROR",{message=tostring(err)})end
  if n%4==0 then
   local uiOk,uiErr=pcall(ui)
   if not uiOk then changed("uiError","ERROR",{message=tostring(uiErr)})end
  end
  n=n+1
  if gui.Parent then status.Text="Observando: "..math.floor(os.clock()-started).."/90 s. Use o outro script normalmente." end
  task.wait(0.5)
 end
 if not stopped then finish()end
end)
