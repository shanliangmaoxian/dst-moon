-- 小月亮 物品禁用
-- 被禁用的物品无法制作，已存在的会被移除并退还制作材料
-- 配置格式: {'prefab1','prefab2|30','prefab3'}
--   'prefab'        永久禁用
--   'prefab|30'     禁用 30 个游戏日后自动解禁（起始天数 = 配置生效时,随存档持久化）

local _G = GLOBAL
local ban_items = GetModConfigData("BAN_ITEMS")
-- local ban_items = {"bigpeach|1", "krampus", "spear|1", "raincoat", "moonrockseed"}

-- 空表则跳过
if not ban_items or type(ban_items) ~= "table" or #ban_items == 0 then
    return
end

-- 解析配置: prefab -> { days = number|nil }（nil = 永久禁用）
local ban_map = {}
for _, v in ipairs(ban_items) do
    if type(v) == "string" and v ~= "" then
        local prefab, days_str = v:match("^%s*([^|]+)%s*|%s*(.-)%s*$")
        if prefab then
            prefab = prefab:match("^%s*(.-)%s*$") -- 去首尾空格
            if days_str:match("^%d+$") then
                -- 加载阶段沙箱无裸 tonumber,必须走 _G (见 MODDING_PITFALLS)
                local days = _G.tonumber(days_str)
                if days and days > 0 then
                    ban_map[prefab] = { days = days }
                else
                    ban_map[prefab] = {}
                    print(string.format("[LittleMoon] 警告: BAN_ITEMS 条目 \"%s\" 天数必须大于 0,按永久禁用处理", v))
                end
            else
                ban_map[prefab] = {}
                print(string.format("[LittleMoon] 警告: BAN_ITEMS 条目 \"%s\" 天数无效,按永久禁用处理", v))
            end
        else
            prefab = v:match("^%s*(.-)%s*$")
            if prefab and prefab ~= "" then
                ban_map[prefab] = {}
            end
        end
    end
end

local function SpawnLootPrefab(owner, name, sum, pos)
    local sp = GLOBAL.SpawnPrefab(name)
    if not sp then return end
    if sp.components.stackable then
        local m = sp.components.stackable.maxsize
        local c = sum - m
        sp.components.stackable:SetStackSize(c > 0 and m or sum)
        if owner then
            if owner.components.inventory then
                owner.components.inventory:GiveItem(sp)
            end
        elseif pos then
            sp.Transform:SetPosition(pos.x, 0, pos.z)
        end
        while c > 0 do
            local loot = GLOBAL.SpawnPrefab(name)
            if c > m then
                loot.components.stackable:SetStackSize(m)
            else
                loot.components.stackable:SetStackSize(c)
            end
            if owner then
                if owner.components.inventory then
                    owner.components.inventory:GiveItem(loot)
                end
            elseif pos then
                loot.Transform:SetPosition(pos.x, 0, pos.z)
            end
            c = c - m
        end
    else
        if owner then
            if owner.components.inventory then
                owner.components.inventory:GiveItem(sp)
            end
        elseif pos then
            sp.Transform:SetPosition(pos.x, 0, pos.z)
        end
        for i = 2, sum do
            local extra = GLOBAL.SpawnPrefab(name)
            if owner then
                if owner.components.inventory then
                    owner.components.inventory:GiveItem(extra)
                end
            elseif pos then
                extra.Transform:SetPosition(pos.x, 0, pos.z)
            end
        end
    end
end

local function GetRecipeIngredients(prefab)
    for _, v in pairs(GLOBAL.AllRecipes) do
        if v.product == prefab then
            return v.ingredients, v.name
        end
    end
    return nil
end

local function RemoveAndRefund(inst)
    local owner = inst.components.inventoryitem and inst.components.inventoryitem.owner
    local pos = inst:GetPosition()
    local ingred = GetRecipeIngredients(inst.prefab)
    inst:Remove()
    if ingred then
        local ingredientmod = owner and owner.components and owner.components.builder
            and owner.components.builder.ingredientmod or 1
        for _, v in pairs(ingred) do
            SpawnLootPrefab(owner, v.type, math.ceil(v.amount * ingredientmod), pos)
        end
    end
end

-- 禁用的配方名称集合（用于UI提示）
local banned_recipe_names = {}
-- 屏蔽前保存的配方原 canbuild（解禁时恢复）
local saved_canbuild = {}

-- 解禁: 从禁用集合移除 + 恢复配方
local function Unban(prefab)
    ban_map[prefab] = nil
    local _, recipe_name = GetRecipeIngredients(prefab)
    if recipe_name then
        banned_recipe_names[recipe_name] = nil
        local rec = GLOBAL.AllRecipes[recipe_name]
        if rec then
            rec.canbuild = saved_canbuild[recipe_name]
            saved_canbuild[recipe_name] = nil
        end
    end
    print(string.format("[LittleMoon] 物品 %s 禁用期已过，自动解禁", prefab))
end

if GLOBAL.TheNet:GetIsServer() then
    -- 限时禁用: 挂世界组件记录起始天数, 每个游戏日检查是否到期待解禁
    AddPrefabPostInit("world", function(world)
        if not world.ismastersim then return end
        if not world.components.moon_ban_timer then
            world:AddComponent("moon_ban_timer")
        end
        local timer = world.components.moon_ban_timer

        local function CheckUnban()
            local start_cycle = timer:GetStartCycle() -- 首次调用时记录起始天数
            local cycle = world.state.cycles or start_cycle
            for prefab, info in pairs(ban_map) do
                if info.days and cycle >= start_cycle + info.days then
                    Unban(prefab)
                end
            end
        end

        -- 天数变化时检查; 延迟一帧保证世界状态就绪
        world:DoTaskInTime(0, CheckUnban)
        world:WatchWorldState("cycles", CheckUnban)
    end)

    -- 物品生成即移除
    -- DoTaskInTime(0.05): 延迟一帧给调用方留足时间操作，只执行一次
    for prefab in pairs(ban_map) do
        local p = prefab -- 显式捕获, 防 Lua 5.1 for 闭包陷阱
        AddPrefabPostInit(p, function(inst)
            if not ban_map[p] then return end -- 已过禁用期
            inst:DoTaskInTime(0.05, function(inst)
                if inst.components and inst.components.container then
                    if inst.components.container:IsEmpty() then
                        RemoveAndRefund(inst)
                    else
                        inst.components.container:DropEverything()
                    end
                else
                    RemoveAndRefund(inst)
                end
            end)
        end)
    end

    -- 屏蔽配方
    AddPlayerPostInit(function(inst)
        if not GLOBAL.TheWorld then return end
        for prefab in pairs(ban_map) do
            local _, recipe_name = GetRecipeIngredients(prefab)
            if recipe_name then
                banned_recipe_names[recipe_name] = true
                local rec = GLOBAL.AllRecipes[recipe_name]
                if rec then
                    if saved_canbuild[recipe_name] == nil then
                        saved_canbuild[recipe_name] = rec.canbuild
                    end
                    rec.canbuild = function() return false, "BANNEDITEM" end
                end
            end
        end
    end)
end

-- UI 提示
GLOBAL.STRINGS.CHARACTERS.GENERIC.ACTIONFAIL.BUILD.BANNEDITEM = "此物品已被禁用"

AddClassPostConstruct("widgets/redux/craftingmenu_details", function(self)
    local oldUpdate = self.UpdateBuildButton
    function self:UpdateBuildButton(from_pin_slot)
        oldUpdate(self, from_pin_slot)
        if not self.data or not self.data.recipe then return end
        if banned_recipe_names[self.data.recipe.name] then
            local teaser = self.build_button_root.teaser
            teaser:SetSize(20)
            teaser:UpdateOriginalSize()
            teaser:SetMultilineTruncatedString("此物品已被禁用", 2, (self.panel_width / 2) * 0.8, nil, false, true)
            teaser:Show()
            self.build_button_root.button:Hide()
        end
    end
end)

print(string.format("[LittleMoon] 已加载物品禁用列表，共 %d 个物品", #ban_items))
