-- 小月亮 附魔：无限星力
-- 联动魔卡少女小樱mod(workshop-3043439883)
-- 获取：仅小樱(ccs)消耗160点魔力炼成「无限星力附魔石」(配方 ccs_legend_stone)
-- 效果：仅限小樱佩戴附魔卡牌盒，无限魔力，封印后摇及回/无/风/力牌施法速度×100

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local RECIPE_NAME = "ccs_legend_stone"
local PRODUCT = "lmoon_effect_stone_infinite_star"
local EFFECT_ID = "Legend_infinite_star"
local EFFECT_NAME = "infinite_star"
local CRAFT_MAGIC_COST = 160

-- =========================================================
-- 无限魔力：消耗入口拦截
-- =========================================================
-- 该玩家是否有"无限星力"效果
local function HasInfiniteStar(inst)
    if inst == nil or inst.prefab ~= "ccs" then return false end
    local inventory = _G.TheWorld.ismastersim and inst.components.inventory
        or inst.replica.inventory
    if inventory == nil then return false end
    for _, slot in pairs(_G.EQUIPSLOTS) do
        local box = inventory:GetEquippedItem(slot)
        if box ~= nil and box.prefab == "ccs_card_box" then
            if _G.TheWorld.ismastersim then
                local hh = box.components.hh_equip
                if hh ~= nil and hh:HasEffectByName(EFFECT_ID) then return true end
            elseif box._moon_infinite_star ~= nil and box._moon_infinite_star:value() then
                return true
            end
        end
    end
    return false
end

-- 需要"真实付费"的配方：产物是小月亮自己的附魔石（炼石不能被无限魔力免单，
-- 否则可以无限刷石）。小樱本体那些消耗魔力的配方（物品/卡牌）不受影响。
local function NeedsRealMagicCost(recname)
    if recname == RECIPE_NAME then return true end
    local recipe = _G.AllRecipes ~= nil and _G.AllRecipes[recname] or nil
    local product = recipe ~= nil and recipe.product or nil
    if type(product) ~= "string" then return false end
    return product:find("^lmoon_effect_stone_") ~= nil
        or product:find("^moon_effect_stone_") ~= nil
end

AddComponentPostInit("ccs_magic", function(self)
    local old_DoDelta = self.DoDelta
    function self:DoDelta(amount, ...)
        local inst = self.inst
        -- 本石配方必须实扣160魔力，不受卡牌减耗影响。
        if type(amount) == "number" and amount < 0
            and inst ~= nil and inst._moon_infinite_star_crafting
        then
            local previous = self.consume_bf
            self.consume_bf = 0
            local results = { _G.pcall(old_DoDelta, self, amount, ...) }
            self.consume_bf = previous
            if not results[1] then _G.error(results[2]) end
            return _G.unpack(results, 2)
        end
        -- 与原 consume_bf = 1 语义一致：消耗归零但仍走完 DoDelta（保留事件推送）；
        -- 制作炼石付款期间（_moon_crafting_magic_pay）不抵消，保证真实扣费
        if type(amount) == "number" and amount < 0
            and not (inst ~= nil and inst._moon_crafting_magic_pay)
            and HasInfiniteStar(inst)
        then
            amount = 0
        end
        return old_DoDelta(self, amount, ...)
    end
end)

-- 制作付费放行：本体已在 prefab 构造函数里包过一层 RemoveIngredients（扣魔力），
-- AddPrefabPostInit 晚于构造函数，这里包到的是本体那层 → 我们位于更外层。
AddPrefabPostInit("ccs", function(inst)
    if not _G.TheWorld.ismastersim then return end
    local builder = inst.components.builder
    if builder == nil then return end
    local old_RemoveIngredients = builder.RemoveIngredients
    builder.RemoveIngredients = function(self, ingredients, recname, ...)
        if not NeedsRealMagicCost(recname) then
            return old_RemoveIngredients(self, ingredients, recname, ...)
        end
        local previous = inst._moon_crafting_magic_pay
        local previous_star = inst._moon_infinite_star_crafting
        inst._moon_crafting_magic_pay = true
        inst._moon_infinite_star_crafting = recname == RECIPE_NAME
        local results = { _G.pcall(old_RemoveIngredients, self, ingredients, recname, ...) }
        inst._moon_crafting_magic_pay = previous
        inst._moon_infinite_star_crafting = previous_star
        if not results[1] then _G.error(results[2]) end
        return _G.unpack(results, 2)
    end
end)

-- =========================================================
-- 词条注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end
    -- 检测小樱mod
    if not _G.Moon_IsModEnabled("workshop-3043439883") then return end

    _G.AddSpecialEquipEffect(EFFECT_ID, {
        name = "无限星力",
        client_text = "无限\n星力",
        desc = "无限魔力(魔力消耗全免)\n封印后摇速度×100\n回牌、无牌、风牌、力牌施法速度×100\n仅小樱佩戴卡牌盒生效",
        check_desc = "星之力，取之不尽～",
        obtains = {},
        obtain_desc = "仅小樱消耗160魔力制作",
        -- 不声明 recipes：不写 __recipe__ 别名键，与其他附魔一致。
        can_add = false,
        only_one = true,
        is_special = true,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(equip_inst)
            return equip_inst ~= nil and equip_inst.prefab == "ccs_card_box",
                "只能附魔在小樱的卡牌盒上"
        end,

        start_fn = function(equip_inst)
            if equip_inst._moon_infinite_star ~= nil then
                equip_inst._moon_infinite_star:set(true)
            end
        end,
        end_fn = function(equip_inst)
            if equip_inst._moon_infinite_star ~= nil then
                equip_inst._moon_infinite_star:set(false)
            end
        end,

        on_equip_fn = function(equip_inst, owner, value)
            if owner ~= nil and owner.prefab ~= "ccs" then
                if owner.components.talker then
                    owner.components.talker:Say("星星之力只回应小樱的呼唤！")
                end
                return
            end
            _G.Moon_AddEffect(owner, EFFECT_NAME, EFFECT_ID, 1)
        end,

        un_equip_fn = function(equip_inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_NAME, EFFECT_ID, 1)
        end,
    })

    -- 仅制作获取，不注册随机掉落。
end)

-- =========================================================
-- 炼成配方：消耗160小樱魔力 → 产物 lmoon_effect_stone_infinite_star
-- （dummy prefab，由 lmoon_effect_stones.lua 的 OnBuiltFn 生成真正的
--   HH 附魔石并注入 Legend_infinite_star 效果）
-- =========================================================
STRINGS.NAMES.CCS_LEGEND_STONE = "无限星力附魔石"
STRINGS.RECIPE_DESC.CCS_LEGEND_STONE = "消耗160点小樱魔力，炼成无限星力附魔石。"
STRINGS.NAMES.LMOON_EFFECT_STONE_INFINITE_STAR = "无限星力附魔石"

AddSimPostInit(function()
    if not _G.Moon_IsHHEnabled() then return end
    if not _G.Moon_IsModEnabled("workshop-3043439883") then return end
    if _G.AllRecipes[RECIPE_NAME] ~= nil then return end
    -- 注意：AddRecipe2 是 mod 环境注入的 modutil 函数，不在 GLOBAL 里，
    -- 必须裸写（GLOBAL.AddRecipe2 会触发 strict.lua "not declared"）
    AddRecipe2(
        RECIPE_NAME,
        {
            _G.Ingredient(
                _G.CHARACTER_INGREDIENT.CCS_MAGIC,
                CRAFT_MAGIC_COST,
                "images/inventoryimages/ccs_magic.xml"
            ),
        },
        _G.TECH.NONE,
        {
            product = PRODUCT,
            builder_tag = "ccs",
            no_deconstruction = true,
            atlas = "images/hh_icon/hh_items.xml",
            image = "hh_effect_stone.tex",
            -- 本体的材料检查用 math.ceil(current)，159.x 魔力也会判定通过，
            -- 这里按实际值卡住，避免"魔力不够也能炼"
            canbuild = function(recipe, builder)
                local magic = builder.components.ccs_magic
                if builder.prefab ~= "ccs" or magic == nil then
                    return false, "仅小樱可以炼成"
                end
                if magic.current < CRAFT_MAGIC_COST then
                    return false, "魔力不足"
                end
                return true
            end,
        },
        { "CCS_TAB1" }
    )
end)

-- 卡牌盒附魔及客机同步；已有的附魔槽位设置不作改动。
AddPrefabPostInit("ccs_card_box", function(inst)
    if not _G.Moon_IsHHEnabled() then return end
    inst._moon_infinite_star = _G.net_bool(inst.GUID, "moon.infinite_star")
    inst:AddTag("hh_equip")
    if not _G.TheWorld.ismastersim then return end
    if inst.components.hh_equip == nil then
        inst:AddComponent("hh_equip")
        inst.components.hh_equip:SetMaxGemLimit(3)
        inst.components.hh_equip:SetEquipBuffLimit(3)
    end
    inst:DoTaskInTime(0, function(box)
        box._moon_infinite_star:set(box.components.hh_equip:HasEffectByName(EFFECT_ID))
    end)
end)

-- 第2帧封印生效，后续时间缩为1/100。复制状态以保留未附魔时的原动作。
local function InstallSealState(sg)
    local original = sg.states.ccs_seal_magic
    local handler = _G.ACTIONS.CCS_SEAL and sg.actionhandlers[_G.ACTIONS.CCS_SEAL]
    if original == nil or handler == nil then return end
    local state = _G.setmetatable({}, _G.getmetatable(original))
    for key, value in pairs(original) do state[key] = value end
    state.name = "moon_infinite_star_seal"
    if sg.name == "wilson_client" then
        state.server_states = { [_G.hash(state.name)] = true }
    end
    local action_time = 2 * _G.FRAMES
    local end_time = action_time
    state.timeline = {}
    for _, event in ipairs(original.timeline or {}) do
        local copy = _G.setmetatable({}, _G.getmetatable(event))
        for key, value in pairs(event) do copy[key] = value end
        if copy.time > action_time then
            copy.time = action_time + (copy.time - action_time) / 100
        end
        end_time = _G.math.max(end_time, copy.time)
        state.timeline[#state.timeline + 1] = copy
    end
    state.onenter = function(inst, ...)
        original.onenter(inst, ...)
        inst.sg:SetTimeout(end_time + _G.FRAMES)
    end
    state.onexit = function(inst, ...)
        if original.onexit ~= nil then original.onexit(inst, ...) end
        inst.AnimState:Resume()
        inst.AnimState:SetDeltaTimeMultiplier(1)
    end
    sg.states[state.name] = state
    local destination = handler.deststate
    handler.deststate = function(inst, action, ...)
        local result = destination
        if type(destination) == "function" then result = destination(inst, action, ...) end
        if result == "ccs_seal_magic" and HasInfiniteStar(inst) then return state.name end
        return result
    end
end
AddStategraphPostInit("wilson", InstallSealState)
AddStategraphPostInit("wilson_client", InstallSealState)

-- 四张指定卡牌的整段施法加速；不改变卡牌效果、冷却或其他施法。
local FAST_CAST_CARDS = {
    ccs_cards_10 = true, -- 回牌
    ccs_cards_29 = true, -- 无牌
    ccs_cards_5 = true,  -- 风牌
    ccs_cards_13 = true, -- 力牌
}

local function InstallCardCast(sg)
    for _, name in ipairs({ "castspell", "quickcastspell" }) do
        local state = sg.states[name]
        if state ~= nil then
            local old_onenter = state.onenter
            local old_onexit = state.onexit
            local timeline = state.timeline or {}
            state.onenter = function(inst, ...)
                local action = inst:GetBufferedAction()
                local card = action ~= nil and action.invobject or nil
                local fast = action ~= nil and action.action == _G.ACTIONS.CASTAOE
                    and card ~= nil and FAST_CAST_CARDS[card.prefab] == true
                    and HasInfiniteStar(inst)
                local mem = inst.sg.statemem
                mem._moon_card_cast_fast = fast
                mem._moon_card_cast_done = fast and {} or nil
                old_onenter(inst, ...)
                if fast and inst.sg.statemem == mem then
                    inst.AnimState:SetDeltaTimeMultiplier(100)
                end
            end
            state.onexit = function(inst, ...)
                if inst.sg.statemem._moon_card_cast_fast then
                    inst.AnimState:SetDeltaTimeMultiplier(1)
                end
                if old_onexit ~= nil then return old_onexit(inst, ...) end
            end

            local function RunFastEvent(inst, index)
                local done = inst.sg.statemem._moon_card_cast_done
                if done ~= nil and not done[index] then
                    done[index] = true
                    timeline[index].fn(inst)
                end
            end
            state.timeline = {}
            for index, event in ipairs(timeline) do
                state.timeline[#state.timeline + 1] = _G.TimeEvent(event.time / 100, function(inst)
                    RunFastEvent(inst, index)
                end)
                state.timeline[#state.timeline + 1] = _G.TimeEvent(event.time, function(inst)
                    if not inst.sg.statemem._moon_card_cast_fast then event.fn(inst) end
                end)
            end
            _G.table.sort(state.timeline, function(a, b) return a.time < b.time end)

            -- 100倍后可能一帧内播完；确保动画结束时施法事件已且仅已执行一次。
            local finished = state.events and state.events.animqueueover
            if finished ~= nil then
                state.events.animqueueover = _G.EventHandler("animqueueover", function(inst, ...)
                    if inst.sg.statemem._moon_card_cast_fast and inst.AnimState:AnimDone() then
                        local mem = inst.sg.statemem
                        for index in ipairs(timeline) do
                            RunFastEvent(inst, index)
                            if inst.sg.statemem ~= mem then return end
                        end
                    end
                    return finished.fn(inst, ...)
                end)
            end
        end
    end
end
AddStategraphPostInit("wilson", InstallCardCast)
AddStategraphPostInit("wilson_client", InstallCardCast)
