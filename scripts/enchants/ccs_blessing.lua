-- 小月亮 附魔：小野的加护
-- 联动魔卡少女小樱mod(workshop-3043439883)
-- 仅小樱角色(ccs)可用，仅可附魔在卡牌盒(ccs_card_box)上
-- 攻击Boss概率封印(锁血4秒留10%)，满级卡牌盒1.5%秒杀

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end
    -- 检测小樱mod
    if not _G.Moon_IsModEnabled("workshop-3043439883") then return end

    -- 可封印Boss列表(目标→对应卡牌)
    local SEAL_MAP = {
        dragonfly = "ccs_cards_11",
        moose = "ccs_cards_5",
        antlion = "ccs_cards_21",
        bearger = "ccs_cards_13",
        deerclops = "ccs_cards_2",
        crabking = "ccs_cards_18",
        shadow_bishop = "ccs_cards_25",
        shadow_rook = "ccs_cards_1",
        alterguardian_phase3 = "ccs_cards_8",
        leif = "ccs_cards_16",
        beequeen = "ccs_cards_6",
        bishop = "ccs_cards_15",
        bishop_nightmare = "ccs_cards_15",
        bat = "ccs_cards_26",
        malbatross = "ccs_cards_27",
    }

    -- 检测卡牌盒是否满级(全部卡牌满级)
    local function is_cardbox_max_level(cardbox)
        if cardbox._level25 then return true end
        local container = cardbox.components and cardbox.components.container
        if not container then return false end
        local all_max, has_any = true, false
        for i = 1, container:GetNumSlots() do
            local item = container:GetItemInSlot(i)
            if item and item.components and item.components.ccs_card_level then
                has_any = true
                if item.components.ccs_card_level:GetLevel() < item.components.ccs_card_level:GetMaxLevel() then
                    all_max = false
                    break
                end
            end
        end
        if has_any and all_max then
            cardbox._level25 = true
            return true
        end
        return false
    end

    -- 检查目标是否可封印(卡牌盒中有对应卡牌即可,不论等级)
    local function can_seal_target(owner, target)
        local card_prefab = SEAL_MAP[target.prefab]
        if not card_prefab then return false end

        -- 影织/影织主教需要是epic大怪
        if (target.prefab == "shadow_bishop" or target.prefab == "shadow_rook")
            and not (target:HasTag("epic") and not target:HasTag("smallepic")) then
            return false
        end

        local cardbox
        for _, v in pairs(owner.components.inventory.equipslots) do
            if v.prefab == "ccs_card_box" then
                cardbox = v
                break
            end
        end
        if not cardbox or not cardbox.components or not cardbox.components.container then return false end

        -- 只要卡牌盒里有这张卡就算可封印
        for i = 1, cardbox.components.container:GetNumSlots() do
            local item = cardbox.components.container:GetItemInSlot(i)
            if item and item.prefab == card_prefab then
                return true
            end
        end
        return false
    end

    --
    -- 锁血钩子：当目标血量≤10%时触发，锁在10%持续duration秒
    -- 锁血期间目标无法被击杀，到期后恢复正常
    --
    local function apply_health_lock(target, duration)
        if not target or not target:IsValid() or not target.components.health then return end
        local health = target.components.health
        if health._ccs_hp_locked then return end

        health._ccs_hp_locked = true
        local oldDoDelta = health.DoDelta
        health._ccs_hp_old = oldDoDelta
        health.DoDelta = function(self, amount, overtime, cause, ...)
            if amount < 0 and self._ccs_hp_locked then
                local floor = self.maxhealth * 0.10
                local after = self.currenthealth + amount
                if after < floor then
                    local to_floor = floor - self.currenthealth
                    return oldDoDelta(self, to_floor, false, nil)
                end
            end
            return oldDoDelta(self, amount, overtime, cause, ...)
        end

        target:DoTaskInTime(duration, function()
            if health and health._ccs_hp_old then
                health.DoDelta = health._ccs_hp_old
                health._ccs_hp_old = nil
                health._ccs_hp_locked = nil
            end
        end)
    end

    _G.AddSpecialEquipEffect("Moon_CCS_BLESSING", {
        name = "小野的加护",
        client_text = "小野\n加护",
        desc = "限小樱,攻击Boss血量≤10%%时锁血4秒(无法击杀)\n满级卡牌盒1.5%%秒杀\n同一目标冷却10秒",
        check_desc = "仅限附魔卡牌盒(ccs_card_box)",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(equip_inst)
            return equip_inst.prefab == "ccs_card_box", "仅限附魔卡牌盒"
        end,

        on_equip_fn = function(equip_inst, owner, value)
            if owner.prefab ~= "ccs" then
                if owner.components.talker then
                    owner.components.talker:Say("只有小樱才能得到加护！")
                end
                return
            end
            _G.Moon_AddEffect(owner, "ccs_blessing", "Moon_CCS_BLESSING", 1)
            if owner._ccs_blessing_hooked then return end
            owner._ccs_blessing_hooked = true

            owner._ccs_blessing_handler = function(attacker, data)
                if not _G.Moon_HasEffect(owner, "ccs_blessing") then return end
                local target = data and data.target
                if not target or not target:IsValid() then return end
                if target:HasTag("wall") or target:HasTag("structure") or target:HasTag("balloon") or target:HasTag("playerghost") then return end
                if not target.components or not target.components.health or target.components.health:IsDead() then return end

                -- 找到装备的卡牌盒
                local cardbox
                for _, v in pairs(owner.components.inventory.equipslots) do
                    if v.prefab == "ccs_card_box" then
                        cardbox = v
                        break
                    end
                end
                if not cardbox then return end

                -- ====== 满级模式：1.5%秒杀 ======
                if is_cardbox_max_level(cardbox) then
                    if math.random() <= 0.015 then
                        if owner.components.talker then
                            owner.components.talker:Say("代表月亮消灭你！")
                        end
                        local maxhp = target.components.health.maxhealth
                        target.components.health:DoDelta(-maxhp, false, nil, nil, owner)
                    end
                    return
                end

                -- ====== 血量触发锁血 ======
                -- 攻击时检测目标血量，若≤10%则锁血4秒
                if not can_seal_target(owner, target) then return end
                local hp_pct = target.components.health.currenthealth / target.components.health.maxhealth
                if hp_pct > 0.10 then return end
                if target._ccs_blessing_seal_cd then return end

                target._ccs_blessing_seal_cd = true
                target:DoTaskInTime(10, function()
                    if target:IsValid() then target._ccs_blessing_seal_cd = nil end
                end)

                apply_health_lock(target, 4)

                if owner.components.talker then
                    owner.components.talker:Say("小野:看我锁它血！")
                end
            end
            owner:ListenForEvent("onattackother", owner._ccs_blessing_handler)
        end,

        un_equip_fn = function(equip_inst, owner, value)
            _G.Moon_ReduceEffect(owner, "ccs_blessing", "Moon_CCS_BLESSING", 1)
            if not _G.Moon_HasEffect(owner, "ccs_blessing") then
                if owner._ccs_blessing_handler then
                    owner:RemoveEventCallback("onattackother", owner._ccs_blessing_handler)
                    owner._ccs_blessing_handler = nil
                end
                owner._ccs_blessing_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Moon_CCS_BLESSING", 0.01)
end)
