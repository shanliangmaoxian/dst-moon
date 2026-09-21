-- 小月亮 附魔掉落工具
-- 精英/Boss 死亡时按概率掉落附魔石
-- 两级 roll：先 roll 总掉率，命中则从池中加权随机选一个附魔石

local _G = GLOBAL

-- 总掉落概率（epic 死亡时掉任意附魔石的概率）
TUNING.MOON_ENCHANT_BASE_DROP_CHANCE = TUNING.MOON_ENCHANT_BASE_DROP_CHANCE or 0.005

-- 掉落池 {enchant_id = weight}
local POOL = {}

-- 注册附魔石到掉落池
-- @param enchant_id: 附魔石 ID
-- @param drop_weight: 权重 (0 表示不掉落，默认 1)
-- 档位覆盖：tier_config.lua 配了档位的附魔，权重以中央表
-- TUNING.MOON_ENCHANT_TIER_WEIGHTS[tier] 为准；未列入的沿用注册值
function _G.Moon_RegisterEnchantDrop(enchant_id, drop_weight)
    local weight = drop_weight
    if weight == nil then weight = 1 end
    local tier = TUNING.MOON_ENCHANT_TIERS and TUNING.MOON_ENCHANT_TIERS[enchant_id]
    if tier and TUNING.MOON_ENCHANT_TIER_WEIGHTS then
        local tier_weight = TUNING.MOON_ENCHANT_TIER_WEIGHTS[tier]
        if tier_weight then weight = tier_weight end
    end
    if weight <= 0 then
        POOL[enchant_id] = nil
    else
        POOL[enchant_id] = weight
    end
end

-- 加权随机从池中选一个
local function PickFromPool()
    local total = 0
    local entries = {}
    for id, weight in pairs(POOL) do
        total = total + weight
        entries[#entries + 1] = {id = id, weight = weight}
    end
    if total <= 0 or #entries == 0 then return nil end
    local roll = math.random() * total
    local cumulative = 0
    for _, entry in ipairs(entries) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.id
        end
    end
    return entries[#entries].id
end

-- 统一监听器（只注册一次）
AddPrefabPostInitAny(function(inst)
    if not GLOBAL.TheWorld.ismastersim then return end
    if not inst:HasTag("epic") then return end
    inst:ListenForEvent("death", function(inst, data)
        if math.random() > TUNING.MOON_ENCHANT_BASE_DROP_CHANCE then return end
        local enchant_id = PickFromPool()
        if not enchant_id then return end
        local stone = GLOBAL.HHSpawnStoneById(enchant_id)
        if stone then
            local pt = inst:GetPosition()
            local killer = data and data.afflicter
            if killer and killer:IsValid() and killer.components.inventory then
                killer.components.inventory:GiveItem(stone, nil, pt)
            else
                stone.Transform:SetPosition(pt:Get())
            end
        end
    end)
end)

-- 钢羊(spat)击杀掉落：3%概率掉落 Legend_LAOSHI 附魔石（需开启魔女之旅 Mod）
AddPrefabPostInit("spat", function(inst)
    if not GLOBAL.TheWorld.ismastersim then return end
    if not GLOBAL.Moon_IsModEnabled("workshop-2578692071") then return end
    inst:ListenForEvent("death", function(inst, data)
        if math.random() > 0.03 then return end
        local stone = GLOBAL.HHSpawnStoneById("Legend_LAOSHI")
        if stone then
            local pt = inst:GetPosition()
            stone.Transform:SetPosition(pt:Get())
        end
    end)
end)

-- 击杀蝴蝶(butterfly)掉落：0.1%概率掉落 小蝴蝶/小阿飞 附魔石之一
AddPrefabPostInit("butterfly", function(inst)
    if not GLOBAL.TheWorld.ismastersim then return end
    if not GLOBAL.MOON_CFG or not GLOBAL.MOON_CFG.ENABLE_MORE_ENCHANTS then return end
    if not GLOBAL.Moon_IsHHEnabled or not GLOBAL.Moon_IsHHEnabled() then return end
    inst:ListenForEvent("death", function(inst, data)
        if math.random() > 0.001 then return end
        local enchant_id = math.random(2) == 1 and "Legend_XIAOHUDIE" or "Legend_HUFEI"
        local stone = GLOBAL.HHSpawnStoneById(enchant_id)
        if stone then
            local pt = inst:GetPosition()
            local killer = data and data.afflicter
            if killer and killer:IsValid() and killer.components.inventory then
                killer.components.inventory:GiveItem(stone, nil, pt)
            else
                stone.Transform:SetPosition(pt:Get())
            end
        end
    end)
end)

-- =========================================================
-- 使用时长掉落：装备佩戴指定附魔满 N 秒 → 掉落一枚该附魔石
-- mode="continuous"：按物品连续佩戴计时，仅在"被佩戴"时计时；
--                    摘下即取消并清零（摘掉就重新计数）；计满清零可循环获取
-- mode="total"：佩戴期间累计总时长（跨摘戴累计、随玩家存档保存），
--               计满后单人单档（按 userid）仅可获取一次
-- =========================================================
local USE_TIME_DROPS = {
    -- 附魔id = { time = 需要秒数, name = 附魔名, mode = 计时模式, msg = 获取飘字 }
    ["Legend_YUFENFEN"] = {
        time = 2400, name = "雨纷纷", mode = "continuous",
        msg = "这把伞陪你走过了一场又一场雨…",
    }, -- 同一把伞连续使用满 2400 秒（游戏内40分钟）
    ["Legend_WYWQ"] = {
        time = 1200, name = "无欲无求", mode = "total",
        msg = "心如止水，宠辱不惊…",
    }, -- 挂机（禅定）累计满 1200 秒（游戏内20分钟），单人单档一次
}

-- 检查物品是否带有指定附魔（HH equip_buff_list: {name=附魔id, value=数值}）
local function ItemHasEnchant(item, enchant_id)
    local eq = item and item.components and item.components.hh_equip
    local list = eq and eq.equip_buff_list
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do
        if type(v) == "table" and v.name == enchant_id then
            return true
        end
    end
    return false
end

local function GiveEnchantStone(owner, enchant_id)
    local cfg = USE_TIME_DROPS[enchant_id]
    local ok, stone = _G.pcall(_G.HHSpawnStoneById, enchant_id)
    if not (ok and stone) then return end
    if owner.components.inventory then
        owner.components.inventory:GiveItem(stone, nil, owner:GetPosition())
    else
        stone.Transform:SetPosition(owner:GetPosition():Get())
    end
    if owner.components.talker then
        owner.components.talker:Say((cfg and cfg.msg or "漫长的陪伴得到了回应…")
            .. "获得了新的【" .. (cfg and cfg.name or enchant_id) .. "】附魔石")
    end
end

-- ============ total 模式：单人单档获取记录（存档级，按 userid） ============
local function HasObtainedOnce(enchant_id, player)
    local world = _G.TheWorld
    local record = world and world._moon_usedrop_once and world._moon_usedrop_once[enchant_id]
    return record ~= nil and record[player.userid or "unknown"] == true
end

local function MarkObtainedOnce(enchant_id, player)
    local world = _G.TheWorld
    if not world then return end
    world._moon_usedrop_once = world._moon_usedrop_once or {}
    world._moon_usedrop_once[enchant_id] = world._moon_usedrop_once[enchant_id] or {}
    world._moon_usedrop_once[enchant_id][player.userid or "unknown"] = true
end

AddPlayerPostInit(function(player)
    if not _G.TheWorld.ismastersim then return end

    -- continuous：按物品计时（同一件装备独立，摘下清零）
    local function startContinuousTimer(item, enchant_id)
        item._moon_usedrop_tasks = item._moon_usedrop_tasks or {}
        if item._moon_usedrop_tasks[enchant_id] then return end
        item._moon_usedrop_time = item._moon_usedrop_time or {}
        item._moon_usedrop_time[enchant_id] = item._moon_usedrop_time[enchant_id] or 0
        item._moon_usedrop_tasks[enchant_id] = item:DoPeriodicTask(1, function(it)
            -- 玩家失效（离线等）时本轮不计
            if not (player and player:IsValid()) then return end
            it._moon_usedrop_time[enchant_id] = (it._moon_usedrop_time[enchant_id] or 0) + 1
            local cfg = USE_TIME_DROPS[enchant_id]
            if cfg and it._moon_usedrop_time[enchant_id] >= cfg.time then
                it._moon_usedrop_time[enchant_id] = 0 -- 计满清零，继续佩戴可再次累计
                GiveEnchantStone(player, enchant_id)
            end
        end, 1)
    end

    -- total：玩家级计时，每秒仅在处于无欲无求禅定（挂机）状态时 +1
    local function startTotalTimer(enchant_id)
        if player._moon_usedrop_total_task then return end
        player._moon_usedrop_total = player._moon_usedrop_total or {}
        player._moon_usedrop_total_task = player:DoPeriodicTask(1, function()
            if not player:IsValid() then
                if player._moon_usedrop_total_task then
                    player._moon_usedrop_total_task:Cancel()
                    player._moon_usedrop_total_task = nil
                end
                return
            end
            if not player._wywq_meditating then return end -- 仅禅定挂机时计时
            player._moon_usedrop_total[enchant_id] = (player._moon_usedrop_total[enchant_id] or 0) + 1
            local cfg = USE_TIME_DROPS[enchant_id]
            if cfg and player._moon_usedrop_total[enchant_id] >= cfg.time then
                player._moon_usedrop_total[enchant_id] = 0
                if player._moon_usedrop_total_task then
                    player._moon_usedrop_total_task:Cancel()
                    player._moon_usedrop_total_task = nil
                end
                if not HasObtainedOnce(enchant_id, player) then
                    MarkObtainedOnce(enchant_id, player)
                    GiveEnchantStone(player, enchant_id)
                end
            end
        end, 1)
    end

    -- 佩戴：物品带有计掉附魔时按模式启动计时
    player:ListenForEvent("equip", function(owner, data)
        local item = data and data.item
        if not item or not item:IsValid() then return end
        for id, cfg in pairs(USE_TIME_DROPS) do
            if ItemHasEnchant(item, id) then
                if cfg.mode == "total" then
                    -- 已获取过则不再计时
                    if not HasObtainedOnce(id, player) then
                        startTotalTimer(id)
                    end
                else
                    startContinuousTimer(item, id)
                end
            end
        end
    end)

    -- 摘下：continuous 取消并清零（摘掉就重新计数）；total 停止计时但保留累计值
    player:ListenForEvent("unequip", function(_, data)
        local item = data and data.item
        if item then
            if item._moon_usedrop_tasks then
                for _, task in pairs(item._moon_usedrop_tasks) do
                    task:Cancel()
                end
                item._moon_usedrop_tasks = nil
            end
            item._moon_usedrop_time = nil
        end
        -- 仅当摘下的是带 total 附魔的物品时才停玩家计时
        if player._moon_usedrop_total_task then
            local has_total = false
            for id, cfg in pairs(USE_TIME_DROPS) do
                if cfg.mode == "total" and item and ItemHasEnchant(item, id) then
                    has_total = true
                    break
                end
            end
            if has_total or not item then
                player._moon_usedrop_total_task:Cancel()
                player._moon_usedrop_total_task = nil
            end
        end
    end)

    -- total 累计值随玩家存档
    local old_onsave = player.OnSave
    player.OnSave = function(inst, data)
        if old_onsave then old_onsave(inst, data) end
        if inst._moon_usedrop_total then
            data.moon_usedrop_total = inst._moon_usedrop_total
        end
    end
    local old_onload = player.OnLoad
    player.OnLoad = function(inst, data)
        if old_onload then old_onload(inst, data) end
        if data and data.moon_usedrop_total then
            inst._moon_usedrop_total = data.moon_usedrop_total
        end
    end
end)

-- 单人单档获取记录随世界存档
AddPrefabPostInit("world", function(inst)
    if not _G.TheWorld.ismastersim then return end
    local old_onsave = inst.OnSave
    inst.OnSave = function(i, data)
        if old_onsave then old_onsave(i, data) end
        if i._moon_usedrop_once then
            data.moon_usedrop_once = i._moon_usedrop_once
        end
    end
    local old_onload = inst.OnLoad
    inst.OnLoad = function(i, data)
        if old_onload then old_onload(i, data) end
        if data and data.moon_usedrop_once then
            i._moon_usedrop_once = data.moon_usedrop_once
        end
    end
end)
