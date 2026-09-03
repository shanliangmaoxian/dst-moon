--[[
该模块拓展了原版逻辑，用以支持 AddRecipe2 和 Ingredient2 的新 API。

Ingredient2 兼容 Ingredient，同时增加对自定义数据的支持。

原版签名：Ingredient(ingredienttype, amount, atlas, deconstruct, imageoverride)

Ingredient2 签名：
Ingredient2(ingredienttype: string, amount: number, {
    atlas: string,
    imageoverride: string,
    deconstruct: boolean,

    -- 新 API，在 prefab 匹配后需要额外满足 test_fn 的要求才算作满足要求的材料。
    -- 注意该函数分别在两端执行，建议优先假设在服务器端运行的场景，例如：
    --      if item.components.ccc then
    --          return item.components.ccc:GetXXX()
    --      elseif item.classified then
    --          return item.xxx:value()
    --      else
    --          return ''
    --      end
    test_fn: (item: Instance) => boolean,

    -- 新 API，返回一个控件，将作为 IngredientUI 的子控件展示，主要用于配方详情中需
    -- 要叠加新信息或者任何其它需要额外控件的场景
    overlay: () => Widget,
})

--]]

local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"

local TEMPLATES = require "widgets/redux/templates"

local IngredientUI = require "widgets/ingredientui"

require("util")

local INGREDIENTS_SCALE = 0.75
local TEASER_SCALE_TEXT = 1
local TEASER_SCALE_BTN = 1.5
local TEASER_TEXT_WIDTH = 64 * 3 + 24
local TEASER_BTN_WIDTH = TEASER_TEXT_WIDTH / TEASER_SCALE_BTN

local function Count(item)
    local stackable = item.replica.stackable
    return stackable and stackable:StackSize() or 1
end

local function match_item(test_item, prefab, test_fn)
    local prefab_right = test_item.prefab == prefab
    if test_fn then
        return prefab_right and test_fn(test_item)
    end
    return prefab_right
end

local function crafting_priority_fn(a, b)
    if a.stacksize == b.stacksize then
        return a.slot < b.slot
    end
    return a.stacksize < b.stacksize --smaller stacks first
end

AddPrefabPostInit("container_classified", function(inst)
    function inst.HasItemThatMatches(inst, fn, amount, iscrafting)
        local count = 0
        if inst._itemspreview ~= nil then
            for i = 1, #inst._items do
                local item = inst._itemspreview[i]
                if item ~= nil and fn(item) and not (iscrafting and item:HasTag("nocrafting")) then
                    count = count + Count(item)
                end
            end
        else
            for i, v in ipairs(inst._items) do
                local item = v:value()
                if item ~= nil and fn(item) and not (iscrafting and item:HasTag("nocrafting")) then
                    count = count + Count(item)
                end
            end
        end
        return count >= amount, count
    end
end)

AddPrefabPostInit("inventory_classified", function(inst)
    function inst.HasItemThatMatches(inst, fn, amount, checkallcontainers)
        -- V2C: this is the current assumption, so make it explicit
        local iscrafting = checkallcontainers

        local count = inst._activeitem ~= nil and fn(inst._activeitem) and not (iscrafting and inst._activeitem:HasTag("nocrafting")) and Count(inst._activeitem) or 0

        if inst._itemspreview ~= nil then
            for i = 1, #inst._items do
                local item = inst._itemspreview[i]
                if item ~= nil and fn(item) and not (iscrafting and item:HasTag("nocrafting")) then
                    count = count + Count(item)
                end
            end
        else
            for i, v in ipairs(inst._items) do
                local item = v:value()
                if item ~= nil and item ~= inst._activeitem and fn(item) and
                    not (iscrafting and item:HasTag("nocrafting")) then
                    count = count + Count(item)
                end
            end
        end

        local overflow = inst:GetOverflowContainer()
        if overflow ~= nil then
            local overflowhas, overflowcount = overflow:HasItemThatMatches(fn, amount, checkallcontainers)
            count = count + overflowcount
        end

        if checkallcontainers then
            local inventory_replica = inst and inst._parent and inst._parent.replica.inventory
            local containers = inventory_replica and inventory_replica:GetOpenContainers()

            if containers then
                for container_inst in pairs(containers) do
                    local container = container_inst.replica.container or container_inst.replica.inventory
                    if container and container ~= overflow and not container.excludefromcrafting and
                        (container.IsReadOnlyContainer == nil or not container:IsReadOnlyContainer()) then
                        local containerhas, containercount =
                            container:HasItemThatMatches(fn, amount, checkallcontainers)
                        count = count + containercount
                    end
                end
            end
        end

        return count >= amount, count
    end
end)

AddClassPostConstruct("components/container_replica", function(Component)
    function Component:HasItemThatMatches(fn, amount, checkallcontainers)
        if self.inst.components.inventory ~= nil then
            return self.inst.components.inventory:HasItemThatMatches(fn, amount, checkallcontainers)
        elseif self.classified ~= nil then
            return self.classified:HasItemThatMatches(fn, amount, checkallcontainers)
        else
            return amount <= 0, 0
        end
    end
end)

AddClassPostConstruct("components/inventory_replica", function(Component)
    function Component:HasItemThatMatches(fn, amount, checkallcontainers)
        if self.inst.components.inventory ~= nil then
            return self.inst.components.inventory:HasItemThatMatches(fn, amount, checkallcontainers)
        elseif self.classified ~= nil then
            return self.classified:HasItemThatMatches(fn, amount, checkallcontainers)
        else
            return amount <= 0, 0
        end
    end
end)

AddClassPostConstruct("components/builder_replica", function(Builder)
    function Builder:HasIngredients(recipe)
        if self.inst.components.builder ~= nil then
            return self.inst.components.builder:HasIngredients(recipe)
        elseif self.classified ~= nil then
            if type(recipe) == "string" then
                recipe = GetValidRecipe(recipe)
            end
            if recipe ~= nil then
                if self.classified.isfreebuildmode:value() then
                    return true
                end
                if recipe.getlimitedrecipecount and recipe:getlimitedrecipecount(self.inst) <= 0 then
                    return false
                end
                local cp_inventory = self.inst.replica.inventory
                for i, ingredient in ipairs(recipe.ingredients) do
                    local amount = math.max(1, RoundBiasedUp(ingredient.amount * self:IngredientMod()))

                    if ingredient.data and ingredient.data.test_fn then
                        local has = cp_inventory:HasItemThatMatches(ingredient.data.test_fn, amount, true)
                        if not has then
                            return false
                        end
                    elseif not cp_inventory:Has(ingredient.type, amount, true) then
                        return false
                    end
                end
                for i, v in ipairs(recipe.character_ingredients) do
                    if not self:HasCharacterIngredient(v) then
                        return false
                    end
                end
                for i, v in ipairs(recipe.tech_ingredients) do
                    if not self:HasTechIngredient(v) then
                        return false
                    end
                end
                return true
            end
        end

        return false
    end
end)

AddComponentPostInit("container", function(self)
    function self:GetCraftingIngredient(item, amount, reverse_search_order, test_fn)
        local items = {}
        for i = 1, self.numslots do
            local v = self.slots[i]
            if v ~= nil and match_item(v, item, test_fn) and not v:HasTag("nocrafting") then
                table.insert(items, {
                    item = v,
                    stacksize = v.components.stackable and v.components.stackable:StackSize() or 1,
                    slot = reverse_search_order and (self.numslots - (i - 1)) or i,
                })
            end
        end
        table.sort(items, crafting_priority_fn)

        local crafting_items = {}
        local total_num_found = 0
        for i, v in ipairs(items) do
            local stacksize = math.min(v.stacksize, amount - total_num_found)
            crafting_items[v.item] = stacksize
            total_num_found = total_num_found + stacksize
            if total_num_found >= amount then
                break
            end
        end

        return crafting_items
    end
end)

AddComponentPostInit("inventory", function(self)
    -- 拓展 Inventory:HasItemThatMatches 到支持所有容器递归匹配
    local old_has_item_that_matches = self.HasItemThatMatches
    function self:HasItemThatMatches(fn, amount, checkallcontainers)
        local has, num_found = old_has_item_that_matches(self, fn, amount, checkallcontainers)

        local overflow = self:GetOverflowContainer()

        if checkallcontainers then
            local containers = self.opencontainers

            for container_inst in pairs(containers) do
                local container = container_inst.components.container or container_inst.components.inventory
                if container and container ~= overflow and not container.excludefromcrafting and
                    not container.readonlycontainer then
                    local container_enough, container_found =
                        container:HasItemThatMatches(fn, amount, checkallcontainers)
                    num_found = num_found + container_found
                    has = has or container_enough
                end
            end
        end

        return has, num_found
    end

    function self:GetCraftingIngredient(item, amount, test_fn)
        local overflow = self:GetOverflowContainer()
        local crafting_items = {}
        local total_num_found = 0

        for container_inst in pairs(self.opencontainers) do
            local container = container_inst.components.container or container_inst.components.inventory
            if container and container ~= overflow and not container.excludefromcrafting and not container.readonlycontainer then
                for k, v in pairs(container:GetCraftingIngredient(item, amount - total_num_found, true, test_fn)) do
                    crafting_items[k] = v
                    total_num_found = total_num_found + v
                end
            end
            if total_num_found >= amount then
                return crafting_items
            end
        end

        local items = {}
        for i = 1, self.maxslots do
            local v = self.itemslots[i]
            if v ~= nil and match_item(v, item, test_fn) and not v:HasTag("nocrafting") then
                table.insert(items, {
                    item = v,
                    stacksize = v.components.stackable and v.components.stackable:StackSize() or 1,
                    slot = i,
                })
            end
        end
        table.sort(items, crafting_priority_fn)
        for i, v in ipairs(items) do
            local stacksize = math.min(v.stacksize, amount - total_num_found)
            crafting_items[v.item] = stacksize
            total_num_found = total_num_found + stacksize
            if total_num_found >= amount then
                return crafting_items
            end
        end

        if overflow then
            for k,v in pairs(overflow:GetCraftingIngredient(item, amount - total_num_found, nil, test_fn)) do
                crafting_items[k] = v
                total_num_found = total_num_found + v
            end
            if total_num_found >= amount then
                return crafting_items
            end
        end

        if self.activeitem ~= nil and match_item(self.activeitem, item, test_fn) and not self.activeitem:HasTag("nocrafting") then
            crafting_items[self.activeitem] = math.min(
                self.activeitem.components.stackable and self.activeitem.components.stackable:StackSize() or 1,
                amount - total_num_found
            )
        end

        return crafting_items
    end

end)

local function combine_items_to_ingredients(ingredients, type, items)
    local exists_items_stack = ingredients[type]
    if exists_items_stack then
        ingredients[type] = table.merge(exists_items_stack, items)
    else
        ingredients[type] = items
    end
    return ingredients
end

AddComponentPostInit("builder", function(self)
    function self:HasIngredients(recipe)
        if type(recipe) == "string" then
            recipe = GetValidRecipe(recipe)
        end
        if recipe ~= nil then
            if self.freebuildmode then
                return true
            end
            if recipe.getlimitedrecipecount and recipe:getlimitedrecipecount(self.inst) <= 0 then
                return false
            end
            local cp_inventory = self.inst.components.inventory
            for i, ingredient in ipairs(recipe.ingredients) do
                local amount = math.max(1, RoundBiasedUp(ingredient.amount * self.ingredientmod))

                if ingredient.data and ingredient.data.test_fn then
                    local has = cp_inventory:HasItemThatMatches(ingredient.data.test_fn, amount, true)
                    if not has then
                        return false
                    end
                elseif not cp_inventory:Has(ingredient.type, amount, true) then
                    return false
                end
            end
            for i, v in ipairs(recipe.character_ingredients) do
                if not self:HasCharacterIngredient(v) then
                    return false
                end
            end
            for i, v in ipairs(recipe.tech_ingredients) do
                if not self:HasTechIngredient(v) then
                    return false
                end
            end
            return true
        end
        return false
    end

    function self:GetIngredients(recname)
        local recipe = AllRecipes[recname]
        if recipe then
            local ingredients = {}
            local discounted = false
            for k, ingredient in pairs(recipe.ingredients) do
                if ingredient.amount > 0 then
                    local amt = math.max(1, RoundBiasedUp(ingredient.amount * self.ingredientmod))
                    local test_fn = ingredient.data and ingredient.data.test_fn or nil
                    local items = self.inst.components.inventory:GetCraftingIngredient(ingredient.type, amt, test_fn)
                    ingredients = combine_items_to_ingredients(ingredients, ingredient.type, items)
                    if amt < ingredient.amount then
                        discounted = true
                    end
                end
            end
            return ingredients, discounted
        end
    end
end)

AddGlobalClassPostConstruct("recipe", "Recipe", function(self, name, ingredients, tab, level, placer_or_more_data, ...)
    local more_data = type(placer_or_more_data) == "table" and placer_or_more_data or {}
    self.data = more_data
end)

AddClassPostConstruct("widgets/ingredientui", function(self, atlas, image, quantity, on_hand, has_enough, name, owner, recipe_type, quant_text_scale, ingredient_recipe, data)
    self.data = data
    self.custom_layer = nil
    if data and data.type == "item" and data.ingredient and data.ingredient.data and data.ingredient.data.overlay then
        local control = data.ingredient.data.overlay()
        if control then
            self.custom_layer = self.ing:AddChild(control)
        end
    end
end)

AddClassPostConstruct("widgets/redux/craftingmenu_ingredients", function(self, owner, max_ingredients_wide, recipe, extra_quantity_scale)
    function self:SetRecipe(recipe)
        if self.recipe ~= recipe then
            self.recipe = recipe
        end

        self:KillAllChildren()

        local atlas = resolvefilepath(CRAFTING_ATLAS)

        local owner = self.owner
        local builder = owner.replica.builder
        local inventory = owner.replica.inventory

        self.ingredient_widgets = {}
        local root = self:AddChild(Widget("root"))

        local equippedBody = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
        local showamulet = false
        if equippedBody ~= nil and equippedBody.prefab == "greenamulet" then
            --Check if we're actually discounted by amulet
            for i, v in ipairs(recipe.ingredients) do
                local amt = math.max(1, RoundBiasedUp(v.amount * builder:IngredientMod()))
                if amt < v.amount then
                    showamulet = true
                    break
                end
            end
        end

        local num = (recipe.ingredients ~= nil and #recipe.ingredients or 0)
                    + (recipe.character_ingredients ~= nil and #recipe.character_ingredients or 0)
                    + (recipe.tech_ingredients ~= nil and #recipe.tech_ingredients or 0)
                    + (showamulet and 1 or 0)

        local w = 64
        local div = 10
        local half_div = div * .5
        local offset = 0 --center
        if num > 1 then
            offset = offset - (w *.5 + half_div) * (num - 1)
        end

        self.num_items = num

        local scale = math.min(1, self.max_ingredients_wide / num)
        root:SetScale(scale * INGREDIENTS_SCALE)

        local quant_text_scale = math.max(1, 1/(scale*1.125))
        if self.extra_quantity_scale ~= nil then
            quant_text_scale = quant_text_scale * self.extra_quantity_scale
        end

        self.hint_tech_ingredient = nil

        for i, v in ipairs(recipe.tech_ingredients) do
            if v.type:sub(-9) == "_material" then
                local has, level = builder:HasTechIngredient(v)
                local ing = root:AddChild(IngredientUI(v:GetAtlas(), v:GetImage(), nil, nil, has, STRINGS.NAMES[string.upper(v.type)], owner, v.type, quant_text_scale, nil, {type = 'tech', ingredient = v}))

                if GetGameModeProperty("icons_use_cc") then
                    ing.ing:SetEffect("shaders/ui_cc.ksh")
                end
                if num > 1 and #self.ingredient_widgets > 0 then
                    offset = offset + half_div
                end
                ing:SetPosition(offset, 0)
                offset = offset + w + half_div
                table.insert(self.ingredient_widgets, ing)
                if not has and self.hint_tech_ingredient == nil and not builder:IsFreeBuildMode() then
                    self.hint_tech_ingredient = v.type:sub(1, -10):upper()
                end
            end
        end

        local recipe_data = (self.owner.HUD.controls ~= nil and self.owner.HUD.controls.craftingmenu ~= nil) and owner.HUD.controls.craftingmenu:GetRecipeState(recipe.name) or nil
        local allow_ingredient_crafting = self.hint_tech_ingredient == nil and recipe_data ~= nil and recipe_data.meta.build_state ~= "hint" and recipe_data.meta.build_state ~= "hide"

        for i, ingredient in ipairs(recipe.ingredients) do
            local ing_prefab = ingredient.type
            
            -- 主要改动的地方，增加对 ingredient.data.test_fn 的支持
            local amount = math.max(1, RoundBiasedUp(ingredient.amount * builder:IngredientMod()))
            local has, num_found
            if ingredient.data and ingredient.data.test_fn then
                has, num_found = inventory:HasItemThatMatches(ingredient.data.test_fn, amount, true)
            else
                has, num_found = inventory:Has(ing_prefab, amount, true)
            end

            local ingredient_recipe_data
            if allow_ingredient_crafting then
                ingredient_recipe_data = owner.HUD.controls.craftingmenu:GetRecipeState(ing_prefab)
                if ingredient_recipe_data and
                    ingredient_recipe_data.meta.build_state == "hide" and
                    ingredient_recipe_data.recipe.forward_ingredients
                then
                    --V2C: skill tree might've locked basic ingredient recipe. try the forwarded ingredient recipes.
                    for _, v1 in ipairs(ingredient_recipe_data.recipe.forward_ingredients) do
                        local data1 = owner.HUD.controls.craftingmenu:GetRecipeState(v1)
                        if data1 and data1.meta.build_state ~= "hide" then
                            ing_prefab = v1
                            ingredient_recipe_data = data1
                            break
                        end
                    end
                end
            end

            local ing = root:AddChild(IngredientUI(ingredient:GetAtlas(), ingredient:GetImage(), ingredient.amount ~= 0 and ingredient.amount or nil, num_found, has, STRINGS.NAMES[string.upper(ingredient.type)], owner, ing_prefab, quant_text_scale, ingredient_recipe_data, {type = 'item', ingredient = ingredient}))
            if GetGameModeProperty("icons_use_cc") then
                ing.ing:SetEffect("shaders/ui_cc.ksh")
            end
            if num > 1 and #self.ingredient_widgets > 0 then
                offset = offset + half_div
            end
            ing:SetPosition(offset, 0)
            offset = offset + w + half_div
            table.insert(self.ingredient_widgets, ing)
        end

        for i, v in ipairs(recipe.character_ingredients) do
            --#BDOIG - does this need to listen for deltas and change while menu is open?
            --V2C: yes, but the entire craft tabs does. (will be added there)
            local has, amount = builder:HasCharacterIngredient(v)

            if v.type == CHARACTER_INGREDIENT.HEALTH and owner:HasTag("health_as_oldage") then
                v = Ingredient(CHARACTER_INGREDIENT.OLDAGE, math.ceil(v.amount * TUNING.OLDAGE_HEALTH_SCALE))
            end
            local ing = root:AddChild(IngredientUI(v:GetAtlas(), v:GetImage(), v.amount, amount, has, STRINGS.NAMES[string.upper(v.type)], owner, v.type, quant_text_scale, nil, {type = 'character', ingredient = v}))
            if GetGameModeProperty("icons_use_cc") then
                ing.ing:SetEffect("shaders/ui_cc.ksh")
            end
            if num > 1 and #self.ingredient_widgets > 0 then
                offset = offset + half_div
            end
            ing:SetPosition(offset, 0)
            offset = offset + w + half_div
            table.insert(self.ingredient_widgets, ing)
        end

        if showamulet then
            local amulet_atlas, amulet_img = equippedBody.replica.inventoryitem:GetAtlas(), equippedBody.replica.inventoryitem:GetImage()
            
            local amulet = root:AddChild(IngredientUI(amulet_atlas, amulet_img, 0.2, 0.2, true, STRINGS.GREENAMULET_TOOLTIP, owner, CHARACTER_INGREDIENT.MAX_HEALTH, quant_text_scale, nil, {type = 'amulet', ingredient = v}))
            amulet:SetPosition(offset + half_div, 0)
            table.insert(self.ingredient_widgets, amulet)

            for _, ing in ipairs(self.ingredient_widgets) do
                local glow = ing:AddChild(Image("images/global_redux.xml", "shop_glow.tex"))
                glow:SetTint(.8, .8, .8, 0.4)
                local len = 3
                local function doscale(start) if start then glow:SetScale(0) glow:ScaleTo(0, 0.5, len/2, doscale) else glow:ScaleTo(.5, 0, len/2) end end
                local function animate_glow() 
                    local t = math.random() * 360
                    glow:RotateTo(t, t-360, 3, animate_glow) 
                    doscale(true)
                end
                animate_glow()
            end

        end
    end

    if recipe ~= nil then
        self:SetRecipe(recipe)
    end
end)

AddClassPostConstruct("widgets/recipepopup", function(self)
    function self:Refresh()
        local owner = self.owner
        if owner == nil then
            return false
        end

        local recipe = self.recipe
        local builder = owner.replica.builder
        local inventory = owner.replica.inventory

        local knows = builder:KnowsRecipe(recipe)
        local buffered = builder:IsBuildBuffered(recipe.name)
        local can_build = buffered or builder:HasIngredients(recipe)
        local tech_level = builder:GetTechTrees()
        local should_hint = not knows and ShouldHintRecipe(recipe.level, tech_level) and not CanPrototypeRecipe(recipe.level, tech_level)

        self.skins_list = self:GetSkinsList()

        self.skins_options = self:GetSkinOptions() -- In offline mode, this will return the default option and nothing else

        if #self.skins_options == 1 then
            -- No skins available, so use the original version of this popup
            if self.skins_spinner ~= nil then
                self:BuildNoSpinner(self.horizontal)
            end
        else
            --Skins are available, use the spinner version of this popup
            if self.skins_spinner == nil then
                self:BuildWithSpinner(self.horizontal)
            end

            self.skins_spinner.spinner:SetOptions(self.skins_options)
            local last_skin = Profile:GetLastUsedSkinForItem(recipe.name)
            RecipeTile.sSetImageFromRecipe(self.skins_spinner.spinner.fgimage, recipe, last_skin)
            if last_skin then
                self.skins_spinner.spinner:SetSelectedIndex(self:GetIndexForSkin(last_skin) or 1)
            end
        end

        self.name:SetTruncatedString(STRINGS.NAMES[string.upper(self.recipe.name)] or STRINGS.NAMES[string.upper(self.recipe.product)], TEXT_WIDTH+38, nil, false)
        self.desc:SetMultilineTruncatedString(STRINGS.RECIPE_DESC[string.upper(self.recipe.description or self.recipe.product)], 2, TEXT_WIDTH, self.smallfonts and 40 or 33, true)

        for i, v in ipairs(self.ing) do
            v:Kill()
        end

        self.ing = {}

        local num =
            (recipe.ingredients ~= nil and #recipe.ingredients or 0) +
            (recipe.character_ingredients ~= nil and #recipe.character_ingredients or 0) +
            (recipe.tech_ingredients ~= nil and #recipe.tech_ingredients or 0)
        local w = 64
        local div = 10
        local half_div = div * .5
        local offset = 315 --center
        if num > 1 then
            offset = offset - (w *.5 + half_div) * (num - 1)
        end

        local hint_tech_ingredient = nil

        for i, v in ipairs(recipe.tech_ingredients) do
            if v.type:sub(-9) == "_material" then
                local has, level = builder:HasTechIngredient(v)
                local ing = self.contents:AddChild(IngredientUI(v:GetAtlas(), v:GetImage(), nil, nil, has, STRINGS.NAMES[string.upper(v.type)], owner, v.type, nil, nil, {type = 'tech', ingredient = v}))
                if GetGameModeProperty("icons_use_cc") then
                    ing.ing:SetEffect("shaders/ui_cc.ksh")
                end
                if num > 1 and #self.ing > 0 then
                    offset = offset + half_div
                end
                ing:SetPosition(Vector3(offset, self.skins_spinner ~= nil and 110 or 80, 0))
                offset = offset + w + half_div
                table.insert(self.ing, ing)
                if not has and hint_tech_ingredient == nil then
                    hint_tech_ingredient = v.type:sub(1, -10):upper()
                end
            end
        end

        for i, ingredient in ipairs(recipe.ingredients) do
            -- 主要改动的地方，增加对 ingredient.data.test_fn 的支持
            local amount = math.max(1, RoundBiasedUp(ingredient.amount * builder:IngredientMod()))
            local has, num_found
            if ingredient.data and ingredient.data.test_fn then
                has, num_found = inventory:HasItemThatMatches(ingredient.data.test_fn, amount, true)
            else
                has, num_found = inventory:Has(ingredient.type, amount, true)
            end
            local ing = self.contents:AddChild(IngredientUI(ingredient:GetAtlas(), ingredient:GetImage(), ingredient.amount ~= 0 and ingredient.amount or nil, num_found, has, STRINGS.NAMES[string.upper(ingredient.type)], owner, ingredient.type, nil, nil, {type = 'item', ingredient = ingredient}))
            if GetGameModeProperty("icons_use_cc") then
                ing.ing:SetEffect("shaders/ui_cc.ksh")
            end
            if num > 1 and #self.ing > 0 then
                offset = offset + half_div
            end
            ing:SetPosition(Vector3(offset, self.skins_spinner ~= nil and 110 or 80, 0))
            offset = offset + w + half_div
            table.insert(self.ing, ing)
        end

        for i, v in ipairs(recipe.character_ingredients) do
            --#BDOIG - does this need to listen for deltas and change while menu is open?
            --V2C: yes, but the entire craft tabs does. (will be added there)
            local has, amount = builder:HasCharacterIngredient(v)

            if v.type == CHARACTER_INGREDIENT.HEALTH and owner:HasTag("health_as_oldage") then
                v = Ingredient(CHARACTER_INGREDIENT.OLDAGE, math.ceil(v.amount * TUNING.OLDAGE_HEALTH_SCALE))
            end
            local ing = self.contents:AddChild(IngredientUI(v:GetAtlas(), v:GetImage(), v.amount, amount, has, STRINGS.NAMES[string.upper(v.type)], owner, v.type, nil, nil, {type = 'character', ingredient = v}))
            if GetGameModeProperty("icons_use_cc") then
                ing.ing:SetEffect("shaders/ui_cc.ksh")
            end
            if num > 1 and #self.ing > 0 then
                offset = offset + half_div
            end
            ing:SetPosition(Vector3(offset, self.skins_spinner ~= nil and 110 or 80, 0))
            offset = offset + w + half_div
            table.insert(self.ing, ing)
        end

        local equippedBody = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
        local showamulet = equippedBody and equippedBody.prefab == "greenamulet"

        if should_hint or hint_tech_ingredient ~= nil then
            self.button:Hide()

            local str
            if should_hint then
                local hint_text =
                {
                    ["SCIENCEMACHINE"] = "NEEDSCIENCEMACHINE",
                    ["ALCHEMYMACHINE"] = "NEEDALCHEMYENGINE",
                    ["SHADOWMANIPULATOR"] = "NEEDSHADOWMANIPULATOR",
                    ["PRESTIHATITATOR"] = "NEEDPRESTIHATITATOR",
                    ["CANTRESEARCH"] = "CANTRESEARCH",
                    ["ANCIENTALTAR_HIGH"] = "NEEDSANCIENT_FOUR",
                    ["SPIDERCRAFT"] = "NEEDSSPIDERFRIENDSHIP",
                    ["ROBOTMODULECRAFT"] = "NEEDSCREATURESCANNING",
                    ["BOOKCRAFT"] = "NEEDSBOOKSTATION",
                    ["LUNAR_FORGE"] = "NEEDSLUNARFORGING_TWO",
                    ["SHADOW_FORGE"] = "NEEDSSHADOWFORGING_TWO",
                    ["CARPENTRY_STATION"] = "NEEDSCARPENTRY_TWO",
                    ["CARPENTRY_STATION_STONE"] = "NEEDSCARPENTRY_THREE",
                    ["NEEDSMOONORB_LOW"] = "NEEDSCELESTIAL_ONE",
                    ["NEEDSMOON_ALTAR_FULL"] = "NEEDSCELESTIAL_THREE",
                }
                local prototyper_tree = GetHintTextForRecipe(owner, recipe)
                str = STRINGS.UI.CRAFTING[hint_text[prototyper_tree] or ("NEEDS"..prototyper_tree)]
            else
                str = STRINGS.UI.CRAFTING.NEEDSTECH[hint_tech_ingredient]
            end
            self.teaser:SetScale(TEASER_SCALE_TEXT)
            self.teaser:SetMultilineTruncatedString(str, 3, TEASER_TEXT_WIDTH, 38, true)
            self.teaser:Show()
            showamulet = false
        elseif TheNet:IsServerPaused() then
            self.button:Hide()

            self.teaser:SetScale(TEASER_SCALE_TEXT)
            self.teaser:SetMultilineTruncatedString(STRINGS.UI.CRAFTING.GAMEPAUSED, 3, TEASER_TEXT_WIDTH, 38, true)
            self.teaser:Show()
        else
            self.teaser:Hide()

            local buttonstr =
                (not (knows or recipe.nounlock) and STRINGS.UI.CRAFTING.PROTOTYPE) or
                (buffered and STRINGS.UI.CRAFTING.PLACE) or
                (recipe.actionstr ~= nil and STRINGS.UI.CRAFTING.RECIPEACTION[recipe.actionstr]) or
                STRINGS.UI.CRAFTING.TABACTION[recipe.tab.str] or
                STRINGS.UI.CRAFTING.BUILD

            if TheInput:ControllerAttached() then
                self.button:Hide()
                self.teaser:Show()

                if can_build then
                    self.teaser:SetScale(TEASER_SCALE_BTN)
                    self.teaser:SetTruncatedString(TheInput:GetLocalizedControl(TheInput:GetControllerID(), CONTROL_ACCEPT).." "..buttonstr, TEASER_BTN_WIDTH, 26, true)
                else
                    self.teaser:SetScale(TEASER_SCALE_TEXT)
                    self.teaser:SetMultilineTruncatedString((STRINGS.UI.CRAFTING.TABNEEDSTUFF or {})[recipe.tab.str] or STRINGS.UI.CRAFTING.NEEDSTUFF, 3, TEASER_TEXT_WIDTH, 38, true)
                end
            else
                self.button:Show()
                if self.skins_spinner ~= nil then
                    self.button:SetPosition(320, -155, 0)
                else
                    self.button:SetPosition(320, -105, 0)
                end
                self.button:SetScale(1,1,1)

                self.button:SetText(buttonstr)
                if can_build then
                    self.button:Enable()
                else
                    self.button:Disable()
                end
            end
        end

        if showamulet then
            self.amulet:Show()
        else
            self.amulet:Hide()
        end

        -- update new tags
        if self.skins_spinner then
            self.skins_spinner.spinner:Changed()
        end
    end
end)

GLOBAL.Ingredient2 = Class(Ingredient, function(self, ingredienttype, amount, atlas_or_data, deconstruct, imageoverride)
    local atlas, data
    if type(atlas_or_data) == 'table' then
        data = atlas_or_data
        atlas = data.atlas
        deconstruct = data.deconstruct
        imageoverride = data.imageoverride
    else
        atlas = atlas_or_data
        data = {}
    end

    Ingredient._ctor(self, ingredienttype, amount, atlas, deconstruct, imageoverride)

    self.data = data
end)
