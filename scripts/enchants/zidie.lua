-- 小月亮 附魔：紫蝶
-- 身化蝶影，以假乱真！
-- 攻击5%几率召唤蝶影分身（启迪之冠小虚影 alterguardianhat_projectile，继承50%属性，最多2个）
-- 分身像启迪之冠一样冲向玩家当前目标攻击。分身存在时本体伤害+30%
-- 移速永久+20%
-- 小虚影不会破坏建筑，也不会攻击玩家

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- ======== 分身辅助函数 ========

-- 清理已消亡的分身
local function cleanup_clones(owner)
    if not owner._zidie_clones then
        owner._zidie_clones = {}
        return
    end
    local alive = {}
    for _, data in ipairs(owner._zidie_clones) do
        if data.entity and data.entity:IsValid() then
            table.insert(alive, data)
        end
    end
    owner._zidie_clones = alive
end

-- 检查是否有存活分身
local function has_alive_clones(owner)
    cleanup_clones(owner)
    return #(owner._zidie_clones or {}) > 0
end

-- 蝶影固定召唤小虚影（alterguardianhat_projectile，启迪之冠的月之虚影弹）
-- 像启迪之冠一样：出现后冲向玩家当前目标攻击，随后自行消散
local function spawn_clone(owner, target)
    local x, y, z = owner.Transform:GetWorldPosition()

    -- 固定召唤启迪之冠小虚影
    local clone = _G.SpawnPrefab("alterguardianhat_projectile")
    if not clone then return nil end

    -- 定位：玩家和目标的中间偏目标方向，加随机偏移
    local tx, ty, tz = target.Transform:GetWorldPosition()
    local sx = x + (tx - x) * 0.4 + math.random(-2, 2)
    local sz = z + (tz - z) * 0.4 + math.random(-2, 2)
    clone.Transform:SetPosition(sx, y, sz)

    -- 蝴蝶特效登场
    -- 紫蝶化外观：紫色半透明！
    -- 虚影的可见主体是 blobhead(大头)，主实体+大头都要染色
    if clone.AnimState then
        clone.AnimState:SetMultColour(0.7, 0.3, 1, 0.75)
        clone.AnimState:SetAddColour(0.3, 0, 0.5, 0)
    end
    if clone.blobhead and clone.blobhead.AnimState then
        clone.blobhead.AnimState:SetMultColour(0.7, 0.3, 1, 0.75)
    end
    -- 虚影自带的透明组件会把大头刷回白色，替换成紫色版，保住染色
    if clone.components.transparentonsanity then
        clone.components.transparentonsanity.onalphachangedfn = function(cinst, a)
            if cinst.blobhead and cinst.blobhead.AnimState then
                cinst.blobhead.AnimState:OverrideMultColour(0.7, 0.3, 1, a)
            end
        end
        clone.components.transparentonsanity:ForceUpdate()
    end

    -- 配置：像启迪之冠一样攻击玩家当前目标
    if clone.components.follower then
        clone.components.follower:SetLeader(owner)
    end
    clone._focustarget = target                          -- 优先打玩家当前目标
    if clone.SetTargetPosition then
        clone:SetTargetPosition(_G.Vector3(tx, ty, tz))  -- 朝目标方向飞
    end
    -- 伤害继承50%攻击力
    if clone.components.combat then
        clone.components.combat.defaultdamage = (owner.components.combat and owner.components.combat.defaultdamage or 10) * 0.5
    end
    -- 保险：绝不攻击玩家
    local orig_find = clone.find_attack_victim
    clone.find_attack_victim = function(cinst)
        local t = orig_find and orig_find(cinst)
        if t and t:IsValid() and t:HasTag("player") then
            return nil
        end
        return t
    end

    -- 兜底清理（正常0.4秒内自行消散，此任务防卡住）
    clone:DoTaskInTime(8, function()
        if clone:IsValid() then
            clone:Remove()
        end
    end)

    return clone
end

-- ======== 注册附魔 ========

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    _G.AddSpecialEquipEffect("Legend_ZIDIE", {
        name = "紫蝶",
        client_text = "紫\n蝶",
        desc = "攻击5%几率召唤小虚影(最多2个)\n继承50%属性,自动追击,本体伤害+30%\n移速永久+20%,不可被玩家攻击",
        check_desc = "身化蝶影，以假乱真！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,

        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "zidie", "Legend_ZIDIE", 1)
            if not owner._zidie_hooked then
                owner._zidie_hooked = true
                owner._zidie_clones = {}

                -- 永久移速+20%
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("addSpeedPercent", 20)
                end

                -- 监听攻击事件：5%几率召唤分身
                owner._zidie_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "zidie") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target == owner then return end
                    if math.random() > 0.05 then return end

                    local had_clones = has_alive_clones(owner)
                    if #owner._zidie_clones >= 2 then return end

                    local clone = spawn_clone(owner, target)
                    if clone then
                        table.insert(owner._zidie_clones, { entity = clone })
                        if not had_clones and hh then
                            hh:AddEffectValueByKey("addComDamagePercent", 30)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._zidie_attack_handler)

                -- 每2秒检查分身状态
                owner._zidie_check_task = owner:DoPeriodicTask(2, function()
                    if not _G.Moon_HasEffect(owner, "zidie") then return end
                    if not owner:IsValid() then return end
                    local had_clones = #(owner._zidie_clones or {})
                    cleanup_clones(owner)
                    local now_clones = #(owner._zidie_clones or {})
                    if had_clones > 0 and now_clones == 0 then
                        local hhp = owner.components.hh_player
                        if hhp then
                            hhp:ReduceEffectValueByKey("addComDamagePercent", 30)
                        end
                    end
                end)
            end
        end,

        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "zidie", "Legend_ZIDIE", 1)
            if not _G.Moon_HasEffect(owner, "zidie") then
                if owner._zidie_check_task then
                    owner._zidie_check_task:Cancel()
                    owner._zidie_check_task = nil
                end
                if owner._zidie_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._zidie_attack_handler)
                    owner._zidie_attack_handler = nil
                end

                cleanup_clones(owner)
                for _, data in ipairs(owner._zidie_clones or {}) do
                    if data.entity and data.entity:IsValid() then
                        data.entity:Remove()
                    end
                end
                owner._zidie_clones = nil

                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addSpeedPercent", 20)
                    hh:ReduceEffectValueByKey("addComDamagePercent", 30)
                end
                owner._zidie_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_ZIDIE", 0.01)
end)
