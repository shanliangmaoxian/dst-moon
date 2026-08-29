-- 小月亮 开局礼包 已领记录组件（旧档兼容用）
-- 挂在 TheWorld 上，通过 OnSave/OnLoad 随世界存档持久化
-- 权威记录在 start_gift.lua 的集群共享文件；本组件仅保留老版本（1.17.4-）的已领记录，
-- 新版本首次查询时同步进共享文件后即可废弃。世界重新生成时 OnLoad 无数据，自动清零

local MoonStartGiftStore = Class(function(self, inst)
    self.inst = inst
    self.claimed = {}
end)

function MoonStartGiftStore:OnSave()
    local save = {}
    for k, v in pairs(self.claimed) do
        save[k] = v
    end
    local data = {}
    if next(save) then data.claimed = save end
    if self._session then data._session = self._session end
    return next(data) and data or nil
end

function MoonStartGiftStore:OnLoad(data)
    if data then
        if type(data.claimed) == "table" then
            for k, v in pairs(data.claimed) do
                self.claimed[k] = v
            end
        end
        if data._session then
            self._session = data._session
        end
    end
end

function MoonStartGiftStore:GetClaimed()
    return self.claimed
end

function MoonStartGiftStore:SetClaimed(userid, plan)
    self.claimed[userid] = plan
end

return MoonStartGiftStore
