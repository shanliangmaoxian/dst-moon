-- 附魔收集册组件：以"存档数据合并"方式收纳附魔石
-- 机制说明（参考祈巧 sora2list 的思路，独立实现，非复制）：
--   每个槽位保留 1 块"展示石"（真实实体，可正常拖出），
--   其余同款（prefab + 皮肤 + hh_effect 一致）在入库时序列化为存档记录存在后台，
--   取出/开册时用 SpawnSaveRecord 从存档数据重建实体。
--   全程不使用 stackable 组件：词条数据（hh_effect）零丢失，
--   取出的永远是普通单实体，不触发 HH 附魔台"禁止叠加附魔石"检查。
--
-- v2 关键设计：
--   * 合并的石头【不进入容器】：包装 container.GiveItem，命中同款指纹时直接
--     序列化入库 + 移除实体，原 GiveItem 不执行。客户端不会出现
--     "格子先出现再消失"的死实体幽灵格（?? 占位）。
--   * restock 补出的展示石由组件手动登记指纹（GiveItem 触发的 itemget
--     被 busy 屏蔽，v1 依赖事件登记会漏，导致后续合并/回收状态错位）。
--   * 数量同步：net_counts（net_string，"槽位:总数;..."），客户端角标用。
--
-- 数据模型：
--   entries[slot]      = { data = 存档记录, count = n }  后台存货（不含展示石）
--   fingerprints[slot] = { prefab, skin, effect }        展示石指纹（同指纹才合并）
--   槽位内总数 = (展示石 1 或 0) + 后台 count

local MoonAlbum = Class(function(self, inst)
    self.inst = inst
    self.container = nil
    self.numslots = 0
    self.entries = {}
    self.fingerprints = {}
    self.pending_restock = {} -- 待补展示石的槽位集合
    self.busy = false         -- 内部操作防重入（restock 期间屏蔽事件与拦截）
    self.isloading = false
end)

local function GetFingerprint(item)
    if item == nil or item.prefab == nil then
        return nil
    end
    return {
        prefab = item.prefab,
        skin = item.skinname,
        effect = item.hh_effect,
    }
end

local function FingerprintFromRecord(record)
    if record == nil or record.prefab == nil then
        return nil
    end
    return {
        prefab = record.prefab,
        skin = record.skinname,
        effect = record.data ~= nil and record.data.hh_effect or nil,
    }
end

local function IsSameFingerprint(a, b)
    return a ~= nil and b ~= nil
        and a.prefab == b.prefab
        and a.skin == b.skin
        and a.effect == b.effect
end

---- 数量同步（客户端角标数据源）
function MoonAlbum:UpdateCounts()
    local inst = self.inst
    if inst.net_counts == nil then
        return
    end
    local parts = {}
    for slot = 1, self.numslots do
        local display = self.container ~= nil
            and self.container:GetItemInSlot(slot) ~= nil
        local entry = self.entries[slot]
        local n = (display and 1 or 0) + (entry ~= nil and entry.count or 0)
        if n > 1 then
            table.insert(parts, slot .. ":" .. n)
        end
    end
    local str = table.concat(parts, ";")
    if inst.net_counts:value() ~= str then
        inst.net_counts:set(str)
    end
    self:BroadcastCounts(str)
end

---- 数量变化时推给所有打开者（客户端角标数据源，不依赖 netvar 同步）
function MoonAlbum:BroadcastCounts(str)
    local rpc = _G.CLIENT_MOD_RPC
    local id = rpc ~= nil and rpc["LittleMoon"] ~= nil
        and rpc["LittleMoon"]["AlbumCounts"] or nil
    local sendrpc = _G.SendModRPCToClient
    if id == nil or sendrpc == nil or self.container == nil then
        return
    end
    for _, opener in pairs(self.container:GetOpeners()) do
        if opener ~= nil and opener.userid ~= nil then
            sendrpc(id, opener.userid, str)
        end
    end
end

function MoonAlbum:SetupContainer()
    self.container = self.inst.components.container
    if self.container == nil then
        return
    end
    self.numslots = self.container:GetNumSlots()

    -- 拦截入库：同款指纹命中时不进入容器，直接序列化并入后台
    -- （调用方约定：GiveItem 返回 true 即物品已收纳，实体已移除）
    local orig_give = self.container.GiveItem
    self.container.GiveItem = function(c, item, slot, src_pos, drop_on_fail)
        if self:TryMergeInto(item) then
            return true
        end
        return orig_give(c, item, slot, src_pos, drop_on_fail)
    end

    self.inst:ListenForEvent("itemget", function(inst, data)
        if data == nil or data.item == nil then return end
        self:OnItemGet(data.slot, data.item)
    end)
    self.inst:ListenForEvent("itemlose", function(inst, data)
        self:OnItemLose(data ~= nil and data.slot or nil)
    end)
end

---- 合并拦截：命中同款展示位则入库并吞掉实体
function MoonAlbum:TryMergeInto(item)
    if self.busy or self.isloading or item == nil then
        return false
    end
    if item.prefab ~= "hh_effect_stone" or item.hh_effect == nil then
        return false
    end
    local fp = GetFingerprint(item)
    if fp == nil then
        return false
    end
    for i = 1, self.numslots do
        if IsSameFingerprint(self.fingerprints[i], fp) then
            local entry = self.entries[i]
            -- 防御：命中槽的后台存货（若有）必须与指纹同词条，否则说明该槽状态已错位，
            -- 不能把石头并进去（否则取用时会把错词条的石头补出来 = "凭空留一个"）
            if entry == nil
                or (entry.data ~= nil
                    and IsSameFingerprint(FingerprintFromRecord(entry.data), fp)) then
                local record = item:GetSaveRecord()
                if entry ~= nil then
                    entry.count = entry.count + 1
                else
                    self.entries[i] = { data = record, count = 1 }
                end
                self:UpdateCounts()
                item:Remove()
                return true
            end
        end
    end
    return false
end

---- 找一个既无展示石、也无后台存货的空槽（用于错位存货迁移兜底）
function MoonAlbum:FindEntrySlot()
    for i = 1, self.numslots do
        if self.entries[i] == nil
            and (self.container == nil or self.container:GetItemInSlot(i) == nil) then
            return i
        end
    end
    return nil
end

---- 新展示石入槽：登记指纹（restock 的 GiveItem 由 busy 屏蔽，走手动登记）
function MoonAlbum:OnItemGet(slot, item)
    if self.busy or self.isloading or slot == nil then return end
    local fp = GetFingerprint(item)
    if fp == nil or fp.effect == nil then return end
    local entry = self.entries[slot]
    if entry ~= nil and entry.data ~= nil
        and not IsSameFingerprint(FingerprintFromRecord(entry.data), fp) then
        -- 该槽被新词条展示石占用，但后台还存着旧词条：把旧存货挪到空槽，避免错位
        local dest = self:FindEntrySlot()
        if dest ~= nil then
            self.entries[slot] = nil
            self.entries[dest] = entry
            self.fingerprints[dest] = nil
            local d = dest
            self.inst:DoTaskInTime(0, function()
                if self.inst:IsValid() then self:RestockSlot(d) end
            end)
        end
    end
    self.fingerprints[slot] = fp
    self.pending_restock[slot] = nil
    self:UpdateCounts()
end

---- 展示石被拿走：有存货则标记待补（0 帧后自动补一块），否则清指纹
function MoonAlbum:OnItemLose(slot)
    if self.busy or self.isloading or slot == nil then return end
    if self.fingerprints[slot] == nil then return end
    self.fingerprints[slot] = nil
    self:UpdateCounts()
    local entry = self.entries[slot]
    if entry == nil or entry.count <= 0 then
        self.entries[slot] = nil
        return
    end
    self.pending_restock[slot] = true
    self.inst:DoTaskInTime(0, function()
        self.pending_restock[slot] = nil
        if self.inst:IsValid() then
            self:RestockSlot(slot)
        end
    end)
end

---- 从后台存货补一块展示石到指定槽位
function MoonAlbum:RestockSlot(slot)
    local entry = self.entries[slot]
    if entry == nil or entry.count <= 0 then
        self.entries[slot] = nil
        return
    end
    if self.container == nil or self.container:GetItemInSlot(slot) ~= nil then
        return
    end
    local item = SpawnSaveRecord(entry.data)
    if item == nil then
        -- 存档数据损坏，丢弃该条存货
        self.entries[slot] = nil
        self:UpdateCounts()
        return
    end
    local record = entry.data -- 先取记录再递减（entry 可能随清空失效）
    entry.count = entry.count - 1
    if entry.count <= 0 then
        self.entries[slot] = nil
    end
    self.busy = true
    self.container:GiveItem(item, slot)
    self.busy = false
    -- GiveItem 的 itemget 被 busy 屏蔽，指纹手动登记
    self.fingerprints[slot] = FingerprintFromRecord(record)
    self:UpdateCounts()
end

---- 开册时把所有有存货的空槽补上展示石
function MoonAlbum:RestockAll()
    if self.isloading or self.container == nil then return end
    for slot = 1, self.numslots do
        if self.container:GetItemInSlot(slot) == nil and self.entries[slot] ~= nil then
            self:RestockSlot(slot)
        end
    end
end

---- 按排序权重重排册内附魔石（"整理"按钮的服务端实现）
---- 做法：把所有非空槽（展示石 + 后台存货）统一收进内存 → 按权重排序 →
----       从 1 号槽起重新连续落位 → 补回展示石。顺带消除中间空洞。
---- @param rank_of: function(effect_id) -> number，权重越小越靠前
----        （权重表见 prefabs/lmoon_stone_album.lua 的 COLOR_ORDER：
----         按附魔石背景色 client_color 分组，同色相邻）
---- @return 参与整理的词条数；0 表示无需整理
---- 注意：entries/fingerprints 是按槽位号存档的，本函数会整体改写键位——
----       这是"整理"的预期效果（内容不丢，只是换了槽号）。
function MoonAlbum:SortByRank(rank_of)
    if self.busy or self.isloading or self.container == nil or rank_of == nil then
        return 0
    end

    -- 1) 收集所有非空槽；展示石按 1 块计入，与后台存货合并成同一条
    local items = {}
    for slot = 1, self.numslots do
        local display = self.container:GetItemInSlot(slot)
        local entry = self.entries[slot]
        local count = (display ~= nil and 1 or 0) + (entry ~= nil and entry.count or 0)
        if count > 0 then
            local fp = self.fingerprints[slot]
            -- 兜底用 prefab 名：itemtestfn 已限制只收附魔石，万一有别的物品混进来，
            -- 也必须照原样收进 items 再放回去，否则第 3 步清空时会把它弄丢
            local effect = (display ~= nil and display.hh_effect)
                or (fp ~= nil and fp.effect)
                or (display ~= nil and display.prefab)
            -- 存档记录优先取后台存货（同一词条所有石头同款）；只有展示石时现场生成一份
            local record = (entry ~= nil and entry.data)
                or (display ~= nil and display:GetSaveRecord())
            if effect == nil or record == nil then
                -- 有内容却拿不到重建信息（异常数据）：宁可放弃整理，
                -- 也不能让第 3 步的清空把它弄丢
                return 0
            end
            table.insert(items, {
                effect = effect,
                fingerprint = fp or FingerprintFromRecord(record),
                record = record,
                count = count,
            })
        end
    end
    if #items <= 1 then
        return 0 -- 0 或 1 条本来就没有顺序问题
    end

    -- 2) 排序：先比权重，同权重比 effect_id。effect_id 唯一 → 全序，
    --    避免 table.sort 不稳定导致同档内每次结果不同
    table.sort(items, function(a, b)
        local ra, rb = rank_of(a.effect), rank_of(b.effect)
        if ra ~= rb then
            return ra < rb
        end
        return tostring(a.effect) < tostring(b.effect)
    end)

    -- 3) 清空容器与后台数据。busy 期间 itemget/itemlose 回调被屏蔽，
    --    否则移除展示石会被 OnItemLose 当成"玩家取走"而标记补货
    self.busy = true
    for slot = 1, self.numslots do
        local display = self.container:GetItemInSlot(slot)
        if display ~= nil then
            -- wholestack=true 确保整块取出（RemoveItem 默认只取 1 个）；
            -- RemoveItem 只把物品移出容器（不销毁实体），还需要自己 Remove 掉
            self.container:RemoveItem(display, true)
            display:Remove()
        end
        self.entries[slot] = nil
        self.fingerprints[slot] = nil
        self.pending_restock[slot] = nil
    end
    self.busy = false

    -- 4) 按新顺序落位：count 先全额记进后台，再由 RestockAll 扣 1 补出展示石
    for i, item in ipairs(items) do
        if i > self.numslots then break end
        self.entries[i] = { data = item.record, count = item.count }
        self.fingerprints[i] = item.fingerprint
    end

    self:RestockAll()
    self:UpdateCounts()
    return #items
end

---- 收录明细（查看描述用）
---- name_of(effect_id) -> 展示名，由 prefab 层注入（词条中文名在 HH 注册表里）
function MoonAlbum:GetSummary(name_of)
    name_of = name_of or function(effect) return tostring(effect) end
    local total = 0
    local lines = {}
    for slot = 1, self.numslots do
        local display = self.container ~= nil and self.container:GetItemInSlot(slot) or nil
        local entry = self.entries[slot]
        local n = (display ~= nil and 1 or 0) + (entry ~= nil and entry.count or 0)
        if n > 0 then
            local fp = self.fingerprints[slot]
            local effect = display ~= nil and display.hh_effect
                or (fp ~= nil and fp.effect or nil)
            table.insert(lines, string.format("%s ×%d", name_of(effect), n))
            total = total + n
        end
    end
    if total <= 0 then
        return "一本装订好的附魔收集册\n当前没有收录任何附魔石"
    end
    return string.format("附魔收集册（共收录 %d 块）\n%s", total,
        table.concat(lines, "\n"))
end

function MoonAlbum:OnSave()
    return {
        entries = self.entries,
        fingerprints = self.fingerprints,
    }
end

function MoonAlbum:OnLoad(data)
    if data == nil then return end
    self.entries = data.entries or {}
    self.fingerprints = data.fingerprints or {}
    -- 载入期间容器会逐个 GiveItem 还原展示石，屏蔽事件处理与合并拦截
    self.isloading = true
    self.inst:DoTaskInTime(0, function()
        self.isloading = false
        self:UpdateCounts()
    end)
end

return MoonAlbum
