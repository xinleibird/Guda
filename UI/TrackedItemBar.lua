-- Guda 追踪物品条
-- 显示被追踪的物品及其背包总数量

local addon = Guda
local TrackedItemBar = addon.Modules.TrackedItemBar
if not TrackedItemBar then
    TrackedItemBar = {}
    addon.Modules.TrackedItemBar = TrackedItemBar
end

local buttons = {}
local trackedItemsInfo = {}

--=====================================================
-- 追踪物品条按钮图标边框（跟随主题风格）
-- 圆角（GUDA/暴雪默认）：保持图标原始外观（保留贴图自带边框）
-- 方形（pfUI）：裁掉图标自带边框，改为黑色 1 像素边框
--（与任务栏 QuestItemBar 的实现保持一致）
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
local function ApplyButtonThemeStyle(button, buttonSize)
    if not button then return end

    local icon = getglobal(button:GetName() .. "IconTexture")
    local normalTex = getglobal(button:GetName() .. "NormalTexture")
    local emptyBg = getglobal(button:GetName() .. "_EmptySlotBg")

    if icon then
        icon:SetWidth(buttonSize)
        icon:SetHeight(buttonSize)
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
        -- 圆角模式：保持图标原始外观，恢复被方形模式销毁的圆角边框纹理
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

-- 重新应用所有已存在按钮的主题样式，用于主题切换后的即时刷新
function TrackedItemBar:RefreshIconStyles()
    local buttonSize = addon.Modules.DB:GetSetting("trackedBarSize") or 36
    for _, button in ipairs(buttons) do
        ApplyButtonThemeStyle(button, buttonSize)
    end
end

-- 通过扫描 tooltip 检查物品是否为任务物品
local function IsQuestItem(bagID, slotID)
    if addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
        return addon.Modules.Utils:IsQuestItem(bagID, slotID, nil, false, false)
    end
    return false, false
end

-- 扫描背包中的追踪物品并计算总数
function TrackedItemBar:ScanForTrackedItems()
    trackedItemsInfo = {}
    local trackedIDs = addon.Modules.DB:GetSetting("trackedItems") or {}

    local itemCounts = {}
    local itemTextures = {}
    local itemLinks = {}
    local itemOrder = {}
    local itemIsQuest = {}
    local itemIsQuestStarter = {}

    -- 扫描背包和 4 个背包
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                local link = GetContainerItemLink(bagID, slotID)
                -- 若安装了 Nampower，直接用其 itemId（免正则提取）
                local id = nil
                if addon.Modules.Nampower and addon.Modules.Nampower:IsAvailable() then
                    id = addon.Modules.Nampower:GetBagItemInfo(bagID, slotID)
                end
                if not id and link then
                    id = addon.Modules.Utils:ExtractItemID(link)
                end
                if id and trackedIDs[id] then
                    if not itemCounts[id] then
                        itemCounts[id] = 0
                        itemTextures[id] = texture
                        itemLinks[id] = link
                        itemCounts[id .. "_bag"] = bagID
                        itemCounts[id .. "_slot"] = slotID
                        -- 检查是否为任务物品
                        local isQuest, isStarter = IsQuestItem(bagID, slotID)
                        itemIsQuest[id] = isQuest
                        itemIsQuestStarter[id] = isStarter
                        table.insert(itemOrder, id)
                    end
                    itemCounts[id] = itemCounts[id] + count
                end
            end
        end
    end

    for _, id in ipairs(itemOrder) do
        local bagID = itemCounts[id .. "_bag"]
        local slotID = itemCounts[id .. "_slot"]
        local link = itemLinks[id]

        -- 使用集中式 ItemDetection 检测不可用和垃圾状态
        local isUnusable = false
        local isJunk = false
        if addon.Modules.ItemDetection and link then
            local itemData = { link = link }
            local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
            isUnusable = props.isUnusable
            isJunk = props.isJunk
        end

        table.insert(trackedItemsInfo, {
            itemID = id,
            texture = itemTextures[id],
            count = itemCounts[id],
            link = link,
            bagID = bagID,
            slotID = slotID,
            isQuest = itemIsQuest[id],
            isQuestStarter = itemIsQuestStarter[id],
            isUnusable = isUnusable,
            isJunk = isJunk,
        })
    end
end

-- 更新物品条按钮
function TrackedItemBar:Update()
    local frame = Guda_TrackedItemBar
    
    if not frame then return end
    frame:Show()

    self:ScanForTrackedItems()

    local buttonSize = addon.Modules.DB:GetSetting("trackedBarSize") or 36
    local spacing = 2
    local xOffset = 5

    -- 根据按钮尺寸更新框架高度
    frame:SetHeight(buttonSize + 8)
    
    -- 初始时隐藏所有按钮及其覆盖层
    for _, btn in ipairs(buttons) do
        btn:Hide()
        if btn.unusableOverlay then btn.unusableOverlay:Hide() end
        if btn.junkIcon then btn.junkIcon:Hide() end
    end

    for i, info in ipairs(trackedItemsInfo) do
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", "Guda_TrackedItemBarButton" .. i, frame, "Guda_ItemButtonTemplate")
            table.insert(buttons, button)

            -- 创建任务边框（金色）
            local questBorder = CreateFrame("Frame", nil, button)
            questBorder:SetFrameLevel(button:GetFrameLevel() + 6)
            questBorder:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
                insets = {left = 4, right = 4, top = 4, bottom = 4}
            })
            questBorder:SetBackdropBorderColor(1.0, 0.82, 0, 1)
            questBorder:Hide()
            button.questBorder = questBorder

            -- 创建任务图标（角落的问号）
            local questIcon = CreateFrame("Frame", nil, button)
            questIcon:SetFrameLevel(button:GetFrameLevel() + 7)
            questIcon:SetWidth(16)
            questIcon:SetHeight(16)
            local iconTex = questIcon:CreateTexture(nil, "OVERLAY")
            iconTex:SetAllPoints(questIcon)
            iconTex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
            iconTex:SetTexCoord(0, 1, 0, 1)
            questIcon:Hide()
            button.questIcon = questIcon

            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function() end)
            button:SetScript("OnReceiveDrag", function() end)
            button:SetScript("OnMouseDown", function()
                if arg1 == "LeftButton" then
                    if IsShiftKeyDown() and not (CursorHasItem and CursorHasItem()) then
                        this:GetParent():StartMoving()
                        this:GetParent().isMoving = true
                    end
                end
            end)
            button:SetScript("OnMouseUp", function()
                if arg1 == "LeftButton" then
                    local parent = this:GetParent()
                    if parent.isMoving then
                        parent:StopMovingOrSizing()
                        parent.isMoving = false
                        local point, _, relativePoint, x, y = parent:GetPoint()
                        addon.Modules.DB:SetSetting("trackedBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
                    end
                end
            end)
        end

        button.hasItem = true
        button.itemData = { link = info.link }
        button.itemID = info.itemID
        button.bagID = info.bagID
        button.slotID = info.slotID
        button.isReadOnly = false -- 改为 false 以允许交互并显示使用方法的 tooltip
        
        local icon = getglobal(button:GetName() .. "IconTexture")
        icon:SetTexture(info.texture)
        icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
        
        local countText = getglobal(button:GetName() .. "Count")
        countText:SetText(info.count)
        countText:Show()
        
        button:SetScript("OnClick", function()
            if IsAltKeyDown() and arg1 == "LeftButton" then
                -- 取消追踪物品
                local itemID = this.itemID
                if itemID then
                    local trackedIDs = addon.Modules.DB:GetSetting("trackedItems") or {}
                    trackedIDs[itemID] = nil
                    addon.Modules.DB:SetSetting("trackedItems", trackedIDs)
                    
                    -- 更新所有相关内容
                    if Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
                        Guda.Modules.BagFrame:Update()
                    end
                    TrackedItemBar:Update()
                end
            elseif not IsShiftKeyDown() then
                -- 使用物品
                if this.bagID and this.slotID then
                    UseContainerItem(this.bagID, this.slotID)
                end
            end
        end)
        
        button:SetScript("OnEnter", function()
            GudaBag.ItemButton_OnEnter(this)
        end)

        button:SetScript("OnLeave", function()
            GudaBag.ItemButton_OnLeave(this)
        end)

        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", xOffset + (i-1) * (buttonSize + spacing), 0)
        button:SetWidth(buttonSize)
        button:SetHeight(buttonSize)

        -- 根据当前主题应用图标边框/空槽背景/贴图裁剪样式
        ApplyButtonThemeStyle(button, buttonSize)

        -- 定位并显示/隐藏任务边框
        if button.questBorder then
            button.questBorder:ClearAllPoints()
            button.questBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
            button.questBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            if info.isQuest then
                button.questBorder:Show()
            else
                button.questBorder:Hide()
            end
        end

        -- 定位并显示/隐藏任务图标
        if button.questIcon then
            local questIconSize = math.max(12, math.min(20, buttonSize * 0.35))
            button.questIcon:SetWidth(questIconSize)
            button.questIcon:SetHeight(questIconSize)
            button.questIcon:ClearAllPoints()
            button.questIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 0)

            if info.isQuest then
                -- 根据任务类型设置合适的贴图
                local tex = button.questIcon:GetRegions()
                if tex and tex.SetTexture then
                    if info.isQuestStarter then
                        tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                    else
                        tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
                    end
                end
                button.questIcon:Show()
            else
                button.questIcon:Hide()
            end
        end

        -- 应用不可用的红色覆盖层（与背包位置指示器相同）
        if info.isUnusable then
            if not button.unusableOverlay then
                local overlay = button:CreateTexture(nil, "OVERLAY")
                overlay:SetAllPoints(icon)
                overlay:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                overlay:Hide()
                button.unusableOverlay = overlay
            end
            local r, g, b = 0.9, 0.2, 0.2
            if RED_FONT_COLOR then
                r, g, b = RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b
            end
            button.unusableOverlay:SetVertexColor(r, g, b, 0.45)
            button.unusableOverlay:Show()
        else
            if button.unusableOverlay then
                button.unusableOverlay:Hide()
            end
        end

        -- 应用垃圾物品商人图标（与背包位置指示器相同）
        if info.isJunk then
            if not button.junkIcon then
                local junkFrame = CreateFrame("Frame", nil, button)
                junkFrame:SetFrameStrata("HIGH")
                local junkTex = junkFrame:CreateTexture(nil, "OVERLAY")
                junkTex:SetAllPoints(junkFrame)
                junkTex:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")
                junkTex:SetTexCoord(0, 1, 0, 1)
                junkFrame.texture = junkTex
                button.junkIcon = junkFrame
            end
            local junkIconSize = math.max(10, math.min(14, buttonSize * 0.30))
            button.junkIcon:SetWidth(junkIconSize)
            button.junkIcon:SetHeight(junkIconSize)
            button.junkIcon:ClearAllPoints()
            button.junkIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
            button.junkIcon:Show()
        else
            if button.junkIcon then
                button.junkIcon:Hide()
            end
        end

        button:Show()
    end

    local numItems = table.getn(trackedItemsInfo)
    if numItems > 0 then
        local newWidth = xOffset * 2 + numItems * (buttonSize + spacing) - spacing
        frame:SetWidth(newWidth)
        frame:Show()
    else
        frame:Hide()
    end
end

function TrackedItemBar:Initialize()
    local frame = CreateFrame("Frame", "Guda_TrackedItemBar", UIParent)
    frame:SetWidth(40)
    frame:SetHeight(45)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200) -- 默认位于任务条上方
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    --addon:ApplyBackdrop(frame, "DEFAULT_FRAME")
    
    -- 处理拖拽
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            if IsShiftKeyDown() and not (CursorHasItem and CursorHasItem()) then
                this:StartMoving()
                this.isMoving = true
            end
        end
    end)
    frame:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" and this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            local point, _, relativePoint, x, y = this:GetPoint()
            addon.Modules.DB:SetSetting("trackedBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
        end
    end)
    
    -- 恢复位置
    local pos = addon.Modules.DB:GetSetting("trackedBarPosition")
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
            TrackedItemBar:Update()
        end)
    end, "TrackedItemBar")
    
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        TrackedItemBar:Update()
    end, "TrackedItemBar")

    addon.Modules.Events:Register("PLAYER_LEVEL_UP", function()
        -- 延迟以让客户端先更新内部玩家等级，再重新扫描 tooltips
        GudaBag.ScheduleTimer(0.5, function()
            if addon.Modules.ItemDetection then
                addon.Modules.ItemDetection:ClearCache()
            end
            TrackedItemBar:Update()
        end)
    end, "TrackedItemBar")

    TrackedItemBar:Update()
    addon:Debug("TrackedItemBar initialized")
end

TrackedItemBar.isLoaded = true
