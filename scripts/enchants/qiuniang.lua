-- 小月亮 附魔：建家能手穹酱！
-- 联动小穹 Mod (workshop-1638724235)，仅小穹(sora)角色装备生效
--  免疫生物仇恨 | 脱战99%免伤（主动攻击后失效，脱战5秒恢复）
--  永久建造材料减半 | 快速动作 | san值快速恢复 | 每日1份奇异甜食
-- 获取：小穹累计食用10份奇异甜食
-- 穹酱！穹酱！

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- 依赖小穹 Mod：未启用时整份文件不注册（附魔与解锁计数器一起跳过）
if not _G.Moon_IsModEnabled("workshop-1638724235") then return end

local EFFECT_ID  = "Legend_QIUNIANG"
local EFFECT_KEY = "qiuniang"

local CHAR_PREFAB  = "sora"         -- 小穹角色 prefab
local CHAR_TAG     = "sora"         -- 小穹角色 tag
local FOOD_PREFAB  = "sora_yaojing" -- 奇异甜食
local UNLOCK_COUNT = 10             -- 累计食用份数门槛

local COMBAT_TIMEOUT   = 5      -- 脱战判定：最后一次战斗行为后多少秒算脱战
local DAMAGE_TAKEN_MOD = 0.01   -- 脱战免伤99%：只吃 1% 伤害
local BUILD_MOD        = 0.5    -- 建造材料减半（原版 builder.ingredientmod 语义）
local SANITY_RATE      = 8      -- san 恢复速率加成（点/秒，叠加在原版 rate 上）
local SANITY_KEY       = "建家能手穹酱"
local DAILY_FOOD_COUNT = 1      -- 每日发放份数

-- external_imports.lua 用 pcall 导入，失败时拿到的是错误字符串，必须做类型判断
local hh_utils = type(HH_UTILS) == "table" and HH_UTILS or nil

-- =========================================================
-- 战斗状态
-- =========================================================
-- 用"最后一次战斗行为的时间戳"判定脱战：主动攻击(onattackother)或被
-- 攻击(health DoDelta 负值)都刷新时间戳，距最后一次超过 COMBAT_TIMEOUT
-- 即视为脱战，此时才享受免伤与免疫仇恨。
local function is_out_of_combat(owner)
    local last = owner._qiuniang_last_combat
    return last == nil or (_G.GetTime() - last) >= COMBAT_TIMEOUT
end

-- 进入/刷新战斗状态：立刻撤掉 notarget，让被攻击的怪物能正常反击
-- （notarget 只挡"主动仇恨"，挡不住 combat:GetAttacked 的反击逻辑，
--   所以这里必须显式移除，否则玩家打怪怪不还手，与"主动攻击效果失效"不符）
local function mark_combat(owner)
    owner._qiuniang_last_combat = _G.GetTime()
    if owner._qiuniang_notarget then
        owner._qiuniang_notarget = nil
        owner:RemoveTag("notarget")
    end
end

-- =========================================================
-- 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "建家能手穹酱！",
        client_text = "建家\n穹酱",
        -- 百分号用全角：本附魔没有 value_range，HH 不会对 desc 做 string.format，
        -- 写半角 %% 会原样显示成两个百分号
        desc = "免疫生物仇恨\n脱战99％免伤(主动攻击后失效,脱战5秒恢复)\n建造材料永久减半+快速动作\nsan值快速恢复,每日1份奇异甜食\n仅小穹可使用",
        check_desc = "穹酱！穹酱！",
        ui_from_desc = "小穹累计食用10份奇异甜食",
        obtain_desc = "小穹累计食用10份奇异甜食",
        obtains = {}, -- 空表：不进入任何掉落池/附魔卷轴，打宝藏坎普斯也不掉
        can_add = false,
        only_one = true,
        is_special = true, -- 从 HH 三池(普通/优质/稀有)全部排除
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(equip)
            return true, "满足条件"
        end,

        on_equip_fn = function(inst, owner, value)
            -- 仅小穹生效：其他角色附了也是白板（不注册效果、不挂钩子）
            if owner.prefab ~= CHAR_PREFAB and not owner:HasTag(CHAR_TAG) then
                if owner.components.talker then
                    owner.components.talker:Say("只有小穹才能驾驭穹酱的力量！")
                end
                return
            end

            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if owner._qiuniang_hooked then return end
            owner._qiuniang_hooked = true

            local hh = owner.components.hh_player

            -- 快速动作：HH 内建 fast_act 效果（大幅提升采集/建造/烹饪/交易速度）
            -- 服务端加效果值，客户端靠 HHClientRpc 同步，否则动画与服务端不同步
            if hh then
                hh:AddEffectValueByKey("fast_act", 1)
                if hh_utils then hh_utils:HHClientRpc(owner, "hh_fast_act", true) end
            end

            -- 永久建造材料减半：走原版 builder.ingredientmod（绿护符同款机制），
            -- GetIngredients / HasIngredients 都会按它折算材料数量
            local builder = owner.components.builder
            if builder and builder.ingredientmod == 1 then
                builder.ingredientmod = BUILD_MOD
                owner._qiuniang_ingredientmod = true
            end

            -- san值快速恢复
            local sanity = owner.components.sanity
            if sanity then
                sanity.externalmodifiers:SetModifier(SANITY_KEY, SANITY_RATE)
            end

            -- ==============================================
            -- 免伤钩子：脱战吃 1% 伤害，被击中即进入战斗
            -- 判定顺序很关键——先按"受击前"的状态算免伤，再标记战斗，
            -- 这样脱战状态被偷袭的第一下也能吃到免伤
            -- ==============================================
            local health = owner.components.health
            if health and not health._qiuniang_hooked_dodelta then
                local old_DoDelta = health.DoDelta
                health._qiuniang_old_dodelta = old_DoDelta
                health.DoDelta = function(self, delta, overtime, cause, ...)
                    if delta < 0 and owner:IsValid()
                        and _G.Moon_HasEffect(owner, EFFECT_KEY)
                    then
                        if is_out_of_combat(owner) then
                            delta = delta * DAMAGE_TAKEN_MOD
                        end
                        mark_combat(owner)
                    end
                    return old_DoDelta(self, delta, overtime, cause, ...)
                end
                health._qiuniang_hooked_dodelta = true
            end

            -- 主动攻击同样算进入战斗
            owner._qiuniang_attack_handler = function(attacker, data)
                if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                mark_combat(owner)
            end
            owner:ListenForEvent("onattackother", owner._qiuniang_attack_handler)

            -- ==============================================
            -- 每秒巡检：脱战后补回 notarget（免疫生物仇恨）
            -- notarget 是原版 brain 通用的 CANT_TAGS，绝大多数怪物靠它
            -- 过滤仇恨目标，因此这是最省事也最贴近原版语义的实现
            -- ==============================================
            owner._qiuniang_tick_task = owner:DoPeriodicTask(1, function()
                if not owner:IsValid() or not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                if is_out_of_combat(owner) then
                    if not owner._qiuniang_notarget then
                        owner._qiuniang_notarget = true
                        owner:AddTag("notarget")
                    end
                elseif owner._qiuniang_notarget then
                    owner._qiuniang_notarget = nil
                    owner:RemoveTag("notarget")
                end
            end)

            -- ==============================================
            -- 每日1份奇异甜食
            -- ==============================================
            local function give_daily_food()
                if not owner:IsValid() or not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                if not owner.components.inventory then return end
                for _ = 1, DAILY_FOOD_COUNT do
                    local food = _G.SpawnPrefab(FOOD_PREFAB)
                    if food then
                        if not owner.components.inventory:GiveItem(food, nil, owner:GetPosition())
                            and food:IsValid() then
                            food.Transform:SetPosition(owner.Transform:GetWorldPosition())
                        end
                    end
                end
                if owner.components.talker then
                    owner.components.talker:Say("穹酱！今天的奇异甜食到啦～")
                end
            end

            -- 当天已发过（含刚装备/轮询）则不重复发，脱下重穿也不刷
            local function try_give_daily()
                if not owner:IsValid() or not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                local current_day = _G.TheWorld.state.cycles
                if owner._qiuniang_last_day ~= nil
                    and current_day <= owner._qiuniang_last_day then
                    return
                end
                owner._qiuniang_last_day = current_day
                give_daily_food()
            end

            owner._qiuniang_daycheck_task = owner:DoPeriodicTask(60, function()
                if not owner:IsValid() or not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                local current_day = _G.TheWorld.state.cycles
                if owner._qiuniang_last_day == nil
                    or current_day > owner._qiuniang_last_day then
                    owner._qiuniang_last_day = current_day
                    owner:DoTaskInTime(0.5, function()
                        if owner:IsValid() then give_daily_food() end
                    end)
                end
            end)

            -- 刚装备时补发（延迟几秒等加载完成）；当天已发过则跳过
            owner:DoTaskInTime(3, function()
                if owner:IsValid() then try_give_daily() end
            end)
        end,

        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("fast_act", 1)
                    if hh_utils then
                        hh_utils:HHClientRpc(owner, "hh_fast_act",
                            hh:HasSpecialEffect("fast_act") and true or false)
                    end
                end

                -- 只有确实由本附魔改过 ingredientmod 才还原，避免踩到绿护符等其他来源
                if owner._qiuniang_ingredientmod then
                    local builder = owner.components.builder
                    if builder then builder.ingredientmod = 1 end
                    owner._qiuniang_ingredientmod = nil
                end

                local sanity = owner.components.sanity
                if sanity then
                    sanity.externalmodifiers:RemoveModifier(SANITY_KEY)
                end

                local health = owner.components.health
                if health and health._qiuniang_old_dodelta then
                    health.DoDelta = health._qiuniang_old_dodelta
                    health._qiuniang_old_dodelta = nil
                    health._qiuniang_hooked_dodelta = nil
                end

                if owner._qiuniang_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._qiuniang_attack_handler)
                    owner._qiuniang_attack_handler = nil
                end
                if owner._qiuniang_tick_task then
                    owner._qiuniang_tick_task:Cancel()
                    owner._qiuniang_tick_task = nil
                end
                if owner._qiuniang_daycheck_task then
                    owner._qiuniang_daycheck_task:Cancel()
                    owner._qiuniang_daycheck_task = nil
                end

                if owner._qiuniang_notarget then
                    owner._qiuniang_notarget = nil
                    owner:RemoveTag("notarget")
                end

                owner._qiuniang_last_combat = nil
                owner._qiuniang_hooked = nil
            end
        end,
    })

    -- 不走小月亮的精英/Boss 掉落池
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0)
end)

-- =========================================================
-- 使用限制：穹酱附魔石只能由小穹本人使用
-- HH 的 AddEquipEffect 只校验附魔台容器内容（25 号格装备 / 26 号格附魔石），
-- 完全不看使用者是谁，所以必须在组件层包一层：
-- 26 号格是本附魔石且使用者不是小穹时直接拒绝，附魔石不会被消耗
-- =========================================================
AddComponentPostInit("hh_player", function(self)
    local old_AddEquipEffect = self.AddEquipEffect
    if type(old_AddEquipEffect) ~= "function" then return end

    self.AddEquipEffect = function(self, ...)
        local container = self.ui_container and self.ui_container.components.container
        local stone = container and container:GetItemInSlot(26)
        if stone and stone.prefab == "hh_effect_stone" and stone.hh_effect == EFFECT_ID then
            local doer = self.inst
            if not doer or (doer.prefab ~= CHAR_PREFAB and not doer:HasTag(CHAR_TAG)) then
                return false, "只有小穹才能使用穹酱的附魔石！"
            end
        end
        return old_AddEquipEffect(self, ...)
    end
end)

-- =========================================================
-- 解锁通道：小穹累计食用 UNLOCK_COUNT 份奇异甜食 → 掉落附魔石
-- 独立于 HH 框架，与装备/附魔无关，纯玩家维度的计数
-- =========================================================
AddPlayerPostInit(function(inst)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then return end
    -- 附魔石由 HH 框架生成，HH 未启用时无需挂计数器
    if not _G.Moon_IsHHEnabled() then return end

    -- 计数跨存档持久化：换世界/重载后玩家实体重建，不存就会归零重刷
    local old_OnSave = inst.OnSave
    inst.OnSave = function(inst, data)
        if old_OnSave then old_OnSave(inst, data) end
        data._qiuniang_eaten = inst._qiuniang_eaten
        data._qiuniang_unlocked = inst._qiuniang_unlocked
        data._qiuniang_last_day = inst._qiuniang_last_day
    end
    local old_OnLoad = inst.OnLoad
    inst.OnLoad = function(inst, data)
        if old_OnLoad then old_OnLoad(inst, data) end
        if data then
            if data._qiuniang_eaten ~= nil then inst._qiuniang_eaten = data._qiuniang_eaten end
            if data._qiuniang_unlocked ~= nil then inst._qiuniang_unlocked = data._qiuniang_unlocked end
            if data._qiuniang_last_day ~= nil then inst._qiuniang_last_day = data._qiuniang_last_day end
        end
    end

    inst:ListenForEvent("oneat", function(inst, data)
        -- 只统计小穹自己吃的
        if inst.prefab ~= CHAR_PREFAB and not inst:HasTag(CHAR_TAG) then return end
        if inst._qiuniang_unlocked then return end
        local food = data and data.food
        if not food or food.prefab ~= FOOD_PREFAB then return end

        inst._qiuniang_eaten = (inst._qiuniang_eaten or 0) + 1

        if inst._qiuniang_eaten < UNLOCK_COUNT then
            if inst.components.talker then
                inst.components.talker:Say(
                    string.format("穹酱！奇异甜食 %d/%d", inst._qiuniang_eaten, UNLOCK_COUNT))
            end
            return
        end

        -- 达标：发一颗附魔石（只发一次，之后永久标记已解锁）
        inst._qiuniang_unlocked = true
        local ok, stone = _G.pcall(_G.HHSpawnStoneById, EFFECT_ID)
        if ok and stone then
            if inst.components.inventory then
                inst.components.inventory:GiveItem(stone, nil, inst:GetPosition())
            elseif stone.Transform then
                stone.Transform:SetPosition(inst.Transform:GetWorldPosition())
            end
        end
        if inst.components.talker then
            inst.components.talker:Say("穹酱！穹酱！建家能手穹酱到手啦！")
        end
    end)
end)
