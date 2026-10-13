-- 小月亮：调整 HH 附魔强化 mod 的极品附魔石爆率
-- 原理：HH 所有掉落概率集中在 TUNING.HH_CHANCE_CONFIG（main/hh_config.lua 写入），
--       且 hh_monster.lua 在每次怪物死亡时实时读取该表（非加载时缓存），
--       因此世界初始化后覆写即可生效，无需改动 HH mod 本体。
-- 范围：仅 elite_monster_stone（精英 5% 默认）与 boss_monster_stone（boss 20% 默认）。
-- 配置值 0 = 跟随 HH 默认，不修改。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

-- mod env 是白名单表，tonumber 不在其中，须经 _G 调用；配置值本身已是数字，此处仅防旧档字符串
local function to_rate(v)
    if type(v) == "number" then return v end
    return v ~= nil and _G.tonumber(v) or 0
end

local ELITE_RATE = to_rate(CFG.HH_ELITE_STONE_RATE)
local BOSS_RATE = to_rate(CFG.HH_BOSS_STONE_RATE)

if ELITE_RATE <= 0 and BOSS_RATE <= 0 then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsModEnabled("workshop-3096210166") then return end

    local chance = _G.TUNING ~= nil and _G.TUNING.HH_CHANCE_CONFIG ~= nil
        and _G.TUNING.HH_CHANCE_CONFIG.GIF_CHANCE or nil
    if chance == nil then
        print("[小月亮] 极品附魔石爆率调整：未找到 HH_CHANCE_CONFIG，跳过")
        return
    end

    if ELITE_RATE > 0 then
        chance.elite_monster_stone = ELITE_RATE
    end
    if BOSS_RATE > 0 then
        chance.boss_monster_stone = BOSS_RATE
    end
    print(string.format("[小月亮] 极品附魔石爆率：精英 %d%%，boss %d%%",
        math.floor((ELITE_RATE > 0 and ELITE_RATE or chance.elite_monster_stone) * 100 + 0.5),
        math.floor((BOSS_RATE > 0 and BOSS_RATE or chance.boss_monster_stone) * 100 + 0.5)))
end)
