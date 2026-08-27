-- FrameHelpers: 用于框架标题和背包父框架的集中工具函数
local addon = Guda

local FrameHelpers = {}
addon.Modules.FrameHelpers = FrameHelpers

-- 背包与银行框架共用的标准分类列表
-- 现在如果 CategoryManager 可用则由其动态构建
GudaBag.CategoryList = {
    "Recently Looted", "BoP", "BoE", "Weapon", "Armor", "Consumable", "Food", "Drink", "Trade Goods", "Reagent", "Recipe", "Quiver", "Container", "Soul Bag", "Miscellaneous", "Quest", "Junk", "Class Items", "Keyring"
}

-- 从 CategoryManager 重建分类列表
function GudaBag.RefreshCategoryList()
    if addon.Modules.CategoryManager then
        GudaBag.CategoryList = addon.Modules.CategoryManager:BuildCategoryList()
    end
end

-- 将单个物品归类到 categories 与 specialItems 表中
-- 无返回值，直接修改表内容
function GudaBag.CategorizeItem(itemData, bagID, slotID, categories, specialItems, isOtherChar)
    local itemName = itemData.name or ""
    local cat = "Miscellaneous"

    -- 最近拾取（时间敏感，按物品链接判断，优先于一切分类）：
    -- 乌龟服团队副本拾取的 BoP 装备有 10 分钟可交易宽限期，此分类帮助
    -- 快速定位刚拾取/交易到的装备。不经过按链接的缓存，保证实时。
    if not isOtherChar
       and categories["Recently Looted"]
       and addon.Modules.RecentLoot and addon.Modules.RecentLoot.IsRecentlyLooted
       and addon.Modules.CategoryManager
       and addon.Modules.CategoryManager:GetCategory("Recently Looted")
       and addon.Modules.CategoryManager:GetCategory("Recently Looted").enabled ~= false
       and addon.Modules.RecentLoot:IsRecentlyLooted(itemData.link, nil) then
        table.insert(categories["Recently Looted"], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 仅为当前角色检测消耗品恢复/进食/饮水标记。
    -- 以 class == "Consumable" 作为门槛：只有消耗品才会出现
    -- "while eating"/"while drinking"/"use: restores" 这类模式，
    -- 因此扫描其他物品只会让冷缓存路径下每个背包白白多一次 tooltip 往返。
    if not isOtherChar and itemData.class == "Consumable"
       and addon.Modules.Utils and addon.Modules.Utils.GetConsumableRestoreTag then
        local tag = addon.Modules.Utils:GetConsumableRestoreTag(bagID, slotID)
        if tag then
            itemData.restoreTag = tag
        end
    end

    -- 特殊物品：现在只有坐骑被单独处理
    -- 家/工具是真实分类，由 CategoryManager 的规则处理
    if addon.Modules.SortEngine and addon.Modules.SortEngine.IsMount and addon.Modules.SortEngine.IsMount(itemData.texture) then
        table.insert(specialItems.Mount, {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- CategoryManager 可用时使用其规则引擎，否则回退到旧逻辑。
    -- 快速路径：仅查缓存。CacheWarmer 会在后台填充 categoryCache；
    -- 冷缓存未命中时跳过规则评估（否则会触发逐物品的 tooltip 扫描），
    -- 用 itemData.class 作为粗略分类。
    -- CacheWarmer 的完成标记会重新触发 BagFrame:Update，
    -- 使物品在预热完成后落入真实分类。
    if addon.Modules.CategoryManager then
        if addon.Modules.CategoryManager.CategorizeItemCached then
            cat = addon.Modules.CategoryManager:CategorizeItemCached(itemData, isOtherChar)
        end
        if not cat then
            cat = itemData.class or "Miscellaneous"
        end
        if not categories[cat] then cat = "Miscellaneous" end
        table.insert(categories[cat], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 旧版分类逻辑（CategoryManager 不可用时的回退）
    -- 优先级 2：职业物品（灵魂碎片、箭矢、子弹）
    if addon.Modules.Utils:IsSoulShard(itemData.link) or
       itemData.class == "Projectile" or
       itemData.subclass == "Arrow" or
       itemData.subclass == "Bullet" then
        table.insert(categories["Class Items"], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 优先级 3：任务物品（使用整合检测）
    local isQuestItem, _ = addon.Modules.Utils:IsQuestItem(bagID, slotID, itemData, isOtherChar, false)
    if isQuestItem then
        table.insert(categories["Quest"], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 优先级 4：垃圾（灰色物品）
    if itemData.quality == 0 or addon.Modules.Utils:IsItemGrayTooltip(bagID, slotID, itemData.link) then
        table.insert(categories["Junk"], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 优先级 5：食物与饮料
    if itemData.class == "Consumable" then
        cat = "Consumable"
        local sub = itemData.subclass or ""
        if sub == "Food & Drink" or string.find(sub, "Food") or string.find(sub, "Drink") then
            if string.find(sub, "Drink") then
                cat = "Drink"
            else
                cat = "Food"
            end
        end
        table.insert(categories[cat], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 优先级 6：装备后绑定（BoE）/ 拾取后绑定（BoP）装备
    if (itemData.class == "Weapon" or itemData.class == "Armor") and not isOtherChar then
        local isBoP = addon.Modules.Utils:IsBindOnPickup(bagID, slotID, itemData.link)
        if isBoP and categories["BoP"] then
            table.insert(categories["BoP"], {bagID = bagID, slotID = slotID, itemData = itemData})
            return
        end
        local isBoE = addon.Modules.Utils:IsBindOnEquip(bagID, slotID, itemData.link)
        if isBoE then
            table.insert(categories["BoE"], {bagID = bagID, slotID = slotID, itemData = itemData})
        else
            table.insert(categories[itemData.class], {bagID = bagID, slotID = slotID, itemData = itemData})
        end
        return
    end

    -- 优先级 7：其他角色的装备
    if (itemData.class == "Weapon" or itemData.class == "Armor") and isOtherChar then
        table.insert(categories[itemData.class], {bagID = bagID, slotID = slotID, itemData = itemData})
        return
    end

    -- 优先级 8：其他分类
    cat = itemData.class or "Miscellaneous"
    if not categories[cat] then cat = "Miscellaneous" end
    table.insert(categories[cat], {bagID = bagID, slotID = slotID, itemData = itemData})
end

--=====================================================
-- 分类表池化（内存优化）
-- 复用分类表，而不是创建新表
--=====================================================
local categoriesCache = nil
local specialItemsCache = nil

-- 清空表而不创建新表（兼容 Lua 5.0）
-- 对于数组，从后往前迭代以安全移除所有元素
local function WipeTable(t)
    if not t then return end
    -- 对于数组（数字键），从后往前移除
    local n = table.getn(t)
    if n > 0 then
        for i = n, 1, -1 do
            table.remove(t, i)
        end
    end
    -- 同时清除所有非数字键（哈希部分）
    for k in pairs(t) do
        if type(k) ~= "number" then
            t[k] = nil
        end
    end
end

-- 初始化空的分类表（复用缓存的表）
function GudaBag.InitCategories()
    -- 从 CategoryManager 刷新分类列表（仅显示已启用的分类）
    GudaBag.RefreshCategoryList()

    -- 复用或创建分类表
    if not categoriesCache then
        categoriesCache = {}
    end

    -- 清空已有分类数组（不重建主表）
    local totalItemsBeforeWipe = 0
    for cat, items in pairs(categoriesCache) do
        totalItemsBeforeWipe = totalItemsBeforeWipe + table.getn(items)
        WipeTable(items)
    end

    -- 验证清空是否成功
    local totalItemsAfterWipe = 0
    for cat, items in pairs(categoriesCache) do
        totalItemsAfterWipe = totalItemsAfterWipe + table.getn(items)
    end
    addon:DebugCategory("InitCategories: beforeWipe=%d, afterWipe=%d", totalItemsBeforeWipe, totalItemsAfterWipe)

    if addon.Modules.CategoryManager then
        -- 获取完整分类顺序（所有分类，而不仅是已启用的）
        local allCategories = addon.Modules.CategoryManager:GetCategoryOrder()
        for _, cat in ipairs(allCategories) do
            if not categoriesCache[cat] then
                categoriesCache[cat] = {}
            end
        end
    else
        -- 回退：使用显示列表
        for _, cat in ipairs(GudaBag.CategoryList) do
            if not categoriesCache[cat] then
                categoriesCache[cat] = {}
            end
        end
    end

    -- 始终确保 Miscellaneous 存在作为回退
    if not categoriesCache["Miscellaneous"] then
        categoriesCache["Miscellaneous"] = {}
    end

    -- 始终确保 Keyring 存在（在 BagFrame 中特殊处理）
    if not categoriesCache["Keyring"] then
        categoriesCache["Keyring"] = {}
    end

    -- 始终确保 Soul Bag 存在（在 BagFrame 中特殊处理）
    if not categoriesCache["Soul Bag"] then
        categoriesCache["Soul Bag"] = {}
    end

    -- 复用或创建 specialItems 表
    -- 现在只有坐骑是特殊物品；家/工具已成为真实分类
    if not specialItemsCache then
        specialItemsCache = {
            Mount = {},
        }
    else
        WipeTable(specialItemsCache.Mount)
    end

    return categoriesCache, specialItemsCache
end

-- 对分类（或合并分组）内的物品排序
-- 物品可能带有由合并分组显示设置的 categoryOrderIndex 字段
function GudaBag.SortCategoryItems(items)
    if not items then return end
    table.sort(items, function(a, b)
        -- 防止 nil 条目
        if not a then return false end
        if not b then return true end
        if not a.itemData then return false end
        if not b.itemData then return true end

        -- 投放目标（分类空位）始终排在最前面（左侧）
        local da = a.itemData.isDropTarget and true or false
        local db = b.itemData.isDropTarget and true or false
        if da ~= db then
            return da
        end
        if da and db then
            -- 两个投放目标：按名称稳定排序
            return (a.itemData.name or "") < (b.itemData.name or "")
        end

        -- 主排序：分类顺序索引（用于合并分组）
        local oa = a.categoryOrderIndex or 0
        local ob = b.categoryOrderIndex or 0
        if oa ~= ob then
            return oa < ob
        end

        -- 对贸易物品排序：肉（名称以 'meat' 结尾）= 2，蛋（包含 'egg'）= 1，其他 = 0
        local function tgRank(d)
            if not d or not d.name then return 0 end
            local t = d.type or d.class or ""
            if t ~= "Trade Goods" then return 0 end
            local n = string.lower(d.name)
            if string.find(n, "meat$") then return 2 end
            if string.find(n, "egg") then return 1 end
            return 0
        end
        local ra = tgRank(a.itemData)
        local rb = tgRank(b.itemData)
        if ra ~= rb then
            return ra > rb
        end
        -- 优先级：消耗品恢复标记（eat > drink > restore > nil）
        local pa = a.itemData.restoreTag
        local pb = b.itemData.restoreTag
        local function pr(t)
            if t == "eat" then return 3 end
            if t == "drink" then return 2 end
            if t == "restore" then return 1 end
            return 0
        end
        if pr(pa) ~= pr(pb) then
            return pr(pa) > pr(pb)
        end
        -- 回退：子类别、品质、名称
        if a.itemData.subclass ~= b.itemData.subclass then
            return (a.itemData.subclass or "") < (b.itemData.subclass or "")
        end
        if (a.itemData.quality or 0) ~= (b.itemData.quality or 0) then
            return (a.itemData.quality or 0) > (b.itemData.quality or 0)
        end
        return (a.itemData.name or "") < (b.itemData.name or "")
    end)
end

-- 在 ToggleDropDownMenu 后增大暴雪 UIDropDownMenu 按钮的字体大小
function GudaBag.ScaleDropdownFonts(size)
    for level = 1, 3 do
        local listName = "DropDownList" .. level
        local list = getglobal(listName)
        if not list then break end
        for i = 1, 20 do
            local ntxt = getglobal(listName .. "Button" .. i .. "NormalText")
            if ntxt then
                local f, _, fl = ntxt:GetFont()
                if f then ntxt:SetFont(f, size, fl) end
            end
        end
    end
end

-- 为给定的框架前缀与容器创建或返回一个分区标题
function GudaBag.GetSectionHeader(framePrefix, containerName, index)
    local name = framePrefix .. "_SectionHeader" .. index
    local header = getglobal(name)
    if not header then
        local container = getglobal(containerName)
        header = CreateFrame("Frame", name, container)
        header:SetHeight(20)
        header:EnableMouse(true)

        -- 分类名称文本
        local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", header, "LEFT", 0, 0)
        header.text = text

        -- 物品数量文本
        local countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("LEFT", text, "RIGHT", 4, 0)
        countText:SetTextColor(0.6, 0.6, 0.6)
        header.countText = countText

        -- 从数量/文本延伸到右边缘的分隔线
        local line = header:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", countText, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        line:SetTexture(0.6, 0.6, 0.6, 0.3)
        header.separatorLine = line

        header:SetScript("OnEnter", function()
            if this.fullName and this.isShortened then
                GameTooltip:SetOwner(this, "ANCHOR_TOP")
                GameTooltip:SetText(this.fullName)
                GameTooltip:Show()
            end
        end)
        header:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    header.inUse = true
    return header
end

-- 为给定的框架前缀与背包父框架表创建或返回一个背包父框架
function GudaBag.GetBagParent(framePrefix, parentsTable, bagID, containerName)
    local container = getglobal(containerName)
    if not parentsTable[bagID] then
        local name = framePrefix .. "_BagParent" .. bagID
        parentsTable[bagID] = CreateFrame("Frame", name, container)
        parentsTable[bagID]:SetAllPoints(container)
        if parentsTable[bagID].SetID then
            parentsTable[bagID]:SetID(bagID)
        end
        -- 跟踪物品按钮，避免 GetChildren() 的建表开销
        parentsTable[bagID].itemButtons = {}
    end
    return parentsTable[bagID]
end

-- 将一个物品按钮注册到其父框架以供跟踪
function GudaBag.RegisterItemButton(parent, button)
    if parent and parent.itemButtons and button then
        parent.itemButtons[button] = true
    end
end

-- 更新一组父框架的锁定/去饱和状态
-- 使用 itemButtons 跟踪以避免 GetChildren() 的建表开销
function GudaBag.UpdateLockStates(parentsTable)
    if not parentsTable then return end
    for _, parent in pairs(parentsTable) do
        if parent and parent.itemButtons then
            for button in pairs(parent.itemButtons) do
                if button.hasItem ~= nil and button:IsShown() and button.bagID and button.slotID then
                    -- GetContainerItemInfo 返回：texture, itemCount, locked, quality, readable
                    -- 第三个返回值是锁定状态（布尔值或 nil）
                    local _, _, locked = GetContainerItemInfo(button.bagID, button.slotID)
                    if not button.otherChar and not button.isReadOnly and SetItemButtonDesaturated then
                        -- locked 可以是 true/1（已锁定）或 nil/false（未锁定）
                        SetItemButtonDesaturated(button, locked, 0.5, 0.5, 0.5)
                    end
                end
            end
        end
    end
end

-- 隐藏一组父框架下的所有物品按钮，降低每帧渲染成本。
-- 背包/银行框架包含数百个按钮，每个按钮又有多个贴图/字体，
-- 在拖拽移动或整理排序等重操作期间逐帧重绘全部子区域会拖垮帧率。
-- 隐藏按钮后仅剩框架外壳（标题/底栏/搜索栏）随动，帧率恢复正常；
-- 操作结束后由 Update() 重建恢复按钮。
function GudaBag.HideItemButtons(parentsTable)
    if not parentsTable then return end
    for _, parent in pairs(parentsTable) do
        if parent and parent.itemButtons then
            for button in pairs(parent.itemButtons) do
                if button and button.hasItem ~= nil and button:IsShown() then
                    button:Hide()
                end
            end
        end
    end
end

-- 拖拽期间隐藏物品按钮（旧名，保留兼容）
function GudaBag.HideItemButtonsForDrag(parentsTable)
    GudaBag.HideItemButtons(parentsTable)
end

-- 显示一组父框架下的所有物品按钮（仅显示之前被 HideItemButtons 隐藏的，
-- 即当前 hasItem 且已隐藏的按钮；按钮位置由 Update() 重建时重新摆放）。
function GudaBag.ShowItemButtons(parentsTable)
    if not parentsTable then return end
    for _, parent in pairs(parentsTable) do
        if parent and parent.itemButtons then
            for button in pairs(parent.itemButtons) do
                if button and button.hasItem ~= nil and not button:IsShown() then
                    button:Show()
                end
            end
        end
    end
end

-- 把光标上的物品放入背包（0-4）中的第一个真实空槽。
-- 使用 PickupContainerItem 直接放置（对装备物品/银行取出物品都可靠），
-- 而不是 PutItemInBackpack（在 1.12 中可能不移动光标上的某些物品）。
-- 返回 true 表示成功放下，false 表示未放下（例如背包已满或被锁定）。
function GudaBag.PutCursorItemInFirstFreeSlot()
    if not (CursorHasItem and CursorHasItem()) then return false end
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local texture = GetContainerItemInfo(bagID, slot)
                if not texture then
                    -- 空槽：放入光标物品（交换操作，光标物品进入该槽）
                    PickupContainerItem(bagID, slot)
                    return not (CursorHasItem and CursorHasItem())
                end
            end
        end
    end
    return false
end

-- 把光标上的物品放入银行（-1 主银行 + 5-10 银行包）中的第一个真实空槽。
-- 返回 true 表示成功放下，false 表示未放下。
function GudaBag.PutCursorItemInFirstBankFreeSlot()
    if not (CursorHasItem and CursorHasItem()) then return false end
    for _, bagID in ipairs({-1, 5, 6, 7, 8, 9, 10}) do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local texture = GetContainerItemInfo(bagID, slot)
                if not texture then
                    PickupContainerItem(bagID, slot)
                    return not (CursorHasItem and CursorHasItem())
                end
            end
        end
    end
    return false
end

-- BagFrame 和 BankFrame 共用的搜索过滤器
-- 支持空格分隔的关键词，每个关键词属于以下三种之一：
--   ~t:<keyword>   — tooltip 文本子串（不区分大小写）
--   ~<category>    — 分类快捷方式（equipment、consumable、quest 等）
--   <plain text>   — 物品名称子串
-- 所有关键词都必须匹配（AND 关系），物品才算通过。
local function TokenizeSearch(text)
    local tokens = {}
    local s = string.lower(text)
    local pos = 1
    local len = string.len(s)
    while pos <= len do
        local startPos, endPos = string.find(s, "%S+", pos)
        if not startPos then break end
        table.insert(tokens, string.sub(s, startPos, endPos))
        pos = endPos + 1
    end
    return tokens
end

local function MatchesCategoryShortcut(itemData, category)
    local itemType = itemData.class or ""
    local itemQuality = itemData.quality or -1
    if category == "equipment" or category == "armor" or category == "weapon" then
        return (itemType == "Armor" or itemType == "Weapon")
    elseif category == "consumable" then
        return itemType == "Consumable"
    elseif category == "tradegoods" or category == "trades" then
        return itemType == "Trade Goods"
    elseif category == "quest" then
        local isQuest, isQuestStarter = false, false
        if addon.Modules and addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
            isQuest, isQuestStarter = addon.Modules.Utils:IsQuestItem(itemData.bagID, itemData.slotID, itemData, false, itemData.isBank)
        end
        return (isQuest or isQuestStarter or itemType == "Quest") and true or false
    elseif category == "reagent" then
        return itemType == "Reagent"
    elseif category == "common"    then return itemQuality == 1
    elseif category == "uncommon"  then return itemQuality == 2
    elseif category == "rare"      then return itemQuality == 3
    elseif category == "epic"      then return itemQuality == 4
    elseif category == "legendary" then return itemQuality == 5
    end
    return nil  -- 未知快捷方式 — 调用方回退到名称匹配
end

function GudaBag.PassesSearchFilter(itemData, searchText)
    if not searchText or searchText == "" then return true end
    if searchText == "Search, try ~equipment" or searchText == "Search bank..." then
        return true
    end
    if not itemData then return false end

    local itemName = itemData.name
    if not itemName and itemData.link then
        local _, _, name = string.find(itemData.link, "%[(.+)%]")
        itemName = name
    end
    if not itemName then return false end
    local lowerName = string.lower(itemName)

    local Utils = Guda and Guda.Modules and Guda.Modules.Utils

    for _, tok in ipairs(TokenizeSearch(searchText)) do
        local matched = false

        if string.sub(tok, 1, 3) == "~t:" then
            -- Tooltip 文本过滤器。
            local keyword = string.sub(tok, 4)
            if keyword == "" then
                matched = true   -- 单独的 ~t: 是空操作，跳过此关键词
            elseif Utils and Utils.GetTooltipText then
                local text = Utils:GetTooltipText(itemData.bagID, itemData.slotID, itemData.link)
                if text and string.find(text, keyword, 1, true) then
                    matched = true
                end
            end
        elseif string.sub(tok, 1, 1) == "~" then
            -- 分类快捷方式。未知快捷方式回退到名称匹配。
            local category = string.sub(tok, 2)
            local shortcut = MatchesCategoryShortcut(itemData, category)
            if shortcut == true then
                matched = true
            elseif shortcut == nil then
                -- 未知快捷方式 — 当作普通名称子串处理
                matched = string.find(lowerName, tok, 1, true) ~= nil
            end
        else
            matched = string.find(lowerName, tok, 1, true) ~= nil
        end

        if not matched then return false end
    end

    return true
end

-- Bag/Bank 框架的通用 ResizeFrame
function GudaBag.ResizeFrame(frameName, containerName, currentRow, currentCol, columns, overrideHeight)
    local buttonSize = addon.Modules.DB:GetSetting("iconSize") or addon.Constants.BUTTON_SIZE
    local spacing = addon.Modules.DB:GetSetting("iconSpacing") or addon.Constants.BUTTON_SPACING

    -- currentRow/currentCol 反映最后一个物品之后的位置：
    -- 若 col==0，row 已递增（满行），因此 totalRows = row
    -- 若 col>0，是部分行，因此 totalRows = row + 1
    local totalRows = (currentRow or 0)
    if (currentCol or 0) > 0 then
        totalRows = totalRows + 1
    end
    if totalRows < 1 then totalRows = 1 end

    -- 获取感知主题的内边距
    local pad = { containerExtra = 20, frameExtra = 20, titleHeight = 40, qualityBarHeight = 27, searchBarHeight = 30, footerHeight = 45, footerHiddenHeight = 10 }
    if addon.Modules and addon.Modules.Theme and addon.Modules.Theme.GetFramePadding then
        pad = addon.Modules.Theme:GetFramePadding()
    end

    local containerWidth = columns * (buttonSize + spacing) - spacing + 2 * pad.startX
    local containerHeight = overrideHeight or (totalRows * (buttonSize + spacing) - spacing + 2 * math.abs(pad.startY))
    local frameWidth = containerWidth + pad.frameExtra

    -- 搜索栏的有效显示状态："shown" 始终显示，"hidden"/"toggle"
    -- 默认隐藏，但可通过标题栏的图标按钮展开。
    local mode = addon.Modules.DB:GetSetting("searchBarMode")
    if mode ~= "shown" and mode ~= "hidden" and mode ~= "toggle" then
        local legacy = addon.Modules.DB:GetSetting("showSearchBar")
        mode = (legacy == false) and "hidden" or "shown"
    end
    local showSearchBar
    if mode == "shown" then
        showSearchBar = true
    else  -- "hidden" 或 "toggle"：均可通过图标按钮展开
        local BF = addon.Modules and addon.Modules.BagFrame
        showSearchBar = BF and BF.searchBarExpanded and true or false
    end

    local titleHeight = pad.titleHeight
    -- 品质过滤栏高度：仅当框架实际拥有该栏时才计入（银行框架没有）
    local qualityBarHeight = 0
    if getglobal(frameName .. "_QualityBar") then
        qualityBarHeight = pad.qualityBarHeight or 27
    end
    local searchBarHeight = pad.searchBarHeight
    local footerHeight = pad.footerHeight
    local frameHeight

    local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
    if hideFooter then
        footerHeight = pad.footerHiddenHeight
        frameHeight = containerHeight + titleHeight + qualityBarHeight + (showSearchBar and searchBarHeight or 0) + footerHeight
    elseif showSearchBar then
        frameHeight = containerHeight + titleHeight + qualityBarHeight + searchBarHeight + footerHeight
    else
        frameHeight = containerHeight + titleHeight + qualityBarHeight + footerHeight
    end

    if containerWidth < 200 then
        containerWidth = 200
        frameWidth = 220
    end
    if containerHeight < 150 then containerHeight = 150 end
    if frameHeight < 250 then frameHeight = 250 end

    if containerWidth > 1250 then containerWidth = 1250; frameWidth = 1270 end
    if containerHeight > 1000 then containerHeight = 1000 end
    if frameHeight > 1200 then frameHeight = 1200 end

    local frame = getglobal(frameName)
    local itemContainer = getglobal(containerName)

    if frame then
        frame:SetWidth(frameWidth)
        frame:SetHeight(frameHeight)
        frame:ClearAllPoints()
        -- 如果存在则尝试保留保存的位置（仅为 Bag 框架保存）
        if addon and addon.Modules and addon.Modules.DB then
            local settingName = (frameName == "Guda_BagFrame") and "bagFramePosition" or nil
            if settingName then
                local pos = addon.Modules.DB:GetSetting(settingName)
                if pos and pos.point == "BOTTOMRIGHT" and pos.x and pos.y then
                    frame:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", pos.x, pos.y)
                else
                    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100)
                end
            else
                frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100)
            end
        else
            frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100)
        end
    end

    if itemContainer then
        itemContainer:SetWidth(containerWidth)
        itemContainer:SetHeight(containerHeight)
    end

    -- 调整搜索栏与工具栏宽度以匹配容器宽度
    local searchBar = getglobal(frameName .. "_SearchBar")
    if searchBar then searchBar:SetWidth(containerWidth) end
    local qualityBar = getglobal(frameName .. "_QualityBar")
    if qualityBar then qualityBar:SetWidth(containerWidth) end
    local toolbar = getglobal(frameName .. "_Toolbar")
    if toolbar then toolbar:SetWidth(containerWidth) end
end
