-- Nerfangel Infinite Tower probe 1.0. Read-only game inspection.
-- Does not move, attack, click game buttons or invoke server remotes.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("NerfangelTowerProbe")
if old then old:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="NerfangelTowerProbe";gui.ResetOnSpawn=false;gui.DisplayOrder=250;gui.Parent=pg
local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(350,190);frame.Position=UDim2.fromOffset(20,260)
frame.BackgroundColor3=Color3.fromRGB(24,20,36);frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local function label(text,y,h)
    local obj=Instance.new("TextLabel");obj.Size=UDim2.new(1,-20,0,h);obj.Position=UDim2.fromOffset(10,y)
    obj.BackgroundTransparency=1;obj.TextColor3=Color3.fromRGB(235,230,250);obj.TextSize=14
    obj.TextWrapped=true;obj.Text=text;obj.Parent=frame;return obj
end
label("NERFANGEL • DIAGNÓSTICO DA TORRE",8,24)
local status=label("Observação por 120 s. Jogue manualmente: READY → waves → NEXT FLOOR → READY.",35,48)
local lines={"NERFANGEL INFINITE TOWER DIAGNOSTICO 1.0","PlaceId="..tostring(game.PlaceId)}
local previous={}
local connections={}
local eventSeen={}
local stopped=false
local expires=os.clock()+120
local function add(message)
    if #lines<900 then
        local line=os.date("%H:%M:%S").." "..message
        table.insert(lines,line);print("[Nerfangel Tower] "..line)
    end
end
local function changed(key,message)
    if previous[key]~=message then previous[key]=message;add(message) end
end
local function path(obj)
    local ok,result=pcall(function() return obj:GetFullName() end)
    return ok and result or "<objeto removido>"
end
local function visible(obj)
    local node=obj
    while node and node~=game do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node=node.Parent
    end
    return obj.Parent~=nil
end
local function relevant(text)
    text=tostring(text):lower()
    for _,word in ipairs({"floor","wave","ready","cleared","enemies"," left","tower","next","boss","stage","failed","defeat"}) do
        if text:find(word,1,true) then return true end
    end
    return false
end
local function summary(value,depth)
    if typeof(value)=="Instance" then return path(value) end
    if type(value)~="table" then return tostring(value):sub(1,160) end
    if depth>=2 then return "{...}" end
    local fields={}
    for key,v in pairs(value) do
        if #fields>=16 then break end
        fields[#fields+1]=tostring(key).."="..summary(v,depth+1)
    end
    table.sort(fields)
    return "{"..table.concat(fields,",").."}"
end
local function watchRemote(obj)
    if eventSeen[obj] or not obj:IsA("RemoteEvent") then return end
    local name=path(obj)
    if not name:lower():find("tower",1,true) and obj.Name~="Scene" then return end
    eventSeen[obj]=true
    add("EVENTO DISPONIVEL "..name)
    connections[#connections+1]=obj.OnClientEvent:Connect(function(...)
        if stopped then return end
        local args=table.pack(...);local fields={}
        for i=1,math.min(args.n,4) do fields[#fields+1]=summary(args[i],0) end
        add("EVENTO RECEBIDO "..name.." "..table.concat(fields," | "))
    end)
end
local function snapshot()
    if stopped or not gui.Parent then return end
    for _,screen in ipairs(pg:GetChildren()) do
        if screen~=gui and not screen.Name:lower():find("polyloot",1,true)
            and not screen.Name:lower():find("oasis",1,true) then
            changed("root:"..path(screen),"GUI "..path(screen).." ["..screen.ClassName.."]")
            local nodes=screen:GetDescendants()
            for i,obj in ipairs(nodes) do
                if i>10000 then break end
                if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                    if relevant(obj.Text) then
                        changed("text:"..path(obj),"TEXTO "..path(obj).." visivel="..tostring(visible(obj)).." texto="..obj.Text:sub(1,220))
                    end
                end
                if obj:IsA("GuiButton") and visible(obj) then
                    local texts={}
                    if obj:IsA("TextButton") and obj.Text~="" then texts[1]=obj.Text end
                    for _,child in ipairs(obj:GetDescendants()) do
                        if child:IsA("TextLabel") and child.Text~="" and #texts<6 then texts[#texts+1]=child.Text end
                    end
                    if relevant(table.concat(texts," ")) or path(obj):lower():find("tower",1,true) then
                        local p,size=obj.AbsolutePosition,obj.AbsoluteSize
                        changed("button:"..path(obj),"BOTAO "..path(obj).." ativo="..tostring(obj.Active).." centro="..math.floor(p.X+size.X/2)..","..math.floor(p.Y+size.Y/2).." texto="..table.concat(texts," | "):sub(1,200))
                    end
                end
            end
        end
    end
    local live=workspace:FindFirstChild("Animal_Live")
    if live then
        local count=0
        for _,npc in ipairs(live:GetDescendants()) do
            if npc:IsA("Model") and type(npc:GetAttribute("Health"))=="number" then
                count+=1
                if count<=12 then
                    local attrs={}
                    for _,key in ipairs({"Animal","Health","MaxHealth","Tier","_GroundY","DungeonRun","TowerRun","Floor","Wave","_SpawnMarkerId"}) do
                        local v=npc:GetAttribute(key)
                        if v~=nil then attrs[key]=v end
                    end
                    local ok,cf=pcall(function()return npc:GetPivot()end)
                    changed("npc:"..path(npc),"NPC "..path(npc).." "..summary(attrs,0)..(ok and " pos="..tostring(cf.Position) or ""))
                end
            end
        end
        changed("npcCount","NPCS carregados="..count)
    end
    for _,obj in ipairs(workspace:GetChildren()) do
        if obj.Name:lower():find("tower",1,true) or obj.Name=="DungeonRuns" then
            changed("world:"..path(obj),"MAPA "..path(obj).." atributos="..summary(obj:GetAttributes(),0))
            for i,child in ipairs(obj:GetChildren()) do
                if i>16 then break end
                changed("world:"..path(child),"ESTRUTURA "..path(child).." ["..child.ClassName.."] atributos="..summary(child:GetAttributes(),0))
            end
        end
    end
    local char=player.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if root then changed("playerPosition","POSICAO personagem="..tostring(root.Position)) end
end
local function copyReport()
    local text=table.concat(lines,"\n")
    local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
    if copy then
        local ok=pcall(copy,text)
        status.Text=ok and "Relatório copiado. Cole na conversa." or "Não foi possível copiar. Consulte F9."
    else
        print(text);status.Text="Relatório impresso no F9; copiar não está disponível."
    end
end
local function button(text,x,y,width,callback)
    local obj=Instance.new("TextButton");obj.Size=UDim2.fromOffset(width,32);obj.Position=UDim2.fromOffset(x,y)
    obj.BackgroundColor3=Color3.fromRGB(87,58,150);obj.TextColor3=Color3.new(1,1,1);obj.TextSize=13
    obj.Text=text;obj.Parent=frame;Instance.new("UICorner",obj).CornerRadius=UDim.new(0,7)
    obj.Activated:Connect(callback)
end
local function stop()
    if stopped then return end
    stopped=true
    for _,conn in ipairs(connections) do pcall(function()conn:Disconnect()end) end
    status.Text="Observação encerrada. Clique em Copiar relatório e envie na conversa."
end
button("Capturar agora",10,96,160,function()pcall(snapshot)end)
button("Copiar relatório",180,96,160,copyReport)
button("Encerrar observação",10,140,235,stop)
button("Fechar",255,140,85,function()stop();gui:Destroy()end)
gui.Destroying:Connect(stop)
for _,obj in ipairs(RS:GetDescendants()) do watchRemote(obj) end
connections[#connections+1]=RS.DescendantAdded:Connect(watchRemote)
task.spawn(function()
    while gui.Parent and not stopped and os.clock()<expires do
        local ok,err=pcall(snapshot)
        if not ok then add("ERRO DE LEITURA "..tostring(err):sub(1,240)) end
        task.wait(2)
    end
    if gui.Parent then stop() end
end)
