-- 小月亮 开局礼包（服务端）
-- 玩家进服后可自选领取一次开局礼包（方案数由配置决定，每玩家仅一次）
-- 配置格式: 物品,数量,角色|物品,数量,角色:::方案2...（角色 all=所有人 或 角色prefab）
-- 已领记录：集群共享文件为唯一权威——地表/洞穴等所有 shard 进程读写同一份记录，真共享
--   world 组件 moon_start_gift_store 仅作旧档兼容迁移（老版本记录同步进共享文件）
-- 重置清零：共享文件不随世界重置删除，故记录各 shard 的 session_identifier，
--   某 shard session 变化（世界被重建）→ 已领作废 → 重置后可重新领取

local _G = GLOBAL
local CFG = _G.MOON_CFG

if not CFG.ENABLE_START_GIFT then return end

local AddModRPCHandler = AddModRPCHandler

-- 世界加载完成标记（领取只发生在玩家加入后，时序安全）
local load_done = false

-- ------------------------------------------------------------------
-- 方案解析
-- ------------------------------------------------------------------
-- 单一配置项格式: 物品,数量,角色|物品,数量,角色:::方案2...
--   ::: 分隔多个方案，| 分隔同方案的多个物品，角色填 all 或角色 prefab
--   数量/角色可省略（默认 1 / all），如 "cutstone" 或 "cutstone,5"
local function ParseConfig(cfg_str)
    local plans = {}
    if type(cfg_str) ~= "string" then return plans end
    for plan_str in string.gmatch(cfg_str, "[^:]+") do
        local items = {}
        for entry in string.gmatch(plan_str, "[^|]+") do
            local prefab, count, role = entry:match("^%s*(.-)%s*,%s*(%d+)%s*,%s*(.-)%s*$")
            if not prefab then
                prefab, count = entry:match("^%s*(.-)%s*,%s*(%d+)%s*$")
                role = "all"
            end
            if not prefab then
                prefab = entry:match("^%s*(.-)%s*$")
                count, role = 1, "all"
            end
            if prefab and prefab ~= "" then
                local n = tonumber(count) or 1
                if n < 1 then n = 1 end
                if role == nil or role == "" then role = "all" end
                table.insert(items, { prefab = prefab, count = n, role = role })
            end
        end
        if #items > 0 then
            table.insert(plans, items)
        end
    end
    return plans
end

-- 方案标签自动生成: 礼包A / 礼包B / 礼包C ...（超过 26 个方案用 P27 等兜底）
local PLAN_LETTERS = { "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z" }
local PLANS_CFG = ParseConfig(CFG.START_GIFT_PLANS)
local PLAN_LIST   = {}              -- {"a","b"}
local PLAN_DATA   = {}              -- id -> 物品定义表
local PLAN_LABELS = {}              -- id -> "礼包A"
for i, items in ipairs(PLANS_CFG) do
    local id = PLAN_LETTERS[i] or ("p" .. i)
    table.insert(PLAN_LIST, id)
    PLAN_DATA[id] = items
    PLAN_LABELS[id] = "礼包" .. (PLAN_LETTERS[i] or i)
end

-- 角色匹配：all 或精确匹配玩家 prefab（忽略大小写）
local function RoleMatches(role, player_prefab)
    if not role or role == "" or role == "all" then return true end
    return string.lower(role) == string.lower(player_prefab or "")
end

-- ------------------------------------------------------------------
-- 已领记录存取（moon_start_gift_store 组件，随世界存档持久化）
-- ------------------------------------------------------------------
local function GetStore()
    if _G.TheWorld and _G.TheWorld.components and _G.TheWorld.components.moon_start_gift_store then
        return _G.TheWorld.components.moon_start_gift_store
    end
    return nil
end

-- AddPrefabPostInit("world") 在客户端不触发，正好只有服务端挂载组件
AddPrefabPostInit("world", function(inst)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then return end
    if not inst.components.moon_start_gift_store then
        inst:AddComponent("moon_start_gift_store")
    end
    load_done = true
end)

-- ------------------------------------------------------------------
-- 集群共享已领记录（地表/洞穴等所有 shard 真共享 + 重置世界清零）
-- DST 各 shard（地表 Master / 洞穴 Caves / 多层等）是独立进程，各持独立 user session /
-- 世界存档，玩家“退出重进另一世界”时读不到另一边的记录。已领记录写入所有进程都能访问
-- 的同一份 TheSim 持久化文件，候选位置按序探测（首个能读到的即共享位置，各进程选同一路径）：
--   1) InClusterSlot(slot, "Master") —— 主机模式（slot 非 0）可靠共享（LoadShardInSlot 同款）
--   2) "../../" —— 专用服务器 TheSim 根为 <cluster>/<shard>/save/，上两级即 cluster 根（各 shard 共享）
--   3) "../" —— 退一级（shard 目录，仅兜底）
--   4) 本 shard 根 —— 不共享，最后兜底
-- 共享文件不随世界重置删除，因此额外记录每个 shard 的 session_identifier：
-- 某 shard 的 session 与文件里记录的不一致 → 该世界被重建过 → 已领记录作废（重置清零）。
-- 这是“跨 shard 共享”与“重置后可重新领”同时成立的必要机制。
-- ------------------------------------------------------------------
local SHARED_KEY = "moon_gift_claims_v1"

-- 集群 slot 号：仅主机模式（cluster slot）非 0；专用服务器 ShardIndex:Load 传 0/nil，视为无 slot
local function GetSharedSlot()
    local s = _G.ShardGameIndex and _G.ShardGameIndex:GetSlot()
    if s and s ~= 0 then return s end
    s = _G.SaveGameIndex and _G.SaveGameIndex:GetCurrentSaveSlot()
    if s and s ~= 0 then return s end
    return nil
end

-- 当前 shard 的唯一标识（session 字段 key）
-- 用 TheShard:GetShardId()（地表 "1"、各洞穴层 "2"/"3"...，每进程唯一且重置后不变），
-- 不能退化成 surface/caves 二分：多层洞穴/地表会共用字段，层间互相误判重置而清空记录
local function GetShardKey()
    local sid = _G.TheShard and _G.TheShard.GetShardId and _G.TheShard:GetShardId()
    if sid then
        return "s" .. tostring(sid)
    end
    -- 兜底（理论上不会走到）：官方洞穴判断 TheWorld:HasTag("cave")
    if _G.TheWorld and _G.TheWorld.HasTag and _G.TheWorld:HasTag("cave") then
        return "caves"
    end
    return "surface"
end

local function GetMySession()
    local meta = _G.TheWorld and _G.TheWorld.meta
    if meta and meta.session_identifier then
        return meta.session_identifier
    end
    -- 本地游戏 session_identifier 不可靠（可能为 nil 或重置后不变）
    -- 回退：用 world 组件自维护的 session ID，随世界存档持久化，重置自然清零
    local store = GetStore()
    if store then
        if not store._session then
            store._session = "ws" .. tostring(os.time())
        end
        return store._session
    end
    return nil
end

-- 共享读写候选（顺序即优先级）；shared_target 记录首次探测到的可用位置，写入复用同一路径
local shared_target = nil

local function BuildSharedOps()
    local ops = {}
    local slot = GetSharedSlot()
    if slot then
        table.insert(ops, { name = "slot:" .. tostring(slot) .. "/Master/" .. SHARED_KEY,
            read = function(cb) _G.TheSim:GetPersistentStringInClusterSlot(slot, "Master", SHARED_KEY, cb) end,
            write = function(str) _G.TheSim:SetPersistentStringInClusterSlot(slot, "Master", SHARED_KEY, str, false, nil) end })
    end
    table.insert(ops, { name = "../../" .. SHARED_KEY,
        read = function(cb) _G.TheSim:GetPersistentString("../../" .. SHARED_KEY, cb, false) end,
        write = function(str) _G.TheSim:SetPersistentString("../../" .. SHARED_KEY, str, false, nil) end })
    table.insert(ops, { name = "../" .. SHARED_KEY,
        read = function(cb) _G.TheSim:GetPersistentString("../" .. SHARED_KEY, cb, false) end,
        write = function(str) _G.TheSim:SetPersistentString("../" .. SHARED_KEY, str, false, nil) end })
    table.insert(ops, { name = SHARED_KEY,
        read = function(cb) _G.TheSim:GetPersistentString(SHARED_KEY, cb, false) end,
        write = function(str) _G.TheSim:SetPersistentString(SHARED_KEY, str, false, nil) end })
    return ops
end

-- 读共享已领记录（异步；success=true 即接受——含空数据，避免探测跳到不共享的后备位置）
local function ReadShared(cb)
    local ops = BuildSharedOps()
    local function try(i)
        if not ops[i] then
            cb({ sessions = {}, claimed = {} })
            return
        end
        ops[i].read(function(success, str)
            if success then
                if not shared_target then
                    shared_target = ops[i]
                    print("[小月亮] 开局礼包共享存储位置: " .. tostring(ops[i].name))
                end
                local data = { sessions = {}, claimed = {} }
                if type(str) == "string" and str ~= "" then
                    local ok, parsed = _G.pcall(_G.json.decode, str)
                    if ok and type(parsed) == "table" then
                        data = parsed
                        if type(data.sessions) ~= "table" then data.sessions = {} end
                        if type(data.claimed) ~= "table" then data.claimed = {} end
                    end
                end
                cb(data)
            else
                try(i + 1)
            end
        end)
    end
    try(1)
end

local function WriteShared(data)
    local target = shared_target or (BuildSharedOps())[1]
    if target then
        if not shared_target then
            shared_target = target
            print("[小月亮] 开局礼包共享存储位置(写入时选定): " .. tostring(target.name))
        end
        target.write(_G.json.encode(data))
    end
end

-- 重置清零检测：本 shard 的 session 与共享记录不一致 → 该世界被重建过 → 已领作废
-- （各 shard 独立字段，互不干扰；首次加入的新 shard 无记录，保留已领 → 跨世界共享生效）
local function CheckWorldReset(data)
    local key = GetShardKey()
    local my_session = GetMySession()
    if my_session then
        if data.sessions[key] and data.sessions[key] ~= my_session then
            data.claimed = {}
        end
        data.sessions[key] = my_session
    else
        -- session_identifier 不可用时（本地游戏）回退：world store 为空 + 共享文件有记录 = 世界重置
        local store = GetStore()
        if store and next(store:GetClaimed()) == nil and next(data.claimed) ~= nil then
            data.claimed = {}
        end
    end
end

-- ------------------------------------------------------------------
-- 领取防重入（异步读共享文件期间拒绝重复请求，防连点双发）
-- ------------------------------------------------------------------
local claim_pending = {}

AddPlayerPostInit(function(player)
    if not (player and player.ismastersim) then return end
    -- 玩家离开时清理挂起的领取请求，防 userid 残留导致重进后永久被拒
    player:ListenForEvent("onremove", function()
        if player.userid then claim_pending[player.userid] = nil end
    end)
end)

-- ------------------------------------------------------------------
-- 发放
-- ------------------------------------------------------------------
-- 背包满等 GiveItem 失败时，把物品放到玩家脚下（GetWorldPosition 返回多值，直接多值接收）
local function DropAtFeet(inst, player)
    if not (inst and inst.Transform and player and player.Transform) then return end
    local x, y, z = player.Transform:GetWorldPosition()
    inst.Transform:SetPosition(x, y, z)
end

local function GivePlan(player, plan)
    local defs = PLAN_DATA[plan]
    if not defs or #defs == 0 then return false end

    local player_prefab = player.prefab or ""
    local items = {}
    for _, def in ipairs(defs) do
        if RoleMatches(def.role, player_prefab) then
            -- 逐个数生成：配置多少就给足多少，不受物品堆叠上限(maxsize)截断影响
            local count = def.count or 1
            if count < 1 then count = 1 end
            for i = 1, count do
                local item = _G.SpawnPrefab(def.prefab)
                if item then
                    table.insert(items, item)
                else
                    if i == 1 then
                        print(string.format("[小月亮] 开局礼包物品不存在，已跳过: %s", tostring(def.prefab)))
                    end
                    break
                end
            end
        end
    end
    if #items == 0 then return false end
    print(string.format("[小月亮] 发放开局礼包%s: %d 件物品", tostring(plan), #items))

    -- 打包成礼盒（参考 ciallo.WrapAndGiveGift：gift + WrapItems + GiveItem，开袋获取物品）
    local gift = _G.SpawnPrefab("gift")
    if not (gift and gift.components and gift.components.unwrappable) then
        -- 礼盒不可用时降级直接给物品
        if gift then gift:Remove() end
        for _, item in ipairs(items) do
            if item and item:IsValid() then
                if player.components and player.components.inventory then
                    if not player.components.inventory:GiveItem(item) then
                        DropAtFeet(item, player)
                    end
                else
                    DropAtFeet(item, player)
                end
            end
        end
        return true
    end

    gift.components.unwrappable:WrapItems(items, player)
    for _, item in ipairs(items) do
        if item and item:IsValid() then item:Remove() end
    end
    if gift.components.named then
        gift.components.named:SetName("开局" .. (PLAN_LABELS[plan] or plan))
    end
    if player.components and player.components.inventory then
        if not player.components.inventory:GiveItem(gift) then
            DropAtFeet(gift, player)
        end
    else
        DropAtFeet(gift, player)
    end
    return true
end

-- ------------------------------------------------------------------
-- RPC（命名空间 LittleMoon）
-- ------------------------------------------------------------------
-- 方案全部条目（含专属物品及其角色，用于客户端展示完整礼包内容）
local function PlanItemsFor(plan_id)
    local defs = PLAN_DATA[plan_id]
    if not defs then return {} end
    local items = {}
    for _, def in ipairs(defs) do
        table.insert(items, { prefab = def.prefab, count = def.count, role = def.role })
    end
    return items
end

-- 查询可用方案与领取状态（客户端打开弹窗时调用）
-- 已领状态从集群共享文件实时读取（异步），地表/洞穴读到同一份记录
AddModRPCHandler("LittleMoon", "GetStartGiftPlans", function(player)
    if not player or not _G.TheWorld or not _G.TheWorld.ismastersim then return end
    ReadShared(function(data)
        CheckWorldReset(data)
        local claimed = data.claimed[player.userid] or false
        if not claimed then
            -- 旧档迁移：老版本记录在 world store，借本次查询同步进共享文件
            local store = GetStore()
            claimed = store and store:GetClaimed()[player.userid] or false
            if claimed then
                data.claimed[player.userid] = claimed
                WriteShared(data)
            end
        end
        local result = {
            plans = PLAN_LIST,
            labels = PLAN_LABELS,
            contents = {},
            claimed = claimed,
        }
        for _, pid in ipairs(PLAN_LIST) do
            result.contents[pid] = PlanItemsFor(pid)
        end
        local rpc = _G.CLIENT_MOD_RPC
        if rpc and rpc["LittleMoon"] and rpc["LittleMoon"]["StartGiftPlansResponse"] and _G.json then
            _G.SendModRPCToClient(rpc["LittleMoon"]["StartGiftPlansResponse"], player.userid, _G.json.encode(result))
        end
    end)
end)

-- 回执给客户端（成功/失败），用于回滚乐观置灰
local function SendClaimResponse(player, ok, plan)
    local rpc = _G.CLIENT_MOD_RPC
    if rpc and rpc["LittleMoon"] and rpc["LittleMoon"]["ClaimStartGiftResponse"] and _G.json then
        _G.SendModRPCToClient(rpc["LittleMoon"]["ClaimStartGiftResponse"], player.userid, _G.json.encode({ ok = ok, plan = plan }))
    end
end

-- 领取指定方案（异步读共享文件，判定+写入同一回调内完成）
AddModRPCHandler("LittleMoon", "ClaimStartGift", function(player, plan)
    if not player or not _G.TheWorld or not _G.TheWorld.ismastersim then return end
    local userid = player.userid
    if not userid then return end

    local store = GetStore()
    if not store or not load_done then
        _G.Moon_Say(player, "礼包数据加载中，请稍后再试")
        return
    end
    if type(plan) ~= "string" or not PLAN_DATA[plan] then
        _G.Moon_Say(player, "无效的礼包方案")
        SendClaimResponse(player, false, plan)
        return
    end
    -- 防重入：同一玩家已有领取请求在处理中（异步读共享文件期间），直接拒绝
    if claim_pending[userid] then
        _G.Moon_Say(player, "礼包发放中，请稍候")
        return
    end
    claim_pending[userid] = true

    ReadShared(function(data)
        claim_pending[userid] = nil
        -- 玩家在异步读取期间离开：实体失效，放弃处理
        if not player:IsValid() then return end
        CheckWorldReset(data)
        -- 已领判定：共享文件（权威）→ world store（旧档兼容）
        local claimed = data.claimed[userid] or store:GetClaimed()[userid]
        if claimed then
            _G.Moon_Say(player, "你已经领取过开局礼包了")
            SendClaimResponse(player, false, plan)
            return
        end

        if not GivePlan(player, plan) then
            _G.Moon_Say(player, "礼包发放失败，该礼包是专属礼包或物品不存在")
            SendClaimResponse(player, false, plan)
            return
        end

        data.claimed[userid] = plan
        WriteShared(data)
        store:SetClaimed(userid, plan)
        _G.Moon_Say(player, "已领取" .. (PLAN_LABELS[plan] or plan) .. "！")
        SendClaimResponse(player, true, plan)
    end)
end)
