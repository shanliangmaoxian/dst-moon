-- 小月亮 附魔：幸运橙汁 (#31)
-- 获取：#roll 掷骰子，连续两次80+获得（冷却10秒，期望~25次）
-- 效果：掉落/采集/收锅/制作30%，击杀额外掉落30%，幸运值+10

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

-- =========================================================
-- Part 1: 组件钩子（编译期注册，运行期检测附魔是否存在）
-- =========================================================

-- 1a. 烹饪锅收锅概率双倍 (20%)
AddComponentPostInit("stewer", function(self)
    local _old_Harvest = self.Harvest
    self.Harvest = function(self, harvester, ...)
        local product = _old_Harvest(self, harvester, ...)
        if harvester and harvester:IsValid() and harvester:HasTag("player")
                and _G.Moon_HasEffect and _G.Moon_HasEffect(harvester, "xingyunchengzhi") then
            if math.random() <= 0.30 then
                local product_prefab = self.product
                if product_prefab then
                    local extra = _G.SpawnPrefab(product_prefab)
                    if extra and harvester.components.inventory then
                        harvester.components.inventory:GiveItem(extra)
                        if harvester.components.talker then
                            harvester.components.talker:Say("幸运橙汁！多一份出锅！")
                        end
                    end
                end
            end
        end
        return product
    end
end)

-- 1b. 制作物品概率不消耗材料 (15%)
AddComponentPostInit("builder", function(self)
    local _old_RemoveIngredients = self.RemoveIngredients
    self.RemoveIngredients = function(self, ingredients, recname, discounted)
        if self.inst:HasTag("player")
                and _G.Moon_HasEffect and _G.Moon_HasEffect(self.inst, "xingyunchengzhi") then
            if math.random() <= 0.30 then
                if self.inst.components.talker then
                    self.inst.components.talker:Say("幸运橙汁！没消耗材料！")
                end
                -- 不消耗物品材料，但仍然需要处理角色材料（血量/理智消耗）
                local recipe = _G.AllRecipes[recname]
                if recipe then
                    for k, v in pairs(recipe.character_ingredients) do
                        if v.type == _G.CHARACTER_INGREDIENT.HEALTH then
                            self.inst:PushEvent("consumehealthcost")
                            self.inst.components.health:DoDelta(-v.amount, false, "builder", true, nil, true)
                        elseif v.type == _G.CHARACTER_INGREDIENT.MAX_HEALTH then
                            self.inst:PushEvent("consumehealthcost")
                            self.inst.components.health:DeltaPenalty(v.amount)
                        elseif v.type == _G.CHARACTER_INGREDIENT.SANITY then
                            self.inst.components.sanity:DoDelta(-v.amount)
                        end
                    end
                end
                self.inst:PushEvent("consumeingredients", { discounted = discounted })
                return
            end
        end
        return _old_RemoveIngredients(self, ingredients, recname, discounted)
    end
end)

-- =========================================================
-- Part 2: HH 附魔框架依赖
-- =========================================================
if not CFG.ENABLE_MORE_ENCHANTS then return end

-- =========================================================
-- 2a. 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_XYCZ", {
        name = "幸运橙汁",
        client_text = "幸运\n橙汁",
        desc = "幸运女神的眷顾！\n击杀/采集/收锅/制作30%额外奖励，幸运值+10",
        check_desc = "聊天输入 #roll 掷骰子，连续两次80+即可获得",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "xingyunchengzhi", "Legend_XYCZ", 1)
            if not owner._xycz_hooked then
                owner._xycz_hooked = true

                -- 幸运值+10（走原版 luckuser 组件）
                if not owner.components.luckuser then
                    owner:AddComponent("luckuser")
                end
                owner.components.luckuser:SetLuckSource(10, "Legend_XYCZ")

                -- 击杀敌人20%概率额外掉落
                owner._xycz_kill_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "xingyunchengzhi") then return end
                    local victim = data and data.victim
                    if not victim or not victim:IsValid() then return end
                    if math.random() <= 0.30 then
                        if victim.components.lootdropper then
                            local x, y, z = victim.Transform:GetWorldPosition()
                            _G.pcall(victim.components.lootdropper.DropLoot, victim.components.lootdropper, _G.Vector3(x, y, z))
                            if owner.components.talker then
                                owner.components.talker:Say("幸运橙汁！额外掉落！")
                            end
                        end
                    end
                end
                owner:ListenForEvent("killed", owner._xycz_kill_handler)

                -- 采集15%概率双倍产出（采摘/收获）
                owner._xycz_pick_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "xingyunchengzhi") then return end
                    if data and data.loot and math.random() <= 0.30 then
                        if data.loot.prefab and owner.components.inventory then
                            local extra = _G.SpawnPrefab(data.loot.prefab)
                            if extra then
                                owner.components.inventory:GiveItem(extra, nil, owner:GetPosition())
                            end
                        end
                    end
                end
                owner:ListenForEvent("picksomething", owner._xycz_pick_handler)

                -- 砍树/挖矿 15%概率双倍产出
                owner._xycz_work_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "xingyunchengzhi") then return end
                    local target = data and data.target
                    if target and target:IsValid() and target.components.lootdropper and math.random() <= 0.30 then
                        _G.pcall(target.components.lootdropper.DropLoot, target.components.lootdropper)
                    end
                end
                owner:ListenForEvent("finishedwork", owner._xycz_work_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "xingyunchengzhi", "Legend_XYCZ", 1)
            if not _G.Moon_HasEffect(owner, "xingyunchengzhi") then
                -- 移除幸运值（原版 luckuser 组件）
                if owner.components.luckuser then
                    owner.components.luckuser:RemoveLuckSource("Legend_XYCZ")
                end

                if owner._xycz_kill_handler then
                    owner:RemoveEventCallback("killed", owner._xycz_kill_handler)
                    owner._xycz_kill_handler = nil
                end
                if owner._xycz_pick_handler then
                    owner:RemoveEventCallback("picksomething", owner._xycz_pick_handler)
                    owner._xycz_pick_handler = nil
                end
                if owner._xycz_work_handler then
                    owner:RemoveEventCallback("finishedwork", owner._xycz_work_handler)
                    owner._xycz_work_handler = nil
                end
                owner._xycz_hooked = nil
            end
        end,
    })

    -- 不通过 Boss 掉落获取（仅骰子获取）
    _G.Moon_RegisterEnchantDrop("Legend_XYCZ", 0)
end)

-- =========================================================
-- 2b. 骰子系统：Player PostInit（网络变量 + 持久化）
-- =========================================================
AddPlayerPostInit(function(inst)
    -- 网络变量：客户端 UI 读取（net_byte 存值，net_bool 做触发器）
    inst._xycz_dice_last = _G.net_byte(inst.GUID, "little_moon.xycz_dice_last", "xyczdicedirty")
    inst._xycz_dice_current = _G.net_byte(inst.GUID, "little_moon.xycz_dice_cur", "xyczdicedirty")
    inst._xycz_dice_updated = _G.net_bool(inst.GUID, "little_moon.xycz_dice_updated", "xyczdicedirty")

    if not _G.TheWorld.ismastersim then return end

    -- 服务端：初始化
    inst._xycz_dice_last:set(0)
    inst._xycz_dice_current:set(0)
    inst._xycz_dice_updated:set(false)
    inst._xycz_last_roll_value = 0       -- 服务端上一次有效投掷值
    inst._xycz_next_roll_time = 0         -- 冷却时间戳

    -- 持久化：保存/加载骰子状态
    local _old_OnSave = inst.OnSave
    inst.OnSave = function(inst, data)
        if _old_OnSave then _old_OnSave(inst, data) end
        data._xycz_last_roll = inst._xycz_last_roll_value or 0
    end
    local _old_OnLoad = inst.OnLoad
    inst.OnLoad = function(inst, data)
        if _old_OnLoad then _old_OnLoad(inst, data) end
        if data and data._xycz_last_roll then
            inst._xycz_last_roll_value = data._xycz_last_roll
            if inst._xycz_dice_last then
                inst._xycz_dice_last:set(data._xycz_last_roll)
            end
        end
    end
end)

-- =========================================================
-- 2c. 骰子 RPC 处理（服务端）
-- =========================================================
function _G.Moon_DoDiceRoll(player)
    if not player or not player:IsValid() then return end
    if player:HasTag("playerghost") then return end

    local now = _G.GetTime()
    if player._xycz_next_roll_time and now < player._xycz_next_roll_time then
        if player.components.talker then
            local remaining = math.ceil(player._xycz_next_roll_time - now)
            player.components.talker:Say("骰子还在冷却中..." .. remaining .. "秒")
        end
        return
    end
    player._xycz_next_roll_time = now + 10

    local roll = math.random(1, 100)
    local last_roll = player._xycz_last_roll_value or 0

    if player._xycz_dice_last then
        player._xycz_dice_last:set(last_roll)
    end
    if player._xycz_dice_current then
        player._xycz_dice_current:set(roll)
    end
    if player._xycz_dice_updated then
        player._xycz_dice_updated:set(not player._xycz_dice_updated:value())
    end

    if last_roll >= 80 and roll >= 80 then
        local success, stone = _G.pcall(_G.HHSpawnStoneById, "Legend_XYCZ")
        if success and stone and player.components.inventory then
            player.components.inventory:GiveItem(stone, nil, player:GetPosition())
            if player.components.talker then
                player.components.talker:Say("恭喜！连续两次80+！获得幸运橙汁附魔石！")
            end
        end
        player._xycz_last_roll_value = 0
        if player._xycz_dice_last then
            player._xycz_dice_last:set(0)
        end
    else
        player._xycz_last_roll_value = roll
        if player.components.talker then
            if roll >= 80 then
                player.components.talker:Say("掷出" .. roll .. "点！80以上！再掷一次80+就能获得幸运橙汁！")
            else
                player.components.talker:Say("掷出" .. roll .. "点")
            end
        end
    end
end

-- =========================================================
-- 2d. 聊天指令 #roll 备用触发（调试用）
-- =========================================================
local _Old_Networking_Say_XYCZ = _G.Networking_Say
_G.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
    if _G.TheWorld and _G.TheWorld.ismastersim then
        -- 拦截 #roll 指令：执行骰子但不显示消息
        if message == "#roll" then
            _G.Moon_DoDiceRoll(_G.UserToPlayer(userid))
            return
        end
        -- -- 调试：查看当前幸运值
        -- if message == "#luck" then
        --     local player = _G.UserToPlayer(userid)
        --     if player and player.components.talker then
        --         if player.components.luckuser then
        --             local luck = player.components.luckuser:GetLuck()
        --             player.components.talker:Say("[调试] 当前幸运值: " .. tostring(luck))
        --         else
        --             player.components.talker:Say("[调试] luckuser 组件不存在")
        --         end
        --     end
        --     return
        -- end
    end
    if _Old_Networking_Say_XYCZ then
        _Old_Networking_Say_XYCZ(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
    end
end
