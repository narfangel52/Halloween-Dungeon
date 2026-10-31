-- Nerfangel Hub V3 BETA. Dark adapter is experimental and requires in-game structural validation.
-- NERFANGEL HUB V3 BETA
-- Derived from Lyrancy/polyloot-speedrun main.lua, SHA 8bf2525bd210dda9d55f61ea81d0cf6e89954901
-- Modified on user-stated permission. Not tested in a Roblox executor.
-- Auto Replay consumes one Halloween Dungeon 2026 item per restart.
-- Auto Sell and Auto Replay remain off by default; enable explicitly.
-- POLY LOOT V6.0 | OASISUI | DUNGEON + MAIN WORLD + AUTO SELL
-- Release version: V6.0 | Based on V5.10.6 (no gameplay logic changes)
-- V5.10.4: World Boss UI simplified; boss combat and automation logic unchanged.
-- V5.10.2: Restore classic Single Enemy Farm distances/teleport logic from V5.9.6.
-- No TweenService or teleport/activation diagnostics. Auto Sell separate tab preserved.
-- POLY LOOT V6.0 | OASISUI | 24H KEY
-- ============================================
-- POLY LOOT | DUNGEON SPEEDRUN V5.5 OASISUI + ANTI-AFK

-- ============================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================
-- PERSONAL EDITION | modified at user's stated authorization
-- No key server or access timer. Original gameplay author: Lyrancy.
-- ============================================
-- EINSTELLUNGEN

-- ============================================
local CFG = {}
-- Equipped combat tool is detected automatically.
-- Add utility/non-combat Tool names here to avoid using them as weapons.
CFG.NON_WEAPON_TOOLS = {
    ["halloween dungeon 2026"] = true,
    ["ghostnet"] = true,
}
-- Kampf
CFG.ATTACK_DISTANCE = 2
CFG.ATTACK_INTERVAL = 0.65
CFG.ATTACK_STABILIZE = 0.12
CFG.TARGET_SEARCH_RADIUS = 140
CFG.REPOSITION_DISTANCE = 3.5
CFG.REPOSITION_INTERVAL = 0.35
-- Bewegungs-Vorhersage
CFG.PREDICTION_TIME = 0.04
CFG.MAX_PREDICTION = 0.8
-- Anti-Stuck
CFG.NO_DAMAGE_TIMEOUT = 12
CFG.ENEMY_RETRY_DELAY = 5
-- Navigation | V5.3: direct-only crossings, bounded quick retries.
CFG.DOOR_TELEPORT_DISTANCE = 12
-- V5.4: the visible Room notification may arrive after the character crossed.
-- Give the game a chance to report the room before forcing another teleport.
CFG.ROOM_CONFIRM_TIMEOUT = 3.4
CFG.ROOM_RETRY_DELAY = 0.35
CFG.ROOM_TRANSITION_DELAY = 0.4
CFG.ROOM_MAX_CROSS_ATTEMPTS = 3
CFG.ROOM_POSITION_CHECK_DELAY = 0.22
-- V5.5: poll after the initial check so late rollbacks are caught promptly.
CFG.ROOM_POSITION_POLL_INTERVAL = 0.10
CFG.ROOM_ROLLBACK_CONFIRM_SAMPLES = 2
CFG.ROOM_RETRY_AFTER_ROLLBACK = 0.38
CFG.ROOM_POPUP_GRACE_SECONDS = 6.0
CFG.ROOM_CROSSED_SIDE_THRESHOLD = 5.0
CFG.ROOM_CLOSE_TO_TARGET_THRESHOLD = 8.0
CFG.AUTO_ENTER_FIRST_ROOM = true

-- Auto Replay is opt-in because each successful restart costs one
-- Halloween Dungeon 2026 item. Selects available executor APIs automatically.
CFG.AUTO_REPLAY_DEFAULT = false
-- Anti-AFK is enabled by default, but only sends activity while the
-- active Speedrun is running. It can be toggled independently in the GUI.
CFG.ANTI_AFK_DEFAULT = true
CFG.REPLAY_CONFIRM_TIMEOUT = 15
CFG.transitionUntil = 0
CFG.DEBUG_MODE = true

-- ============================================
-- AUTOMATISCHE DROP-SAMMLUNG

-- ============================================
CFG.LOOT_SEARCH_RADIUS = 65
CFG.LOOT_TIMEOUT = 8
CFG.LOOT_SETTLE_TIME = 0.6
CFG.LOOT_PICKUP_WAIT = 0.35

-- ============================================
-- STATUS

-- ============================================
-- Main World runs as a separate exclusive automation session.
local MW: any = {
    worldFarmRunning = false,
    worldFarmMode = nil,
    worldFarmSession = 0,
    worldAutoLoot = true,
    worldDefeated = 0,
    worldAttacks = 0,
    selectedEnemyName = nil,
    enemyFarmEnabled = false,
    bossFarmEnabled = false,
    bossActive = false,
    selectedBossName = "__any_boss",
    bossKnownLabels = {},
    bossScanAt = 0,
    cachedBoss = nil,
    bossRetryUntil = 0,
    bossKills = 0,
    lastBossKillAt = 0,
}

local running = false
local sessionId = 0
local currentRoom = 0
local currentWave = 0
local totalWaves = 0
local roomCleared = false
local dungeonComplete = false
local waitingForRestart = false
local completedRuns = 0
local PRO = {
    startedAt=os.clock(), runStartedAt=nil, activeStartedAt=nil,
    finished=0, totalSeconds=0, lastSeconds=0, bestSeconds=nil,
    kills=0, lootObserved=0, saleRequests=0, salesObserved=0,
    maxRuns=0, maxMinutes=0, lootRetries=3, lootQuiet=1.5,
    lootEnabled=true, lootConfirmSeconds=1.2,
}
function PRO.duration(seconds)
    seconds=math.max(0,math.floor(seconds or 0))
    return string.format("%02d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
function PRO.limitReason()
    if PRO.maxRuns>0 and PRO.finished>=PRO.maxRuns then return "Limite de dungeons atingido" end
    if PRO.maxMinutes>0 and PRO.activeStartedAt and os.clock()-PRO.activeStartedAt>=PRO.maxMinutes*60 then
        return "Limite de tempo atingido"
    end
    return nil
end
local finalLootHandled = false
local restartRoomObserved = false
local autoReplayEnabled = CFG.AUTO_REPLAY_DEFAULT
local antiAfkEnabled = CFG.ANTI_AFK_DEFAULT
local replayAttempted = false
local replayAttemptAt = 0
local attackCount = 0
local defeatedCount = 0
local skippedEnemies = {}
local usedDoors = {}
local currentHighlight = nil
local lastRoomAttempt = 0
-- One loot inspection per room; keep direction stable across failed retries.
local lootCheckedRoom = nil
local approachRoom = nil
local approachDoor = nil
local approachDirection = nil
-- A door can be physically crossed before the game's room notification arrives.
-- Keep a short pending state so we don't teleport backwards on stale popup data.
local pendingDoor = nil
local pendingRoom = nil
local pendingDirection = nil
local pendingCrossedAt = 0
local pendingDoorLogAt = 0

local function clearPendingDoor()
    pendingDoor = nil
    pendingRoom = nil
    pendingDirection = nil
    pendingCrossedAt = 0
    pendingDoorLogAt = 0
end

-- ============================================
-- SPIELOBJEKTE

-- ============================================

local function getEnemies()
    local live = workspace:FindFirstChild("Animal_Live")
    if PRO.dungeonId=="dark" then return live end
    return live and live:FindFirstChild("Aggressors")
end

-- Dark is an experimental structural adapter, not a verified game-specific map.
PRO.dungeonId=nil
PRO.roomCount=18
PRO.darkChain=nil
PRO.darkEngine=nil
PRO.sceneConnection=nil
PRO.stallSeconds=120
PRO.healthFloor=0
PRO.doorWalkSpeed=24
PRO.lastProgressAt=os.clock()
PRO.errors={}
function PRO.log(message)
    table.insert(PRO.errors,os.date("%H:%M:%S").." "..tostring(message))
    if #PRO.errors>60 then table.remove(PRO.errors,1) end
    print("[Nerfangel V3.15]",message)
end
function PRO.roomNumber(name)
    return tonumber(name:match("^(%d+)_"))
end
function PRO.darkCandidates()
    local result={}
    local runs=workspace:FindFirstChild("DungeonRuns")
    if not runs then return result end
    for _,run in ipairs(runs:GetChildren()) do
        if run:IsA("Model") or run:IsA("Folder") then
            for _,room in ipairs(run:GetChildren()) do
                if PRO.roomNumber(room.Name) then table.insert(result,run);break end
            end
        end
    end
    return result
end
function PRO.floorRun(root,containers)
    if not root or #containers==0 then return nil,nil end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances=containers
    local hit=workspace:Raycast(root.Position+Vector3.new(0,4,0),Vector3.new(0,-35,0),params)
    if not hit then return nil,nil end
    local node=hit.Instance
    local roomIndex=nil
    while node and node~=workspace do
        roomIndex=PRO.roomNumber(node.Name) or roomIndex
        for _,run in ipairs(containers) do if node==run then return run,roomIndex end end
        node=node.Parent
    end
    return nil,nil
end
function PRO.refreshDarkRoom()
    if PRO.dungeonId~="dark" or not PRO.darkChain or not PRO.darkChain.Parent then return end
    if PRO.sceneRoom then return end -- observed server room wins over floor inference
    local now=os.clock()
    if now<(PRO.nextRoomProbe or 0) then return end
    PRO.nextRoomProbe=now+0.4
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local _,index=PRO.floorRun(root,{PRO.darkChain})
    if index and index>=1 and index<=PRO.roomCount and currentRoom~=index then
        currentRoom=index; currentWave=0; roomCleared=false
        PRO.lastProgressAt=now
        clearPendingDoor()
        PRO.log("Sala Dark pelo piso: "..index)
    end
end
function PRO.resolveDark()
    local candidates=PRO.darkCandidates()
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root then return false,"Aguardando personagem." end
    local chain,index=PRO.floorRun(root,candidates)
    if not chain then
        -- If airborne, accept only ONE nearby run; never select a remote party.
        local near={}
        for _,run in ipairs(candidates) do
            for _,part in ipairs(run:GetDescendants()) do
                if part:IsA("BasePart") and (part.Position-root.Position).Magnitude<60 then
                    table.insert(near,run);break
                end
            end
        end
        if #near==1 then chain=near[1] end
    end
    if not chain then return false,"Dark: nenhum mapa próximo e inequívoco em DungeonRuns. Entre na sala e gere diagnóstico." end
    local engine=game:GetService("ReplicatedStorage"):FindFirstChild("Dungeon_Engine")
    if not engine then return false,"Dungeon_Engine não carregado; aguarde e gere diagnóstico." end
    PRO.darkChain=chain; PRO.darkEngine=engine
    PRO.nextRoomProbe=0
    PRO.refreshDarkRoom()
    PRO.log("Dark vinculada: "..chain:GetFullName().." | sala="..tostring(index or currentRoom))
    return true
end

local function getDungeon()
    if PRO.dungeonId=="dark" then
        return PRO.darkChain and PRO.darkChain.Parent and PRO.darkChain or nil
    end
    return workspace:FindFirstChild("HalloweenDungeon_Chain")
end

local function getCharacter()
    return player.Character
end

local function getRoot()
    local character = getCharacter()
    if not character or not character:IsDescendantOf(workspace) then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") and root.Parent == character then return root end
    return nil
end

local function getHumanoid()
    local character = getCharacter()
    return character
        and character:FindFirstChildOfClass("Humanoid")
end

local function getWeapon()
    local character = getCharacter()
    if not character then
        return nil
    end

    -- Equipped Roblox Tools are parented to the player's Character.
    -- Backpack items are intentionally ignored until equipped.
    local fallback = nil
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and not CFG.NON_WEAPON_TOOLS[tool.Name:lower()] then
            -- Prefer items carrying the game's weapon attributes when available.
            if tool:GetAttribute("WeaponId") ~= nil
                or tool:GetAttribute("WeaponRank") ~= nil
                or tool:GetAttribute("_HitboxReach") ~= nil then
                return tool
            end
            fallback = fallback or tool
        end
    end
    return fallback
end

local gui -- Forward declaration shared by session validation and UI initialization.

local function validSession(id)
    if running and PRO.dungeonId=="dark" then PRO.refreshDarkRoom() end
    return running and sessionId == id and gui ~= nil and gui.Parent ~= nil
end

local function debugPrint(...)
    if CFG.DEBUG_MODE then
        print("[DUNGEON V5]", ...)
    end
end

local function horizontalDistance(a, b)
    return Vector3.new(
        a.X - b.X,
        0,
        a.Z - b.Z
    ).Magnitude
end

-- ============================================
-- OASIS UI | DUNGEON SELECTION HUB
-- ============================================
-- OasisUI's demo features are NOT loaded. Only the controls below exist.
-- Keep the original 24H Key window as a separate login gate.
local oldGui = playerGui:FindFirstChild("PolyLootDungeonV4")
if oldGui then oldGui:Destroy() end

-- A lightweight lifecycle parent retained for the existing dungeon logic,
-- and for target Highlights that were parented to the old ScreenGui.
gui = Instance.new("ScreenGui")
gui.Name = "PolyLootDungeonV4"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local OasisUI = loadstring(game:HttpGet(
    "https://github.com/Mold53/OasisUI/releases/download/v1.6.0/OasisUI.lua"
))()


-- Translate display text only. Game IDs, dropdown Values and remote payloads stay intact.
local PT={
    ["Halloween Dungeon"]="Dungeon de Halloween",
    ["Halloween Dungeon 2026 | 18 rooms and bosses"]="Halloween 2026 | 18 salas e chefes",
    ["Dungeon"]="Dungeon",
    ["Status"]="Status",
    ["Main World"]="Mapa principal",
    ["Auto Sell"]="Venda automática",
    ["Single Enemy Farm"]="Farm de inimigo",
    ["One area. One enemy type. One spawn locked."]="Escolha uma área, um inimigo e um ponto de aparecimento.",
    ["Choose an Area and Enemy, then stand near the spawn. The nearest spawn stays locked, except while a verified World Boss is active."]="Escolha a área e o inimigo e aproxime-se do ponto de aparecimento. O alvo fica fixo, exceto durante um chefe confirmado.",
    ["Area"]="Área",
    ["Beach"]="Praia",
    ["Dark Forest"]="Floresta sombria",
    ["Jungle"]="Selva",
    ["Cave"]="Caverna",
    ["Grasslands"]="Pradarias",
    ["Select an area..."]="Selecione uma área...",
    ["Enemy Name"]="Nome do inimigo",
    ["Choose an enemy in this area..."]="Escolha um inimigo desta área...",
    ["Capture Nearby Spawns for Selected Area"]="Mapear pontos próximos da área",
    ["Only needed if area mapping is missing. Stand within your area; capture nearby spawn markers."]="Use se a área ainda não foi mapeada. Fique nela para registrar pontos próximos.",
    ["Refresh Enemy Names"]="Atualizar inimigos",
    ["Auto Farm Single Enemy"]="Farm automático de inimigo",
    ["Lock one spawn marker, defeat its NPC, collect loot and wait for its respawn."]="Fixa um ponto, derrota o inimigo, coleta e aguarda o reaparecimento.",
    ["World Boss"]="Chefe do mapa",
    ["Any detected World Boss"]="Qualquer chefe detectado",
    ["Choose boss or Any detected Boss"]="Escolha um chefe ou qualquer chefe",
    ["Auto Farm World Boss"]="Farm automático de chefe",
    ["Watch for the selected World Boss and farm it when available."]="Aguarda o chefe escolhido e inicia o combate quando disponível.",
    ["Refresh Known Bosses"]="Atualizar chefes",
    ["Refresh bosses identified by Tier=Boss or verified boss flags. Choose Any if waiting for respawn."]="Atualiza chefes confirmados pelos dados do jogo. Escolha qualquer chefe para aguardar.",
    ["Boss status"]="Status do chefe",
    ["Boss farm off"]="Farm de chefe desligado",
    ["Bosses defeated"]="Chefes derrotados",
    ["Selected boss respawn (sign)"]="Reaparecimento do chefe (placa)",
    ["Select a boss to view its sign timer"]="Selecione um chefe para ver o tempo da placa",
    ["Loot"]="Itens",
    ["Auto Collect Loot"]="Coletar itens automaticamente",
    ["Collect drops from the locked enemy only."]="Coleta apenas drops do inimigo selecionado.",
    ["Single Farm Status"]="Status do farm",
    ["Choose area + enemy"]="Escolha área e inimigo",
    ["Locked spawn"]="Ponto fixado",
    ["Defeated"]="Derrotados",
    ["Attacks"]="Ataques",
    ["Auto Sell by item name"]="Vender por nome de item",
    ["All weapon/armor types are loaded from ItemRegistry, including items not yet owned. Favorite, locked, equipped, hotbar, quest-reserved and other protected copies are always excluded. Auto Sell is OFF until enabled below."]="Lista armas e armaduras do jogo, inclusive as que você não possui. Exclui favoritos, bloqueados, equipados, atalhos e reservas de missão. A venda começa desligada.",
    ["Filter by rarity"]="Filtrar lista por raridade",
    ["All rarities"]="Todas as raridades",
    ["Items to auto-sell"]="Itens permitidos para venda",
    ["Choose item names (all registry items)..."]="Selecione os nomes dos itens...",
    ["Inventory fullness threshold"]="Vender quando o inventário atingir",
    ["Auto Sell status"]="Status da venda",
    ["OFF | Select item types"]="Desligado | Selecione os itens",
    ["Enable Auto Sell"]="Ativar venda automática",
    ["Automatically sells eligible copies when inventory reaches the threshold. Protected copies are excluded; max one instance per cycle."]="Vende itens permitidos quando o inventário atinge o limite. Revalida proteções antes de cada pedido; no máximo um item por ciclo.",
    ["Sell Selected Now"]="Vender selecionados agora",
    ["Immediately sell every eligible copy of the selected item types, regardless of inventory fullness. Protected items stay excluded. THIS SELLS FOR REAL."]="Envia vendas reais dos itens permitidos, mesmo abaixo do limite de ocupação. Respeita proteções e a opção de guardar uma unidade.",
    ["Dungeon Selection"]="Seleção de dungeon",
    ["Select a Dungeon"]="Selecione uma dungeon",
    ["Choose a dungeon to display its available farming functions."]="Escolha uma dungeon para exibir suas funções.",
    ["Choose a dungeon..."]="Escolha uma dungeon...",
    ["Dungeon Speedrun"]="Completar dungeon automaticamente",
    ["Automatically enter, fight, and clear the 18 Halloween rooms."]="Entra, combate e avança pelas 18 salas de Halloween.",
    ["Auto Replay"]="Reiniciar automaticamente",
    ["Attempt to restart after clearing the dungeon. Uses one dungeon item per successful replay."]="Tenta reiniciar ao concluir. Cada reinício consome um item de entrada.",
    ["Anti-AFK"]="Evitar inatividade",
    ["Attempt to prevent idle disconnects while a active farm is active."]="Tenta evitar desconexão por inatividade durante o farm.",
    ["Script Version"]="Versão do script",
    ["Version"]="Versão",
    ["Dungeon Statistics"]="Estatísticas da dungeon",
    ["Room"]="Sala",
    ["Wave"]="Onda",
    ["Target"]="Alvo",
    ["Target HP"]="Vida do alvo",
    ["Personal Edition"]="Edição pessoal",
    ["Access"]="Acesso",
    ["Local / no key"]="Local / sem chave",
    ["All"]="Todas",
    ["Common"]="Comum",
    ["Rare"]="Raro",
    ["Epic"]="Épico",
    ["Legendary"]="Lendário",
    ["Godly"]="Divino",
    ["Secret"]="Secreto",
    ["Unknown"]="Desconhecido",
    ["Ready"]="Pronto",
    ["Final wave"]="Última onda",
    ["Room cleared"]="Sala concluída",
    ["Starting new run"]="Iniciando nova rodada",
    ["Checking for dropped items"]="Procurando itens no chão",
    ["Collecting item..."]="Coletando item...",
    ["Loot collection complete"]="Coleta concluída",
    ["Waiting for character / respawn"]="Aguardando personagem / reaparecimento",
    ["Dungeon cleared - waiting for restart"]="Dungeon concluída — aguardando reinício",
    ["Dungeon exited without replay - stopped"]="Saiu da dungeon sem reiniciar — parado",
    ["Replay input sent - awaiting Scene confirmation"]="Reinício solicitado — aguardando confirmação",
    ["Auto Replay failed - click Run again"]="Falha ao reiniciar — clique em jogar novamente",
    ["Replay not confirmed - click Run again"]="Reinício não confirmado — clique em jogar novamente",
    ["Restart received but gate not ready - stopped"]="Reinício recebido, mas a entrada não abriu — parado",
    ["Restart unconfirmed by Scene - stopped"]="Reinício não confirmado pelo jogo — parado",
    ["Replay was not confirmed"]="Reinício não confirmado",
    ["Equip a weapon"]="Equipe uma arma",
    ["Character not ready"]="Personagem indisponível",
    ["Entering dungeon..."]="Entrando na dungeon...",
    ["Confirming room transition"]="Confirmando troca de sala",
    ["Waiting for room confirmation..."]="Aguardando confirmação da sala...",
    ["Waiting for enemies / door"]="Aguardando inimigos / porta",
    ["Speedrun stopped"]="Automação parada",
    ["Speedrun started"]="Automação iniciada",
    ["Select Halloween Dungeon before starting"]="Selecione a dungeon de Halloween antes de iniciar",
    ["Stopped after error: open F9 console for details"]="Parado após erro: abra o console F9 para ver os detalhes",
    ["Dungeon: recovered from falling"]="Dungeon: personagem recuperado da queda",
    ["Weapon or character missing"]="Arma ou personagem indisponível",
    ["Position adjusted"]="Posição ajustada",
    ["Attacking enemy"]="Atacando inimigo",
    ["Restart accepted - loading dungeon..."]="Reinício aceito — carregando dungeon...",
    ["New dungeon loaded - waiting for gate..."]="Nova dungeon carregada — aguardando entrada...",
    ["Dungeon ready - resuming speedrun"]="Dungeon pronta — retomando automação",
    ["Stopped"]="Parado",
    ["ON | Monitoring inventory"]="Ligado | Monitorando inventário",
    ["OFF"]="Desligado",
    ["Sale already running"]="Venda já em andamento",
    ["No eligible items selected"]="Nenhum item elegível selecionado",
    ["Error; see output"]="Erro; veja o console",
    ["Select Area and Enemy first"]="Selecione a área e o inimigo primeiro",
    ["No mapped spawn within 65 studs: approach enemy / capture area"]="Nenhum ponto mapeado em 65 studs: aproxime-se ou mapeie a área",
    ["No safe landing; approach enemy manually"]="Sem posição segura; aproxime-se do inimigo manualmente",
    ["Boss unreachable; retry after cooldown"]="Chefe fora de alcance; aguardando nova tentativa",
    ["Boss defeated; collecting boss loot"]="Chefe derrotado; coletando itens",
    ["Boss defeated; waiting for next spawn"]="Chefe derrotado; aguardando reaparecimento",
    ["Boss recovery stuck; move closer and retry"]="Recuperação travada; aproxime-se e tente novamente",
    ["Boss active; waiting for registered hits"]="Chefe ativo; aguardando confirmação dos golpes",
    ["Paused for World Boss"]="Pausado para enfrentar o chefe",
    ["Resuming single enemy farm"]="Retomando farm de inimigo",
    ["Equip combat weapon manually"]="Equipe uma arma de combate manualmente",
    ["Waiting for respawn at locked spawn"]="Aguardando inimigo reaparecer no ponto fixado",
    ["Watching boss spawns; normal farm continues"]="Monitorando chefes; farm normal continua",
}
local function pt(value)
    if type(value)~="string" then return value end
    if PT[value] then return PT[value] end
    local prefixes={
        {"Room: ","Sala: "},{"Wave: ","Onda: "},{"Waves: ","Ondas: "},
        {"Target: ","Alvo: "},{"Enemies defeated: ","Inimigos derrotados: "},
        {"Attacks: ","Ataques: "},{"Status: ","Status: "},
        {"Crossing into room ","Entrando na sala "},
        {"Selected item types: ","Tipos selecionados: "},
        {"Selected types: ","Tipos selecionados: "},{"Inventory unavailable: ","Inventário indisponível: "},
        {"Fighting ","Combatendo "},{"Boss spawned, ","Chefe apareceu, "},
        {"Move closer to locked NPC (","Aproxime-se do inimigo fixado ("},
        {"Boss done; move back to locked enemy spawn (","Chefe finalizado; retorne ao ponto do inimigo ("},
        {"Recovering from boss knockback (","Recuperando posição após golpe do chefe ("},
        {"Locked enemy too far; move closer (","Inimigo fixado distante; aproxime-se ("},
    }
    for _,pair in ipairs(prefixes) do
        if value:sub(1,#pair[1])==pair[1] then return pair[2]..pt(value:sub(#pair[1]+1)) end
    end
    return value
end
local function translateConfig(config,method)
    if type(config)~="table" then return config end
    local result={}
    for k,v in pairs(config) do
        if k=="Title" or k=="Text" or k=="Description" or k=="Content" or k=="Placeholder"
            or (k=="Value" and method=="Label") then result[k]=pt(v)
        elseif k=="Values" and type(v)=="table" then
            local opts={}
            for i,option in ipairs(v) do opts[i]=translateConfig(option,"Option") end
            result[k]=opts
        else result[k]=v end
    end
    return result
end
local function portugueseUI(raw,isLabel)
    local proxy={}
    return setmetatable(proxy,{
        __index=function(_,key)
            local value=raw[key]
            if type(value)~="function" then return value end
            return function(_, ...)
                local args=table.pack(...)
                local creates={CreateWindow=true,Tab=true,Section=true,Module=true,Label=true,Paragraph=true,Dropdown=true,Slider=true,Toggle=true,Button=true}
                if creates[key] then args[1]=translateConfig(args[1],key)
                elseif key=="SetValue" and isLabel then args[1]=pt(args[1])
                elseif key=="Refresh" and type(args[1])=="table" then
                    local opts={}
                    for i,opt in ipairs(args[1]) do opts[i]=translateConfig(opt,"Option") end
                    args[1]=opts
                end
                local result=value(raw,table.unpack(args,1,args.n))
                if creates[key] and type(result)=="table" then return portugueseUI(result,key=="Label") end
                return result
            end
        end,
        __newindex=function(_,key,value) raw[key]=value end,
    })
end
OasisUI=portugueseUI(OasisUI,false)

local Window = OasisUI:CreateWindow({
    Title = "NERFANGEL HUB",
    Subtitle = "Nerfangel V3.15 BETA | Dungeon + Main World + Auto Sell",
    Folder = "PolyLootSpeedrun",
    GuiName = "PolyLootOasisV5",
    Icon = "swords",
    Theme = "Midnight",
    ToggleKey = Enum.KeyCode.RightShift,
    Settings = false,          -- Hide built-in settings/config editor
    Search = false,            -- Hide the search bar
    SearchShortcut = false,
    User = false,              -- Hide the user profile card
    AutoLoad = false,          -- Do not restore a saved Speedrun ON state
    AutoSave = false,
    CloseAction = "Hide",
})
Window:SetVisible(false)     -- Key must be verified first

-- Legacy "frame.Visible" reads/writes are mapped to the Oasis window.
-- This also keeps the Auto Replay mouse-blocking workaround intact.
local oasisVisible = false
local frame = setmetatable({}, {
    __index = function(_, key)
        if key == "Visible" then return oasisVisible end
    end,
    __newindex = function(_, key, value)
        if key == "Visible" then
            oasisVisible = value == true
            Window:SetVisible(oasisVisible)
        end
    end,
})

-- Make Oasis labels respond to the existing statusLabel.Text assignments.
-- This lets the combat/navigation logic stay untouched.
local function textProxy(element)
    local current = ""
    return setmetatable({}, {
        __index = function(_, key)
            if key == "Text" then return current end
        end,
        __newindex = function(_, key, value)
            if key == "Text" then
                current = tostring(value)
                element:SetValue(current:match("^[^:]+:%s*(.*)$") or current)
            end
        end,
    })
end

-- Dungeon hub architecture: selecting a dungeon reveals only its own controls.
-- To add another dungeon later, register it below and implement its engine.
local DUNGEON_ORDER = { "halloween", "dark" }
local DUNGEONS = {
    dark = {
        Title="Dark Dungeon — BETA",Icon="moon",
        Description="Adaptador experimental: entre manualmente. Exige estrutura compatível; use o diagnóstico se não iniciar.",
    },
    halloween = {
        Title = "Halloween Dungeon",
        Description = "Halloween Dungeon 2026 | 18 rooms and bosses",
        Icon = "skull",
    },
}

-- World controls are wired to the engine near the end of this file.
local selectedDungeonId = nil
local onSpeedrunToggle = nil   -- Implemented after the dungeon loop
local syncingSpeedrun = false

local dungeonTab = Window:Tab({ Title = "Dungeon", Icon = "swords", Columns = 1 })
local statusTab = Window:Tab({ Title = "Status", Icon = "activity", Columns = 1 })
MW.worldTab = Window:Tab({ Title = "Main World", Icon = "globe", Columns = 1 })
local autoSellTab = Window:Tab({ Title = "Auto Sell", Icon = "shopping-cart", Columns = 1 })

-- ============================================
-- MAIN WORLD | SINGLE TARGET FARM V5.9.0
-- ============================================
-- One connected map, five named areas. Capture areas with existing spawn
-- markers, then lock exactly ONE spawn marker per farm session.
MW.AREAS = {"Beach", "Dark Forest", "Jungle", "Cave", "Grasslands"}
MW.AREA_MAP_FILE = "PolyLoot_AreaSpawns_v1.json"
MW.areaMarks = {}
MW.selectedArea = nil
MW.selectedEnemyName = nil
MW.lockedSpawn = nil
MW.worldGuiSync = false
MW.worldUiRefreshing = false
MW.worldAutoLoot = true
MW.preferredWeaponName = nil
MW.lastBossRangeWarning = 0
MW.lastBossSignature = ""
MW.nextBossStallWarning = 0
MW.bossUiRefreshing = false

local function singleChoice(value)
    if typeof(value)=="string" then return value end
    if type(value)=="table" then return value.Value or value.value or value[1] end
    return nil
end

function MW.validArea(area)
    for _,name in ipairs(MW.AREAS) do
        if name==area then return true end
    end
    return false
end

function MW.markerKey(part)
    local animal=part:GetAttribute("Animal")
    if not part:IsA("BasePart") or type(animal)~="string" then return nil end
    return string.format("%s|%d|%d",animal,math.floor(part.Position.X+0.5),math.floor(part.Position.Z+0.5))
end

function MW.loadAreaMarkers()
    if type(readfile)~="function" then return end
    local ok,data=pcall(function()
        local txt=readfile(MW.AREA_MAP_FILE)
        return game:GetService("HttpService"):JSONDecode(txt)
    end)
    if not ok or type(data)~="table" or type(data.marks)~="table" then return end
    local loaded=0
    for key,mark in pairs(data.marks) do
        if loaded>=1500 then break end
        if type(key)=="string" and type(mark)=="table" and MW.validArea(mark.area)
            and type(mark.animal)=="string" and type(mark.x)=="number" and type(mark.z)=="number" then
            MW.areaMarks[key]=mark
            loaded+=1
        end
    end
    print("[WORLD][SINGLE] Area mapping loaded:",loaded,"spawn markers")
end
MW.loadAreaMarkers()

MW.selectionSection=MW.worldTab:Section({Title="Single Enemy Farm",Icon="target"})
MW.selectionInfo=MW.selectionSection:Paragraph({
    Title="One area. One enemy type. One spawn locked.",
    Content="Choose an Area and Enemy, then stand near the spawn. "..
        "The nearest spawn stays locked, except while a verified World Boss is active.",
    Icon="info"
})
MW.areaDropdown=MW.selectionSection:Dropdown({
    Title="Area",
    Values={
        {Title="Beach",Value="Beach"},
        {Title="Dark Forest",Value="Dark Forest"},
        {Title="Jungle",Value="Jungle"},
        {Title="Cave",Value="Cave"},
        {Title="Grasslands",Value="Grasslands"},
    },
    Multi=false,Search=false,AllowNone=true,
    Placeholder="Select an area...",
    Callback=function(selection)
        if MW.worldUiRefreshing then return end
        local area=singleChoice(selection)
        if not MW.validArea(area) then area=nil end
        if area~=MW.selectedArea then
            if MW.setWorldFarmMode then MW.setWorldFarmMode("enemy",false) end
            MW.selectedArea=area
            MW.selectedEnemyName=nil
            if MW.refreshAreaEnemies then MW.refreshAreaEnemies() end
        end
    end,
})
MW.enemyDropdown=MW.selectionSection:Dropdown({
    Title="Enemy Name", Values={}, Multi=false, Search=true, AllowNone=true,
    Placeholder="Choose an enemy in this area...",
    Callback=function(selection)
        if MW.worldUiRefreshing then return end
        local enemy=singleChoice(selection)
        if enemy~=MW.selectedEnemyName then
            if MW.setWorldFarmMode then MW.setWorldFarmMode("enemy",false) end
            MW.selectedEnemyName=enemy
        end
    end,
})
MW.selectionSection:Button({
    Title="Capture Nearby Spawns for Selected Area",
    Description="Only needed if area mapping is missing. Stand within your area; capture nearby spawn markers.",
    Icon="map-pin",
    Callback=function()
        if MW.captureAreaMarkers then MW.captureAreaMarkers() end
    end,
})
MW.selectionSection:Button({
    Title="Refresh Enemy Names",
    Icon="refresh-cw",
    Callback=function() if MW.refreshAreaEnemies then MW.refreshAreaEnemies() end end,
})
MW.rotateEnemies=false
MW.regionalStepWait=0.8
MW.rotationBlocked=setmetatable({},{__mode="k"})
MW.worldTab:Module({
    Title="Alternar monstros da região (XP)",
    Description="Seleciona outro vivo nos pontos mapeados até 600 studs do início. Aproximação por passos de até 20 studs, com piso e chegada verificados.",
    Icon="repeat",Default=false,Keybind=false,
    Callback=function(enabled)
        if MW.enemyFarmEnabled and MW.setWorldFarmMode then MW.setWorldFarmMode("enemy",false) end
        MW.rotateEnemies=enabled
        MW.activeNPC=nil;MW.lastApproachedNPC=nil;MW.lockedSpawn=nil
        MW.rotationOrigin=nil
        MW.rotationBlocked=setmetatable({},{__mode="k"})
    end,
})
MW.selectionSection:Slider({
    Title="Pausa entre passos de teleporte (s)",
    Min=0.1,Max=1.2,Default=0.8,Step=0.05,
    Callback=function(value) MW.regionalStepWait=math.clamp(tonumber(value) or 0.8,0.1,1.2) end,
})
MW.worldEnemiesModule=MW.worldTab:Module({
    Title="Auto Farm Single Enemy",
    Description="Lock one spawn marker, defeat its NPC, collect loot and wait for its respawn.",
    Icon="swords", Default=false, Keybind=false,
    Callback=function(enabled)
        if MW.onWorldFarmToggle then MW.onWorldFarmToggle("enemy",enabled) end
    end,
})
-- World Boss controls. Existing combat scheduling is unchanged.
-- Boss names are dynamically discovered from explicit boss NPC metadata/folders.
MW.bossSection=MW.worldTab:Section({Title="World Boss",Icon="crown"})
MW.bossDropdown=MW.bossSection:Dropdown({
    Title="World Boss",
    Values={{Title="Any detected World Boss",Value="__any_boss"}},
    Default="__any_boss",Multi=false,Search=true,AllowNone=false,
    Placeholder="Choose boss or Any detected Boss",
    Callback=function(selection)
        if MW.bossUiRefreshing then return end
        local name=singleChoice(selection)
        if type(name)=="string" and name~="" then
            MW.selectedBossName=(name=="__any_boss") and name or MW.canonicalBossName(name)
            MW.bossRetryUntil=0
            MW.lastBossSignDisplay=nil
            if MW.showSelectedBossSignTimer then MW.showSelectedBossSignTimer() end
            print("[WORLD][BOSS] Selected",name)
        end
    end,
})
MW.bossModule=MW.worldTab:Module({
    Title="Auto Farm World Boss",
    Description="Watch for the selected World Boss and farm it when available.",
    Icon="crown",Default=false,Keybind=false,
    Callback=function(enabled)
        if MW.setWorldFarmMode then MW.setWorldFarmMode("boss",enabled) end
    end,
})
MW.bossSection:Button({
    Title="Refresh Known Bosses",
    Description="Refresh bosses identified by Tier=Boss or verified boss flags. Choose Any if waiting for respawn.",
    Icon="refresh-cw",
    Callback=function()
        if MW.refreshBossList then MW.refreshBossList(true) end
    end,
})
MW.bossStatusLabel=MW.bossSection:Label({Text="Boss status",Value="Boss farm off"})
MW.bossKillsLabel=MW.bossSection:Label({Text="Bosses defeated",Value="0"})
MW.bossTimerLabel=MW.bossSection:Label({Text="Selected boss respawn (sign)",Value="Select a boss to view its sign timer"})

-- Boss respawn timers are read from in-world signs, not estimated from kill time.
-- Verified structure: Workspace.SkullcrabSign.Sign.Sign.SurfaceGui.BossName/TIMER.
-- Other boss signs are located by their own BossName text; never display one
-- boss's TIMER for a different selected boss. Signs can stream in/out.
MW.bossSignCache = {}        -- normalized BossName -> SurfaceGui
MW.bossSignScanAt = 0
MW.lastBossSignDisplay = nil

-- Boss NPC attributes and physical respawn signs may use different names.
-- Confirmed alias: Animal="TripleCobra" and sign="Triple Head Cobra"
-- denote the same world boss. Canonicalize before listing, selecting or reading signs.
function MW.canonicalBossName(value)
    if type(value) ~= "string" then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    local key = trimmed:lower():gsub("[%s%p_]+", "")
    if key == "triplecobra" or key == "tripleheadcobra" then
        return "Triple Head Cobra"
    end
    return trimmed
end

function MW.bossSignKey(value)
    local canonical = MW.canonicalBossName(value)
    if not canonical then return nil end
    local key = canonical:lower():gsub("[%s%p_]+", "")
    if key == "" then return nil end
    return key
end

function MW.signLabelText(instance)
    if not instance or not (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
        return nil
    end
    local ok, result = pcall(function() return instance.Text end)
    if not ok or type(result) ~= "string" then return nil end
    return result:match("^%s*(.-)%s*$")
end

function MW.inspectBossSign(surface)
    if not surface or not (surface:IsA("SurfaceGui") or surface:IsA("BillboardGui")) then return nil end
    local name = MW.signLabelText(surface:FindFirstChild("BossName",true))
    local timer = surface:FindFirstChild("TIMER",true)
    if not name or name == "" or not timer or not MW.bossSignKey(name) then return nil end
    local timeText = MW.signLabelText(timer)
    return name,timeText
end

function MW.rememberBossSign(surface)
    local rawName,timer=MW.inspectBossSign(surface)
    local name=MW.canonicalBossName(rawName)
    if not name then return false end
    local key=MW.bossSignKey(name)
    MW.bossSignCache[key]=surface
    -- Prefer the display name from the sign, but keep one canonical boss entry.
    if not MW.bossKnownLabels[name] then
        MW.bossKnownLabels[name]=true
        return true
    end
    return false
end

function MW.discoverBossSigns(force)
    local now=os.clock()
    if not force and now < MW.bossSignScanAt then return end
    MW.bossSignScanAt=now+8
    local newNames=false
    -- Explicit first: all top-level sign objects, including SkullcrabSign and
    -- potential CursedOwlSign / Cursed OwlSign without assuming either exists.
    for _,child in ipairs(workspace:GetChildren()) do
        if child.Name:lower():find("sign",1,true) then
            local panel=child:FindFirstChild("SurfaceGui",true)
            if panel and MW.rememberBossSign(panel) then newNames=true end
        end
    end
    -- Fallback for signs nested within area models. Infrequent (8 seconds)
    -- to avoid repeatedly traversing the entire streamed Workspace.
    for _,obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("SurfaceGui") or obj:IsA("BillboardGui")) and
           obj:FindFirstChild("BossName",true) and obj:FindFirstChild("TIMER",true) then
            if MW.rememberBossSign(obj) then newNames=true end
        end
    end
    if newNames and MW.refreshBossList then
        task.defer(function() if gui.Parent then MW.refreshBossList(true) end end)
    end
end

function MW.readSelectedBossSign()
    local selected=MW.selectedBossName
    if type(selected)~="string" or selected=="" or selected=="__any_boss" then
        return nil,"choose a specific boss"
    end
    local key=MW.bossSignKey(selected)
    local surface=key and MW.bossSignCache[key]
    if surface and not surface:IsDescendantOf(workspace) then
        MW.bossSignCache[key]=nil
        surface=nil
    end
    if not surface then
        -- Force a new search on explicit boss changes, otherwise throttled.
        MW.discoverBossSigns(false)
        surface=key and MW.bossSignCache[key]
    end
    if not surface then return nil,"sign not streamed in (approach boss area)" end
    local realName,timer=MW.inspectBossSign(surface)
    if not realName or MW.bossSignKey(realName)~=key then
        MW.bossSignCache[key]=nil
        return nil,"boss name on sign changed"
    end
    if not timer or timer=="" then return nil,"TIMER label empty" end
    return timer,nil
end

function MW.showSelectedBossSignTimer()
    local selected=MW.selectedBossName
    local display
    if type(selected)~="string" or selected=="" or selected=="__any_boss" then
        display="Choose a specific boss to view its respawn timer"
    else
        local timeText,reason=MW.readSelectedBossSign()
        display=timeText and (selected..": "..timeText)
            or (selected..": sign unavailable ("..tostring(reason or "unknown")..")")
    end
    if display~=MW.lastBossSignDisplay then
        MW.lastBossSignDisplay=display
        MW.bossTimerLabel:SetValue(display)
    end
end

MW.worldTab:Section({Title="Loot",Icon="package"}):Toggle({
    Title="Auto Collect Loot",
    Description="Collect drops from the locked enemy only.",
    Default=true,
    Callback=function(value) MW.worldAutoLoot=value==true end,
})
MW.worldStatusSection=MW.worldTab:Section({Title="Single Farm Status",Icon="activity"})
MW.worldStatusLabel=MW.worldStatusSection:Label({Text="Status",Value="Choose area + enemy"})
MW.worldTargetLabel=MW.worldStatusSection:Label({Text="Locked spawn",Value="-"})
MW.worldKillsLabel=MW.worldStatusSection:Label({Text="Defeated",Value="0"})
MW.worldAttackLabel=MW.worldStatusSection:Label({Text="Attacks",Value="0"})


-- ================================================================
-- AUTO SELL V5.9.6 | REGISTRY NAMES, RARITY FILTER, PROTECTED INSTANCE CHECKS
-- ================================================================
-- Preview is default. Real requests require an independent toggle and
-- explicit allowed names. All eligibility is recalculated before sending.
local AS = {
    enabled=false, live=false, threshold=90, selectedNames={},
    keepOne=true, pollSeconds=8, lastRun=0, busy=false, rarityFilter="All",
}
MW.AS=AS
local ReplicatedStorageAS=game:GetService("ReplicatedStorage")
local InventoryEngineAS=ReplicatedStorageAS:WaitForChild("Inventory_Engine")
local PlayerDataAS=require(player:WaitForChild("PlayerScripts"):WaitForChild("Data_Client"):WaitForChild("PlayerData"))
local RegistryAS=require(InventoryEngineAS.Modules:WaitForChild("ItemRegistry"))
local SellValueAS=require(InventoryEngineAS.Modules:WaitForChild("SellValue"))
local ReserveAS=require(ReplicatedStorageAS:WaitForChild("Quest_Engine"):WaitForChild("Reserve"))
local SellRemoteAS=InventoryEngineAS.Remotes:WaitForChild("SellRequest")
local replicaAS=nil

local function inventorySnapshot()
    if not replicaAS then
        local ok,result=pcall(function() return PlayerDataAS:WaitFor(nil,10) end)
        if ok and type(result)=="table" then replicaAS=result end
    end
    if type(replicaAS)~="table" or type(replicaAS.Data)~="table" then
        return nil,nil,"PlayerData replica unavailable"
    end
    local data=replicaAS.Data
    if type(data.Inventory)~="table" then return nil,nil,"Inventory unavailable" end
    if type(data.Inventory.Weapons)~="table" or type(data.Inventory.Armors)~="table" then
        return nil,nil,"Weapons/Armors buckets unavailable"
    end
    return data.Inventory,data,nil
end

function AS.parseNames(value)
    local set={}
    if type(value)=="string" then
        for part in value:gmatch("[^,;\r\n]+") do
            local name=part:match("^%s*(.-)%s*$")
            if name~="" then set[name:lower()]=true end
        end
    end
    return set
end

local function capacityAS()
    local inv=playerGui:FindFirstChild("Inventory")
    local space=inv and inv:FindFirstChild("InventorySpace",true)
    if not space then return nil,nil,"InventorySpace not loaded" end
    local nodes={space}
    for _,v in ipairs(space:GetDescendants()) do nodes[#nodes+1]=v end
    for _,obj in ipairs(nodes) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local x,y=obj.Text:match("(%d+)%s*/%s*(%d+)")
            x,y=tonumber(x),tonumber(y)
            if x and y and y>0 and x>=0 and x<=y then return x,y,nil end
        end
    end
    return nil,nil,"Capacity indicator unreadable"
end

local function inUseAS(serial,data)
    if type(data.Equipped)~="table" or type(data.Hotbar)~="table" then
        return true,"equipped / hotbar data unknown"
    end
    for _,slot in pairs(data.Equipped) do
        if slot==serial then return true,"equipped" end
    end
    for _,slot in pairs(data.Hotbar) do
        if slot==serial then return true,"hotbar assigned" end
    end
    local char=player.Character
    if char then
        for _,tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("InventorySerial")==serial then
                return true,"weapon currently drawn"
            end
        end
    end
    return false,nil
end

local function eligibleAS(serial,item,bucket,data)
    if type(serial)~="string" or not serial:match("^s_[%x]+_[%x]+$") then return nil,"serial missing/invalid" end
    if type(item)~="table" or type(item.Id)~="string" or item.Id=="" then return nil,"invalid item" end
    local id=item.Id:lower()
    if not AS.selectedNames[id] then return nil,"item name not selected" end
    if item.Locked~=false or item.Favorited~=false then return nil,"locked/favorite/unknown flag" end
    if item.Protected~=nil and item.Protected~=false and item.Protected~=0 then return nil,"protected item" end
    if item.Equipped==true or item.equipped==true then return nil,"equipped item" end
    if item.Serial~=nil and item.Serial~=serial then return nil,"serial mismatch" end
    if item.Source=="Starter" and bucket=="Weapons" then return nil,"starter weapon" end
    if item.Bound==nil then return nil,"binding status unknown" end
    if data.Quests and data.Quests.Story then
        local okReserve,amount=pcall(function() return ReserveAS.For(data.Quests.Story,item.Id) end)
        if not okReserve or type(amount)~="number" then return nil,"quest reservation unknown" end
        if amount>0 then return nil,"quest reserved item type" end
    end
    local definition=RegistryAS[item.Id]
    if type(definition)~="table" then return nil,"registry entry missing" end
    if bucket=="Weapons" and definition.Kind~="Weapon" then return nil,"weapon kind mismatch" end
    if bucket=="Armors" and definition.Kind~="Armor" then return nil,"armor kind mismatch" end
    if item.Count==nil or type(item.Count)~="number" or item.Count<1 or item.Count%1~=0 then
        return nil,"invalid count"
    end
    local used,reason=inUseAS(serial,data)
    if used then return nil,reason end
    local ok,price=pcall(function() return SellValueAS.For(item) end)
    if not ok or type(price)~="number" or price<=0 then return nil,"no verified sell value" end
    local qty=item.Count
    if AS.keepOne then
        -- Reserve a deterministic owned copy, including protected/equipped copies.
        -- Re-evaluated against fresh data immediately before every request.
        local retained=nil
        for _,kind in ipairs({"Weapons","Armors"}) do
            for ownedSerial,owned in pairs(data.Inventory[kind] or {}) do
                if type(ownedSerial)=="string" and type(owned)=="table" and owned.Id==item.Id
                    and type(owned.Count)=="number" and owned.Count>0 then
                    if not retained or ownedSerial<retained then retained=ownedSerial end
                end
            end
        end
        if retained==serial then qty=math.max(0,qty-1) end
    end
    if not definition.Stackable then
        if item.Count~=1 then return nil,"unexpected unstackable count" end
        qty=math.min(qty,1)
    end
    if qty<1 then return nil,"keeping last one" end
    return {serial=serial,id=item.Id,bucket=bucket,qty=qty,price=price},nil
end

local function planAS()
    local inv,data,err=inventorySnapshot()
    if not inv then return nil,nil,err end
    local used,cap,cerr=capacityAS()
    if not used then return nil,nil,cerr end
    local candidates,skipped={},{}
    local total=0
    for _,bucket in ipairs({"Weapons","Armors"}) do
        for serial,item in pairs(inv[bucket]) do
            total+=1
            local candidate,reason=eligibleAS(serial,item,bucket,data)
            if candidate then candidates[#candidates+1]=candidate
            else skipped[reason]=(skipped[reason] or 0)+1 end
        end
    end
    table.sort(candidates,function(x,y) return x.id==y.id and x.serial<y.serial or x.id<y.id end)
    return {candidates=candidates,skipped=skipped,used=used,cap=cap,pct=100*used/cap,total=total},data,nil
end

local function statusAS(message)
    if AS.label then AS.label:SetValue(message) end
end

-- forceNow is used only for an explicit OasisUI button press.
-- It bypasses the capacity threshold and the automatic monitor toggle,
-- NEVER the allowlist, or item protection checks.
function AS.preview(reason,execute,forceNow)
    if AS.busy then
        statusAS("Sale already running")
        return
    end
    AS.busy=true
    local ok,err=pcall(function()
        local plan,_,problem=planAS()
        if not plan then
            statusAS("Inventory unavailable: "..tostring(problem))
            warn("[AUTOSELL]",problem)
            return
        end
        local above=plan.pct>=AS.threshold
        local mode=not execute and "PRÉVIA" or forceNow and "VENDER AGORA" or "AUTOMÁTICO"
        statusAS(string.format("%d/%d (%.1f%%) | %d eligible | %s",plan.used,plan.cap,plan.pct,#plan.candidates,mode))
        print("[AUTOSELL]",mode,reason,"used",plan.used,"capacity",plan.cap,"pct",plan.pct,"threshold",AS.threshold,"inventory entries",plan.total)
        for _,v in ipairs(plan.candidates) do
            print("[AUTOSELL][ITEM]",v.id,"serial",v.serial,"qty",v.qty,"unit value",v.price)
        end
        for why,n in pairs(plan.skipped) do print("[AUTOSELL][SKIP]",why,n) end
        if not forceNow and not above then
            print("[AUTOSELL] Below threshold: no requests")
            return
        end
        if not execute then
            print("[AUTOSELL] Preview only: zero remotes called")
            return
        end
        if not forceNow and not (AS.live and AS.enabled) then
            warn("[AUTOSELL] Automatic monitor is disabled")
            return
        end
        if #plan.candidates==0 then
            statusAS("No eligible items selected")
            return
        end

        -- Manual: every eligible selected serial (subject to fresh checks).
        -- Automatic: only one per cycle to avoid outdated sale plans.
        local limit=forceNow and #plan.candidates or 1
        local sent=0
        for i=1,limit do
            if not gui.Parent then break end
            if not forceNow and not AS.enabled then break end
            local target=plan.candidates[i]
            local inv2,data2=inventorySnapshot()
            if not inv2 or type(inv2[target.bucket])~="table" then break end
            local item=inv2[target.bucket][target.serial]
            local fresh=eligibleAS(target.serial,item,target.bucket,data2)
            if not fresh or fresh.id~=target.id or fresh.qty~=target.qty then
                warn("[AUTOSELL] Item changed/protected, skipping",target.id,target.serial)
            else
                local permitted=true
                if not forceNow then
                    local nowUsed,nowCap=capacityAS()
                    permitted=nowUsed and nowCap and 100*nowUsed/nowCap>=AS.threshold
                end
                if not permitted then
                    print("[AUTOSELL] Threshold no longer met; stopping")
                    break
                end
                print("[AUTOSELL][LIVE] Selling",fresh.id,fresh.serial,fresh.qty)
                SellRemoteAS:FireServer({[fresh.serial]=fresh.qty})
                sent+=1
                PRO.saleRequests+=1
                local beforeCount=item.Count
                local confirmationDeadline=os.clock()+2
                while gui.Parent and os.clock()<confirmationDeadline do
                    local after=inventorySnapshot()
                    local remaining=after and after[fresh.bucket] and after[fresh.bucket][fresh.serial]
                    if after and (not remaining or (type(remaining.Count)=="number" and remaining.Count<=beforeCount-fresh.qty)) then
                        PRO.salesObserved+=fresh.qty
                        break
                    end
                    task.wait(0.15)
                end
                AS.lastRun=os.clock()
                if forceNow and i<limit then task.wait(0.3) end
            end
        end
        statusAS(string.format("%s: %d sale request(s) sent",mode,sent))
        print("[AUTOSELL]",mode,"completed; sent",sent,"sale requests; server confirmation not verified")
    end)
    AS.busy=false
    if not ok then warn("[AUTOSELL] Error",tostring(err)) statusAS("Error; see output") end
end

-- Each dropdown value is a normalized item TYPE name, not an instance Serial.
-- A sale plan separately resolves EVERY matching Serial from current PlayerData.
local function dropdownSetAS(value)
    local result={}
    if type(value)=="string" then
        result[value]=true
    elseif type(value)=="table" then
        if type(value.Value)=="string" then result[value.Value]=true end
        if type(value.value)=="string" then result[value.value]=true end
        for key,v in pairs(value) do
            if type(v)=="string" then result[v]=true
            elseif type(key)=="string" and v==true then result[key]=true
            elseif type(v)=="table" then
                local name=v.Value or v.value
                if type(name)=="string" then result[name]=true end
            end
        end
    end
    return result
end

local function selectionCountAS(set)
    local count=0
    for _ in pairs(set) do count+=1 end
    return count
end

AS.section=autoSellTab:Section({Title="Auto Sell",Icon="shield-check"})
AS.section:Paragraph({
    Title="Auto Sell by item name",
    Content="All weapon/armor types are loaded from ItemRegistry, including items not yet owned. "..
        "Favorite, locked, equipped, hotbar, quest-reserved and other protected copies are always excluded. "..
        "Auto Sell is OFF until enabled below.",
    Icon="info"
})

-- Rarity is a registry definition field, NOT an attribute of the player-owned instance.
-- Filtering only changes the dropdown display, never the persisted name selection.
local rarityOrderAS={"All","Common","Rare","Epic","Legendary","Godly","Secret","Unknown"}
local knownRarityAS={}
for _,rarity in ipairs(rarityOrderAS) do knownRarityAS[rarity]=true end
for _,def in pairs(RegistryAS) do
    if type(def)=="table" and (def.Kind=="Weapon" or def.Kind=="Armor") then
        if type(def.Rarity)=="string" and def.Rarity~="" and not knownRarityAS[def.Rarity] then
            knownRarityAS[def.Rarity]=true
            rarityOrderAS[#rarityOrderAS+1]=def.Rarity
        end
    end
end
local rarityOptionsAS={}
for _,r in ipairs(rarityOrderAS) do rarityOptionsAS[#rarityOptionsAS+1]={Title=r,Value=r} end
AS.refreshingDropdowns=false
AS.visibleNames={}

local function refreshRegistryDropdownAS()
    local opts,visible={},{}
    for registryId,definition in pairs(RegistryAS) do
        if type(registryId)=="string" and type(definition)=="table" and
           (definition.Kind=="Weapon" or definition.Kind=="Armor") then
            local rarity=type(definition.Rarity)=="string" and definition.Rarity or "Unknown"
            if AS.rarityFilter=="All" or AS.rarityFilter==rarity then
                local key=registryId:lower()
                visible[key]=true
                opts[#opts+1]={
                    Title=tostring(definition.Display or registryId),
                    Value=key,
                    Description=definition.Kind.." | "..rarity.." | ID: "..registryId,
                }
            end
        end
    end
    table.sort(opts,function(a,b)
        if a.Title:lower()==b.Title:lower() then return a.Value<b.Value end
        return a.Title:lower()<b.Title:lower()
    end)
    AS.visibleNames=visible
    AS.refreshingDropdowns=true
    local ok,err=pcall(function()
        AS.sellDropdown:Refresh(opts,false)
        local checked={}
        for key in pairs(AS.selectedNames) do
            if visible[key] then checked[#checked+1]=key end
        end
        AS.sellDropdown:Set(checked)
    end)
    AS.refreshingDropdowns=false
    if not ok then
        warn("[AUTOSELL][REGISTRY] Dropdown error",tostring(err))
    end
    statusAS("Selected types: "..selectionCountAS(AS.selectedNames).." | Registry items: "..#opts)
end

AS.rarityDropdown=AS.section:Dropdown({
    Title="Filter by rarity",Values=rarityOptionsAS,Multi=false,Search=false,
    AllowNone=false,Default="All",Placeholder="All rarities",
    Callback=function(value)
        local rarity=type(value)=="string" and value or type(value)=="table" and (value.Value or value.value or value[1])
        if type(rarity)~="string" or not knownRarityAS[rarity] then rarity="All" end
        AS.rarityFilter=rarity
        if AS.sellDropdown then refreshRegistryDropdownAS() end
    end,
})
AS.sellDropdown=AS.section:Dropdown({
    Title="Items to auto-sell",Values={},Multi=true,Search=true,AllowNone=true,
    Placeholder="Choose item names (all registry items)...",
    Callback=function(value)
        if AS.refreshingDropdowns then return end
        local nextVisible=dropdownSetAS(value)
        -- Replace choices only in the currently visible rarity; retain selections
        -- from other rarity categories, including item types not currently owned.
        for key in pairs(AS.visibleNames) do AS.selectedNames[key]=nil end
        for key in pairs(nextVisible) do
            if AS.visibleNames[key] then AS.selectedNames[key]=true end
        end
        statusAS("Selected item types: "..selectionCountAS(AS.selectedNames))
    end,
})
AS.section:Slider({Title="Inventory fullness threshold",Min=80,Max=95,Step=1,Default=90,Suffix="%",
    Callback=function(value) AS.threshold=math.clamp(tonumber(value) or 90,80,95) end})
AS.label=AS.section:Label({Text="Auto Sell status",Value="OFF | Select item types"})
AS.section:Toggle({Title="Guardar uma unidade de cada item",Default=true,
    Description="Reserva uma cópia por ID. Itens protegidos continuam excluídos.",
    Callback=function(value) AS.keepOne=value==true end})
AS.section:Button({Title="Prévia da venda (sem vender)",Icon="eye",
    Description="Exibe itens elegíveis e motivos de exclusão no console F9.",
    Callback=function() AS.preview("Prévia manual",false,true) end})
AS.section:Toggle({
    Title="Enable Auto Sell",Default=false,
    Description="Automatically sells eligible copies when inventory reaches the threshold. "..
       "Protected copies are excluded; max one instance per cycle.",
    Callback=function(value)
        AS.enabled=value==true
        AS.live=AS.enabled
        statusAS(AS.enabled and "ON | Monitoring inventory" or "OFF")
    end,
})
-- Manual one-shot action: does not require Auto Sell to be enabled.
-- Intentional click sends actual sell requests for ALL eligible instances
-- of the selected names, even when fullness is below the slider value.
AS.section:Button({
    Title="Sell Selected Now",
    Description="Immediately sell every eligible copy of the selected item types, regardless of inventory fullness. Protected items stay excluded. THIS SELLS FOR REAL.",
    Icon="shopping-cart",
    Callback=function()
        AS.preview("manual Sell Selected Now button",true,true)
    end,
})

-- Populate from all static definitions rather than the player's current inventory.
-- Defer so the dropdown object is ready before Refresh/Set.
task.defer(refreshRegistryDropdownAS)

task.spawn(function()
    while gui.Parent do
        if AS.enabled then
            if os.clock()-AS.lastRun>=12 then
                AS.preview("automatic capacity check",true)
            end
        end
        task.wait(AS.pollSeconds)
    end
end)

-- Only registered dungeons appear in the selector. No fake or placeholder modes.
local dungeonValues = {}
for _, dungeonId in ipairs(DUNGEON_ORDER) do
    local definition = DUNGEONS[dungeonId]
    table.insert(dungeonValues, {
        Title = definition.Title,
        Value = dungeonId,
        Description = definition.Description,
        Icon = definition.Icon,
    })
end

local selectorSection = dungeonTab:Section({ Title = "Dungeon Selection", Icon = "list" })
local selectorInfo = selectorSection:Paragraph({
    Title = "Select a Dungeon",
    Content = "Choose a dungeon to display its available farming functions.",
    Icon = "info",
})
local onDungeonSelected = nil
local dungeonSelector = selectorSection:Dropdown({
    Title = "Dungeon",
    Values = dungeonValues,
    Default = nil,
    Multi = false,
    AllowNone = true,
    Search = false,
    Placeholder = "Choose a dungeon...",
    Callback = function(value)
        if onDungeonSelected then
            onDungeonSelected(value)
        end
    end,
})

-- Halloween-specific features: displayed only while Halloween is selected.
local speedrunModule = dungeonTab:Module({
    Title = "Dungeon Speedrun",
    Description = "Completa Halloween; Dark Dungeon usa um adaptador experimental após entrada manual.",
    Icon = "swords",
    Keybind = false,
    Default = false,
    Callback = function(enabled)
        if not syncingSpeedrun and onSpeedrunToggle then
            onSpeedrunToggle(enabled)
        end
    end,
})

local autoReplayModule = dungeonTab:Module({
    Title = "Auto Replay",
    Description = "Halloween: consome um item por reinício. Dark: requer confirmação do jogo e teste do botão de resultado.",
    Icon = "rotate-cw",
    Keybind = false,
    Default = CFG.AUTO_REPLAY_DEFAULT,
    Callback = function(enabled)
        autoReplayEnabled = enabled
        debugPrint("Auto Replay:", enabled and "ON" or "OFF")
    end,
})

local antiAfkModule = dungeonTab:Module({
    Title = "Anti-AFK",
    Description = "Attempt to prevent idle disconnects while a active farm is active.",
    Icon = "shield-check",
    Keybind = false,
    Default = CFG.ANTI_AFK_DEFAULT,
    Callback = function(enabled)
        antiAfkEnabled = enabled
        debugPrint("Anti-AFK:", enabled and "ON" or "OFF")
    end,
})

-- Future dungeons register their own modules here, without showing
-- irrelevant controls from the Halloween farm.
local dungeonModules = {
    halloween = { speedrunModule, autoReplayModule, antiAfkModule },
}

local function updateDungeonModules()
    local show=selectedDungeonId=="halloween" or selectedDungeonId=="dark"
    for _,module in ipairs(dungeonModules.halloween) do module:SetVisible(show) end
end

onDungeonSelected = function(value)
    -- OasisUI single-select returns the configured string Value.
    -- This also handles clearing the selection or a table value defensively.
    if type(value) == "table" then
        value = value.Value or value.value or value[1]
    end
    if type(value) ~= "string" or not DUNGEONS[value] then
        value = nil
    end
    if value == selectedDungeonId then
        return
    end

    -- Switching or clearing a selected dungeon safely stops a running farm.
    if running and onSpeedrunToggle then
        onSpeedrunToggle(false)
    end
    selectedDungeonId = value
    PRO.dungeonId=value
    PRO.roomCount=value=="dark" and 10 or 18
    currentRoom=0; currentWave=0; totalWaves=0; roomCleared=false
    clearPendingDoor()
    if PRO.rebindScene then PRO.rebindScene() end
    updateDungeonModules()

    if selectedDungeonId == "dark" then
        selectorInfo:SetContent("Dark Dungeon BETA: entre manualmente antes de ativar. Se o mapa não for reconhecido, use Diagnóstico na aba Nerfangel.")
        Window:SetSubtitle("Nerfangel V3.15 | Dark Dungeon BETA")
    elseif selectedDungeonId == "halloween" then
        selectorInfo:SetContent(
            "Halloween Dungeon 2026 selected. Choose Speedrun, Auto Replay, and Anti-AFK below."
        )
        Window:SetSubtitle("Nerfangel V3.15 | Halloween")
        debugPrint("Dungeon selected:", "Halloween Dungeon")
    else
        selectorInfo:SetContent("Choose a dungeon to display its available farming functions.")
        Window:SetSubtitle("Nerfangel V3.15 BETA | Dungeon + Main World + Auto Sell")
        debugPrint("Dungeon selection cleared")
    end
end

-- On first launch, nothing is selected and no farming controls are visible.
updateDungeonModules()
onDungeonSelected(dungeonSelector:Get())

-- Universal status and license page retained independently from the selected dungeon.
local versionSection = statusTab:Section({ Title = "Script Version", Icon = "info" })
versionSection:Label({ Text = "Version", Value = "Poly Loot Nerfangel V3.15 BETA" })
local live = statusTab:Section({ Title = "Dungeon Statistics", Icon = "chart-no-axes-column" })
local roomLabel = textProxy(live:Label({ Text = "Room", Value = "Room: - / 18" }))
local waveLabel = textProxy(live:Label({ Text = "Wave", Value = "Wave: -" }))
local targetLabel = textProxy(live:Label({ Text = "Target", Value = "Target: -" }))
local healthLabel = textProxy(live:Label({ Text = "Target HP", Value = "HP: -" }))
local killLabel = textProxy(live:Label({ Text = "Defeated", Value = "Enemies defeated: 0" }))
local attackLabel = textProxy(live:Label({ Text = "Attacks", Value = "Attacks: 0" }))
local statusLabel = textProxy(live:Label({ Text = "Status", Value = "Status: Ready" }))
local editionArea = statusTab:Section({ Title = "Personal Edition", Icon = "info" })
editionArea:Label({ Text = "Access", Value = "Local / no key" })

local function setButton(enabled)
    syncingSpeedrun = true
    if speedrunModule:Get() ~= enabled then
        speedrunModule:Set(enabled)
    end
    syncingSpeedrun = false
end

-- Stop all background dungeon tasks if OasisUI is unloaded.
OasisUI:OnUnload(function()
    MW.worldFarmRunning = false
    MW.enemyFarmEnabled = false
    MW.bossFarmEnabled = false
    MW.bossActive = false
    MW.worldFarmSession = MW.worldFarmSession + 1
    running = false
    sessionId = sessionId + 1
    if gui.Parent then gui:Destroy() end
    local oldAccess = playerGui:FindFirstChild("PolyLootAccessV4")
    if oldAccess then oldAccess:Destroy() end
end)

local function stopMovement()
    local humanoid = getHumanoid()
    local root = getRoot()
    if humanoid and root then
        humanoid:MoveTo(root.Position)
    end
end


-- ============================================
-- Personal edition opens directly. Farming remains opt-in.
frame.Visible = true

-- ============================================
-- UNIVERSAL ANTI-AFK | IDLE EVENT + SAFE FALLBACKS
-- ============================================
-- Fired by Roblox after a period without real player input.
-- No mouse clicks are used: they could accidentally click "Run again".
-- Executor capabilities vary; successful delivery is not a guarantee
-- that Roblox will reset the inactivity timer in every environment.
local antiAfkConnection = nil
local antiAfkWarningShown = false

local function sendAntiAfkActivity()
    -- Most executor environments expose VirtualUser. Prefer its right-click
    -- simulation since it does not require foreground mouse coordinates.
    local virtualUserOk, virtualUser = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if virtualUserOk and virtualUser then
        local ok = pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        if ok then
            return true, "VirtualUser"
        end
    end

    -- Some executors expose VirtualInputManager instead.
    -- F15 should not activate normal in-game buttons or cause movement.
    local vimOk, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if vimOk and vim then
        local ok = pcall(function()
            vim:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
        end)
        if ok then
            return true, "VirtualInputManager"
        end
    end

    -- Final fallback: executor-specific keyboard APIs. Only attempt
    -- when Roblox is focused; never generate a real desktop key into
    -- the browser, another app, or a chat text field.
    if type(keypress) == "function" and type(keyrelease) == "function" then
        local gameIsFocused = true
        if type(isrbxactive) == "function" then
            local ok, active = pcall(isrbxactive)
            gameIsFocused = ok and active == true
        elseif type(isgameactive) == "function" then
            local ok, active = pcall(isgameactive)
            gameIsFocused = ok and active == true
        else
            -- Unknown focus: do not synthesize desktop input.
            gameIsFocused = false
        end

        local textBoxFocused = false
        local inputOk, inputService = pcall(function()
            return game:GetService("UserInputService")
        end)
        if inputOk and inputService then
            local ok, focused = pcall(function()
                return inputService:GetFocusedTextBox()
            end)
            textBoxFocused = not ok or focused ~= nil
        end

        if gameIsFocused and not textBoxFocused then
            local ok = pcall(function()
                keypress(0x7E) -- F15
                task.wait(0.05)
                keyrelease(0x7E)
            end)
            if ok then
                return true, "Executor F15"
            end
            -- Release best-effort even after an unexpected error.
            pcall(keyrelease, 0x7E)
        end
    end

    return false, "No supported Anti-AFK input method"
end

antiAfkConnection = player.Idled:Connect(function()
    -- When a new script execution replaces this GUI, remove this old listener.
    if not gui.Parent then
        if antiAfkConnection then
            antiAfkConnection:Disconnect()
            antiAfkConnection = nil
        end
        return
    end

    if not antiAfkEnabled or not (running or MW.worldFarmRunning) then
        return
    end

    local ok, method = sendAntiAfkActivity()
    if ok then
        debugPrint("Anti-AFK activity sent via", method)
        antiAfkWarningShown = false
    elseif not antiAfkWarningShown then
        warn("[DUNGEON V5] Anti-AFK unavailable: " .. tostring(method))
        antiAfkWarningShown = true
    end
end)

local function dismissLootPopup()
    local rewardScreen = playerGui:FindFirstChild(
        "RewardScreen"
    )
    if not rewardScreen then
        return false
    end
    local main = rewardScreen:FindFirstChild("Main")
    local header = main and main:FindFirstChild("Header")
    local title = header and header:FindFirstChild("Title")
    if not main or not title then
        return false
    end
    if not rewardScreen.Enabled
        or not main.Visible
        or title.Text ~= "NEW LOOT!" then
        return false
    end
    debugPrint("NEW LOOT Popup erkannt")
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local camera = workspace.CurrentCamera
        if not camera then
            error("Keine Kamera")
        end
        local size = camera.ViewportSize
        local x = math.floor(size.X / 2)
        local y = math.floor(size.Y / 2)
        vim:SendMouseButtonEvent(
            x, y, 0, true, game, 0
        )
        task.wait(0.08)
        vim:SendMouseButtonEvent(
            x, y, 0, false, game, 0
        )
    end)
    if not ok then
        warn(
            "[DUNGEON V4] Loot-Klick fehlgeschlagen:",
            err
        )
        return false
    end
    task.wait(0.2)
    return not rewardScreen.Enabled
        or not main.Visible
end

-- ============================================
-- DUNGEON ABSCHLUSS

-- ============================================

local function isDungeonComplete()
    local hud = playerGui:FindFirstChild("DungeonHud")
    if not hud or not hud:IsA("ScreenGui") then
        return false
    end
    local result = hud:FindFirstChild("Result")
    if not result or not result:IsA("GuiObject") then
        return false
    end
    local header = result:FindFirstChild("Header")
    local resultTitle =
        header and header:FindFirstChild("Title")
    if not resultTitle
        or not resultTitle:IsA("TextLabel") then
        return false
    end
    return hud.Enabled
        and result.Visible
        and resultTitle.Text == "Dungeon Cleared!"
end

-- ============================================
-- HALLOWEEN SCENE REPLAY CONFIRMATION
-- ============================================
-- Scene is SERVER -> CLIENT. It confirms a restart but cannot start one.
-- Observed manual replay sequence: exit {reason="again"}, arrive, gate.
-- No __namecall hooks, no RemoteEvent:FireServer calls.
local SCENE_RESTART_WAIT_SECONDS = 45
local sceneReplay = {
    exit = false,
    arrive = false,
    gate = false,
    otherExit = false,
    exitAt = 0,
    arriveAt = 0,
}

local function clearSceneReplay()
    sceneReplay.exit = false
    sceneReplay.arrive = false
    sceneReplay.gate = false
    sceneReplay.otherExit = false
    sceneReplay.exitAt = 0
    sceneReplay.arriveAt = 0
end

local sceneEventsAvailable = false
local function installSceneReplayListener()
    local replicated = game:GetService("ReplicatedStorage")
    if PRO.sceneConnection then PRO.sceneConnection:Disconnect(); PRO.sceneConnection=nil end
    local engine = PRO.dungeonId=="dark" and PRO.darkEngine
        or (PRO.dungeonId~="dark" and replicated:FindFirstChild("HalloweenDungeon_Engine"))
    local remotes = engine and engine:FindFirstChild("Remotes")
    local scene = remotes and remotes:FindFirstChild("Scene")

    if not scene or not scene:IsA("RemoteEvent") then
        debugPrint("[SCENE] Scene RemoteEvent not available; legacy replay detection")
        return false
    end

    local ok, conn = pcall(function()
        return scene.OnClientEvent:Connect(function(action, data)
            if PRO.dungeonId=="dark" then
                local info=""
                if type(data)=="table" then
                    local fields={}
                    for key,value in pairs(data) do
                        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then
                            if #fields<10 then table.insert(fields,tostring(key).."="..tostring(value):sub(1,90)) end
                        end
                    end
                    info=table.concat(fields,",")
                end
                PRO.log("Scene Dark: "..tostring(action).." "..info)
                if type(data)=="table" then
                    local index=tonumber(data.index or data.room)
                    if action=="room" and index and index>=1 and index<=PRO.roomCount then
                        PRO.sceneRoom=index; currentRoom=index
                        currentWave=0; totalWaves=tonumber(data.waves) or 0
                        PRO.darkUnlocked=nil; roomCleared=false
                        PRO.lastProgressAt=os.clock();clearPendingDoor()
                    elseif action=="wave" and tonumber(data.room)==currentRoom then
                        currentWave=tonumber(data.wave) or currentWave
                        totalWaves=tonumber(data.waves) or totalWaves
                        roomCleared=false;PRO.darkUnlocked=nil;PRO.lastProgressAt=os.clock()
                    elseif action=="cleared" and index==currentRoom then
                        roomCleared=true; PRO.lastProgressAt=os.clock()
                    elseif action=="unlock" and index==currentRoom then
                        PRO.darkUnlocked=index;PRO.darkYaw=tonumber(data.yaw)
                        roomCleared=true;PRO.lastProgressAt=os.clock()
                    elseif action=="slam" then
                        PRO.darkUnlocked=nil
                    end
                end
            end
            -- Diagnostic only: compare server gate timing with the delayed
            -- room popup. Gate signals alone do NOT prove room entry.
            if CFG.DEBUG_MODE and running and not waitingForRestart
                and action == "gate" and type(data) == "table" then
                debugPrint("[SCENE] In-run gate event:",
                    "room", tostring(data.room),
                    "open", tostring(data.open))
            end
            -- Only interpret replay events for a completed dungeon.
            if not running or not gui.Parent or not
                (waitingForRestart or isDungeonComplete()) then
                return
            end
            if type(action) ~= "string" then return end
            if type(data) ~= "table" then data = {} end

            if action == "exit" then
                local reason = tostring(data.reason or "")
                if reason == "again" then
                    if not sceneReplay.exit then
                        sceneReplay.exit = true
                        sceneReplay.exitAt = os.clock()
                        debugPrint("[SCENE] exit(reason=again): restart accepted")
                        statusLabel.Text = "Restart accepted - loading dungeon..."
                    end
                else
                    sceneReplay.otherExit = true
                    debugPrint("[SCENE] exit(reason=" .. reason .. "): not a replay")
                end
            elseif action == "arrive" and sceneReplay.exit then
                local dungeonName = tostring(data.name or "")
                if dungeonName == "" or dungeonName == (PRO.dungeonId=="dark" and "Dark Dungeon" or "Halloween Dungeon 2026") then
                    sceneReplay.arrive = true
                    sceneReplay.arriveAt = os.clock()
                    debugPrint("[SCENE] arrive: new dungeon loaded")
                    statusLabel.Text = "New dungeon loaded - waiting for gate..."
                end
            elseif PRO.dungeonId=="dark" and sceneReplay.arrive
                and ((action=="room" and tonumber(data.index or data.room)==1)
                    or (action=="wave" and tonumber(data.room)==1)) then
                -- Dark reports room/wave instead of Halloween's gate(open=true).
                sceneReplay.gate=true
                PRO.log("Reinício Dark confirmado: primeira sala ativa")
                statusLabel.Text="Dungeon pronta — retomando automaticamente"
            elseif action == "gate" and sceneReplay.arrive then
                if tonumber(data.room) == 1 and data.open == true then
                    sceneReplay.gate = true
                    debugPrint("[SCENE] gate(room=1, open=true): ready to continue")
                    statusLabel.Text = "Dungeon ready - resuming speedrun"
                end
            end
        end)
    end)

    if not ok or not conn then
        debugPrint("[SCENE] Failed to connect; legacy replay detection")
        return false
    end

    PRO.sceneConnection=conn
    -- Prevent accumulating listeners when the script GUI is destroyed.
    gui.Destroying:Connect(function()
        pcall(function() conn:Disconnect() end)
    end)
    debugPrint("[SCENE] Listener enabled: exit -> arrive -> gate")
    return true
end

PRO.rebindScene=function()
    PRO.sceneRoom=nil; PRO.darkUnlocked=nil
    clearSceneReplay()
    sceneEventsAvailable=installSceneReplayListener()
end
PRO.rebindScene()

-- ============================================
-- RAUM UND WELLEN

-- ============================================

local function processNotification(text)
    if type(text) ~= "string" then
        return
    end
    if PRO.dungeonId=="dark" then
        local room,total=text:match("Room%s+(%d+)%s*/%s*(%d+)")
        if tonumber(total)==PRO.roomCount and tonumber(room) and tonumber(room)~=currentRoom then
            currentRoom=tonumber(room); currentWave=0; roomCleared=false
            PRO.lastProgressAt=os.clock(); clearPendingDoor()
        end
    end
    local room, _, waves = text:match(
        "Room%s+(%d+)%s*/%s*(%d+)%s*[^%d]+(%d+)%s+waves"
    )
    if room then
        local newRoom = tonumber(room)
        if not PRO.dungeonId or tonumber(select(2,text:match("Room%s+(%d+)%s*/%s*(%d+)")))~=PRO.roomCount then return end
        PRO.lastProgressAt=os.clock()
        if waitingForRestart and newRoom == 1 then
            restartRoomObserved = true
            debugPrint("Neuer Dungeon: Raum 1 angekuendigt")
        end
        if newRoom ~= currentRoom then
            -- This notification is the *displayed* room progress, not proof
            -- of when the avatar first crossed the gate. Record the delay.
            if pendingRoom and newRoom > pendingRoom then
                debugPrint(
                    "[DOOR] Room popup arrived:", pendingRoom, "->", newRoom,
                    string.format("%.2fs after physical crossing",
                        math.max(0, os.clock() - pendingCrossedAt))
                )
                clearPendingDoor()
            end
            currentRoom = newRoom
            currentWave = 0
            totalWaves = tonumber(waves)
            roomCleared = false
            debugPrint("Neuer Raum:", currentRoom)
        end
        roomLabel.Text =
            "Room: " .. currentRoom .. " / " .. PRO.roomCount
        waveLabel.Text =
            "Waves: " .. totalWaves
        return
    end
    local wave, maxWave = text:match(
        "Wave%s+(%d+)%s*/%s*(%d+)"
    )
    if wave then
        currentWave = tonumber(wave)
        totalWaves = tonumber(maxWave)
        roomCleared = false
        waveLabel.Text =
            "Wave: " .. currentWave
            .. " / " .. totalWaves
        return
    end
    if text:lower():find("final wave", 1, true) then
        currentWave = totalWaves
        roomCleared = false
        waveLabel.Text = "Final wave"
        return
    end
    if text:lower():find("room cleared", 1, true) then
        roomCleared = true
        statusLabel.Text = "Room cleared"
        debugPrint("Raum abgeschlossen:", currentRoom)
    end
end

-- ============================================
-- DYNAMISCHE UI ERKENNUNG

-- ============================================
local observedLabels = {}

local function isNotificationLabel(obj)
    if not obj:IsA("TextLabel")
        or obj.Name ~= "text" then
        return false
    end
    local parent = obj.Parent
    return parent ~= nil
        and (
            parent.Name == "Blank"
            or parent.Name == "Success"
        )
end

local function observeLabel(label)
    if observedLabels[label] then
        return
    end
    observedLabels[label] = true
    label:GetPropertyChangedSignal("Text"):Connect(
        function()
            if gui.Parent then
                processNotification(label.Text)
            end
        end
    )
    processNotification(label.Text)
end

local function registerNotificationUI()
    local notifi = playerGui:FindFirstChild("NotifiUI")
    local notificationFrame =
        notifi and notifi:FindFirstChild("Frame")
    if not notificationFrame then
        return
    end
    for _, obj in ipairs(notificationFrame:GetDescendants()) do
        if isNotificationLabel(obj) then
            observeLabel(obj)
        end
    end
    notificationFrame.DescendantAdded:Connect(function(obj)
        if isNotificationLabel(obj) then
            observeLabel(obj)
        end
    end)
end
task.spawn(function()
    local notifi = playerGui:WaitForChild(
        "NotifiUI",
        15
    )
    if notifi then
        registerNotificationUI()
    else
        warn("[DUNGEON V4] NotifiUI nicht gefunden")
    end
end)

-- ============================================
-- GEGNER ERKENNEN

-- ============================================

local function enemyAlive(enemy)
    local folder = getEnemies()
    if not folder or not enemy
        or not enemy:IsDescendantOf(folder) then
        return false
    end
    local hp = enemy:GetAttribute("Health")
    return typeof(hp) == "number" and hp > 0
end

local function enemyPosition(enemy)
    if enemy and enemy:IsA("Model") then
        return enemy:GetPivot().Position
    end
    return nil
end

local function getNextEnemy()
    local root = getRoot()
    local folder = getEnemies()
    if not root or not folder then
        return nil
    end
    local nearest = nil
    local bestDistance = CFG.TARGET_SEARCH_RADIUS
    local now = os.clock()
    for _, enemy in ipairs(PRO.dungeonId=="dark" and folder:GetDescendants() or folder:GetChildren()) do
        if enemy:IsA("Model")
            and enemyAlive(enemy)
            and (skippedEnemies[enemy] or 0) <= now then
            local position = enemyPosition(enemy)
            if position then
                if PRO.dungeonId=="dark" then
                    local chain=getDungeon()
                    if not chain then continue end
                    local params=RaycastParams.new()
                    params.FilterType=Enum.RaycastFilterType.Include
                    params.FilterDescendantsInstances={chain}
                    local _,enemyRoom=PRO.floorRun({Position=position},{chain})
                    if not enemyRoom or enemyRoom~=currentRoom then continue end
                end
                local distance =
                    horizontalDistance(
                        root.Position,
                        position
                    )
                if distance < bestDistance then
                    nearest = enemy
                    bestDistance = distance
                end
            end
        end
    end
    return nearest
end

-- ============================================
-- GEGNER MARKIEREN

-- ============================================

local function clearTarget()
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    targetLabel.Text = "Target: -"
end

local function markEnemy(enemy)
    clearTarget()
    local highlight = Instance.new("Highlight")
    highlight.Name = "DungeonTarget"
    highlight.Adornee = enemy
    highlight.FillColor = Color3.fromRGB(255, 60, 60)
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.65
    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = gui
    currentHighlight = highlight
    targetLabel.Text =
        "Target: " .. enemy.Name:sub(1, 12)
end


-- DUNGEON SAFETY V5.10.6 | Ground verification + out-of-bounds recovery
-- The bridge and room edges may contain open space beneath a valid X/Z target.
local dungeonSafeCF = nil
local dungeonSafeAt = 0
local dungeonRecoveryAt = -math.huge

local function dungeonGroundAt(position)
    local dungeon = getDungeon()
    if not dungeon then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    local character = getCharacter()
    if character then table.insert(exclude, character) end
    local live = workspace:FindFirstChild("Animal_Live")
    if live then table.insert(exclude, live) end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    local result = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -19, 0), params)
    if not result or not result.Instance or not result.Instance.CanCollide
        or result.Normal.Y < 0.65 or not result.Instance:IsDescendantOf(dungeon) then
        return nil
    end
    -- Do not treat a floor far below the intended Y as the correct bridge deck.
    if math.abs(position.Y - (result.Position.Y + 3)) > 7 then return nil end
    return result
end

local function dungeonSafeDestination(position)
    local hit = dungeonGroundAt(position)
    if not hit then return nil end
    return Vector3.new(position.X, hit.Position.Y + 3.2, position.Z)
end

local function dungeonSafetyWatch()
    if currentRoom <= 0 or dungeonComplete then return false end
    local root, char = getRoot(), getCharacter()
    local humanoid = getHumanoid()
    if not root or not char or not humanoid or humanoid.Health <= 0 then return false end
    local now = os.clock()
    local hit = dungeonGroundAt(root.Position)
    if hit then
        -- Only remember positions with a real dungeon floor directly beneath us.
        if now - dungeonRecoveryAt > 1.5 then
            dungeonSafeCF = root.CFrame
            dungeonSafeAt = now
        end
        return false
    end
    -- An airborne character is normal briefly; rescue only a sustained fall
    -- significantly lower than the last confirmed safe floor.
    if dungeonSafeCF and now - dungeonSafeAt < 45
        and root.Position.Y < dungeonSafeCF.Position.Y - 12
        and now - dungeonRecoveryAt > 2 then
        dungeonRecoveryAt = now
        debugPrint("[DUNGEON][SAFETY] Falling below floor; recovering", currentRoom,
            "drop", math.floor(dungeonSafeCF.Position.Y - root.Position.Y))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        char:PivotTo(dungeonSafeCF)
        clearPendingDoor()
        approachRoom, approachDoor, approachDirection = nil, nil, nil
        CFG.transitionUntil = now + 0.7
        statusLabel.Text = "Dungeon: recovered from falling"
        return true
    end
    return false
end

-- ============================================
-- TELEPORT ZUM GEGNER

-- ============================================

local function teleportToEnemy(enemy)
    local character = getCharacter()
    local root = getRoot()
    local position = enemyPosition(enemy)
    if not character or not root or not position then
        return false
    end
    local horizontal = Vector3.new(
        root.Position.X - position.X,
        0,
        root.Position.Z - position.Z
    )
    local direction
    if horizontal.Magnitude > 0.01 then
        direction = horizontal.Unit
    else
        direction = -root.CFrame.LookVector
        direction = Vector3.new(
            direction.X,
            0,
            direction.Z
        )
        if direction.Magnitude < 0.01 then
            direction = Vector3.new(0, 0, 1)
        else
            direction = direction.Unit
        end
    end
    local destination =
        Vector3.new(
            position.X,
            root.Position.Y,
            position.Z
        ) + direction * CFG.ATTACK_DISTANCE
    destination = dungeonSafeDestination(destination)
    if not destination then
        debugPrint("[DUNGEON][SAFETY] Enemy teleport skipped (no safe floor)", enemy.Name)
        return false
    end
    local lookTarget = Vector3.new(
        position.X,
        destination.Y,
        position.Z
    )
    if (lookTarget - destination).Magnitude < 0.01 then
        return false
    end
    character:PivotTo(
        CFrame.lookAt(destination, lookTarget)
    )
    return true
end

-- ============================================
-- AUTOMATISCHER KAMPF

-- ============================================

local function fightEnemy(enemy, id)
    markEnemy(enemy)
    local lastAttack = -math.huge
    local lastTeleport = -math.huge
    local lastDamage = os.clock()
    local oldHealth = enemy:GetAttribute("Health")
    local attackPauseUntil = 0
    local nextCombatLog=0
    debugPrint("Kampf gestartet:", enemy.Name)
-- Einmal zum ersten Ziel teleportieren
    teleportToEnemy(enemy)
    while validSession(id)
        and enemyAlive(enemy)
        and not isDungeonComplete() do
        RunService.Heartbeat:Wait()
        if not validSession(id)
            or not enemyAlive(enemy) then
            break
        end
        local now = os.clock()
        local weapon = getWeapon()
        local root = getRoot()
        local humanoid = getHumanoid()
        if not weapon or not root or not humanoid
            or humanoid.Health <= 0 then
            statusLabel.Text = "Weapon or character missing"
            break
        end
        if PRO.healthFloor>0 and humanoid.MaxHealth>0
            and humanoid.Health/humanoid.MaxHealth*100<PRO.healthFloor then
            stopMovement(); statusLabel.Text="Vida baixa: combate pausado (sem cura automática)"
            task.wait(0.5); continue
        end
        local hp = enemy:GetAttribute("Health")
        local maxHP = enemy:GetAttribute("MaxHealth")
        if typeof(hp) ~= "number" then
            break
        end
        healthLabel.Text =
            "HP: " .. math.floor(hp)
            .. " / " .. tostring(
                typeof(maxHP) == "number"
                and math.floor(maxHP)
                or "?"
            )
        if oldHealth and hp < oldHealth then
            lastDamage = now
            PRO.lastProgressAt=now
        end
        oldHealth = hp
        local position = enemyPosition(enemy)
        if not position then
            break
        end
        local distance =
            horizontalDistance(root.Position, position)
        if PRO.dungeonId=="dark" and now>=nextCombatLog then
            nextCombatLog=now+3
            PRO.log(string.format("COMBATE alvo=%s arma=%s habilitada=%s HP=%.1f distXZ=%.1f altura=%.1f ataques=%d semDano=%.1fs",
                enemy.Name,weapon.Name,tostring(weapon.Enabled),hp,distance,
                math.abs(root.Position.Y-position.Y),attackCount,now-lastDamage))
        end
-- Position nur bei Bedarf korrigieren.-- Keine Korrektur direkt waehrend Angriffspause.
        if now >= attackPauseUntil
            and now - lastTeleport >= CFG.REPOSITION_INTERVAL
            and distance > CFG.REPOSITION_DISTANCE then
            teleportToEnemy(enemy)
            lastTeleport = now
            statusLabel.Text = "Position adjusted"
        end
-- Angriff
        if distance <= CFG.REPOSITION_DISTANCE
            and weapon.Enabled
            and now - lastAttack >= CFG.ATTACK_INTERVAL
            and now >= attackPauseUntil then
-- Position unmittelbar vor Angriff korrigieren,-- aber nicht bei jedem Frame.
            if distance > CFG.ATTACK_DISTANCE + 0.4 then
                teleportToEnemy(enemy)
                task.wait(0.05)
            end
            if not validSession(id)
                or not enemyAlive(enemy) then
                break
            end
            weapon:Activate()
            lastAttack = os.clock()
            attackPauseUntil =
                lastAttack + CFG.ATTACK_STABILIZE
            attackCount = attackCount + 1
            attackLabel.Text =
                "Attacks: " .. attackCount
            statusLabel.Text = "Attacking enemy"
        end
-- Anti-Stuck bei ausbleibendem HP-Verlust
        if now - lastDamage >= CFG.NO_DAMAGE_TIMEOUT then
            skippedEnemies[enemy] =
                now + CFG.ENEMY_RETRY_DELAY
            debugPrint(
                "Kein HP-Fortschritt:",
                enemy.Name
            )
            break
        end
    end
    local ended = not enemyAlive(enemy)
    if validSession(id) then
        clearTarget()
        if ended then
            defeatedCount = defeatedCount + 1
            PRO.kills+=1
            killLabel.Text =
                "Enemies defeated: " .. defeatedCount
        end
    end
    return ended
end

-- ============================================
-- PASSENDE OFFENE TÜR FINDEN

-- ============================================

-- Only the exact current-room Door group is eligible: never EntrySeal or DoorFAKE.

function PRO.darkDoor()
    local chain=getDungeon()
    if not chain or currentRoom<1 or currentRoom>=PRO.roomCount then return nil end
    -- All physical Door pieces being non-collidable also allows late-starting in an already-cleared room.
    for _,room in ipairs(chain:GetChildren()) do
        if PRO.roomNumber(room.Name)==currentRoom then
            local assembly=room:FindFirstChild("Door")
            if not assembly then return nil end
            local parts={}
            if assembly:IsA("BasePart") then table.insert(parts,assembly) end
            for _,part in ipairs(assembly:GetDescendants()) do
                if part:IsA("BasePart") then table.insert(parts,part) end
            end
            if #parts==0 then return nil end
            for _,part in ipairs(parts) do if part.CanCollide then return nil end end
            local representative=parts[1]
            for _,part in ipairs(parts) do if part.Name=="DoorWood" then representative=part;break end end
            return representative,assembly,parts
        end
    end
    return nil
end

local function getOpenDoor()
    if PRO.dungeonId=="dark" then return PRO.darkDoor() end
    local dungeonFolder = getDungeon()
    local root = getRoot()
    if not dungeonFolder or not root
        or currentRoom <= 0
        or currentRoom >= PRO.roomCount then
        return nil
    end
    local nearestDoor = nil
    local nearestDistance = math.huge
-- Die Raumnummer im Ordner kann abweichen.-- Deshalb mehrere benachbarte Indizes erlauben.
    local minIndex = currentRoom + 1
    local maxIndex = currentRoom + 3
    for _, door in ipairs(dungeonFolder:GetDescendants()) do
        if door:IsA("BasePart")
            and door.Name == "Door"
            and door.CanCollide == false
            and not usedDoors[door] then
            local roomFolder = door.Parent and door.Parent.Parent
            if PRO.dungeonId=="dark" then
                roomFolder=door.Parent
                while roomFolder and roomFolder~=dungeonFolder and not PRO.roomNumber(roomFolder.Name) do
                    roomFolder=roomFolder.Parent
                end
            end
            local index = roomFolder and PRO.roomNumber(roomFolder.Name)
            if index
                and index >= minIndex
                and index <= maxIndex then
                local distance = horizontalDistance(
                    root.Position,
                    door.Position
                )
                if distance < nearestDistance then
                    nearestDoor = door
                    nearestDistance = distance
                end
            end
        end
    end
    if nearestDoor then
        debugPrint(
            "Offene Ausgangstuer gefunden:",
            nearestDoor:GetFullName(),
            "Distanz:",
            math.floor(nearestDistance)
        )
    end
    return nearestDoor
end

local function enterFirstRoom(id)
    if not validSession(id) or currentRoom > 0 then
        return false
    end
    local dungeon = getDungeon()
    local character = getCharacter()
    local root = getRoot()
    if not dungeon or not character or not root then
        debugPrint("Dungeon oder Charakter fehlt")
        return false
    end
-- Exakte Eingangstuer suchen
    local startRoom = dungeon:FindFirstChild(
        "01_StartingRoom",
        true
    )
    if PRO.dungeonId=="dark" then
        PRO.refreshDarkRoom()
        return currentRoom>0 -- manual entry is already inside an indexed room
    end
    if not startRoom then
        debugPrint("StartingRoom nicht gefunden")
        return false
    end
    local walls = startRoom:FindFirstChild("InvisWalls")
    local door = walls and walls:FindFirstChild("Door")
    if not door or not door:IsA("BasePart") then
        debugPrint("Eingangstuer nicht gefunden")
        return false
    end
    if door.CanCollide then
        debugPrint("Eingangstuer ist geschlossen")
        return false
    end
    local direction = Vector3.new(
        door.Position.X - root.Position.X,
        0,
        door.Position.Z - root.Position.Z
    )
    if direction.Magnitude < 0.1 then
        debugPrint("Richtung nicht bestimmbar")
        return false
    end
    direction = direction.Unit
    local destination = Vector3.new(
        door.Position.X,
        root.Position.Y,
        door.Position.Z
    ) + direction * CFG.DOOR_TELEPORT_DISTANCE
    destination = dungeonSafeDestination(destination)
    if not destination then
        debugPrint("[DUNGEON][SAFETY] First door skipped: unsafe landing")
        return false
    end
    debugPrint(
        "Teleportiere durch Dungeon-Eingang:",
        door:GetFullName()
    )
    character:PivotTo(
        CFrame.lookAt(
            destination,
            destination + direction
        )
    )
    CFG.transitionUntil = os.clock() + CFG.ROOM_TRANSITION_DELAY
-- Auf Raum 1 warten
    local started = os.clock()
    while validSession(id)
        and os.clock() - started < CFG.ROOM_CONFIRM_TIMEOUT do
        if currentRoom >= 1 then
            debugPrint(
                "Dungeon erfolgreich gestartet! Raum:",
                currentRoom
            )
            return true
        end
        task.wait(0.1)
    end
    debugPrint(
        "Eingang betreten, aber Raum 1 nicht bestaetigt"
    )
    return false
end

-- ============================================
-- CROSS OPEN DOOR | V5.5 / CONTINUOUS ROLLBACK MONITOR
-- ============================================
-- The popup is not a reliable real-time position sensor. After crossing,
-- continuously monitor the door side and wait for the popup as long as the
-- character remains in the new room. Retry on confirmed rollback only.
-- Bounded to 3 attempts per transition, with no new remote calls.

function PRO.doorApproach(center,normal,size,position)
    normal=Vector3.new(normal.X,0,normal.Z)
    if normal.Magnitude<0.1 then return nil end
    normal=normal.Unit
    if (position-center):Dot(normal)>0 then normal=-normal end
    local thickness=math.min(size.X,size.Z)
    return center-normal*(thickness/2+5),center+normal*(thickness/2+8),normal
end

-- Validate fallback walking against floor gaps and collidable obstacles.
function PRO.safeDarkSegment(from,to,roomIndex)
    if (to-from).Magnitude>300 then return false end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={getCharacter()}
    params.RespectCanCollide=true
    params.IgnoreWater=true
    local steps=math.max(1,math.ceil((to-from).Magnitude/2))
    local previous=from
    for i=1,steps do
        local point=dungeonSafeDestination(from:Lerp(to,i/steps))
        if not point or math.abs(point.Y-previous.Y)>2 then return false end
        local _,index=PRO.floorRun({Position=point},{getDungeon()})
        if index~=roomIndex then return false end
        local delta=point-previous
        if delta.Magnitude>0.01 then
            local ok,hit=pcall(function()
                return workspace:Blockcast(CFrame.new(previous),Vector3.new(2,4,2),delta,params)
            end)
            if not ok or hit then return false end
        end
        previous=point
    end
    return true
end

function PRO.darkFallbackRoute(from,destination,roomIndex)
    local routes={{destination}}
    local saved=PRO.preLootPosition
    if saved and saved.run==getDungeon() and saved.room==roomIndex
        and os.clock()-saved.time<90 then
        table.insert(routes,{saved.position,destination})
    end
    table.insert(routes,{Vector3.new(destination.X,from.Y,from.Z),destination})
    table.insert(routes,{Vector3.new(from.X,from.Y,destination.Z),destination})
    for _,route in ipairs(routes) do
        local previous=from
        local valid=true
        for _,point in ipairs(route) do
            if not PRO.safeDarkSegment(previous,point,roomIndex) then valid=false;break end
            previous=point
        end
        if valid then return route end
    end
    return nil
end

function PRO.walkDarkApproach(id,destination,roomIndex,parts)
    local deadline=os.clock()+30
    local function ready()
        if not validSession(id) or currentRoom~=roomIndex or os.clock()>=deadline then return false end
        local hum=getHumanoid()
        if not hum or hum.Health<=0 then return false end
        for _,part in ipairs(parts) do if not part.Parent or part.CanCollide then return false end end
        return true
    end
    local function walkWaypoint(point,jump)
        if not ready() then return false end
        local root,hum=getRoot(),getHumanoid()
        if not root then return false end
        if horizontalDistance(root.Position,point)<=1.5 then return true end
        if jump then hum.Jump=true end
        hum:MoveTo(point)
        local started=os.clock()
        local checkedAt=started
        local lastPosition=root.Position
        while ready() and os.clock()-started<8 do
            task.wait(0.1)
            root=getRoot()
            if not root then return false end
            if horizontalDistance(root.Position,point)<=1.5 then return true end
            if os.clock()-checkedAt>=1.8 then
                if horizontalDistance(root.Position,lastPosition)<0.5 then return false end
                checkedAt=os.clock();lastPosition=root.Position
            end
        end
        return false
    end
    for attempt=1,2 do
        if not ready() then stopMovement();return false end
        local root=getRoot()
        if not root then return false end
        if horizontalDistance(root.Position,destination)<=2 then return true end
        local path
        local ok,err=pcall(function()
            path=game:GetService("PathfindingService"):CreatePath({
                AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=3,
            })
            path:ComputeAsync(root.Position,destination)
        end)
        local points={}
        if ok and path and path.Status==Enum.PathStatus.Success then
            points=path:GetWaypoints()
        end
        local fallback=false
        if #points==0 then
            PRO.log("Porta Dark: caminho indisponível; procurando rota livre: "..tostring(err or (path and path.Status)))
            local route=PRO.darkFallbackRoute(root.Position,destination,roomIndex)
            if not route then
                PRO.log("Porta Dark: nenhuma rota segura após a coleta; nova tentativa em breve")
                stopMovement();return false
            end
            fallback=true
            for _,point in ipairs(route) do table.insert(points,{Position=point}) end
            PRO.log("Porta Dark: retomando caminhada por rota alternativa")
        end
        -- Approach paths must stay in the current room. Crossing is a separate step.
        for _,point in ipairs(points) do
            local _,index=PRO.floorRun({Position=point.Position},{getDungeon()})
            if index~=roomIndex then
                PRO.log("Porta Dark: caminho de aproximação sairia da sala; cancelado")
                stopMovement();return false
            end
        end
        local followed=true
        for _,point in ipairs(points) do
            local liveRoot=getRoot()
            if fallback and (not liveRoot or not PRO.safeDarkSegment(liveRoot.Position,point.Position,roomIndex)) then
                followed=false;break
            end
            if not walkWaypoint(point.Position,point.Action==Enum.PathWaypointAction.Jump) then followed=false;break end
        end
        root=getRoot()
        if followed and ready() and root and horizontalDistance(root.Position,destination)<=2 then return true end
        stopMovement()
        PRO.log("Porta Dark: aproximação interrompida; recalculando "..attempt.."/2")
    end
    return false
end

function PRO.crossDarkDoorWalk(id)
    local door,assembly,parts=PRO.darkDoor()
    local root,humanoid,char=getRoot(),getHumanoid(),getCharacter()
    if not door or not root or not humanoid or not char or getNextEnemy() then return false end
    local before=currentRoom
    -- The threshold is stationary even if the opened door leaves move aside.
    local room=assembly.Parent
    local threshold=room and room:FindFirstChild("DoorThreshold")
    local anchor=threshold and threshold:IsA("BasePart") and threshold or door
    local boxCF,boxSize=anchor.CFrame,anchor.Size
    local center=Vector3.new(boxCF.Position.X,root.Position.Y,boxCF.Position.Z)
    local axis=boxSize.X<boxSize.Z and boxCF.RightVector or boxCF.LookVector
    local near,far,normal=PRO.doorApproach(center,axis,boxSize,root.Position)
    if not near then return false end
    near=dungeonSafeDestination(near)
    far=dungeonSafeDestination(far)
    if not near or not far then
        PRO.log("Porta Dark: piso de aproximação/saída não confirmado; movimento cancelado")
        return false
    end
    -- Verify that the walking alignment point stays on the current-room side.
    local _,nearRoom=PRO.floorRun({Position=near},{getDungeon()})
    if nearRoom~=before then
        PRO.log("Porta Dark: alinhamento fora da sala atual; movimento cancelado")
        return false
    end
    if not validSession(id) or currentRoom~=before then return false end
    for _,part in ipairs(parts) do if not part.Parent or part.CanCollide then return false end end
    if os.clock()<(PRO.nextDoorAttempt or 0) then return false end
    statusLabel.Text="Caminhando até a porta da sala "..before
    PRO.log("Porta Dark: aproximação a pé por "..anchor:GetFullName()..
        " | destino="..tostring(near).." saída="..tostring(far))
    if not PRO.walkDarkApproach(id,near,before,parts) then
        PRO.nextDoorAttempt=os.clock()+3
        statusLabel.Text="Não foi possível alcançar a porta a pé; veja o diagnóstico"
        return false
    end
    if not validSession(id) or currentRoom~=before then return currentRoom>before end
    root=getRoot();humanoid=getHumanoid()
    if not root or not humanoid or humanoid.Health<=0 then return false end
    -- No PivotTo/CFrame/velocity write anywhere in the Dark door traversal.
    -- The whole transition uses ordinary walking, with natural Humanoid rotation.
    statusLabel.Text="Caminhando reto pela porta aberta"
    humanoid:MoveTo(far)
    local started=os.clock()
    local checkedAt=started
    local lastPosition=root.Position
    while validSession(id) and currentRoom==before and os.clock()-started<8 do
        task.wait(0.1)
        root=getRoot();humanoid=getHumanoid()
        if not root or not humanoid or humanoid.Health<=0 or not assembly.Parent then return false end
        if currentRoom~=before then break end
        for _,part in ipairs(parts) do
            if not part.Parent or part.CanCollide then stopMovement();return false end
        end
        if os.clock()-checkedAt>=1.5 then
            local moved=horizontalDistance(root.Position,lastPosition)
            if moved<0.5 and horizontalDistance(root.Position,far)>2 then
                stopMovement()
                PRO.log("Porta Dark: caminhada bloqueada; não vou insistir contra a parede")
                return false
            end
            checkedAt=os.clock();lastPosition=root.Position
        end
        if horizontalDistance(root.Position,far)<1 then break end
    end
    local untilTime=os.clock()+3
    while validSession(id) and currentRoom==before and os.clock()<untilTime do task.wait(0.1) end
    if currentRoom>before then
        usedDoors[door]=true;clearPendingDoor();PRO.lastProgressAt=os.clock()
        PRO.log("Caminhada pela porta confirmada: sala "..currentRoom)
        return true
    end
    stopMovement()
    PRO.log("Caminhada terminou sem nova sala confirmada; gere diagnóstico")
    return false
end

function PRO.crossDarkDoor(id)
    local humanoid=getHumanoid()
    if not humanoid or humanoid.Health<=0 or not validSession(id) then return false end
    local original=humanoid.WalkSpeed
    local requested=math.clamp(tonumber(PRO.doorWalkSpeed) or 24,16,40)
    local applied=math.max(original,requested) -- never slow an already faster character
    humanoid.WalkSpeed=applied
    local ok,result=xpcall(function() return PRO.crossDarkDoorWalk(id) end,debug.traceback)
    -- Restore on success, failure or cancellation. Do not overwrite a game-side speed change.
    if humanoid.Parent and humanoid.WalkSpeed==applied then humanoid.WalkSpeed=original end
    if not ok then
        pcall(stopMovement)
        PRO.log("Erro ao atravessar porta: "..tostring(result))
        return false
    end
    return result
end

local function teleportThroughDoor(id)
    if PRO.dungeonId=="dark" then return PRO.crossDarkDoor(id) end
    if not validSession(id) or currentRoom <= 0 or currentRoom >= PRO.roomCount then
        return false
    end

    local door = getOpenDoor()
    if not door or not door:IsA("BasePart") or door.CanCollide then
        return false
    end

    local roomBefore = currentRoom
    local initialRoot = getRoot()
    if not initialRoot then return false end

    if approachRoom ~= roomBefore or approachDoor ~= door
        or not approachDirection then
        local delta = Vector3.new(
            door.Position.X - initialRoot.Position.X,
            0,
            door.Position.Z - initialRoot.Position.Z
        )
        if delta.Magnitude < 0.1 then
            debugPrint("[DOOR] Cannot determine door direction")
            return false
        end
        approachRoom = roomBefore
        approachDoor = door
        approachDirection = delta.Unit
    end

    local direction = approachDirection
    local started = os.clock()
    local attempts = 0
    local lastAttemptAt = 0
    local positionCheckAt = 0
    local lastTarget = nil
    local physicalCrossingSeen = false
    local rollback = false
    local rollbackSamples = 0
    local firstPositionLogged = false

    local function measurePosition()
        local root = getRoot()
        if not root or not door.Parent then return nil, nil end
        local delta = Vector3.new(
            root.Position.X - door.Position.X,
            0,
            root.Position.Z - door.Position.Z
        )
        local side = delta:Dot(direction)
        local targetOffset = lastTarget
            and horizontalDistance(root.Position, lastTarget) or nil
        return side, targetOffset
    end

    local function directAttempt(reason)
        if not validSession(id) or currentRoom ~= roomBefore
            or isDungeonComplete() or not door.Parent or door.CanCollide then
            return false
        end
        local character = getCharacter()
        local root = getRoot()
        if not character or not root then return false end
        local target = Vector3.new(
            door.Position.X, root.Position.Y, door.Position.Z
        ) + direction * CFG.DOOR_TELEPORT_DISTANCE
        target = dungeonSafeDestination(target)
        if not target then
            debugPrint("[DUNGEON][SAFETY] Door teleport skipped: no safe floor", roomBefore)
            return false
        end
        attempts = attempts + 1
        lastAttemptAt = os.clock()
        positionCheckAt = lastAttemptAt + CFG.ROOM_POSITION_CHECK_DELAY
        lastTarget = target
        rollback = false
        rollbackSamples = 0
        firstPositionLogged = false
        CFG.transitionUntil = os.clock() + CFG.ROOM_TRANSITION_DELAY
        statusLabel.Text = "Crossing into room " .. (roomBefore + 1)
        debugPrint(
            "[DOOR] Direct attempt", attempts,
            "room", roomBefore, "->", roomBefore + 1,
            "trigger", reason,
            "doorDistance", string.format("%.1f",
                horizontalDistance(root.Position, door.Position))
        )
        character:PivotTo(CFrame.lookAt(target, target + direction))
        return true
    end

    if not directAttempt("initial") then return false end

    while validSession(id) and os.clock() - started < CFG.ROOM_CONFIRM_TIMEOUT do
        if isDungeonComplete() then return false end

        if currentRoom > roomBefore then
            usedDoors[door] = true
            roomCleared = false
            approachRoom = nil
            approachDoor = nil
            approachDirection = nil
            clearPendingDoor()
            debugPrint(
                "[DOOR] Room transition confirmed:",
                roomBefore, "->", currentRoom,
                string.format("%.2fs", os.clock() - started),
                "attempts", attempts
            )
            return true
        end

        local now = os.clock()
        -- V5.5: continue sampling after the first 0.22-second position check.
        -- In V5.4 we sampled once, so a later server snapback could remain
        -- unnoticed until the full timeout or pending-popup grace handling.
        if positionCheckAt > 0 and now >= positionCheckAt then
            positionCheckAt = now + CFG.ROOM_POSITION_POLL_INTERVAL
            local side, targetOffset = measurePosition()
            if side then
                local wasRollback = rollback
                if side < -3 then
                    rollbackSamples = rollbackSamples + 1
                else
                    rollbackSamples = 0
                end
                rollback = rollbackSamples >= CFG.ROOM_ROLLBACK_CONFIRM_SAMPLES

                if side >= CFG.ROOM_CROSSED_SIDE_THRESHOLD
                    and targetOffset
                    and targetOffset <= CFG.ROOM_CLOSE_TO_TARGET_THRESHOLD then
                    if not physicalCrossingSeen then
                        physicalCrossingSeen = true
                        pendingDoor = door
                        pendingRoom = roomBefore
                        pendingDirection = direction
                        pendingCrossedAt = now
                        pendingDoorLogAt = now
                        debugPrint(
                            "[DOOR] Behind door; monitoring position and popup:",
                            roomBefore, "->", roomBefore + 1
                        )
                    end
                end

                if not firstPositionLogged or (rollback and not wasRollback) then
                    debugPrint(
                        "[DOOR] Position check:",
                        "attempt", attempts,
                        "side", string.format("%.1f", side),
                        "targetOffset", string.format("%.1f", targetOffset or -1),
                        "returnedToStartSide", tostring(rollback),
                        "rollbackSamples", rollbackSamples
                    )
                    firstPositionLogged = true
                end
                if rollback and not wasRollback then
                    debugPrint(
                        "[DOOR] Late rollback detected; retrying without waiting for timeout",
                        "room", roomBefore, "->", roomBefore + 1,
                        "elapsed", string.format("%.2fs", now - started)
                    )
                end
            end
        end

        -- Never repeat an already successful physical crossing simply because
        -- the game's notification is late. Only retry when the avatar is
        -- actually back on the starting side of the selected door.
        if rollback and attempts < CFG.ROOM_MAX_CROSS_ATTEMPTS
            and now - lastAttemptAt >= CFG.ROOM_RETRY_AFTER_ROLLBACK then
            physicalCrossingSeen = false
            clearPendingDoor()
            if not directAttempt("measured rollback") then break end
        end

        task.wait(0.06)
    end

    local side, targetOffset = measurePosition()
    debugPrint(
        "[DOOR] Popup still pending after crossing:", roomBefore,
        "attempts", attempts,
        "side", side and string.format("%.1f", side) or "n/a",
        "targetOffset", targetOffset
            and string.format("%.1f", targetOffset) or "n/a"
    )
    -- The next main-loop iteration observes pendingDoor first. It waits for
    -- the popup, unless the avatar moves back to the original side.
    return false
end

local function waitingForDelayedRoomPopup()
    if not pendingDoor or pendingRoom ~= currentRoom
        or not pendingDirection or not pendingDoor.Parent then
        clearPendingDoor()
        return false
    end

    local root = getRoot()
    if not root then return false end

    local offset = Vector3.new(
        root.Position.X - pendingDoor.Position.X,
        0,
        root.Position.Z - pendingDoor.Position.Z
    )
    local side = offset:Dot(pendingDirection)

    -- We are genuinely back in the previous room: allow recovery crossing.
    if side < -3 then
        debugPrint("[DOOR] Physical rollback confirmed; retry enabled", side)
        clearPendingDoor()
        return false
    end

    -- Pending notifications are given a bounded grace period so the script
    -- cannot get stuck forever waiting for a UI popup that never appears.
    if os.clock() - pendingCrossedAt < CFG.ROOM_POPUP_GRACE_SECONDS then
        if os.clock() - pendingDoorLogAt >= 1.0 then
            debugPrint("[DOOR] Waiting for room popup, still behind door:",
                currentRoom, "side", string.format("%.1f", side))
            pendingDoorLogAt = os.clock()
        end
        return true
    end

    debugPrint("[DOOR] Popup grace expired; allowing one recovery pass:",
        currentRoom, "side", string.format("%.1f", side))
    clearPendingDoor()
    return false
end

-- ============================================
-- HAUPTSCHLEIFE

-- ============================================

local function resetDungeonRun(roomAlreadyDetected)
    PRO.runStartedAt=os.clock() -- next run starts only after confirmed replay
-- Raum 1 kann bereits gemeldet worden sein,-- bevor die Result-Anzeige verschwindet.
    currentRoom = roomAlreadyDetected and 1 or 0
    currentWave = 0
    totalWaves = 0
    roomCleared = false
    dungeonComplete = false
    waitingForRestart = false
    finalLootHandled = false
    restartRoomObserved = false
    replayAttempted = false
    replayAttemptAt = 0
    clearSceneReplay()
    skippedEnemies = {}
    usedDoors = {}
    lastRoomAttempt = 0
    lootCheckedRoom = nil
    approachRoom = nil
    approachDoor = nil
    approachDirection = nil
    clearPendingDoor()
    dungeonSafeCF = nil
    dungeonSafeAt = 0
    dungeonRecoveryAt = -math.huge
    CFG.transitionUntil = 0
    attackCount = 0
    defeatedCount = 0
    clearTarget()
    stopMovement()
    roomLabel.Text = roomAlreadyDetected
        and ("Room: 1 / "..PRO.roomCount)
        or ("Room: - / "..PRO.roomCount)
    waveLabel.Text = "Wave: -"
    targetLabel.Text = "Target: -"
    healthLabel.Text = "HP: -"
    killLabel.Text = "Enemies defeated: 0"
    attackLabel.Text = "Attacks: 0"
    statusLabel.Text = "Starting new run"
    debugPrint(
        "Dungeon-Reset abgeschlossen!",
        "Abgeschlossene Runs:",
        completedRuns
    )
end

local function getNearbyDrops(origin)
    local folder = workspace:FindFirstChild("WorldBits")
    local root = getRoot()
    if not folder or not root then
        return {}
    end
    origin = origin or root.Position
    local drops = {}
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local aura = model:FindFirstChild(
                "DropAura",
                true
            )
            local prompt = model:FindFirstChild(
                "ProximityPrompt",
                true
            )
            if aura
                and aura:IsA("BasePart")
                and aura:GetAttribute("DropAura") == true
                and prompt
                and prompt:IsA("ProximityPrompt")
                and prompt.ActionText == "Pick Up"
                and prompt.Enabled then
                local distance = (
                    aura.Position - origin
                ).Magnitude
                if distance <= CFG.LOOT_SEARCH_RADIUS then
                    table.insert(drops, {
                        model = model,
                        aura = aura,
                        prompt = prompt,
                        distance = distance
                    })
                end
            end
        end
    end
    table.sort(drops, function(a, b)
        return a.distance < b.distance
    end)
    return drops
end

local function collectDroppedItems(id)
    if not PRO.lootEnabled then return true end
    if not validSession(id) then
        return false
    end
    statusLabel.Text = "Checking for dropped items"
-- Warten, damit verzoegerte Drops erscheinen
    task.wait(CFG.LOOT_SETTLE_TIME)
    local started = os.clock()
    local attempted = {}
    local collected = 0
    local emptySince=nil
    -- Keep the search centered on the original room, even after teleporting.
    local originRoot = getRoot()
    local lootOrigin = originRoot and originRoot.Position or nil
    if PRO.dungeonId=="dark" and lootOrigin then
        PRO.preLootPosition={position=lootOrigin,room=currentRoom,run=getDungeon(),time=os.clock()}
    end
    while validSession(id)
        and os.clock() - started < CFG.LOOT_TIMEOUT do
        local drops = getNearbyDrops(lootOrigin)
        local target = nil
-- Naechsten noch nicht versuchten Drop suchen
        for _, drop in ipairs(drops) do
            if (attempted[drop.model] or 0) < PRO.lootRetries then
                target = drop
                break
            end
        end
        if not target then
            emptySince=emptySince or os.clock()
            if os.clock()-emptySince>=PRO.lootQuiet then break end
            task.wait(0.15)
            continue
        end
        emptySince=nil
        attempted[target.model] = (attempted[target.model] or 0) + 1
        local character = getCharacter()
        local root = getRoot()
        if not character or not root then
            break
        end
        if not target.aura.Parent
            or not target.prompt.Parent then
            continue
        end
        local prompt = target.prompt
        local promptPart = prompt.Parent
        if promptPart and promptPart:IsA("Attachment") then
            promptPart=promptPart:FindFirstAncestorWhichIsA("BasePart")
        end
        if not promptPart or not promptPart:IsA("BasePart") then
            debugPrint("Prompt ohne BasePart")
            continue
        end
-- Direkt neben den Pickup-Handle teleportieren
        local position = promptPart.Position
        local destination = Vector3.new(
            position.X,
            position.Y + 2,
            position.Z
        )
        debugPrint(
            "Sammle Drop:",
            target.model:GetAttribute("wbId")
                or target.model.Name
        )
        statusLabel.Text = "Collecting item..."
        character:PivotTo(
            CFrame.new(destination)
        )
-- Auf Interaktionsreichweite warten
        local pickupReady = false
        local waitStarted = os.clock()
        while validSession(id)
            and os.clock() - waitStarted < 2 do
            local currentRoot = getRoot()
            if not currentRoot
                or not prompt.Parent
                or not target.model.Parent then
                break
            end
            local distance = (
                currentRoot.Position - promptPart.Position
            ).Magnitude
            if prompt.Enabled
                and distance <= prompt.MaxActivationDistance then
                pickupReady = true
                break
            end
            task.wait(0.1)
        end
        if not validSession(id) then
            break
        end
        if pickupReady then
            local ok, err = pcall(function()
                if type(fireproximityprompt) ~= "function" then
                    error(
                        "fireproximityprompt nicht verfuegbar"
                    )
                end
                fireproximityprompt(prompt)
            end)
            if not ok then
                warn(
                    "[DUNGEON V4] Pickup fehlgeschlagen:",
                    err
                )
            end
-- Auf Verarbeitung des Pickups warten
            task.wait(CFG.LOOT_PICKUP_WAIT)
            local confirmUntil=os.clock()+PRO.lootConfirmSeconds
            while validSession(id) and target.model.Parent and os.clock()<confirmUntil do
                task.wait(0.1)
            end
            if not target.model.Parent then
                collected = collected + 1
                PRO.lootObserved+=1
                debugPrint(
                    "Drop erfolgreich eingesammelt"
                )
            else
                debugPrint(
                    "Drop noch vorhanden:",
                    target.model.Name
                )
            end
        else
            debugPrint(
                "Pickup nicht bereit:",
                target.model.Name
            )
        end
    end
    debugPrint(
        "Loot-Phase beendet.",
        "Eingesammelt:",
        collected
    )
    statusLabel.Text = "Loot collection complete"
    return true
end

-- ============================================
-- UNIVERSAL AUTO REPLAY | EXECUTOR CAPABILITIES
-- ============================================
-- Detect the executor for diagnostics, but choose APIs by capability.
-- Executor names and APIs change between releases.
local function getExecutorInfo()
    local probes = {}
    if type(identifyexecutor) == "function" then
        table.insert(probes, identifyexecutor)
    end
    if type(getexecutorname) == "function" then
        table.insert(probes, getexecutorname)
    end
    for _, probe in ipairs(probes) do
        local ok, name, version = pcall(probe)
        if ok and type(name) == "string" and #name > 0 then
            return name, type(version) == "string" and version or ""
        end
    end
    return "Unknown", ""
end

local executorName, executorVersion = getExecutorInfo()
local executorNameLower = string.lower(executorName)
local function canUseNativeMouse()
    return type(mousemoveabs) == "function" and (
        type(mouse1click) == "function" or
        (type(mouse1press) == "function" and type(mouse1release) == "function")
    )
end

local function getNativeMouseFocus()
    local focusFn = nil
    if type(isrbxactive) == "function" then
        focusFn = isrbxactive
    elseif type(isgameactive) == "function" then
        focusFn = isgameactive
    elseif type(iswindowactive) == "function" then
        focusFn = iswindowactive
    end
    if focusFn then
        local ok, isActive = pcall(focusFn)
        if ok and isActive == false then
            return false
        end
    end
    return true
end

local function getReplayButton()
    local hud = playerGui:FindFirstChild("DungeonHud")
    local result = hud and hud:FindFirstChild("Result")
    local again = result and result:FindFirstChild("Again")
    if not again or not again:IsA("GuiButton") then
        return nil, "Run again button was not found"
    end
    if not again.Visible or not again.Active or not again.Interactable then
        return nil, "Run again button is not clickable"
    end
    return again, nil
end

-- ============================================
-- PRECISE REPLAY CLICK (Solara/desktop executors)
-- ============================================
-- Roblox AbsolutePosition is relative to CoreUISafeInsets. Native mouse
-- coordinates and UserInputService:GetMouseLocation() use screen pixels.
-- Add the top-left inset exactly once regardless of IgnoreGuiInset.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local function replayButtonCenter(again)
    local pos = again.AbsolutePosition
    local size = again.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return nil, nil, "Run again button is not on-screen"
    end
    local center = pos + size * 0.5
    local ok, inset = pcall(function()
        return GuiService:GetGuiInset()
    end)
    if not ok or typeof(inset) ~= "Vector2" then
        inset = Vector2.new(0, 0)
    end
    local x = math.floor(center.X + inset.X + 0.5)
    local y = math.floor(center.Y + inset.Y + 0.5)
    local camera = workspace.CurrentCamera
    if camera then
        local viewport = camera.ViewportSize
        if x < 0 or y < 0 or x >= viewport.X or y >= viewport.Y then
            return nil, nil, "Run again button is outside the viewport"
        end
    end
    return x, y, nil
end

local function readActualMouse()
    local ok, p = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if ok and typeof(p) == "Vector2" then
        return p
    end
    return nil
end

-- Move first, measure where the cursor actually landed, then correct any
-- window/inset offset BEFORE pressing. No probing clicks are performed.
local function moveToReplayCenter(x, y, again)
    local target = Vector2.new(x, y)
    local size = again.AbsoluteSize
    local toleranceX = math.max(5, math.min(16, size.X * 0.14))
    local toleranceY = math.max(5, math.min(16, size.Y * 0.14))

    mousemoveabs(x, y)
    task.wait(0.12)

    local last = readActualMouse()
    if not last then
        -- On executors where location cannot be read, preserve the normal
        -- native mouse behavior, but report that alignment was unverified.
        return true, "Mouse position unavailable; alignment unverified"
    end

    for step = 1, 3 do
        local dx = target.X - last.X
        local dy = target.Y - last.Y
        if math.abs(dx) <= toleranceX and math.abs(dy) <= toleranceY then
            return true, string.format(
                "Aligned at (%d,%d), target (%d,%d), correction steps %d",
                math.floor(last.X + 0.5), math.floor(last.Y + 0.5),
                x, y, step - 1
            )
        end

        if step == 3 then break end

        debugPrint(string.format(
            "Replay mouse offset: dx=%.1f dy=%.1f; adjusting",
            dx, dy
        ))
        local moved = pcall(function()
            if type(mousemoverel) == "function" then
                mousemoverel(math.floor(dx + (dx >= 0 and 0.5 or -0.5)),
                             math.floor(dy + (dy >= 0 and 0.5 or -0.5)))
            else
                -- Fallback if the executor only provides absolute movement.
                mousemoveabs(math.floor(x + dx + 0.5),
                             math.floor(y + dy + 0.5))
            end
        end)
        if not moved then
            return false, "Cursor correction API failed"
        end
        task.wait(0.12)
        local updated = readActualMouse()
        if not updated then
            return false, "Cursor location became unavailable"
        end
        last = updated
    end

    return false, string.format(
        "Cursor missed button center: target (%d,%d), actual (%d,%d)",
        x, y, math.floor(last.X + 0.5), math.floor(last.Y + 0.5)
    )
end

-- A single verified native press-and-release. Never spam clicks or retry
-- after input was dispatched, because each successful restart costs an item.
local function tryNativeMouseReplay(id, again)
    if not canUseNativeMouse() then
        return false, "Native mouse API not available"
    end
    if not getNativeMouseFocus() then
        return false, "Roblox is not the focused window"
    end

    local wasVisible = frame.Visible
    local pressed = false
    local inputStarted = false
    local movedDetails = "not attempted"
    local ok, err = pcall(function()
        frame.Visible = false
        task.wait(0.12)
        if not validSession(id) or not isDungeonComplete()
            or not again.Visible or not again.Interactable then
            error("Result screen changed before clicking")
        end

        -- Recalculate AFTER hiding the overlay, in case the GUI moved.
        local x, y, locationError = replayButtonCenter(again)
        if not x then error(locationError) end
        local aligned, details = moveToReplayCenter(x, y, again)
        movedDetails = details
        debugPrint("Replay cursor:", details)
        if not aligned then error(details) end

        if not validSession(id) or not isDungeonComplete()
            or not getNativeMouseFocus() then
            error("Replay stopped: result closed or window lost focus")
        end

        if type(mouse1press) == "function" and
            type(mouse1release) == "function" then
            mouse1press()
            inputStarted = true
            pressed = true
            task.wait(0.11)
            mouse1release()
            pressed = false
        else
            inputStarted = true
            mouse1click()
        end
        task.wait(0.15)
    end)

    if pressed then pcall(mouse1release) end
    frame.Visible = wasVisible and gui.Parent ~= nil

    if not ok then
        if inputStarted then
            return true, "Mouse input possibly sent: " .. tostring(err)
        end
        return false, "Mouse alignment/press failed: " .. tostring(err)
    end
    return true, "Single native click sent; " .. movedDetails
end

-- Direct signal activation for executors supporting firesignal.
-- This does not guarantee that game logic will accept a missing InputObject.
local function chooseReplaySignal(again)
    if type(getconnections) == "function" then
        local okA, activated = pcall(getconnections, again.Activated)
        local okM, clicked = pcall(getconnections, again.MouseButton1Click)
        if okA and type(activated) == "table" and #activated > 0 then
            return again.Activated, "Activated", activated
        end
        if okM and type(clicked) == "table" and #clicked > 0 then
            return again.MouseButton1Click, "MouseButton1Click", clicked
        end
    end
    return again.Activated, "Activated", nil
end

local function tryFireSignalReplay(_, again)
    if type(firesignal) ~= "function" then
        return false, "firesignal API not available"
    end
    local signal, eventName, listeners = chooseReplaySignal(again)
    if type(getconnections) == "function" and listeners == nil then
        -- If introspection works and reports no handlers for either event,
        -- use a real mouse action instead of treating an empty signal as success.
        local aOk, aList = pcall(getconnections, again.Activated)
        local mOk, mList = pcall(getconnections, again.MouseButton1Click)
        if aOk and mOk and type(aList) == "table" and type(mList) == "table"
            and #aList == 0 and #mList == 0 then
            return false, "No accessible replay button listeners"
        end
    end
    local ok, err = pcall(function()
        if eventName == "Activated" then
            firesignal(signal, nil, 0)
        else
            firesignal(signal)
        end
    end)
    if not ok then
        -- It is impossible to know whether any listener ran before the error.
        return true, "Signal dispatch may have partially succeeded: " .. tostring(err)
    end
    return true, "firesignal(" .. eventName .. ") dispatched"
end

-- Some executors have getconnections but no firesignal.
local function tryConnectionsReplay(_, again)
    if type(getconnections) ~= "function" then
        return false, "getconnections API not available"
    end
    local _, eventName, list = chooseReplaySignal(again)
    if type(list) ~= "table" or #list == 0 then
        return false, "No accessible button event connections"
    end
    local count = 0
    for _, conn in ipairs(list) do
        if conn.Enabled ~= false then
            local ok = pcall(function()
                if type(conn.Fire) == "function" then
                    if eventName == "Activated" then
                        conn:Fire(nil, 0)
                    else
                        conn:Fire()
                    end
                elseif type(conn.Function) == "function" then
                    if eventName == "Activated" then
                        conn.Function(nil, 0)
                    else
                        conn.Function()
                    end
                else
                    error("Unusable connection")
                end
            end)
            if ok then count = count + 1 end
        end
    end
    if count == 0 then
        return false, "Button connections could not be executed"
    end
    return true, "Fired " .. count .. " " .. eventName .. " connection(s)"
end

-- Last-resort API for runtimes which expose VirtualInputManager only.
-- This previously failed in some executors, so it is NOT the first choice.
local function tryVirtualInputReplay(id, again)
    local x, y, err = replayButtonCenter(again)
    if not x then return false, err end
    local okService, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if not okService or not vim then
        return false, "VirtualInputManager is unavailable"
    end
    local wasVisible = frame.Visible
    local inputStarted = false
    local ok, failure = pcall(function()
        frame.Visible = false
        task.wait(0.1)
        if not validSession(id) or not isDungeonComplete() then
            error("Result screen changed before clicking")
        end
        vim:SendMouseMoveEvent(x, y, game)
        task.wait(0.09)
        inputStarted = true
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.09)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        task.wait(0.1)
    end)
    frame.Visible = wasVisible and gui.Parent ~= nil
    if not ok then
        if inputStarted then
            return true, "VirtualInputManager may have sent input: " .. tostring(failure)
        end
        return false, "VirtualInputManager failed: " .. tostring(failure)
    end
    return true, "VirtualInputManager click dispatched"
end

local function replayMethodOrder()
    -- Name-based preference is only a hint; functionality is checked at call.
    -- Solara: native cursor. Potassium: fire signal first, then native cursor.
    -- Unknown executor: detect and use whichever API is available.
    if executorNameLower:find("potassium", 1, true) then
        -- Prefer the previously used Potassium signal API. The generic native
        -- mouse path can report input dispatched even when it missed the GUI.
        return { "signal", "native", "connections", "virtual" }
    elseif executorNameLower:find("solara", 1, true) then
        return { "native", "virtual", "signal", "connections" }
    end
    return { "native", "signal", "connections", "virtual" }
end

local replayMethods = {
    native = tryNativeMouseReplay,
    signal = tryFireSignalReplay,
    connections = tryConnectionsReplay,
    virtual = tryVirtualInputReplay,
}

local function printReplayCapabilities()
    local versionText = executorVersion ~= "" and (" " .. executorVersion) or ""
    debugPrint("Executor detected:", executorName .. versionText)
    debugPrint("Replay API:",
        "nativeMouse=" .. tostring(canUseNativeMouse()),
        "firesignal=" .. tostring(type(firesignal) == "function"),
        "getconnections=" .. tostring(type(getconnections) == "function"))
    debugPrint("Replay preference:", table.concat(replayMethodOrder(), " -> "))
end
printReplayCapabilities()

-- One actual activation attempt per endscreen. If an API call errors BEFORE
-- dispatching input, the next supported method is tried automatically.
-- If input might have been sent, we wait for the game or require manual replay.
local function attemptAutoReplay(id)
    if not validSession(id) or not isDungeonComplete() then
        return false, "Endscreen not ready"
    end
    local again, buttonError = getReplayButton()
    if not again then
        return false, buttonError
    end
    local failures = {}
    for _, method in ipairs(replayMethodOrder()) do
        if not validSession(id) or not isDungeonComplete() then
            return false, "Endscreen changed while choosing replay method"
        end
        local success, sent, reason = pcall(replayMethods[method], id, again)
        if success and sent then
            debugPrint("Auto Replay input dispatched by:", method, reason,
                "(not yet confirmed by dungeon)")
            return true, method .. ": " .. tostring(reason)
        end
        local failure = tostring(success and reason or sent)
        debugPrint("Auto Replay method skipped/failed:", method, failure)
        table.insert(failures, method .. "=" .. failure)
    end
    return false, "No usable method: " .. table.concat(failures, "; ")
end

local function startSpeedrun(id)
    debugPrint("Dungeon Speedrun started!")
    while validSession(id) do
        local reason=PRO.limitReason()
        if reason then
            onSpeedrunToggle(false)
            statusLabel.Text=reason
            break
        end
        local root, humanoid = getRoot(), getHumanoid()
        if not root or not humanoid or humanoid.Health <= 0 then
            statusLabel.Text = "Waiting for character / respawn"
            task.wait(0.5)
            continue
        end
        if PRO.dungeonId=="dark" then
            PRO.refreshDarkRoom()
            roomLabel.Text="Room: "..currentRoom.." / "..PRO.roomCount
        end
        -- Only confirmed room/wave/kill changes reset the stall clock, not attacks.
        local progress=tostring(currentRoom)..":"..tostring(currentWave)..":"..tostring(defeatedCount)
        if progress~=PRO.progressSignature then PRO.progressSignature=progress; PRO.lastProgressAt=os.clock() end
        if not isDungeonComplete() and PRO.stallSeconds>0 and os.clock()-PRO.lastProgressAt>PRO.stallSeconds then
            onSpeedrunToggle(false); statusLabel.Text="Parado: sem progresso confirmado. Gere o diagnóstico."; break
        end
        if PRO.healthFloor>0 and humanoid.MaxHealth>0 and humanoid.Health/humanoid.MaxHealth*100<PRO.healthFloor then
            stopMovement(); statusLabel.Text="Vida baixa: combate pausado (sem cura automática)"
            task.wait(0.5); continue
        end
        if PRO.dungeonId=="dark" and not getDungeon() and not isDungeonComplete() then
            onSpeedrunToggle(false); statusLabel.Text="Mapa Dark desapareceu: gere novo diagnóstico antes de reiniciar."; break
        end
        if isDungeonComplete() or waitingForRestart then
            if not waitingForRestart then
                if PRO.runStartedAt then
                    PRO.lastSeconds=os.clock()-PRO.runStartedAt
                    PRO.totalSeconds+=PRO.lastSeconds
                    PRO.bestSeconds=PRO.bestSeconds and math.min(PRO.bestSeconds,PRO.lastSeconds) or PRO.lastSeconds
                    PRO.finished+=1
                    completedRuns=PRO.finished
                    PRO.runStartedAt=nil
                end
                waitingForRestart = true
                restartRoomObserved = false
                stopMovement()
                clearTarget()
                replayAttempted = false
                replayAttemptAt = 0
                -- Scene exit might already have arrived; do not clear it here.
                statusLabel.Text = "Dungeon cleared - waiting for restart"
                debugPrint("Dungeon cleared; waiting for restart")
            end
            -- Collect any final boss drops before requesting another run.
            if not finalLootHandled then
                finalLootHandled = true
                collectDroppedItems(id)
            end
            local reason=PRO.limitReason()
            if reason then
                onSpeedrunToggle(false)
                statusLabel.Text=reason
                break
            end
            -- A Scene event confirms a restart. It never triggers one.
            -- Dispatch at most ONE input attempt; manual Run again stays available.
            local endscreenHiddenAt = nil
            local replayReady = false
            while validSession(id) do
                local completeScreenVisible = isDungeonComplete()
                local now = os.clock()
                local reason=PRO.limitReason()
                if reason then
                    onSpeedrunToggle(false)
                    statusLabel.Text=reason
                    break
                end

                if sceneEventsAvailable and sceneReplay.otherExit then
                    statusLabel.Text = "Dungeon exited without replay - stopped"
                    debugPrint("[SCENE] Left dungeon without Run again; stopping")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                if sceneEventsAvailable and sceneReplay.gate
                    and not completeScreenVisible then
                    replayReady = true
                    break
                end

                if not completeScreenVisible then
                    if not sceneEventsAvailable then
                        -- If the Scene listener cannot be installed, retain
                        -- the old endscreen-based fallback as a last resort.
                        task.wait(1)
                        replayReady = not isDungeonComplete()
                        break
                    end
                    endscreenHiddenAt = endscreenHiddenAt or now
                else
                    endscreenHiddenAt = nil
                end

                if completeScreenVisible and autoReplayEnabled
                    and not replayAttempted and not sceneReplay.exit then
                    replayAttempted = true
                    replayAttemptAt = os.clock()
                    local sent, reason = attemptAutoReplay(id)
                    debugPrint("Auto Replay attempt:", sent, reason)
                    if sent then
                        statusLabel.Text = "Replay input sent - awaiting Scene confirmation"
                    else
                        statusLabel.Text = "Auto Replay failed - click Run again"
                    end
                end

                -- Never automatically click again merely because Scene is slow.
                if replayAttempted and replayAttemptAt > 0
                    and not sceneReplay.exit
                    and now - replayAttemptAt >= CFG.REPLAY_CONFIRM_TIMEOUT then
                    statusLabel.Text = "Replay not confirmed - click Run again"
                    replayAttemptAt = 0
                end

                if sceneEventsAvailable and sceneReplay.exit
                    and not sceneReplay.gate
                    and now - sceneReplay.exitAt >= SCENE_RESTART_WAIT_SECONDS then
                    statusLabel.Text = "Restart received but gate not ready - stopped"
                    debugPrint("[SCENE] Timed out waiting for arrive/gate")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                if sceneEventsAvailable and endscreenHiddenAt
                    and not sceneReplay.gate
                    and now - endscreenHiddenAt >= SCENE_RESTART_WAIT_SECONDS then
                    statusLabel.Text = "Restart unconfirmed by Scene - stopped"
                    debugPrint("[SCENE] Endscreen vanished without confirmed gate")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                task.wait(0.2)
            end
            if not validSession(id) then break end
            if not replayReady then
                statusLabel.Text = "Replay was not confirmed"
                break
            end

            -- New dungeon confirmed by the server: exit -> arrive -> gate.
            -- Room 1 may already be reported by a notification.
            local roomAlreadyDetected = restartRoomObserved and currentRoom == 1
            local darkState
            if PRO.dungeonId=="dark" then
                local ok,reason=PRO.resolveDark()
                if not ok then onSpeedrunToggle(false); statusLabel.Text=reason; break end
                -- The listener already observed room/wave; keep it and its state.
                darkState={room=PRO.sceneRoom or currentRoom,wave=currentWave,
                    waves=totalWaves,cleared=roomCleared,unlocked=PRO.darkUnlocked}
                roomAlreadyDetected=true
            end
            PRO.lastProgressAt=os.clock()
            resetDungeonRun(roomAlreadyDetected)
            if darkState then
                currentRoom=darkState.room;PRO.sceneRoom=darkState.room
                currentWave=darkState.wave;totalWaves=darkState.waves
                roomCleared=darkState.cleared;PRO.darkUnlocked=darkState.unlocked
                PRO.preLootPosition=nil;PRO.nextDoorAttempt=nil
                PRO.log("Reinício Dark: automação retomada na sala "..tostring(currentRoom))
            end
            setButton(true)
            debugPrint("[SCENE] New dungeon confirmed; resuming")
            continue
        end
        if dismissLootPopup() then
            debugPrint("NEW LOOT bestaetigt")
        end
        if dungeonSafetyWatch() then
            task.wait(0.2)
            continue
        end
        local weapon = getWeapon()
        local humanoid = getHumanoid()
        if not weapon then
            statusLabel.Text = "Equip a weapon"
            task.wait(0.4)
        elseif not humanoid or humanoid.Health <= 0 then
            statusLabel.Text = "Character not ready"
            task.wait(0.4)
        elseif CFG.AUTO_ENTER_FIRST_ROOM and currentRoom == 0 then
            statusLabel.Text = "Entering dungeon..."
            enterFirstRoom(id)
            task.wait(0.5)
        elseif os.clock() < CFG.transitionUntil then
            statusLabel.Text = "Confirming room transition"
            task.wait(0.1)
        else
            local enemy = getNextEnemy()
            if enemy then
                fightEnemy(enemy, id)
            elseif waitingForDelayedRoomPopup() then
                statusLabel.Text = "Waiting for room confirmation..."
                task.wait(0.12)
            elseif currentRoom > 0 and currentRoom < PRO.roomCount and getOpenDoor() then
            if os.clock() - lastRoomAttempt
                >= CFG.ROOM_RETRY_DELAY then
                lastRoomAttempt = os.clock()
                local requestedRoom = currentRoom
-- Scan loot once per room, not again after an unconfirmed door.
                if lootCheckedRoom ~= currentRoom then
                    local scannedRoom = currentRoom
                    local scanned = collectDroppedItems(id)
                    if scanned and validSession(id) and currentRoom == scannedRoom then
                        lootCheckedRoom = scannedRoom
                    end
                else
                    debugPrint("Loot already checked for room", currentRoom,
                        "- skipping repeated scan")
                end
-- Then try crossing (never if the room changed while scanning).
                if validSession(id) and currentRoom == requestedRoom then
                    teleportThroughDoor(id)
                end
            end
                task.wait(0.2)
            else
                statusLabel.Text = "Waiting for enemies / door"
                task.wait(0.25)
            end
        end
        task.wait(0.03)
    end
    if sessionId == id then
        clearTarget()
        stopMovement()
        statusLabel.Text = "Speedrun stopped"
    end
    debugPrint("Dungeon Speedrun beendet")
end

-- ============================================
-- MAIN WORLD V5.9.0 | SINGLE NPC / SAME RESPAWN
-- ============================================
-- Deliberately no long-range route, area roaming, boss loop, target switching,
-- multi-spawn farm, global teleport watchdog, or UID-based player selection.
MW.dropOrigins={}
MW.dropAttempts={}
MW.lastWeaponAttempt=-1e12
MW.lockedSpawn=nil
MW.activeNPC=nil
MW.lastApproachedNPC=nil
MW.lastCombatWarning=0
MW.lastCombatLog=0

function MW.worldFarmValid(id)
    return MW.worldFarmRunning and MW.worldFarmSession==id
        and not running and gui.Parent~=nil
end

function MW.captureAreaMarkers()
    if not MW.validArea(MW.selectedArea) then
        warn("[WORLD][SINGLE] Select an area before capturing")
        return
    end
    local folder=workspace:FindFirstChild("Animal_SpawnPoints")
    local root=getRoot()
    if not root or not folder then return end
    local captured=0
    for _,part in ipairs(folder:GetChildren()) do
        local key=MW.markerKey(part)
        if key and horizontalDistance(root.Position,part.Position)<=115
            and math.abs(root.Position.Y-part.Position.Y)<=60 then
            MW.areaMarks[key]={area=MW.selectedArea,
                animal=part:GetAttribute("Animal"),x=part.Position.X,z=part.Position.Z}
            captured+=1
        end
    end
    if type(writefile)=="function" then
        local ok,err=pcall(function()
            writefile(MW.AREA_MAP_FILE,game:GetService("HttpService"):JSONEncode({
                version=1,marks=MW.areaMarks
            }))
        end)
        if not ok then warn("[WORLD][SINGLE] Cannot save map:",err) end
    end
    print("[WORLD][SINGLE] Captured",captured,"spawns for",MW.selectedArea)
    MW.refreshAreaEnemies()
end

function MW.refreshAreaEnemies()
    local names={}
    local folder=workspace:FindFirstChild("Animal_SpawnPoints")
    if folder and MW.validArea(MW.selectedArea) then
        for _,part in ipairs(folder:GetChildren()) do
            local key=MW.markerKey(part)
            local mark=key and MW.areaMarks[key]
            if mark and mark.area==MW.selectedArea then
                local animal=part:GetAttribute("Animal")
                if type(animal)=="string" then names[animal]=true end
            end
        end
    end
    local sorted={}
    for name in pairs(names) do table.insert(sorted,name) end
    table.sort(sorted)
    local options={}
    for _,name in ipairs(sorted) do
        table.insert(options,{Title=name,Value=name})
    end
    MW.worldUiRefreshing=true
    pcall(function() MW.enemyDropdown:Refresh(options,false) end)
    MW.worldUiRefreshing=false
    if #sorted==0 then
        MW.selectionInfo:SetContent("No mapped enemies for "..tostring(MW.selectedArea or "this area")..
            ". Stand there and use Capture Nearby Spawns, then select the enemy.")
    else
        MW.selectionInfo:SetContent("Area "..MW.selectedArea.." has "..#sorted..
            " enemy types. Select one and stand near the particular NPC to lock its spawn.")
    end
    print("[WORLD][SINGLE] Area",tostring(MW.selectedArea),"enemies",table.concat(sorted,", "))
end

function MW.lockNearestSpawn()
    local folder=workspace:FindFirstChild("Animal_SpawnPoints")
    local root=getRoot()
    if not folder or not root then return false end
    local possible={}
    for _,part in ipairs(folder:GetChildren()) do
        local key=MW.markerKey(part)
        local mark=key and MW.areaMarks[key]
        if mark and mark.area==MW.selectedArea
            and part:GetAttribute("Animal")==MW.selectedEnemyName then
            local d=horizontalDistance(root.Position,part.Position)
            if d<=65 then
                table.insert(possible,{part=part,distance=d,
                    marker=tostring(part:GetAttribute("_MarkerId") or "")})
            end
        end
    end
    if #possible==0 then
        MW.worldStatusLabel:SetValue("No mapped spawn within 65 studs: approach enemy / capture area")
        return false
    end
    -- Choose a LIVE matching spawn first, otherwise the nearest fixed spawn.
    local enemies=getEnemies()
    for _,slot in ipairs(possible) do
        slot.occupied=false
        if enemies then
            for _,npc in ipairs(enemies:GetChildren()) do
                if npc:IsA("Model") and npc:GetAttribute("Animal")==MW.selectedEnemyName then
                    local hp=npc:GetAttribute("Health")
                    local npcPos=enemyPosition(npc)
                    local marker=npc:GetAttribute("_SpawnMarkerId") or npc:GetAttribute("SpawnMarkerId")
                    if type(hp)=="number" and hp>0 and npcPos
                        and ((marker~=nil and slot.marker~="" and tostring(marker)==slot.marker)
                            or (horizontalDistance(npcPos,slot.part.Position)<=20
                                and math.abs(npcPos.Y-slot.part.Position.Y)<=18)) then
                        slot.occupied=true
                        break
                    end
                end
            end
        end
    end
    table.sort(possible,function(a,b)
        if a.occupied~=b.occupied then return a.occupied end
        return a.distance<b.distance
    end)
    local chosen=possible[1]
    MW.lockedSpawn={part=chosen.part,pos=chosen.part.Position,
        marker=chosen.marker,animal=MW.selectedEnemyName}
    MW.worldTargetLabel:SetValue(MW.selectedEnemyName.." | one spawn locked")
    print("[WORLD][SINGLE] LOCKED_SPAWN",MW.selectedArea,MW.selectedEnemyName,
        "distance",math.floor(chosen.distance),"alive",chosen.occupied,
        "marker",MW.lockedSpawn.marker)
    return true
end

function MW.isLockedNpc(npc)
    local slot=MW.lockedSpawn
    if not slot or not npc:IsA("Model") or npc:GetAttribute("Animal")~=slot.animal then
        return false
    end
    if not npc.Parent then return false end
    local id=npc:GetAttribute("_SpawnMarkerId") or npc:GetAttribute("SpawnMarkerId")
    if id~=nil and slot.marker~="" then
        return tostring(id)==slot.marker
    end
    local pos=enemyPosition(npc)
    return pos~=nil and horizontalDistance(pos,slot.pos)<=25
        and math.abs(pos.Y-slot.pos.Y)<=20
end

function MW.rotationNpc()
    local live=workspace:FindFirstChild("Animal_Live")
    local folder=live and live:FindFirstChild("Aggressors")
    local root=getRoot()
    local spawns=workspace:FindFirstChild("Animal_SpawnPoints")
    if not folder or not root or not spawns then return nil end
    local active=MW.activeNPC
    if active and active.Parent==folder and active:GetAttribute("Animal")==MW.selectedEnemyName then
        local hp=active:GetAttribute("Health")
        if type(hp)=="number" and hp>0 then return active end
    end
    local origin=MW.rotationOrigin or root.Position
    MW.rotationOrigin=origin
    local slots={}
    for _,part in ipairs(spawns:GetChildren()) do
        local key=MW.markerKey(part)
        local mark=key and MW.areaMarks[key]
        if mark and mark.area==MW.selectedArea
            and part:GetAttribute("Animal")==MW.selectedEnemyName
            and horizontalDistance(origin,part.Position)<=600 then
            table.insert(slots,{part=part,pos=part.Position,
                marker=tostring(part:GetAttribute("_MarkerId") or ""),animal=MW.selectedEnemyName})
        end
    end
    MW.rotationMappedSlots=#slots
    local best,bestSlot,bestDistance
    for _,npc in ipairs(folder:GetChildren()) do
        local hp=npc:IsA("Model") and npc:GetAttribute("Health")
        local pos=type(hp)=="number" and hp>0 and enemyPosition(npc) or nil
        if pos and npc:GetAttribute("Animal")==MW.selectedEnemyName
            and horizontalDistance(origin,pos)<=600
            and (MW.rotationBlocked[npc] or 0)<=os.clock() then
            local marker=npc:GetAttribute("_SpawnMarkerId") or npc:GetAttribute("SpawnMarkerId")
            for _,slot in ipairs(slots) do
                local matches
                if marker~=nil and slot.marker~="" then
                    matches=tostring(marker)==slot.marker
                else
                    matches=horizontalDistance(pos,slot.pos)<=25 and math.abs(pos.Y-slot.pos.Y)<=20
                end
                if matches then
                    if npc==MW.activeNPC then return npc end
                    local distance=horizontalDistance(root.Position,pos)
                    if not bestDistance or distance<bestDistance then
                        best,bestSlot,bestDistance=npc,slot,distance
                    end
                    break
                end
            end
        end
    end
    MW.activeNPC=best
    if best then
        MW.targetRetryAt=0
        MW.lockedSpawn=bestSlot
        MW.lastApproachedNPC=nil
        MW.worldTargetLabel:SetValue(MW.selectedEnemyName.." | rotação na região")
    end
    return best
end

function MW.currentNpc()
    if MW.rotateEnemies then return MW.rotationNpc() end
    local folder=getEnemies()
    if not folder then return nil end
    -- Keep the live instance until it dies: never switch NPCs mid-combat.
    if MW.activeNPC and MW.isLockedNpc(MW.activeNPC) then
        local hp=MW.activeNPC:GetAttribute("Health")
        if type(hp)=="number" and hp>0 then return MW.activeNPC end
    end
    MW.activeNPC=nil
    for _,npc in ipairs(folder:GetChildren()) do
        if MW.isLockedNpc(npc) then
            local hp=npc:GetAttribute("Health")
            if type(hp)=="number" and hp>0 then
                MW.activeNPC=npc
                return npc
            end
        end
    end
    return nil
end

function MW.equipWeapon()
    local equipped=getWeapon()
    if equipped then
        MW.preferredWeaponName=equipped.Name
        return equipped
    end
    if not MW.preferredWeaponName or os.clock()-MW.lastWeaponAttempt<0.7 then return nil end
    MW.lastWeaponAttempt=os.clock()
    local humanoid=getHumanoid()
    local bag=player:FindFirstChildOfClass("Backpack")
    local tool=bag and bag:FindFirstChild(MW.preferredWeaponName)
    if humanoid and tool and tool:IsA("Tool") then
        pcall(function() humanoid:EquipTool(tool) end)
    end
    return getWeapon()
end

function MW.groundAt(pos,npc)
    local char=getCharacter()
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local exclusions={}
    if char then table.insert(exclusions,char) end
    if npc then table.insert(exclusions,npc) end
    params.FilterDescendantsInstances=exclusions
    params.IgnoreWater=true
    local hit=workspace:Raycast(pos+Vector3.new(0,24,0),Vector3.new(0,-80,0),params)
    return hit and hit.Position or nil
end

-- This step is never a prerequisite for attempting Tool:Activate().
function MW.shortStep(npc,id)
    local root,hum=getRoot(),getHumanoid()
    local pos=enemyPosition(npc)
    if not root or not hum or not pos then return false end
    local flat=horizontalDistance(root.Position,pos)
    if flat>7 then return false end
    local from=root.Position
    local d=Vector3.new(pos.X-from.X,0,pos.Z-from.Z)
    if d.Magnitude<0.1 then d=Vector3.new(1,0,0) end
    local toward=d.Unit
    local sideways=Vector3.new(-toward.Z,0,toward.X)
    local direction=(flat>3.3) and toward or sideways
    local goal=from+direction*1.1
    local ground1,ground2=MW.groundAt(from,npc),MW.groundAt(goal,npc)
    if not ground1 or not ground2 or math.abs(ground1.Y-ground2.Y)>3.5 then
        return false
    end
    hum:MoveTo(goal)
    local deadline=os.clock()+1.0
    while MW.worldFarmValid(id) and os.clock()<deadline do
        task.wait(0.08)
        local current=getRoot()
        if not current then return false end
        local moved=horizontalDistance(current.Position,from)
        if moved>=0.55 and moved<5.0 then
            hum:MoveTo(current.Position)
            return true
        end
    end
    hum:MoveTo(root.Position)
    return false
end

-- Broad bounds can overlap empty space in meshes. Confirm with exact geometry.
function MW.regionalLandingClear(point,overlap)
    local size=Vector3.new(2,3,2)
    local parts=workspace:GetPartBoundsInBox(CFrame.new(point),size,overlap)
    local suspect=false
    for _,part in ipairs(parts) do if part.CanCollide then suspect=true;break end end
    if not suspect then return true end
    local probe=Instance.new("Part")
    probe.Name="NerfangelLandingProbe"
    probe.Size=size;probe.CFrame=CFrame.new(point)
    probe.Anchored=true;probe.Transparency=1
    probe.CanCollide=false;probe.CanTouch=false;probe.CanQuery=false
    probe.Parent=workspace
    local ok,exact=pcall(function() return workspace:GetPartsInPart(probe,overlap) end)
    probe:Destroy()
    if not ok then return false end
    for _,part in ipairs(exact) do if part.CanCollide then return false end end
    return true
end

-- Probe from above ledges; accept walkable top surfaces, not wall faces.
function MW.regionalGroundAt(probe,baseY,npc)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local excluded={}
    local char=getCharacter()
    local live=workspace:FindFirstChild("Animal_Live")
    if char then table.insert(excluded,char) end
    if live then table.insert(excluded,live) elseif npc then table.insert(excluded,npc) end
    params.FilterDescendantsInstances=excluded
    params.RespectCanCollide=true;params.IgnoreWater=true
    local from=Vector3.new(probe.X,baseY+40,probe.Z)
    local hit=workspace:Raycast(from,Vector3.new(0,-90,0),params)
    if not hit or hit.Normal.Y<0.65 then return nil end
    local landingY=hit.Position.Y+3.2
    if landingY-baseY>24 or baseY-landingY>20 then return nil end
    return hit.Position
end

-- Travel to distant regional targets in bounded, floor-checked steps.
function MW.regionalSteps(npc,id)
    local character=getCharacter()
    local deadline=os.clock()+35
    local steps=0
    while MW.worldFarmValid(id) and MW.rotateEnemies and MW.activeNPC==npc
        and getCharacter()==character and os.clock()<deadline and steps<30 do
        local root,hum=getRoot(),getHumanoid()
        local pos=enemyPosition(npc)
        local hp=npc.Parent and npc:GetAttribute("Health")
        if not root or not hum or hum.Health<=0 or not pos or type(hp)~="number" or hp<=0 then return false end
        local distance=horizontalDistance(root.Position,pos)
        local targetGround=tonumber(npc:GetAttribute("_GroundY"))
        local targetY=targetGround and targetGround+3.2 or pos.Y
        if distance<=30 and math.abs(root.Position.Y-targetY)<=8 then return true end
        local delta=Vector3.new(pos.X-root.Position.X,0,pos.Z-root.Position.Z)
        if delta.Magnitude<0.1 then delta=Vector3.new(1,0,0) end
        local forward=delta.Unit
        local side=Vector3.new(-forward.Z,0,forward.X)
        local overlap=OverlapParams.new()
        overlap.FilterType=Enum.RaycastFilterType.Exclude
        overlap.FilterDescendantsInstances={character,npc}
        overlap.RespectCanCollide=true
        local point
        -- Try shorter and lateral landing points instead of cancelling the target.
        for _,length in ipairs({20,12,6}) do
            for _,offset in ipairs({0,0.6,-0.6,1.2,-1.2}) do
                local direction=(forward+side*offset).Unit
                local probe=root.Position+direction*math.min(length,math.max(3,distance-5))
                local ground=MW.regionalGroundAt(probe,root.Position.Y,npc)
                if ground then
                    local candidate=Vector3.new(probe.X,ground.Y+3.2,probe.Z)
                    local newDistance=horizontalDistance(candidate,pos)
                    local heightImproved=math.abs(candidate.Y-targetY)<math.abs(root.Position.Y-targetY)-2
                    local makesProgress=newDistance<distance-1 or (newDistance<=distance+3 and heightImproved)
                    if makesProgress and (candidate-root.Position).Magnitude<=28 then
                        if MW.regionalLandingClear(candidate,overlap) then point=candidate;break end
                    end
                end
            end
            if point then break end
        end
        if not point then
            PRO.log("Farm XP: sem ponto intermediário livre; mantendo o mesmo alvo")
            return false
        end
        if not MW.worldFarmValid(id) or getCharacter()~=character then return false end
        hum:MoveTo(root.Position)
        local heightDelta=point.Y-root.Position.Y
        character:PivotTo(CFrame.lookAt(point,Vector3.new(pos.X,point.Y,pos.Z)))
        steps=steps+1
        if math.abs(heightDelta)>8 then
            PRO.log("Farm XP: desnível de "..math.floor(heightDelta).." studs; ponto superior/inferior validado")
        end
        local untilTime=os.clock()+(MW.regionalStepWait or 0.8)
        repeat
            task.wait(math.min(0.05,MW.regionalStepWait or 0.8))
            if not MW.worldFarmValid(id) or getCharacter()~=character then return false end
            root=getRoot()
            if not root or horizontalDistance(root.Position,point)>6 or math.abs(root.Position.Y-point.Y)>8 then
                PRO.log("Farm XP: passo "..steps.." revertido; viagem interrompida")
                return false
            end
        until os.clock()>=untilTime
    end
    return false
end

function MW.approachOnce(npc,id)
    if MW.rotateEnemies then
        if not MW.regionalSteps(npc,id) then return false end
    end
    local char,root,hum=getCharacter(),getRoot(),getHumanoid()
    local pos=enemyPosition(npc)
    if not char or not root or not hum or not pos then return false end
    local flat=horizontalDistance(root.Position,pos)
    if MW.lastApproachedNPC==npc then
        -- Never repeat teleports to the SAME living instance after rollback.
        if flat<=7 and not MW.rotateEnemies then MW.shortStep(npc,id) end
        return flat<=7
    end
    if flat>35 then
        MW.worldStatusLabel:SetValue("Move closer to locked NPC ("..math.floor(flat).." studs)")
        return false
    end
    MW.lastApproachedNPC=npc
    if flat>6 then
        -- One bounded teleport on acquisition of THIS respawn, never mid-combat.
        local outward=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
        if outward.Magnitude<0.1 then outward=Vector3.new(1,0,0) end
        outward=outward.Unit
        local dirs={outward,-outward,Vector3.new(-outward.Z,0,outward.X)}
        local feetGap=3
        local boxOk,boxCF,boxSize=pcall(function() return char:GetBoundingBox() end)
        if boxOk then feetGap=math.clamp(root.Position.Y-(boxCF.Position.Y-boxSize.Y/2),2,5) end
        local landed=false
        for _,dir in ipairs(dirs) do
            local destXZ=pos+dir*3.3
            local ground=MW.groundAt(destXZ,npc)
            if ground and math.abs(ground.Y-pos.Y)<=9 then
                local landing=Vector3.new(destXZ.X,ground.Y+feetGap+0.2,destXZ.Z)
                hum:MoveTo(root.Position)
                char:PivotTo(CFrame.lookAt(landing,Vector3.new(pos.X,landing.Y,pos.Z)))
                task.wait(0.25)
                root=getRoot()
                if root and horizontalDistance(root.Position,landing)<5.5 then
                    landed=true
                    break
                end
            end
        end
        if not landed then
            MW.worldStatusLabel:SetValue("No safe landing; approach enemy manually")
            return false
        end
    end
    -- Prefer genuine movement, but do NOT block the first attack if it is
    -- already within reach or movement cannot be confirmed (V5.7.0 bug).
    if not MW.rotateEnemies then MW.shortStep(npc,id) end
    return true
end

function MW.addLootOrigin(position)
    if not MW.worldAutoLoot or not position then return end
    table.insert(MW.dropOrigins,{pos=position,expiry=os.clock()+20})
    while #MW.dropOrigins>2 do table.remove(MW.dropOrigins,1) end
end

function MW.findLoot()
    if not MW.worldAutoLoot then return nil end
    local now=os.clock()
    for i=#MW.dropOrigins,1,-1 do
        if MW.dropOrigins[i].expiry<now then table.remove(MW.dropOrigins,i) end
    end
    if #MW.dropOrigins==0 then return nil end
    local folder=workspace:FindFirstChild("WorldBits")
    if not folder then return nil end
    local best,bestDist=nil,math.huge
    local root=getRoot()
    if not root then return nil end
    for _,drop in ipairs(folder:GetChildren()) do
        if (MW.dropAttempts[drop] or 0)<now then
            local prompt=drop:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and prompt.Enabled then
                local parent=prompt.Parent
                local part=parent and parent:FindFirstAncestorWhichIsA("BasePart")
                local pos=parent and ((parent:IsA("Attachment") and parent.WorldPosition)
                    or (parent:IsA("BasePart") and parent.Position)
                    or (part and part.Position))
                if pos then
                    for _,origin in ipairs(MW.dropOrigins) do
                        if (pos-origin.pos).Magnitude<=24 then
                            local dist=(root.Position-pos).Magnitude
                            if dist<bestDist then
                                best,bestDist={obj=drop,prompt=prompt,pos=pos},dist
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return best
end

function MW.collectLoot(id)
    local drop=MW.findLoot()
    if not drop then return false end
    local root,hum,char=getRoot(),getHumanoid(),getCharacter()
    if not root or not hum or not char then return false end
    local reach=math.max(1,drop.prompt.MaxActivationDistance)
    local dist=(root.Position-drop.pos).Magnitude
    if dist>reach*0.8 then
        if dist>22 then return false end
        -- Only local loot from THIS killed NPC: one bounded pickup movement.
        hum:MoveTo(root.Position)
        char:PivotTo(CFrame.new(drop.pos+Vector3.new(0,2.5,0)))
        task.wait(0.18)
    end
    root=getRoot()
    if not root or not drop.prompt.Parent or not drop.prompt.Enabled
        or (root.Position-drop.pos).Magnitude>reach then
        MW.dropAttempts[drop.obj]=os.clock()+1.1
        return true
    end
    local fired=false
    if type(fireproximityprompt)=="function" then
        fired=pcall(fireproximityprompt,drop.prompt)
    end
    if not fired then
        pcall(function() drop.prompt:InputHoldBegin() end)
        task.wait(math.max(0.08,math.min(1,drop.prompt.HoldDuration+0.10)))
        pcall(function() drop.prompt:InputHoldEnd() end)
    end
    local stop=os.clock()+0.7
    while MW.worldFarmValid(id) and os.clock()<stop do
        if not drop.obj.Parent or not drop.prompt.Parent or not drop.prompt.Enabled then
            debugPrint("[WORLD][SINGLE] LOOT_PICKED")
            MW.dropAttempts[drop.obj]=os.clock()+60
            return true
        end
        task.wait(0.08)
    end
    MW.dropAttempts[drop.obj]=os.clock()+1.0
    debugPrint("[WORLD][SINGLE] Loot attempted; not yet confirmed")
    return true
end

-- Boss drops can appear in staggered batches. Allow several pickup passes,
-- including a short no-drop window, instead of a fixed 2.1-second deadline.
-- This only uses the existing, origin-restricted MW.findLoot/collectLoot logic.
function MW.collectBossLootBurst(id)
    if not MW.worldAutoLoot then return end
    local started=os.clock()
    local maxDuration=15
    local minimumWindow=3.0
    local quietWindow=1.8
    local lastVisible=started
    local attempts=0
    while MW.worldFarmValid(id) and MW.worldAutoLoot and os.clock()-started<maxDuration do
        local drop=MW.findLoot()
        if drop then
            lastVisible=os.clock()
            attempts+=1
            MW.collectLoot(id)
            -- A fresh check is essential because another prompt may spawn
            -- after the previously collected one disappears.
            task.wait(0.10)
        else
            if os.clock()-started>=minimumWindow and
                os.clock()-lastVisible>=quietWindow then
                break
            end
            task.wait(0.12)
        end
    end
    print("[WORLD][BOSS] LOOT_BURST_FINISHED", "attempts",attempts,
        "elapsed",math.floor((os.clock()-started)*10)/10,
        "possibleRemaining",MW.findLoot()~=nil)
end

-- ================================
-- WORLD BOSS | VALIDATED LIVE SPAWN WATCHER
-- ================================
-- Real in-game diagnostics verified: Skullcrab has Animal="Skullcrab",
-- Tier="Boss", IsBoss=nil, and lives under Animal_Live.Aggressors.
-- Tier="Boss" is therefore authoritative even with no IsBoss flag.
-- Do NOT classify Tier="Huge" or other sizes as world bosses.
function MW.bossName(npc)
    local name=npc:GetAttribute("Animal") or npc:GetAttribute("BossName")
        or npc:GetAttribute("DisplayName")
    if type(name)=="string" and name~="" then
        return MW.canonicalBossName(name)
    end
    local raw=npc.Name
    if type(raw)=="string" and not raw:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x") then
        return MW.canonicalBossName(raw)
    end
    return nil
end

function MW.isVerifiedBoss(npc)
    if not npc or not npc:IsA("Model") then return false end
    -- Verified on a live Skullcrab: Tier="Boss" is the boss flag.
    -- NPCs have generated UIDs as model names, so use attributes.
    local tier = npc:GetAttribute("Tier")
    if type(tier) == "string" and tier:match("^%s*(.-)%s*$"):lower() == "boss" then
        return true
    end
    for _,key in ipairs({"IsBoss","Boss","_IsBoss","IsWorldBoss","WorldBoss"}) do
        local v=npc:GetAttribute(key)
        if v==true or v==1 or (type(v)=="string" and v:lower()=="true") then
            return true
        end
    end
    for _,key in ipairs({"NPCType","EnemyType","Category","Type"}) do
        local v=npc:GetAttribute(key)
        if type(v)=="string" and v:lower():find("boss",1,true) then return true end
    end
    local p=npc.Parent
    while p and p~=workspace do
        local folderName=p.Name:lower()
        if folderName=="bosses" or folderName=="worldbosses"
            or folderName=="world_bosses" or folderName=="boss_live" then
            return true
        end
        if folderName=="halloweendungeon_chain" then return false end
        p=p.Parent
    end
    return false
end

function MW.scanBossNPCs()
    local out,seen={},{}
    local live=workspace:FindFirstChild("Animal_Live")
    local containers={}
    for _,folder in ipairs({"Aggressors","Bosses","WorldBosses"}) do
        local candidate=live and live:FindFirstChild(folder)
        if candidate then table.insert(containers,candidate) end
    end
    for _,folder in ipairs({"Bosses","WorldBosses","World_Bosses"}) do
        local candidate=workspace:FindFirstChild(folder)
        if candidate then table.insert(containers,candidate) end
    end
    for _,container in ipairs(containers) do
        if container then
            for _,inst in ipairs(container:GetDescendants()) do
                if inst:IsA("Model") and not seen[inst] and MW.isVerifiedBoss(inst) then
                    local hp=inst:GetAttribute("Health")
                    if type(hp)=="number" and hp>0 and enemyPosition(inst) then
                        seen[inst]=true
                        table.insert(out,inst)
                    end
                end
            end
            -- GetDescendants excludes the container itself (rare model container).
            if container:IsA("Model") and not seen[container]
                and MW.isVerifiedBoss(container) then
                local hp=container:GetAttribute("Health")
                if type(hp)=="number" and hp>0 and enemyPosition(container) then
                    seen[container]=true
                    table.insert(out,container)
                end
            end
        end
    end
    return out
end

function MW.refreshBossList(force)
    local names={}
    for _,npc in ipairs(MW.scanBossNPCs()) do
        local name=MW.bossName(npc)
        if name then MW.bossKnownLabels[name]=true end
    end
    -- Merge alternate names from NPCs and signs, also if cached earlier.
    local canonicalLabels={}
    for name in pairs(MW.bossKnownLabels) do
        local canonical=MW.canonicalBossName(name)
        if canonical then canonicalLabels[canonical]=true end
    end
    MW.bossKnownLabels=canonicalLabels
    for name in pairs(canonicalLabels) do table.insert(names,name) end
    table.sort(names)
    local signature=table.concat(names,"|")
    if not force and signature==MW.lastBossSignature then return end
    MW.lastBossSignature=signature
    local values={{Title="Any detected World Boss",Value="__any_boss"}}
    for _,name in ipairs(names) do
        table.insert(values,{Title=name,Value=name})
    end
    MW.bossUiRefreshing=true
    pcall(function() MW.bossDropdown:Refresh(values,false) end)
    MW.bossUiRefreshing=false
    print("[WORLD][BOSS] Verified boss names:",#names,
        #names>0 and signature or "none loaded; Any Boss still available")
end

function MW.availableBoss()
    if not MW.bossFarmEnabled or os.clock()<MW.bossRetryUntil then return nil end
    local now=os.clock()
    if now<MW.bossScanAt and MW.cachedBoss and MW.cachedBoss.Parent then
        local hp=MW.cachedBoss:GetAttribute("Health")
        if type(hp)=="number" and hp>0 then return MW.cachedBoss end
    end
    if now<MW.bossScanAt then return nil end
    MW.bossScanAt=now+0.6
    MW.cachedBoss=nil
    local root=getRoot()
    if not root then return nil end
    local best,bestDist=nil,math.huge
    local newName=false
    for _,npc in ipairs(MW.scanBossNPCs()) do
        local name=MW.bossName(npc)
        if name and not MW.bossKnownLabels[name] then
            MW.bossKnownLabels[name]=true
            newName=true
        end
        if (MW.selectedBossName=="__any_boss" or
            name==MW.canonicalBossName(MW.selectedBossName)) then
            local pos=enemyPosition(npc)
            if pos then
                local d=(pos-root.Position).Magnitude
                if d<bestDist then best,bestDist=npc,d end
            end
        end
    end
    if newName then task.defer(function() if gui.Parent then MW.refreshBossList() end end) end
    -- The standalone single-spot build has no proven safe cross-map travel.
    -- Never seize movement control for a faraway boss and deadlock local farming.
    if best and bestDist>38 then
        if now>MW.lastBossRangeWarning+9 then
            MW.lastBossRangeWarning=now
            MW.bossStatusLabel:SetValue("Boss spawned, "..math.floor(bestDist).." studs away (approach area)")
            print("[WORLD][BOSS] SPAWN_OUT_OF_LOCAL_RANGE",MW.bossName(best),math.floor(bestDist))
        end
        return nil
    end
    MW.cachedBoss=best
    return best
end

function MW.bossApproach(npc,id)
    local root,hum,char=getRoot(),getHumanoid(),getCharacter()
    local pos=enemyPosition(npc)
    if not root or not hum or not char or not pos then return false end
    local dist=horizontalDistance(root.Position,pos)
    if dist>38 then return false end
    if dist>6 then
        local away=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
        if away.Magnitude<0.1 then away=Vector3.new(1,0,0) end
        local dirs={away.Unit,-away.Unit,Vector3.new(-away.Unit.Z,0,away.Unit.X)}
        local boxOk,boxCF,boxSize=pcall(function() return char:GetBoundingBox() end)
        local feetGap=3
        if boxOk then feetGap=math.clamp(root.Position.Y-(boxCF.Position.Y-boxSize.Y/2),2,5) end
        local arrived=false
        for _,dir in ipairs(dirs) do
            local landXZ=pos+dir*3.3
            local ground=MW.groundAt(landXZ,npc)
            if ground and math.abs(ground.Y-pos.Y)<=10 then
                local land=Vector3.new(landXZ.X,ground.Y+feetGap+0.2,landXZ.Z)
                hum:MoveTo(root.Position)
                char:PivotTo(CFrame.lookAt(land,Vector3.new(pos.X,land.Y,pos.Z)))
                task.wait(0.30)
                root=getRoot()
                if root and horizontalDistance(root.Position,pos)<7 then
                    arrived=true
                    break
                end
            end
        end
        if not arrived then return false end
    end
    MW.shortStep(npc,id)
    return true
end

function MW.returnToLockedSpawn()
    local char,root,hum=getCharacter(),getRoot(),getHumanoid()
    local spawn=MW.lockedSpawn
    if not spawn or not root or not char or not hum then return false end
    local distance=horizontalDistance(root.Position,spawn.pos)
    if distance<=8 then return true end
    -- The local boss mode intentionally avoids unverified cross-map travel.
    if distance>38 then
        MW.worldStatusLabel:SetValue("Boss done; move back to locked enemy spawn ("..math.floor(distance).." studs)")
        print("[WORLD][BOSS] RETURN_TOO_FAR",math.floor(distance))
        return false
    end
    local point=spawn.pos+Vector3.new(3.0,0,0)
    local ground=MW.groundAt(point,nil)
    if not ground then return false end
    local ok,cf,size=pcall(function() return char:GetBoundingBox() end)
    local foot=3
    if ok then foot=math.clamp(root.Position.Y-(cf.Position.Y-size.Y/2),2,5) end
    local dest=Vector3.new(point.X,ground.Y+foot+0.2,point.Z)
    hum:MoveTo(root.Position)
    char:PivotTo(CFrame.new(dest))
    task.wait(0.28)
    local newRoot=getRoot()
    local arrived=newRoot and horizontalDistance(newRoot.Position,spawn.pos)<10
    if not arrived then print("[WORLD][BOSS] RETURN_ROLLBACK_OR_BLOCKED") end
    return arrived==true
end

function MW.fightBoss(npc,id)
    if not MW.worldFarmValid(id) or not MW.bossFarmEnabled then return false end
    local name=MW.bossName(npc) or "Boss"
    MW.bossStatusLabel:SetValue("Fighting "..name.." – normal farm paused")
    print("[WORLD][BOSS] PRIORITY_START",name)
    if not MW.bossApproach(npc,id) then
        MW.bossStatusLabel:SetValue("Boss unreachable; retry after cooldown")
        MW.bossRetryUntil=os.clock()+5
        print("[WORLD][BOSS] APPROACH_FAILED",name)
        return false
    end
    local startHp=npc:GetAttribute("Health")
    if type(startHp)~="number" or startHp<=0 then return false end
    local prevHp=startHp
    local lastHit=os.clock()
    local nextAttack=0
    local nextMove=0
    local attacks=0
    local hitCount=0
    local lastPos=enemyPosition(npc)
    -- Knockback recovery is strictly for boss combat; the single enemy farm is unchanged.
    local recoverSince=nil
    local recoverBestDistance=math.huge
    local recoverProgressAt=0
    local recoverLastLog=0
    while MW.worldFarmValid(id) and MW.bossFarmEnabled and MW.bossActive do
        local hp=npc.Parent and npc:GetAttribute("Health") or 0
        if type(hp)~="number" or hp<=0 then
            if attacks>0 or hitCount>0 then
                MW.bossKills+=1
                MW.bossKillsLabel:SetValue(tostring(MW.bossKills))
                local now=os.clock()
                MW.lastBossKillAt=now
                MW.addLootOrigin(lastPos)
                print("[WORLD][BOSS] KILL_CONFIRMED",name,"loot priority")
                MW.bossStatusLabel:SetValue("Boss defeated; collecting boss loot")
                MW.collectBossLootBurst(id)
                MW.bossRetryUntil=os.clock()+1.4
                MW.bossStatusLabel:SetValue("Boss defeated; waiting for next spawn")
                return true
            end
            return false
        end
        if hp<prevHp then
            hitCount+=1
            lastHit=os.clock()
            print("[WORLD][BOSS] TRUE_HIT",name,math.floor(prevHp),math.floor(hp))
        end
        prevHp=hp
        local pos=enemyPosition(npc)
        local root,hum=getRoot(),getHumanoid()
        if not pos or not root or not hum then return false end
        lastPos=pos
        local flat=horizontalDistance(root.Position,pos)
        local vert=math.abs(root.Position.Y-pos.Y)
        if flat>5.5 or vert>8 then
            if flat>17 or vert>17 then
                -- A boss knockback can push the character beyond the old 17-stud
                -- chase range. Reissue MoveTo towards the CURRENT boss position,
                -- not a stale point from before the knockback.
                local now=os.clock()
                if not recoverSince then
                    recoverSince=now
                    recoverProgressAt=now
                    recoverBestDistance=flat
                    MW.bossStatusLabel:SetValue("Recovering from boss knockback ("..math.floor(flat).." studs)")
                    print("[WORLD][BOSS] KNOCKBACK_RECOVER_START",name,math.floor(flat))
                end
                if flat<recoverBestDistance-2 then
                    recoverBestDistance=flat
                    recoverProgressAt=now
                end
                if now>=nextMove then
                    local diff=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                    if diff.Magnitude<0.1 then diff=Vector3.new(1,0,0) end
                    local dest=pos+diff.Unit*3
                    hum:MoveTo(Vector3.new(dest.X,root.Position.Y,dest.Z))
                    nextMove=now+0.45
                end
                if now-recoverLastLog>=3 then
                    recoverLastLog=now
                    print("[WORLD][BOSS] KNOCKBACK_RECOVER",name,"distance",math.floor(flat),
                        "best",math.floor(recoverBestDistance),"noProgress",math.floor(now-recoverProgressAt))
                end
                -- Do not hold an encounter indefinitely when the player is
                -- displaced and normal Humanoid movement cannot recover.
                if now-recoverProgressAt>7 or now-recoverSince>18 then
                    hum:MoveTo(root.Position)
                    MW.bossRetryUntil=now+5
                    MW.bossStatusLabel:SetValue("Boss recovery stuck; move closer and retry")
                    warn("[WORLD][BOSS] KNOCKBACK_RECOVER_STUCK",name,"distance",math.floor(flat))
                    return false
                end
            elseif os.clock()>=nextMove then
                if recoverSince then
                    print("[WORLD][BOSS] KNOCKBACK_RECOVER_CLOSE",name,math.floor(flat))
                    recoverSince=nil
                    recoverBestDistance=math.huge
                end
                local diff=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                if diff.Magnitude<0.1 then diff=Vector3.new(1,0,0) end
                local dest=pos+diff.Unit*2.4
                hum:MoveTo(Vector3.new(dest.X,root.Position.Y,dest.Z))
                nextMove=os.clock()+0.5
            end
        else
            if recoverSince then
                print("[WORLD][BOSS] KNOCKBACK_RECOVER_DONE",name)
                recoverSince=nil
                recoverBestDistance=math.huge
            end
            if os.clock()>=nextAttack then
                local tool=MW.equipWeapon()
                if tool then
                    local ok,err=pcall(function() tool:Activate() end)
                    MW.worldAttacks+=1
                    MW.worldAttackLabel:SetValue(tostring(MW.worldAttacks))
                    nextAttack=os.clock()+0.65
                    attacks+=1
                    if not ok then warn("[WORLD][BOSS] Attack error",err) end
                end
            end
            if os.clock()-lastHit>2.7 and os.clock()>=nextMove then
                MW.shortStep(npc,id)
                nextMove=os.clock()+1.1
            end
        end
        -- Priority contract: once combat with a spawned boss begins, the
        -- normal farm stays paused until the boss dies/disappears or the
        -- user disables Boss Farm. Never classify missing damage as a kill.
        if os.clock()-lastHit>24 and os.clock()>=MW.nextBossStallWarning then
            MW.nextBossStallWarning=os.clock()+12
            MW.bossStatusLabel:SetValue("Boss active; waiting for registered hits")
            warn("[WORLD][BOSS] NO_HP_CHANGE; boss still has priority",name,
                "distance",math.floor(flat))
        end
        task.wait(0.1)
    end
    return false
end

function MW.fight(npc,id)
    if not MW.worldFarmValid(id) or not npc or not npc.Parent then return end
    -- ONE fixed NPC instance per respawn. No target rotation and no combat re-teleport.
    MW.worldStatusLabel:SetValue("Fighting "..MW.selectedEnemyName..(MW.rotateEnemies and " (rotação XP)" or " (one spawn)"))
    if MW.rotateEnemies and os.clock()<(MW.targetRetryAt or 0) then
        task.wait(0.2);return
    end
    if not MW.approachOnce(npc,id) then
        if MW.rotateEnemies then
            MW.targetRetryAt=os.clock()+3
            MW.lastApproachedNPC=nil
            MW.worldStatusLabel:SetValue("Aproximação pausada — mantendo o mesmo alvo")
        end
        task.wait(0.35)
        return
    end
    local hp0=npc:GetAttribute("Health")
    if type(hp0)~="number" or hp0<=0 then return end
    local prevHp=hp0
    local lastHit=os.clock()
    local nextAttack=0
    local nextMove=0
    local hits=0
    local attacks=0
    while MW.worldFarmValid(id) and MW.activeNPC==npc do
        if MW.bossFarmEnabled and MW.availableBoss() then
            MW.bossActive=true
            MW.lastApproachedNPC=nil
            print("[WORLD][BOSS] PREEMPT_SINGLE_ENEMY")
            return
        end
        local hp=npc.Parent and npc:GetAttribute("Health") or 0
        if type(hp)~="number" or hp<=0 then
            if hits>0 or attacks>0 then
                MW.worldDefeated+=1
                MW.worldKillsLabel:SetValue(tostring(MW.worldDefeated))
                MW.addLootOrigin(enemyPosition(npc) or MW.lockedSpawn.pos)
                debugPrint("[WORLD][SINGLE] KILL confirmed; collecting loot before respawn")
                local untilTime=os.clock()+((MW.rotateEnemies and not MW.worldAutoLoot) and 0 or 1.5)
                while MW.worldFarmValid(id) and os.clock()<untilTime do
                    if not MW.collectLoot(id) then task.wait(0.12) end
                end
            end
            return
        end
        if hp<prevHp then
            hits+=1
            lastHit=os.clock()
            debugPrint("[WORLD][SINGLE] TRUE_HIT",math.floor(prevHp),math.floor(hp))
        end
        prevHp=hp
        local root=getRoot()
        local pos=enemyPosition(npc)
        local hum=getHumanoid()
        if not root or not pos or not hum or hum.Health<=0 then return end
        local flat=horizontalDistance(root.Position,pos)
        local vert=math.abs(root.Position.Y-pos.Y)
        if not MW.rotateEnemies and MW.worldAutoLoot and MW.findLoot() then
            MW.collectLoot(id)
            root=getRoot()
            if not root then return end
            flat=horizontalDistance(root.Position,pos)
            vert=math.abs(root.Position.Y-pos.Y)
        end
        if MW.rotateEnemies and (flat>16 or vert>16) then
            MW.targetRetryAt=os.clock()+3
            MW.lastApproachedNPC=nil
            hum:MoveTo(root.Position)
            PRO.log("Farm XP: posição perdida; alvo="..npc.Name.." distancia="..math.floor(flat).." altura="..math.floor(vert).." HP="..math.floor(hp).." — mantendo alvo")
            return
        end
        -- Never teleport again while fighting this NPC. Recover knockback by walking.
        if (flat>5.5 or vert>8) and os.clock()>=nextMove then
            if flat<=16 and vert<=16 then
                local delta=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                if delta.Magnitude<0.1 then delta=Vector3.new(1,0,0) end
                local goal=pos+delta.Unit*2.3
                hum:MoveTo(Vector3.new(goal.X,root.Position.Y,goal.Z))
            else
                MW.worldStatusLabel:SetValue("Locked enemy too far; move closer ("..math.floor(flat)..")")
            end
            nextMove=os.clock()+0.55
        elseif flat<=5.5 and vert<=8 then
            -- Tool activation is never blocked by an unconfirmed 1-stud step.
            if os.clock()>=nextAttack then
                local tool=MW.equipWeapon()
                if tool then
                    local ok,err=pcall(function() tool:Activate() end)
                    attacks+=1
                    MW.worldAttacks+=1
                    MW.worldAttackLabel:SetValue(tostring(MW.worldAttacks))
                    nextAttack=os.clock()+0.65
                    if attacks==1 or (not ok) then
                        debugPrint("[WORLD][SINGLE] ATTACK_REQUESTED",tool.Name,"ok",ok,tostring(err))
                    end
                elseif os.clock()-MW.lastCombatWarning>3 then
                    MW.lastCombatWarning=os.clock()
                    warn("[WORLD][SINGLE] No equipped weapon. Equip weapon manually.")
                end
            end
            -- Only micro-adjust locally; do not abandon or re-teleport this NPC.
            if os.clock()-lastHit>2.5 and os.clock()>=nextMove then
                MW.shortStep(npc,id)
                nextMove=os.clock()+1.5
            end
        end
        if MW.rotateEnemies and os.clock()-lastHit>15 then
            MW.targetRetryAt=os.clock()+3
            MW.lastApproachedNPC=nil
            MW.worldStatusLabel:SetValue("Sem dano confirmado — mantendo alvo para reposicionar")
            return
        end
        if os.clock()-MW.lastCombatLog>5 then
            MW.lastCombatLog=os.clock()
            debugPrint("[WORLD][SINGLE] LOCKED",MW.selectedEnemyName,
                "distance",math.floor(flat*10)/10,"height",math.floor(vert*10)/10,
                "HP",math.floor(hp),"attacks",attacks,"hits",hits)
        end
        task.wait(0.1)
    end
end

function MW.runFarm(id)
    print("[WORLD][CTRL] START", "enemy",MW.enemyFarmEnabled,"boss",MW.bossFarmEnabled)
    while MW.worldFarmValid(id) do
        local character,hum=getCharacter(),getHumanoid()
        if not character or not getRoot() or not hum or hum.Health<=0 then
            MW.lastApproachedNPC=nil;MW.activeNPC=nil
            task.wait(0.4)
            continue
        end
        if MW.farmCharacter~=character then
            MW.farmCharacter=character
            MW.lastApproachedNPC=nil;MW.activeNPC=nil
        end
        -- Boss has absolute movement/combat priority. There is only ONE
        -- controller coroutine, so normal and boss movement never overlap.
        local boss=MW.bossFarmEnabled and MW.availableBoss() or nil
        if boss then
            MW.bossActive=true
            MW.worldStatusLabel:SetValue("Paused for World Boss")
            local ok,err=pcall(MW.fightBoss,boss,id)
            if not ok then warn("[WORLD][BOSS] Encounter error",tostring(err)) end
            MW.bossActive=false
            MW.cachedBoss=nil
            MW.bossScanAt=0
            -- Enemy combat must reacquire its prior spawn after a boss fight.
            -- The old 'already approached this NPC' cache would otherwise
            -- prevent restarting after the boss moved the player away.
            MW.lastApproachedNPC=nil
            if MW.enemyFarmEnabled and MW.lockedSpawn then
                if not MW.rotateEnemies then MW.returnToLockedSpawn() end
                MW.worldStatusLabel:SetValue("Resuming single enemy farm")
            end
            task.wait(0.2)
        elseif MW.enemyFarmEnabled and MW.lockedSpawn then
            local current=MW.currentNpc()
            if MW.worldAutoLoot and (not MW.rotateEnemies or not current) and MW.findLoot() then
                MW.collectLoot(id)
            elseif current then
                if not MW.equipWeapon() then
                    MW.worldStatusLabel:SetValue("Equip combat weapon manually")
                    task.wait(0.35)
                else
                    local ok,err=pcall(MW.fight,current,id)
                    if not ok then warn("[WORLD][SINGLE] Fight exception",tostring(err)) end
                    task.wait(0.10)
                end
            else
                MW.worldStatusLabel:SetValue(MW.rotateEnemies and "Sem alvo disponível nos pontos mapeados — aguardando" or "Waiting for respawn at locked spawn")
                task.wait(0.25)
            end
        else
            task.wait(0.4)
        end
        -- The separate read-only sign watcher below provides the countdown.
        -- Live NPCs, not the sign text, continue to drive boss engagement.
    end
    print("[WORLD][CTRL] STOP")
end

function MW.stopWorldFarm()
    MW.enemyFarmEnabled=false
    MW.bossFarmEnabled=false
    MW.bossActive=false
    MW.worldFarmRunning=false
    MW.worldFarmMode=nil
    MW.worldFarmSession+=1
    MW.activeNPC=nil
    MW.lastApproachedNPC=nil
    MW.lockedSpawn=nil
    MW.cachedBoss=nil
    MW.dropOrigins={}
    if not MW.worldGuiSync then
        MW.worldGuiSync=true
        if MW.worldEnemiesModule:Get() then MW.worldEnemiesModule:Set(false) end
        if MW.bossModule:Get() then MW.bossModule:Set(false) end
        MW.worldGuiSync=false
    end
    MW.worldStatusLabel:SetValue("Stopped")
    MW.bossStatusLabel:SetValue("Boss farm off")
end

function MW.setWorldFarmMode(mode,enabled)
    if MW.worldGuiSync then return end
    if mode~="enemy" and mode~="boss" then return end
    local module=(mode=="enemy") and MW.worldEnemiesModule or MW.bossModule
    local function reject(message)
        if message then MW.worldStatusLabel:SetValue(message) end
        MW.worldGuiSync=true
        if module:Get() then module:Set(false) end
        MW.worldGuiSync=false
    end
    if enabled then
        if running and onSpeedrunToggle then onSpeedrunToggle(false) end
        if mode=="enemy" then
            if not MW.validArea(MW.selectedArea) or not MW.selectedEnemyName then
                reject("Select Area and Enemy first")
                return
            end
            if not MW.lockedSpawn then
                if not MW.lockNearestSpawn() then
                    reject("No matching spawn nearby; approach/capture area")
                    return
                end
            end
            MW.rotationOrigin=getRoot() and getRoot().Position or nil
            MW.rotationBlocked=setmetatable({},{__mode="k"})
            MW.enemyFarmEnabled=true
        else
            MW.bossFarmEnabled=true
            MW.bossRetryUntil=0
            MW.bossScanAt=0
            MW.bossStatusLabel:SetValue("Watching boss spawns; normal farm continues")
            MW.refreshBossList(false)
        end
    else
        if mode=="enemy" then
            MW.enemyFarmEnabled=false
            MW.activeNPC=nil
            MW.lastApproachedNPC=nil
            MW.lockedSpawn=nil
        else
            MW.bossFarmEnabled=false
            MW.bossActive=false
            MW.cachedBoss=nil
            MW.bossStatusLabel:SetValue("Boss farm off")
        end
    end
    if not MW.enemyFarmEnabled and not MW.bossFarmEnabled then
        MW.stopWorldFarm()
        return
    end
    if not MW.worldFarmRunning then
        MW.dropOrigins={}
        MW.dropAttempts={}
        MW.worldFarmSession+=1
        MW.worldFarmRunning=true
        local weapon=getWeapon()
        MW.preferredWeaponName=weapon and weapon.Name or MW.preferredWeaponName
        local id=MW.worldFarmSession
        task.spawn(function()
            local ok,err=pcall(MW.runFarm,id)
            if not ok then
                warn("[WORLD][CTRL] FARM_ERROR",tostring(err))
                if MW.worldFarmSession==id then MW.stopWorldFarm() end
            end
        end)
    end
end
MW.onWorldFarmToggle=function(mode,enabled)
    MW.setWorldFarmMode(mode,enabled)
end


task.spawn(function()
    task.wait(1)
    if gui.Parent then
        MW.refreshAreaEnemies()
        MW.discoverBossSigns(true)
        MW.refreshBossList(true)
        MW.showSelectedBossSignTimer()
    end
end)

-- Passive, read-only in-world respawn display. No travel, no attack, no event hooks.
task.spawn(function()
    while gui.Parent do
        local ok,err=pcall(function()
            MW.discoverBossSigns(false)
            MW.showSelectedBossSignTimer()
        end)
        if not ok then
            -- Keep the controller alive even if a streamed GUI element disappears.
            if CFG.DEBUG_MODE then warn("[WORLD][BOSS][SIGN] Read error:",tostring(err)) end
        end
        task.wait(1.0)
    end
end)

-- AN / AUS BUTTON

-- ============================================
onSpeedrunToggle = function(enabled)
    if enabled and MW.worldFarmRunning and MW.stopWorldFarm then
        MW.stopWorldFarm()
    end
    if enabled and selectedDungeonId ~= "halloween" and selectedDungeonId ~= "dark" then
        setButton(false)
        statusLabel.Text = "Select Halloween Dungeon before starting"
        return
    end
    if enabled and selectedDungeonId=="dark" then
        local ok,reason=PRO.resolveDark()
        if not ok then setButton(false); statusLabel.Text=reason; PRO.log(reason); return end
        PRO.rebindScene()
    end
    if running == enabled then return end
    running = enabled
    sessionId = sessionId + 1
    if running then
        local reason=PRO.limitReason()
        if reason then
            running=false
            setButton(false)
            statusLabel.Text=reason..". Use Zerar estatísticas para iniciar outra sessão."
            return
        end
        PRO.lastProgressAt=os.clock()
        PRO.progressSignature=nil
        PRO.activeStartedAt=PRO.activeStartedAt or os.clock()
        PRO.runStartedAt=not isDungeonComplete() and os.clock() or nil
        finalLootHandled=false
        dungeonComplete = false
        waitingForRestart = false
        replayAttempted = false
        replayAttemptAt = 0
        clearSceneReplay()
        skippedEnemies = {}
        usedDoors = {}
        lastRoomAttempt = 0
        lootCheckedRoom = nil
        approachRoom = nil
        approachDoor = nil
        approachDirection = nil
        clearPendingDoor()
        setButton(true)
        statusLabel.Text = "Speedrun started"
        local id = sessionId
        task.spawn(function()
            local ok, failure = xpcall(function() startSpeedrun(id) end, debug.traceback)
            if not ok then
                PRO.log("ERRO Dungeon: "..tostring(failure))
                warn("[POLY LOOT PERSONAL][Dungeon] " .. tostring(failure))
                if sessionId == id and gui.Parent then
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    clearPendingDoor()
                    pcall(stopMovement)
                    pcall(clearTarget)
                    statusLabel.Text = "Stopped after error: open F9 console for details"
                end
            end
        end)
    else
        clearPendingDoor()
        setButton(false)
        statusLabel.Text = "Speedrun stopped"
        stopMovement()
        clearTarget()
    end
end


-- Personal 2.0: session statistics, explicit limits and bounded collection.
local proTab=Window:Tab({Title="Sessão e limites",Icon="timer",Columns=1})
local proStats=proTab:Section({Title="Estatísticas desta sessão",Icon="chart-no-axes-column"})
PRO.labels={}
for _,key in ipairs({"Dungeons concluídas","Tempo da sessão","Tempo da dungeon atual","Última dungeon","Média das dungeons","Melhor tempo","Monstros derrotados","Drops removidos após coleta","Pedidos de venda","Unidades reduzidas no inventário"}) do
    PRO.labels[key]=proStats:Label({Text=key,Value="0"})
end
proStats:Paragraph({Title="Como os números são medidos",
    Content="Tempos incluem esperas e respawn. Drops contam quando o objeto desaparece após a coleta; vendas contam reduções observadas no inventário. Não são comprovantes do servidor. Estatísticas não são salvas entre execuções."})
local limits=proTab:Section({Title="Controle de repetição",Icon="repeat"})
limits:Slider({Title="Parar após quantas dungeons (0 = ilimitado)",Min=0,Max=100,Step=1,Default=0,
    Callback=function(v) PRO.maxRuns=math.clamp(math.floor(tonumber(v) or 0),0,100) end})
limits:Slider({Title="Tempo máximo em minutos (0 = ilimitado)",Min=0,Max=720,Step=5,Default=0,
    Callback=function(v) PRO.maxMinutes=math.clamp(tonumber(v) or 0,0,720) end})
limits:Paragraph({Title="Regras dos limites",Content="Rodadas: termina a coleta final antes de impedir o próximo reinício. Tempo: pede parada quando a rotina retoma o controle; uma ação em andamento pode terminar antes. O cronômetro inclui pausas desde o primeiro início."})
limits:Button({Title="Parar dungeon agora",Icon="square",Callback=function()
    if onSpeedrunToggle then onSpeedrunToggle(false) end
end})
limits:Button({Title="Zerar estatísticas e limites consumidos",Icon="rotate-ccw",Callback=function()
    if running or MW.worldFarmRunning or AS.busy then
        statusLabel.Text="Pare as automações antes de zerar as estatísticas"
        return
    end
    PRO.startedAt=os.clock(); PRO.activeStartedAt=nil; PRO.runStartedAt=nil
    PRO.finished=0; completedRuns=0; PRO.totalSeconds=0; PRO.lastSeconds=0
    PRO.bestSeconds=nil; PRO.kills=0; PRO.lootObserved=0
    PRO.saleRequests=0; PRO.salesObserved=0
end})
local lootControls=proTab:Section({Title="Coleta da dungeon",Icon="package"})
lootControls:Toggle({Title="Coletar itens na dungeon",Default=true,Callback=function(v) PRO.lootEnabled=v==true end})
lootControls:Slider({Title="Raio de busca",Min=20,Max=100,Step=5,Default=65,
    Callback=function(v) CFG.LOOT_SEARCH_RADIUS=math.clamp(tonumber(v) or 65,20,100) end})
lootControls:Slider({Title="Tempo máximo de coleta por sala (segundos)",Min=4,Max=25,Step=1,Default=8,
    Callback=function(v) CFG.LOOT_TIMEOUT=math.clamp(tonumber(v) or 8,4,25) end})
lootControls:Slider({Title="Tentativas por drop",Min=1,Max=5,Step=1,Default=3,
    Callback=function(v) PRO.lootRetries=math.clamp(math.floor(tonumber(v) or 3),1,5) end})
task.spawn(function()
    while gui.Parent do
        if running and PRO.stallSeconds>0 and not isDungeonComplete()
            and os.clock()-PRO.lastProgressAt>PRO.stallSeconds then
            onSpeedrunToggle(false)
            statusLabel.Text="Parado: sem progresso confirmado. Gere o diagnóstico."
        end
        if running and PRO.maxMinutes>0 and PRO.activeStartedAt
            and os.clock()-PRO.activeStartedAt>=PRO.maxMinutes*60 then
            onSpeedrunToggle(false)
            statusLabel.Text="Limite de tempo atingido"
        end
        local values={PRO.finished,PRO.duration(os.clock()-PRO.startedAt),
            PRO.runStartedAt and running and PRO.duration(os.clock()-PRO.runStartedAt) or "—",
            PRO.duration(PRO.lastSeconds),PRO.duration(PRO.finished>0 and PRO.totalSeconds/PRO.finished or 0),
            PRO.bestSeconds and PRO.duration(PRO.bestSeconds) or "—",PRO.kills,PRO.lootObserved,PRO.saleRequests,PRO.salesObserved}
        local keys={"Dungeons concluídas","Tempo da sessão","Tempo da dungeon atual","Última dungeon","Média das dungeons","Melhor tempo","Monstros derrotados","Drops removidos após coleta","Pedidos de venda","Unidades reduzidas no inventário"}
        for i,key in ipairs(keys) do
            local ok,err=pcall(function() PRO.labels[key]:SetValue(tostring(values[i])) end)
            if not ok then warn("[POLY LOOT PT][Estatísticas]",err) end
        end
        task.wait(1)
    end
end)

print("Poly Loot V6.0 OasisUI | Dungeon + Main World + Auto Sell loaded!")



-- Nerfangel controls are deliberately isolated from the gameplay functions.
do
    local tab=Window:Tab({Title="Nerfangel",Icon="settings",Columns=1})
    local identity=tab:Section({Title="Nerfangel Hub • V3 BETA",Icon="moon"})
    identity:Paragraph({Title="Halloween + Dark Dungeon experimental",
        Content="Halloween preserva a base v2. Dark depende da estrutura carregada no seu jogo: entrada manual, 10 salas previstas e verificação antes de iniciar. Não foi validada no Roblox."})
    identity:Button({Title="Parar todas as automações",Icon="square",Callback=function()
        onSpeedrunToggle(false)
        if MW.stopWorldFarm then MW.stopWorldFarm() end
        AS.enabled=false; AS.live=false
        PRO.log("Parada de todas as automações solicitada")
    end})
    identity:Slider({Title="Velocidade mínima até a porta (studs/s)",Min=16,Max=40,Step=2,Default=24,
        Description="Acelera apenas a aproximação e travessia. Depois restaura a velocidade anterior.",
        Callback=function(v) PRO.doorWalkSpeed=math.clamp(tonumber(v) or 24,16,40) end})
    identity:Slider({Title="Parar sem progresso por segundos (0 = desligado)",Min=0,Max=300,Step=10,Default=120,
        Callback=function(v) PRO.stallSeconds=math.clamp(tonumber(v) or 120,0,300) end})
    identity:Slider({Title="Pausar combate abaixo de vida % (0 = desligado)",Min=0,Max=70,Step=5,Default=0,
        Callback=function(v) PRO.healthFloor=math.clamp(tonumber(v) or 0,0,70) end})
    identity:Toggle({Title="Mostrar logs detalhados no F9",Default=true,
        Callback=function(v) CFG.DEBUG_MODE=v==true end})
    local diag=tab:Section({Title="Diagnóstico da Dark Dungeon",Icon="scan"})
    local diagLabel=diag:Label({Text="Resultado",Value="Entre manualmente na Dark e gere o relatório."})
    local function report()
        local lines={"NERFANGEL V3.15 DIAGNOSTICO", "PlaceId="..tostring(game.PlaceId),
            "Perfil="..tostring(PRO.dungeonId),"Sala="..currentRoom.."/"..PRO.roomCount,
            "Rodando="..tostring(running),"Scene="..tostring(sceneEventsAvailable)}
        local function add(value) if #lines<350 then table.insert(lines,tostring(value)) end end
        local runs=workspace:FindFirstChild("DungeonRuns")
        if runs then
            for runIndex,run in ipairs(runs:GetChildren()) do
                if runIndex>8 then break end
                add("RUN "..run:GetFullName())
                for _,room in ipairs(run:GetChildren()) do
                    if PRO.roomNumber(room.Name) then
                        local door=room:FindFirstChild("Door")
                        add("SAIDA "..room.Name.."="..(door and (door.ClassName.." "..door:GetFullName()) or "ausente"))
                    end
                end
                for key,value in pairs(run:GetAttributes()) do
                    if type(value)~="table" then add("ATRIBUTO RUN "..tostring(key).."="..tostring(value)) end
                end
                for _,room in ipairs(run:GetChildren()) do
                    if PRO.roomNumber(room.Name) then add("SALA DIRETA "..room:GetFullName()) end
                end
                local count=0
                for _,obj in ipairs(run:GetDescendants()) do
                    local lower=obj.Name:lower()
                    if (obj:IsA("BasePart") and (lower:find("door",1,true) or lower:find("gate",1,true)))
                        or obj:IsA("ProximityPrompt") then
                        add("PASSAGEM "..obj:GetFullName().." ["..obj.ClassName.."]"..
                            (obj:IsA("BasePart") and (" CanCollide="..tostring(obj.CanCollide)) or ""))
                        count=count+1; if count>=45 then break end
                    end
                end
            end
        end
        local live=workspace:FindFirstChild("Animal_Live")
        if live then
            for _,child in ipairs(live:GetChildren()) do add("PASTA NPC "..child:GetFullName().." ["..child.ClassName.."]") end
            local count=0
            for _,npc in ipairs(live:GetDescendants()) do
                if npc:IsA("Model") and npc:GetAttribute("Health")~=nil then
                    add("NPC REAL "..npc:GetFullName().." Health="..tostring(npc:GetAttribute("Health")))
                    for key,value in pairs(npc:GetAttributes()) do
                        if type(value)=="string" or type(value)=="number" then add("ATRIBUTO NPC "..key.."="..tostring(value):sub(1,90)) end
                    end
                    count=count+1;if count>=10 then break end
                end
            end
        end
        for _,parent in ipairs({workspace,game:GetService("ReplicatedStorage"),playerGui}) do
            for _,obj in ipairs(parent:GetChildren()) do
                local lower=obj.Name:lower()
                if lower:find("dungeon",1,true) or lower:find("dark",1,true)
                    or lower:find("animal",1,true) or lower:find("notifi",1,true) then
                    add(obj:GetFullName().." ["..obj.ClassName.."]")
                    for i,child in ipairs(obj:GetDescendants()) do
                        if i>300 then add("... limite de nós"); break end
                        if child:IsA("BasePart") and child.Name=="Door" then
                            add("PORTA "..child:GetFullName().." fechada="..tostring(child.CanCollide))
                        elseif child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                            add("EVENTO "..child:GetFullName())
                        elseif child:IsA("TextLabel") and child.Text~="" then
                            add("TEXTO "..child:GetFullName().."="..child.Text:sub(1,180))
                        elseif PRO.roomNumber(child.Name) then add("SALA "..child:GetFullName()) end
                    end
                end
            end
        end
        local enemies=getEnemies()
        if enemies then
            for i,npc in ipairs(enemies:GetChildren()) do
                if i>12 then break end
                add("NPC "..npc.Name.." Health="..tostring(npc:GetAttribute("Health")).." Animal="..tostring(npc:GetAttribute("Animal")))
            end
        end
        add("FARM alvo_fixo="..tostring(MW.activeNPC and MW.activeNPC.Name).." nova_tentativa="..string.format("%.1f",math.max(0,(MW.targetRetryAt or 0)-os.clock())))
        add("FARM mundo="..tostring(MW.worldFarmRunning).." inimigos="..tostring(MW.enemyFarmEnabled).." rotacao="..tostring(MW.rotateEnemies))
        add("FARM area="..tostring(MW.selectedArea).." especie="..tostring(MW.selectedEnemyName).." pontos_mapeados="..tostring(MW.rotationMappedSlots or 0))
        local farmRoot=getRoot()
        local live=workspace:FindFirstChild("Animal_Live")
        local aggressors=live and live:FindFirstChild("Aggressors")
        if farmRoot and aggressors then
            local count=0
            for _,npc in ipairs(aggressors:GetChildren()) do
                local hp=npc:GetAttribute("Health")
                local pos=npc:IsA("Model") and enemyPosition(npc)
                if pos and npc:GetAttribute("Animal")==MW.selectedEnemyName and type(hp)=="number" and hp>0 then
                    count=count+1
                    if count<=30 then add("ALVO XP "..npc.Name.." distancia="..math.floor(horizontalDistance(farmRoot.Position,pos)).." HP="..math.floor(hp).." bloqueado="..tostring((MW.rotationBlocked[npc] or 0)>os.clock())) end
                end
            end
            add("ALVOS XP vivos carregados="..count)
        end
        for _,line in ipairs(PRO.errors) do add(line) end
        local text=table.concat(lines,"\n")
        print(text)
        if type(setclipboard)=="function" then
            local ok=pcall(setclipboard,text)
            diagLabel:SetValue(ok and "Relatório copiado. Cole na conversa." or "Relatório no console F9.")
        else diagLabel:SetValue("Relatório no console F9; envie o texto ou print.") end
        return text
    end
    diag:Button({Title="Gerar e copiar diagnóstico",Icon="clipboard",Callback=function()
        local ok,err=pcall(report)
        if not ok then diagLabel:SetValue("Falha: "..tostring(err)); PRO.log(err) end
    end})
    diag:Button({Title="Verificar estrutura Dark (sem iniciar)",Icon="scan",Callback=function()
        if running then diagLabel:SetValue("Pare a dungeon antes de verificar o mapa."); return end
        local ok,result,reason=pcall(PRO.resolveDark)
        diagLabel:SetValue(ok and (result and "Estrutura compatível. Adaptador ainda exige teste no jogo." or tostring(reason)) or tostring(result))
    end})
end








