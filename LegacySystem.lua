--============================================================
-- LEGACY SYSTEM (Nivel 1) - Pontos por conta + NPC de gasto
--============================================================

local LEGACY_NPC = 400200

local POINT_SOURCES = {
    [776] = { key = "explore_elwynn",    points = 5 },
    [627] = { key = "explore_dunmorogh", points = 5 },
    [842] = { key = "explore_teldrassil", points = 5 },
    [728] = { key = "explore_durotar",   points = 5 },
    [736] = { key = "explore_mulgore",   points = 5 },
    [779] = { key = "explore_lochmodan", points = 5 },
}


local LEGACY_TREE = {
    { name = "Tradeskills", unlocks = {
        { key = "prof_eff_1", name = "Eficiencia de Coleta I (5 pts)",  cost = 5,  spellId = 0 },
        { key = "prof_eff_2", name = "Eficiencia de Coleta II (10 pts)", cost = 10, spellId = 0 },
    }},
    { name = "Adventure", unlocks = {
        { key = "rest_1", name = "Descanso Acelerado I (5 pts)", cost = 5, spellId = 0 },
    }},
}

local function GetPoints(accountId)
    local q = CharDBQuery("SELECT points FROM legacy_points WHERE accountId = " .. accountId)
    if q then
        return q:GetUInt32(0)
    end
    return 0
end

local function AddPoints(accountId, amount)
    CharDBExecute("INSERT INTO legacy_points (accountId, points) VALUES (" .. accountId .. ", " .. amount .. ") ON DUPLICATE KEY UPDATE points = points + " .. amount)
end

local function SpendPoints(accountId, amount)
    CharDBExecute("UPDATE legacy_points SET points = points - " .. amount .. " WHERE accountId = " .. accountId)
end

local function HasUnlock(accountId, key)
    local q = CharDBQuery("SELECT 1 FROM legacy_unlocks WHERE accountId = " .. accountId .. " AND unlockKey = '" .. key .. "'")
    return q ~= nil
end

local function GrantUnlock(accountId, key, spellId)
    CharDBExecute("INSERT IGNORE INTO legacy_unlocks (accountId, unlockKey, spellId) VALUES (" .. accountId .. ", '" .. key .. "', " .. spellId .. ")")
end

local function AlreadyLogged(accountId, sourceKey)
    local q = CharDBQuery("SELECT 1 FROM legacy_point_log WHERE accountId = " .. accountId .. " AND sourceKey = '" .. sourceKey .. "'")
    return q ~= nil
end

local function LogSource(accountId, sourceKey)
    CharDBExecute("INSERT IGNORE INTO legacy_point_log (accountId, sourceKey) VALUES (" .. accountId .. ", '" .. sourceKey .. "')")
end

local function ApplyAllUnlocks(player)
    local accountId = player:GetAccountId()
    local q = CharDBQuery("SELECT spellId FROM legacy_unlocks WHERE accountId = " .. accountId)
    if q then
        repeat
            local spellId = q:GetUInt32(0)
            if spellId > 0 and not player:HasSpell(spellId) then
                player:LearnSpell(spellId)
            end
        until not q:NextRow()
    end
end

local function OnAchievementEarned(event, player, achievementId)
    local source = POINT_SOURCES[achievementId]
    if not source then return end

    local accountId = player:GetAccountId()
    if AlreadyLogged(accountId, source.key) then return end

    AddPoints(accountId, source.points)
    LogSource(accountId, source.key)
    player:SendBroadcastMessage("|cFFFFD700[Legacy]|r Voce ganhou " .. source.points .. " Pontos Legacy!")
end

local function OnLogin(event, player)
    ApplyAllUnlocks(player)
end

RegisterPlayerEvent(3, OnLogin)
RegisterPlayerEvent(45, OnAchievementEarned)

-- Guarda por jogador (guidLow) qual categoria (indice numerico) ele esta vendo
local playerCategory = {}

local function OnGossipHello(event, player, creature)
    local accountId = player:GetAccountId()
    local points = GetPoints(accountId)

    creature:SendUnitSay("Voce tem " .. points .. " Pontos Legacy.", 0)

    player:GossipClearMenu()
    for i, category in ipairs(LEGACY_TREE) do
        -- intid = 1000 + i identifica "abrir categoria i"
        player:GossipMenuAddItem(0, category.name, 0, 1000 + i)
    end
    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code, menu_id)
    local accountId = player:GetAccountId()
    local guidLow = player:GetGUIDLow()

    if intid >= 1000 and intid < 2000 then
        -- Abrir categoria
        local catIndex = intid - 1000
        local category = LEGACY_TREE[catIndex]
        if not category then
            player:GossipComplete()
            return
        end

        playerCategory[guidLow] = catIndex

        player:GossipClearMenu()
        for i, unlock in ipairs(category.unlocks) do
            local owned = HasUnlock(accountId, unlock.key)
            local label = unlock.name .. (owned and " [Adquirido]" or "")
            -- intid = 2000 + i identifica "comprar unlock i da categoria atual"
            player:GossipMenuAddItem(0, label, 0, 2000 + i)
        end
        player:GossipMenuAddItem(0, "[Voltar]", 0, 1)
        player:GossipSendMenu(1, creature)

    elseif intid >= 2000 and intid < 3000 then
        -- Comprar unlock
        local catIndex = playerCategory[guidLow]
        local category = catIndex and LEGACY_TREE[catIndex]
        if not category then
            player:GossipComplete()
            return
        end

        local unlockIndex = intid - 2000
        local unlock = category.unlocks[unlockIndex]
        if not unlock then
            player:GossipComplete()
            return
        end

        local points = GetPoints(accountId)

        if HasUnlock(accountId, unlock.key) then
            player:SendBroadcastMessage("Voce ja possui isso.")
        elseif points < unlock.cost then
            player:SendBroadcastMessage("Pontos Legacy insuficientes.")
        elseif unlock.spellId == 0 then
            player:SendBroadcastMessage("Essa opcao ainda nao foi configurada pelo administrador.")
        else
            SpendPoints(accountId, unlock.cost)
            GrantUnlock(accountId, unlock.key, unlock.spellId)
            player:LearnSpell(unlock.spellId)
            player:SendBroadcastMessage("Desbloqueado: " .. unlock.name)
        end
        player:GossipComplete()

    elseif intid == 1 then
        -- Voltar para o menu principal
        OnGossipHello(event, player, creature)
    else
        player:GossipComplete()
    end
end

RegisterCreatureGossipEvent(LEGACY_NPC, 1, OnGossipHello)
RegisterCreatureGossipEvent(LEGACY_NPC, 2, OnGossipSelect)
