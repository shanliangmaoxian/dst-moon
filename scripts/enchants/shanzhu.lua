 -- 小月亮 附魔：山竹的捏
-- 厚皮甜心 — 厚皮护盾吸收伤害，破盾回血并释放果香迸发，周期性进入果中皇后强化状态
-- 击杀怪物15%双倍掉落，小樱角色(ccs)且装了3043439883时每天送两份双皮奶

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_SHANZHU", {
        name = "山竹的捏",
        client_text = "山竹\n的捏",
        desc = "战斗护盾25%血量，移速+15%攻击+20%\n破盾回血+AoE，每60s果中皇后强化\n打怪15%双倍掉落",
        check_desc = "厚皮甜心，永不认输！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "shanzhu", "Legend_SHANZHU", 1)
            if not owner._shanzhu_hooked then
                owner._shanzhu_hooked = true
                owner._shanzhu_shield_active = false
                owner._shanzhu_shield_hp = 0
                owner._shanzhu_shield_max = 0
                owner._shanzhu_queen_active = false
                owner._shanzhu_shield_task = nil
                owner._shanzhu_queen_task = nil
                owner._shanzhu_break_count = 0
                owner._shanzhu_in_combat = false
                owner._shanzhu_combat_timer = nil

                local hh = owner.components.hh_player

                -- 台词表
                local BREAK_LINES = {
                    "哎哟，又破皮了~",
                    "果肉都露出来了！",
                    "厚皮甜心，永不认输！",
                    "我的紫皮最好吃了！",
                    "别打了别打了，果肉要烂了！",
                }

                local QUEEN_LINES = {
                    "果中皇后驾到！",
                    "现在是山竹最甜的时候！",
                    "紫玉生辉，甜满人间！",
                }

                -- 说话
                local function say_line(lines)
                    if owner.components.talker then
                        owner.components.talker:Say(lines[_G.math.random(#lines)])
                    end
                end

                -- 创建护盾
                local function apply_shield()
                    if owner._shanzhu_shield_active then return end

                    local max_hp = 150
                    if owner.components.health then
                        max_hp = owner.components.health.maxhealth or 150
                    end

                    local shield_pct = 0.25
                    if owner._shanzhu_queen_active then
                        shield_pct = 0.50
                    end

                    owner._shanzhu_shield_max = max_hp * shield_pct
                    owner._shanzhu_shield_hp = owner._shanzhu_shield_max
                    owner._shanzhu_shield_active = true

                    if hh then
                        hh:AddEffectValueByKey("addSpeedPercent", 15)
                        hh:AddEffectValueByKey("addComDamagePercent", 20)
                    end

                    if owner.components.talker then
                        owner.components.talker:Say("厚皮护盾，启动！")
                    end
                end

                -- 移除护盾buff
                local function remove_shield_buffs()
                    if hh then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 15)
                        hh:ReduceEffectValueByKey("addComDamagePercent", 20)
                    end
                end

                -- 清除护盾
                local function clear_shield(do_burst)
                    if not owner._shanzhu_shield_active then return end
                    owner._shanzhu_shield_active = false
                    owner._shanzhu_shield_hp = 0

                    remove_shield_buffs()

                    if do_burst then
                        -- 破盾回复
                        local cur_hp = owner.components.health and owner.components.health.currenthealth or 0
                        local max_hp = owner.components.health and owner.components.health.maxhealth or 150
                        local lost_hp = max_hp - cur_hp
                        if lost_hp > 0 and owner.components.health then
                            owner.components.health:DoDelta(lost_hp * 0.25, false, nil)
                        end
                        if owner.components.sanity then
                            owner.components.sanity:DoDelta(30)
                        end

                        -- 果香迸发：范围伤害+队友回血
                        local x, y, z = owner.Transform:GetWorldPosition()
                        local ents = _G.TheSim:FindEntities(x, y, z, 4)

                        local dmg = 34
                        if owner.components.combat then
                            dmg = owner.components.combat.defaultdamage or 34
                        end
                        for _, ent in _G.ipairs(ents) do
                            if ent.components.health and not ent.components.health:IsDead() then
                                if ent ~= owner and ent:HasTag("_combat") and not ent:HasTag("player") then
                                    ent.components.health:DoDelta(-dmg, false, "shanzhu_burst")
                                elseif ent:HasTag("player") and ent ~= owner then
                                    local friend_max = ent.components.health.maxhealth or 150
                                    ent.components.health:DoDelta(friend_max * 0.1, false, nil)
                                end
                            end
                        end

                        owner._shanzhu_break_count = (owner._shanzhu_break_count or 0) + 1
                        if owner._shanzhu_break_count % 3 == 0 then
                            say_line(BREAK_LINES)
                        end
                    end

                    if owner._shanzhu_shield_task then
                        owner._shanzhu_shield_task:Cancel()
                    end
                    owner._shanzhu_shield_task = owner:DoTaskInTime(8, function()
                        if owner:IsValid() then
                            apply_shield()
                        end
                    end)
                end

                -- 皇后状态
                local function start_queen_mode()
                    if owner._shanzhu_queen_active then return end
                    owner._shanzhu_queen_active = true

                    if owner._shanzhu_shield_active then
                        local max_hp = owner.components.health and owner.components.health.maxhealth or 150
                        owner._shanzhu_shield_max = max_hp * 0.50
                        owner._shanzhu_shield_hp = owner._shanzhu_shield_max
                    end

                    if hh then
                        hh:AddEffectValueByKey("trueDamageNum", 50)
                    end

                    say_line(QUEEN_LINES)

                    if owner._shanzhu_queen_task then
                        owner._shanzhu_queen_task:Cancel()
                    end
                    owner._shanzhu_queen_task = owner:DoTaskInTime(5, function()
                        if not owner:IsValid() then return end
                        owner._shanzhu_queen_active = false
                        if hh then
                            hh:ReduceEffectValueByKey("trueDamageNum", 50)
                        end
                        if owner._shanzhu_shield_active then
                            local max_hp = owner.components.health and owner.components.health.maxhealth or 150
                            owner._shanzhu_shield_max = max_hp * 0.25
                            if owner._shanzhu_shield_hp > owner._shanzhu_shield_max then
                                owner._shanzhu_shield_hp = owner._shanzhu_shield_max
                            end
                        end
                        if owner.components.talker then
                            owner.components.talker:Say("甜味散去，继续厚皮！")
                        end
                    end)
                end

                -- Hook DoDelta 拦截护盾吸收
                local health = owner.components.health
                if health and not health._shanzhu_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._shanzhu_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and cause ~= "shanzhu_burst" then
                            if _G.Moon_HasEffect(owner, "shanzhu") and owner._shanzhu_shield_active then
                                local damage = -delta
                                if damage >= owner._shanzhu_shield_hp then
                                    local overflow = damage - owner._shanzhu_shield_hp
                                    clear_shield(true)
                                    if overflow > 0 then
                                        return oldDoDelta(self, -overflow, overtime, cause, ...)
                                    end
                                    return oldDoDelta(self, 0, overtime, cause, ...)
                                else
                                    owner._shanzhu_shield_hp = owner._shanzhu_shield_hp - damage
                                    return oldDoDelta(self, 0, overtime, cause, ...)
                                end
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._shanzhu_hooked_dodelta = true
                end

                -- 被攻击后进入战斗状态
                owner._shanzhu_attacked_handler = function(victim, data)
                    if not _G.Moon_HasEffect(owner, "shanzhu") then return end
                    if not owner._shanzhu_in_combat then
                        owner._shanzhu_in_combat = true
                        apply_shield()
                    end
                    if owner._shanzhu_combat_timer then
                        owner._shanzhu_combat_timer:Cancel()
                    end
                    owner._shanzhu_combat_timer = owner:DoTaskInTime(3, function()
                        if owner:IsValid() then
                            owner._shanzhu_in_combat = false
                        end
                    end)
                end
                owner:ListenForEvent("attacked", owner._shanzhu_attacked_handler)

                -- 主动攻击也刷新战斗状态
                owner._shanzhu_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "shanzhu") then return end
                    if not owner._shanzhu_in_combat then
                        owner._shanzhu_in_combat = true
                        apply_shield()
                    end
                    if owner._shanzhu_combat_timer then
                        owner._shanzhu_combat_timer:Cancel()
                    end
                    owner._shanzhu_combat_timer = owner:DoTaskInTime(3, function()
                        if owner:IsValid() then
                            owner._shanzhu_in_combat = false
                        end
                    end)
                end
                owner:ListenForEvent("onattackother", owner._shanzhu_attack_handler)

                -- 皇后周期：每60秒触发
                owner._shanzhu_cycle_task = owner:DoPeriodicTask(60, function()
                    if not owner:IsValid() then return end
                    if not _G.Moon_HasEffect(owner, "shanzhu") then return end
                    start_queen_mode()
                end)

                -- ========================================
                -- 15% 击杀双倍掉落
                -- ========================================
                owner._shanzhu_death_handler = function(victim, data)
                    if not _G.Moon_HasEffect(owner, "shanzhu") then return end
                    local dead = data and data.inst
                    if not dead or not dead:IsValid() then return end
                    if dead:HasTag("player") or not dead:HasTag("_combat") then return end

                    -- 判断是否是玩家击杀（参照genzhe模式）
                    local killer = nil
                    if dead.components.combat and dead.components.combat.lastattacker then
                        killer = dead.components.combat.lastattacker
                    end
                    if not killer or not killer:IsValid() then return end
                    if killer ~= owner then return end

                    if _G.math.random() <= 0.15 then
                        if dead.components.lootdropper then
                            _G.pcall(dead.components.lootdropper.DropLoot, dead.components.lootdropper)
                        end
                        if owner.components.talker then
                            local lines = {"双倍掉落！", "再来一份！", "捏捏，掉俩～"}
                            owner.components.talker:Say(lines[_G.math.random(#lines)])
                        end
                    end
                end
                owner:ListenForEvent("entity_death", owner._shanzhu_death_handler)

                -- ========================================
                -- 小樱角色每日双皮奶
                -- ========================================
                if owner.prefab == "ccs" then
                    local function give_milk()
                        if not _G.Moon_HasEffect(owner, "shanzhu") then return end
                        if not owner:IsValid() or not owner.components.inventory then return end

                        for i = 1, 2 do
                            local milk = _G.SpawnPrefab("ccs_strawberry_food1")
                            if milk then
                                local ok = owner.components.inventory:GiveItem(milk, nil, owner:GetPosition())
                                if not ok and milk:IsValid() then
                                    milk.Transform:SetPosition(owner.Transform:GetWorldPosition())
                                end
                            end
                        end

                        if owner.components.talker then
                            local lines = {
                                "小樱，今天的双皮奶到了～",
                                "新鲜的双皮奶，趁热吃！",
                                "捏～双皮奶给你留了两份！",
                            }
                            owner.components.talker:Say(lines[_G.math.random(#lines)])
                        end
                    end

                    -- 每天送双皮奶（轮询天数变化，必触发）
                    owner._shanzhu_last_day = _G.TheWorld.state.cycles
                    owner._shanzhu_daycheck_task = owner:DoPeriodicTask(60, function()
                        if not _G.Moon_HasEffect(owner, "shanzhu") then return end
                        local current_day = _G.TheWorld.state.cycles
                        if current_day > owner._shanzhu_last_day then
                            owner._shanzhu_last_day = current_day
                            owner:DoTaskInTime(0.5, function()
                                if owner:IsValid() then give_milk() end
                            end)
                        end
                    end)

                    -- 刚装备时首次给（延迟几秒等加载完成）
                    owner:DoTaskInTime(3, function()
                        if owner:IsValid() then give_milk() end
                    end)
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "shanzhu", "Legend_SHANZHU", 1)
            if not _G.Moon_HasEffect(owner, "shanzhu") then
                if owner._shanzhu_shield_active then
                    owner._shanzhu_shield_active = false
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 15)
                        hh:ReduceEffectValueByKey("addComDamagePercent", 20)
                    end
                end
                if owner._shanzhu_queen_active then
                    owner._shanzhu_queen_active = false
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("trueDamageNum", 50)
                    end
                end

                if owner._shanzhu_shield_task then
                    owner._shanzhu_shield_task:Cancel()
                    owner._shanzhu_shield_task = nil
                end
                if owner._shanzhu_queen_task then
                    owner._shanzhu_queen_task:Cancel()
                    owner._shanzhu_queen_task = nil
                end
                if owner._shanzhu_cycle_task then
                    owner._shanzhu_cycle_task:Cancel()
                    owner._shanzhu_cycle_task = nil
                end
                if owner._shanzhu_combat_timer then
                    owner._shanzhu_combat_timer:Cancel()
                    owner._shanzhu_combat_timer = nil
                end
                if owner._shanzhu_daycheck_task then
                    owner._shanzhu_daycheck_task:Cancel()
                    owner._shanzhu_daycheck_task = nil
                end

                if owner._shanzhu_attacked_handler then
                    owner:RemoveEventCallback("attacked", owner._shanzhu_attacked_handler)
                    owner._shanzhu_attacked_handler = nil
                end
                if owner._shanzhu_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._shanzhu_attack_handler)
                    owner._shanzhu_attack_handler = nil
                end
                if owner._shanzhu_death_handler then
                    owner:RemoveEventCallback("entity_death", owner._shanzhu_death_handler)
                    owner._shanzhu_death_handler = nil
                end

                local health = owner.components.health
                if health and health._shanzhu_old_dodelta then
                    health.DoDelta = health._shanzhu_old_dodelta
                    health._shanzhu_old_dodelta = nil
                    health._shanzhu_hooked_dodelta = nil
                end

                owner._shanzhu_hooked = nil
                owner._shanzhu_shield_hp = nil
                owner._shanzhu_shield_max = nil
                owner._shanzhu_break_count = nil
                owner._shanzhu_in_combat = nil
                owner._shanzhu_was_night = nil
                owner._shanzhu_daily_today = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_SHANZHU", 0.01)
end)
