-- 小月亮 锁定移速
-- 原理："Fast moving" 等 client_only_mod 在客户端修改 TUNING.WILSON_RUN_SPEED，
-- 客户端 locomotor 初始化时读取该值 (default=6)，存入 self.runspeed，实现加速。
-- 反制：客户端/服务端定时直接复位玩家 locomotor.runspeed 字段。
--
-- 注意：AddPrefabPostInit / AddPlayerPostInit 是沙箱函数，只能裸名调用，不能 _G.xxx

local CFG = GLOBAL.MOON_CFG
if not CFG.LOCK_RUN_SPEED then return end

local DEFAULT_RUN_SPEED = 6

-- 立即锁 TUNING（兜底）
GLOBAL.TUNING.WILSON_RUN_SPEED = DEFAULT_RUN_SPEED

-- world init 后，服务端和客户端各自执行保护逻辑
AddPrefabPostInit("world", function(inst)
    if inst.ismastersim then
        -- ===== 服务端：每秒复位所有玩家 locomotor 速度 =====
        inst:DoPeriodicTask(1, function()
            for _, player in ipairs(GLOBAL.AllPlayers) do
                if player and player.components and player.components.locomotor then
                    player.components.locomotor.runspeed = DEFAULT_RUN_SPEED
                end
            end
        end)
    else
        -- ===== 客户端：每 0.5 秒复位本地玩家 locomotor + 覆盖 TUNING =====
        inst:DoPeriodicTask(0.5, function()
            GLOBAL.TUNING.WILSON_RUN_SPEED = DEFAULT_RUN_SPEED
            if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.locomotor then
                GLOBAL.ThePlayer.components.locomotor.runspeed = DEFAULT_RUN_SPEED
            end
        end)
    end
end)

-- 玩家初始化时立即复位（服务端）
AddPlayerPostInit(function(player)
    if not GLOBAL.TheWorld or not GLOBAL.TheWorld.ismastersim then return end
    if player.components and player.components.locomotor then
        player.components.locomotor.runspeed = DEFAULT_RUN_SPEED
    end
end)
