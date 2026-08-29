-- 小月亮 安全补丁 v2
-- 拦截 3273001012（幸运模拟器）多种攻击向量
--
-- v1: MoneyBuy RPC 未授权购买
-- v2: 通用 metatable __concat/__div 注入走私模式检测
--     幸运模拟器通过 setmetatable 创建含 __concat/__div 的 smuggling table,
--     在运行时用 .. 和 / 操作符走私恶意字符串, 构建微型 VM 执行任意代码.
--     此补丁在 setmetatable/debug.setmetatable 层面阻断该模式,
--     并在 mod 加载完成后执行全局清理.

local _G = GLOBAL

-- v2 保护开关 (默认关闭, 需要时再启用)
local ENABLE_V2 = false

if ENABLE_V2 then
    ------------------------------------------------------------------
    -- 1. 全局 setmetatable 钩子
    --    阻止创建同时包含 __concat 和 __div 的 metatable（走私模式）
    ------------------------------------------------------------------
    local orig_setmetatable = _G.setmetatable
    _G.setmetatable = function(t, mt)
        if mt and type(mt) == "table" and mt.__concat and mt.__div then
            print("[小月亮] 拦截可疑 setmetatable (走私模式: __concat+__div)")
            return t
        end
        return orig_setmetatable(t, mt)
    end

    -- 同时 hook debug.setmetatable, 防止绕过
    if _G.debug and _G.debug.setmetatable then
        local orig_debug_setmetatable = _G.debug.setmetatable
        _G.debug.setmetatable = function(t, mt)
            if mt and type(mt) == "table" and mt.__concat and mt.__div then
                print("[小月亮] 拦截可疑 debug.setmetatable (走私模式: __concat+__div)")
                return t
            end
            return orig_debug_setmetatable(t, mt)
        end
    end
end

----------------------------------------------------------------------
-- 拦截 MoneyBuy RPC（原 v1 补丁）
----------------------------------------------------------------------
AddComponentPostInit("moneymanager", function(self)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then
        return
    end
    local _oldOnBuy = self.OnBuy
    self.OnBuy = function(self, itemName, number, lastskin)
        if _G.TUNING.slotmachineutils and _G.TUNING.slotmachineutils.findItemInShopMap then
            if not _G.TUNING.slotmachineutils.findItemInShopMap(itemName) then
                print("[小月亮] 拦截非法购买: " .. _G.tostring(itemName))
                return false, 0
            end
        end
        return _oldOnBuy(self, itemName, number, lastskin)
    end
end)

----------------------------------------------------------------------
-- post-init 清理 + 安全网 (仅在 ENABLE_V2 时生效)
----------------------------------------------------------------------
if ENABLE_V2 then
    AddPrefabPostInit("world", function(inst)
        if not _G.TheWorld or not _G.TheWorld.ismastersim then
            return
        end

        -- 清除已存在的走私 metatable（清理函数, 可复用）
        local function cleanse_smuggling_metatables()
            local cleaned = 0
            local ok, err = pcall(function()
                -- 两遍扫描: 先收集可疑对象, 再执行清除, 避免迭代中修改表
                local targets = {}
                for k, v in pairs(_G) do
                    if type(v) == "table" then
                        local mt = debug.getmetatable(v)
                        if mt and type(mt) == "table" and mt.__concat and mt.__div then
                            table.insert(targets, { key = k, obj = v, mt = mt })
                        end
                    end
                end
                for _, tgt in ipairs(targets) do
                    -- 仅清除走私字段, 保留其他元方法
                    tgt.mt.__concat = nil
                    tgt.mt.__div = nil
                    cleaned = cleaned + 1
                end
                for _, tgt in ipairs(targets) do
                    print("[小月亮] 净化全局变量: " .. _G.tostring(tgt.key))
                end
            end)
            if not ok then
                print("[小月亮] 全局扫描异常: " .. _G.tostring(err))
            end
            if cleaned > 0 then
                print("[小月亮] 已净化 " .. cleaned .. " 个恶意 metatable")
            end
            return cleaned
        end

        -- 初始化扫描
        cleanse_smuggling_metatables()

        -- 延迟扫描（捕获 mod 加载后延迟注入）
        inst:DoTaskInTime(0, function()
            cleanse_smuggling_metatables()
        end)

        -- 包装 SpawnPrefab 防止因注入导致的崩溃
        -- 输出错误日志但不崩溃, 同时保留原始错误信息
        local orig_SpawnPrefab = _G.SpawnPrefab
        _G.SpawnPrefab = function(name, ...)
            local ok, result = pcall(orig_SpawnPrefab, name, ...)
            if ok then
                return result
            end
            print("[小月亮] SpawnPrefab 捕获错误 (" .. _G.tostring(name) .. "): " .. _G.tostring(result))
            print(_G.debug.traceback())
            return nil
        end
    end)
end
