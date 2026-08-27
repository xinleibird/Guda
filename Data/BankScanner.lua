-- Guda 银行扫描器
-- 扫描并存储银行内容，带缓存和事件待处理跟踪

local addon = Guda

local BankScanner = {}
addon.Modules.BankScanner = BankScanner

local bankOpen = false

-- 银行数据缓存，避免每次更新都重新扫描所有栏位
local bankCache = nil
local cacheValid = false

-- 事件待处理跟踪（类似 Baganator 的 IsBagEventPending）
local eventPending = false
local dirtySlots = {}  -- 跟踪变化的特定栏位

-- 清除银行缓存（银行打开或发生重大变化时调用）
function BankScanner:ClearCache()
    bankCache = nil
    cacheValid = false
    dirtySlots = {}
    eventPending = false
end

-- 检查是否有银行事件待处理（转移前使用）
function BankScanner:IsEventPending()
    return eventPending
end

-- 清除待处理标志（处理后调用）
function BankScanner:ClearEventPending()
    eventPending = false
end

-- 将特定栏位标记为脏（增量跟踪）
function BankScanner:MarkSlotDirty(bagID, slotID)
    if not dirtySlots[bagID] then
        dirtySlots[bagID] = {}
    end
    dirtySlots[bagID][slotID] = true
    eventPending = true
end

-- 获取缓存的银行数据，如果缓存无效则扫描
function BankScanner:GetBankData()
    addon:DebugCategory("GetBankData: ENTRY bankOpen=%s, cacheValid=%s, hasCache=%s",
        tostring(bankOpen), tostring(cacheValid), tostring(bankCache ~= nil))

    -- 检查银行是否可访问（正式打开或者我们可以访问银行栏位）
    local bankAccessible = bankOpen
    local forceRescan = false
    if not bankAccessible then
        -- 尝试访问主银行 - 如果它有栏位，则银行实际可访问
        local testSlots = GetContainerNumSlots(-1)
        if testSlots and testSlots > 0 then
            bankAccessible = true
            -- 当 bankOpen 为 false 但银行可访问时强制重扫
            -- 这处理缓存有过期数据的边界情况
            forceRescan = true
            addon:DebugCategory("GetBankData: bankOpen=false but bank accessible (%d slots), forcing rescan", testSlots)
        end
    end

    if not bankAccessible then
        addon:DebugCategory("GetBankData: bank NOT accessible, returning empty")
        return {}
    end

    -- 当 bankOpen 状态不一致时强制重扫
    if forceRescan then
        cacheValid = false
    end

    if cacheValid and bankCache then
        addon:DebugCategory("GetBankData: using cached data (cacheValid=true)")
        -- 增量处理任何脏栏位
        for bagID, slots in pairs(dirtySlots) do
            if bagID ~= nil and type(slots) == "table" then
                if bankCache[bagID] then
                    for slotID in pairs(slots) do
                        -- 验证 slotID 是有效数字
                        if type(slotID) == "number" and slotID >= 1 then
                            local oldData = bankCache[bagID].slots[slotID]
                            local newData = addon.Modules.BagScanner:ScanSlot(bagID, slotID)
                            bankCache[bagID].slots[slotID] = newData

                            -- 更新空闲栏位数
                            local wasEmpty = (oldData == nil)
                            local isEmpty = (newData == nil)
                            if wasEmpty and not isEmpty then
                                bankCache[bagID].freeSlots = bankCache[bagID].freeSlots - 1
                            elseif not wasEmpty and isEmpty then
                                bankCache[bagID].freeSlots = bankCache[bagID].freeSlots + 1
                            end
                        end
                    end
                else
                    -- 背包不在缓存中，扫描它
                    bankCache[bagID] = self:ScanBankBag(bagID)
                end
            end
        end
        dirtySlots = {}

        -- 检查被无效化的背包（nil 条目）并重新扫描它们
        local rescannedBags = 0
        for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
            if bankCache[bagID] == nil then
                addon:DebugCategory("GetBankData: rescanning invalidated bag %d", bagID)
                bankCache[bagID] = self:ScanBankBag(bagID)
                rescannedBags = rescannedBags + 1
            end
        end
        if rescannedBags > 0 then
            addon:DebugCategory("GetBankData: rescanned %d invalidated bags", rescannedBags)
        end

        -- 验证所有银行背包的缓存是否与实际一致
        -- 只在物品被添加时（API > 缓存）强制完整重扫
        -- 当物品被移除时（缓存 > API），增量更新 + 空占位符应能处理
        local needsFullRescan = false
        for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
            local cacheItems = 0
            local realItems = 0
            if bankCache[bagID] and bankCache[bagID].slots then
                for slotID, item in pairs(bankCache[bagID].slots) do
                    if item then cacheItems = cacheItems + 1 end
                end
            end
            -- 检查实际的 API 状态
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                local texture = GetContainerItemInfo(bagID, slot)
                if texture then realItems = realItems + 1 end
            end
            if realItems > cacheItems then
                -- 物品已添加到银行 - 需要完整重扫才能显示它们
                addon:DebugCategory("GetBankData: ITEMS ADDED in bag %d! cache=%d, API=%d -> full rescan",
                    bagID, cacheItems, realItems)
                needsFullRescan = true
            elseif cacheItems > realItems then
                -- 物品已从银行移除 - 增量更新可处理
                -- 只为该背包更新缓存以反映移除
                addon:DebugCategory("GetBankData: ITEMS REMOVED in bag %d, cache=%d, API=%d -> incremental update",
                    bagID, cacheItems, realItems)
                -- 只重扫这个背包来更新缓存（不进行完整的界面重绘）
                bankCache[bagID] = self:ScanBankBag(bagID)
            end
        end
        if needsFullRescan then
            -- 只在物品被添加时强制完整重扫
            cacheValid = false
            bankCache = self:ScanBank()
            cacheValid = true
            addon:DebugCategory("GetBankData: forced full rescan due to new items")
        end

        return bankCache
    end

    -- 缓存未命中 - 进行完整扫描
    addon:DebugCategory("GetBankData: cache miss, doing full scan (cacheValid=%s, bankCache=%s)",
        tostring(cacheValid), tostring(bankCache ~= nil))
    bankCache = self:ScanBank()
    cacheValid = true
    dirtySlots = {}
    return bankCache
end

-- 更新缓存中的单个栏位（增量更新）
function BankScanner:UpdateSlot(bagID, slotID)
    if not bankOpen then return end

    -- 标记为脏，供下次 GetBankData 调用处理
    self:MarkSlotDirty(bagID, slotID)
end

-- 使缓存失效（下次更新时强制完整重扫）
function BankScanner:InvalidateCache()
    cacheValid = false
end

-- 获取背包的缓存物品数，而不触发重扫
-- 用于事件处理期间比较前后计数
function BankScanner:GetCachedItemCount(bagID)
    if not bankCache or not bankCache[bagID] or not bankCache[bagID].slots then
        return 0
    end
    local count = 0
    for slotID, item in pairs(bankCache[bagID].slots) do
        if item then count = count + 1 end
    end
    return count
end

-- 使缓存中的特定背包失效（仅强制重扫该背包）
function BankScanner:InvalidateBag(bagID)
    -- 如果银行可访问（不只是正式打开）则允许失效
    local bankAccessible = bankOpen
    if not bankAccessible then
        local testSlots = GetContainerNumSlots(-1)
        if testSlots and testSlots > 0 then
            bankAccessible = true
        end
    end
    if not bankAccessible then
        addon:DebugCategory("InvalidateBag(%d): bank not accessible, skipping", bagID)
        return
    end
    if not bankCache then
        addon:DebugCategory("InvalidateBag(%d): no bankCache exists, skipping", bagID)
        return
    end
    local hadBag = (bankCache[bagID] ~= nil)
    bankCache[bagID] = nil
    addon:DebugCategory("InvalidateBag(%d): invalidated (hadBag=%s, cacheValid=%s)",
        bagID, tostring(hadBag), tostring(cacheValid))
end

-- 扫描所有银行背包并返回数据（完整扫描）
function BankScanner:ScanBank()
    -- 检查银行是否可访问（正式打开或栏位可读）
    local bankAccessible = bankOpen
    if not bankAccessible then
        local testSlots = GetContainerNumSlots(-1)
        if testSlots and testSlots > 0 then
            bankAccessible = true
        end
    end

    if not bankAccessible then
        addon:Debug("Cannot scan bank - not accessible")
        return {}
    end

    local bankData = {}
    local totalItems = 0

    for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
        bankData[bagID] = self:ScanBankBag(bagID)
        local bagItems = 0
        if bankData[bagID] and bankData[bagID].slots then
            for _, item in pairs(bankData[bagID].slots) do
                if item then
                    bagItems = bagItems + 1
                    totalItems = totalItems + 1
                end
            end
        end
        if bagItems > 0 then
            addon:DebugCategory("ScanBank: bag %d has %d items", bagID, bagItems)
        end
    end
    addon:DebugCategory("ScanBank: total %d items across all bags", totalItems)

    return bankData
end

-- 扫描单个银行背包
function BankScanner:ScanBankBag(bagID)
    -- 确定背包类型
    local bagType = "regular"
    if addon.Modules.Utils:IsSoulBag(bagID) then
        bagType = "soul"
    elseif addon.Modules.Utils:IsHerbBag(bagID) then
        bagType = "herb"
    elseif addon.Modules.Utils:IsEnchantBag(bagID) then
        bagType = "enchant"
    elseif addon.Modules.Utils:IsAmmoQuiverBag(bagID) then
        bagType = "ammo"
    end

    local bag = {
        slots = {},
        numSlots = addon.Modules.Utils:GetBagSlotCount(bagID),
        freeSlots = 0,
        bagType = bagType,
    }

    if not addon.Modules.Utils:IsBagValid(bagID) then
        addon:DebugCategory("ScanBankBag(%d): bag not valid", bagID)
        return bag
    end

    local itemCount = 0
    for slot = 1, bag.numSlots do
        local itemData = addon.Modules.BagScanner:ScanSlot(bagID, slot)
        bag.slots[slot] = itemData

        if not itemData then
            bag.freeSlots = bag.freeSlots + 1
        else
            itemCount = itemCount + 1
        end
    end

    addon:DebugCategory("ScanBankBag(%d): numSlots=%d, items=%d, freeSlots=%d",
        bagID, bag.numSlots, itemCount, bag.freeSlots)

    return bag
end

-- 将当前银行保存到数据库
function BankScanner:SaveToDatabase()
    if not bankOpen then
        return
    end

    local bankData = self:GetBankData()  -- 使用缓存数据
    addon.Modules.DB:SaveBank(bankData)
    addon:Debug("Bank data saved")
end

-- 初始化银行扫描器
function BankScanner:Initialize()
    -- 银行打开 - 进行初始扫描
    addon.Modules.Events:OnBankOpen(function()
        bankOpen = true
        BankScanner:ClearCache()  -- 打开时清除缓存
        addon:Debug("Bank opened")

        -- 延迟扫描以确保银行完全加载（使用池化定时器）
        GudaBag.ScheduleTimer(0.5, function()
            BankScanner:SaveToDatabase()
        end)
    end, "BankScanner")

    -- 银行关闭
    addon.Modules.Events:OnBankClose(function()
        -- 在标记银行关闭之前进行最终保存
        addon:Debug("Bank closing - performing final save")
        BankScanner:SaveToDatabase()

        bankOpen = false
        BankScanner:ClearCache()  -- 关闭时清除缓存
        addon:Debug("Bank closed")
    end, "BankScanner")
end

-- 检查银行当前是否打开
function BankScanner:IsBankOpen()
    return bankOpen
end
