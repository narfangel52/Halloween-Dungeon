-- NERFANGEL • TORRE SIMPLES 1.0
-- Independent client script. Enter Infinite Tower manually and equip your combat weapon.
-- Uses the existing weapon only. No keys, external UI, selling or weapon selection.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local old=playerGui:FindFirstChild("NerfangelTorreSimples")
if old then old:Destroy() end
local S={active=false,token=0,height=10,advance=true,floor=0,wave=0,waves=0,run=nil,target=nil,
    nextMove=0,nextAttack=0,clicks={},connections={},errors={},attacks=0,moveFailures=0}
local gui
local function root()local c=player.Character;return c and c:FindFirstChild("HumanoidRootPart")end
local function humanoid()local c=player.Character;return c and c:FindFirstChildOfClass("Humanoid")end
local function node(o,...)
    for _,name in ipairs({...})do o=o and o:FindFirstChild(name)end
    return o
end
local function text(o)return o and (o:IsA("TextLabel")or o:IsA("TextButton"))and o.Text or ""end
local function visible(o)
    if not o or not o.Parent then return false end
    while o and o~=game do
        if o:IsA("GuiObject")and not o.Visible or o:IsA("ScreenGui")and not o.Enabled then return false end
        o=o.Parent
    end
    return true
end
local function valid(id)return S.active and S.token==id and gui and gui.Parent~=nil end
local function status(message)
    if S.message==message then return end
    S.message=message
    if S.statusLabel then S.statusLabel.Text=message end
end
local function log(message)
    S.errors[#S.errors+1]=os.date("%H:%M:%S").." "..tostring(message)
    if #S.errors>60 then table.remove(S.errors,1)end
end
local function phase()
    local hud=playerGui:FindFirstChild("TowerRunV5")
    if not hud or not hud.Enabled then return "missing"end
    local result=node(hud,"Result")
    local title=node(result,"Head","Title")
    if visible(result)and visible(title)and text(title)~=""then
        local floor=tonumber(text(node(result,"Head","Floor")):match("[Ff][Ll][Oo][Oo][Rr]%s+(%d+)"))
        local label=text(node(result,"Again","Background","Frame","Label"))
        if text(title)=="CLEARED!"then return "cleared",floor,label=="NEXT FLOOR"and node(result,"Again","Btn")or nil end
        return "defeated",floor
    end
    local intro=node(hud,"Intro")
    local button=node(intro,"Ready","Btn")
    if visible(intro)and visible(button)then
        local floor=tonumber(text(node(intro,"Head","Title")):match("[Ff][Ll][Oo][Oo][Rr]%s+(%d+)"))
        return "intro",floor,text(node(intro,"Ready","Background","Frame","Label"))=="READY"and button or nil
    end
    local crest=node(hud,"Crest","Words")
    if visible(node(hud,"Bar"))and visible(crest)then return "fight",tonumber(text(crest):match("[Ff]loor%s+(%d+)"))end
    return "transition"
end
local function releaseHover()
    local state=S.hover
    S.hover=nil
    if not state then return end
    for _,c in ipairs(state.connections)do c:Disconnect()end
    for part,original in pairs(state.parts)do pcall(function()part.CanCollide=original end)end
    for _,o in ipairs(state.objects)do pcall(function()o:Destroy()end)end
    if state.hum.Parent then
        state.hum.AutoRotate=state.autoRotate;state.hum.PlatformStand=state.platformStand
        if state.hum.Health>0 and not state.platformStand then pcall(function()state.hum:ChangeState(Enum.HumanoidStateType.GettingUp)end)end
    end
end
local function stop(reason)
    S.active=false;S.token+=1;S.target=nil
    if S.push then S.push:Disconnect();S.push=nil end
    releaseHover()
    status(reason or "Parado")
    if S.startButton then S.startButton.Text="INICIAR FARM"end
    log(reason or "Parado")
end
local function arena()
    if S.arena and S.arena.Parent and tonumber(S.arena:GetAttribute("TowerFloor"))==S.floor then return S.arena end
    local folder=workspace:FindFirstChild("TowerRuns")
    local r=root()
    if not folder or not r then return nil end
    local best,distance
    for _,model in ipairs(folder:GetChildren())do
        if model:IsA("Model")and tonumber(model:GetAttribute("TowerFloor"))==S.floor then
            local cf,size=model:GetBoundingBox()
            local d=(r.Position-cf.Position).Magnitude
            if d<400 and (not distance or d<distance)then best,distance=model,d end
        end
    end
    S.arena=best;S.boundsArena=nil
    return best
end
local function inArena(pos)
    local model=arena()
    if not model then return false end
    if S.boundsArena~=model or os.clock()-(S.boundsAt or 0)>1 then
        S.boundsCF,S.boundsSize=model:GetBoundingBox();S.boundsArena=model;S.boundsAt=os.clock()
    end
    local p=S.boundsCF:PointToObjectSpace(pos);local size=S.boundsSize
    return math.abs(p.X)<=size.X/2+5 and math.abs(p.Z)<=size.Z/2+5 and math.abs(p.Y)<=size.Y/2+40
end
local function npcPosition(npc)return npc and npc.Parent and npc:GetPivot().Position end
local function eligible(npc,folder)
    if not npc or npc.Parent~=folder or not npc:IsA("Model")then return false end
    local hp=npc:GetAttribute("Health")
    if type(hp)~="number"or hp<=0 then return false end
    local run=npc:GetAttribute("_TowerRun")or npc:GetAttribute("_DungeonRun")
    if S.run and run and run~=S.run then return false end
    local pos=npcPosition(npc)
    return pos and inArena(pos)
end
local function target()
    local folder=node(workspace,"Animal_Live","Aggressors")
    local r=root()
    if not folder or not r or not arena()then return nil end
    if eligible(S.target,folder)then return S.target end
    local best,distance
    for _,npc in ipairs(folder:GetChildren())do
        if eligible(npc,folder)then
            local d=(r.Position-npcPosition(npc)).Magnitude
            if not distance or d<distance then best,distance=npc,d end
        end
    end
    S.target=best;S.nextMove=0;S.moveFailures=0;S.side=false
    S.lastHp=best and best:GetAttribute("Health");S.lastDamage=os.clock();S.repositionAt=0
    return best
end
local function weapon()
    local char=player.Character
    if not char then return nil end
    for _,tool in ipairs(char:GetChildren())do
        if tool:IsA("Tool")and(tool:GetAttribute("WeaponId")or tool:GetAttribute("WeaponRank")or tool:GetAttribute("_HitboxReach"))then return tool end
    end
end
local function hover(r,hum,id,point)
    if S.hover and S.hover.root~=r then releaseHover()end
    if S.hover then return S.hover end
    local state={root=r,hum=hum,char=player.Character,autoRotate=hum.AutoRotate,platformStand=hum.PlatformStand,
        parts=setmetatable({},{__mode="k"}),connections={},objects={}}
    S.hover=state
    local function register(part)
        if part:IsA("BasePart")and state.parts[part]==nil then state.parts[part]=part.CanCollide;part.CanCollide=false end
    end
    for _,part in ipairs(state.char:GetDescendants())do register(part)end
    state.connections[#state.connections+1]=state.char.DescendantAdded:Connect(register)
    state.connections[#state.connections+1]=state.char.DescendantRemoving:Connect(function(part)
        local original=state.parts[part]
        if original~=nil then state.parts[part]=nil;pcall(function()part.CanCollide=original end)end
    end)
    local attachment=Instance.new("Attachment");state.objects[#state.objects+1]=attachment
    attachment.Name="NerfangelSimpleHover";attachment.Parent=r
    local position=Instance.new("AlignPosition");state.objects[#state.objects+1]=position
    position.Mode=Enum.PositionAlignmentMode.OneAttachment;position.Attachment0=attachment
    position.ApplyAtCenterOfMass=true;position.MaxForce=math.max(10000,r.AssemblyMass*workspace.Gravity*12)
    position.MaxVelocity=0;position.Responsiveness=35;position.Position=point;position.Parent=r
    local orientation=Instance.new("AlignOrientation");state.objects[#state.objects+1]=orientation
    orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment;orientation.Attachment0=attachment
    orientation.MaxTorque=1000000;orientation.MaxAngularVelocity=25;orientation.Responsiveness=35;orientation.Parent=r
    state.position=position;state.orientation=orientation
    hum.AutoRotate=false;hum.PlatformStand=true
    state.connections[#state.connections+1]=RunService.PreSimulation:Connect(function()
        if not valid(id)or player.Character~=state.char or hum.Health<=0 then releaseHover();return end
        for part in pairs(state.parts)do if part.Parent and part.CanCollide then part.CanCollide=false end end
    end)
    return state
end
local function moveAbove(npc,id)
    local r,hum,char=root(),humanoid(),player.Character
    local pos=npcPosition(npc)
    if not r or not hum or not pos or hum.Health<=0 or not valid(id)then return false end
    local point=pos+Vector3.new(S.side and 2.5 or 0,S.height,0)
    local state=hover(r,hum,id,point)
    state.position.Position=point
    local floor=S.floor
    if (r.Position-point).Magnitude>2 then
        if os.clock()<S.nextMove then return false end
        S.nextMove=os.clock()+0.25
        state.orientation.CFrame=CFrame.lookAt(point,pos,Vector3.new(1,0,0))
        char:PivotTo(CFrame.lookAt(point,pos,Vector3.new(1,0,0)))
        task.wait(0.25)
        if not valid(id)or player.Character~=char or S.floor~=floor or phase()~="fight"then return false end
        r=root();pos=npcPosition(npc)
        if not r or not pos then return false end
        point=pos+Vector3.new(S.side and 2.5 or 0,S.height,0)
        if (r.Position-point).Magnitude>4 then
            S.moveFailures+=1;S.nextMove=os.clock()+0.75
            status("Teleporte não confirmado — aguardando")
            if S.moveFailures==1 then log("Teleporte não confirmado")end
            return false
        end
        S.moveFailures=0;state.position.Position=point
    end
    local aim=pos-r.Position
    if aim.Magnitude<0.1 then return false end
    local up=math.abs(aim.Unit.Y)>0.95 and Vector3.new(1,0,0)or Vector3.new(0,1,0)
    state.orientation.CFrame=CFrame.lookAt(r.Position,pos,up)
    return (r.Position-point).Magnitude<=4
end
local function click(button,id,expectedPhase)
    if not button or not button:IsA("GuiButton")or not button.Active or not button.Interactable then return false end
    local function ready()
        local current,_,actual=phase()
        return valid(id)and current==expectedPhase and actual==button and visible(button)
    end
    if not ready()then return false end
    local key=tostring(S.run or S.floor)..":"..S.floor..":"..expectedPhase
    if S.clicks[key]then return false end
    S.clicks[key]=true
    local event=button.Activated
    if type(getconnections)=="function"then
        local ok,list=pcall(getconnections,event)
        if ok and type(list)=="table"and #list==0 then event=button.MouseButton1Click end
    end
    if type(firesignal)=="function"then
        local usable=true
        if type(getconnections)=="function"then local ok,list=pcall(getconnections,event);if ok and type(list)=="table"and #list==0 then usable=false end end
        if usable then
            -- Never retry through another API after a potentially partial dispatch.
            local ok,err=pcall(firesignal,event,nil,0)
            S.clickIssue=nil
            log(expectedPhase..": sinal enviado"..(ok and ""or " (erro parcial: "..tostring(err)..")"))
            return true
        end
    end
    local shown=gui.Enabled
    local vim,x,y,pressed,nativeStarted,nativePressed
    local ok,err=pcall(function()
        local input=game:GetService("UserInputService")
        if input:GetFocusedTextBox()then error("Feche o chat para avançar")end
        local focus=isrbxactive or isgameactive or iswindowactive
        if type(focus)=="function"and not focus()then error("Coloque o Roblox em foco")end
        gui.Enabled=false;task.wait(0.1)
        if not ready()then error("Tela mudou antes do clique")end
        local center=button.AbsolutePosition+button.AbsoluteSize*0.5
        local screen=button:FindFirstAncestorOfClass("ScreenGui")
        if not screen or not screen.IgnoreGuiInset then center=center+game:GetService("GuiService"):GetGuiInset()end
        x,y=math.floor(center.X+0.5),math.floor(center.Y+0.5)
        if button.AbsoluteSize.X<=0 or button.AbsoluteSize.Y<=0 then error("Botão sem tamanho")end
        local camera=workspace.CurrentCamera
        if camera and (x<0 or y<0 or x>=camera.ViewportSize.X or y>=camera.ViewportSize.Y)then error("Botão fora da tela")end
        if type(mousemoveabs)=="function"and(type(mouse1click)=="function"or type(mouse1press)=="function"and type(mouse1release)=="function")then
            mousemoveabs(x,y);task.wait(0.05)
            if not ready()then error("Tela mudou antes do clique")end
            nativeStarted=true
            if type(mouse1press)=="function"and type(mouse1release)=="function"then
                nativePressed=true;mouse1press();task.wait(0.05);mouse1release();nativePressed=false
            else mouse1click()end
        else
            vim=game:GetService("VirtualInputManager");pressed=true
            vim:SendMouseButtonEvent(x,y,0,true,game,0)
        end
    end)
    if nativePressed then pcall(mouse1release)end
    if pressed then pcall(function()vim:SendMouseButtonEvent(x,y,0,false,game,0)end)end
    if gui.Parent then gui.Enabled=shown end
    S.clickIssue=not ok and "Clique pendente — use o botão do jogo manualmente"or nil
    log(expectedPhase..": "..(ok and "clique enviado"or tostring(err)))
    return ok or nativeStarted==true or pressed==true
end
local function onPush(action,data)
    if not S.active or type(data)~="table"then return end
    if action=="intro"then
        if data.run~=S.run or tonumber(data.floor)~=S.floor then S.clicks={};S.target=nil;S.arena=nil end
        S.run=data.run;S.floor=tonumber(data.floor)or S.floor;S.wave=0;S.waves=0
    elseif action=="wave"or action=="fight"or action=="won"then
        if S.run and data.run and data.run~=S.run then return end
        S.run=data.run or S.run;S.floor=tonumber(data.floor)or S.floor
        if action=="wave"then S.wave=tonumber(data.wave)or S.wave;S.waves=tonumber(data.waves)or S.waves end
    elseif action=="state"and data.inRun==false then stop("Saiu da torre")end
end
local function step(id)
    local current,floor,button=phase()
    if floor and floor~=S.floor then S.floor=floor;S.arena=nil;S.target=nil;S.clicks={}end
    if current~=S.phase then S.phase=current;S.clickIssue=nil;log("Estado="..current.." andar="..S.floor)end
    if current=="missing"then
        S.missingAt=S.missingAt or os.clock()
        if os.clock()-S.missingAt>5 then stop("Torre não encontrada — entre manualmente")end
        return
    end
    S.missingAt=nil
    local hum=humanoid()
    if not hum or hum.Health<=0 then stop("Sem vida — reinicie manualmente");return end
    if current=="defeated"then stop("Derrota — reinicie manualmente");return end
    if current=="intro"or current=="cleared"then
        releaseHover();S.target=nil
        status(S.clickIssue or (current=="intro"and "Aguardando READY"or "Andar concluído"))
        if S.advance then click(button,id,current)end
        return
    end
    if current~="fight"then status("Aguardando transição");return end
    local tool=weapon()
    if not tool then status("Equipe sua arma manualmente");return end
    local npc=target()
    if not npc then status(arena()and "Aguardando próximos monstros"or "Arena não identificada — copie diagnóstico");return end
    local hp=npc:GetAttribute("Health")
    if S.lastHp and hp<S.lastHp then S.lastDamage=os.clock()end
    S.lastHp=hp
    -- Reposition sideways at the same height, never dive into the enemy.
    if os.clock()-(S.lastDamage or os.clock())>8 and os.clock()>(S.repositionAt or 0)then
        S.side=not S.side;S.repositionAt=os.clock()+4;S.nextMove=0
        status("Ajustando posição sem baixar a altura")
    end
    if not moveAbove(npc,id)then return end
    if not valid(id)or phase()~="fight"or not npc.Parent or (npc:GetAttribute("Health")or 0)<=0 then return end
    if tool.Parent~=player.Character then return end
    if tool.Enabled and os.clock()>=S.nextAttack then
        local interval=0.25
        for _,name in ipairs({"AttackCooldown","SwingCooldown","Cooldown"})do
            local value=tool:GetAttribute(name);if type(value)=="number"and value>0 and value<=10 then interval=math.max(interval,value)end
        end
        tool:Activate();S.nextAttack=os.clock()+interval;S.attacks+=1
    end
    status("Andar "..S.floor.." • "..tostring(npc:GetAttribute("Animal")or npc.Name).." • altura "..S.height)
end
local function start()
    if S.active then return end
    if phase()=="missing"then status("Entre manualmente na Infinite Tower primeiro");return end
    if not weapon()then status("Equipe a arma que quer usar antes de iniciar");return end
    S.active=true;S.token+=1;S.floor=0;S.wave=0;S.waves=0;S.run=nil;S.target=nil;S.arena=nil;S.clicks={}
    S.nextMove=0;S.nextAttack=0;S.missingAt=nil;S.phase=nil;S.attacks=0
    local push=node(game:GetService("ReplicatedStorage"),"Tower_Engine","Remotes","Push")
    if push and push:IsA("RemoteEvent")then S.push=push.OnClientEvent:Connect(onPush)end
    if S.startButton then S.startButton.Text="PARAR FARM"end
    local id=S.token
    task.spawn(function()
        local ok,err=xpcall(function()
            while valid(id)do step(id);task.wait(0.12)end
        end,debug.traceback)
        if not ok and S.token==id then log(err);stop("Erro — copie o diagnóstico")end
    end)
end
local function diagnostic()
    local r=root();local hum=humanoid();local current,floor,button=phase()
    local lines={"NERFANGEL TORRE SIMPLES 1.0","PlaceId="..tostring(game.PlaceId),"Ativo="..tostring(S.active).." Estado="..current.." Andar="..tostring(floor or S.floor),
        "Run="..tostring(S.run).." Wave="..S.wave.."/"..S.waves.." Altura="..S.height.." Ataques solicitados="..S.attacks,
        "Arma="..tostring(weapon()and weapon().Name).." HP="..tostring(hum and hum.Health),
        "Arena="..tostring(S.arena and S.arena:GetFullName()).." Botão="..tostring(button and button:GetFullName()),"Status="..tostring(S.message)}
    if r then lines[#lines+1]="Posição="..tostring(r.Position).." Olhar="..tostring(r.CFrame.LookVector)end
    if S.target then lines[#lines+1]="Alvo="..S.target.Name.." HP="..tostring(S.target:GetAttribute("Health"))end
    for _,line in ipairs(S.errors)do lines[#lines+1]=line end
    local report=table.concat(lines,"\n")
    local ok=type(setclipboard)=="function"and pcall(setclipboard,report)
    if not ok then print(report)end
    status(ok and "Diagnóstico copiado — envie na conversa"or "Diagnóstico no console F9")
end
-- Interface: native Roblox GUI, no external UI library.
gui=Instance.new("ScreenGui");gui.Name="NerfangelTorreSimples";gui.ResetOnSpawn=false;gui.DisplayOrder=250;gui.Parent=playerGui
local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(320,260);panel.Position=UDim2.fromOffset(30,200)
panel.BackgroundColor3=Color3.fromRGB(23,20,34);panel.Active=true;panel.Draggable=true;panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,12)
local function label(value,y,height)
    local o=Instance.new("TextLabel");o.Size=UDim2.new(1,-20,0,height);o.Position=UDim2.fromOffset(10,y)
    o.BackgroundTransparency=1;o.Text=value;o.TextWrapped=true;o.TextColor3=Color3.fromRGB(238,232,255);o.TextSize=14;o.Parent=panel
    return o
end
local function button(value,x,y,width,callback)
    local o=Instance.new("TextButton");o.Size=UDim2.fromOffset(width,32);o.Position=UDim2.fromOffset(x,y)
    o.BackgroundColor3=Color3.fromRGB(79,52,125);o.TextColor3=Color3.new(1,1,1);o.TextSize=14;o.Text=value;o.Parent=panel
    Instance.new("UICorner",o).CornerRadius=UDim.new(0,7)
    S.connections[#S.connections+1]=o.Activated:Connect(callback)
    return o
end
label("NERFANGEL • TORRE SIMPLES 1.0",8,24)
S.statusLabel=label("Entre na torre, equipe a arma e inicie.",38,44)
S.startButton=button("INICIAR FARM",10,88,300,function()if S.active then stop("Parado manualmente")else start()end end)
local heightLabel=label("Altura: 10",124,25)
button("−",10,124,45,function()S.height=math.max(4,S.height-1);heightLabel.Text="Altura: "..S.height;S.nextMove=0 end)
button("+",265,124,45,function()S.height=math.min(20,S.height+1);heightLabel.Text="Altura: "..S.height;S.nextMove=0 end)
local advanceButton
advanceButton=button("Avançar/READY: ligado",10,158,300,function()
    S.advance=not S.advance;S.clicks={}
    advanceButton.Text="Avançar/READY: "..(S.advance and "ligado"or "desligado")
end)
button("Copiar diagnóstico",10,198,210,diagnostic)
button("Fechar",230,198,80,function()gui:Destroy()end)
label("Equipe sua arma antes de iniciar.",233,22)
gui.Destroying:Connect(function()
    stop("Hub fechado")
    for _,connection in ipairs(S.connections)do connection:Disconnect()end
    S.connections={}
end)
