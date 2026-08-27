-- Guda 装备套装模块
-- 检测并追踪来自 Outfitter 和 ItemRack 插件的装备套装
-- 提供用于检查物品是否属于装备套装的 API

local addon = Guda

local EquipmentSets = {}
addon.Modules.EquipmentSets = EquipmentSets

-- 防止扫描执行期间重复执行全量扫描，占用较多线程
local scanInProgress = false
-- 内部状态
local setData = {}       -- 装备套装数据：{ setName => { itemIDs = {[itemID] = true} } }
local itemToSets = {}    -- 物品到套装索引：{ [itemID] => { setName1 = true, setName2 = true } }
local initialized = false
local outfitterReady = false
local itemRackReady = false

-------------------------------------------
-- 公共 API
-------------------------------------------

-- 检查物品 ID 是否属于任何装备套装
function EquipmentSets:IsInSet(itemID)
    if not itemID then return false end
    return itemToSets[itemID] ~= nil
end

-- 获取包含特定物品 ID 的套装名称
-- 返回套装名称表或 nil
function EquipmentSets:GetSetNames(itemID)
    if not itemID then return nil end
    local sets = itemToSets[itemID]
    if not sets then return nil end

    local names = {}
    for name in pairs(sets) do
        table.insert(names, name)
    end
    if table.getn(names) == 0 then return nil end
    return names
end

-- 获取所有已知套装名称（已排序）
function EquipmentSets:GetAllSetNames()
    local names = {}
    for name in pairs(setData) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-------------------------------------------
-- 内部：重建物品到套装索引
-------------------------------------------

local function RebuildItemIndex()
    itemToSets = {}
    for setName, data in pairs(setData) do
        if data and type(data) == "table" and data.itemIDs then
            for itemID in pairs(data.itemIDs) do
                if not itemToSets[itemID] then
                    itemToSets[itemID] = {}
                end
                itemToSets[itemID][setName] = true
            end
        end
    end
end

-------------------------------------------
-- Outfitter 集成
-------------------------------------------

-- Outfitter 把套装归入四个内置类别（Outfitter.lua:112-117）：
-- "Complete"、"Partial" 是用户组装的装备；"Accessory" 是饰品/戒指
-- 替换按钮；"Special" 是预制便利套装。只有前两个
-- 是真正属于 Guda 背包分类的装备套装。
local kIgnoredOutfitterCategories = {
    Accessory = true,
    Special = true,
}

local function ScanOutfitter()
    -- 检查 Outfitter 是否已加载并初始化
    if not Outfitter_GetCategoryOrder then return false end

    addon:Debug("EquipmentSets: Scanning Outfitter outfits...")

    local categoryOrder = Outfitter_GetCategoryOrder()
    if not categoryOrder or type(categoryOrder) ~= "table" then return false end

    local scannedSets = 0
    for _, catID in ipairs(categoryOrder) do
        if not kIgnoredOutfitterCategories[catID] then
            local outfits = nil
            if Outfitter_GetOutfitsByCategoryID then
                outfits = Outfitter_GetOutfitsByCategoryID(catID)
            end
            if outfits and type(outfits) == "table" then
                for _, outfit in ipairs(outfits) do
                    local setName = outfit.Name
                    if setName and outfit.Items and type(outfit.Items) == "table" then
                        local itemIDs = {}
                        for slotName, item in pairs(outfit.Items) do
                            if item and type(item) == "table" then
                                local itemID = nil
                                -- Outfitter 存储物品代码
                                if item.Code then
                                    itemID = tonumber(item.Code)
                                elseif item.ItemID then
                                    itemID = tonumber(item.ItemID)
                                end
                                if itemID and itemID > 0 then
                                    itemIDs[itemID] = true
                                end
                            end
                        end

                        setData[setName] = { itemIDs = itemIDs, source = "Outfitter" }
                        scannedSets = scannedSets + 1
                    end
                end
            end
        end
    end

    addon:Debug("EquipmentSets: Scanned %d Outfitter outfits", scannedSets)
    return scannedSets > 0
end

local function HookOutfitterEvents()
    if not Outfitter_RegisterOutfitEvent then return end

    local events = { "ADD", "DELETE", "EDIT", "RENAME" }
    for _, eventName in ipairs(events) do
        local success, err = pcall(function()
            Outfitter_RegisterOutfitEvent(eventName, function()
                -- 短暂延迟后重新扫描，让 Outfitter 完成其更新
                addon:Debug("EquipmentSets: Outfitter event '%s', rescanning...", eventName)
                FullScan()
                RebuildItemIndex()
                -- 同步分类，延后1帧执行，避免与模块初始化冲突
                C_Timer.After(0, function()
                    if addon.Modules and addon.Modules.CategoryManager then
                        addon.Modules.CategoryManager:SyncEquipmentSetCategories()
                    end
                end)
            end)
        end)
        if not success then
            addon:Debug("EquipmentSets: Failed to hook Outfitter event '%s': %s", eventName, tostring(err))
        end
    end
end

-------------------------------------------
-- ItemRack 集成
-------------------------------------------

local function ExtractItemRackID(value)
    -- 接受一个数字、裸 ID 字符串 "12345"，或物品链接片段
    -- 如 "item:12345:0:0:0"。返回数字 itemID 或 nil。
    if type(value) == "number" then
        return value > 0 and value or nil
    end
    if type(value) ~= "string" then return nil end
    local _, _, idStr = string.find(value, "item:(%d+)")
    if not idStr then
        _, _, idStr = string.find(value, "^(%d+)")
    end
    local itemID = tonumber(idStr)
    if itemID and itemID > 0 then return itemID end
    return nil
end

local function ScanItemRackStock(sets)
    -- 标准 Gello ItemRack：ItemRackUser.Sets[name].equip[slot] = "itemID:..."
    -- 内部套装以 "~" 开头。
    local scanned = 0
    if not sets or type(sets) ~= "table" then return 0 end
    for setName, setInfo in pairs(sets) do
        if type(setName) == "string" and not string.find(setName, "^~") then
            local itemIDs = {}
            if type(setInfo) == "table" and setInfo.equip and type(setInfo.equip) == "table" then
                for _, itemString in pairs(setInfo.equip) do
                    local itemID = ExtractItemRackID(itemString)
                    if itemID then itemIDs[itemID] = true end
                end
            end
            setData[setName] = { itemIDs = itemIDs, source = "ItemRack" }
            scanned = scanned + 1
        end
    end
    return scanned
end

local function ScanItemRackFork(sets)
    -- 乌龟/Khalil ItemRack 分支：Rack_User[user].Sets[name][slotNum] =
    -- { id = "item:<id>:<enchant>:<suffix>", name = "ItemName" }。内部
    -- 套装以 "Rack-" 或 "ItemRack" 为前缀。
    local scanned = 0
    if not sets or type(sets) ~= "table" then return 0 end
    for setName, setInfo in pairs(sets) do
        if type(setName) == "string"
           and not string.find(setName, "^Rack%-")
           and not string.find(setName, "^ItemRack")
           and type(setInfo) == "table" then
            local itemIDs = {}
            for k, v in pairs(setInfo) do
                if type(k) == "number" and type(v) == "table" then
                    local itemID = ExtractItemRackID(v.id)
                    if itemID then itemIDs[itemID] = true end
                end
            end
            setData[setName] = { itemIDs = itemIDs, source = "ItemRack" }
            scanned = scanned + 1
        end
    end
    return scanned
end

local function IsItemRackLoaded()
    if ItemRackUser and type(ItemRackUser) == "table" and ItemRackUser.Sets then return true end
    if Rack_User and type(Rack_User) == "table" then
        local userKey = UnitName("player") .. " of " .. GetRealmName()
        if Rack_User[userKey] and type(Rack_User[userKey]) == "table" and Rack_User[userKey].Sets then return true end
    end
    return false
end

local function ScanItemRack()
    local scannedSets = 0

    if ItemRackUser and type(ItemRackUser) == "table" and ItemRackUser.Sets then
        addon:Debug("EquipmentSets: Scanning ItemRack (stock) sets...")
        scannedSets = scannedSets + ScanItemRackStock(ItemRackUser.Sets)
    end

    if Rack_User and type(Rack_User) == "table" then
        local userKey = UnitName("player") .. " of " .. GetRealmName()
        local userData = Rack_User[userKey]
        if userData and type(userData) == "table" and userData.Sets then
            addon:Debug("EquipmentSets: Scanning ItemRack (fork) sets for " .. userKey)
            scannedSets = scannedSets + ScanItemRackFork(userData.Sets)
        end
    end

    if scannedSets == 0 then return false end
    addon:Debug("EquipmentSets: Scanned %d ItemRack sets", scannedSets)
    return true
end

-------------------------------------------
-- 共享的物品 ID 提取
-------------------------------------------

-- 从任何物品表示形式中提取数字 itemID：完整的物品链接
-- （"|Hitem:12345:...|h"）、裸 "item:12345:..." 字符串，或 "item:12345"
-- 片段。适用于所有受支持的装备套装插件。
local function ExtractItemIDFromLink(link)
    if not link or type(link) ~= "string" then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    if id then
        local n = tonumber(id)
        if n and n > 0 then return n end
    end
    return nil
end

-------------------------------------------
-- EN_AutoEquip 集成
-------------------------------------------
-- EAE_Config[charKey][setIndex] = { name = "配装1", <SlotName> = { name=..., link="item:..." }, ... }
-- charKey = UnitName("player") .. "@" .. GetRealmName()

local function ScanEnAutoEquip()
    if not EAE_Config then return false end
    local charKey = UnitName("player") .. "@" .. GetRealmName()
    local charSets = EAE_Config[charKey]
    if not charSets then return false end

    local scanned = 0
    for i, setEntry in ipairs(charSets) do
        if type(setEntry) == "table" then
            local setName = type(setEntry.name) == "string" and setEntry.name or ("EN_AutoEquip " .. i)
            local itemIDs = {}
            for slotName, slotData in pairs(setEntry) do
                if type(slotData) == "table" and slotData.link then
                    local itemID = ExtractItemIDFromLink(slotData.link)
                    if itemID then itemIDs[itemID] = true end
                end
            end
            if next(itemIDs) then
                setData[setName] = { itemIDs = itemIDs, source = "EN_AutoEquip" }
                scanned = scanned + 1
            end
        end
    end

    if scanned > 0 then
        addon:Debug("EquipmentSets: Scanned %d EN_AutoEquip sets", scanned)
        return true
    end
    return false
end

-------------------------------------------
-- GBDSwitcher 集成
------------------------------------------
-- GBDSwitcher_DB.specs[i] = { name = "天赋 1", gear = { [n] = "|Hitem:...|h", ... }, bars = {} }

local function ScanGBDswitcher()
    if not GBDSwitcher_DB or not GBDSwitcher_DB.specs then return false end

    local scanned = 0
    for _, spec in ipairs(GBDSwitcher_DB.specs) do
        if type(spec) == "table" and type(spec.name) == "string" and spec.gear then
            local setName = spec.name
            local itemIDs = {}
            for _, link in pairs(spec.gear) do
                local itemID = ExtractItemIDFromLink(link)
                if itemID then itemIDs[itemID] = true end
            end
            setData[setName] = { itemIDs = itemIDs, source = "GBDSwitcher" }
            scanned = scanned + 1
        end
    end

    if scanned > 0 then
        addon:Debug("EquipmentSets: Scanned %d GBDSwitcher sets", scanned)
        return true
    end
    return false
end

-------------------------------------------
-- 全量扫描（所有来源）
-------------------------------------------

local function FullScan()
    -- 扫描中直接返回，防止重复执行，避免占用过多线程资源
    if scanInProgress then return end
    scanInProgress = true

    -- 用 pcall 包裹全部逻辑，确保无论是否抛出异常，scanInProgress 都会被复位。
    -- 避免中途异常导致永远停在 true，从而阻塞后续扫描。
    local ok, err = pcall(function()
        setData = {}

        local hasOutfitter = ScanOutfitter()
        local hasItemRack = ScanItemRack()
        local hasEnAutoEquip = ScanEnAutoEquip()
        local hasGBDswitcher = ScanGBDswitcher()

        RebuildItemIndex()

        -- 同步装备套装分类，延后1帧执行，避免初始化冲突
        C_Timer.After(0, function()
            if addon.Modules and addon.Modules.CategoryManager then
                addon.Modules.CategoryManager:SyncEquipmentSetCategories()
            end
        end)

        if hasOutfitter or hasItemRack or hasEnAutoEquip or hasGBDswitcher then
            addon:Debug("EquipmentSets: Full scan complete, %d total sets", table.getn(EquipmentSets:GetAllSetNames()))
        end
    end)

    scanInProgress = false

    if not ok then
        addon:Debug("EquipmentSets: FullScan failed: %s", tostring(err))
    end
end

-------------------------------------------
-- 初始化
-------------------------------------------

function EquipmentSets:Initialize()
    -- 初始化前等待，确保 Events 模块安全加载后再注册事件，避免引用报错
    if not addon.Modules or not addon.Modules.Events then
        C_Timer.After(0, function()
            EquipmentSets:Initialize()
        end)
        return
    end

    if initialized then return end
    initialized = true

    -- 注册 ADDON_LOADED 以捕获延迟加载的插件
    addon.Modules.Events:Register("ADDON_LOADED", function(event, addonName)
        if addonName == "Outfitter" then
            -- Outfitter 在扫描前需要其 INIT 事件
            outfitterReady = true
            addon:Debug("EquipmentSets: Outfitter loaded, waiting for INIT...")
        elseif addonName == "ItemRack" then
            itemRackReady = true
            addon:Debug("EquipmentSets: ItemRack loaded, scanning...")
            -- 延后2秒扫描，避免与其他初始化高峰冲突
            C_Timer.After(2, function() FullScan() end)
        elseif addonName == "EN_AutoEquip" then
            addon:Debug("EquipmentSets: EN_AutoEquip loaded, scanning...")
            C_Timer.After(2, function() FullScan() end)
        elseif addonName == "GBDSwitcher" then
            addon:Debug("EquipmentSets: GBDSwitcher loaded, scanning...")
            C_Timer.After(2, function() FullScan() end)
        end
    end, "EquipmentSets")

    -- 注册 PLAYER_ENTERING_WORLD 以捕获已加载的插件
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        -- 检查 Outfitter 是否已经加载
        if Outfitter_GetCategoryOrder or gOutfitter_Initialized then
            outfitterReady = true
            HookOutfitterEvents()
        end

        -- 检查 ItemRack 是否已经加载（标准版或分支版）
        if IsItemRackLoaded() then
            itemRackReady = true
        end

        -- 延后2秒执行首次全量扫描，安全避开其他模块初始化高峰期，避免卡住主线程
        C_Timer.After(2, function()
            FullScan()
        end)
    end, "EquipmentSets")

    -- 如果可用则钩住 Outfitter 的 INIT 事件（在 Outfitter 完成设置后触发）
    -- 由于 OUTFITTER_INIT 是自定义事件，这里使用一个框架定期检查
    local initCheckFrame = CreateFrame("Frame")
    initCheckFrame.elapsed = 0
    initCheckFrame.checks = 0
    initCheckFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        -- 将间隔由1秒改为2秒，减少帧循环资源占用，并把最大检查次数由30次改为15次
        if this.elapsed < 2 then return end
        this.elapsed = 0
        this.checks = this.checks + 1

        -- 检查 Outfitter 是否可用
        if not outfitterReady and (gOutfitter_Initialized or Outfitter_GetCategoryOrder) then
            outfitterReady = true
            HookOutfitterEvents()
            -- 延后1秒执行扫描，避免与模块初始化抢占资源
            C_Timer.After(1, function() FullScan() end)
            this:Hide()
            return
        end

        -- 30 秒后停止检查
        if this.checks > 15 then
            this:Hide()
            -- 无论如何执行一次最终扫描，以防插件在没有事件的情况下加载
            if Outfitter_GetCategoryOrder or IsItemRackLoaded() then
                C_Timer.After(1, function() FullScan() end)
            end
        end
    end)
    initCheckFrame:Show()

    -- 删除原初始化阶段直接执行的全量扫描，避免与初始化时机冲突
    addon:Debug("EquipmentSets: Module initialized")
end

-- 强制重新扫描所有装备套装来源
function EquipmentSets:Rescan()
    FullScan()
end