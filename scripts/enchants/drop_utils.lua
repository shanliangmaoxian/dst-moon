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
function _G.Moon_RegisterEnchantDrop(enchant_id, drop_weight)
    local weight = drop_weight
    if weight == nil then weight = 1 end
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

-- 钢羊(spat)击杀掉落：10%概率掉落 Legend_LAOSHI 附魔石（需开启魔女之旅 Mod）
AddPrefabPostInit("spat", function(inst)
    if not GLOBAL.TheWorld.ismastersim then return end
    if not GLOBAL.Moon_IsModEnabled("workshop-2578692071") then return end
    inst:ListenForEvent("death", function(inst, data)
        if math.random() > 0.01 then return end
        local stone = GLOBAL.HHSpawnStoneById("Legend_LAOSHI")
        if stone then
            local pt = inst:GetPosition()
            stone.Transform:SetPosition(pt:Get())
        end
    end)
end)
