-- 仅替换星之杖的彩虹宝石伤害回调。小樱工具模块、health和weapon.damage均不改写。
local M = { EFFECT_ID = "Moon_YINGYU_XINGHUI" }
local replacements = {}

function M.HasEffect(inst)
    local hh = inst.components and inst.components.hh_equip
    return inst.prefab == "ccs_starstaff" and hh ~= nil
        and hh:HasEffectByName(M.EFFECT_ID) or false
end

local function GetUpvalue(fn, key)
    for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then return end
        if name == key then return value end
    end
end

local function GetSakura(inst, attacker)
    return M.HasEffect(inst) and attacker and attacker.components
        and attacker.components.ccs_wanly_damage or nil
end

local function MakeDirect(original)
    local utils = GetUpvalue(original, "ccsutl")
    local plant = GetUpvalue(original, "PlantTick")
    if type(utils) ~= "table" or type(plant) ~= "function" then return end
    return function(inst, attacker, target)
        local sakura = GetSakura(inst, attacker)
        if not sakura or type(sakura.ApplyTemporaryDamage) ~= "function" then
            return original(inst, attacker, target)
        end
        if not target or not target:IsValid() or not target.components.health
            or target.components.health:IsDead() then return end

        -- 保留本体DoRealDelta的皮肤特效。
        local skin = inst:GetSkinBuild()
        if skin == "ccs_starstaff_skin_blue" then
            plant(target)
        elseif skin == "ccs_magic_wand3_skins9" then
            local fx = SpawnPrefab("ccs_starhit")
            if fx then
                local x, y, z = target.Transform:GetWorldPosition()
                fx.Transform:SetPosition(x, y + 1.5, z)
            end
        end
        local damage = (inst.opalpreciousgemcount or 0)
            * utils.TTgetentityMultiplier(attacker, target)
        if damage > 0 then
            -- 与本体卡牌盒、樱花技能相同的入口；免疫、击杀及同步由本体处理。
            return sakura:ApplyTemporaryDamage(target, damage)
        end
    end
end

-- 卡牌切换会把onattack替换成blueattack/swordattack等，它们共享DoRealDelta。
-- 只替换这个闭包，不按伤害数值猜测来源，避免误拦截数值相同的卡牌技能。
local function PatchAttack(fn, seen)
    if type(fn) ~= "function" then return fn end
    if replacements[fn] then return replacements[fn] end
    seen = seen or {}
    if seen[fn] then return fn end
    seen[fn] = true
    local direct = MakeDirect(fn)
    if direct then
        replacements[fn] = direct
        replacements[direct] = direct
        return direct
    end
    for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if type(value) == "function" then
            local patched = PatchAttack(value, seen)
            if patched ~= value then debug.setupvalue(fn, i, patched) end
        end
    end
    return fn
end

-- 星之杖发射时的延迟范围伤害也包含四分之一的彩虹宝石加成。
-- 只转换这部分；50点基础值及黄宝石带来的原有范围真伤仍由本体工具结算。
local function PatchSplash(original)
    if type(original) ~= "function" then return original end
    if replacements[original] then return replacements[original] end
    local utils = GetUpvalue(original, "ccsutl")
    local cooldown = GetUpvalue(original, "OnCooldown")
    local goldfx = GetUpvalue(original, "SpawnGoldwingHitFx")
    if not utils or not cooldown or not goldfx then return original end
    local function splash(inst, attacker, target)
        if not GetSakura(inst, attacker) then return original(inst, attacker, target) end
        if not attacker or inst._cdtask ~= nil then return end
        inst._cdtask = inst:DoTaskInTime(3, cooldown)
        if not target or not target:IsValid() then return end
        if inst:GetSkinBuild() == "ccs_starstaff_skin_goldwing" then
            goldfx(target)
        else
            local fx = SpawnPrefab("ccs_star_burst")
            if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
        end
        target:DoTaskInTime(1, function()
            if not target:IsValid() or not attacker:IsValid() or not inst:IsValid() then return end
            local sakura = GetSakura(inst, attacker)
            local mul = utils.TTgetentityMultiplier(attacker, target)
            local x, y, z = target.Transform:GetWorldPosition()
            local ents = TheSim:FindEntities(x, y, z, 4, { "_combat", "_health" },
                { "INLIMBO", "companion", "wall", "abigail", "shadowminion",
                  "player", "playerghost", "erd_doll" })
            for _, victim in ipairs(ents) do
                local health = victim.components.health
                if health and not health:IsDead() and victim.components.combat then
                    local opal = (inst.opalpreciousgemcount or 0) * mul / 4
                    local other = ((inst.yellowgemcount or 0) + 50) * mul / 4
                    if sakura and type(sakura.ApplyTemporaryDamage) == "function" then
                        utils.ttlrealhealth(attacker, victim, -other, attacker.prefab, attacker)
                        if victim:IsValid() and not health:IsDead() and opal > 0 then
                            sakura:ApplyTemporaryDamage(victim, opal)
                        end
                    else
                        utils.ttlrealhealth(attacker, victim, -(other + opal), attacker.prefab, attacker)
                    end
                end
            end
        end)
    end
    replacements[original] = splash
    replacements[splash] = splash
    return splash
end

function M.Install(inst)
    local weapon = inst.components.weapon
    if not weapon or weapon._lmoon_yingyu_hooked then return end
    weapon._lmoon_yingyu_hooked = true
    local old_set = weapon.SetOnAttack
    weapon.SetOnAttack = function(self, fn)
        return old_set(self, PatchAttack(fn))
    end
    weapon:SetOnAttack(weapon.onattack)
    local old_projectile = weapon.SetOnProjectileLaunched
    weapon.SetOnProjectileLaunched = function(self, fn)
        return old_projectile(self, PatchSplash(fn))
    end
    weapon:SetOnProjectileLaunched(weapon.onprojectilelaunched)
end

return M
