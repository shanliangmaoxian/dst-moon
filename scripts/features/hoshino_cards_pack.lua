-- 小月亮 小鸟卡包堆叠（联动 workshop-3398290914）
-- 基础之理/神秘核心/窥秘权柄/最高神秘 是同一个 prefab：hoshino_item_cards_pack，
-- 靠原 mod 的 Type 事件换名/换卡组/换外观。本文件让它支持堆叠：
--   1) 同类型才可堆叠（窥秘权柄不和最高神秘混堆）
--   2) 拆堆时恢复卡组数据（引擎拆堆是重新 SpawnPrefab，实例数据会丢）
--   3) 开包只消耗 1 个（原版开包逻辑会 Remove 整个实体，堆叠时不拆会误删整堆）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_HOSHINO_CARDS_PACK then return end
if not _G.Moon_IsModEnabled("workshop-3398290914") then return end

local PACK_PREFAB = "hoshino_item_cards_pack"
local STACK_MAX = 40

--- 堆叠身份键：类型优先，无名无类型的按显示名区分（基础之理 / 神秘核心）
local function GetStackKey(inst)
    if inst._moon_pack_type ~= nil then
        return tostring(inst._moon_pack_type)
    end
    return "name:" .. tostring(inst.name or inst.prefab)
end

AddPrefabPostInit(PACK_PREFAB, function(inst)
    if not TheWorld.ismastersim then
        return
    end

    --- 堆叠组件
    if inst.components.stackable == nil then
        inst:AddComponent("stackable")
    end
    inst.components.stackable.maxsize = STACK_MAX

    --- 记录卡包类型（Type 事件是原 mod 的预设外观机制，窥秘权柄/最高神秘触发）
    inst:ListenForEvent("Type", function(inst, pack_type)
        inst._moon_pack_type = pack_type
        inst.components.hoshino_data:Set("moon_pack_type", pack_type)
    end)

    --- 存档兼容：老档没有 moon_pack_type，从外观数据推断
    inst.components.hoshino_data:AddOnLoadFn(function()
        if inst._moon_pack_type ~= nil then
            return
        end
        local saved = inst.components.hoshino_data:Get("moon_pack_type")
        if saved ~= nil then
            inst._moon_pack_type = saved
            return
        end
        local display = inst.components.hoshino_data:Get("display_data") or {}
        local key = tostring(display.imagename or display.bank or "")
        if string.find(key, "supreme_mystery", 1, true) then
            inst._moon_pack_type = "hoshino_item_cards_pack_supreme_mystery"
        elseif string.find(key, "authority_to_unveil_secrets", 1, true) then
            inst._moon_pack_type = "hoshino_item_cards_pack_authority_to_unveil_secrets"
        end
    end)

    --- 同类型才允许堆叠（官方 stackable 自带的逐实例判定钩子）
    inst.stackable_CanStackWithFn = function(a, b)
        return GetStackKey(a) == GetStackKey(b)
    end

    --- 拆堆时给新拆出的包恢复卡组数据
    inst.components.stackable:SetOnDeStack(function(new_inst, stack)
        if stack._moon_pack_type ~= nil then
            new_inst:PushEvent("Type", stack._moon_pack_type)
        end
    end)

    --- 开包前拆堆：只消耗 1 个，剩余留在堆上
    local workable_com = inst.components.hoshino_com_workable
    local old_active_fn = workable_com ~= nil and workable_com.acive_fn or nil
    if workable_com ~= nil and old_active_fn ~= nil then
        workable_com:SetOnWorkFn(function(inst, doer)
            local cards_sys = doer.components.hoshino_cards_sys
            local selecting = false
            if cards_sys ~= nil then
                -- 工作坊版组件只有 selectting 字段（新版 demo 才封装出 IsCardsSelecting 方法）
                if type(cards_sys.IsCardsSelecting) == "function" then
                    selecting = cards_sys:IsCardsSelecting() and true or false
                else
                    selecting = cards_sys.selectting and true or false
                end
            end
            if selecting then
                -- 正在选卡：原逻辑只会强制重开界面（return false 不消耗），不能拆堆
                return old_active_fn(inst, doer)
            end
            if inst.components.stackable ~= nil and inst.components.stackable:IsStack() then
                -- 从堆里拆出 1 个来开，堆上余量原样留在背包
                inst = inst.components.stackable:Get(1)
            end
            return old_active_fn(inst, doer)
        end)
    end
end)

--- 选完卡牌后自动关闭平板
--- 复用原 mod 白卡/金卡同款机制：服务端经 hoshino_com_rpc_event 下发
--- "hoshino_event.inspect_hud_force_close"，客户端平板在 ThePlayer 上监听此事件触发 pad_close
AddComponentPostInit("hoshino_cards_sys", function(self)
    local inst = self.inst
    if not TheWorld.ismastersim then
        return
    end
    inst:ListenForEvent("hoshino_cards_sys.card_activated", function()
        local rpc = inst.components ~= nil and inst.components.hoshino_com_rpc_event or nil
        if rpc ~= nil then
            rpc:PushEvent("hoshino_event.inspect_hud_force_close")
        end
    end)
end)
