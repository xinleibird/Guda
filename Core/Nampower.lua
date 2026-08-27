-- Guda Nampower 集成模块
--
-- Nampower 是 Turtle WoW 的一个客户端扩展 DLL，提供更高效的低层 API
-- （GetBagItem / GetBagItems / GetItemStatsField / GetItemLevel 等）。
-- 本模块把这些 API 统一封装成安全的 GudaBag.Nampower 接口：
--   * 已安装 Nampower 时，用其快速 API 加速背包扫描、charges 读取等；
--   * 未安装时，所有封装自动回退（返回 nil/false），调用方走原生逻辑，
--     行为与没有本模块时完全一致。
--
-- 检测依据：Nampower 提供 GetNampowerVersion() 与 GetBagItem() 全局函数。

local addon = Guda

local Nampower = {}
addon.Modules.Nampower = Nampower

-- 是否检测到 Nampower（惰性检测一次）
local detected = nil
local hasVersionFn = GetNampowerVersion ~= nil
local hasBagItemFn = GetBagItem ~= nil
local hasBagItemsFn = GetBagItems ~= nil
local hasItemLevelFn = GetItemLevel ~= nil
local hasItemStatsFn = GetItemStats ~= nil
local hasItemStatsFieldFn = GetItemStatsField ~= nil
local hasFindSlotFn = FindPlayerItemSlot ~= nil

function Nampower:IsAvailable()
    if detected == nil then
        detected = (hasBagItemFn and (hasVersionFn or hasBagItemsFn))
    end
    return detected
end

-- 返回 Nampower 主/次/补丁版本号；未安装返回 nil
function Nampower:GetVersion()
    if hasVersionFn then
        return GetNampowerVersion()
    end
    return nil
end

--===========================================================================
-- 背包扫描加速
--===========================================================================

-- 获取某一格物品的信息（Nampower 版本）。
-- 返回：itemId, stackCount, spellCharges
--   * itemId        - 物品 ID（可直接用于分类/缓存，免正则提取）
--   * stackCount    - 堆叠数量
--   * spellCharges  - 剩余使用次数（如巫师油/法力油），0 或 nil 表示无次数
-- 未安装 Nampower 或格内无物品时返回 nil。
function Nampower:GetBagItemInfo(bagID, slot)
    if not self:IsAvailable() then return nil end
    local item = GetBagItem(bagID, slot)
    if not item then return nil end
    return item.itemId, item.stackCount, item.spellChargesRemaining
end

-- 一次性拉取整包物品（bagIndex 省略时拉全部包）。
-- 返回：{ [slot] = itemInfo, ... } 或 nil（未安装/包不可访问）。
-- itemInfo 含 itemId / stackCount / spellChargesRemaining 等。
-- 注意 Nampower 复用表引用，调用方应立即提取所需值。
function Nampower:GetBagItems(bagIndex)
    if not hasBagItemsFn then return nil end
    local ok, items = pcall(GetBagItems, bagIndex)
    if ok then return items end
    return nil
end

-- 快速读取物品等级（用于排序/分类等）；未安装或读取失败返回 nil
function Nampower:GetItemLevel(itemId)
    if not hasItemLevelFn or not itemId then return nil end
    local ok, ilvl = pcall(GetItemLevel, itemId)
    if ok and ilvl then return ilvl end
    return nil
end

-- 快速读取物品某个 DBC 字段；未安装或失败返回 nil
function Nampower:GetItemStat(itemId, field)
    if not itemId or not field then return nil end
    if hasItemStatsFieldFn then
        local ok, val = pcall(GetItemStatsField, itemId, field)
        if ok and val ~= nil then return val end
    end
    if hasItemStatsFn then
        local ok2, stats = pcall(GetItemStats, itemId)
        if ok2 and stats and stats[field] ~= nil then
            return stats[field]
        end
    end
    return nil
end

-- 物品是否可堆叠（stackable 字段）。返回 true/false/nil（nil = 未知或未安装）。
-- 用于加速堆叠判断（省 GetItemInfo 的 stackCount 查询）。
function Nampower:IsStackable(itemId)
    local stackable = self:GetItemStat(itemId, "stackable")
    if stackable == nil then return nil end
    return stackable > 1
end

-- 在背包中查找指定物品（itemId 或名称）。
-- 返回 bag, slot（与 FindPlayerItemSlot 一致）；未安装/未找到返回 nil,nil。
-- bag 为 nil 时 slot 表示装备槽（0-18）。
function Nampower:FindItemSlot(itemIdOrName)
    if not hasFindSlotFn then return nil, nil end
    local ok, bag, slot = pcall(FindPlayerItemSlot, itemIdOrName)
    if ok then return bag, slot end
    return nil, nil
end

--===========================================================================
-- 兼容辅助：把 Nampower 结果合并进 guda 的 itemData
-- 在已有 itemData 表上填充 Nampower 能提供的字段（itemID/charges 等），
-- 不覆盖已有值。返回 true 表示成功填充，false 表示无 Nampower。
--===========================================================================
function Nampower:EnrichItemData(itemData, bagID, slot)
    if not self:IsAvailable() or not itemData then return false end
    local itemId, stackCount, charges = self:GetBagItemInfo(bagID, slot)
    if not itemId then return false end

    if itemData.itemID == nil then
        itemData.itemID = itemId
    end
    if itemData.stackCount == nil and stackCount then
        itemData.stackCount = stackCount
    end
    -- charges：Nampower 直接给出剩余次数，免 tooltip 扫描。
    -- 注意：Nampower 对无次数物品返回 1（"无充能"哨兵值），并非真正的
    -- 剩余次数，因此只在 >1 时才视为有效次数，避免无次数物品显示 x1。
    if itemData.spellChargesRemaining == nil and charges and charges > 1 then
        itemData.spellChargesRemaining = charges
    end
    return true
end

addon:Debug("Nampower module loaded (available=%s)", tostring(Nampower:IsAvailable()))
