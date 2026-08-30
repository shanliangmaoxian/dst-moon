name = "小月亮 (Little Moon)"
description = "提取自特定Mod的召唤功能：小月亮按钮及召唤面板"
author = "九月"
version = "1.19.3"
api_version = 10
priority = -1
dst_compatible = true
all_clients_require_mod = true
client_only_mod = false
dependencies = {
    {workshop = "2526778484"},
}
icon_atlas = "modicon.xml"
icon = "modicon.tex"

-- 定义标题函数
local function AddTitle(title)
    return { 
        name = " ", 
        label = title, 
        options = { { description = "", data = 0 } }, 
        default = 0 
    }
end

configuration_options = {

    AddTitle("通用配置"),
    {
        name = "LITTLE_MOON_SCALE",
        label = "助手面板缩放",
        hover = "设置小月亮助手面板的整体大小",
        options = {
            { description = "缩小 (0.8x)", data = 0.8 },
            { description = "标准 (1.0x)", data = 1.0 },
            { description = "放大 (1.2x)", data = 1.2 },
            { description = "特大 (1.5x)", data = 1.5 },
        },
        default = 1.0,
    },
    AddTitle("附魔强化挖宝组件"),
    {
        name = "ENABLE_TREASURE",
        label = "开启挖宝组件",
        hover = "是否开启小月亮按钮及召唤功能",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "PROXIMITY_LIMIT",
        label = "局部密度限制(20码)",
        hover = "规定范围内最多存在的宝藏点数量",
        options = {
            { description = "10个", data = 10 },
            { description = "20个", data = 20 },
            { description = "50个", data = 50 },
            { description = "100个", data = 100 },
            { description = "不限制", data = 999 },
        },
        default = 50,
    },
    {
        name = "PLAYER_LIMIT",
        label = "个人全图上限",
        hover = "单个玩家在全图范围内最多拥有的宝藏点数量",
        options = {
            { description = "20个", data = 20 },
            { description = "50个", data = 50 },
            { description = "100个", data = 100 },
            { description = "200个", data = 200 },
            { description = "不限制", data = 9999 },
        },
        default = 100,
    },
    {
        name = "GLOBAL_LIMIT",
        label = "全图总数上限",
        hover = "整个服务器范围内最多允许存在的宝藏点总数",
        options = {
            { description = "200个", data = 200 },
            { description = "500个", data = 500 },
            { description = "1000个", data = 1000 },
            { description = "不限制", data = 99999 },
        },
        default = 500,
    },
    {
        name = "EXPIRY_TIME",
        label = "自动过期消失",
        hover = "未被开启的宝藏点多久后会自动消失",
        options = {
            { description = "0.5天", data = 240 },
            { description = "1天", data = 480 },
            { description = "3天", data = 1440 },
            { description = "永不消失", data = -1 },
        },
        default = 480,
    },
    {
        name = "DIG_TREASURE_MODE",
        label = "一键挖宝",
        hover = "跳过宝藏点和铲子挖掘，消耗卷轴直接出怪。选择每次挖宝数量。",
        options = {
            { description = "关闭", data = 0 },
            { description = "1个", data = 1 },
            { description = "3个", data = 3 },
            { description = "5个", data = 5 },
            { description = "10个", data = 10 },
        },
        default = 0,
    },
    {
        name = "MAX_NEARBY_MONSTERS",
        label = "周边怪物上限",
        hover = "一键挖宝时玩家周边20码内怪物超过此数量则禁止使用，防止服务器卡顿",
        options = {
            { description = "10只", data = 10 },
            { description = "20只", data = 20 },
            { description = "30只", data = 30 },
            { description = "50只", data = 50 },
        },
        default = 20,
    },

    AddTitle("怪物强化"),
    {
        name = "ENABLE_MOB_ENHANCE",
        label = "开启怪物强化",
        hover = "为Boss和普通怪物添加防御层和附魔能力（共50+种怪物，75种附魔）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "MOB_ENHANCE_BOSS",
        label = "强化Boss",
        hover = "龙蝇、巨鹿、熊獾等23个Boss获得强化（需开启怪物强化）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "MOB_ENHANCE_NORMAL",
        label = "强化普通怪",
        hover = "猎犬、蜘蛛、猪人等50+种敌对生物获得强化（需开启怪物强化）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "MOB_ENHANCE_LEVEL",
        label = "强化难度",
        hover = "难度越高，怪物的附魔效果越强。附魔数 = 简单1 / 普通3 / 困难5 / 噩梦7，Boss和普通怪共用此难度",
        options = {
            { description = "简单 (×0.6, 共1附魔)", data = "easy" },
            { description = "普通 (×1.0, 共3附魔)", data = "normal" },
            { description = "困难 (×3.0, 共5附魔)", data = "hard" },
            { description = "噩梦 (×5.0, 共7附魔)", data = "nightmare" },
        },
        default = "easy",
    },
    {
        name = "MOB_ENCHANT_CHANCE",
        label = "怪物附魔几率",
        hover = "怪物获得附魔的概率。100% 时所有被强化的怪物必定获得附魔，调低后仅部分怪物获得附魔（需开启怪物强化）",
        options = {
            { description = "10%", data = 0.1 },
            { description = "25%", data = 0.25 },
            { description = "50%", data = 0.5 },
            { description = "75%", data = 0.75 },
            { description = "100%", data = 1.0 },
        },
        default = 1.0,
    },
    {
        name = "MOB_ENHANCE_EXCLUDE",
        label = "排除怪物/禁用附魔,在MOB_ENHANCE_EXCLUDE表中添加",
        hover = "在此表中添加要排除的内容，支持两种：怪物 prefab 名（如 'pigman'）→ 该怪物不强化；附魔 ID 或附魔中文名（如 'MOB_YUEBAN'、'月半'）→ 该附魔不再抽取。\n格式: {'pigman','月半','哎哟'}\n留空表则全部启用（需开启怪物强化）",
        options = { {description = "在服务器mod配置中添加", data = {}} },
        default = {},
    },

    -- AddTitle("怪物强化 — 防御层"),
    -- {
    --     name = "ENABLE_MOB_DEFENSE",
    --     label = "开启防御层",
    --     hover = "关闭时下面的防御层配置全部不生效",
    --     options = {
    --         -- { description = "开启", data = true },
    --         { description = "关闭", data = false },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "MOB_DEFENSE_MITIGATION",
    --     label = "基础减伤",
    --     hover = "固定百分比降低怪物受到的伤害",
    --     options = {
    --         { description = "关闭", data = false },
    --         { description = "10%", data = 0.1 },
    --         { description = "30%", data = 0.3 },
    --         { description = "50%", data = 0.5 },
    --         { description = "70%", data = 0.7 },
    --         { description = "90%", data = 0.9 },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "MOB_DEFENSE_DYNAMIC",
    --     label = "动态减伤",
    --     hover = "血量越低减伤越高",
    --     options = {
    --         { description = "关闭", data = false },
    --         { description = "线性减伤", data = 1 },
    --         { description = "阶梯式减伤", data = 3 },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "MOB_DEFENSE_CAP",
    --     label = "单次限伤",
    --     hover = "限制每下受伤不超过最大生命值的百分比",
    --     options = {
    --         { description = "关闭", data = false },
    --         { description = "1%", data = 1 },
    --         { description = "3%", data = 3 },
    --         { description = "5%", data = 5 },
    --         { description = "10%", data = 10 },
    --         { description = "15%", data = 15 },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "MOB_DEFENSE_FREQ",
    --     label = "受伤限频",
    --     hover = "限制同一来源每秒能造成的伤害次数",
    --     options = {
    --         { description = "关闭", data = false },
    --         { description = "0.2秒", data = 0.2 },
    --         { description = "0.5秒", data = 0.5 },
    --         { description = "1秒", data = 1 },
    --         { description = "2秒", data = 2 },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "MOB_DEFENSE_SCOPE",
    --     label = "防御范围",
    --     hover = "防御层作用于哪些怪物",
    --     options = {
    --         { description = "仅Boss", data = "boss" },
    --         { description = "所有强化怪物", data = "all" },
    --     },
    --     default = "all",
    -- },

    AddTitle("更多附魔"),
    {
        name = "ENABLE_MORE_ENCHANTS",
        label = "开启更多附魔",
        hover = "是否开启额外的附魔词条 毛旭/灵尾印记",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "remove_enchant",
        label = "禁用指定附魔石,在remove_enchant表中添加",
        hover = "在此表中添加要禁用的附魔石ID或名称。\n格式: {'id1','id2','id3'}\n支持所有HH框架附魔石，留空表则不禁用任何附魔石",
        options = { {description = "在服务器mod配置中添加", data = {}} },
        default = {},
    },

    AddTitle("欧皇模拟器清理组件"),
    {
        name = "ENABLE_QL_HELPER",
        label = "开启快捷指令面板",
        hover = "是否开启包含 #ql 和 #cleanup 的快捷指令面板",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },

    AddTitle("禁止打包"),
    {
        name = "DISABLE_KRAMPUS_PACK",
        label = "坎普斯",
        hover = "是否禁止坎普斯被打包",
        options = {
            { description = "禁止", data = true },
            { description = "不禁止", data = false },
        },
        default = false,
    },

    -- AddTitle("物品自动吸入"),
    -- {
    --     name = "ENABLE_AUTO_PICKUP",
    --     label = "开启自动吸入",
    --     hover = "是否开启周围物品自动吸入背包功能",
    --     options = {
    --         { description = "开启", data = true },
    --         { description = "关闭", data = false },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "AUTO_PICKUP_RANGE",
    --     label = "吸入范围",
    --     hover = "设置自动吸入物品的距离",
    --     options = {
    --         { description = "较近 (3码)", data = 3 },
    --         { description = "标准 (5码)", data = 5 },
    --         { description = "较远 (8码)", data = 8 },
    --         { description = "超远 (12码)", data = 12 },
    --     },
    --     default = 5,
    -- },

    AddTitle("客户端反作弊"),
    {
        name = "LOCK_RUN_SPEED",
        label = "锁定跑速",
        hover = "禁止客户端通过 mod 修改跑速（如 Fast moving 等加速 mod）",
        options = {
            { description = "锁定 (默认6)", data = true },
            { description = "不锁定", data = false },
        },
        default = false,
    },
    {
        name = "ENABLE_DISABLE_RESELECT",
        label = "禁用客户端换人",
        hover = "是否禁用换人指令",
        options = {
            { description = "禁用", data = true },
            { description = "允许", data = false },
        },
        default = true,
    },

    AddTitle("快捷自杀组件"),
    {
        name = "ENABLE_SUICIDE",
        label = "开启快捷自杀",
        hover = "是否开启自杀面板按钮",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },

    AddTitle("死亡统计"),
    {
        name = "ENABLE_DEATH_STATS",
        label = "开启死亡统计",
        hover = "统计所有玩家的死亡次数，在助手面板中显示排行榜",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "ENABLE_DEATH_ANNOUNCE",
        label = "死亡公告",
        hover = "当玩家死亡时在聊天框公告死亡信息",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "DEATH_STATS_RESET_ON_SWITCH",
        label = "换人重置计数",
        hover = "换人（切换角色）后是否将死亡次数清零",
        options = {
            { description = "清零", data = true },
            { description = "不清零", data = false },
        },
        default = false,
    },

    AddTitle("快捷发言"),
    {
        name = "ENABLE_QUICK_CHAT",
        label = "开启快捷发言",
        hover = "是否在助手面板中显示快捷发言输入框",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },

    AddTitle("模组介绍"),
    {
        name = "ENABLE_MOD_BROWSER",
        label = "开启模组介绍",
        hover = "在助手面板中显示模组浏览器，查看服务器 Mod 的 Wiki 介绍",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },

    -- AddTitle("掉落优化 (防卡顿)"),
    -- {
    --     name = "ENABLE_LOOT_LIMITER",
    --     label = "开启掉落限流",
    --     hover = "合并可堆叠物品，限制不可堆叠物品数量",
    --     options = {
    --         { description = "开启", data = true },
    --         { description = "关闭", data = false },
    --     },
    --     default = false,
    -- },
    -- {
    --     name = "MAX_NON_STACKABLE",
    --     label = "不可堆叠上限",
    --     hover = "同种不可堆叠物品单次掉落的最大数量",
    --     options = {
    --         { description = "3个", data = 3 },
    --         { description = "5个", data = 5 },
    --         { description = "10个", data = 10 },
    --         { description = "20个", data = 20 },
    --         { description = "50个", data = 50 },
    --         { description = "100个", data = 100 },
    --         { description = "200个", data = 200 },
    --         { description = "500个", data = 500 },
    --         { description = "不限制", data = 9999 },
    --     },
    --     default = 5,
    -- },

    AddTitle("物品禁用"),
    {
        name = "BAN_ITEMS",
        label = "禁用物品列表,在BAN_ITEMS表中添加",
        hover = "在此表中添加要禁用的物品 prefab 名称，支持原版及 mod 物品。\n格式: {'prefab1','prefab2|30','prefab3'}\n'prefab' 永久禁用; 'prefab|30' 表示禁用 30 个游戏日后自动解禁(从配置生效时起算,服务器重启不重置)。\n被禁用的物品无法制作，现有的也会被移除并退还材料。\n留空表则不禁用任何物品。",
        options = { {description = "在服务器mod配置中添加", data = {}} },
        default = {},
    },

    AddTitle("便捷功能"),

    {
        name = "ENABLE_WARDROBE_ANYWHERE",
        label = "随身换装",
        hover = "物品栏上方显示\"换装\"按钮，随时随地打开更衣室",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    -- {
    --     name = "ENABLE_SKIN_SHARING",
    --     label = "皮肤通用化",
    --     hover = "允许玩家跨角色套用皮肤，更衣室显示全部在场角色的皮肤选项",
    --     options = {
    --         { description = "开启", data = true },
    --         { description = "关闭", data = false },
    --     },
    --     default = false,
    -- },

    AddTitle("小月亮商店"),
    {
        name = "ENABLE_MOON_SHOP",
        label = "开启小月亮商店",
        hover = "在制作栏中添加小月亮商店标签，可购买部分物品",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "ENABLE_MOON_SHOP_BATCH",
        label = "精炼材料批量兑换",
        hover = "小月亮商店中显示原版精炼材料 x10 批量兑换配方和彩虹宝石兑换",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_BOSS_CELESTIAL",
        label = "兑换天体后裔",
        hover = "小月亮商店中用 100 水晶小人兑换天体后裔掉落物（需 HH 附魔模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_BOSS_STALKER",
        label = "兑换织影者",
        hover = "小月亮商店中用 100 水晶小人兑换织影者掉落物（需 HH 附魔模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_BOSS_ALTERGUARDIAN",
        label = "兑换天体英雄",
        hover = "小月亮商店中用 100 水晶小人兑换天体英雄掉落物（需 HH 附魔模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_BOSS_CRABKING",
        label = "兑换帝王蟹",
        hover = "小月亮商店中用 100 水晶小人兑换帝王蟹掉落物（需 HH 附魔模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_BOSS_QUNYOU",
        label = "召唤群友",
        hover = "小月亮商店中用 20 个大肉召唤 1 只猪人群友，周边最多同时 3 只",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_SOUL",
        label = "灵魂互换",
        hover = "小月亮商店中显示 3:1 暗影/光明之魂互换配方（需泰拉模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_TRAVEL_TRACES",
        label = "遍历之迹兑换",
        hover = "小月亮商店中显示用 500 水晶小人兑换遍历之迹（需 HH 附魔 + 小鸟模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_DEMON_ALTAR",
        label = "恶魔祭坛可制作",
        hover = "小月亮商店中显示恶魔祭坛购买配方",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_SHIJIZHIHUA_BULB",
        label = "世纪之花球茎可制作",
        hover = "小月亮商店中显示世纪之花球茎购买配方",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_TREASURE_TALLY",
        label = "寻宝卷轴兑换",
        hover = "小月亮商店中显示用金子兑换寻宝卷轴（需 HH 附魔模组）\n50金子=1卷轴 / 500金子=10卷轴",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_SPARK",
        label = "月熠兑换",
        hover = "小月亮商店中显示用 5 个月亮碎片兑换 1 个月熠",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "ENABLE_MOON_SHOP_STAR_BROOCH",
        label = "星辰胸针兑换",
        hover = "小月亮商店中显示用 1 个老师怜悯附魔石兑换 1 个星辰胸针（需 Legend 模组）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },

    AddTitle("开局礼包"),
    {
        name = "ENABLE_START_GIFT",
        label = "开启开局礼包",
        hover = "玩家进服后可自选领取一次开局礼包（全服仅一次，跨世界记录）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = false,
    },
    {
        name = "START_GIFT_PLANS",
        label = "礼包方案配置",
        hover = "单一配置项配置全部方案。\n格式: 物品,数量,角色|物品,数量,角色:::方案2...\n| 分隔同方案的多个物品，::: 分隔多个方案，角色填 all（所有人）或角色prefab（如 wilson）\n示例: cutstone,10,all|goldnugget,5,wilson:::spear,1,all",
        options = { {description = "在服务器mod配置中添加", data = ""} },
        default = "",
    },

    AddTitle("性能设置"),
    {
        name = "TRANSFORM_LIMIT",
        label = "自动转换附魔重试次数上限",
        hover = "最多自动转换次数的上限",
        options = {
            { description = "10", data = 200 },
            { description = "100", data = 200 },
            { description = "200", data = 200 },
            { description = "500", data = 500 },
            { description = "1000", data = 1000 },
            { description = "不限制", data = "INF" },
        },
        default = 500,
    },
}
