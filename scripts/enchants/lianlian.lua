-- 小月亮 附魔：无意识的恋恋
-- 免疫生物仇恨，主动攻击解除，恢复cd10s；玩家移速+100%，快速交互
-- 获取：投骰子 roll 出数字 5 和 14 后，公屏打字"哈德曼的妖怪少女"或"5.14"
-- "有注意到恋恋了嘛～"
-- 注：骰子系统由 幸运橙汁(xingyunchengzhi.lua) 的 Moon_DoDiceRoll 提供，
--     本文件监听其广播的 moon_dice_roll 事件；公屏聊天检测 hook Networking_Say。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local STEALTH_CD = 10 -- 免疫仇恨被主动攻击解除后的恢复cd（秒）

-- 通用兜底：任何以恋恋玩家为 afflicter 的直扣血伤害(health:DoDelta)也算主动攻击
-- 覆盖魔女等 mod 中不走 combat 攻击链、但传了 afflicter 的技能伤害（如泰拉棱镜·剑雨）
AddComponentPostInit("health", function(self)
    if self._moon_lianlian_hooked then return end
    self._moon_lianlian_hooked = true
    local Old_DoDelta = self.DoDelta
    self.DoDelta = function(self, amount, overtime, cause, ignore_invincible, afflicter, ...)
        if amount ~= nil and amount < 0
                and afflicter ~= nil and afflicter.isplayer
                and afflicter ~= self.inst
                and afflicter._lianlian_break_stealth ~= nil then
            afflicter._lianlian_break_stealth("魔法波动暴露了位置！10秒后重新隐身...")
        end
        return Old_DoDelta(self, amount, overtime, cause, ignore_invincible, afflicter, ...)
    end
end)

-- =========================================================
-- Part 1: 骰子事件监听（记录 roll 出 5 和 14）
-- =========================================================
AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    inst._lianlian_roll5 = false
    inst._lianlian_roll14 = false
    inst:ListenForEvent("moon_dice_roll", function(_, data)
        local value = data and data.value
        if value == 5 then
            inst._lianlian_roll5 = true
            if inst.components.talker then
                inst.components.talker:Say("roll出5！再roll出14，公屏打出'哈德曼的妖怪少女'或'5.14'获取恋恋～")
            end
        elseif value == 14 then
            inst._lianlian_roll14 = true
            if inst.components.talker then
                inst.components.talker:Say("roll出14！公屏打出'哈德曼的妖怪少女'或'5.14'获取恋恋～")
            end
        end
    end)
end)

-- =========================================================
-- Part 2: 公屏打字检测（满足条件后给予附魔石）
-- =========================================================
local _Old_Networking_Say_LIANLIAN = _G.Networking_Say
_G.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
    if _G.TheWorld and _G.TheWorld.ismastersim
            and type(message) == "string"
            and (message == "哈德曼的妖怪少女" or message == "5.14")
    then
        local player = _G.UserToPlayer(userid)
        if player and player:IsValid() then
            if player._lianlian_roll5 and player._lianlian_roll14 then
                local success, stone = _G.pcall(_G.HHSpawnStoneById, "Legend_LIANLIAN")
                if success and stone and player.components.inventory then
                    player.components.inventory:GiveItem(stone, nil, player:GetPosition())
                    if player.components.talker then
                        player.components.talker:Say("有注意到恋恋了嘛～")
                    end
                end
                player._lianlian_roll5 = false
                player._lianlian_roll14 = false
            elseif player.components.talker then
                player.components.talker:Say("还需要roll出5和14才能注意到恋恋哦～")
            end
        end
    end
    if _Old_Networking_Say_LIANLIAN then
        _Old_Networking_Say_LIANLIAN(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
    end
end

-- =========================================================
-- Part 3: 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_LIANLIAN", {
        name = "无意识的恋恋",
        client_text = "恋恋",
        desc = "免疫生物仇恨(主动攻击解除,10秒后恢复)\n玩家移速+100% 快速交互",
        check_desc = "有注意到恋恋了嘛～",
        can_add = false,
        only_one = true,
        is_special = true, -- 专属获取：从 HH 掉落池(普通/优质/稀有)中排除，打宝藏怪也不掉
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "lianlian", "Legend_LIANLIAN", 1)
            if not owner._lianlian_inited then
                owner._lianlian_inited = true
                owner._lianlian_stealth_on = false
                owner._lianlian_stealth_until = 0

                -- 玩家移速+100%
                if owner.components.locomotor then
                    owner.components.locomotor:SetExternalSpeedMultiplier(owner, "lianlian_speed", 2.0)
                end

                -- 快速交互（HH fast_act，参考 3096210166 / laodong）
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("fast_act", 1)
                end
                _G.pcall(function()
                    if owner.userid then
                        _G.SendModRPCToClient(_G.CLIENT_MOD_RPC["hh_rpc"]["hh_client_value"], owner.userid, "hh_fast_act", true)
                    end
                end)

                -- 免疫生物仇恨（原版：stealth tag + combat.shouldavoidaggrofn）
                local function stealthOn()
                    if owner._lianlian_stealth_on then return end
                    if not owner:HasTag("stealth") then
                        owner:AddTag("stealth")
                        owner._lianlian_own_stealth = true
                    end
                    if owner.components.combat then
                        owner.components.combat.shouldavoidaggrofn = function() return true end
                    end
                    owner._lianlian_stealth_on = true
                end
                local function stealthOff()
                    if not owner._lianlian_stealth_on then return end
                    if owner._lianlian_own_stealth then
                        owner:RemoveTag("stealth")
                        owner._lianlian_own_stealth = nil
                    end
                    if owner.components.combat then
                        owner.components.combat.shouldavoidaggrofn = nil
                    end
                    owner._lianlian_stealth_on = false
                end

                -- 统一破隐：解除免疫仇恨，10秒后自动恢复
                local function breakStealth(tip)
                    if not owner._lianlian_stealth_on then return end
                    stealthOff()
                    owner._lianlian_stealth_until = _G.GetTime() + STEALTH_CD
                    if tip and owner.components.talker then
                        owner.components.talker:Say(tip)
                    end
                end
                -- 供 health:DoDelta 兜底钩调用（见文件顶部）
                owner._lianlian_break_stealth = breakStealth

                -- 主动攻击 → 解除免疫仇恨
                owner._lianlian_attack_handler = function()
                    if not _G.Moon_HasEffect(owner, "lianlian") then return end
                    breakStealth("被发现了！10秒后重新隐身...")
                end
                owner:ListenForEvent("onattackother", owner._lianlian_attack_handler)
                -- AoE 攻击(DoAreaAttack)推 onareaattackother；攻击命中(GetAttacked)推 onhitother，一并监听
                owner:ListenForEvent("onareaattackother", owner._lianlian_attack_handler)
                owner:ListenForEvent("onhitother", owner._lianlian_attack_handler)

                -- 魔女(2578692071)施法统一入口：elaina_magic 扣魔力时在玩家身上推
                -- elaina_magic_delta，绝大多数技能伤害是 health:DoDelta 直扣血、
                -- 不产生任何 combat 攻击事件，靠这条覆盖（消耗魔力即视为主动攻击）
                owner._lianlian_magic_handler = function(_, data)
                    if not _G.Moon_HasEffect(owner, "lianlian") then return end
                    if data and data.amount and data.amount < 0 then
                        breakStealth("魔法波动暴露了位置！10秒后重新隐身...")
                    end
                end
                owner:ListenForEvent("elaina_magic_delta", owner._lianlian_magic_handler)

                -- 周期检测：cd 结束后恢复隐身
                owner._lianlian_stealth_task = owner:DoPeriodicTask(0.5, function()
                    if not _G.Moon_HasEffect(owner, "lianlian") then return end
                    if not owner._lianlian_stealth_on and _G.GetTime() >= owner._lianlian_stealth_until then
                        stealthOn()
                    end
                end)

                stealthOn()
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "lianlian", "Legend_LIANLIAN", 1)
            if not _G.Moon_HasEffect(owner, "lianlian") then
                -- 移速恢复
                if owner.components.locomotor then
                    owner.components.locomotor:RemoveExternalSpeedMultiplier(owner, "lianlian_speed")
                end

                -- 快速交互恢复
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("fast_act", 1)
                end
                _G.pcall(function()
                    if owner.userid then
                        local still_fast = hh and hh.HasSpecialEffect and hh:HasSpecialEffect("fast_act")
                        _G.SendModRPCToClient(_G.CLIENT_MOD_RPC["hh_rpc"]["hh_client_value"], owner.userid, "hh_fast_act", still_fast or false)
                    end
                end)

                -- 免疫仇恨恢复
                if owner._lianlian_own_stealth then
                    owner:RemoveTag("stealth")
                    owner._lianlian_own_stealth = nil
                end
                if owner.components.combat then
                    owner.components.combat.shouldavoidaggrofn = nil
                end

                if owner._lianlian_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._lianlian_attack_handler)
                    owner:RemoveEventCallback("onareaattackother", owner._lianlian_attack_handler)
                    owner:RemoveEventCallback("onhitother", owner._lianlian_attack_handler)
                    owner._lianlian_attack_handler = nil
                end
                if owner._lianlian_magic_handler then
                    owner:RemoveEventCallback("elaina_magic_delta", owner._lianlian_magic_handler)
                    owner._lianlian_magic_handler = nil
                end
                owner._lianlian_break_stealth = nil
                if owner._lianlian_stealth_task then
                    owner._lianlian_stealth_task:Cancel()
                    owner._lianlian_stealth_task = nil
                end

                owner._lianlian_stealth_on = nil
                owner._lianlian_stealth_until = nil
                owner._lianlian_inited = nil
            end
        end,
    })

    -- 不通过 Boss 掉落获取（仅骰子+公屏打字）
    _G.Moon_RegisterEnchantDrop("Legend_LIANLIAN", 0)
end)
