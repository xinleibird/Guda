-- Guda 任务物品条
-- 在独立物品条中显示可用的任务物品

local addon = Guda
local QuestItemBar = addon.Modules.QuestItemBar
if not QuestItemBar then
    -- 若 Init.lua 有改动则回退
    QuestItemBar = {}
    addon.Modules.QuestItemBar = QuestItemBar
end

local buttons = {}
local questItems = {}
local flyoutButtons = {}
local flyoutFrame

--=====================================================
-- 任务物品条按钮图标边框（跟随主题风格）
-- 圆角（GUDA/暴雪默认）：保持图标原始外观（保留贴图自带边框）
-- 方形（pfUI）：裁掉图标自带边框，改为黑色 1 像素边框
--=====================================================

local function GetOrCreateIconBorder(button)
    if button._iconBorder then
        return button._iconBorder
    end
    local frame = CreateFrame("Frame", nil, button)
    frame:SetFrameLevel(button:GetFrameLevel() + 2)
    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropBorderColor(0, 0, 0, 1) -- 黑色
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    frame:Hide()
    button._iconBorder = frame
    return frame
end

local function ApplyIconBorderStyle(button, slotStyle)
    local frame = GetOrCreateIconBorder(button)
    if slotStyle == "square" then
        frame:Show()
    else
        frame:Hide()
    end
end

-- 根据当前主题应用按钮的图标边框/空槽背景/贴图裁剪样式
-- 主按钮与 flyout 按钮共用，保证切换主题后二者行为一致
-- bare=true 时不显示任何外边框（flyout 下拉图标使用）
local function ApplyButtonThemeStyle(button, buttonSize, bare)
    if not button then return end

    local icon = getglobal(button:GetName() .. "IconTexture")
    local normalTex = getglobal(button:GetName() .. "NormalTexture")
    local emptyBg = getglobal(button:GetName() .. "_EmptySlotBg")

    if icon then
        icon:SetWidth(buttonSize)
        icon:SetHeight(buttonSize)
    end

    if bare then
        -- 无外边框模式（flyout 下拉图标）：隐藏空槽背景与圆角边框，
        -- 图标完整显示，不带任何外框
        if normalTex then
            normalTex:Hide()
        end
        if emptyBg then
            emptyBg:Hide()
        end
        if icon then
            icon:SetTexCoord(0, 1, 0, 1)
        end
        ApplyIconBorderStyle(button, "rounded")
        return
    end

    local slotStyle = "rounded"
    if addon.Modules and addon.Modules.Theme then
        slotStyle = addon.Modules.Theme:GetSlotStyle()
    end

    if slotStyle == "square" then
        -- pfUI 模式：隐藏圆角边框，裁剪图标，加黑色 1 像素边框
        button:SetNormalTexture("")
        if normalTex then
            normalTex:SetTexture(nil)
            normalTex:Hide()
        end
        if icon then
            icon:SetTexCoord(.08, .92, .08, .92)
        end
        ApplyIconBorderStyle(button, "square")
        -- 空槽背景改为方形深色，避免圆角 UI-EmptySlot 露出外边框
        if emptyBg then
            emptyBg:SetTexture("Interface\\Buttons\\WHITE8x8")
            emptyBg:SetVertexColor(0.05, 0.05, 0.05, 1)
            emptyBg:ClearAllPoints()
            emptyBg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            emptyBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            emptyBg:Show()
        end
    else
        -- 圆角模式：保持图标原始外观（保留贴图自带的圆角边框），
        -- 恢复被方形模式销毁的圆角边框纹理
        if icon then
            icon:SetTexCoord(0, 1, 0, 1)
        end
        ApplyIconBorderStyle(button, "rounded")
        local borderSize = buttonSize * 64 / 37
        if normalTex then
            if not normalTex:GetTexture() then
                normalTex:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            end
            normalTex:SetWidth(borderSize)
            normalTex:SetHeight(borderSize)
            normalTex:Show()
        end
        if emptyBg then
            emptyBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            emptyBg:SetVertexColor(1, 1, 1, 1)
            emptyBg:SetTexCoord(0, 1, 0, 1)
            emptyBg:ClearAllPoints()
            emptyBg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            emptyBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            emptyBg:SetWidth(buttonSize)
            emptyBg:SetHeight(buttonSize)
            emptyBg:Show()
        end
    end
end

-- 重新应用所有已存在按钮（含 flyout）的主题样式，用于主题切换后的即时刷新
function QuestItemBar:RefreshIconStyles()
    local buttonSize = addon.Modules.DB:GetSetting("questBarSize") or 36
    for _, button in ipairs(buttons) do
        ApplyButtonThemeStyle(button, buttonSize)
    end
    for _, btn in ipairs(flyoutButtons) do
        ApplyButtonThemeStyle(btn, buttonSize, true)
    end
end

--=====================================================
-- 任务物品检测（使用集中式 ItemDetection 模块）
--=====================================================

-- 组合函数：检查物品是否既是任务物品且可用
-- 使用集中式 ItemDetection 模块以保证检测的一致性
function QuestItemBar:CheckQuestItemUsable(bagID, slotID)
    if not bagID or not slotID then return false, false, false end

    -- 获取物品数据供 ItemDetection 使用
    local itemData = nil
    if addon.Modules.BagScanner then
        itemData = addon.Modules.BagScanner:ScanSlot(bagID, slotID)
    end

    -- 使用集中式 ItemDetection
    if addon.Modules.ItemDetection and itemData then
        local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
        return props.isQuestItem, props.isQuestStarter, props.isQuestUsable
    end

    -- ItemDetection 不可用时回退到 Utils
    if addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
        local isQuestItem, isQuestStarter = addon.Modules.Utils:IsQuestItem(bagID, slotID, nil, false, false)
        -- 可用性回退：检查是否为任务物品（假定可用）
        return isQuestItem, isQuestStarter, isQuestItem
    end

    return false, false, false
end

-- 扫描背包中的任务物品（优化：每个物品只做一次 tooltip 扫描）
function QuestItemBar:ScanForQuestItems()
    questItems = {}

    -- 扫描背包和 4 个背包
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                -- 单次组合检查，而非两次独立的 tooltip 扫描
                local isQuest, isStarter, isUsable = self:CheckQuestItemUsable(bagID, slotID)
                if isQuest and isUsable and not isStarter then
                    table.insert(questItems, {
                        bagID = bagID,
                        slotID = slotID,
                        texture = texture,
                        count = count
                    })
                end
            end
        end
    end
end

-- 为兼容性保留的旧函数（现在调用组合函数）
function QuestItemBar:IsQuestItem(bagID, slotID)
    local isQuestItem, isQuestStarter, _ = self:CheckQuestItemUsable(bagID, slotID)
    return isQuestItem, isQuestStarter
end

function QuestItemBar:PinItem(itemID, slot)
    if not itemID then return end
    local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
    
    local targetSlot = slot or 1
    if not slot then
        -- 原始逻辑：找到第一个空位，否则替换第一个
        for i = 1, 2 do
            if pins[i] == itemID then return end
        end
        
        for i = 1, 2 do
            if not pins[i] then
                targetSlot = i
                break
            end
        end
    end
    
    pins[targetSlot] = itemID
    addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
    self:Update()
    return true
end

-- 更新物品条按钮
function QuestItemBar:Update()
    local showQuestBar = addon.Modules.DB:GetSetting("showQuestBar")
    local frame = Guda_QuestItemBar
    
    if not frame then return end

    if showQuestBar == false then
        frame:Hide()
        return
    end
    
    self:ScanForQuestItems()
    
    -- 如果没有找到任务物品，隐藏物品条
    if table.getn(questItems or {}) == 0 then
        frame:Hide()
        return
    end

    frame:Show()

    local pinnedItems = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
    local buttonSize = addon.Modules.DB:GetSetting("questBarSize") or 36
    local spacing = 2
    local xOffset = 5

    -- 根据按钮尺寸更新框架高度
    frame:SetHeight(buttonSize + 8)
    
    -- 用于跟踪哪些背包物品已被显示
    local usedBagSlots = {}

    local slots = math.min(2, table.getn(questItems or {}))
    for i = 1, slots do
        local index = i
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", "Guda_QuestItemBarButton" .. i, frame, "Guda_ItemButtonTemplate")
            table.insert(buttons, button)
            
            -- 按钮只设置一次
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function() end)
            button:SetScript("OnReceiveDrag", function() end)
            button:SetScript("OnMouseDown", function()
                if arg1 == "LeftButton" then
                    local parent = this:GetParent()
                    if parent and IsShiftKeyDown() and not parent.isMoving and not (CursorHasItem and CursorHasItem()) then
                        parent:StartMoving()
                        parent.isMoving = true
                    end
                end
            end)
            button:SetScript("OnMouseUp", function()
                if arg1 == "LeftButton" then
                    local parent = this:GetParent()
                    if parent and parent.isMoving then
                        parent:StopMovingOrSizing()
                        parent.isMoving = false
                        local point, _, relativePoint, x, y = parent:GetPoint()
                        if point then
                            addon.Modules.DB:SetSetting("questBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
                        end
                    end
                end
            end)
        end

        local itemToDisplay = nil
        
        -- 1. 尝试为该位置查找已固定的物品
        local pinnedID = pinnedItems[i]
        if pinnedID then
            -- 在背包中查找该物品
            for _, item in ipairs(questItems) do
                local itemID = addon.Modules.Utils:ExtractItemID(GetContainerItemLink(item.bagID, item.slotID))
                if itemID == pinnedID and not usedBagSlots[item.bagID .. ":" .. item.slotID] then
                    itemToDisplay = item
                    usedBagSlots[item.bagID .. ":" .. item.slotID] = true
                    break
                end
            end
        end
        
        -- 2. 如果没有固定物品或未找到固定物品，则自动填充
        if not itemToDisplay then
            for _, item in ipairs(questItems) do
                if not usedBagSlots[item.bagID .. ":" .. item.slotID] then
                    itemToDisplay = item
                    usedBagSlots[item.bagID .. ":" .. item.slotID] = true
                    break
                end
            end
        end

        if itemToDisplay then
            button.bagID = itemToDisplay.bagID
            button.slotID = itemToDisplay.slotID
            button.hasItem = true
            button.fromDB = itemToDisplay.fromDB
            
            local link = itemToDisplay.link
            if not link and itemToDisplay.bagID and itemToDisplay.slotID then
                link = GetContainerItemLink(itemToDisplay.bagID, itemToDisplay.slotID)
            end
            button.itemData = { link = link }
            
            local icon = getglobal(button:GetName() .. "IconTexture")
            icon:SetTexture(itemToDisplay.texture)
            icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
            
            local countText = getglobal(button:GetName() .. "Count")
            if itemToDisplay.count > 1 then
                countText:SetText(itemToDisplay.count)
                countText:Show()
            else
                countText:Hide()
            end
            
            button:SetScript("OnClick", function()
                if this.fromDB then
                    addon:Print(GudaBag.L["Item is not currently in your bags (loading from database)."])
                    return
                end
                
                if arg1 == "LeftButton" then
                    if CursorHasItem() then
                        -- 尝试固定鼠标指针上的物品
                        local tooltip = addon.Modules.Utils:GetScanTooltip()
                        tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
                        tooltip:SetCursorItem()
                        local link = nil
                        -- 在 1.12 中从指针获取链接很困难。
                        -- 固定操作将依赖背包中的 Alt-点击。
                    end

                    if not IsShiftKeyDown() then
                        UseContainerItem(this.bagID, this.slotID)
                    end
                elseif arg1 == "RightButton" then
                    if IsAltKeyDown() then
                        -- 清除该位置的固定
                        local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
                        pins[index] = nil
                        addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
                        QuestItemBar:Update()
                    elseif not IsShiftKeyDown() then
                        UseContainerItem(this.bagID, this.slotID)
                    end
                end
end)

            button:Show()
        else
            -- 空位置
            button.hasItem = false
            button.bagID = nil
            button.slotID = nil
            
            local icon = getglobal(button:GetName() .. "IconTexture")
            local slotStyle = "rounded"
            if addon.Modules and addon.Modules.Theme then
                slotStyle = addon.Modules.Theme:GetSlotStyle()
            end
            if slotStyle == "square" then
                icon:SetTexture("Interface\\Buttons\\WHITE8x8")
                icon:SetVertexColor(0.05, 0.05, 0.05, 0.5)
            else
                icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                icon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
            end
            
            local countText = getglobal(button:GetName() .. "Count")
            countText:Hide()
            
            button:SetScript("OnClick", function()
                if arg1 == "LeftButton" then
                    if CursorHasItem() then
                        -- 在 1.12 中，没有 hooks 时从指针固定很困难。
                    end
                elseif arg1 == "RightButton" then
                    if IsAltKeyDown() then
                        -- 清除该位置的固定
                        local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
                        pins[index] = nil
                        addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
                        QuestItemBar:Update()
                    end
                end
            end)
            
            button:Show()
        end

        button:SetScript("OnEnter", function()
            if this.hasItem then
                GudaBag.ItemButton_OnEnter(this)
            else
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(string.format(GudaBag.L["Quest Slot %d"] or "Quest Slot %d", index))
                GameTooltip:AddLine(GudaBag.L["Auto-fills with usable quest items."], 1, 1, 1)
                GameTooltip:AddLine(GudaBag.L["Alt-Click an item in bags to pin it."], 0, 1, 0)
                GameTooltip:AddLine(GudaBag.L["Alt-Right-Click to unpin."], 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
            
            -- 仅在还有更多任务物品可显示时显示弹出面板
            if QuestItemBar:HasExtraQuestItems() then
                QuestItemBar:ShowFlyout(this)
            end
        end)

        button:SetScript("OnLeave", function()
            if this.hasItem then
                GudaBag.ItemButton_OnLeave(this)
            else
                GameTooltip:Hide()
            end
            QuestItemBar:HideFlyout()
        end)

        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", xOffset + (i-1) * (buttonSize + spacing), 0)
        button:SetWidth(buttonSize)
        button:SetHeight(buttonSize)

        -- 根据当前主题应用图标边框/空槽背景/贴图裁剪样式
        ApplyButtonThemeStyle(button, buttonSize)

        -- 更新视觉覆盖层（冷却时间等）
        if GudaBag.ItemButton_UpdateCooldown then
            GudaBag.ItemButton_UpdateCooldown(button)
        end
    end

    -- 隐藏超出当前位置的额外按钮
    for j = slots + 1, table.getn(buttons) do
        local extra = buttons[j]
        if extra then
            extra:Hide()
            extra.hasItem = false
        end
    end

    -- 为当前位置数量设置固定宽度
    local newWidth = xOffset * 2 + slots * (buttonSize + spacing) - spacing
    frame:SetWidth(newWidth)
end

function QuestItemBar:UpdateCooldowns()
    for _, button in ipairs(buttons) do
        if button:IsShown() and GudaBag.ItemButton_UpdateCooldown then
            GudaBag.ItemButton_UpdateCooldown(button)
        end
    end
    for _, button in ipairs(flyoutButtons) do
        if button:IsShown() and GudaBag.ItemButton_UpdateCooldown then
            GudaBag.ItemButton_UpdateCooldown(button)
        end
    end
end

-- 检查是否有多于主位置显示数量的任务物品
function QuestItemBar:HasExtraQuestItems()
    local mainItemIDs = {}
    for i = 1, 2 do
        local btn = buttons[i]
        if btn and btn.hasItem and btn.itemData and btn.itemData.link then
            local id = addon.Modules.Utils:ExtractItemID(btn.itemData.link)
            if id then mainItemIDs[id] = true end
        end
    end
    
    for _, item in ipairs(questItems or {}) do
        local link = item.link
        if not link and item.bagID and item.slotID then
            link = GetContainerItemLink(item.bagID, item.slotID)
        end
        
        if link then
            local id = addon.Modules.Utils:ExtractItemID(link)
            if id and not mainItemIDs[id] then
                return true
            end
        end
    end
    
    return false
end

function QuestItemBar:ShowFlyout(parent)
    if not flyoutFrame then return end
    
    self:UpdateFlyout(parent)
    flyoutFrame:Show()
end

function QuestItemBar:HideFlyout(immediate)
    if not flyoutFrame then return end
    
    if immediate then
        flyoutFrame:Hide()
        flyoutFrame:SetScript("OnUpdate", nil)
        return
    end
    
    -- 延迟隐藏以允许鼠标移向弹出面板
    flyoutFrame.hideTime = GetTime() + 0.1
    flyoutFrame:SetScript("OnUpdate", function()
        if GetTime() > this.hideTime then
            if not MouseIsOver(this) and (not this.parent or not MouseIsOver(this.parent)) then
                this:Hide()
            end
            this:SetScript("OnUpdate", nil)
        end
    end)
end

function QuestItemBar:UpdateFlyout(parent)
    if not flyoutFrame then return end
    flyoutFrame.parent = parent

    local buttonSize = addon.Modules.DB:GetSetting("questBarSize") or 36
    local spacing = 2
    
    -- 收集不在主按钮中的物品
    local displayItems = {}
    local mainItemIDs = {}
    for _, btn in ipairs(buttons) do
        if btn and btn.hasItem and btn.itemData and btn.itemData.link then
            local id = addon.Modules.Utils:ExtractItemID(btn.itemData.link)
            if id then mainItemIDs[id] = true end
        end
    end
    
    for _, item in ipairs(questItems) do
        local link = GetContainerItemLink(item.bagID, item.slotID)
        local id = addon.Modules.Utils:ExtractItemID(link)
        if id and not mainItemIDs[id] then
            -- 如果存在多个堆叠则避免弹出面板中出现重复（可选，但 TrinketMenu 也这样做）
            local alreadyInFlyout = false
            for _, existing in ipairs(displayItems) do
                if existing.itemID == id then
                    alreadyInFlyout = true
                    break
                end
            end
            
            if not alreadyInFlyout then
                table.insert(displayItems, {
                    bagID = item.bagID,
                    slotID = item.slotID,
                    texture = item.texture,
                    count = item.count,
                    itemID = id,
                    link = link
                })
            end
        end
    end
    
    -- 先隐藏所有弹出面板按钮
    for _, btn in ipairs(flyoutButtons) do
        btn:Hide()
    end
    
    if table.getn(displayItems) == 0 then
        flyoutFrame:Hide()
        return
    end
    
    -- 将弹出面板定位在父按钮上方
    flyoutFrame:ClearAllPoints()
    flyoutFrame:SetPoint("BOTTOM", parent, "TOP", 0, 5)
    
    for i, item in ipairs(displayItems) do
        local btn = flyoutButtons[i]
        if not btn then
            btn = CreateFrame("Button", "Guda_QuestItemFlyoutButton" .. i, flyoutFrame, "Guda_ItemButtonTemplate")
            table.insert(flyoutButtons, btn)
            
            btn:SetScript("OnDragStart", function() end)
            btn:SetScript("OnReceiveDrag", function() end)
            btn:SetScript("OnMouseDown", function() end)
            
            btn:SetScript("OnEnter", function()
                GudaBag.ItemButton_OnEnter(this)
                if flyoutFrame then flyoutFrame.hideTime = GetTime() + 5 end -- 保持打开
            end)
            btn:SetScript("OnLeave", function()
                GudaBag.ItemButton_OnLeave(this)
                QuestItemBar:HideFlyout()
            end)
        end
        
        btn.bagID = item.bagID
        btn.slotID = item.slotID
        btn.hasItem = true
        btn.fromDB = item.fromDB
        btn.itemData = { link = item.link }
        btn.itemID = item.itemID
        
        local icon = getglobal(btn:GetName() .. "IconTexture")
        icon:SetTexture(item.texture)
        
        local countText = getglobal(btn:GetName() .. "Count")
        if item.count > 1 then
            countText:SetText(item.count)
            countText:Show()
        else
            countText:Hide()
        end
        
        btn:SetScript("OnClick", function()
            if this.fromDB then
                addon:Print(GudaBag.L["Item is not currently in your bags (loading from database)."])
                return
            end
            
            local targetSlot = 1
            if flyoutFrame.parent then
                -- 检查父按钮是否为 Guda_QuestItemBarButton2
                if flyoutFrame.parent:GetName() == "Guda_QuestItemBarButton2" then
                    targetSlot = 2
                end
            end
            
            if arg1 == "LeftButton" then
                QuestItemBar:PinItem(this.itemID, targetSlot)
            elseif arg1 == "RightButton" then
                -- 两种点击现在都根据上下文作用于 targetSlot，
                -- 但我们会保留 RightButton 对应位置 2 作为回退/原始行为，
                -- 或者如果需要“两次点击都在鼠标 1 上工作”，也可以都使用 targetSlot。
                -- 需求是“让两次点击都在鼠标 1 上工作，而不是鼠标 2，且鼠标 1 点击分别作用于不同物品条”。
                -- 这种措辞有些含糊，但按上下文理解，它的意思是
                -- 在弹出面板按钮上的鼠标 1 点击应替换鼠标悬停的物品条。
                QuestItemBar:PinItem(this.itemID, targetSlot)
            end
            QuestItemBar:HideFlyout(true)
        end)
        
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOM", flyoutFrame, "BOTTOM", 0, (i-1) * (buttonSize + spacing) + 5)
        btn:SetWidth(buttonSize)
        btn:SetHeight(buttonSize)

        -- 根据当前主题应用图标样式（bare：无外边框）
        ApplyButtonThemeStyle(btn, buttonSize, true)

        btn:Show()

        if GudaBag.ItemButton_UpdateCooldown then
            GudaBag.ItemButton_UpdateCooldown(btn)
        end
    end
    
    flyoutFrame:SetWidth(buttonSize + 10)
    flyoutFrame:SetHeight(table.getn(displayItems) * (buttonSize + spacing) + 10)
end

-- 键绑定的全局包装函数
function GudaBag.UseQuestItem1()
    local button = getglobal("Guda_QuestItemBarButton1")
    if button and button:IsShown() and button.hasItem and button.bagID and button.slotID then
        UseContainerItem(button.bagID, button.slotID)
    end
end

function GudaBag.UseQuestItem2()
    local button = getglobal("Guda_QuestItemBarButton2")
    if button and button:IsShown() and button.hasItem and button.bagID and button.slotID then
        UseContainerItem(button.bagID, button.slotID)
    end
end

function QuestItemBar:Initialize()
    local frame = CreateFrame("Frame", "Guda_QuestItemBar", UIParent)
    frame:SetWidth(40)
    frame:SetHeight(45)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    --addon:ApplyBackdrop(frame, "DEFAULT_FRAME")
    
    -- 创建弹出面板框架
    flyoutFrame = CreateFrame("Frame", "Guda_QuestItemFlyout", UIParent)
    flyoutFrame:SetFrameStrata("TOOLTIP")
    flyoutFrame:Hide()
    -- 弹出面板无背景无边框，纯浮层（避免任何外框贴着图标显示）
    
    -- 处理拖拽
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" and IsShiftKeyDown() and not this.isMoving then
            this:StartMoving()
            this.isMoving = true
        end
    end)
    frame:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" and this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            local point, _, relativePoint, x, y = this:GetPoint()
            if point then
                addon.Modules.DB:SetSetting("questBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
            end
        end
    end)
    
    -- 恢复位置
    local pos = addon.Modules.DB:GetSetting("questBarPosition")
    if pos and pos.point then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
    end
    
    -- 注册事件并进行防抖，避免快速背包更新时卡顿
    local bagUpdatePending = false
    addon.Modules.Events:Register("BAG_UPDATE", function()
        -- 排序进行中时跳过更新（排序完成会触发更新）
        if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then return end
        if bagUpdatePending then return end
        bagUpdatePending = true
        -- 防抖：更新前等待 0.15 秒（使用池化计时器）
        GudaBag.ScheduleTimer(0.15, function()
            bagUpdatePending = false
            QuestItemBar:Update()
        end)
    end, "QuestItemBar")

    addon.Modules.Events:Register("BAG_UPDATE_COOLDOWN", function()
        QuestItemBar:UpdateCooldowns()
    end, "QuestItemBar")
    
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        QuestItemBar:Update()
    end, "QuestItemBar")

    QuestItemBar:Update()
    addon:Debug("QuestItemBar initialized")
end

-- 用于诊断 QuestItemBar 问题的调试函数
-- 用法: /script Guda.Modules.QuestItemBar:Debug()
function QuestItemBar:Debug()
    addon:Print("=== QuestItemBar Debug ===")

    -- 检查设置
    local showQuestBar = addon.Modules.DB:GetSetting("showQuestBar")
    addon:Print("showQuestBar setting: " .. tostring(showQuestBar))

    -- 检查框架
    local frame = Guda_QuestItemBar
    addon:Print("Frame exists: " .. tostring(frame ~= nil))
    if frame then
        addon:Print("Frame shown: " .. tostring(frame:IsShown()))
    end

    -- 扫描所有背包以查找可能的任务物品
    addon:Print("--- Scanning bags ---")
    local foundCount = 0
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                local itemLink = GetContainerItemLink(bagID, slotID)
                local itemData = addon.Modules.BagScanner:ScanSlot(bagID, slotID)

                if itemData then
                    local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)

                    -- 显示与任务相关或拥有 Quest 类别的物品
                    if props.isQuestItem or props.isQuestUsable or (itemData.class and itemData.class == "Quest") then
                        foundCount = foundCount + 1
                        addon:Print(string.format("[%d:%d] %s", bagID, slotID, itemData.name or "Unknown"))
                        addon:Print(string.format("  class=%s, isQuest=%s, isUsable=%s, isStarter=%s",
                            tostring(itemData.class),
                            tostring(props.isQuestItem),
                            tostring(props.isQuestUsable),
                            tostring(props.isQuestStarter)))

                        -- 检查它是否会显示在物品条中
                        local wouldShow = props.isQuestItem and props.isQuestUsable and not props.isQuestStarter
                        addon:Print("  Would show in bar: " .. tostring(wouldShow))
                    end
                end
            end
        end
    end

    if foundCount == 0 then
        addon:Print("No quest-related items found in bags")
    end

    addon:Print("=== End Debug ===")
end

QuestItemBar.isLoaded = true
