-- Guda 常量模块
-- 集中存放所有魔法数字和硬编码值

local addon = Guda

-- 扩展 Init.lua 中已有的 Constants 表
local C = addon.Constants

--=============================================================================
-- 背包 ID
--=============================================================================
C.BAG_BACKPACK = 0
C.BAG_FIRST = 1
C.BAG_LAST = 4
C.BANK_FIRST = 5
C.BANK_LAST = 11
C.KEYRING_BAG = -2
C.BANK_CONTAINER = -1

-- 用于遍历的背包 ID 范围
C.BAG_IDS = {0, 1, 2, 3, 4}
C.BANK_BAG_IDS = {5, 6, 7, 8, 9, 10, 11}
C.ALL_BAG_IDS = {0, 1, 2, 3, 4, -2}  -- 包括钥匙链

--=============================================================================
-- 装备栏位
--=============================================================================
C.EQUIPMENT_SLOT_FIRST = 1
C.EQUIPMENT_SLOT_LAST = 19

--=============================================================================
-- 物品 ID
--=============================================================================
C.SOUL_SHARD_ID = 6265
C.HEARTHSTONE_ID = 6948

-- 不应被标记为垃圾的专业工具物品 ID，
-- 即使它们是白色品质的可装备物品
C.PROFESSION_TOOL_IDS = {
    -- 剥皮
    [7005] = true,   -- Skinning Knife
    [7812] = true,   -- Simple Skinning Knife
    [12709] = true,  -- Finkle's Skinner
    [19901] = true,  -- 祖利安切割者

    -- 乌龟魔兽 / 自定义专业
    [36700] = true,  -- Lumberjack Axe (伐木斧)
    [42004] = true,  -- Carving Knife (雕刻小刀)

    -- 采矿
    [2901] = true,   -- Mining Pick
    [778] = true,    -- Kobold Mining Shovel
    [1959] = true,   -- Cold Iron Pick
    [9465] = true,   -- Digmaster 5000

    -- 锻造
    [5956] = true,   -- Blacksmith Hammer

    -- 工程学
    [6219] = true,   -- Arclight Spanner
    [10498] = true,  -- Gyromatic Micro-Adjuster
    [11590] = true,  -- Mechanical Repair Kit

    -- 附魔棒
    [6218] = true,   -- Runed Copper Rod
    [6339] = true,   -- Runed Silver Rod
    [11130] = true,  -- Runed Golden Rod
    [11145] = true,  -- Runed Truesilver Rod
    [16207] = true,  -- Runed Arcanite Rod

    -- 钓鱼（按 ID 指定，以防子类型检测失败）
    [6256] = true,   -- Fishing Pole
    [6365] = true,   -- Strong Fishing Pole
    [6366] = true,   -- Darkwood Fishing Pole
    [6367] = true,   -- Big Iron Fishing Pole
    [12225] = true,  -- Blump Family Fishing Pole
    [19022] = true,  -- Nat Pagle's Extreme Angler FC-5000
    [19970] = true,  -- Arcanite Fishing Pole
    [84660] = true,  -- Pandaren Fishing Pole (Turtle WoW)

    -- 珠宝加工（如果适用）
    [55155] = true,  -- Jewelers Kit
    [41328] = true,  -- Precision Jewelry Kit
    [20815] = true,  -- Jeweler's Kit
    [20824] = true,  -- Simple Grinder

    -- 职业工具（非专业）
    [5060] = true,   -- Thieves' Tools (盗贼工具)

    -- 炼金术
    [9149] = true,   -- Philosopher's Stone (点金石) — Alchemist transmute tool
}

-- 被 GetItemInfo 归类为"任务"但实际上是消耗品的物品
-- 这些物品在分类视图和排序中被重新归类为"消耗品"
C.QUEST_CATEGORY_EXCLUSIONS = {
    [12450] = true, -- Juju Flurry
    [12451] = true, -- Juju Power
    [12455] = true, -- Juju Ember
    [12457] = true, -- Juju Chill
    [12458] = true, -- Juju Guile
    [12459] = true, -- Juju Escape
    [12460] = true, -- Juju Might
}

-- 不应被标记为垃圾的武器子类型
C.PROFESSION_TOOL_SUBTYPES = {
    ["Fishing Pole"] = true,
    ["Fishing Poles"] = true,
}

--=============================================================================
-- 颜色（r、g、b 表，便于解包）
--=============================================================================
C.COLORS = {
    -- 特殊物品边框
    KEYRING_CYAN = {r = 0.2, g = 0.8, b = 1.0},
    QUEST_GOLD = {r = 1.0, g = 0.82, b = 0},

    -- 文本颜色
    GRAY_TEXT = {r = 0.5, g = 0.5, b = 0.5},
    WHITE_TEXT = {r = 1.0, g = 1.0, b = 1.0},
    GOLD_TITLE = {r = 1.0, g = 0.82, b = 0},
    CYAN_LABEL = {r = 0, g = 1.0, b = 1.0},

    -- 不可用物品着色
    UNUSABLE_RED = {r = 0.9, g = 0.2, b = 0.2, a = 0.45},

    -- 锁定/去饱和
    LOCKED_GRAY = {r = 0.5, g = 0.5, b = 0.5},
}

--=============================================================================
-- 界面阈值
--=============================================================================
C.ICON_SIZE_THRESHOLD = 44  -- 低于此值，使用更小的内边距/填充
C.ICON_INSET_SMALL = 10     -- 小图标的内边距
C.ICON_INSET_LARGE = 15     -- 大图标的内边距
C.ICON_TEXCOORD_CROP = 0.08 -- 纹理坐标裁剪量

--=============================================================================
-- 数据库 / 清理
--=============================================================================
C.CLEANUP_OLD_CHARS_DAYS = 90

--=============================================================================
-- 提示框扫描
--=============================================================================
C.QUEST_TOOLTIP_PATTERNS = {
    "quest starter",
    "this item begins a quest",
    "starts a quest",
    "quest item",
    "manual",
}

C.BIND_ON_EQUIP_PATTERN = "binds when equipped"

--=============================================================================
-- 专用背包类型
--=============================================================================
C.BAG_TYPES = {
    SOUL = "soul",
    HERB = "herb",
    ENCHANT = "enchant",
    QUIVER = "quiver",
    AMMO = "ammo",
}

-- 用于背包类型检测的提示框模式
C.BAG_TYPE_PATTERNS = {
    soul = {"soul bag", "soul pouch"},
    herb = {"herb bag"},
    enchant = {"enchanting bag"},
    quiver = {"quiver"},
    ammo = {"ammo pouch"},
}

--=============================================================================
-- 物品分类（用于 GetItemInfo）
--=============================================================================
C.ITEM_CATEGORIES = {
    WEAPON = "Weapon",
    ARMOR = "Armor",
    CONSUMABLE = "Consumable",
    CONTAINER = "Container",
    TRADE_GOODS = "Trade Goods",
    PROJECTILE = "Projectile",
    QUIVER = "Quiver",
    REAGENT = "Reagent",
    RECIPE = "Recipe",
    KEY = "Key",
    MISCELLANEOUS = "Miscellaneous",
    QUEST = "Quest",
}

--=============================================================================
-- 金币格式化
--=============================================================================
C.MONEY = {
    COPPER_PER_SILVER = 100,
    SILVER_PER_GOLD = 100,
    COPPER_PER_GOLD = 10000,
}

-- 金币显示的颜色代码
C.MONEY_COLORS = {
    GOLD = "|cFFFFD700",
    SILVER = "|cFFC7C7CF",
    COPPER = "|cFFEDA55F",
    WHITE = "|cFFFFFFFF",
}

--=============================================================================
-- 框架常量
--=============================================================================
C.FRAME = {
    TITLE_HEIGHT = 40,
    SEARCH_BAR_HEIGHT = 30,
    FOOTER_HEIGHT = 45,
    FOOTER_HEIGHT_HIDDEN = 10,
    MIN_WIDTH = 200,
    MIN_HEIGHT = 150,
    MAX_WIDTH = 1250,
    MAX_HEIGHT = 1000,
}

--=============================================================================
-- 银行栏位
--=============================================================================
C.BANK_MAIN_SLOTS = 24  -- 主银行容器的栏位数量

--=============================================================================
-- 提示框钩子设置
--=============================================================================
C.TOOLTIP = {
    DEBOUNCE_TIME = 0.2,  -- 清除缓存前等待的秒数
    MAX_MONEY_FRAMES = 8, -- 要搜索的金币框架的最大数量
}

--=============================================================================
-- pfUI 主题默认值
--=============================================================================
C.PFUI_DEFAULT_BG_TRANSPARENCY = 0.4

addon:Debug("Constants module loaded")
