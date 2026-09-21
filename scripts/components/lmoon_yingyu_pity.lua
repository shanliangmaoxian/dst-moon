-- 每位小樱独立保存封印保底；制作附魔石不改变此计数。
local EFFECT_ID = "Moon_YINGYU_XINGHUI"
local DROP_CHANCE = 0.0005 -- 0.05%
local PITY_LIMIT = 1500

local YingyuPity = Class(function(self, inst)
    self.inst = inst
    self.seals_without_drop = 0
end)

function YingyuPity:OnSealSuccess()
    if self.inst.prefab ~= "ccs" or not TheWorld.ismastersim then return end
    self.seals_without_drop = math.min(self.seals_without_drop + 1, PITY_LIMIT)
    if self.seals_without_drop < PITY_LIMIT and math.random() >= DROP_CHANCE then return end

    local spawn_stone = rawget(_G, "HHSpawnStoneById")
    local stone = spawn_stone and spawn_stone(EFFECT_ID)
    if not stone then return end -- 生成失败保留进度，下一次封印继续保底。
    local pos = self.inst:GetPosition()
    stone.Transform:SetPosition(pos:Get())
    if self.inst.components.inventory then
        self.inst.components.inventory:GiveItem(stone, nil, pos)
    end
    self.seals_without_drop = 0
end

function YingyuPity:OnSave()
    return { seals_without_drop = self.seals_without_drop }
end

function YingyuPity:OnLoad(data)
    local count = data and data.seals_without_drop
    if type(count) == "number" and count == count then
        self.seals_without_drop = math.max(0, math.min(math.floor(count), PITY_LIMIT))
    end
end

return YingyuPity
