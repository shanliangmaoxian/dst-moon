-- 小月亮商店：召唤群友
-- 商店配方 MoonShop_moon_qunyou_summon（20 个大肉，猪皮图标）制作后，
-- 原地生成瞬发实体 moon_qunyou_summon → 在制作玩家身边召唤 1 只猪人群友：
--   每次兑换只出 1 只，玩家周边最多同时 N 只（上限 = 名字数量，一个名字一只）；
--   群友各有名字（与槽位一一对应，保证不重名）+随机骚话（参考 demo/2944389000_玛言玛语），跟随玩家打架，一直存活不消失；
--   不可被攻击（notarget + noattack + SetInvincible 三层）；群友无敌不会死，故无补员；
--   传送跟随：玩家传送（法杖/虫洞/雕像复活）后群友不会自动跟上（follower 的 GoToEntity 有距离上限），每 10 秒检查一次，超 40 码直接瞬移到玩家身边。
-- 附魔版 scripts/enchants/qunyou.lua 保持原 5 只设定，本文件为商店版独立参数。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MOON_SHOP then return end
if not CFG.ENABLE_MOON_SHOP_BOSS_QUNYOU then return end

-- 配方显示名：crafting menu 用 STRINGS.NAMES[string.upper(recipe.name)] 或
-- STRINGS.NAMES[string.upper(recipe.product)] 查名字（craftingmenu_details.lua:253）。
-- product=moon_qunyou_summon 是全新 prefab 无原版名，须两端（mod 加载时）显式补名，
-- 否则商店配方名字显示为空。先例：moon_shop.lua 的 EMOJITAN / SHIJIZHIHUA_BULB。
if _G.STRINGS and _G.STRINGS.NAMES then
    _G.STRINGS.NAMES.MOONSHOP_MOON_QUNYOU_SUMMON = "召唤群友"
    _G.STRINGS.NAMES.MOON_QUNYOU_SUMMON = "召唤群友"
end

-- ======== 群友配置 ========
local FOLLOW_TELEPORT_DIST = 40 -- 群友距玩家超过该距离视为传送掉队，直接拉回身边（follower GoToEntity 上限约 40 码）
-- 群友一直存活+无敌：不设 PIG_LIFETIME 到期移除、无补员（不会死）；被其他机制移除时清槽位
local PIG_NAMES = {           -- 群友名字池（一个名字一只，MAX_PIGS = #PIG_NAMES 自动跟随）
    "毛旭猪", "紫蝶猪", "番茄炒蛋猪",  "秀猪",
    "无欲无求猪",  "球猪", "哎哟猪", "fay猪",
    "摸瓜吃鱼猪", "挂白猪", "昔猪", "新猪",
     "干饭猪", "飞猪", "混猪", "酸猪",
    "胖虎猪", "零猪",  "萝猪",
    "民猪", "E猪", "兔猪",
}
local MAX_PIGS = 3      -- 同时存在的群友上限 = 名字数量（一个名字一只，改名字自动同步）
local PIG_LINES = {           -- 骚话池（登场/周期性随机取用，%s=自己的名字；风格参考 demo/2944389000_玛言玛语）
    "九月九月，你在哪？不想上班想回家",
    "灌篮！可是我的球框呢？",
    "哎呀 你干嘛～",
    "看看腹肌~~",
    "噜噜噜, 我是 E 猪！",
    "V我50，给你开挂~",
    -- 玛言玛语风格骚话
    "今天星期四，%s v我50吃KFC！",
    "%s，你请我吃汉堡王周三疯狂国王日吗？",
    "%s，让我们点一波外卖吧",
    "嘻嘻，是铸币%s",
    "让我们看看铸币%s有没有在直播",
    "%s，现在这个mod多少订阅了？",
    "%s，来速通吗",
    "速通有无，%s 快上车",
    "%s 又在写bug了吗",
    "今天又在迫害谁了？",
    "是懒狗主播%s！",
    "别卷了别卷了，%s 在摸鱼",
    "干饭不积极，%s 思想有问题！",
    "打工人打工魂，%s 打工都是人上人",
    "呱！%s 你的欧气借我吸一口",
    "%s，附魔出货了吗？面板骰子走起",
    "水晶小人不够了，%s 快帮我去挖",
    "挖宝挖宝，%s 我们去找藏宝图",
    "都别抢，%s 是我的好兄弟",
    "哎哟，%s 打我你也疼！",
    "让我看看是谁在打 %s 的兄弟",
    "%s 今天也是元气满满的一天呢",
    "这把稳了，%s 带飞",
    "鸽了鸽了，%s 我先咕为敬",
}

-- ======== 群友槽位管理（与 qunyou.lua 同构） ========
-- owner._moon_qunyou_pigs[slot] = pig，slot 与 PIG_NAMES[slot] 一一对应（名字不重名）；骚话随机取用

local function get_empty_slot(owner)
    local pigs = owner._moon_qunyou_pigs
    for i = 1, MAX_PIGS do
        local pig = pigs[i]
        if not pig or not pig:IsValid() then
            return i
        end
    end
    return nil
end

-- 只清自己的引用：重复兑换时旧猪人的 onremove 回调不能误清新一批同槽位猪人
local function clear_slot(owner, slot, pig)
    if owner and owner._moon_qunyou_pigs and owner._moon_qunyou_pigs[slot] == pig then
        owner._moon_qunyou_pigs[slot] = nil
    end
end

-- 在 owner 身边召唤 1 只群友（位置 1.5~3 码随机，避免叠在一起）
local function spawn_qunyou(owner, slot)
    local name = PIG_NAMES[slot]
    local x, y, z = owner.Transform:GetWorldPosition()

    local angle = math.random() * 2 * math.pi
    local dist = 1.5 + math.random() * 1.5

    local pig = _G.SpawnPrefab("pigman")
    if not pig then return false end
    pig.Transform:SetPosition(x + math.cos(angle) * dist, y, z + math.sin(angle) * dist)

    -- 名字（挂在 named 组件上；缺失则补挂，保证有名字）
    local named = pig.components.named
    if not named then
        pig:AddComponent("named")
        named = pig.components.named
    end
    if named then
        named:SetName(name)
    end

    -- 随机骚话（参考 demo/2944389000_玛言玛语）：随机取一条，支持 %s 占位符（=自己的名字）
    local function say_random_line()
        local line = PIG_LINES[math.random(#PIG_LINES)]
        if line and string.find(line, "%%s", 1, true) then
            line = string.format(line, name)
        end
        if pig.components.talker then
            pig.components.talker:Say(line)
        end
    end
    -- 登场必说一句；之后周期性随机骚话（60~120 秒随机间隔，避免齐声；任务挂猪实体上，移除自动取消）
    say_random_line()
    local function schedule_random_talk()
        pig:DoTaskInTime(60 + math.random(60), function()
            if not pig:IsValid() then return end
            say_random_line()
            schedule_random_talk()
        end)
    end
    schedule_random_talk()

    -- 跟随玩家打架
    if pig.components.follower then
        pig.components.follower:SetLeader(owner)
    end

    -- 群友不能被攻击（玩家/怪物/AoE 均无效）：
    --   notarget: 怪物不主动选为目标（hufei/yangmaoke/malatutou 同款）
    --   noattack: 一切攻击对其挥空 0 伤害（combat CanBeAttacked 检查）
    --   SetInvincible: 免疫所有伤害路径（含火烧/环境直伤，hufei.lua 同款）
    pig:AddTag("notarget")
    pig:AddTag("noattack")
    if pig.components.health and pig.components.health.SetInvincible then
        pig.components.health:SetInvincible(true)
    end

    -- 群友不睡觉（免得晚上集体掉线）
    -- 注意：sleeper 组件没有 SetSleepiness 方法（qunyou.lua 附魔版同款已修），
    -- 正确做法是把睡眠测试函数替换为恒 false
    if pig.components.sleeper and pig.components.sleeper.SetSleepTest then
        pig.components.sleeper:SetSleepTest(function() return false end)
    end

    -- 召唤的猪人不出掉落物（免得杀猪刷肉/猪皮）：
    -- SetLoot({}) 清固定掉落并重置 randomloot/numrandomloot，ClearRandomLoot 双保险
    if pig.components.lootdropper then
        pig.components.lootdropper:SetLoot({})
        if pig.components.lootdropper.ClearRandomLoot then
            pig.components.lootdropper:ClearRandomLoot()
        end
    end

    owner._moon_qunyou_pigs[slot] = pig

    -- 一直存活+无敌：不设到期移除；被其他机制移除时清槽位（无补员）
    pig:ListenForEvent("onremove", function()
        clear_slot(owner, slot, pig)
    end)

    return true
end

-- 给 owner 召唤 1 只群友（兑换触发）：每次兑换只出 1 只
-- 重复兑换 = 有空槽就再补 1 只（不清理已有群友）；满 MAX_PIGS 只则提示不再出
-- 群友无敌不会死，无补员任务；传送跟随任务随玩家实体存活（玩家下线自动销毁）
function _G.Moon_Qunyou_SummonGroup(owner)
    if not (owner and owner:IsValid() and owner.Transform) then return end
    if owner:HasTag("playerghost") then return end

    -- 首次调用初始化槽位表
    if not owner._moon_qunyou_pigs then
        owner._moon_qunyou_pigs = {}
    end

    -- 每次兑换只召唤 1 只（有空槽才补）
    local slot = get_empty_slot(owner)
    if not slot then
        if _G.Moon_Say then
            _G.Moon_Say(owner, "群友已满啦，最多 " .. MAX_PIGS .. " 只")
        end
        return
    end
    spawn_qunyou(owner, slot)

    -- 传送跟随：玩家传送后群友留在原地（follower 的 GoToEntity 有距离上限，且远处群友可能不更新），
    -- 每 10 秒检查一次，超过 FOLLOW_TELEPORT_DIST 直接瞬移到玩家身边；任务只建一次（多次兑换不累积）
    if not owner._moon_qunyou_follow_task then
        owner._moon_qunyou_follow_task = owner:DoPeriodicTask(10, function()
            if not owner:IsValid() or owner:HasTag("playerghost") then return end
            local px, py, pz = owner.Transform:GetWorldPosition()
            local pigs = owner._moon_qunyou_pigs
            for i = 1, MAX_PIGS do
                local pig = pigs and pigs[i]
                if pig and pig:IsValid() and pig.Transform then
                    local x, _, z = pig.Transform:GetWorldPosition()
                    local dx, dz = px - x, pz - z
                    if dx * dx + dz * dz > FOLLOW_TELEPORT_DIST * FOLLOW_TELEPORT_DIST then
                        pig.Transform:SetPosition(px, py, pz)
                    end
                end
            end
        end)
    end
end

-- ======== 瞬发召唤实体（商店配方 product） ========
-- 制作时 builder.lua 对无 inventoryitem 的 product 会 SetPosition 到制作位置并
-- 同步推送 "onbuilt" 事件（data.builder = 制作玩家），据此直接部署群友后自毁；
-- 若经其他途径生成（无 onbuilt），0 帧后兜底找最近存活玩家。

local function find_nearest_player(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local owner
    local best = math.huge
    if _G.TheSim and _G.TheSim.FindEntities then
        local candidates = _G.TheSim:FindEntities(x, y, z, 12, { "player" })
        for _, p in ipairs(candidates) do
            if p and p:IsValid() and p.Transform and not p:HasTag("playerghost") then
                local px, _, pz = p.Transform:GetWorldPosition()
                local d = (px - x) * (px - x) + (pz - z) * (pz - z)
                if d < best then
                    best = d
                    owner = p
                end
            end
        end
    end
    return owner
end

local function do_summon(inst, owner)
    if inst._moon_qunyou_done then return end
    inst._moon_qunyou_done = true
    if owner and owner:IsValid() then
        _G.Moon_Qunyou_SummonGroup(owner)
    end
    inst:Remove()
end

local function moon_qunyou_summon_fn()
    local inst = _G.CreateEntity()
    inst:AddTag("FX")
    inst.entity:AddTransform()

    -- 制作流程同步推送 onbuilt（data.builder = 制作玩家）
    inst:ListenForEvent("onbuilt", function(_, data)
        do_summon(inst, data and data.builder)
    end)

    -- 兜底：无 onbuilt 途径生成时，0 帧后按最近玩家执行
    inst:DoTaskInTime(0, function()
        if not inst:IsValid() then return end
        do_summon(inst, find_nearest_player(inst))
    end)

    return inst
end

-- RECIPE_DESC 需在 PIG_NAMES/MAX_PIGS 定义之后赋值（描述拼接名字数量，自动跟随）
if _G.STRINGS and _G.STRINGS.RECIPE_DESC then
    _G.STRINGS.RECIPE_DESC.MOONSHOP_MOON_QUNYOU_SUMMON = "20 个大肉召唤 1 只猪人群友\n最多同时 " .. MAX_PIGS .. " 只（一猪一名），各有名字，跟随打架\n一直存活+不可被攻击"
end

-- 注意：RegisterPrefabs 不在 mod 沙箱 env 显式提供，需经 GLOBAL 访问
-- 注意：RegisterPrefabs 是可变参数（每个 prefab 一个参数），不能包在表里传
_G.RegisterPrefabs(
    _G.Prefab("moon_qunyou_summon", moon_qunyou_summon_fn)
)
