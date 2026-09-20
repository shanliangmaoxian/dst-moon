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

-- =========================================================
-- 使用时长掉落：装备佩戴指定附魔满 N 秒 → 掉落一枚该附魔石
-- 计时按物品（同一件装备）独立累计，且仅在"被佩戴"时计时；
-- 摘下装备（摘掉附魔）即取消计时并清零，重新佩戴重新计数；
-- 计满后清零重新累计，持续佩戴可反复获取
-- =========================================================
local USE_TIME_DROPS = {
    -- 附魔id = { time = 需要的使用秒数, name = 飘字用的附魔名 }
    ["Legend_YUFENFEN"] = { time = 2400, name = "雨纷纷" }, -- 同一把伞连续使用满 2400 秒（游戏内40分钟）
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
    local ok, stone = _G.pcall(_G.HHSpawnStoneById, enchant_id)
    if not (ok and stone) then return end
    if owner.components.inventory then
        owner.components.inventory:GiveItem(stone, nil, owner:GetPosition())
    else
        stone.Transform:SetPosition(owner:GetPosition():Get())
    end
    if owner.components.talker then
        owner.components.talker:Say("这把伞陪你走过了一场又一场雨…获得了新的【"
            .. (USE_TIME_DROPS[enchant_id] and USE_TIME_DROPS[enchant_id].name or enchant_id) .. "】附魔石")
    end
end

AddPlayerPostInit(function(player)
    if not _G.TheWorld.ismastersim then return end

    -- 佩戴：物品带有计掉附魔时，按物品启动计时
    player:ListenForEvent("equip", function(owner, data)
        local item = data and data.item
        if not item or not item:IsValid() then return end
        local enchant_id
        for id in pairs(USE_TIME_DROPS) do
            if ItemHasEnchant(item, id) then
                enchant_id = id
                break
            end
        end
        if not enchant_id then return end
        if item._moon_usedrop_task then
            item._moon_usedrop_task:Cancel()
        end
        item._moon_usedrop_id = enchant_id
        item._moon_usedrop_time = item._moon_usedrop_time or 0
        item._moon_usedrop_task = item:DoPeriodicTask(1, function(it)
            -- 玩家失效（离线等）时本轮不计
            if not (owner and owner:IsValid()) then return end
            it._moon_usedrop_time = (it._moon_usedrop_time or 0) + 1
            local need = USE_TIME_DROPS[it._moon_usedrop_id]
                and USE_TIME_DROPS[it._moon_usedrop_id].time or 2400
            if it._moon_usedrop_time >= need then
                it._moon_usedrop_time = 0 -- 计满清零，继续佩戴可再次累计
                GiveEnchantStone(owner, it._moon_usedrop_id)
            end
        end, 1)
    end)

    -- 摘下：取消计时并清零（摘掉就重新计数）
    player:ListenForEvent("unequip", function(_, data)
        local item = data and data.item
        if not item then return end
        if item._moon_usedrop_task then
            item._moon_usedrop_task:Cancel()
            item._moon_usedrop_task = nil
        end
        item._moon_usedrop_time = nil
        item._moon_usedrop_id = nil
    end)
end)
