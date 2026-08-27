-- Guda 分类管理器
-- 处理自定义分类定义和基于规则的物品分类

local addon = Guda

local CategoryManager = {}
addon.Modules.CategoryManager = CategoryManager

--=====================================================
-- 分类结果缓存
-- 缓存 CategorizeItem 的结果，避免重复评估
--=====================================================
local categoryCache = {}
local cacheHits = 0
local cacheMisses = 0

-- 清空分类缓存（分类变更或完全刷新时调用）
function CategoryManager:ClearCache()
    categoryCache = {}
    cacheHits = 0
    cacheMisses = 0
    addon:Debug("CategoryManager cache cleared")
end

-- 获取缓存统计信息（用于调试/性能监控）
function CategoryManager:GetCacheStats()
    local total = cacheHits + cacheMisses
    local hitRate = total > 0 and (cacheHits / total * 100) or 0
    return {
        hits = cacheHits,
        misses = cacheMisses,
        total = total,
        hitRate = hitRate,
        size = 0, -- 稍后在下方计算
    }
end

-- 生成物品的缓存键
local function GetCacheKey(itemLink, isOtherChar)
    if not itemLink then return nil end
    -- 包含 isOtherChar 标志，因为分类结果可能不同
    return itemLink .. (isOtherChar and ":other" or ":current")
end

-- 规则类型：
-- itemType：按 GetItemInfo 的类型匹配（Armor、Weapon、Consumable 等）
-- itemSubtype：按子类型匹配（Cloth、Potion、Herb 等）
-- namePattern：对物品名称进行 Lua 模式匹配
-- quality：按品质等级匹配（0=灰色、1=白色、2=绿色、3=蓝色、4=紫色、5=橙色）
-- isBoE：装备后绑定的布尔值
-- isQuestItem：任务物品的布尔值
-- texturePattern：匹配图标贴图路径
-- itemID：特定的物品 ID（ID 表）

-- 分组常量
local GROUP_MAIN = "Main"
local GROUP_OTHER = "Other"
local GROUP_CLASS = "Class"

-- 内置物品覆盖：强制将特定 itemID 归入某个分类，无论游戏报告的类别如何。
-- 与语言环境无关（以 itemID 为键），在 CategorizeItem 中先于任何规则评估检查。
-- 用于被游戏错误标记的物品（例如被报告为 Miscellaneous 的术士制造宝石），
-- 使它们落入所属分类。用户要求这些物品归为
-- Consumable（消耗品）。
local BUILTIN_ITEM_OVERRIDES = {
    -- Warlock mana stones (法力玛瑙/法力翡翠/法力黄水晶/法力红宝石)
    [5514] = "Consumable",  -- 法力玛瑙
    [5513] = "Consumable",  -- 法力翡翠
    [8007] = "Consumable",  -- 法力黄水晶
    [8008] = "Consumable",  -- 法力红宝石
    -- Warlock firestones (火焰石)
    [1254] = "Consumable",  -- 次级火焰石
    [13699] = "Consumable", -- 火焰石
    [13700] = "Consumable", -- 强效火焰石
    [13701] = "Consumable", -- 特效火焰石
    [51932] = "Consumable", -- 火焰石（服务器变体）
    -- Warlock spellstones (魔法石)
    [5522] = "Consumable",  -- 魔法石
    [13602] = "Consumable", -- 强效魔法石
    [13603] = "Consumable", -- 特效魔法石
    [51933] = "Consumable", -- 魔法石（服务器变体）
    -- 术士愤怒石（愤怒石）
    [51935] = "Consumable", -- 愤怒石
    -- Warlock healthstones (治疗石/次级治疗石/特效治疗石)
    [5509] = "Consumable",  -- 治疗石
    [5510] = "Consumable",  -- 强效治疗石
    [5511] = "Consumable",  -- 次级治疗石
    [5512] = "Consumable",  -- 小型治疗石
    [9421] = "Consumable",  -- 特效治疗石
    [19004] = "Consumable", -- 小型治疗石（服务器变体）
    [19005] = "Consumable", -- 小型治疗石（服务器变体）
    [19006] = "Consumable", -- 次级治疗石（服务器变体）
    [19007] = "Consumable", -- 次级治疗石（服务器变体）
    [19008] = "Consumable", -- 治疗石（服务器变体）
    [19009] = "Consumable", -- 治疗石（服务器变体）
    [19010] = "Consumable", -- 强效治疗石（服务器变体）
    [19011] = "Consumable", -- 强效治疗石（服务器变体）
    [19012] = "Consumable", -- 特效治疗石（服务器变体）
    [19013] = "Consumable", -- 特效治疗石（服务器变体）
    -- 无论游戏报告的类别如何，职业物品都会被强制归入 "Class Items"：
    -- Light Feather (法师缓落/牧师漂浮引怪), Unconscious Dig Rat (战士冲锋引怪)
    [17056] = "Class Items", -- Light Feather (轻羽毛)
    [5052]  = "Class Items", -- Unconscious Dig Rat (昏迷的掘地鼠)
    -- 萨满图腾 — 游戏将这些报告为 Reagent（材料），但它们属于职业专属物品。
    -- 注意：用户报告 大地图腾 的 itemID 是 5075，但 5075 实际上是
    -- "Blood Shard"（血碎片）；真正的大地图腾是 5175。
    [5175] = "Class Items", -- Earth Totem (大地图腾)
    [5176] = "Class Items", -- Fire Totem (火焰图腾)
    [5177] = "Class Items", -- Water Totem (水之图腾)
    [5178] = "Class Items", -- Air Totem (空气图腾)
    -- 点金石（Philosopher's Stone）— 炼金术转化工具；游戏将其报告为
    -- Trade Goods（商品），但用户希望它归入 Tools（工具）。
    [9149] = "Tools",      -- Philosopher's Stone (点金石)

    --=========================================================================
    -- 消耗品覆盖。在 zhCN 客户端上，这些工程/炼金物品被 GetItemInfo
    -- 报告为 "Trade Goods"（商品），因此需要显式覆盖回 Consumable。
    -- （仅限法力/巫师之油——像 黑口鱼油 / 火油 这类烹饪油是真正的
    -- Trade Goods，保持原状。）
    --=========================================================================
    -- Weapon/Armor applied oils (法力之油 / 巫师之油 系列)
    [20745] = "Consumable", -- Minor Mana Oil (次级法力之油)
    [20747] = "Consumable", -- Lesser Mana Oil (法力之油)
    [20748] = "Consumable", -- Brilliant Mana Oil (璀璨法力之油)
    [20744] = "Consumable", -- Minor Wizard Oil (次级巫师之油)
    [20746] = "Consumable", -- Lesser Wizard Oil (巫师之油)
    [20750] = "Consumable", -- Wizard Oil (巫师之油)
    [20749] = "Consumable", -- Brilliant Wizard Oil (璀璨巫师之油)
    -- Sharpening stones (磨刀石 系列)
    [2862]  = "Consumable", -- Rough Sharpening Stone (粗糙的磨刀石)
    [2863]  = "Consumable", -- Coarse Sharpening Stone (粗制磨刀石)
    [2871]  = "Consumable", -- Heavy Sharpening Stone (重型磨刀石)
    [7964]  = "Consumable", -- Solid Sharpening Stone (坚固的磨刀石)
    [12404] = "Consumable", -- Dense Sharpening Stone (致密磨刀石)
    [18262] = "Consumable", -- Elemental Sharpening Stone (元素磨刀石)
    [23122] = "Consumable", -- Consecrated Sharpening Stone (神圣磨刀石)
    [33083] = "Consumable", -- Elementium Sharpening Stone (源质磨刀石)
    -- Bombs / explosive charges (炸弹 / 炸药 / 高爆炸弹 系列)
    [4360]  = "Consumable", -- Rough Copper Bomb (粗制铜质炸弹)
    [4370]  = "Consumable", -- Large Copper Bomb (大型铜质炸弹)
    [4374]  = "Consumable", -- Small Bronze Bomb (小型青铜炸弹)
    [4380]  = "Consumable", -- Big Bronze Bomb (大型青铜炸弹)
    [4394]  = "Consumable", -- Big Iron Bomb (大型铁质炸弹)
    [10514] = "Consumable", -- Mithril Frag Bomb (秘银碎片炸弹)
    [10562] = "Consumable", -- Hi-Explosive Bomb (高爆炸弹)
    [16040] = "Consumable", -- Arcane Bomb (奥术炸弹)
    [16005] = "Consumable", -- Dark Iron Bomb (黑铁炸弹)
    [41909] = "Consumable", -- Dragonfire Bomb (龙火炸弹)
    [10646] = "Consumable", -- Goblin Sapper Charge (哥布林工兵炸药)
    [4852]  = "Consumable", -- Flash Bomb (闪光炸弹)
    [4367]  = "Consumable", -- Small Seaforium Charge (小型瑟银炸药)
    [4398]  = "Consumable", -- Large Seaforium Charge (大型瑟银炸药)
    [18594] = "Consumable", -- Powerful Seaforium Charge (强力瑟银炸药)
    [4358]  = "Consumable", -- Rough Dynamite (粗糙的炸药)
    [4365]  = "Consumable", -- Coarse Dynamite (粗制炸药)
    [4378]  = "Consumable", -- Heavy Dynamite (重型炸药)
    [10507] = "Consumable", -- Solid Dynamite (坚固的炸药)
    [18641] = "Consumable", -- Dense Dynamite (致密炸药)
    [6714]  = "Consumable", -- Ez-Thro Dynamite (Ez-Thro炸药)
    [18588] = "Consumable", -- Ez-Thro Dynamite II (Ez-Thro炸药 II)

    -- 元素试剂属于 Trade Goods（商品），而不是施法材料。
    -- 在 zhCN 客户端上，元素火焰/大地/水/空气被报告为 Reagent（材料）。
    [7068]  = "Trade Goods", -- Elemental Fire (元素火焰)
    [7067]  = "Trade Goods", -- Elemental Earth (元素之土)
    [7070]  = "Trade Goods", -- Elemental Water (元素之水)
    [7069]  = "Trade Goods", -- Elemental Air (元素之气)
}

-- 默认分类定义，复刻现有的硬编码行为
local DEFAULT_CATEGORIES = {
    order = {
        "Recently Looted", "BoP", "BoE", "Weapon", "Armor", "Trinket", "Consumable", "Food", "Drink",
        "Trade Goods", "Reagent", "Recipe", "Quiver", "Container",
        "Soul Bag", "Miscellaneous", "Quest", "Junk",
        "Class Items", "Keyring",
        "Home", "Tools", "Empty"
    },
    itemOverrides = BUILTIN_ITEM_OVERRIDES,  -- 平面映射：[itemID] = categoryId
    definitions = {
        ["Recently Looted"] = {
            name = "Recently Looted",
            icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_02",
            rules = {
                { type = "isRecentlyLooted", value = 600 }
            },
            matchMode = "all",
            priority = 95,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["BoP"] = {
            name = "BoP",
            icon = "Interface\\Icons\\INV_Shield_06",
            rules = {
                { type = "isBoP", value = true }
            },
            matchMode = "all",
            priority = 74,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["BoE"] = {
            name = "BoE",
            icon = "Interface\\Icons\\INV_Misc_Orb_01",
            rules = {
                { type = "isBoE", value = true }
            },
            matchMode = "all",
            priority = 75,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Weapon"] = {
            name = "Weapon",
            icon = "Interface\\Icons\\INV_Sword_04",
            rules = {
                { type = "itemType", value = "Weapon" }
            },
            matchMode = "all",
            priority = 70,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Armor"] = {
            name = "Armor",
            icon = "Interface\\Icons\\INV_Chest_Chain",
            rules = {
                { type = "itemType", value = "Armor" }
            },
            matchMode = "all",
            priority = 70,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Trinket"] = {
            name = "Trinket",
            icon = "Interface\\Icons\\INV_Jewelry_Talisman_07",
            rules = {
                { type = "itemSubtype", value = "INVTYPE_TRINKET" }
            },
            matchMode = "all",
            priority = 72,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Consumable"] = {
            name = "Consumable",
            icon = "Interface\\Icons\\INV_Potion_54",
            rules = {
                { type = "itemType", value = "Consumable" }
            },
            matchMode = "all",
            priority = 50,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Food"] = {
            name = "Food",
            icon = "Interface\\Icons\\INV_Misc_Food_14",
            rules = {
                { type = "itemType", value = "Consumable" },
                { type = "restoreTag", value = "eat" }
            },
            matchMode = "all",
            priority = 55,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Drink"] = {
            name = "Drink",
            icon = "Interface\\Icons\\INV_Drink_07",
            rules = {
                { type = "itemType", value = "Consumable" },
                { type = "restoreTag", value = "drink" }
            },
            matchMode = "all",
            priority = 55,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Trade Goods"] = {
            name = "Trade Goods",
            icon = "Interface\\Icons\\INV_Fabric_Silk_02",
            rules = {
                { type = "itemType", value = "Trade Goods" }
            },
            matchMode = "all",
            priority = 40,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Reagent"] = {
            name = "Reagent",
            icon = "Interface\\Icons\\INV_Misc_Dust_02",
            rules = {
                { type = "itemType", value = "Reagent" }
            },
            matchMode = "all",
            priority = 40,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Recipe"] = {
            name = "Recipe",
            icon = "Interface\\Icons\\INV_Scroll_03",
            rules = {
                { type = "itemType", value = "Recipe" }
            },
            matchMode = "all",
            priority = 40,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Quiver"] = {
            name = "Quiver",
            icon = "Interface\\Icons\\INV_Misc_Quiver_03",
            rules = {
                { type = "itemType", value = "Quiver" }
            },
            matchMode = "all",
            priority = 40,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Container"] = {
            name = "Container",
            icon = "Interface\\Icons\\INV_Misc_Bag_07",
            rules = {
                { type = "itemType", value = "Container" }
            },
            matchMode = "all",
            priority = 40,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Soul Bag"] = {
            name = "Soul Bag",
            icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedMageweave",
            rules = {
                { type = "itemSubtype", value = "Soul Bag" }
            },
            matchMode = "all",
            priority = 45,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Miscellaneous"] = {
            name = "Miscellaneous",
            icon = "Interface\\Icons\\INV_Misc_Rune_01",
            rules = {},
            matchMode = "any",
            priority = 0,
            enabled = true,
            isBuiltIn = true,
            isFallback = true,
            group = GROUP_MAIN,
        },
        ["Quest"] = {
            name = "Quest",
            icon = "Interface\\Icons\\INV_Misc_Book_08",
            rules = {
                { type = "isQuestItem", value = true }
            },
            matchMode = "all",
            priority = 80,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Junk"] = {
            name = "Junk",
            icon = "Interface\\Icons\\INV_Misc_Gear_06",
            rules = {
                { type = "isJunk", value = true }
            },
            matchMode = "any",
            priority = 85,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_MAIN,
        },
        ["Class Items"] = {
            name = "Class Items",
            icon = "Interface\\Icons\\INV_Misc_Ammo_Arrow_01",
            rules = {
                { type = "itemType", value = "Projectile" },
                { type = "isSoulShard", value = true }
            },
            matchMode = "any",
            priority = 90,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_CLASS,
        },
        ["Keyring"] = {
            name = "Keyring",
            icon = "Interface\\Icons\\INV_Misc_Key_04",
            rules = {
                { type = "itemType", value = "Key" }
            },
            matchMode = "all",
            priority = 40,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_CLASS,
        },
        ["Home"] = {
            name = "Home",
            icon = "Interface\\Icons\\INV_Misc_Rune_01",
            rules = {
                { type = "itemID", value = {6948} }
            },
            matchMode = "all",
            priority = 100,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_OTHER,
        },
        ["Tools"] = {
            name = "Tools",
            icon = "Interface\\Icons\\Trade_BlackSmithing",
            rules = {
                { type = "isProfessionTool", value = true }
            },
            matchMode = "all",
            priority = 72,
            enabled = true,
            isBuiltIn = true,
            group = GROUP_OTHER,
        },
        ["Empty"] = {
            name = "Empty",
            icon = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag",
            rules = {},
            matchMode = "all",
            priority = -10,
            enabled = true,
            isBuiltIn = true,
            hideControls = true,
            isEmptyCategory = true,
            group = GROUP_OTHER,
        },
    }
}

-- 用于显示顺序和内置分组映射的分组定义
local GROUP_ORDER = { GROUP_MAIN, GROUP_CLASS, GROUP_OTHER }

-- 内置分类 ID 到其默认分组的映射（用于迁移）
local BUILTIN_GROUP_MAP = {}
for id, def in pairs(DEFAULT_CATEGORIES.definitions) do
    BUILTIN_GROUP_MAP[id] = def.group
end

-- 深拷贝表
local function deepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = deepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- 获取默认分类（返回深拷贝）
function CategoryManager:GetDefaultCategories()
    return deepCopy(DEFAULT_CATEGORIES)
end

-- 从数据库或默认值初始化分类
function CategoryManager:Initialize()
    if not Guda_CharDB then return end

    if not Guda_CharDB.categories then
        Guda_CharDB.categories = self:GetDefaultCategories()
        addon:Debug("CategoryManager: Initialized with default categories")
    else
        -- 确保所有内置分类都存在（迁移支持）
        self:MigrateCategories()
    end
end

-- 迁移/更新分类，确保所有内置分类存在
function CategoryManager:MigrateCategories()
    local cats = Guda_CharDB.categories
    if not cats then return end

    -- 确保 definitions 表存在
    if not cats.definitions then
        cats.definitions = {}
    end

    -- 确保 order 表存在
    if not cats.order then
        cats.order = {}
    end

    -- 添加任何缺失的内置分类
    for id, def in pairs(DEFAULT_CATEGORIES.definitions) do
        if not cats.definitions[id] then
            cats.definitions[id] = deepCopy(def)
            -- 如果不存在则添加到 order 末尾
            local found = false
            for _, orderId in ipairs(cats.order) do
                if orderId == id then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(cats.order, id)
            end
            addon:Debug("CategoryManager: Added missing built-in category: " .. id)
        end
    end

    -- 将 Food/Drink 分类迁移为使用 restoreTag 而非 itemSubtype
    -- 这修复了 "Food & Drink" 子类型同时匹配两个分类的问题
    local foodCat = cats.definitions["Food"]
    if foodCat and foodCat.isBuiltIn then
        local needsUpdate = false
        if foodCat.rules then
            for _, rule in ipairs(foodCat.rules) do
                if rule.type == "itemSubtype" then
                    needsUpdate = true
                    break
                end
            end
        end
        if needsUpdate then
            foodCat.rules = {
                { type = "itemType", value = "Consumable" },
                { type = "restoreTag", value = "eat" }
            }
            addon:Debug("CategoryManager: Migrated Food category to use restoreTag")
        end
    end

    local drinkCat = cats.definitions["Drink"]
    if drinkCat and drinkCat.isBuiltIn then
        local needsUpdate = false
        if drinkCat.rules then
            for _, rule in ipairs(drinkCat.rules) do
                if rule.type == "itemSubtype" then
                    needsUpdate = true
                    break
                end
            end
        end
        if needsUpdate then
            drinkCat.rules = {
                { type = "itemType", value = "Consumable" },
                { type = "restoreTag", value = "drink" }
            }
            addon:Debug("CategoryManager: Migrated Drink category to use restoreTag")
        end
    end

    -- 将 BoE 优先级迁移为高于 Weapon/Armor（75 > 70）
    local boeCat = cats.definitions["BoE"]
    if boeCat and boeCat.isBuiltIn and boeCat.priority and boeCat.priority < 75 then
        boeCat.priority = 75
        addon:Debug("CategoryManager: Migrated BoE priority to 75")
    end

    -- 将 Junk 分类迁移为使用 isJunk 规则类型
    local junkCat = cats.definitions["Junk"]
    if junkCat and junkCat.isBuiltIn then
        local needsUpdate = false
        -- 检查优先级是否过低
        if not junkCat.priority or junkCat.priority < 85 then
            junkCat.priority = 85
            needsUpdate = true
        end
        -- 从 quality=0 规则迁移到 isJunk 规则
        if junkCat.rules then
            for i, rule in ipairs(junkCat.rules) do
                if rule.type == "quality" and rule.value == 0 then
                    junkCat.rules = { { type = "isJunk", value = true } }
                    needsUpdate = true
                    break
                end
            end
        end
        -- 检查规则是否缺失或错误
        if not junkCat.rules or table.getn(junkCat.rules) == 0 then
            junkCat.rules = { { type = "isJunk", value = true } }
            needsUpdate = true
        end
        if needsUpdate then
            addon:Debug("CategoryManager: Migrated Junk category to use isJunk rule")
        end
    end

    -- 迁移：为所有缺少 group 的分类添加分组
    for id, def in pairs(cats.definitions) do
        if not def.group then
            -- 使用内置映射（如果可用），否则默认为 Main
            def.group = BUILTIN_GROUP_MAP[id] or GROUP_MAIN
            addon:Debug("CategoryManager: Added group '%s' to category: %s", def.group, id)
        end
    end

    -- 确保 savedEquipSetProps 表存在
    if not cats.savedEquipSetProps then
        cats.savedEquipSetProps = {}
    end

    -- 确保 deletedEquipSetCats 表存在（持久化套装删除）
    if not cats.deletedEquipSetCats then
        cats.deletedEquipSetCats = {}
    end

    -- 迁移：将每个分类的 itemOverrides 数组转换为 categories 级别的平面映射
    if not cats.itemOverrides then
        cats.itemOverrides = {}
    end
    -- 始终确保内置物品覆盖存在（覆盖在添加这些之前创建的旧存档）。
    -- 用户覆盖会被保留，因为我们只
    -- 填充缺失的键。
    for itemID, catId in pairs(BUILTIN_ITEM_OVERRIDES) do
        if not cats.itemOverrides[itemID] then
            cats.itemOverrides[itemID] = catId
        end
    end
    local migratedOverrides = false
    for catId, def in pairs(cats.definitions) do
        if def.itemOverrides and type(def.itemOverrides) == "table" then
            -- 通过查找数字键来判断是否为数组（旧格式）
            local isArray = false
            for k, v in pairs(def.itemOverrides) do
                if type(k) == "number" then
                    isArray = true
                    break
                end
            end
            if isArray then
                for _, itemID in ipairs(def.itemOverrides) do
                    cats.itemOverrides[itemID] = catId
                    migratedOverrides = true
                end
                def.itemOverrides = nil
            end
        end
    end
    if migratedOverrides then
        addon:Debug("CategoryManager: Migrated per-category itemOverrides to flat map")
    end

    -- 迁移 Home 分类：添加规则并移除 hideControls
    local homeCat = cats.definitions["Home"]
    if homeCat and homeCat.isBuiltIn then
        -- 移除 hideControls
        if homeCat.hideControls then
            homeCat.hideControls = nil
            addon:Debug("CategoryManager: Removed hideControls from Home")
        end
        -- 如果规则为空则添加
        if not homeCat.rules or table.getn(homeCat.rules) == 0 then
            homeCat.rules = { { type = "itemID", value = {6948} } }
            homeCat.priority = 100
            addon:Debug("CategoryManager: Added itemID rule to Home category")
        end
        -- 确保分组是 Other
        if homeCat.group ~= GROUP_OTHER then
            homeCat.group = GROUP_OTHER
        end
    end

    -- 迁移 Class Items：如果缺少则添加 isSoulShard 规则
    local classItemsCat = cats.definitions["Class Items"]
    if classItemsCat and classItemsCat.isBuiltIn then
        local hasSoulShard = false
        if classItemsCat.rules then
            for _, rule in ipairs(classItemsCat.rules) do
                if rule.type == "isSoulShard" then
                    hasSoulShard = true
                    break
                end
            end
        end
        if not hasSoulShard then
            if not classItemsCat.rules then classItemsCat.rules = {} end
            table.insert(classItemsCat.rules, { type = "isSoulShard", value = true })
            classItemsCat.matchMode = "any"
            addon:Debug("CategoryManager: Added isSoulShard rule to Class Items")
        end
    end

    -- 迁移 Tools 优先级：必须高于 Weapon (70)，以捕获鱼竿、剥皮刀等
    local toolsCat = cats.definitions["Tools"]
    if toolsCat and toolsCat.isBuiltIn and toolsCat.priority and toolsCat.priority < 72 then
        toolsCat.priority = 72
        addon:Debug("CategoryManager: Updated Tools priority to 72 (above Weapon/Armor)")
    end

    -- 迁移：将新添加的内置分类移到 order 中合适的位置。
    -- "Recently Looted" 应为列表首位，"BoP" 应紧邻 "BoE" 之前。
    -- 仅在它们是刚被内置迁移添加（位于 order 末尾附近）时执行。
    local freshRecent = false
    local freshBoP = false
    local n = table.getn(cats.order)
    if n > 0 then
        -- 同时新增两个分类时，它们会依次追加到末尾，
        -- 因此同时检查末尾与倒数第二的位置。
        local last = cats.order[n]
        local secondLast = n > 1 and cats.order[n - 1] or nil
        if last == "Recently Looted" or secondLast == "Recently Looted" then freshRecent = true end
        if last == "BoP" or secondLast == "BoP" then freshBoP = true end
    end
    if freshRecent or freshBoP then
        local function RemoveId(id)
            for i = table.getn(cats.order), 1, -1 do
                if cats.order[i] == id then
                    table.remove(cats.order, i)
                    return
                end
            end
        end
        local function InsertBefore(id, beforeId)
            for i, oid in ipairs(cats.order) do
                if oid == beforeId then
                    table.insert(cats.order, i, id)
                    return
                end
            end
            table.insert(cats.order, 1, id)
        end
        if freshRecent then
            RemoveId("Recently Looted")
            -- 插入到 order 首位
            table.insert(cats.order, 1, "Recently Looted")
            addon:Debug("CategoryManager: Moved Recently Looted to front of category order")
        end
        if freshBoP then
            RemoveId("BoP")
            InsertBefore("BoP", "BoE")
            addon:Debug("CategoryManager: Positioned BoP before BoE in category order")
        end
    end

    -- 确保 order 列表中的新分类处于正确位置
    -- 检查 order 是否需要重建以包含新的基于分组的排序
    local hasTools, hasEmpty = false, false
    for _, id in ipairs(cats.order) do
        if id == "Tools" then hasTools = true end
        if id == "Empty" then hasEmpty = true end
    end

    -- 如果 Tools 或 Empty 刚被上面的内置迁移添加，它们已经在 order 末尾。
    -- 将它们移到 Other 分组区域。
    if hasTools or hasEmpty then
        -- 重建 order 以遵循分组：Other、Main、Class
        local grouped = {}
        for _, g in ipairs(GROUP_ORDER) do
            grouped[g] = {}
        end
        grouped["_ungrouped"] = {}

        for _, id in ipairs(cats.order) do
            local def = cats.definitions[id]
            if def then
                local g = def.group or GROUP_MAIN
                if grouped[g] then
                    table.insert(grouped[g], id)
                else
                    table.insert(grouped["_ungrouped"], id)
                end
            end
        end

        -- 重建 order
        local newOrder = {}
        for _, g in ipairs(GROUP_ORDER) do
            if grouped[g] then
                for _, id in ipairs(grouped[g]) do
                    table.insert(newOrder, id)
                end
            end
        end
        for _, id in ipairs(grouped["_ungrouped"]) do
            table.insert(newOrder, id)
        end

        cats.order = newOrder
        addon:Debug("CategoryManager: Rebuilt category order for group ordering")
    end
end

-- 获取所有分类
function CategoryManager:GetCategories()
    if not Guda_CharDB or not Guda_CharDB.categories then
        return self:GetDefaultCategories()
    end
    return Guda_CharDB.categories
end

-- 获取分类顺序
function CategoryManager:GetCategoryOrder()
    local cats = self:GetCategories()
    return cats.order or {}
end

-- 按 ID 获取分类定义
function CategoryManager:GetCategory(categoryId)
    local cats = self:GetCategories()
    if cats.definitions then
        return cats.definitions[categoryId]
    end
    return nil
end

-- 返回分类的本地化显示名称。
-- 内置分类通过 GudaBag.L 翻译；自定义分类保留用户输入的名称。
-- 当没有可用名称时回退到原始 id。
function CategoryManager:GetDisplayName(categoryId, catDef)
    local def = catDef or self:GetCategory(categoryId)
    local base = (def and def.name) or categoryId or ""
    if def and def.isBuiltIn and GudaBag.L and GudaBag.L[base] then
        return GudaBag.L[base]
    end
    return base
end

-- 将分类保存到数据库
function CategoryManager:SaveCategories(categories)
    if not Guda_CharDB then return end
    Guda_CharDB.categories = categories
    -- 分类变更时清空缓存
    self:ClearCache()
end

-- 添加一个新的自定义分类
-- 如果 categoryId 为 nil，自动生成类似 "Custom_<time>_<random>" 的唯一 ID
function CategoryManager:AddCategory(categoryId, definition)
    local cats = self:GetCategories()

    -- 如果未提供则自动生成 ID
    if not categoryId then
        categoryId = "Custom_" .. time() .. "_" .. math.random(1000, 9999)
        -- 确保唯一
        while cats.definitions[categoryId] do
            categoryId = "Custom_" .. time() .. "_" .. math.random(1000, 9999)
        end
    end

    if cats.definitions[categoryId] then
        addon:Debug("CategoryManager: Category already exists: " .. categoryId)
        return false
    end

    definition.isBuiltIn = definition.isBuiltIn or false
    if not definition.group then
        definition.group = GROUP_MAIN
    end
    cats.definitions[categoryId] = definition

    -- 在 order 列表中该分类所属分组的末尾插入
    local insertPos = nil
    local group = definition.group
    -- 查找同一分组中的最后一个分类
    for i = table.getn(cats.order), 1, -1 do
        local existDef = cats.definitions[cats.order[i]]
        if existDef and existDef.group == group then
            insertPos = i + 1
            break
        end
    end
    if insertPos then
        -- Lua 5.0 带位置的 table.insert
        table.insert(cats.order, insertPos, categoryId)
    else
        table.insert(cats.order, categoryId)
    end

    self:SaveCategories(cats)
    return true, categoryId
end

-- 更新现有分类
function CategoryManager:UpdateCategory(categoryId, definition)
    local cats = self:GetCategories()

    if not cats.definitions[categoryId] then
        addon:Debug("CategoryManager: Category not found: " .. categoryId)
        return false
    end

    -- 浅合并：用新字段更新现有定义
    -- 这保留调用方未传入的字段（group、priority、categoryMark 等）
    local existing = cats.definitions[categoryId]
    for k, v in pairs(definition) do
        existing[k] = v
    end
    -- 始终保留原始 isBuiltIn
    existing.isBuiltIn = existing.isBuiltIn

    self:SaveCategories(cats)
    return true
end

-- 删除分类（只能删除自定义分类）
function CategoryManager:DeleteCategory(categoryId)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]

    if not def then
        return false
    end

    if def.isBuiltIn then
        addon:Debug("CategoryManager: Cannot delete built-in category: " .. categoryId)
        return false
    end

    -- 持久化与配装（装备套装）关联的分类删除，以便同步不会在下次登录
    -- 或 Outfitter 事件时重新创建它们。
    if def.isEquipSetCategory then
        if not cats.deletedEquipSetCats then
            cats.deletedEquipSetCats = {}
        end
        cats.deletedEquipSetCats[categoryId] = true
        -- 丢弃已保存的属性，以便将来显式恢复时从头开始
        if cats.savedEquipSetProps then
            cats.savedEquipSetProps[categoryId] = nil
        end
        addon:Debug("CategoryManager: Equipment set category '%s' marked deleted", categoryId)
    end

    cats.definitions[categoryId] = nil

    -- 从 order 中移除
    for i, id in ipairs(cats.order) do
        if id == categoryId then
            table.remove(cats.order, i)
            break
        end
    end

    self:SaveCategories(cats)
    return true
end

-- 检查分类能否在其分组内上移
function CategoryManager:CanMoveUp(categoryId)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]
    if not def or def.hideControls then return false end

    for i, id in ipairs(cats.order) do
        if id == categoryId then
            -- 查找任意前一个非 hideControls 分类（可以跨越分组边界）
            for j = i - 1, 1, -1 do
                local prevDef = cats.definitions[cats.order[j]]
                if prevDef and not prevDef.hideControls then
                    return true
                end
            end
            return false -- 第一个可移动的分类
        end
    end
    return false
end

-- 检查分类能否下移（可跨越分组边界）
function CategoryManager:CanMoveDown(categoryId)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]
    if not def or def.hideControls then return false end

    local count = table.getn(cats.order)
    for i, id in ipairs(cats.order) do
        if id == categoryId then
            -- 查找任意下一个非 hideControls 分类（可以跨越分组边界）
            for j = i + 1, count do
                local nextDef = cats.definitions[cats.order[j]]
                if nextDef and not nextDef.hideControls then
                    return true
                end
            end
            return false -- 最后一个可移动的分类
        end
    end
    return false
end

-- 在 order 中上移分类（跨越分组边界时更改分组）
function CategoryManager:MoveCategoryUp(categoryId)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]
    if not def or def.hideControls then return false end

    for i, id in ipairs(cats.order) do
        if id == categoryId then
            -- 查找前一个非 hideControls 分类
            for j = i - 1, 1, -1 do
                local prevDef = cats.definitions[cats.order[j]]
                if prevDef and not prevDef.hideControls then
                    -- 交换位置
                    cats.order[i] = cats.order[j]
                    cats.order[j] = categoryId
                    -- 如果跨越到不同分组，则采用该分组
                    local prevGroup = prevDef.group or GROUP_MAIN
                    if (def.group or GROUP_MAIN) ~= prevGroup then
                        def.group = prevGroup
                    end
                    self:SaveCategories(cats)
                    return true
                end
            end
            return false
        end
    end
    return false
end

-- 在 order 中下移分类（跨越分组边界时更改分组）
function CategoryManager:MoveCategoryDown(categoryId)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]
    if not def or def.hideControls then return false end

    local count = table.getn(cats.order)

    for i, id in ipairs(cats.order) do
        if id == categoryId then
            -- 查找下一个非 hideControls 分类
            for j = i + 1, count do
                local nextDef = cats.definitions[cats.order[j]]
                if nextDef and not nextDef.hideControls then
                    -- 交换位置
                    cats.order[i] = cats.order[j]
                    cats.order[j] = categoryId
                    -- 如果跨越到不同分组，则采用该分组
                    local nextGroup = nextDef.group or GROUP_MAIN
                    if (def.group or GROUP_MAIN) ~= nextGroup then
                        def.group = nextGroup
                    end
                    self:SaveCategories(cats)
                    return true
                end
            end
            return false
        end
    end
    return false
end

-- 切换分类的启用状态
function CategoryManager:ToggleCategory(categoryId)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]

    if def then
        def.enabled = not def.enabled
        self:SaveCategories(cats)
        return true
    end
    return false
end

-- 将所有分类重置为默认值
function CategoryManager:ResetToDefaults()
    Guda_CharDB.categories = self:GetDefaultCategories()
    addon:Debug("CategoryManager: Reset to default categories")
end

-------------------------------------------
-- 规则评估引擎
-------------------------------------------

-- 对物品数据评估单条规则
function CategoryManager:EvaluateRule(rule, itemData, bagID, slotID, isOtherChar)
    local ruleType = rule.type
    local ruleValue = rule.value

    if ruleType == "itemType" then
        return (itemData.class == ruleValue) or (itemData.type == ruleValue)

    elseif ruleType == "itemSubtype" then
        local subclass = itemData.subclass or ""
        -- 检查部分匹配（例如 "Food" 匹配 "Food & Drink"）
        if string.find(subclass, ruleValue) then
            return true
        end
        return subclass == ruleValue

    elseif ruleType == "namePattern" then
        local itemName = itemData.name or ""
        return string.find(itemName, ruleValue) ~= nil

    elseif ruleType == "quality" then
        -- 对于品质 0（灰色/垃圾），同时检查工具提示作为回退
        if ruleValue == 0 then
            if itemData.quality == 0 then
                return true
            end
            -- 灰色检测的工具提示回退（仅当前角色）
            if not isOtherChar and addon.Modules.Utils and addon.Modules.Utils.IsItemGrayTooltip then
                return addon.Modules.Utils:IsItemGrayTooltip(bagID, slotID, itemData.link)
            end
            return false
        end
        return itemData.quality == ruleValue

    elseif ruleType == "qualityMin" then
        -- 最低品质检查（物品品质 >= ruleValue）
        return (itemData.quality or 0) >= (ruleValue or 0)

    elseif ruleType == "isBoE" then
        if isOtherChar then return false end
        if itemData.class ~= "Weapon" and itemData.class ~= "Armor" then
            return false
        end
        local isBoE = addon.Modules.Utils:IsBindOnEquip(bagID, slotID, itemData.link)
        return isBoE == ruleValue

    elseif ruleType == "isBoP" then
        if isOtherChar then return false end
        if itemData.class ~= "Weapon" and itemData.class ~= "Armor" then
            return false
        end
        local isBoP = addon.Modules.Utils:IsBindOnPickup(bagID, slotID, itemData.link)
        return isBoP == ruleValue

    elseif ruleType == "isQuestItem" then
        -- 使用集中的 ItemDetection 进行任务物品检测
        if addon.Modules.ItemDetection then
            local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
            return props.isQuestItem == ruleValue
        end
        -- 如果 ItemDetection 不可用则回退到 Utils
        local isQuestItem, _ = addon.Modules.Utils:IsQuestItem(bagID, slotID, itemData, isOtherChar, false)
        return isQuestItem == ruleValue

    elseif ruleType == "texturePattern" then
        local texture = itemData.texture or ""
        return string.find(string.lower(texture), string.lower(ruleValue)) ~= nil

    elseif ruleType == "itemID" then
        if not itemData.link then return false end
        local itemID = addon.Modules.Utils:ExtractItemID(itemData.link)
        if not itemID then return false end

        -- ruleValue 可以是单个 ID 或 ID 表
        if type(ruleValue) == "table" then
            for _, id in ipairs(ruleValue) do
                if itemID == tonumber(id) then return true end
            end
            return false
        else
            -- 如果需要，将字符串转换为数字
            return itemID == tonumber(ruleValue)
        end

    elseif ruleType == "isSoulShard" then
        return addon.Modules.Utils:IsSoulShard(itemData.link) == ruleValue

    elseif ruleType == "isProjectile" then
        local isProj = (itemData.class == "Projectile" or
                        itemData.subclass == "Arrow" or
                        itemData.subclass == "Bullet")
        return isProj == ruleValue

    elseif ruleType == "restoreTag" then
        -- restoreTag 由工具提示扫描设置："eat"、"drink" 或 "restore"
        local tag = itemData.restoreTag
        if not tag then return false end
        return tag == ruleValue

    elseif ruleType == "isRecentlyLooted" then
        -- 最近拾取：基于物品链接的全包总数变化（见 Core/RecentLoot.lua）。
        -- 注意：此规则是时间敏感的，CategorizeItem 不会缓存其结果。
        if isOtherChar then return false end
        if not addon.Modules.RecentLoot or not itemData.link then return false end
        local window = ruleValue or addon.Modules.RecentLoot.DEFAULT_WINDOW
        return addon.Modules.RecentLoot:IsRecentlyLooted(itemData.link, window)

    elseif ruleType == "isProfessionTool" then
        -- 按 ID 或子类型检查物品是否为专业工具
        local isProfessionTool = false

        -- 按物品 ID 检查
        if itemData.link then
            local itemID = addon.Modules.Utils:ExtractItemID(itemData.link)
            if itemID and addon.Constants.PROFESSION_TOOL_IDS and addon.Constants.PROFESSION_TOOL_IDS[itemID] then
                isProfessionTool = true
            end
        end

        -- 按子类型检查（例如 Fishing Pole 钓鱼竿）
        if not isProfessionTool then
            local itemSubclass = itemData.subclass or ""
            if addon.Constants.PROFESSION_TOOL_SUBTYPES and addon.Constants.PROFESSION_TOOL_SUBTYPES[itemSubclass] then
                isProfessionTool = true
            end
        end

        return isProfessionTool == ruleValue

    elseif ruleType == "isJunk" then
        -- 使用集中的 ItemDetection 进行垃圾检测
        if addon.Modules.ItemDetection then
            local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
            return props.isJunk == ruleValue
        end
        -- 回退：灰色物品永远是垃圾
        return (itemData.quality == 0) == ruleValue
    end

    return false
end

-- 评估一个分类的所有规则
function CategoryManager:EvaluateCategoryRules(categoryDef, itemData, bagID, slotID, isOtherChar)
    if not categoryDef.enabled then
        return false
    end

    local rules = categoryDef.rules or {}

    -- 没有规则 = 回退分类（匹配所有物品）
    if table.getn(rules) == 0 then
        return categoryDef.isFallback == true
    end

    local matchMode = categoryDef.matchMode or "any"

    local hasRequired, hasOptional = false, false
    local requiredAllPass, optionalAnyPass, optionalAllPass = true, false, true

    for _, rule in ipairs(rules) do
        local pass = self:EvaluateRule(rule, itemData, bagID, slotID, isOtherChar)
        if rule.required then
            hasRequired = true
            if not pass then requiredAllPass = false end
        else
            hasOptional = true
            if pass then optionalAnyPass = true else optionalAllPass = false end
        end
    end

    if matchMode == "all" then
        if hasRequired and not requiredAllPass then return false end
        if hasOptional and not optionalAllPass then return false end
        return true
    else
        -- "any" 模式：必需规则必须全部通过；可选规则中至少有一个必须通过
        if hasRequired and not requiredAllPass then return false end
        if hasOptional then return optionalAnyPass end
        return hasRequired
    end
end

-- 按优先级获取排序后的分类（最高的在前）
function CategoryManager:GetCategoriesByPriority()
    local cats = self:GetCategories()
    local sorted = {}

    for id, def in pairs(cats.definitions) do
        if def.enabled then
            table.insert(sorted, { id = id, def = def })
        end
    end

    table.sort(sorted, function(a, b)
        return (a.def.priority or 0) > (b.def.priority or 0)
    end)

    return sorted
end

-- 仅缓存变体。如果存在则返回缓存的分类 ID，否则返回 nil。
-- 供打开背包的布局路径使用，这样它永远不会触发冷缓存规则评估
-- （那会级联成每个物品的工具提示扫描）。CacheWarmer 在后台填充缓存；
-- 预热完成后背包会重新布局。
function CategoryManager:CategorizeItemCached(itemData, isOtherChar)
    if not itemData or not itemData.link then return nil end
    local cacheKey = GetCacheKey(itemData.link, isOtherChar)
    if not cacheKey then return nil end
    return categoryCache[cacheKey]
end

-- 使用规则引擎对物品进行分类
-- 返回分类 ID，或回退到 "Miscellaneous"
function CategoryManager:CategorizeItem(itemData, bagID, slotID, isOtherChar)
    -- 先检查缓存
    local cacheKey = GetCacheKey(itemData and itemData.link, isOtherChar)
    if cacheKey and categoryCache[cacheKey] then
        cacheHits = cacheHits + 1
        return categoryCache[cacheKey]
    end
    cacheMisses = cacheMisses + 1

    -- 重新分类 itemType 错误的可装备物品（例如 Trade Goods 饰品/装置）
    -- 如果子类指示装备槽位，则视为 Armor
    if itemData and itemData.subclass then
        local sub = itemData.subclass
        if sub == "INVTYPE_TRINKET" or sub == "INVTYPE_FINGER" or sub == "INVTYPE_NECK"
            or sub == "INVTYPE_HEAD" or sub == "INVTYPE_SHOULDER" or sub == "INVTYPE_CHEST"
            or sub == "INVTYPE_WAIST" or sub == "INVTYPE_LEGS" or sub == "INVTYPE_FEET"
            or sub == "INVTYPE_WRIST" or sub == "INVTYPE_HAND" or sub == "INVTYPE_CLOAK"
            or sub == "INVTYPE_ROBE" or sub == "INVTYPE_BODY" then
            if itemData.class ~= "Armor" and itemData.class ~= "Weapon" then
                local override = {}
                for k, v in pairs(itemData) do override[k] = v end
                override.class = "Armor"
                itemData = override
            end
        end
    end

    -- 将盾牌和副手重新分类为武器（用户偏好：盾牌/副手
    -- 计为武器，而非护甲）。equipSlot 是与语言环境无关的 INVTYPE_* 标记
    -- （zhCN 子类 "盾牌"/"副手" 是本地化的，不适合直接匹配）。
    if itemData and itemData.equipSlot then
        local es = itemData.equipSlot
        if es == "INVTYPE_SHIELD" or es == "INVTYPE_HOLDABLE" then
            if itemData.class ~= "Weapon" then
                local override = {}
                for k, v in pairs(itemData) do override[k] = v end
                override.class = "Weapon"
                itemData = override
            end
        end
    end

    -- 重新分类被游戏误标记为 Reagent（材料）的商品。
    -- 在某些客户端上，这些物品的物品类别被报告为 "Reagent"，尽管它们
    -- 实际上是 Trade Goods（商品），因此将它们移到 Trade Goods，
    -- 以免落入 施法材料。
    --   - 木制品（普通木柴 / 影木 / 亮木 / ...）：名称含 木 / "wood"
    --   - 元素试剂：大地/火焰/水之/空气/冰霜/生命 的精华，以及
    --     之心 / 之核 —— 例如 大地精华、火焰之心。这些属于
    --     Trade Goods，而不是施法材料。
    --   - 附魔精华（魔法/星界/梦境/幻象 + 精华）有意保留在
    --     施法材料 中，粉尘 / 碎片 同理。
    if itemData and itemData.class == "Reagent" and itemData.name then
        local nm = itemData.name
        local isTradeGood = false
        -- 木制品（普通木柴 / 影木 / 亮木 / ...）属于 Trade Goods。德鲁伊施法
        -- 种子（铁木种子 / 枫树种子 / ...）也含 木，但它们是真正的施法材料，
        -- 因此排除任何带 种子 的名称。
        if (string.find(nm, "木") or string.find(string.lower(nm), "wood"))
           and not string.find(nm, "种子") then
            isTradeGood = true
        elseif string.find(nm, "精华") and
               (string.find(nm, "大地") or string.find(nm, "火焰") or
                string.find(nm, "水之") or string.find(nm, "空气") or
                string.find(nm, "冰霜") or string.find(nm, "生命")) then
            isTradeGood = true
        elseif string.find(nm, "之心") or string.find(nm, "之核") then
            isTradeGood = true
        elseif string.find(nm, "羽毛") then
            -- 羽毛（细长的尾羽 / 柔软的羽毛 / ...）属于 Trade Goods，不是
            -- 施法材料。轻羽毛 (Light Feather, 17056) 也会在此匹配，
            -- 但会通过 BUILTIN_ITEM_OVERRIDES 被覆盖为职业物品。
            isTradeGood = true
        end
        if isTradeGood then
            local override = {}
            for k, v in pairs(itemData) do override[k] = v end
            override.class = "Trade Goods"
            itemData = override
        end
    end

    -- 不是蜂蜜酒的酒精饮料属于 Consumable，而不是 Drink。在 zhCN 客户端上，
    -- 所有饮料都会获得 restoreTag "drink"（来自 饮水/喝酒 的工具提示动词），
    -- 这会把它们归类到 饮料。蜂蜜酒（蜂蜜酒 / 蜂蜜饮料）保留在 饮料。
    -- 晨露酒（晨露酒）也保留在 饮料（它虽然名字含"酒"，但属于非酒精的淡酒类）。
    -- 我们对酒精饮料剥离 drink 标记，使它们
    -- 转而落入 Consumable 分类。
    if itemData and itemData.class == "Consumable" and itemData.restoreTag == "drink"
       and itemData.name then
        local nm = itemData.name
        if string.find(nm, "酒") and not string.find(nm, "蜂蜜酒") and not string.find(nm, "晨露酒") then
            local override = {}
            for k, v in pairs(itemData) do override[k] = v end
            override.restoreTag = nil
            itemData = override
        end
    end

    -- 先检查物品覆盖（平面映射：itemID -> categoryId）
    local itemID
    if itemData and itemData.link then
        itemID = addon.Modules.Utils:ExtractItemID(itemData.link)
        if itemID then
            local cats = self:GetCategories()
            if cats.itemOverrides then
                local overrideCatId = cats.itemOverrides[itemID]
                if overrideCatId then
                    local overrideDef = cats.definitions[overrideCatId]
                    if overrideDef and overrideDef.enabled then
                        if cacheKey then
                            categoryCache[cacheKey] = overrideCatId
                        end
                        return overrideCatId
                    end
                end
            end
        end
    end

    -- 装备套装分类（优先级高于基于规则的匹配）
    if itemID and addon.Modules.EquipmentSets then
        local showEquipSets = addon.Modules.DB:GetSetting("showEquipSetCategories")
        if showEquipSets ~= false then
            if addon.Modules.EquipmentSets:IsInSet(itemID) then
                local setNames = addon.Modules.EquipmentSets:GetSetNames(itemID)
                if setNames and table.getn(setNames) > 0 then
                    table.sort(setNames)
                    local catId = "EquipSet:" .. setNames[1]
                    local catDef = self:GetCategory(catId)
                    if catDef and catDef.enabled then
                        if cacheKey then
                            categoryCache[cacheKey] = catId
                        end
                        return catId
                    end
                end
            end
        end
    end

    local sortedCats = self:GetCategoriesByPriority()

    -- 调试：显示白色物品分类
    if itemData.quality == 1 and (itemData.class == "Weapon" or itemData.class == "Armor") then
        addon:Debug("Categorizing white equip: %s (class=%s, quality=%s)", tostring(itemData.name), tostring(itemData.class), tostring(itemData.quality))
        for i, entry in ipairs(sortedCats) do
            addon:Debug("  Cat %d: %s (priority=%s, enabled=%s)", i, entry.id, tostring(entry.def.priority), tostring(entry.def.enabled))
            if i > 10 then break end  -- 限制调试输出
        end
    end

    -- 评估所有分类。时间敏感的"最近拾取"分类（isRecentlyLooted 规则）
    -- 优先返回，但它依赖槽位时间戳，不能按链接缓存 —— 因此缓存的是
    -- 其"底层"分类（如 BoP / Armor），这样 10 分钟窗口过后物品会
    -- 正确落入底层分类，而不会永久停留在"最近拾取"。
    local result = "Miscellaneous"      -- 底层（可缓存）分类
    local recentMatch = nil             -- 时间敏感的最近拾取匹配
    for _, entry in ipairs(sortedCats) do
        if not entry.def.isFallback then
            local matches = self:EvaluateCategoryRules(entry.def, itemData, bagID, slotID, isOtherChar)
            -- 调试：显示白色装备匹配到哪个分类
            if itemData.quality == 1 and (itemData.class == "Weapon" or itemData.class == "Armor") and matches then
                addon:Debug("  -> MATCHED: %s", entry.id)
            end
            if matches then
                -- 判断该分类是否时间敏感（isRecentlyLooted）
                local isRecent = false
                if entry.def.rules then
                    for _, r in ipairs(entry.def.rules) do
                        if r.type == "isRecentlyLooted" then
                            isRecent = true
                            break
                        end
                    end
                end
                if isRecent then
                    recentMatch = entry.id
                    -- 不 break：继续查找底层（可缓存）分类
                elseif result == "Miscellaneous" then
                    result = entry.id
                    -- 底层分类已找到；可以停止
                    break
                end
            end
        end
    end

    -- 最近拾取优先作为最终返回结果（供直接调用方使用）
    local finalResult = recentMatch or result

    -- 缓存底层分类结果；时间敏感的"最近拾取"不缓存
    if cacheKey and result ~= "Recently Looted" then
        categoryCache[cacheKey] = result
    end

    return finalResult
end

-- 根据当前分类顺序构建 GudaBag.CategoryList（用于兼容性）
function CategoryManager:BuildCategoryList()
    local order = self:GetCategoryOrder()
    local list = {}

    for _, id in ipairs(order) do
        local def = self:GetCategory(id)
        if def and def.enabled then
            table.insert(list, id)
        end
    end

    return list
end

-------------------------------------------
-- 分组管理
-------------------------------------------

-- 从分类顺序中获取有序的唯一分组列表
function CategoryManager:GetGroups()
    local cats = self:GetCategories()
    local seen = {}
    local groups = {}
    for _, id in ipairs(cats.order) do
        local def = cats.definitions[id]
        if def then
            local g = def.group or GROUP_MAIN
            if not seen[g] then
                seen[g] = true
                table.insert(groups, g)
            end
        end
    end
    return groups
end

-- 按分组获取分类：{ groupName => {catIds} }
-- 同时返回没有任何分组的分类的未分组列表
function CategoryManager:GetCategoriesByGroup()
    local cats = self:GetCategories()
    local result = {}
    local ungrouped = {}

    for _, id in ipairs(cats.order) do
        local def = cats.definitions[id]
        if def then
            local g = def.group
            if g then
                if not result[g] then result[g] = {} end
                table.insert(result[g], id)
            else
                table.insert(ungrouped, id)
            end
        end
    end

    return result, ungrouped
end

-- 更改分类的分组
function CategoryManager:SetCategoryGroup(categoryId, groupName)
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]
    if not def then return false end

    local oldGroup = def.group or GROUP_MAIN
    if oldGroup == groupName then return true end

    def.group = groupName

    -- 从 order 中的当前位置移除
    local currentPos = nil
    for i, id in ipairs(cats.order) do
        if id == categoryId then
            currentPos = i
            break
        end
    end
    if currentPos then
        table.remove(cats.order, currentPos)
    end

    -- 插入到新分组的末尾
    local insertPos = nil
    for i = table.getn(cats.order), 1, -1 do
        local existDef = cats.definitions[cats.order[i]]
        if existDef and (existDef.group or GROUP_MAIN) == groupName then
            insertPos = i + 1
            break
        end
    end
    if insertPos then
        table.insert(cats.order, insertPos, categoryId)
    else
        table.insert(cats.order, categoryId)
    end

    self:SaveCategories(cats)
    return true
end

-- 获取分组常量
function CategoryManager:GetGroupMain() return GROUP_MAIN end
function CategoryManager:GetGroupOther() return GROUP_OTHER end
function CategoryManager:GetGroupClass() return GROUP_CLASS end

-------------------------------------------
-- 物品覆盖系统
-------------------------------------------

-- 按物品 ID 将物品分配到特定分类
-- 使用 categories 级别的平面映射：cats.itemOverrides[itemID] = categoryId
function CategoryManager:AssignItemToCategory(itemID, categoryId)
    if not itemID or not categoryId then return false end
    local cats = self:GetCategories()
    local def = cats.definitions[categoryId]
    if not def then return false end

    if not cats.itemOverrides then
        cats.itemOverrides = {}
    end

    cats.itemOverrides[itemID] = categoryId
    self:SaveCategories(cats)
    self:ClearCache()
    return true
end

-- 从特定分类的覆盖中移除物品
function CategoryManager:RemoveItemFromCategory(itemID, categoryId)
    if not itemID or not categoryId then return false end
    local cats = self:GetCategories()
    if not cats.itemOverrides then return false end

    if cats.itemOverrides[itemID] == categoryId then
        cats.itemOverrides[itemID] = nil
        self:SaveCategories(cats)
        self:ClearCache()
        return true
    end
    return false
end

-- 移除物品覆盖，无论其属于哪个分类
function CategoryManager:RemoveItemOverride(itemID)
    if not itemID then return end
    local cats = self:GetCategories()
    if cats.itemOverrides then
        cats.itemOverrides[itemID] = nil
    end
end

-------------------------------------------
-- 装备套装分类同步
-------------------------------------------

-- 注意：savedEquipSetProps 存储在 cats.savedEquipSetProps 中（持久化在 SavedVariables）
-- 当套装被删除/重新创建时，保留用户更改（启用状态、分组、标记、顺序位置）

-- 将装备套装分类与 EquipmentSets 模块的当前套装数据同步
function CategoryManager:SyncEquipmentSetCategories()
    local equipSets = addon.Modules.EquipmentSets
    if not equipSets then return end

    local showEquipSets = addon.Modules.DB:GetSetting("showEquipSetCategories")
    if showEquipSets == false then return end

    local setNames = equipSets:GetAllSetNames()
    if not setNames then return end

    local cats = self:GetCategories()
    local existingSetCats = {}

    -- 确保 savedEquipSetProps 表存在（持久化在 SavedVariables）
    if not cats.savedEquipSetProps then
        cats.savedEquipSetProps = {}
    end

    -- 确保 deletedEquipSetCats 表存在（持久化套装删除）
    if not cats.deletedEquipSetCats then
        cats.deletedEquipSetCats = {}
    end

    -- 查找现有的 EquipSet 分类
    for id, def in pairs(cats.definitions) do
        if string.find(id, "^EquipSet:") then
            existingSetCats[id] = true
        end
    end

    -- 为当前套装创建/更新分类
    for _, setName in ipairs(setNames) do
        local catId = "EquipSet:" .. setName
        -- 尊重用户删除：永远不重新创建用户已移除的套装分类
        if cats.deletedEquipSetCats[catId] then
            addon:Debug("CategoryManager: Skipping deleted equipment set category: " .. catId)
        elseif not cats.definitions[catId] then
            -- 检查先前已删除套装的已保存属性
            local props = cats.savedEquipSetProps[catId]
            local defaultMark = "Interface\\AddOns\\Guda\\Assets\\equipment"
            local newDef = {
                name = setName,
                icon = "Interface\\Icons\\INV_Chest_Chain_04",
                rules = {},
                matchMode = "all",
                priority = props and props.priority or 65,
                enabled = props and props.enabled or true,
                isBuiltIn = false,
                isEquipSetCategory = true,
                group = props and props.group or GROUP_MAIN,
                categoryMark = props and props.categoryMark or defaultMark,
            }
            cats.definitions[catId] = newDef

            -- 恢复已保存的顺序位置，或插入到 Main 分组末尾
            local insertPos = nil
            if props and props.orderPos then
                -- 限制在有效范围内
                insertPos = props.orderPos
                if insertPos > table.getn(cats.order) + 1 then
                    insertPos = table.getn(cats.order) + 1
                end
            end
            if not insertPos then
                -- 如果 Junk 分类存在则在其前插入，否则插入到 Main 分组末尾
                for i, orderId in ipairs(cats.order) do
                    if orderId == "Junk" then
                        insertPos = i
                        break
                    end
                end
            end
            if not insertPos then
                for i = table.getn(cats.order), 1, -1 do
                    local existDef = cats.definitions[cats.order[i]]
                    if existDef and (existDef.group or GROUP_MAIN) == GROUP_MAIN then
                        insertPos = i + 1
                        break
                    end
                end
            end
            if insertPos then
                table.insert(cats.order, insertPos, catId)
            else
                table.insert(cats.order, catId)
            end

            addon:Debug("CategoryManager: Created equipment set category: " .. catId)
        end
        existingSetCats[catId] = nil -- 标记为仍然有效
    end

    -- 移除不再存在的套装的分类
    for catId in pairs(existingSetCats) do
        local def = cats.definitions[catId]
        if def then
            -- 在移除前查找当前顺序位置
            local orderPos = nil
            for i, id in ipairs(cats.order) do
                if id == catId then
                    orderPos = i
                    break
                end
            end
            -- 在删除前保存用户编辑的属性（跨重载持久化）
            cats.savedEquipSetProps[catId] = {
                enabled = def.enabled,
                categoryMark = def.categoryMark,
                group = def.group,
                priority = def.priority,
                orderPos = orderPos,
            }
        end
        cats.definitions[catId] = nil
        for i, id in ipairs(cats.order) do
            if id == catId then
                table.remove(cats.order, i)
                break
            end
        end
        addon:Debug("CategoryManager: Removed equipment set category: " .. catId)
    end

    self:SaveCategories(cats)
end

-- 获取可用的规则类型（用于 UI）
function CategoryManager:GetRuleTypes()
    return {
        { id = "itemType", name = "Item Type", description = "Match by item class (Armor, Weapon, etc.)" },
        { id = "itemSubtype", name = "Item Subtype", description = "Match by item subclass (Cloth, Potion, etc.)" },
        { id = "namePattern", name = "Name Pattern", description = "Match item name (supports Lua patterns)" },
        { id = "quality", name = "Quality", description = "Match by item quality (0=Gray to 5=Legendary)" },
        { id = "qualityMin", name = "Quality (min)", description = "Match items with at least this quality" },
        { id = "isBoE", name = "Bind on Equip", description = "Match items that bind when equipped" },
        { id = "isBoP", name = "Bind on Pickup", description = "Match items that bind when picked up (e.g. raid BoP gear)" },
        { id = "isRecentlyLooted", name = "Recently Looted", description = "Match items acquired within the last N seconds (default 600)" },
        { id = "isQuestItem", name = "Quest Item", description = "Match quest items" },
        { id = "isJunk", name = "Is Junk", description = "Match junk items (gray + white equippable)" },
        { id = "isProfessionTool", name = "Profession Tool", description = "Match profession tools (skinning knife, mining pick, etc.)" },
        { id = "texturePattern", name = "Icon Pattern", description = "Match icon texture path" },
        { id = "itemID", name = "Item ID", description = "Match specific item IDs" },
        { id = "isSoulShard", name = "Soul Shard", description = "Match soul shards" },
        { id = "isProjectile", name = "Projectile", description = "Match arrows and bullets" },
        { id = "restoreTag", name = "Restore Type", description = "Match by consumable type (eat, drink, restore)" },
    }
end

-- 获取常见的物品类型（用于 UI 下拉框）
function CategoryManager:GetItemTypes()
    return {
        "Armor", "Weapon", "Consumable", "Container", "Trade Goods",
        "Projectile", "Quiver", "Reagent", "Recipe", "Key", "Miscellaneous", "Quest"
    }
end

-- 获取品质名称（用于 UI）
function CategoryManager:GetQualityNames()
    return {
        [0] = "Poor (Gray)",
        [1] = "Common (White)",
        [2] = "Uncommon (Green)",
        [3] = "Rare (Blue)",
        [4] = "Epic (Purple)",
        [5] = "Legendary (Orange)",
    }
end
