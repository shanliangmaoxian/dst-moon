-- 樱之签 v1.0.2 单文件版。全部逻辑均在本文件，无需另放组件/工具文件。
-- 功能：小樱专属、卡牌盒专属；成功封印掉落；装备后每日抽牌。
-- 初始0.08%，每次未中+0.005个百分点，第1500次保底，获得后重置。
-- 小月亮固定入口的版本不会自动加载新增文件。本文件必须由已有入口加载。
local lottery_global = GLOBAL
if lottery_global.rawget(env, "lmoon_sakura_lottery_loaded") then return end

lottery_global.package.preload["moon_utils/sakura_lottery"] = function()
-- 樱之签：权重及成功封印判定。概率用整数单位表示，1单位=0.001%。
local M = { EFFECT_ID = "Moon_SAKURA_LOTTERY", PITY_LIMIT = 1500 }
local weights = {
    [1]=14, [2]=18, [5]=19, [6]=12, [8]=8, [11]=7, [13]=15,
    [16]=20, [18]=5, [21]=17, [25]=13, [27]=16, [29]=40,
}

function M.GetChance(failures)
    if failures >= M.PITY_LIMIT - 1 then return 1 end
    return (80 + 5 * failures) / 100000
end

function M.GetPool()
    local pool, total = {}, 0
    for id = 1, 29 do
        if id ~= 14 or TUNING.CCS_CARD14_ENBLE then
            local weight = weights[id] or 100
            total = total + weight
            pool[#pool + 1] = { prefab = "ccs_cards_" .. id, weight = weight }
        end
    end
    return pool, total
end

function M.PickCard()
    local pool, total = M.GetPool()
    local roll = math.random(total)
    for _, entry in ipairs(pool) do
        roll = roll - entry.weight
        if roll <= 0 then return entry.prefab end
    end
end

function M.HasEffect(item)
    local hh = item and item.components and item.components.hh_equip
    return hh and hh:HasEffectByName(M.EFFECT_ID) or false
end

function M.IsSakura(player)
    return player and player.prefab == "ccs" and not player:HasTag("playerghost")
        and (not player.components.health or not player.components.health:IsDead())
end

function M.IsActive(player)
    if not M.IsSakura(player) then return false end
    local inventory = player.components.inventory
    if not inventory then return false end
    for _, box in pairs(inventory.equipslots) do
        if box.prefab == "ccs_card_box" and M.HasEffect(box) then return true end
    end
    return false
end

function M.Give(player, item)
    local pos = player:GetPosition()
    item.Transform:SetPosition(pos:Get())
    if player.components.inventory then player.components.inventory:GiveItem(item, nil, pos) end
end

function M.InstallActions()
    local action = ACTIONS.CCS_SEAL
    if action and not action._lmoon_lottery_hooked then
        action._lmoon_lottery_hooked = true
        local original = action.fn
        action.fn = function(act)
            local target, player = act and act.target, act and act.doer
            local counter = M.IsSakura(player) and player.components.lmoon_sakura_lottery
            local valid = counter and target and target:IsValid() and not target._lmoon_lottery_rewarded
            local health = valid and target.components.health
            local alive = health and not health:IsDead()
            local result, reason = original(act)
            -- 原封印动作失败也可能返回true；必须确认目标死亡/物品消耗。
            if valid and result and ((alive and health:IsDead() and target:HasTag("ccs_no_droploot"))
                or (not health and not target:IsValid())) then
                target._lmoon_lottery_rewarded = true
                counter:OnSealSuccess()
            end
            return result, reason
        end
    end
    -- 兼容仓库里的魔杖复制及镜牌复制，既禁止复制石头，也禁止复制已附魔的盒子。
    for _, id in ipairs({ "CCS_DUPLICATE_ITEM", "CCS_MIRROR_COPY" }) do
        local copy = ACTIONS[id]
        if copy and not copy._lmoon_lottery_hooked then
            copy._lmoon_lottery_hooked = true
            local original = copy.fn
            copy.fn = function(act)
                local item = act and act.target
                if item and (item.hh_effect == M.EFFECT_ID or M.HasEffect(item)) then
                    return false, "樱之签及带有此附魔的卡牌盒不能复制"
                end
                return original(act)
            end
        end
    end
end

return M

end

lottery_global.setfenv(lottery_global.package.preload["moon_utils/sakura_lottery"], lottery_global)

lottery_global.package.preload["components/lmoon_sakura_lottery"] = function()
local lottery = require("moon_utils/sakura_lottery")

local Lottery = Class(function(self, inst)
    self.inst = inst
    self.seals_without_drop = 0
    self.pending_stone = false
    -- 首次获得效果从下一游戏日开始；换装备和重连不重置领奖日。
    self.last_reward_day = nil
    inst:WatchWorldState("cycles", function() self:TryDaily() end)
    local function refresh()
        inst:DoTaskInTime(0, function() self:TryDaily() end)
    end
    inst:ListenForEvent("equip", refresh)
    inst:ListenForEvent("ms_respawnfromghost", refresh)
end)

function Lottery:OnSealSuccess()
    if not TheWorld.ismastersim or not lottery.IsSakura(self.inst) then return end
    local chance = lottery.GetChance(self.seals_without_drop)
    self.seals_without_drop = math.min(self.seals_without_drop + 1, lottery.PITY_LIMIT)
    if not self.pending_stone and chance < 1 and math.random() >= chance then return end
    -- 生成失败时保存已中奖状态，后续封印重试，不吞掉随机中奖或保底。
    self.pending_stone = true
    local spawn = rawget(_G, "HHSpawnStoneById")
    local stone = spawn and spawn(lottery.EFFECT_ID)
    if not stone then return end
    lottery.Give(self.inst, stone)
    self.seals_without_drop, self.pending_stone = 0, false
    if self.inst.components.talker then self.inst.components.talker:Say("封印的幸运降临了，获得樱之签！") end
end

function Lottery:TryDaily()
    if not TheWorld.ismastersim or not lottery.IsActive(self.inst) then return false end
    local day = TheWorld.state.cycles
    if self.last_reward_day == nil then
        self.last_reward_day = day
        return false
    end
    if day <= self.last_reward_day then return false end
    local card = SpawnPrefab(lottery.PickCard())
    if not card then return false end
    local level = card.components.ccs_card_level
    if level then level:SetMaster(self.inst.name, self.inst.userid) end
    -- 发奖前写入账本，避免背包事件重入；离线漏掉的天数不补发。
    self.last_reward_day = day
    lottery.Give(self.inst, card)
    if self.inst.components.talker then
        local name = STRINGS.NAMES[string.upper(card.prefab)] or "卡牌"
        self.inst.components.talker:Say("樱之签今日抽到：" .. name)
    end
    return true
end

function Lottery:OnSave()
    return { seals_without_drop = self.seals_without_drop, pending_stone = self.pending_stone,
        last_reward_day = self.last_reward_day }
end

function Lottery:OnLoad(data)
    if not data then return end
    local count, day = data.seals_without_drop, data.last_reward_day
    if type(count) == "number" and count == count then
        self.seals_without_drop = math.max(0, math.min(math.floor(count), lottery.PITY_LIMIT))
    end
    if type(day) == "number" and day == day and day ~= math.huge and day ~= -math.huge then
        self.last_reward_day = math.max(0, math.floor(day))
    end
    self.pending_stone = data.pending_stone == true
    self.inst:DoTaskInTime(0, function() self:TryDaily() end)
end

return Lottery

end

lottery_global.setfenv(lottery_global.package.preload["components/lmoon_sakura_lottery"], lottery_global)

-- 樱之签 v1.0.0：放进小月亮后，由modmain导入本文件。
local G = GLOBAL
if not G.MOON_CFG or not G.MOON_CFG.ENABLE_MORE_ENCHANTS then return end
if G.rawget(env, "lmoon_sakura_lottery_loaded") then return end
env.lmoon_sakura_lottery_loaded = true
local lottery = require("moon_utils/sakura_lottery")
local ID = lottery.EFFECT_ID
local registered = false

local function HHAvailable()
    return type(G.rawget(G, "AddSpecialEquipEffect")) == "function"
end

local function Register()
    local ingredients = G.rawget(G, "CHARACTER_INGREDIENT")
    if registered or not HHAvailable() or not ingredients or not ingredients.CCS_MAGIC then return end
    G.AddSpecialEquipEffect(ID, {
        name = "樱之签",
        client_text = "樱之签",
        desc = "小樱装备卡牌盒后，每个游戏日随机获得一张绑定卡牌",
        check_desc = "仅小樱可附魔、使用；仅限卡牌盒；每日最多一次，不补发离线奖励",
        ui_from_desc = "仅成功封印获得：初始0.08%，每次未中增加0.005个百分点，第1500次保底；获得后重置",
        obtain_desc = "仅小樱成功封印获得：初始0.08%，每次未中增加0.005个百分点，第1500次必得，获得后重置",
        obtains = {}, can_add = false, only_one = true,
        only_compound = false, is_special = true,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(item)
            return item ~= nil and item.prefab == "ccs_card_box", "樱之签只有库洛魔法使小樱可以使用"
        end,
    })
    -- HH原接口不保留所有扩展字段，显式写入以兼容不同加载顺序。
    local config = require("enums/hh_enchant").HH_EQUIP_BUFF_LIST[ID]
    config.obtains, config.recipes = {}, {}
    config.obtain_desc = "仅小樱成功封印获得：初始0.08%，每次未中增加0.005个百分点，第1500次必得，获得后重置"
    if G.TUNING.MOON_ENCHANT_TIERS then G.TUNING.MOON_ENCHANT_TIERS[ID] = "T0" end
    registered = true
end

AddPrefabPostInit("world", Register)
AddSimPostInit(function()
    Register()
    if registered and G.TheWorld.ismastersim then
        G.TheWorld:DoTaskInTime(0, lottery.InstallActions)
    end
end)

AddPrefabPostInit("ccs", function(inst)
    if G.TheWorld.ismastersim and registered and not inst.components.lmoon_sakura_lottery then
        inst:AddComponent("lmoon_sakura_lottery")
    end
end)

AddPrefabPostInit("ccs_card_box", function(inst)
    if not registered then return end
    inst:AddTag("hh_equip")
    if not G.TheWorld.ismastersim then return end
    if not inst.components.hh_equip then
        inst:AddComponent("hh_equip")
        inst.components.hh_equip:SetMaxGemLimit(3)
        inst.components.hh_equip:SetEquipBuffLimit(5)
    end
end)

-- 装备前置检查拿不到操作者；在附魔UI入口再次校验角色，失败不消耗石头。
AddComponentPostInit("hh_player", function(self)
    local original = self.AddEquipEffect
    self.AddEquipEffect = function(component, ...)
        local ui = component.ui_container
        local container = ui and ui.components.container
        local stone = container and container:GetItemInSlot(26)
        if stone and stone.hh_effect == ID and not lottery.IsSakura(component.inst) then
            return false, "樱之签只有小樱可以附魔和使用"
        end
        return original(component, ...)
    end
end)
