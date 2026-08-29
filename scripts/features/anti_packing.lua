-- 小月亮 防打包逻辑
-- 禁止坎普斯被其他 Mod 打包

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.DISABLE_KRAMPUS_PACK then return end

local function ApplyAntiPacking(inst)
    -- 1. 基础标签协议
    inst:AddTag("nopack")
    inst:AddTag("nonpackable")
    inst:AddTag("backpack")
    inst:AddTag("irreplaceable")
    inst:AddTag("questitem")

    -- 2. 移除常见的打包组件 (延迟执行以覆盖其他 Mod 的注入)
    if _G.TheWorld.ismastersim then
        inst:DoTaskInTime(0, function()
            -- 移除 "Architect" 或 "Pack Everything" 等 Mod 可能添加的组件
            if inst.components.packable then
                inst:RemoveComponent("packable")
            end

            -- 针对特定 Mod 的属性设置
            inst.not_packable = true

            if inst.components.inventoryitem then
                inst.components.inventoryitem.cangoincontainer = false
            end
        end)
    end
end

AddPrefabPostInit("krampus", ApplyAntiPacking)
