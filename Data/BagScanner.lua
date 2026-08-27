-- Guda 背包扫描器
-- 扫描并存储背包内容，带缓存和事件待处理跟踪

local addon = Guda

local BagScanner = {}
addon.Modules.BagScanner = BagScanner

-- 背包数据缓存，避免每次更新都重新扫描所有栏位
local bagCache = nil
local cacheValid = false

-- 事件待处理跟踪（类似 Baganator 的 IsBagEventPending）
local eventPending = false
local dirtySlots = {}  -- 跟踪变化的特定栏位：dirtySlots[bagID][slotID] = true

--=====================================================
-- 物品数据池（受 Baganator 启发的内存优化）
-- 复用物品数据表而不是创建新表
--=====================================================
local itemDataPool = {}
local ITEM_DATA_POOL_MAX = 200  -- 限制池大小以防止无界增长

-- 从池中获取物品数据表
local function AcquireItemData()
    return table.remove(itemDataPool) or {}
end

-- 将物品数据表释放回池中
local function ReleaseItemData(data)
    if data and table.getn(itemDataPool) < ITEM_DATA_POOL_MAX then
        -- 为复用清除所有字段
        data.link = nil
        data.texture = nil
        data.count = nil
        data.quality = nil
        data.name = nil
        data.iLevel = nil
        data.type = nil
        data.class = nil
        data.subclass = nil
        data.equipSlot = nil
        data.locked = nil
        table.insert(itemDataPool, data)
    end
end

-- 释放背包缓存条目中的所有物品数据
local function ReleaseBagCacheData(bagData)
    if bagData and bagData.slots then
        for slotID, itemData in pairs(bagData.slots) do
            if itemData then
                ReleaseItemData(itemData)
            end
        end
    end
end

-- 清除背包缓存（释放池化数据）
function BagScanner:ClearCache()
    if bagCache then
        for bagID, bagData in pairs(bagCache) do
            ReleaseBagCacheData(bagData)
        end
    end
    bagCache = nil
    cacheValid = false
    dirtySlots = {}
end

-- 检查是否有背包事件待处理（转移前使用）
function BagScanner:IsEventPending()
    return eventPending
end

-- 清除待处理标志（处理后调用）
function BagScanner:ClearEventPending()
    eventPending = false
end

-- 将特定栏位标记为脏（增量跟踪）
function BagScanner:MarkSlotDirty(bagID, slotID)
    if not dirtySlots[bagID] then
        dirtySlots[bagID] = {}
    end
    dirtySlots[bagID][slotID] = true
    eventPending = true
end

-- 获取脏栏位并清除它们
function BagScanner:GetAndClearDirtySlots()
    local dirty = dirtySlots
    dirtySlots = {}
    return dirty
end

-- 获取缓存的背包数据，如果缓存无效则扫描
function BagScanner:GetBagData()
    if cacheValid and bagCache then
        -- 增量处理任何脏栏位
        for bagID, slots in pairs(dirtySlots) do
            if bagID ~= nil and type(slots) == "table" then
                if bagCache[bagID] then
                    for slotID in pairs(slots) do
                        -- 验证 slotID 是有效数字
                        if type(slotID) == "number" and slotID >= 1 then
                            local oldData = bagCache[bagID].slots[slotID]
                            local newData = self:ScanSlot(bagID, slotID)
                            bagCache[bagID].slots[slotID] = newData

                            -- 更新空闲栏位数
                            local wasEmpty = (oldData == nil)
                            local isEmpty = (newData == nil)
                            if wasEmpty and not isEmpty then
                                bagCache[bagID].freeSlots = bagCache[bagID].freeSlots - 1
                            elseif not wasEmpty and isEmpty then
                                bagCache[bagID].freeSlots = bagCache[bagID].freeSlots + 1
                            end
                        end
                    end
                else
                    -- 背包不在缓存中，扫描它
                    bagCache[bagID] = self:ScanBag(bagID)
                end
            end
        end
        dirtySlots = {}
        return bagCache
    end

    -- 缓存未命中 - 进行完整扫描
    bagCache = self:ScanBags()
    cacheValid = true
    dirtySlots = {}
    return bagCache
end

-- 使缓存失效（下次更新时强制完整重扫）
function BagScanner:InvalidateCache()
    cacheValid = false
end

-- 使缓存中的特定背包失效
function BagScanner:InvalidateBag(bagID)
    if not bagCache then return end
    bagCache[bagID] = nil
end

-- 扫描所有背包并返回数据（完整扫描）
function BagScanner:ScanBags()
    local bagData = {}

    -- 扫描普通背包
    for _, bagID in ipairs(addon.Constants.BAGS) do
        bagData[bagID] = self:ScanBag(bagID)
    end

    -- 也扫描钥匙链（bagID -2）
    bagData[-2] = self:ScanBag(-2)

    return bagData
end

-- 扫描单个背包
function BagScanner:ScanBag(bagID)
    -- 确定背包类型
    local bagType = addon.Modules.Utils:GetSpecializedBagType(bagID) or "regular"

    local bag = {
        slots = {},
        numSlots = addon.Modules.Utils:GetBagSlotCount(bagID),
        freeSlots = 0,
        bagType = bagType,
    }

    if not addon.Modules.Utils:IsBagValid(bagID) then
        return bag
    end

    for slot = 1, bag.numSlots do
        local itemData = self:ScanSlot(bagID, slot)
        bag.slots[slot] = itemData

        if not itemData then
            bag.freeSlots = bag.freeSlots + 1
        end
    end

    return bag
end

-- 扫描单个栏位（使用物品数据池）
function BagScanner:ScanSlot(bagID, slot)
    -- 验证参数以防止 API 错误
    if bagID == nil or slot == nil or slot < 1 then
        return nil
    end

    local texture, itemCount, locked, quality, readable, lootable = GetContainerItemInfo(bagID, slot)

    if not texture then
        return nil
    end

    -- 在 1.12.1 中，必须单独使用 GetContainerItemLink！
    local itemLink = GetContainerItemLink(bagID, slot)

    -- 获取物品信息
    local name, link, itemQuality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice
    if itemLink then
        name, link, itemQuality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice = addon.Modules.Utils:GetItemInfo(itemLink)
    end

    -- 使用池化的物品数据表而不是创建新表
    local itemData = AcquireItemData()
    itemData.link = itemLink
    itemData.texture = texture
    itemData.count = itemCount or 1
    itemData.quality = quality or itemQuality or 0
    itemData.name = name
    itemData.iLevel = iLevel
    itemData.type = itemType
    itemData.class = itemCategory
    -- 覆盖被错误分类为任务物品的物品（例如 Juju 消耗品）为消耗品
    if itemCategory == "Quest" and itemLink and addon.Constants and addon.Constants.QUEST_CATEGORY_EXCLUSIONS then
        local itemID = addon.Modules.Utils:ExtractItemID(itemLink)
        if itemID and addon.Constants.QUEST_CATEGORY_EXCLUSIONS[itemID] then
            itemData.class = "Consumable"
            itemData.type = "Consumable"
        end
    end
    itemData.subclass = itemSubType
    itemData.equipSlot = itemEquipLoc
    itemData.locked = locked

    -- 若安装了 Nampower，用其快速 API 补充 itemID 与剩余次数
    -- （免正则提取 itemID，免 tooltip 扫描 charges）。
    if addon.Modules.Nampower then
        addon.Modules.Nampower:EnrichItemData(itemData, bagID, slot)
    end

    return itemData
end

-- 将当前背包保存到数据库
function BagScanner:SaveToDatabase()
    local bagData = self:ScanBags()
    addon.Modules.DB:SaveBags(bagData)
    addon:Debug("Bag data saved to database")

    -- 清除提示框缓存，使计数立即更新
    if addon.Modules.Tooltip and addon.Modules.Tooltip.ClearCache then
        addon.Modules.Tooltip:ClearCache()
    end
end

-- 使用事件待处理跟踪进行初始化
function BagScanner:Initialize()
    local eventFrame = CreateFrame("Frame")
    self.eventFrame = eventFrame

    -- 为待处理跟踪注册背包更新事件
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:SetScript("OnEvent", function()
        eventPending = true
        -- 标记特定背包有变化
        if arg1 then
            if not dirtySlots[arg1] then
                dirtySlots[arg1] = {}
            end
            -- 我们不知道是哪个栏位，所以将整个背包标记为需要重扫
            -- 通过使其失效
            if bagCache and bagCache[arg1] then
                bagCache[arg1] = nil
            end
        end
    end)

    addon:Debug("Bag scanner initialized with event pending tracking")
end
