-- 小月亮 附魔：新史低 (#Legend_XSD)
-- 获取：精英/Boss 概率掉落（低权重）
-- 效果：装备时，在「欧皇模拟器」(workshop-3273001012) 的商店购物打 5~9 折
--       附魔石属性值 5~9 → 折扣 = (14-属性值)/10（属性值越高折扣越好：5→9折，9→5折满值）
-- 前置：需同时开启 3273001012（幸运模拟器/欧皇模拟器）mod 才生效
--
-- 双端注册说明：
--   * AddPrefabPostInit("world") 仅服务端触发（小月亮惯例）
--   * AddPlayerPostInit 两端都触发；客户端靠它补注册词条 + 折扣 hook，
--     否则客户端商店 UI 显示原价（且余额判断会按原价置灰按钮，误伤打折购买）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- =========================================================
-- Part 1: 组件钩子（编译期注册，运行期检测附魔是否存在）
-- =========================================================

-- 1a. MoneyManager:OnBuy 包装改在 AddPlayerPostInit（玩家创建时）执行：
--     晚于所有 mod 的 AddComponentPostInit，确保包装位于调用链最外层，
--     能拦截到「黑店」等绕过 getShopItemFinalPrice 的写死价扣款并退还新史低差价。

-- =========================================================
-- Part 2: 词条配置（服务端/客户端共用，保证两端行为一致）
-- =========================================================
local XSD_CONFIG = {
    name = "新史低",
    client_text = "新\n史低",
    desc = "「欧皇模拟器」商店购物折扣！\n装备后商店物品%s折\n（装备后价格不变，购买生效，如果失效脱掉在带上）",
    check_desc = "需开启欧皇商店",
    ui_from_desc = "精英/Boss 概率掉落（低权重）",
    can_add = false,
    only_one = true,
    is_special = false,
    client_color = { 0.8, 0, 0.8, 1 },
    value_range = { min = 5, max = 9 },
    check_equip_can_add = function(inst)
        return true, "满足条件"
    end,
    on_equip_fn = function(inst, owner, value)
        _G.Moon_AddEffect(owner, "xinshidi", "Legend_XSD", 1)
        -- 按装备记录折扣，多件同词条取最优惠
        -- 数值映射与一般附魔一致：属性值越高折扣越好（9=满值→5折，5→9折）
        owner._xsd_discounts = owner._xsd_discounts or {}
        owner._xsd_discounts[inst] = (14 - (value or 7)) / 10
        local best = 1
        for _, d in pairs(owner._xsd_discounts) do
            if d < best then best = d end
        end
        owner._xsd_discount = best
        if _G.TheWorld and _G.TheWorld.ismastersim and owner.components.talker then
            owner.components.talker:Say(string.format("新史低！商店购物 %.0f 折！！！", best * 10))
        end
    end,
    un_equip_fn = function(inst, owner, value)
        if owner._xsd_discounts then owner._xsd_discounts[inst] = nil end
        _G.Moon_ReduceEffect(owner, "xinshidi", "Legend_XSD", 1)
        if _G.Moon_HasEffect(owner, "xinshidi") then
            -- 还有其他件，重算最优惠折扣
            local best = 1
            for _, d in pairs(owner._xsd_discounts or {}) do
                if d < best then best = d end
            end
            owner._xsd_discount = best
        else
            owner._xsd_discount = nil
            owner._xsd_discounts = nil
        end
    end,
}

-- =========================================================
-- Part 3: 安装（两端共用；各自时机触发一次）
-- =========================================================
local installed = false
local function XSD_Install()
    if installed then return end
    -- 仅当同时开启 HH 附魔框架 + 3273001012（欧皇模拟器）且其运行时数据存在时生效
    if not _G.Moon_IsHHEnabled() then return end
    if not _G.Moon_IsModEnabled("workshop-3273001012") then return end
    local utils = _G.TUNING and _G.TUNING.slotmachineutils
    if not utils or not utils.getShopItemFinalPrice then return end

    installed = true

    -- 3a. 折扣 hook：getShopItemFinalPrice 是商店 UI（shopTab）与服务端扣款
    --     （MoneyManager:OnBuy）的唯一定价出口，hook 一处两端价格一致
    if not utils._moon_xsd_hooked then
        utils._moon_xsd_hooked = true
        local _old_getShopItemFinalPrice = utils.getShopItemFinalPrice
        utils.getShopItemFinalPrice = function(itemName)
            local price = _old_getShopItemFinalPrice(itemName)
            -- 服务端：购买流程中的买家（由 AddPlayerPostInit 的 OnBuy 包装临时设置）
            -- rawget 读取：该全局字段并非永久存在，直接读会触发 strict.lua 未声明报错
            local owner = _G.rawget(_G, "_Moon_ShopBuyer")
            -- 客户端：本地玩家（商店 UI 显示价格 / 余额判断）
            if not owner then
                owner = _G.rawget(_G, "ThePlayer")
                if owner and not owner:IsValid() then owner = nil end
            end
            if owner and owner._xsd_discount and _G.Moon_HasEffect(owner, "xinshidi") then
                return price * owner._xsd_discount
            end
            return price
        end
    end

    -- 3b. 附魔注册
    _G.AddSpecialEquipEffect("Legend_XSD", XSD_CONFIG)

    -- 3c. 掉落注册（仅服务端；低权重）
    if _G.TheWorld and _G.TheWorld.ismastersim then
        _G.Moon_RegisterEnchantDrop("Legend_XSD", 0.005)
    end
end

-- 服务端：世界创建时安装（客户端 world 回调不触发，由 AddPlayerPostInit 补装）
AddPrefabPostInit("world", function(inst)
    XSD_Install()
end)

-- 客户端：本地玩家创建时补装（两端都会触发；服务端已被 installed 标记跳过）
-- 服务端：玩家创建时对 moneymanager.OnBuy 做最终包装（晚于所有 AddComponentPostInit，
-- 确保包装在最外层），提供「当前购买买家」上下文供 getShopItemFinalPrice 打折，
-- 并对「黑店」等绕过 getShopItemFinalPrice 的写死价扣款退还新史低差价。
-- ⚠️ 时序：moneymanager 是欧皇模拟器在它自己的 AddPlayerPostInit 回调里动态添加的组件
-- （非 prefab 静态注册），而 AddPlayerPostInit 回调按 mod 加载顺序执行——若本 mod 回调先跑，
-- 组件还不存在。因此即时尝试一次后失败要 DoTaskInTime(0) 延迟兜底重试：
-- 所有 AddPlayerPostInit 回调都在同一帧内执行完，下一帧组件必定已加。
AddPlayerPostInit(function(inst)
    XSD_Install()

    if _G.TheWorld and _G.TheWorld.ismastersim then
        local function TryWrapOnBuy()
            local mm = inst.components and inst.components.moneymanager
            if not mm or mm._moon_xsd_onbuy_wrapped then
                return false
            end
            mm._moon_xsd_onbuy_wrapped = true
            local _old_OnBuy = mm.OnBuy
            mm.OnBuy = function(self, itemName, number, lastskin)
                -- rawset/rawget 绕过 strict.lua 的全局未声明检查（字段仅在购买期间临时存在）
                _G.rawset(_G, "_Moon_ShopBuyer", self.inst)
                local balance_before = self.balance or 0
                local results = { _G.pcall(_old_OnBuy, self, itemName, number, lastskin) }
                -- 新史低差价退还：部分商店（如「黑店」）的 OnBuy 用写死价扣款，绕过
                -- getShopItemFinalPrice，新史低 hook 拦不到。这里对比「实际扣款」与
                -- 「折后总价」，多扣的部分退还给买家（普通物品已打折，差额≈0，不受影响）。
                -- 注意：必须在清空 _Moon_ShopBuyer 之前调用 getShopItemFinalPrice，
                -- 否则 hook 内拿不到买家、返回原价，差额会被算成 0。
                if results[1] and self.inst and self.inst._xsd_discount
                    and _G.Moon_HasEffect(self.inst, "xinshidi") then
                    local utils = _G.TUNING and _G.TUNING.slotmachineutils
                    if utils and utils.getShopItemFinalPrice then
                        local actual_cost = balance_before - (self.balance or 0)
                        local discounted_total = utils.getShopItemFinalPrice(itemName) * (number or 1)
                        local refund = actual_cost - discounted_total
                        if refund > 0.01 then
                            self.balance = _G.math.clamp((self.balance or 0) + refund, 0, 4294967295)
                            if self.syncData then
                                self:syncData()
                            end
                        end
                    end
                end
                _G.rawset(_G, "_Moon_ShopBuyer", nil)
                if results[1] then
                    return results[2], results[3]
                end
                _G.print("[小月亮] 新史低: 购买处理异常 " .. _G.tostring(results[2]))
                return false, 0
            end
            return true
        end
        if not TryWrapOnBuy() then
            inst:DoTaskInTime(0, TryWrapOnBuy)
        end
    end
end)

-- =========================================================
-- Part 4: 客户端词条描述换算（hook HH 的 hh_equip:GetBuffDebugList）
-- =========================================================
-- HH 框架显示词条时用附魔石原始 value 填充 desc 的 %s，且 value==max 时
-- 追加「(已满)」。折扣反转映射（9=满值→5折）后 value 与折数不再相等，
-- 直接显示会误导（满值石头显示「商店物品9折(已满)」，实际 5 折）。
-- 这里包装 GetBuffDebugList，把 XSD 词条描述中的折数替换为换算值，
-- 如「商店物品9折(已满)」→「商店物品5折(已满)」。
-- 无副作用：非 XSD 词条不匹配替换规则原样返回；HH 未加载时本回调不触发。
AddComponentPostInit("hh_equip", function(self)
    if not self or type(self.GetBuffDebugList) ~= "function" then return end
    local _old_GetBuffDebugList = self.GetBuffDebugList
    self.GetBuffDebugList = function(comp, player)
        local list = _old_GetBuffDebugList(comp, player)
        if not list then return list end
        for _, entry in _G.ipairs(list) do
            local v = entry.name
            if v and v.name == "Legend_XSD" and type(v.value) == "number" then
                -- 反转映射：value 9（满）→5折，value 5→9折
                entry.desc = (entry.desc or ""):gsub("商店物品%d+折", "商店物品" .. _G.tostring(14 - v.value) .. "折")
            end
        end
        return list
    end
end)
