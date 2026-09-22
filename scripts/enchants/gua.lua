-- 小月亮 附魔：挂！
-- 效果：每天（cycleschanged）从天上掉落一个奖池物品
-- 奖池：30% 肉丸*5，20% 基础物资*100，20% 随机料理(非肉丸)*5，20% 粑粑*99，
--       6% 蜘蛛*1，2% 随机附魔石，1.9% 彩蛋：格子塞满粑粑+向周围玩家发射粑粑1分钟
--       （剩余 0.1% 预留给"创造模式1分钟"彩蛋，暂未实现，本期不掉）
-- "你是不是又偷偷开了"

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_GUA"
local EFFECT_KEY = "gua"

-- =========================================================
-- 工具函数
-- =========================================================

-- 掉落在玩家头顶（从天而降）
local function sky_drop(owner, prefab, x, z)
    local item = _G.SpawnPrefab(prefab)
    if item then
        local jitter_x = (math.random() - 0.5) * 4
        local jitter_z = (math.random() - 0.5) * 4
        item.Transform:SetPosition(x + jitter_x, 20, z + jitter_z)
        if item.Physics then
            item.Physics:SetVel(0, -1, 0)
        end
    end
    return item
end

-- 给玩家发一组物品（自动堆叠，发不下的掉在地上）
local function give_items(owner, prefab, count)
    if not owner.components.inventory then return end
    for i = 1, count do
        local item = _G.SpawnPrefab(prefab)
        if item then
            owner.components.inventory:GiveItem(item, nil, owner:GetPosition())
        end
    end
end

-- 随机料理池（不含肉丸）
local DISH_POOL = {
    "butterflymuffin", "frogglebunwich", "kabobs", "ratatouille",
    "fruitmedley", "jammypres", "taffy", "pumpkincookie",
    "waffles", "icecream", "watermelonicle", "guacamole",
}

-- 基础物资池
local BASIC_POOL = { "rocks", "log", "cutgrass", "twigs", "flint" }

-- 彩蛋：向周围玩家发射粑粑
local function throw_poop(owner)
    if not owner:IsValid() then return end
    local x, y, z = owner.Transform:GetWorldPosition()
    local targets = {}
    for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, 15, { "player" })) do
        if v ~= owner and v:IsValid() and v.components.health and not v.components.health:IsDead() then
            table.insert(targets, v)
        end
    end
    local tx, tz
    if #targets > 0 then
        local target = targets[math.random(#targets)]
        tx, _, tz = target.Transform:GetWorldPosition()
    else
        tx, tz = x + (math.random() - 0.5) * 10, z + (math.random() - 0.5) * 10
    end
    local poop = _G.SpawnPrefab("poop")
    if poop then
        poop.Transform:SetPosition(x, y + 2, z)
        if poop.Physics then
            local dx, dz = tx - x, tz - z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < 1 then
                dx, dz, dist = math.random() - 0.5, math.random() - 0.5, 1
            end
            local speed = math.min(dist, 12)
            poop.Physics:SetVel(dx / dist * speed, 7, dz / dist * speed)
        end
    end
end

-- 彩蛋2：格子塞满粑粑 + 粑粑雨 1 分钟
local function start_poop_rain(owner)
    local inv = owner.components.inventory
    if inv then
        for i = 1, inv.maxslots do
            local poop = _G.SpawnPrefab("poop")
            if poop then
                inv:GiveItem(poop, nil, owner:GetPosition())
            end
        end
    end
    if owner._gua_poop_task then
        owner._gua_poop_task:Cancel()
        owner._gua_poop_task = nil
    end
    owner._gua_poop_task = owner:DoPeriodicTask(2, throw_poop, 1)
    owner:DoTaskInTime(60, function(inst)
        if inst._gua_poop_task then
            inst._gua_poop_task:Cancel()
            inst._gua_poop_task = nil
        end
    end)
    if owner.components.talker then
        owner.components.talker:Say("有味道的一天……")
    end
end

-- 随机附魔石（从 HH 普通/优质/稀有池随机一个）
local function give_random_stone(owner)
    local ids = {}
    if _G.HHGetComEquipEffect then
        for _, id in ipairs(_G.HHGetComEquipEffect()) do table.insert(ids, id) end
    end
    if _G.HHGetGoodEquipEffect then
        for _, id in ipairs(_G.HHGetGoodEquipEffect()) do table.insert(ids, id) end
    end
    if _G.HHGetRareEquipEffect then
        for _, id in ipairs(_G.HHGetRareEquipEffect()) do table.insert(ids, id) end
    end
    if #ids == 0 then return end
    local stone = _G.HHSpawnStoneById(ids[math.random(#ids)])
    if stone and owner.components.inventory then
        owner.components.inventory:GiveItem(stone, nil, owner:GetPosition())
    end
end

-- 每日奖池抽取
local function daily_gacha(owner)
    if not owner:IsValid() or owner.components.health:IsDead() then return end
    local x, _, z = owner.Transform:GetWorldPosition()

    -- 权重表（总和 99.9，剩 0.1 为创造模式彩蛋预留位，本期不掉）
    local roll = math.random() * 100
    if roll < 30 then
        -- 30% 肉丸*2
        give_items(owner, "meatballs", 2)
    elseif roll < 50 then
        -- 20% 基础物资*10
        give_items(owner, BASIC_POOL[math.random(#BASIC_POOL)], 10)
    elseif roll < 70 then
        -- 20% 随机料理*3
        give_items(owner, DISH_POOL[math.random(#DISH_POOL)], 3)
    elseif roll < 90 then
        -- 20% 粑粑*99
        give_items(owner, "poop", 99)
    elseif roll < 96 then
        -- 6% 蜘蛛*1
        sky_drop(owner, "spider", x, z)
    elseif roll < 98 then
        -- 2% 随机附魔石
        give_random_stone(owner)
    elseif roll < 99.9 then
        -- 1.9% 彩蛋：粑粑雨
        start_poop_rain(owner)
    end

    if owner.components.talker then
        owner.components.talker:Say("你是不是又偷偷开了")
    end
end

-- =========================================================
-- 附魔注册
-- =========================================================

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "挂！",
        client_text = "挂！",
        desc = "你是不是又偷偷开了？\n每天从天上掉落一个奖池物品",
        can_add = false,
        only_one = true,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._gua_hooked then
                owner._gua_hooked = true
                owner._gua_last_cycle = nil

                -- 世界进入新的一天时抽一次奖
                owner._gua_day_handler = function(world)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local cycles = world.state.cycles or 0
                    if owner._gua_last_cycle == cycles then return end
                    owner._gua_last_cycle = cycles
                    -- 错开黎明，延迟几秒后掉落
                    owner:DoTaskInTime(math.random(3, 10), function(inst)
                        if inst:IsValid() and _G.Moon_HasEffect(inst, EFFECT_KEY) then
                            daily_gacha(inst)
                        end
                    end)
                end
                _G.TheWorld:ListenForEvent("cycleschanged", owner._gua_day_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                if owner._gua_day_handler then
                    _G.TheWorld:RemoveEventCallback("cycleschanged", owner._gua_day_handler)
                    owner._gua_day_handler = nil
                end
                if owner._gua_poop_task then
                    owner._gua_poop_task:Cancel()
                    owner._gua_poop_task = nil
                end
                owner._gua_hooked = nil
            end
        end,
    })

    -- 进入常规掉落池（权重与其它传奇附魔一致）
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
