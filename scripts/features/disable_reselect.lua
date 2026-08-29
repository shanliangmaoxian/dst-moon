-- 小月亮 禁用客户端换人
-- 拦截 /reselect 和 /重选角色 指令
-- 策略：本 mod 优先级 -1，先于 3607443539 加载，保存原始函数后在游戏初始化时恢复

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_DISABLE_RESELECT then return end

local _originalSendResumeRequest = nil
GLOBAL.pcall(function()
    _originalSendResumeRequest = GLOBAL.NetworkProxy.SendResumeRequestToServer
end)

-- 1. 覆盖聊天指令
local function disabled_msg()
    if GLOBAL.TheFrontEnd then
        GLOBAL.TheFrontEnd:PopScreen()
    end
end
GLOBAL.pcall(GLOBAL.AddUserCommand, "reselect", {}, disabled_msg)
GLOBAL.pcall(GLOBAL.AddUserCommand, "重选角色", {}, disabled_msg)

-- 2. 拦截 mod 3607443539 的存档写入
GLOBAL.pcall(function()
    local oldSave = GLOBAL.SavePersistentString
    GLOBAL.SavePersistentString = function(filepath, data, ...)
        if filepath == "mod_config_data/resetplayer" then
            return 0, 0  -- 静默丢弃
        end
        return oldSave(filepath, data, ...)
    end
end)

-- 3. 游戏初始化后恢复原始 SendResumeRequestToServer
GLOBAL.pcall(function()
    GLOBAL.AddPrefabPostInit("world", function(inst)
        if _originalSendResumeRequest then
            GLOBAL.NetworkProxy.SendResumeRequestToServer = _originalSendResumeRequest
        end
        -- 清理残留存档
        GLOBAL.TheSim:SetPersistentString("mod_config_data/resetplayer", "", false)
    end)
end)
