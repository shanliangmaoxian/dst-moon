-- 小月亮 附魔：劳动最光荣
-- 吃烤土豆获得（135保底）
-- 效果：快采、快速制作、烹饪秒出锅、劳动中20%概率获得藏宝图
--
-- 实现原理：
--   秒采/秒交互 → HH框架 fast_act 效果（stategraph钩子）
--   秒砍挖 → 自建 stategraph 钩子 CHOP/MINE → doshortaction
--   秒制作 → builder.buildingtime = 0.001
--   秒出锅 → stewer.StartCooking 前 cooktimemult = 0.001
--   快敲击 → WorkedBy_Internal 100x 工作量
--   藏宝图 → finishedwork / picksomething 事件 20% 概率

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

-- =========================================================
-- 135烤土豆保底计数（独立于 HH 框架，无条件注册）
-- =========================================================
local _ldg_potato_counter = {}

AddPrefabPostInitAny(function(inst2)
    if not _G.TheWorld.ismastersim then return end
    if not inst2:HasTag("player") then return end

    inst2:ListenForEvent("oneat", function(_, data)
        local food = data and data.food
        if not food or not food:IsValid() then return end
        if food.prefab ~= "potato_cooked" then return end

        local userid = inst2.userid
        if not userid then return end

        _ldg_potato_counter[userid] = (_ldg_potato_counter[userid] or 0) + 1
        local count = _ldg_potato_counter[userid]

        if count >= 135 then
            local success, stone = _G.pcall(_G.HHSpawnStoneById, "Legend_LDG")
            if success and stone and inst2.components.inventory then
                inst2.components.inventory:GiveItem(stone, nil, inst2:GetPosition())
                if inst2.components.talker then
                    inst2.components.talker:Say("劳动最光荣！吃了135个烤土豆，获得劳动附魔石！")
                end
            end
            _ldg_potato_counter[userid] = 0
        elseif count % 15 == 0 and inst2.components.talker then
            inst2.components.talker:Say("吃了" .. count .. "个烤土豆，再吃" .. (135 - count) .. "个保底劳动附魔石！")
        end
    end)
end)

-- =========================================================
-- 以下内容需要 HH 附魔框架
-- =========================================================
if not CFG.ENABLE_MORE_ENCHANTS then return end

-- =========================================================
-- 1. workable 组件钩子 — 敲击 100x（保持原版砍树/挖矿动画）
-- =========================================================
AddComponentPostInit("workable", function(self)
    local old_fn = self["WorkedBy_Internal"]
    self["WorkedBy_Internal"] = function(self, worker, numworks, ...)
        if worker and worker:IsValid() and worker:HasTag("player")
                and _G.Moon_HasEffect(worker, "laodong")
                and self["action"] ~= _G.ACTIONS["HAMMER"] then
            numworks = (numworks or 1) * 100
        end
        return old_fn(self, worker, numworks, ...)
    end
end)

-- =========================================================
-- 3. stewer 组件钩子 — 烹饪秒出锅
-- =========================================================
AddComponentPostInit("stewer", function(self)
    local _old_StartCooking = self.StartCooking
    self.StartCooking = function(self, doer)
        if doer and doer:IsValid() and doer:HasTag("player")
                and _G.Moon_HasEffect(doer, "laodong") then
            self.cooktimemult = 0.001
        end
        return _old_StartCooking(self, doer)
    end
end)

-- =========================================================
-- 4. 附魔注册（world 初始化后）
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_LDG", {
        name = "劳动最光荣",
        client_text = "劳动\n光荣",
        desc = "劳动最光荣！\n秒采/秒砍挖/秒制作/秒出锅全加速\n劳动中5%概率获得藏宝图",
        check_desc = "吃烤土豆获得（135保底），劳动最光荣！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "laodong", "Legend_LDG", 1)
            if not owner._ldg_hooked then
                owner._ldg_hooked = true
                local hh = owner.components.hh_player

                -- fast_act — HH框架 stategraph 钩子（加速 PICK/COOK/BUILD/HARVEST）
                if hh then
                    hh:AddEffectValueByKey("fast_act", 1)
                end

                -- 同步 fast_act 到客户端（wilson_client 侧 stategraph 需要）
                _G.pcall(function()
                    if owner.userid then
                        _G.SendModRPCToClient(_G.CLIENT_MOD_RPC["hh_rpc"]["hh_client_value"], owner.userid, "hh_fast_act", true)
                    end
                end)

                -- 秒制作
                if owner.components.builder then
                    owner._ldg_old_buildtime = owner.components.builder.buildingtime or 1
                    owner.components.builder.buildingtime = 0.001
                end

                -- 劳动中20%概率获得藏宝图（完成工作）
                owner._ldg_work_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "laodong") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if math.random() > 0.05 then return end

                    local tally = _G.SpawnPrefab("hh_treasure_tally")
                    if tally and owner.components.inventory then
                        owner.components.inventory:GiveItem(tally, nil, owner:GetPosition())
                        if owner.components.talker then
                            owner.components.talker:Say("劳动最光荣！挖到一张藏宝图！")
                        end
                    end
                end
                owner:ListenForEvent("finishedwork", owner._ldg_work_handler)

                -- 采摘也有概率获得藏宝图
                owner._ldg_pick_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "laodong") then return end
                    if not data or not data.loot then return end
                    if math.random() > 0.05 then return end

                    local tally = _G.SpawnPrefab("hh_treasure_tally")
                    if tally and owner.components.inventory then
                        owner.components.inventory:GiveItem(tally, nil, owner:GetPosition())
                        if owner.components.talker then
                            owner.components.talker:Say("劳动最光荣！采到一张藏宝图！")
                        end
                    end
                end
                owner:ListenForEvent("picksomething", owner._ldg_pick_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "laodong", "Legend_LDG", 1)
            if not _G.Moon_HasEffect(owner, "laodong") then
                local hh = owner.components.hh_player

                if hh then
                    hh:ReduceEffectValueByKey("fast_act", 1)
                end

                -- 同步客户端 fast_act：有其他来源（如传武快速交互）时仍为 true
                _G.pcall(function()
                    if owner.userid then
                        local still_active = hh and hh:HasSpecialEffect("fast_act")
                        _G.SendModRPCToClient(_G.CLIENT_MOD_RPC["hh_rpc"]["hh_client_value"], owner.userid, "hh_fast_act", still_active)
                    end
                end)

                -- 恢复制作速度
                if owner.components.builder and owner._ldg_old_buildtime then
                    owner.components.builder.buildingtime = owner._ldg_old_buildtime
                    owner._ldg_old_buildtime = nil
                end

                -- 移除事件
                if owner._ldg_work_handler then
                    owner:RemoveEventCallback("finishedwork", owner._ldg_work_handler)
                    owner._ldg_work_handler = nil
                end
                if owner._ldg_pick_handler then
                    owner:RemoveEventCallback("picksomething", owner._ldg_pick_handler)
                    owner._ldg_pick_handler = nil
                end

                owner._ldg_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_LDG", 0)
end)
