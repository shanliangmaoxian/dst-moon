-- 小月亮 附魔档位显示注入
-- ---------------------------------------------------------------
-- 依据 tier_config.lua 的 TUNING.MOON_ENCHANT_TIERS，统一做两件事：
--  1. 给制作菜单石牌 client_text 加档位前缀（如 "【T2】xxx"）；
--     name 显示名保持原样（不加前缀）；
--  2. 按档位覆盖 client_color（地上飘字颜色），颜色按稀有度直觉：
--     红(T0 专属) > 橙(T1 强力) > 紫(T2 均衡) > 蓝(T3 一般) > 绿(T4 娱乐)。
--
-- 安全性：只改 config 的显示字段（client_text / client_color）。
-- 存档持久化与 FindEffect / 词条匹配均使用 effect_id，不受影响。
-- 在 AddPrefabPostInit("world") 时注入：此时所有 mod（含外部限定附魔）
-- 已完成 AddSpecialEquipEffect 注册，客户端与服务端都会执行（飘字颜色是
-- 客户端逻辑 updateChildText 读的）。
-- ---------------------------------------------------------------

local _G = GLOBAL

if not GLOBAL.Moon_IsHHEnabled() then return end

-- 是否按档位覆盖地上飘字颜色（false 则只加名称前缀）
local ENABLE_TIER_COLOR = true

-- 档位 → 飘字颜色
local TIER_COLORS = {
    T0 = { 1, 0.25, 0.25, 1 },     -- 红：超模
    T1 = { 1, 0.60, 0.10, 1 },     -- 橙：强力
    T2 = { 0.80, 0.40, 1, 1 },     -- 紫：均衡（接近原默认紫）
    T3 = { 0.30, 0.70, 1, 1 },     -- 蓝：一般
    T4 = { 0.40, 0.90, 0.40, 1 },  -- 绿：娱乐
}

-- 档位 → 名称前缀（T0 = 专属获取，不入掉落池）
local TIER_PREFIX = {
    T0 = "【T0】",
    T1 = "【T1】",
    T2 = "【T2】",
    T3 = "【T3】",
    T4 = "【T4】",
}

-- 过滤 HH 框架配方别名键（__recipe__<配方名> 指向同一份 config）
local function is_recipe_alias(key)
    return type(key) == "string" and string.sub(key, 1, 11) == "__recipe__"
end

-- 幂等保护：剥掉已存在的档位前缀，避免重复注入
local function strip_tier_prefix(str)
    if type(str) ~= "string" then return str end
    local stripped = string.gsub(str, "^【T%d】", "")
    return stripped
end

AddPrefabPostInit("world", function(inst)
    local tiers = _G.TUNING and _G.TUNING.MOON_ENCHANT_TIERS
    -- 注意：HH_EQUIP_BUFF_LIST 由 external_imports.lua 注入 mod env（裸全局），
    -- 不在 GLOBAL 里；读 GLOBAL.HH_EQUIP_BUFF_LIST 会触发 strict.lua 报错，
    -- 必须像其他文件一样裸引用。
    if not tiers or not HH_EQUIP_BUFF_LIST then return end

    for effect_id, config in pairs(HH_EQUIP_BUFF_LIST) do
        if type(config) == "table" and not is_recipe_alias(effect_id) then
            local tier = tiers[effect_id]
            if tier then
                -- 1. 制作菜单石牌 client_text 加前缀（name 保持原样，不加前缀）
                local prefix = TIER_PREFIX[tier] or ""
                if type(config.name) == "string" then
                    config.name = prefix .. strip_tier_prefix(config.name)
                end
                -- 2. 按档位覆盖地上飘字颜色
                if ENABLE_TIER_COLOR and TIER_COLORS[tier] then
                    config.client_color = TIER_COLORS[tier]
                end
            end
        end
    end
end)
