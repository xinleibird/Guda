-- 插件根表的本地别名（必须在下方任何使用之前定义）
local addon = Guda

-- 物品按钮池
local buttonPool = {}
local nextButtonID = 1
local BUTTON_POOL_MAX = 500  -- 要创建的按钮最大数量（背包约80 + 银行约200 + 钥匙扣约96 + 两个界面同时打开时的缓冲）

-- 分类拖放：记录光标物品用于分类重新分配
local cursorItemInfo = nil  -- 记录的数据：{ bagID（背包ID）, slotID（格子ID）, itemID（物品ID）, link（物品链接） }
local activeCategoryDropIndicator = nil  -- 当前显示的 "+" 指示按钮

-- 获取按钮池统计信息（用于 /guda perf 命令）
function GudaBag.GetButtonPoolStats()
    local total = 0
    local shown = 0
    local hidden = 0
    local inUse = 0
    local available = 0
    for _, button in pairs(buttonPool) do
        total = total + 1
        if button:IsShown() then
            shown = shown + 1
        else
            hidden = hidden + 1
        end
        if button.inUse then
            inUse = inUse + 1
        else
            available = available + 1
        end
    end
    return {
        total = total,
        shown = shown,
        hidden = hidden,
        inUse = inUse,
        available = available,
        maxSize = BUTTON_POOL_MAX,
    }
end

-- 重置按钮池（用于测试/调试）
-- 警告：仅当没有背包/银行界面可见时才可调用！
function GudaBag.ResetButtonPool()
    -- 隐藏并清理所有按钮
    for id, button in pairs(buttonPool) do
        button:Hide()
        button:ClearAllPoints()
        -- 从父级跟踪中清除
        local parent = button:GetParent()
        if parent and parent.itemButtons then
            parent.itemButtons[button] = nil
        end
    end
    -- 清空池表
    for k in pairs(buttonPool) do
        buttonPool[k] = nil
    end
    -- 重置计数器
    nextButtonID = 1
end

-- 将所有按钮标记为可复用（切换视图类型时调用）
-- 这允许一个界面的按钮被另一个界面复用
function GudaBag.ReleaseAllButtons()
    for _, button in pairs(buttonPool) do
        if not button.isBagSlot then
            button.inUse = false
        end
    end
end

-- 分类投放指示器：一个共享的单个框架（父级为 UIParent），带加号图标
local HideCategoryDropIndicator  -- 前向声明
local categoryDropIndicator = nil  -- 唯一的共享指示器框架
local dropIndicatorCategoryId = nil  -- 指示器当前显示的分类
local dropCooldownTime = 0  -- 冷却结束时的 GetTime()

-- 辅助函数：使用已跟踪的信息获取光标物品的分类
local function GetCursorItemCategory()
    local info = GudaBag.GetCursorItemInfo()
    addon:Debug("GetCursorItemCat: info=%s", tostring(info ~= nil))
    if not info or not info.itemID or not addon.Modules.CategoryManager then
        addon:Debug("GetCursorItemCat: BAIL - info=%s itemID=%s catMgr=%s", tostring(info ~= nil), tostring(info and info.itemID), tostring(addon.Modules.CategoryManager ~= nil))
        return nil
    end
    local itemName, itemLink, itemQuality, itemLevel, itemCategory, itemSubType, itemStackCount, itemEquipLoc, itemTexture
    if info.link then
        itemName, itemLink, itemQuality, itemLevel, itemCategory, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(info.link)
    end
    addon:Debug("GetCursorItemCat: itemName=%s itemCategory=%s", tostring(itemName), tostring(itemCategory))
    if not itemName then return nil end
    local itemData = {
        link = info.link,
        itemID = info.itemID,
        name = itemName,
        quality = itemQuality or 0,
        -- Turtle WoW 的 GetItemInfo 在第 5 个位置返回物品 CLASS
        -- （第 6 个位置是子类型）。将类名规范化为英文
        -- 以便 CategorizeItem 在 zhCN 上正常工作。
        class = addon.Modules.Utils:NormalizeItemClass(itemCategory) or "",
        subClass = itemSubType or "",
        equipLoc = itemEquipLoc or "",
        stackCount = itemStackCount or 1,
        level = itemLevel or 0,
        texture = itemTexture,
    }
    return addon.Modules.CategoryManager:CategorizeItem(itemData, info.bagID, info.slotID)
end

-- 创建唯一的共享指示器框架（仅一次）
local function GetOrCreateIndicator()
    if categoryDropIndicator then return categoryDropIndicator end

    local f = CreateFrame("Frame", "Guda_CategoryDropIndicator", UIParent)
    f:SetWidth(36)
    f:SetHeight(36)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(500)

    -- 格子背景（与空背包格子相同的贴图，带 GudaBags 那样的绿色色调）
    local slotBg = f:CreateTexture(nil, "BACKGROUND")
    slotBg:SetPoint("TOPLEFT", f, "TOPLEFT", -9, 9)
    slotBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 9, -9)
    slotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    slotBg:SetVertexColor(0.4, 0.8, 0.4, 0.9)
    f.slotBg = slotBg

    -- 加号图标居中
    local plus = f:CreateTexture(nil, "OVERLAY")
    plus:SetWidth(20)
    plus:SetHeight(20)
    plus:SetPoint("CENTER", f, "CENTER", 0, 0)
    plus:SetTexture("Interface\\AddOns\\Guda\\Assets\\plus")
    f.plus = plus

    -- 启用鼠标以支持拖放
    f:EnableMouse(true)

    -- 处理指示器本身的拖放
    local function DoIndicatorDrop()
        if not activeCategoryDropIndicator then return end
        local parentBtn = activeCategoryDropIndicator
        if parentBtn and parentBtn:GetScript("OnReceiveDrag") then
            local savedThis = getfenv(0)["this"]
            getfenv(0)["this"] = parentBtn
            parentBtn:GetScript("OnReceiveDrag")()
            getfenv(0)["this"] = savedThis
        end
    end

    f:SetScript("OnReceiveDrag", DoIndicatorDrop)
    f:SetScript("OnMouseUp", function()
        if CursorHasItem and CursorHasItem() then
            DoIndicatorDrop()
        end
    end)

    -- 悬停时显示提示
    f:SetScript("OnEnter", function()
        if dropIndicatorCategoryId then
            local catDisplay = dropIndicatorCategoryId
            if GudaBag.L and GudaBag.L[catDisplay] then catDisplay = GudaBag.L[catDisplay] end
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText((GudaBag.L and GudaBag.L["Add item to this category"]) or "Add item to this category", 1, 1, 1)
            GameTooltip:AddLine((GudaBag.L and GudaBag.L["Drop here to permanently assign"]) or "Drop here to permanently assign", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(string.format((GudaBag.L and GudaBag.L['this item to "%s"']) or 'this item to "%s"', catDisplay), 0.5, 1, 0.5)
            GameTooltip:Show()
        end
    end)

    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
        -- 延迟隐藏：使用 OnUpdate 检查而不是 C_Timer
        local elapsed = 0
        this:SetScript("OnUpdate", function()
            elapsed = elapsed + arg1
            if elapsed >= 0.05 then
                this:SetScript("OnUpdate", nil)
                -- 检查鼠标是否仍悬停在指示器或父按钮上
                if activeCategoryDropIndicator and MouseIsOver(activeCategoryDropIndicator) then
                    return
                end
                if this:IsMouseOver() then
                    return
                end
                HideCategoryDropIndicator()
            end
        end)
    end)

    f:Hide()
    categoryDropIndicator = f
    return f
end

local function ShowCategoryDropIndicator(button)
    if activeCategoryDropIndicator == button then return end

    -- 拖放冷却期间不显示
    if GetTime() < dropCooldownTime then return end

    HideCategoryDropIndicator()

    local ind = GetOrCreateIndicator()
    local size = button:GetWidth()

    -- 调整尺寸以匹配图标
    ind:SetWidth(size)
    ind:SetHeight(size)

    -- 更新加号图标大小（图标的 60%，最小 16）
    local plusSize = math.max(16, math.floor(size * 0.6))
    ind.plus:SetWidth(plusSize)
    ind.plus:SetHeight(plusSize)

    -- 使用屏幕坐标将指示器定位在悬停按钮下方
    local buttonLeft = button:GetLeft()
    local buttonBottom = button:GetBottom()
    ind:ClearAllPoints()
    if buttonLeft and buttonBottom then
        ind:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", buttonLeft, buttonBottom - 2)
    end

    -- 记录状态
    dropIndicatorCategoryId = button.categoryId or nil
    activeCategoryDropIndicator = button
    ind:Show()
end

HideCategoryDropIndicator = function()
    if categoryDropIndicator then
        categoryDropIndicator:Hide()
        categoryDropIndicator:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end
    activeCategoryDropIndicator = nil
    dropIndicatorCategoryId = nil
end

-- 记录光标正持有的物品（拾取前调用）
function GudaBag.TrackCursorItem(bagID, slotID)
    local link = GetContainerItemLink(bagID, slotID)
    if link then
        local itemID = addon.Modules.Utils:ExtractItemID(link)
        cursorItemInfo = { bagID = bagID, slotID = slotID, itemID = itemID, link = link }
        addon:Debug("TrackCursor: bag=%d slot=%d itemID=%s", bagID, slotID, tostring(itemID))
    else
        cursorItemInfo = nil
        addon:Debug("TrackCursor: no link at bag=%d slot=%d", bagID, slotID)
    end
end

function GudaBag.ClearCursorItem()
    cursorItemInfo = nil
end

function GudaBag.GetCursorItemInfo()
    return cursorItemInfo
end

-- 检查背包或银行是否处于分类视图
local function IsInCategoryView(isBank)
    if not addon.Modules.DB then return false end
    local key = isBank and "bankViewType" or "bagViewType"
    return (addon.Modules.DB:GetSetting(key) or "single") == "category"
end

-- 通过物品链接设置提示，传入 BARE "item:ID:e:e:e" 形式而不是
-- 完整的彩色链接。1.12 原生的 GameTooltip:SetHyperlink 只
-- 接受裸形式；传入完整的 |cff..|Hitem:..|h[Name]|h|r 链接可能会
-- 在重挂钩的 SetHyperlink 链的更深处到达一个只接受裸形式的原生函数
-- （例如当 AtlasLoot / WoWTranslate / SuperCleverRoidMacros 以绕过 Guda
-- 自身剥离钩子的顺序重新挂钩时），并在那个插件中抛出 "unknown link type"。
-- 始终将 Guda 发起的 SetHyperlink 调用路由到该辅助函数。
local function GudaSetTooltipHyperlink(tooltip, link)
    if not link then return end
    local _, _, bare = string.find(link, "|H(item:[^|]+)|h")
    tooltip:SetHyperlink(bare or link)
end

-- 当光标确实为空时自动清除光标跟踪，并通知 BagFrame 拖拽状态
-- 的转换。在 1.12 中 CURSOR_UPDATE 对物品拾取不可靠，
-- 因此我们还在限频的 OnUpdate 中轮询 CursorHasItem() ——
-- 与 Anniversary 版本的做法一致。
local cursorWatcher = CreateFrame("Frame")
cursorWatcher:RegisterEvent("CURSOR_UPDATE")
cursorWatcher:RegisterEvent("ITEM_LOCK_CHANGED")
cursorWatcher._lastCarrying = false
cursorWatcher._pollAccum = 0

local function NotifyDragState()
    if addon.Modules.BagFrame and addon.Modules.BagFrame.SetDragging then
        -- 用户正在拖动背包界面本身时抑制投放目标状态更新 —— 光标上
        -- 什么都没有，而且 Update() 无论如何都会刻意短路。
        if addon.Modules.BagFrame.IsFrameMoving
           and addon.Modules.BagFrame:IsFrameMoving() then
            return
        end
        local carrying = CursorHasItem and CursorHasItem() and true or false
        if carrying ~= cursorWatcher._lastCarrying then
            cursorWatcher._lastCarrying = carrying
            addon.Modules.BagFrame:SetDragging(carrying)
        end
    end
end

cursorWatcher:SetScript("OnEvent", function()
    NotifyDragState()
    if not cursorItemInfo then
        HideCategoryDropIndicator()
        return
    end
    this.pendingCheck = true
end)
cursorWatcher:SetScript("OnUpdate", function()
    -- 限频的光标轮询（约 10Hz）作为 1.12 事件空档的安全网。
    this._pollAccum = (this._pollAccum or 0) + arg1
    if this._pollAccum >= 0.1 then
        this._pollAccum = 0
        NotifyDragState()
    end

    if this.pendingCheck then
        this.pendingCheck = nil
        if cursorItemInfo and (not CursorHasItem or not CursorHasItem()) then
            cursorItemInfo = nil
            HideCategoryDropIndicator()
        end
    end
end)

-- 应用于空分类投放目标占位按钮的脉冲绿色光晕。
-- 由于 vanilla 1.12 没有动画组，使用 OnUpdate 驱动的正弦波。
-- 使用填满整个按钮的纯色贴图，配合加法混合 +
-- alpha 脉冲 —— 无论用户的 iconSize 设置如何，外观都一样。
local function EnsureDropTargetGlow(button)
    if not button.dropGlow then
        local g = button:CreateTexture(nil, "OVERLAY")
        g:SetTexture(0.2, 1.0, 0.2, 1)   -- 纯绿色；alpha 每帧调整
        g:SetBlendMode("ADD")
        g:SetAllPoints(button)            -- 覆盖整个按钮，随 iconSize 缩放
        button.dropGlow = g

        local driver = CreateFrame("Frame", nil, button)
        driver._t = 0
        driver:SetScript("OnUpdate", function()
            this._t = this._t + arg1
            -- 周期约 1.2 秒 => 2π/1.2 ≈ 5.24
            local phase = (math.sin(this._t * 5.24) + 1) * 0.5
            if this:GetParent().dropGlow then
                -- 细微脉冲：alpha 在 0.15 → 0.45 之间，加法混合。
                this:GetParent().dropGlow:SetAlpha(0.15 + phase * 0.30)
            end
        end)
        button.dropGlowDriver = driver
    end
    -- 如果按钮自上次显示以来被调整过大小，防御性地重新锚定。
    button.dropGlow:ClearAllPoints()
    button.dropGlow:SetAllPoints(button)
    button.dropGlow:Show()
    button.dropGlowDriver:Show()
end

local function StopDropTargetGlow(button)
    if button.dropGlow then button.dropGlow:Hide() end
    if button.dropGlowDriver then button.dropGlowDriver:Hide() end
    button.isDropTarget = false
    button.dropTargetCategoryId = nil
end

-- 使用 Utils 模块的共享提示（按需获取，确保 Utils 已加载）

-- 辅助函数：检查物品是否为任务物品
-- 使用集中的 ItemDetection 模块
local function IsQuestItem(bagID, slotID, isBank, itemData)
    -- 优先使用 ItemDetection
    if addon and addon.Modules and addon.Modules.ItemDetection then
        local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
        return props.isQuestItem, props.isQuestStarter
    end
    -- 回退到 Utils
    if addon and addon.Modules and addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
        return addon.Modules.Utils:IsQuestItem(bagID, slotID, nil, false, isBank)
    end
    return false, false
end

--=====================================================
-- 内阴影（内嵌的品质发光，受 GudaBags 启发）
-- 沿四边分布的 4 个渐变贴图，按物品品质着色
--=====================================================
local INNER_SHADOW_SIZE = 3
local INNER_SHADOW_ALPHA = 0.5
local INNER_SHADOW_INSET = 2  -- 从图标边缘内缩的像素，使发光保持在格子内

-- 在按钮上创建 4 边内阴影贴图，锚定到图标贴图上
local function CreateInnerShadow(button, anchorTo)
    local shadow = {}
    local inset = INNER_SHADOW_INSET
    -- 顶部边缘
    shadow.top = button:CreateTexture(nil, "ARTWORK", nil, 1)
    shadow.top:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", inset, -inset)
    shadow.top:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", -inset, -inset)
    shadow.top:SetHeight(INNER_SHADOW_SIZE)
    shadow.top:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shadow.top:Hide()
    -- 底部边缘
    shadow.bottom = button:CreateTexture(nil, "ARTWORK", nil, 1)
    shadow.bottom:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", inset, inset)
    shadow.bottom:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", -inset, inset)
    shadow.bottom:SetHeight(INNER_SHADOW_SIZE)
    shadow.bottom:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shadow.bottom:Hide()
    -- 左侧边缘
    shadow.left = button:CreateTexture(nil, "ARTWORK", nil, 1)
    shadow.left:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", inset, -inset)
    shadow.left:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", inset, inset)
    shadow.left:SetWidth(INNER_SHADOW_SIZE)
    shadow.left:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shadow.left:Hide()
    -- 右侧边缘
    shadow.right = button:CreateTexture(nil, "ARTWORK", nil, 1)
    shadow.right:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", -inset, -inset)
    shadow.right:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", -inset, inset)
    shadow.right:SetWidth(INNER_SHADOW_SIZE)
    shadow.right:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shadow.right:Hide()
    return shadow
end

-- 用给定的品质颜色显示内阴影
local function ShowInnerShadow(shadow, r, g, b)
    if not shadow then return end
    -- square/pfUI 风格下跳过内部发光
    if addon.Modules and addon.Modules.Theme and addon.Modules.Theme:GetSlotStyle() == "square" then
        shadow.top:Hide()
        shadow.bottom:Hide()
        shadow.left:Hide()
        shadow.right:Hide()
        return
    end
    local a = INNER_SHADOW_ALPHA
    shadow.top:SetGradientAlpha("VERTICAL", r, g, b, 0, r, g, b, a)
    shadow.top:Show()
    shadow.bottom:SetGradientAlpha("VERTICAL", r, g, b, a, r, g, b, 0)
    shadow.bottom:Show()
    shadow.left:SetGradientAlpha("HORIZONTAL", r, g, b, a, r, g, b, 0)
    shadow.left:Show()
    shadow.right:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, a)
    shadow.right:Show()
end

-- 隐藏内阴影
local function HideInnerShadow(shadow)
    if not shadow then return end
    shadow.top:Hide()
    shadow.bottom:Hide()
    shadow.left:Hide()
    shadow.right:Hide()
end

--=====================================================
-- 品质/任务边框 —— 覆盖在图标贴图上方的圆角底板边框叠加层，
-- 用于形成干净的彩色框
--=====================================================
local QUALITY_BORDER_SIZE = 2      -- 边框厚度
local QUALITY_BORDER_PADDING = 1   -- 从按钮边缘内缩的距离

local qualityBorderBackdrop = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local qualityBorderBackdropSquare = {
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

-- 获取或创建按钮的品质边框框架
local function GetQualityBorderFrame(button)
    local qStyle = "rounded"
    if addon.Modules and addon.Modules.Theme then
        qStyle = addon.Modules.Theme:GetQualityBorderStyle()
    end

    if button._qualityBorder then
        -- 如果样式改变则更新底板
        if button._qualityBorderStyle ~= qStyle then
            button._qualityBorderStyle = qStyle
            local pad = QUALITY_BORDER_PADDING
            button._qualityBorder:ClearAllPoints()
            if qStyle == "square" then
                button._qualityBorder:SetBackdrop(qualityBorderBackdropSquare)
                button._qualityBorder:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
                button._qualityBorder:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
            else
                button._qualityBorder:SetBackdrop(qualityBorderBackdrop)
                button._qualityBorder:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
                button._qualityBorder:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
            end
        end
        return button._qualityBorder
    end

    local frame = CreateFrame("Frame", nil, button)
    frame:SetFrameLevel(button:GetFrameLevel() + 3)
    local pad = QUALITY_BORDER_PADDING
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
    frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
    if qStyle == "square" then
        frame:SetBackdrop(qualityBorderBackdropSquare)
    else
        frame:SetBackdrop(qualityBorderBackdrop)
    end
    frame:Hide()
    button._qualityBorder = frame
    button._qualityBorderStyle = qStyle
    return frame
end

-- 用颜色显示品质边框
local function TintSlotBorder(button, r, g, b)
    local frame = GetQualityBorderFrame(button)
    frame:SetBackdropBorderColor(r, g, b, 1)
    frame:Show()
    button._borderTinted = true
end

-- 隐藏品质边框
local function ResetSlotBorder(button)
    if not button._borderTinted then return end
    if button._qualityBorder then
        button._qualityBorder:Hide()
    end
    button._borderTinted = false
end

--=====================================================
-- 垃圾物品图标池（受 Baganator 启发的内存优化）
-- 使用框架池避免为每个按钮创建新框架
--=====================================================
local junkIconPool = {}

-- 从池中获取垃圾图标，或创建新的
local function AcquireJunkIcon()
    local icon = table.remove(junkIconPool)
    if not icon then
        icon = CreateFrame("Frame", nil, UIParent)
        icon:SetFrameStrata("HIGH")
        icon:SetWidth(14)
        icon:SetHeight(14)

        local texture = icon:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(icon)
        texture:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")
        texture:SetTexCoord(0, 1, 0, 1)
        icon.texture = texture
    end
    return icon
end

-- 将垃圾图标释放回池中
local function ReleaseJunkIcon(icon)
    if icon then
        icon:Hide()
        icon:ClearAllPoints()
        table.insert(junkIconPool, icon)
    end
end

-- 更新垃圾图标可见性和位置（使用池化）
local function UpdateJunkIcon(button, isJunk, iconSize)
    if isJunk then
        -- 如需则从池中获取
        if not button.junkIcon then
            button.junkIcon = AcquireJunkIcon()
        end
        -- 根据按钮大小缩放图标尺寸
        local junkIconSize = math.max(10, math.min(14, iconSize * 0.30))
        button.junkIcon:SetWidth(junkIconSize)
        button.junkIcon:SetHeight(junkIconSize)
        button.junkIcon:ClearAllPoints()
        button.junkIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        button.junkIcon:SetAlpha(1.0)
        button.junkIcon:Show()
    else
        -- 不需要时释放回池中
        if button.junkIcon then
            ReleaseJunkIcon(button.junkIcon)
            button.junkIcon = nil
        end
    end
end

-- 隐藏垃圾图标（释放回池）
local function HideJunkIcon(button)
    if button.junkIcon then
        ReleaseJunkIcon(button.junkIcon)
        button.junkIcon = nil
    end
end

--=====================================================
-- 锁图标池（与垃圾图标池相同的模式）
--=====================================================
local lockIconPool = {}

local function AcquireLockIcon()
	local icon = table.remove(lockIconPool)
	if not icon then
		icon = CreateFrame("Frame", nil, UIParent)
		icon:SetWidth(13)
		icon:SetHeight(13)

		-- 阴影（在后层）
		local shadow = icon:CreateTexture(nil, "BACKGROUND")
		shadow:SetWidth(13)
		shadow:SetHeight(13)
		shadow:SetPoint("CENTER", icon, "CENTER", 1, -1)
		shadow:SetTexture("Interface\\AddOns\\Guda\\Assets\\lock_glow")
		shadow:SetVertexColor(0, 0, 0, 1)
		icon.shadow = shadow

		-- 图标（在前层）
		local texture = icon:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints(icon)
		texture:SetTexture("Interface\\AddOns\\Guda\\Assets\\lock_glow")
		icon.texture = texture
	end
	return icon
end

local function ReleaseLockIcon(icon)
	if icon then
		icon:Hide()
		icon:ClearAllPoints()
		icon:SetParent(UIParent)
		table.insert(lockIconPool, icon)
	end
end

local function UpdateLockIcon(button, iconSize)
	local DB = addon.Modules.DB
	if not DB then return end

    local isLocked = false
    -- 优先使用缓存的链接，但回退到实时查询。加载画面
    -- （例如炉石回城）之后，itemData.link 在首个渲染帧上仍可能为 nil；
    -- GetContainerItemLink 是同步的，因此这里的实时读取
    -- 可保证一旦背包数据就绪，锁状态立即被解析。
    if button.hasItem and button.bagID and button.slotID then
        local link = (button.itemData and button.itemData.link) or GetContainerItemLink(button.bagID, button.slotID)
        local Utils = addon.Modules.Utils
        local itemID = Utils and Utils.ExtractItemID and Utils:ExtractItemID(link)
        if itemID and DB:IsItemProtected(itemID) then
            isLocked = true
        end
    end

	if isLocked then
		if not button.lockIcon then
			button.lockIcon = AcquireLockIcon()
		end
		button.lockIcon:SetParent(button)
		local lockSize = math.max(8, math.min(12, iconSize * 0.35 - 3))
		button.lockIcon:SetWidth(lockSize)
		button.lockIcon:SetHeight(lockSize)
		if button.lockIcon.shadow then
			button.lockIcon.shadow:SetWidth(lockSize)
			button.lockIcon.shadow:SetHeight(lockSize)
		end
		button.lockIcon:ClearAllPoints()
		button.lockIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -3)
		button.lockIcon:SetFrameLevel(button:GetFrameLevel() + 5)
		button.lockIcon:Show()
	else
		if button.lockIcon then
			ReleaseLockIcon(button.lockIcon)
			button.lockIcon = nil
		end
	end
end

local function HideLockIcon(button)
	if button.lockIcon then
		ReleaseLockIcon(button.lockIcon)
		button.lockIcon = nil
	end
end

--=====================================================
-- 图钉图标池（表示格子已固定 / 受排序保护）
--=====================================================
local pinIconPool = {}

local function AcquirePinIcon()
	local icon = table.remove(pinIconPool)
	if not icon then
		icon = CreateFrame("Frame", nil, UIParent)
		icon:SetWidth(13)
		icon:SetHeight(13)

		-- 阴影（在后层）
		local shadow = icon:CreateTexture(nil, "BACKGROUND")
		shadow:SetWidth(15)
		shadow:SetHeight(15)
		shadow:SetPoint("CENTER", icon, "CENTER", 0, 0)
		shadow:SetTexture("Interface\\AddOns\\Guda\\Assets\\pin")
		shadow:SetVertexColor(0, 0, 0, 0.9)
		icon.shadow = shadow

		-- 图标（在前层）
		local texture = icon:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints(icon)
		texture:SetTexture("Interface\\AddOns\\Guda\\Assets\\pin")
		icon.texture = texture
	end
	return icon
end

local function ReleasePinIcon(icon)
	if icon then
		icon:Hide()
		icon:ClearAllPoints()
		icon:SetParent(UIParent)
		table.insert(pinIconPool, icon)
	end
end

local function UpdatePinIcon(button, iconSize)
	local DB = addon.Modules.DB
	if not DB then return end

	local isPinned = false
	if button.bagID and button.slotID and not button.otherChar and not button.isReadOnly then
		isPinned = DB:IsPinnedSlot(button.bagID, button.slotID)
	end

	if isPinned then
		if not button.pinIcon then
			button.pinIcon = AcquirePinIcon()
		end
		button.pinIcon:SetParent(button)
		local pinSize = math.max(10, math.min(14, iconSize * 0.35))
		button.pinIcon:SetWidth(pinSize)
		button.pinIcon:SetHeight(pinSize)
		if button.pinIcon.shadow then
			button.pinIcon.shadow:SetWidth(pinSize + 2)
			button.pinIcon.shadow:SetHeight(pinSize + 2)
		end
		button.pinIcon:ClearAllPoints()
		button.pinIcon:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
		button.pinIcon:SetFrameLevel(button:GetFrameLevel() + 5)
		button.pinIcon:Show()
	else
		if button.pinIcon then
			ReleasePinIcon(button.pinIcon)
			button.pinIcon = nil
		end
	end
end

local function HidePinIcon(button)
	if button.pinIcon then
		ReleasePinIcon(button.pinIcon)
		button.pinIcon = nil
	end
end

-- 挂钩 UseContainerItem，防止出售/分解受保护物品
local OriginalUseContainerItem = UseContainerItem
UseContainerItem = function(bag, slot, ...)
	local DB = addon.Modules.DB
	if DB then
		local link = GetContainerItemLink(bag, slot)
		if link then
			local Utils = addon.Modules.Utils
			local itemID = Utils and Utils.ExtractItemID and Utils:ExtractItemID(link)
			if itemID and DB:IsItemProtected(itemID) then
				-- 阻止在商人处出售
				if MerchantFrame and MerchantFrame:IsVisible() then
					addon:Print(format(GudaBag.L["Cannot sell %s — item is protected"], link))
					return
				end
				-- 阻止分解/研磨/探测（对物品施法）
				if SpellIsTargeting and SpellIsTargeting() then
					SpellStopTargeting()
					addon:Print(format(GudaBag.L["Cannot disenchant %s — item is protected"], link))
					return
				end
			end
		end
	end
	return OriginalUseContainerItem(bag, slot)
end

-- 记录光标物品用于删除保护（GetCursorInfo 在 1.12.1 中不存在）
local cursorProtectedLink = nil

	local OriginalPickupContainerItem = PickupContainerItem
PickupContainerItem = function(bag, slot, ...)
	local DB = addon.Modules.DB
	if DB then
		local link = GetContainerItemLink(bag, slot)
		if link then
			local Utils = addon.Modules.Utils
			local itemID = Utils and Utils.ExtractItemID and Utils:ExtractItemID(link)
			if itemID and DB:IsItemProtected(itemID) then
				cursorProtectedLink = link
			else
				cursorProtectedLink = nil
			end
		else
			cursorProtectedLink = nil
		end
	end
	return OriginalPickupContainerItem(bag, slot)
end

-- 追踪从已装备栏位拾取的物品（角色纸娃娃）。装备物品不经过 Guda 的
-- 物品按钮 OnDragStart/OnClick，因此 TrackCursorItem 不会被调用；
-- 这里钩住 PickupInventoryItem，使分类投放目标能识别装备物品并归类。
local function TrackInventoryItem(invSlot)
    local link = GetInventoryItemLink("player", invSlot)
    if link and addon and addon.Modules and addon.Modules.Utils then
        local itemID = addon.Modules.Utils:ExtractItemID(link)
        cursorItemInfo = { bagID = invSlot, slotID = nil, itemID = itemID, link = link, fromInventory = true }
        addon:Debug("TrackInventory: invSlot=%d itemID=%s", invSlot, tostring(itemID))
    else
        cursorItemInfo = nil
        addon:Debug("TrackInventory: no link at invSlot=%d", invSlot)
    end
end

local OriginalPickupInventoryItem = PickupInventoryItem
PickupInventoryItem = function(invSlot)
    -- 在拾取前追踪装备物品（拾取后该栏位链接即消失）
    if addon and addon.Modules and addon.Modules.Utils and addon.Modules.Utils.ExtractItemID then
        TrackInventoryItem(invSlot)
    end
    return OriginalPickupInventoryItem(invSlot)
end

-- 挂钩删除确认弹窗
local function HookDeletePopup(dialogName)
	if not StaticPopupDialogs or not StaticPopupDialogs[dialogName] then return end
	local originalOnShow = StaticPopupDialogs[dialogName].OnShow
	StaticPopupDialogs[dialogName].OnShow = function()
		if cursorProtectedLink then
			addon:Print(format(GudaBag.L["Cannot delete %s — item is protected"], cursorProtectedLink))
			ClearCursor()
			cursorProtectedLink = nil
			this:Hide()
			return
		end
		if originalOnShow then
			return originalOnShow()
		end
	end
end
HookDeletePopup("DELETE_ITEM")
HookDeletePopup("DELETE_GOOD_ITEM")

--=====================================================
-- 不可用物品检测（受 pfUI 启发的实现）
-- 对角色无法使用（职业/种族/技能限制）的物品
-- 添加红色色调叠加层，排除纯粹因耐久度
-- 破损而不可用的情况。
--=====================================================
local function GetUnusableColor()
    -- 使用 pfUI 的配置命名空间 pfUI.env.C（pfUI 环境变量 C 可能与其他
    -- 插件的全局 C 冲突——全局 C 可能是函数值，索引会报错）。
    local C = pfUI and pfUI.env and pfUI.env.C or nil
    if C and C.appearance and C.appearance.bags and C.appearance.bags.unusable_color then
        local cr, cg, cb, ca = strsplit(",", C.appearance.bags.unusable_color)
        local r = tonumber(cr) or 0.9
        local g = tonumber(cg) or 0.2
        local b = tonumber(cb) or 0.2
        local a = tonumber(ca) or 1.0
        return r, g, b, a
    end
    -- 然后是暴雪的 RED_FONT_COLOR（如果存在）
    if RED_FONT_COLOR then
        return RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, 1.0
    end
    -- 默认值，类似 pfUI
    return 0.9, 0.2, 0.2, 1.0
end

-- 注意：IsItemUnusable 检测现在由 ItemDetection:IsUnusable() 处理，
-- 它使用缓存的提示扫描，避免对每个物品重复扫描。
-- 旧的 IsItemUnusable、IsRedColor 和 durabilityPattern 已被移除，
-- 以防止冗余的提示扫描 —— 所有检测现在集中处理。

-- 对不可用物品应用/移除物品贴图上的红色色调。
-- 当 cacheOnly 为 true 时，在冷缓存上跳过提示扫描并返回
-- 未着色 —— BagFrame 中的延迟处理稍后会补上色调。
local function ItemButton_UpdateUsableTint(self, cacheOnly)
-- 先清除任何已有的色调/叠加层
	if self.unusableOverlay and self.unusableOverlay.Hide then
		self.unusableOverlay:Hide()
	end
	if SetItemButtonTextureVertexColor then
		SetItemButtonTextureVertexColor(self, 1.0, 1.0, 1.0)
	end

	-- 检查功能是否启用
	local markUnusable = true
	if Guda and Guda.Modules and Guda.Modules.DB then
		markUnusable = Guda.Modules.DB:GetSetting("markUnusableItems")
		if markUnusable == nil then
			markUnusable = true
		end
	end

	-- 如果功能被禁用，清除后直接返回
	if not markUnusable then
		return
	end

	-- 仅评估实时（玩家）物品；来自其他角色的 DB 缓存物品无法扫描
	if not self or not self.hasItem or not self.bagID or not self.slotID or self.isReadOnly or self.otherChar then
		return
	end

	-- 使用 ItemDetection 模块的缓存检测（避免重复的提示扫描）
	local unusable = false
	if self.itemData and addon.Modules.ItemDetection then
		if cacheOnly then
			local cached = addon.Modules.ItemDetection:IsUnusableCached(self.itemData)
			if cached == nil then
				-- 未知；保持未着色。延迟处理稍后会补上。
				return
			end
			unusable = cached
		else
			unusable = addon.Modules.ItemDetection:IsUnusable(self.itemData, self.bagID, self.slotID)
		end
	end

	-- 确保叠加层存在（在 OnLoad 中创建，但做防御性处理）
	if not self.unusableOverlay then
		local icon = getglobal(self:GetName().."IconTexture") or getglobal(self:GetName().."Icon") or self.icon or self.Icon
		local overlay = (icon and icon:GetParent() or self):CreateTexture(nil, "OVERLAY")
		overlay:SetAllPoints(icon or self)
		overlay:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		overlay:Hide()
		self.unusableOverlay = overlay
	end

	if unusable then
		local r, g, b, a = GetUnusableColor()
		-- 略微降低 alpha，避免过度压暗图标
		local alpha = (a or 1.0) * 0.45
		self.unusableOverlay:SetVertexColor(r or 0.9, g or 0.2, b or 0.2, alpha)
		self.unusableOverlay:Show()
	else
		self.unusableOverlay:Hide()
	end
end


-- 检查按钮是否可复用
-- 按钮在以下任一情况时可复用：
-- 1. 隐藏（未显示）
-- 2. 在更新周期中被标记为未使用（inUse == false）
local function IsButtonAvailable(button)
    if not button:IsShown() then
        return true
    end
    -- 在更新周期中，按钮在显示前被标记为 inUse = false，
    -- 分配时标记为 inUse = true。这允许在不先隐藏的情况下复用。
    if button.inUse == false then
        return true
    end
    return false
end

-- 从池中创建或获取按钮
function GudaBag.GetItemButton(parent)
    local reuseCandidate = nil  -- 来自不同父级、可重新指定父级的按钮

    -- 尝试复用池中的现有按钮
    for _, button in pairs(buttonPool) do
        -- 跳过背包格子按钮
        if not button.isBagSlot and IsButtonAvailable(button) then
            if button:GetParent() == parent then
                -- 同一父级 —— 最佳情况，立即复用
                -- 标记为使用中，防止双重分配
                button.inUse = true
                -- 与父级重新注册（itemButtons 哈希可能已被清除）
                if GudaBag.RegisterItemButton then
                    GudaBag.RegisterItemButton(parent, button)
                end
                return button
            elseif not reuseCandidate then
                -- 不同父级但可用 —— 保存为候选以重新指定父级
                reuseCandidate = button
            end
        end
    end

    -- 如果找到来自不同父级的可用按钮，重新指定其父级
    if reuseCandidate then
        -- 标记为使用中
        reuseCandidate.inUse = true

        -- 从旧父级注销
        local oldParent = reuseCandidate:GetParent()
        if oldParent and oldParent.itemButtons then
            oldParent.itemButtons[reuseCandidate] = nil
        end

        -- 重新指定到新父级
        reuseCandidate:SetParent(parent)

        -- 在新父级注册
        if GudaBag.RegisterItemButton then
            GudaBag.RegisterItemButton(parent, reuseCandidate)
        end

        return reuseCandidate
    end

    -- 仅在低于池上限时创建新按钮
    if nextButtonID <= BUTTON_POOL_MAX then
        local button = CreateFrame("Button", "Guda_ItemButton" .. nextButtonID, parent, "Guda_ItemButtonTemplate")
        buttonPool[nextButtonID] = button
        nextButtonID = nextButtonID + 1
        button.inUse = true

        -- 在父级注册按钮用于跟踪（避免 GetChildren() 分配）
        if GudaBag.RegisterItemButton then
            GudaBag.RegisterItemButton(parent, button)
        end

        return button
    end

    -- 池已达上限且未找到可用按钮 —— 正常情况不应发生，
    -- 但作为后备，强制复用找到的第一个非背包格子按钮
    for _, button in pairs(buttonPool) do
        if not button.isBagSlot then
            -- 先隐藏它（以防它正显示）
            button:Hide()
            button.inUse = true

            -- 从旧父级注销
            local oldParent = button:GetParent()
            if oldParent and oldParent.itemButtons then
                oldParent.itemButtons[button] = nil
            end

            -- 重新指定父级
            button:SetParent(parent)

            -- 在新父级注册
            if GudaBag.RegisterItemButton then
                GudaBag.RegisterItemButton(parent, button)
            end

            return button
        end
    end

    -- 最终后备（不应到达此处）—— 再创建一个按钮
    local button = CreateFrame("Button", "Guda_ItemButton" .. nextButtonID, parent, "Guda_ItemButtonTemplate")
    buttonPool[nextButtonID] = button
    nextButtonID = nextButtonID + 1
    button.inUse = true
    if GudaBag.RegisterItemButton then
        GudaBag.RegisterItemButton(parent, button)
    end
    return button
end

-- 根据物品类型（起始任务 vs 常规任务物品）更新任务图标
local function ItemButton_UpdateQuestIcon(self, isQuest, isQuestStarter)
	if not self.questIcon then return end

	if isQuest then
	-- 根据任务类型设置合适的贴图
		if isQuestStarter then
		-- 任务起始：感叹号
			local texture = self.questIcon:GetRegions()
			if texture and texture.SetTexture then
				texture:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
				texture:SetTexCoord(0, 1, 0, 1)
			end
		else
		-- 常规任务物品：问号
			local texture = self.questIcon:GetRegions()
			if texture and texture.SetTexture then
				texture:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
				texture:SetTexCoord(0, 1, 0, 1)
			end
		end
		self.questIcon:Show()
	else
		self.questIcon:Hide()
	end
end

-- 拾取标记边框（红色呼吸）脉动管理器：集中驱动所有当前显示的边框贴图 alpha。
local lootBorderFrames = {}
local lootBorderTicker = CreateFrame("Frame")
lootBorderTicker:Hide()
lootBorderTicker:SetScript("OnUpdate", function()
    -- alpha 在 0.4 ~ 1.0 之间脉动（周期约 1.5 秒）
    local a = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(GetTime() * 4))
    for btn, border in pairs(lootBorderFrames) do
        if border and border:IsShown() then
            border:SetAlpha(a)
        else
            lootBorderFrames[btn] = nil
        end
    end
    if not next(lootBorderFrames) then lootBorderTicker:Hide() end
end)
local function RegisterLootBorder(self, border)
    lootBorderFrames[self] = border
    lootBorderTicker:Show()
end
local function UnregisterLootBorder(self)
    if lootBorderFrames[self] then
        lootBorderFrames[self] = nil
        if not next(lootBorderFrames) then lootBorderTicker:Hide() end
    end
end

-- 拾取标记：在最近拾取窗口内拾取到的物品上显示标记。
-- 样式由设置 lootMarkerMode 决定：0=关闭，1=星星图标(xingxing.blp)，2=红色呼吸边框。
-- 标记的时间窗口跟随分类里 "最近拾取"(isRecentlyLooted) 规则的值（300/600/1200）。
function GudaBag.ItemButton_UpdateLootMarker(self, Utils)
    local marker = getglobal(self:GetName() .. "_LootMarker")
    local border = getglobal(self:GetName() .. "_LootMarkerBorder")
    if not marker then return end

    -- 默认隐藏；后续按条件显示
    marker:Hide()
    if border then border:Hide() end
    UnregisterLootBorder(self)

    -- 仅对当前角色真实拥有的物品生效（排除其他角色/只读格子）
    if not self.hasItem or self.otherChar or self.isReadOnly then return end
    if not self.bagID or not self.slotID then return end

    -- 读取模式（0/1/2，兼容旧布尔设置）
    local mode = 0
    if Utils and Utils.SafeCall then
        mode = Utils:SafeCall("DB", "GetSetting", "lootMarkerMode")
    elseif addon and addon.Modules and addon.Modules.DB then
        mode = addon.Modules.DB:GetSetting("lootMarkerMode")
    end
    if mode == nil then
        -- 旧版迁移
        local show = false
        if addon and addon.Modules and addon.Modules.DB then
            show = addon.Modules.DB:GetSetting("showLootMarker") and true or false
        end
        mode = 0
        if show then
            local pulse = addon.Modules.DB:GetSetting("lootMarkerPulse") and true or false
            mode = pulse and 2 or 1
        end
    end
    if mode == 0 then return end

    -- 取物品链接（优先 itemData.link，否则实时读取）
    local link = (self.itemData and self.itemData.link)
        or (GetContainerItemLink and GetContainerItemLink(self.bagID, self.slotID))
    if not link then return end

    local RecentLoot = addon and addon.Modules and addon.Modules.RecentLoot
    if not RecentLoot then return end

    local window = RecentLoot:GetMarkerWindow()
    if not RecentLoot:IsRecentlyLooted(link, window) then return end

    -- 样式分支：呼吸边框(2) 或 星星图标(1)
    if mode == 2 and border then
        border:SetVertexColor(1, 0.2, 0.2)
        border:SetAlpha(1)
        border:Show()
        RegisterLootBorder(self, border)
    else
        marker:SetVertexColor(1, 1, 1)
        marker:Show()
    end
end

-- OnLoad 处理器
function GudaBag.ItemButton_OnLoad(self)
    self.hasItem = false
    self.bagID = nil
    self.slotID = nil
    self.itemData = nil
    self.isBank = false
    self.otherChar = nil

    -- 在方形格子样式中，隐藏所有圆角的暴雪模板贴图
    local slotStyle = "rounded"
    if addon.Modules and addon.Modules.Theme then
        slotStyle = addon.Modules.Theme:GetSlotStyle()
    end
    if slotStyle == "square" then
        -- 隐藏 ContainerFrameItemButtonTemplate 的圆角 NormalTexture
        self:SetNormalTexture("")
        local normalTex = getglobal(self:GetName() .. "NormalTexture")
        if normalTex then
            normalTex:SetTexture(nil)
            normalTex:Hide()
        end
        -- 隐藏 QualityRing（圆角 UI-EmptySlot）
        local qRing = getglobal(self:GetName() .. "_QualityRing")
        if qRing then
            qRing:Hide()
        end
        -- 将 EmptySlotBg 更新为方形样式
        local emptySlotBg = getglobal(self:GetName() .. "_EmptySlotBg")
        if emptySlotBg then
            emptySlotBg:SetTexture("Interface\\Buttons\\WHITE8x8")
            emptySlotBg:SetVertexColor(0.05, 0.05, 0.05, 1)
            emptySlotBg:ClearAllPoints()
            emptySlotBg:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            emptySlotBg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- 为品质颜色发光创建内阴影（锚定到图标贴图）
    if not self.innerShadow then
        local iconTex = getglobal(self:GetName() .. "IconTexture")
        if iconTex then
            self.innerShadow = CreateInnerShadow(self, iconTex)
        end
    end

    -- 创建任务图标叠加层（角落的感叹号）
    if not self.questIcon then
        local iconFrame = CreateFrame("Frame", nil, self)
        iconFrame:SetFrameLevel(self:GetFrameLevel() + 7)  -- 在任务边框之上
        iconFrame:SetWidth(16)
        iconFrame:SetHeight(16)

        local texture = iconFrame:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(iconFrame)
        texture:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        texture:SetTexCoord(0, 1, 0, 1)

        iconFrame:Hide()
        self.questIcon = iconFrame
    end

    -- 注意：垃圾图标在 UpdateJunkIcon 中按需从池中获取，不会预先创建

    -- 确保物品按钮位于其容器底板之上，并启用鼠标
    local parent = self:GetParent()
    if parent and parent.GetFrameLevel then
        -- 将按钮放在父级底板/鼠标层之上，以可靠接收拖放
        local parentLevel = parent:GetFrameLevel()
        if parentLevel and self:GetFrameLevel() <= parentLevel + 1 then
            self:SetFrameLevel(parentLevel + 2)
        end
    end

    -- 启用鼠标并注册拖拽/投放（对 Classic/Vanilla WoW 至关重要）
    if self.EnableMouse then
        self:EnableMouse(true)
    end
    if self.RegisterForDrag then
        self:RegisterForDrag("LeftButton")
    end
    if self.RegisterForClicks then
        self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    -- 按钮隐藏时隐藏垃圾和锁图标（因为它们父级为 UIParent）
    self:SetScript("OnHide", function()
        HideJunkIcon(this)
        HideLockIcon(this)
        HidePinIcon(this)
    end)

    -- 拖拽开始时记录光标物品，用于分类拖放
    self:SetScript("OnDragStart", function()
        if this.hasItem and this.bagID and this.slotID and not this.otherChar and not this.isReadOnly then
            GudaBag.TrackCursorItem(this.bagID, this.slotID)
            PickupContainerItem(this.bagID, this.slotID)
        end
    end)

    self:SetScript("OnClick", function()
        -- 光标持有物品时点击投放目标占位按钮：
        -- 路由到与 OnReceiveDrag 相同的处理器（分配到分类）。
        -- 光标上没有物品时点击不执行任何操作。
        if this.isDropTarget then
            if CursorHasItem and CursorHasItem() then
                local handler = this:GetScript("OnReceiveDrag")
                if handler then handler() end
            end
            return
        end

        -- 使用 Ctrl+右键 锁定/解锁物品
        if IsControlKeyDown() and arg1 == "RightButton" and this.hasItem and not this.otherChar and not this.isReadOnly then
            local link = GetContainerItemLink(this.bagID, this.slotID)
            if link and addon and addon.Modules and addon.Modules.Utils and addon.Modules.DB then
                local itemID = addon.Modules.Utils:ExtractItemID(link)
                if itemID then
                    -- 如果物品在某个装备方案中，切换方案保护例外
                    if addon.Modules.DB:GetSetting("autoLockSetItems") then
                        local EquipSets = addon.Modules.EquipmentSets
                        if EquipSets and EquipSets.IsInSet and EquipSets:IsInSet(itemID) then
                            local isNowExcepted = addon.Modules.DB:ToggleSetProtectionException(itemID)
                            if isNowExcepted then
                                addon:Print(format(GudaBag.L["%s set protection removed"], link))
                            else
                                addon:Print(format(GudaBag.L["%s set protection restored"], link))
                            end
                            -- 刷新背包/银行界面的锁定/保护标记（无需全量重建）
                            if addon.Modules.BagFrame and addon.Modules.BagFrame.RefreshItemMarkers then
                                addon.Modules.BagFrame:RefreshItemMarkers()
                            end
                            if addon.Modules.BankFrame and addon.Modules.BankFrame.RefreshItemMarkers then
                                addon.Modules.BankFrame:RefreshItemMarkers()
                            end
                            return
                        end
                    end
                    local isNowLocked = addon.Modules.DB:ToggleItemLock(itemID)
                    if isNowLocked then
                        addon:Print(format(GudaBag.L["%s locked"], link))
                    else
                        addon:Print(format(GudaBag.L["%s unlocked"], link))
                    end
                    -- 刷新背包/银行界面的锁定标记（无需全量重建）
                    if addon.Modules.BagFrame and addon.Modules.BagFrame.RefreshItemMarkers then
                        addon.Modules.BagFrame:RefreshItemMarkers()
                    end
                    if addon.Modules.BankFrame and addon.Modules.BankFrame.RefreshItemMarkers then
                        addon.Modules.BankFrame:RefreshItemMarkers()
                    end
                end
            end
            return
        end

        -- 使用 Alt+右键 固定/取消固定格子
        if IsAltKeyDown() and arg1 == "RightButton" and not this.otherChar and not this.isReadOnly then
            if this.bagID ~= nil and this.slotID and addon.Modules.DB then
                local isNowPinned = addon.Modules.DB:TogglePinnedSlot(this.bagID, this.slotID)
                local itemName = ""
                if this.hasItem and this.itemData and this.itemData.link then
                    itemName = " " .. this.itemData.link
                end
                if isNowPinned then
                    addon:Print(format(GudaBag.L["Slot pinned %s (skipped during sort)"], itemName))
                else
                    addon:Print(format(GudaBag.L["Slot unpinned %s"], itemName))
                end
                -- 刷新以显示/隐藏图钉图标（无需全量重建）
                if addon.Modules.BagFrame and addon.Modules.BagFrame.RefreshItemMarkers then
                    addon.Modules.BagFrame:RefreshItemMarkers()
                end
                if addon.Modules.BankFrame and addon.Modules.BankFrame.RefreshItemMarkers then
                    addon.Modules.BankFrame:RefreshItemMarkers()
                end
            end
            return
        end

        if IsAltKeyDown() and arg1 == "LeftButton" and this.hasItem and not this.otherChar and not this.isReadOnly then
            local link = GetContainerItemLink(this.bagID, this.slotID)
            if link and addon and addon.Modules and addon.Modules.Utils then
                local itemID = addon.Modules.Utils:ExtractItemID(link)
                if itemID then
                    local isQuest = IsQuestItem(this.bagID, this.slotID, this.isBank, this.itemData)
                    local isUnique = addon.Modules.Utils:IsUniqueItem(this.bagID, this.slotID, link)

                    -- 仅当是唯一的任务物品时才固定到 QuestItemBar
                    if isQuest and isUnique and addon.Modules.QuestItemBar and addon.Modules.QuestItemBar.PinItem then
                        addon.Modules.QuestItemBar:PinItem(itemID)
                        return
                    end

                    -- 在 TrackedItemBar 中跟踪非唯一任务物品和常规物品
                    local trackedItems = addon.Modules.DB:GetSetting("trackedItems") or {}
                    if trackedItems[itemID] then
                        trackedItems[itemID] = nil
                    else
                        trackedItems[itemID] = true
                    end
                    addon.Modules.DB:SetSetting("trackedItems", trackedItems)

                    -- 更新所有物品按钮的追踪勾选标记（无需全量重建）
                    if Guda.Modules.BagFrame and Guda.Modules.BagFrame.RefreshItemMarkers then
                        Guda.Modules.BagFrame:RefreshItemMarkers()
                    end
                    if Guda.Modules.BankFrame and Guda.Modules.BankFrame.RefreshItemMarkers then
                        Guda.Modules.BankFrame:RefreshItemMarkers()
                    end
                    if Guda.Modules.TrackedItemBar and Guda.Modules.TrackedItemBar.Update then
                        Guda.Modules.TrackedItemBar:Update()
                    end
                    return
                end
            end
        end
        
        -- Shift+点击 将缓存物品链接到聊天（远程银行、只读或已关闭的银行）
        if IsShiftKeyDown() and arg1 == "LeftButton" and this.hasItem then
            if this.otherChar or this.isReadOnly or (this.isBank and this.bagID == -1 and not (getglobal("BankFrame") and getglobal("BankFrame"):IsVisible())) then
                local link = this.itemData and this.itemData.link
                if link and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
                    ChatFrameEditBox:Insert(link)
                    return
                end
            end
        end

        -- 阻止对受保护物品分解/研磨/探测
        if SpellIsTargeting and SpellIsTargeting() and this.hasItem and this.bagID and this.slotID then
            local link = GetContainerItemLink(this.bagID, this.slotID)
            if link and addon and addon.Modules and addon.Modules.Utils and addon.Modules.DB then
                local itemID = addon.Modules.Utils:ExtractItemID(link)
                if itemID and addon.Modules.DB:IsItemProtected(itemID) then
                    SpellStopTargeting()
                    addon:Print(format(GudaBag.L["Cannot disenchant %s — item is protected"], link))
                    return
                end
            end
        end

        -- 默认行为
        if ContainerFrameItemButton_OnClick then
            -- 除 Ctrl+点击（预览）外，邮箱点击应被忽略，
            -- 除非是当前玩家的实时邮件物品且为 Shift+点击（拾取）
            if this.isMail then
                if IsControlKeyDown() then
                    ContainerFrameItemButton_OnClick(arg1)
                end
                return
            end

            -- 拾取前记录光标物品，用于分类拖放
            if this.hasItem and this.bagID and this.slotID and not CursorHasItem() then
                GudaBag.TrackCursorItem(this.bagID, this.slotID)
            end

            ContainerFrameItemButton_OnClick(arg1)

            -- 如果物品已被放置（光标不再持有物品），清除光标跟踪
            if not CursorHasItem() then
                GudaBag.ClearCursorItem()
            end
        end
    end)

    -- OnReceiveDrag：根据视图类型合并堆叠 / 重新分配分类
    self:SetScript("OnReceiveDrag", function()
        -- 空分类投放目标：将光标物品分配到 this.dropTargetCategoryId
        if this.isDropTarget and this.dropTargetCategoryId then
            local info = GudaBag.GetCursorItemInfo()
            if info and info.itemID and addon.Modules.CategoryManager then
                addon.Modules.CategoryManager:AssignItemToCategory(info.itemID, this.dropTargetCategoryId)
                addon:Debug("Assigned item %d to empty category: %s", info.itemID, this.dropTargetCategoryId)
            end
            if CursorHasItem() then
                if this.bagID and this.bagID ~= 0 and this.slotID then
                    -- 非空分类末尾的真实空槽目标：物理放入该空槽
                    PickupContainerItem(this.bagID, this.slotID)
                elseif info then
                    -- 虚拟目标（空分类）：
                    if info.fromInventory then
                        -- 已装备物品：从身上取下并放入背包（放进对应分类）
                        if PutItemInBackpack then
                            PutItemInBackpack()
                        end
                        -- 若背包已满仍留在光标上，放回装备栏位
                        if CursorHasItem() and PickupInventoryItem then
                            PickupInventoryItem(info.bagID)
                        end
                    else
                        -- 普通背包物品：放回原槽
                        PickupContainerItem(info.bagID, info.slotID)
                    end
                end
            end
            dropCooldownTime = GetTime() + 0.3
            HideCategoryDropIndicator()
            GudaBag.ClearCursorItem()
            -- 分类可能已变更（AssignItemToCategory），需要同步重建网格；
            -- 使用 UpdateGrid 跳过金钱/炉石等视图无关部分
            if addon.Modules.BagFrame and addon.Modules.BagFrame.UpdateGrid then
                addon.Modules.BagFrame:UpdateGrid()
            elseif addon.Modules.BagFrame and addon.Modules.BagFrame.Update then
                addon.Modules.BagFrame:Update()
            end
            return
        end

        local inCatView = IsInCategoryView(this.isBank)
        if not inCatView then
            -- 单一视图：将光标物品直接投放到此格子，这样把堆叠拖到
            -- 相同物品的堆叠上即可合并它们。（这里依赖
            -- ContainerFrameItemButton_OnClick 不可靠，因为该函数读取
            -- 全局 arg1，而 OnReceiveDrag 不会设置它。）
            if this and this.bagID ~= nil and this.slotID and not this.otherChar and not this.isReadOnly
               and CursorHasItem and CursorHasItem() then
                PickupContainerItem(this.bagID, this.slotID)
                -- 如果物品已完全放置/合并，清除跟踪
                if not CursorHasItem() then
                    GudaBag.ClearCursorItem()
                end
            end
            return
        end

        -- 分类视图：把堆叠拖到同一物品的堆叠上会合并堆叠；
        -- 投放到不同物品上会把拖拽物品重新分配到该物品的分类（现有行为）。
        local info = GudaBag.GetCursorItemInfo()
        if not info then return end

        -- 装备来源的物品（从身上拉下来的）：无论拖到哪个物品按钮上，
        -- 只要不是绿色投放目标（上面已处理），都直接放入背包第一个空位，
        -- 而不是归类到目标物品的分类。
        if info.fromInventory and CursorHasItem() then
            local placed = GudaBag.PutCursorItemInFirstFreeSlot()
            if not placed and PickupInventoryItem and info.bagID then
                -- 背包已满等失败：放回装备栏位
                PickupInventoryItem(info.bagID)
            end
            dropCooldownTime = GetTime() + 0.3
            HideCategoryDropIndicator()
            GudaBag.ClearCursorItem()
            -- 物理放置会触发 BAG_UPDATE 增量路径；这里只安排防抖兜底
            -- 重绘（增量成功时会自动取消），避免同步全量重建造成卡顿
            if addon.Modules.BagFrame and addon.Modules.BagFrame.ScheduleGridUpdate then
                addon.Modules.BagFrame:ScheduleGridUpdate(0.05)
            end
            return
        end

        -- 目标为空槽位（空分类的"Empty Slots"指示器，或刚清空的空占位）：
        -- 放入背包第一个真实空槽（实时扫描，避免缓存过期指向已占用槽）。
        if not this.hasItem and this.bagID and this.slotID
           and not this.otherChar and not this.isReadOnly and CursorHasItem() then
            local placed = GudaBag.PutCursorItemInFirstFreeSlot()
            if not placed and info.fromInventory and PickupInventoryItem and info.bagID then
                -- 背包已满：装备物品放回装备栏位
                PickupInventoryItem(info.bagID)
            elseif not placed and info.bagID and info.slotID then
                -- 背包物品放回原槽
                PickupContainerItem(info.bagID, info.slotID)
            end
            dropCooldownTime = GetTime() + 0.3
            HideCategoryDropIndicator()
            GudaBag.ClearCursorItem()
            -- 物理放置会触发 BAG_UPDATE 增量路径；这里只安排防抖兜底重绘
            if addon.Modules.BagFrame and addon.Modules.BagFrame.ScheduleGridUpdate then
                addon.Modules.BagFrame:ScheduleGridUpdate(0.05)
            end
            return
        end

        if this.hasItem and this.itemData and addon.Modules.CategoryManager then
            local targetItemID = nil
            local targetLink = this.itemData.link
            if not targetLink and this.itemData.itemID then
                targetLink = "item:" .. this.itemData.itemID .. ":0:0:0"
            end
            if targetLink and addon.Modules.Utils and addon.Modules.Utils.ExtractItemID then
                targetItemID = addon.Modules.Utils:ExtractItemID(targetLink)
            end

            if info.itemID and targetItemID and info.itemID == targetItemID then
                -- 相同物品：将拖拽的堆叠投放到此堆叠上以合并
                if not this.otherChar and not this.isReadOnly and CursorHasItem() then
                    PickupContainerItem(this.bagID, this.slotID)
                    if not CursorHasItem() then
                        dropCooldownTime = GetTime() + 0.3
                        HideCategoryDropIndicator()
                        GudaBag.ClearCursorItem()
                    else
                        -- 合并失败（例如目标被锁定）—— 把物品放回去
                        PickupContainerItem(info.bagID, info.slotID)
                    end
                end
            else
                -- 不同物品：将拖拽的物品重新分配到目标的分类
                local targetCategory = addon.Modules.CategoryManager:CategorizeItem(this.itemData, this.bagID, this.slotID, this.otherChar)
                if targetCategory and info.itemID then
                    addon.Modules.CategoryManager:AssignItemToCategory(info.itemID, targetCategory)
                    addon:Debug("Reassigned item %d to category: %s", info.itemID, targetCategory)
                end

                -- 将拖拽的物品放回其原格子
                if CursorHasItem() then
                    PickupContainerItem(info.bagID, info.slotID)
                end
            end

            -- 设置投放冷却，防止立即重新显示
            dropCooldownTime = GetTime() + 0.3
            HideCategoryDropIndicator()
            GudaBag.ClearCursorItem()

            -- 刷新界面（分类已变更，需同步重建网格；
            -- UpdateGrid 跳过金钱/炉石等视图无关部分）
            if addon.Modules.BagFrame and addon.Modules.BagFrame.UpdateGrid then
                addon.Modules.BagFrame:UpdateGrid()
            elseif addon.Modules.BagFrame and addon.Modules.BagFrame.Update then
                addon.Modules.BagFrame:Update()
            end
            if addon.Modules.BankFrame and addon.Modules.BankFrame.Update then
                local bankFrame = getglobal("Guda_BankFrame")
                if bankFrame and bankFrame:IsShown() then
                    if addon.Modules.BankFrame.UpdateGrid then
                        addon.Modules.BankFrame:UpdateGrid()
                    else
                        addon.Modules.BankFrame:Update()
                    end
                end
            end
        end
    end)
end

-- 更新此物品按钮上的暴雪冷却叠加层
function GudaBag.ItemButton_UpdateCooldown(self)
    -- 仅对当前角色的实时物品显示冷却
    if not self then return end

    local cooldown = getglobal(self:GetName().."Cooldown") or self.cooldown
    if not cooldown then return end

    -- 确保只读或其他角色视图不显示冷却叠加层
    if self.isReadOnly or self.otherChar then
        -- 清除之前的任何计时器状态并隐藏，避免池化按钮之间的状态残留
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(cooldown, 0, 0, 0)
        elseif CooldownFrame_Set then
            CooldownFrame_Set(cooldown, 0, 0, 0)
        end
        cooldown:Hide()
        return
    end

    if not self.hasItem or not self.bagID or not self.slotID then
        cooldown:Hide()
        return
    end

    local start, duration, enable = GetContainerItemCooldown(self.bagID, self.slotID)
    if start and duration and duration > 0 and enable == 1 then
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(cooldown, start, duration, enable)
        elseif CooldownFrame_Set then
            -- 某些客户端暴露的是 CooldownFrame_Set
            CooldownFrame_Set(cooldown, start, duration, enable)
        else
            -- 后备：如果 API 缺失则显示框架
            cooldown:Show()
        end
    else
        cooldown:Hide()
    end
end

--=====================================================
-- SetItem 的辅助函数（提取出来使代码更清晰）
--=====================================================

-- 重置按钮上的所有视觉状态（用于从池中复用）
local function ResetButtonVisualState(self)
    if self.questIcon then self.questIcon:Hide() end
    ResetSlotBorder(self)
    HideInnerShadow(self.innerShadow)
    if self.unusableOverlay then self.unusableOverlay:Hide() end
    HideJunkIcon(self)
    if self.categoryMarkIcon then self.categoryMarkIcon:Hide() end
    local chargesText = getglobal(self:GetName().."_Charges")
    if chargesText then chargesText:Hide() end

    -- 重置投放目标渲染可能应用在此池化按钮上的效果
    self:SetAlpha(1)
    local iconTex = getglobal(self:GetName().."IconTexture") or getglobal(self:GetName().."Icon") or self.icon or self.Icon
    if iconTex then
        if iconTex.SetDesaturated then iconTex:SetDesaturated(false) end
        iconTex:SetVertexColor(1, 1, 1)
    end

    -- 清除冷却叠加层
    local cd = getglobal(self:GetName().."Cooldown") or self.cooldown
    if cd then
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(cd, 0, 0, 0)
        elseif CooldownFrame_Set then
            CooldownFrame_Set(cd, 0, 0, 0)
        end
        if cd.Hide then cd:Hide() end
    end
end

-- 根据只读状态配置拖拽/投放注册
local function SetupDragDrop(self)
    if not self.isReadOnly and not self.otherChar then
        if self.RegisterForDrag then
            self:RegisterForDrag("LeftButton")
        end
        if self.RegisterForClicks then
            self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        if self.EnableMouse then
            self:EnableMouse(true)
        end
    else
        -- 对只读或其他角色的物品禁用拖拽
        if self.RegisterForDrag then
            self:RegisterForDrag()  -- 清除拖拽注册
        end
        if self.EnableMouse then
            self:EnableMouse(true)  -- 仍启用鼠标以显示提示
        end
    end
end

-- 获取物品格子的显示贴图和数量
-- 返回：texture（贴图）、count（数量）、hasItem（布尔值）
local function GetItemDisplayInfo(bagID, slotID, itemData, isReadOnly)
    local displayTexture, displayCount
    local hasItem = false

    if not isReadOnly then
        -- 实时模式：直接查询游戏状态
        local liveTexture, liveCount = GetContainerItemInfo(bagID, slotID)
        if liveTexture then
            displayTexture = liveTexture
            displayCount = liveCount
            hasItem = true
        elseif bagID == -2 then
            -- 1.12.1 中钥匙扣的后备处理
            local link = GetContainerItemLink(bagID, slotID)
            if link then
                hasItem = true
                local _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(link)
                displayTexture = itemTexture
                displayCount = 1
            end
        end
    else
        -- 只读模式：使用缓存的 itemData
        if itemData and itemData.texture then
            displayTexture = itemData.texture
            displayCount = itemData.count
            hasItem = true
        end
    end

    return displayTexture, displayCount, hasItem
end

-- 更新物品按钮上的跟踪勾选标记
local function UpdateTrackingCheckmark(self, Utils)
    local check = getglobal(self:GetName().."_Check")
    if not check then return end

    local isTracked = false
    -- 与 UpdateLockIcon 相同的实时后备：加载画面后
    -- 缓存的 itemData.link 在首个渲染帧上可能为 nil。
    if self.hasItem and self.bagID and self.slotID then
        local link = (self.itemData and self.itemData.link) or GetContainerItemLink(self.bagID, self.slotID)
        local itemID = Utils and Utils.ExtractItemID and Utils:ExtractItemID(link)
        if itemID then
            local trackedItems = Utils and Utils.SafeCall and Utils:SafeCall("DB", "GetSetting", "trackedItems") or {}
            if trackedItems[itemID] then
                isTracked = true
            end
        end
    end

    if isTracked then
        check:Show()
    else
        check:Hide()
    end
end

-- 轻量刷新单个按钮上的状态标记（物品锁定锁、格子图钉、追踪勾选、
-- 拾取标记）。这些标记只依赖查表（DB 设置/固定槽位表），不涉及
-- tooltip 扫描或布局。用于 Ctrl+右键锁定、Alt+右键固定、Alt+左键
-- 追踪等只需更新图标的操作 —— 取代原先的全量 Update() 重建。
function GudaBag.ItemButton_RefreshMarkers(button, iconSize)
    if not button or not button:IsShown() or button.isDropTarget then return end
    if button.hasItem == nil then return end
    if not iconSize and button.GetWidth then
        iconSize = button:GetWidth() or 37
    end
    if UpdateLockIcon then UpdateLockIcon(button, iconSize) end
    if UpdatePinIcon then UpdatePinIcon(button, iconSize) end
    if UpdateTrackingCheckmark then
        local Utils = addon and addon.Modules and addon.Modules.Utils
        UpdateTrackingCheckmark(button, Utils)
    end
    if GudaBag.ItemButton_UpdateLootMarker then
        local Utils = addon and addon.Modules and addon.Modules.Utils
        GudaBag.ItemButton_UpdateLootMarker(button, Utils)
    end
end

-- 调整空格子背景的大小以匹配图标尺寸和格子样式
local function UpdateEmptySlotBackground(self, emptySlotBg, iconSize)
    if not emptySlotBg then return end

    local slotStyle = "rounded"
    if addon.Modules and addon.Modules.Theme then
        slotStyle = addon.Modules.Theme:GetSlotStyle()
    end

    emptySlotBg:ClearAllPoints()
    if slotStyle == "square" then
        -- 刷新锚点，实现像素级完美的方形格子
        emptySlotBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        emptySlotBg:SetVertexColor(0.05, 0.05, 0.05, 1)
        emptySlotBg:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        emptySlotBg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    else
        -- 超出按钮边缘 9px，让 UI-EmptySlot 的圆角
        -- 覆盖图标贴图的方形角（与 GudaBags 相同）
        emptySlotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        emptySlotBg:SetVertexColor(1, 1, 1, 1)
        emptySlotBg:SetPoint("TOPLEFT", self, "TOPLEFT", -9, 9)
        emptySlotBg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 9, -9)
    end
    emptySlotBg:SetTexCoord(0, 1, 0, 1)
end

-- 根据图标尺寸定位图标和边框
local function PositionIconAndBorders(self, iconSize)
    local iconTexture = getglobal(self:GetName().."IconTexture")
    if not iconTexture then
        iconTexture = getglobal(self:GetName().."Icon") or self.icon or self.Icon
    end

    if not iconTexture or not self.hasItem then return end

    -- 图标填满整个按钮格子
    local iconDisplaySize = iconSize

    iconTexture:ClearAllPoints()
    iconTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
    iconTexture:SetWidth(iconDisplaySize)
    iconTexture:SetHeight(iconDisplaySize)
    iconTexture:SetTexCoord(0, 1, 0, 1)
    iconTexture:Show()

    -- 将任务图标定位在右上角
    if self.questIcon then
        local questIconSize = math.max(12, math.min(20, iconSize * 0.35))
        self.questIcon:SetWidth(questIconSize)
        self.questIcon:SetHeight(questIconSize)
        self.questIcon:ClearAllPoints()
        self.questIcon:SetPoint("TOPRIGHT", self, "TOPRIGHT", 1, 0)
    end
end

-- 清除空格子物品按钮
local function ClearItemButton(self, emptySlotBg, countText, bagID)
    self.hasItem = false

    if SetItemButtonTexture then SetItemButtonTexture(self, nil) end
    if SetItemButtonCount then SetItemButtonCount(self, 0) end
    if SetItemButtonDesaturated then SetItemButtonDesaturated(self, false) end

    -- 清除冷却叠加层
    local cooldown = getglobal(self:GetName().."Cooldown") or self.cooldown
    if cooldown and cooldown.Hide then cooldown:Hide() end

    -- 清除图标贴图
    local iconTexture = getglobal(self:GetName().."IconTexture")
    if not iconTexture then
        iconTexture = getglobal(self:GetName().."Icon") or self.icon or self.Icon
    end
    if iconTexture then
        iconTexture:SetTexture(nil)
        iconTexture:Hide()
    end

    -- 清除不可用色调
    if SetItemButtonTextureVertexColor then
        SetItemButtonTextureVertexColor(self, 1.0, 1.0, 1.0)
    end
    if self.unusableOverlay and self.unusableOverlay.Hide then
        self.unusableOverlay:Hide()
    end

    -- 隐藏垃圾图标
    HideJunkIcon(self)

    -- 隐藏锁和图钉图标
    HideLockIcon(self)
    HidePinIcon(self)

    -- 隐藏普通贴图
    self:SetNormalTexture("")
    local normalBorder = getglobal(self:GetName().."NormalTexture")
    if normalBorder then normalBorder:SetTexture("") end

    -- 显示/隐藏空格子背景
    if emptySlotBg then
        local slotAlpha = 0.5
        if addon.Modules and addon.Modules.Theme then
            local sa = addon.Modules.Theme:GetValue("slotBgAlpha")
            if sa then slotAlpha = sa.empty end
        end
        if slotAlpha > 0 then
            emptySlotBg:Show()
            emptySlotBg:SetAlpha(slotAlpha)
        else
            emptySlotBg:Hide()
        end
    end

    if countText then countText:Hide() end
    local chargesText = getglobal(self:GetName().."_Charges")
    if chargesText then chargesText:Hide() end

    ResetSlotBorder(self)
    HideInnerShadow(self.innerShadow)

    -- 隐藏任务元素
    if self.questIcon then self.questIcon:Hide() end
end

--=====================================================
-- 主 SetItem 函数（协调各辅助函数）
--=====================================================

-- 设置物品数据
function GudaBag.ItemButton_SetItem(self, bagID, slotID, itemData, isBank, otherCharName, matchesFilter, isReadOnly)
    -- 主动转换为数字，避免下游函数中与字符串比较
    bagID = tonumber(bagID)
    slotID = tonumber(slotID)

    -- 在重新分配池化按钮前重置所有视觉状态
    ResetButtonVisualState(self)
    -- 池化按钮可能携带上一次渲染的投放目标光晕 —— 在决定
    -- 此按钮现在的用途前先清除它。
    StopDropTargetGlow(self)

    -- 投放目标伪物品（拖动期间的空分类占位符）。
    -- 使用分类的图标显示，变暗+去饱和，带脉冲绿色光晕。
    -- OnReceiveDrag/OnClick 将路由到 AssignItemToCategory。
    if itemData and itemData.isDropTarget then
        -- 空分类的虚拟目标 bagID=0/slotID=0（仅归类）；非空分类末尾的
        -- 目标则携带真实空槽（bagID/slotID 有效），拖放时物理放入该空槽。
        self.bagID = bagID or 0
        self.slotID = slotID or 0
        self.bagIndex = -100
        self.itemData = itemData
        self.isBank = isBank or false
        self.otherChar = nil
        self.isReadOnly = false
        self.isMail = false
        self.hasItem = false
        self.isDropTarget = true
        self.dropTargetCategoryId = itemData.categoryId

        SetupDragDrop(self)

        local iconSize = 37
        if addon and addon.Modules and addon.Modules.Utils and addon.Modules.Utils.SafeCall then
            iconSize = addon.Modules.Utils:SafeCall("DB", "GetSetting", "iconSize") or iconSize
        end
        self:SetWidth(iconSize)
        self:SetHeight(iconSize)

        if SetItemButtonTexture then
            SetItemButtonTexture(self, itemData.texture)
        end
        local iconTexture = getglobal(self:GetName().."IconTexture") or getglobal(self:GetName().."Icon") or self.icon or self.Icon
        if iconTexture then
            iconTexture:SetTexture(itemData.texture)
            -- 镜像 PositionIconAndBorders()，让分类图标按用户配置的
            -- iconSize 填满整个按钮。PositionIconAndBorders 本身
            -- 由 `self.hasItem` 守卫，而投放目标不会设置该字段。
            iconTexture:ClearAllPoints()
            iconTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
            iconTexture:SetWidth(iconSize)
            iconTexture:SetHeight(iconSize)
            iconTexture:SetTexCoord(0, 1, 0, 1)
            iconTexture:Show()
            if iconTexture.SetDesaturated then iconTexture:SetDesaturated(true) end
            iconTexture:SetVertexColor(0.6, 1.0, 0.6)
        end
        if SetItemButtonCount then SetItemButtonCount(self, 0) end
        self:SetAlpha(0.85)

        EnsureDropTargetGlow(self)
        self:Show()
        return
    end

    -- 设置按钮属性
    self.bagID = bagID
    self.slotID = slotID
    if self.SetID then
        self:SetID(slotID or 0)
    end
    self.bagIndex = bagID or -100
    self.itemData = itemData
    self.isBank = isBank or false
    self.otherChar = otherCharName
    self.isReadOnly = isReadOnly or false
    self.isMail = false
    self.mailIndex = nil
    self.mailItemIndex = nil
    self.mailData = nil

    -- 配置拖拽/投放
    SetupDragDrop(self)

    -- 未指定时默认为 true
    if matchesFilter == nil then
        matchesFilter = true
    end

    -- 获取 UI 元素
    local countText = getglobal(self:GetName().."Count")
    local chargesText = getglobal(self:GetName().."_Charges")
    local emptySlotBg = getglobal(self:GetName().."_EmptySlotBg")
    local Utils = addon and addon.Modules and addon.Modules.Utils

    -- 获取图标尺寸设置
    local iconSize = 37
    if Utils and Utils.SafeCall then
        iconSize = Utils:SafeCall("DB", "GetSetting", "iconSize") or iconSize
    end
    if addon and addon.Constants then
        iconSize = iconSize or addon.Constants.BUTTON_SIZE
    end
    self:SetWidth(iconSize)
    self:SetHeight(iconSize)

    -- 获取物品显示信息（贴图、数量、hasItem）
    local displayTexture, displayCount, hasItem = GetItemDisplayInfo(bagID, slotID, itemData, self.isReadOnly)
    self.hasItem = hasItem

    -- 根据格子是否有物品应用显示
    if self.hasItem then
        -- 设置贴图
        if SetItemButtonTexture then
            SetItemButtonTexture(self, displayTexture)
        end
        local iconTexture = getglobal(self:GetName().."IconTexture") or getglobal(self:GetName().."Icon") or self.icon or self.Icon
        if iconTexture and displayTexture then
            iconTexture:SetTexture(displayTexture)
            iconTexture:Show()
        end

        -- 设置数量
        if SetItemButtonCount then SetItemButtonCount(self, displayCount or 1) end

        -- 更新实时物品的冷却叠加层
        if not self.isReadOnly and not self.otherChar and GudaBag.ItemButton_UpdateCooldown then
            GudaBag.ItemButton_UpdateCooldown(self)
        else
            local cd = getglobal(self:GetName().."Cooldown") or self.cooldown
            if cd and cd.Hide then cd:Hide() end
        end

        -- 更新不可用红色叠加层色调（布局路径上仅缓存；
        -- BagFrame 中的延迟处理通过 QueueWork 运行完整扫描）。
        if ItemButton_UpdateUsableTint then
            ItemButton_UpdateUsableTint(self, true)
        end
    else
        -- 清除空格子
        ClearItemButton(self, emptySlotBg, countText, bagID)
    end

    -- 更新跟踪勾选标记
    UpdateTrackingCheckmark(self, Utils)
    local check = getglobal(self:GetName().."_Check")
    if check then
        local isTracked = false
        if self.hasItem and self.bagID and self.slotID then
            local link = (self.itemData and self.itemData.link) or GetContainerItemLink(self.bagID, self.slotID)
            local itemID = Utils and Utils.ExtractItemID and Utils:ExtractItemID(link)
            if itemID then
                local trackedItems = Utils and Utils.SafeCall and Utils:SafeCall("DB", "GetSetting", "trackedItems") or {}
                if trackedItems[itemID] then
                    isTracked = true
                end
            end
        end
        
        if isTracked then
            check:Show()
        else
            check:Hide()
        end
    end

    -- 更新锁和图钉图标
    UpdateLockIcon(self, iconSize)
    UpdatePinIcon(self, iconSize)

    -- 更新拾取标记（最近拾取窗口内物品右上角的红色空心圆环）
    GudaBag.ItemButton_UpdateLootMarker(self, Utils)

    -- 根据格子样式更新空格子背景的锚点/贴图
    UpdateEmptySlotBackground(self, emptySlotBg, iconSize)

    -- 同时调整底层格子贴图的大小，使边框/背景随按钮缩放。
    -- 在 1.12/Turtle 中，ItemButtonTemplate 使用固定尺寸的贴图，因此我们
    -- 显式设置其大小以匹配当前 iconSize，而不是让其使用默认尺寸。

    -- 为 1.12.1 兼容，使用两种方法以及正确的命名访问贴图
    -- 稍后根据格子是否为空还是已填充来设置 NormalTexture

    -- 图标贴图：确保使用正确的名称（$parentIconTexture 是标准）
    local iconTexture = getglobal(self:GetName().."IconTexture") or getglobal(self:GetName().."Icon") or self.icon or self.Icon

    -- 按下贴图跟随按钮的大小/位置
    local pushedTexture = getglobal(self:GetName().."PushedTexture")
    if not pushedTexture and self.GetPushedTexture then
        pushedTexture = self:GetPushedTexture()
    end
    if pushedTexture then
        pushedTexture:ClearAllPoints()
        pushedTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
        pushedTexture:SetWidth(iconSize)
        pushedTexture:SetHeight(iconSize)
    end

    -- 悬停高亮贴图（搜索时不使用）
    local highlightTexture = getglobal(self:GetName().."HighlightTexture")
    if not highlightTexture and self.GetHighlightTexture then
        highlightTexture = self:GetHighlightTexture()
    end
    if highlightTexture then
        highlightTexture:ClearAllPoints()
        highlightTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
        highlightTexture:SetWidth(iconSize)
        highlightTexture:SetHeight(iconSize)
    end

    -- 选中贴图（格子处于"激活"状态时的居中方形图案）
    local checkedTexture = getglobal(self:GetName().."CheckedTexture")
    if not checkedTexture and self.GetCheckedTexture then
        checkedTexture = self:GetCheckedTexture()
    end
    if checkedTexture then
        checkedTexture:ClearAllPoints()
        checkedTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
        checkedTexture:SetWidth(iconSize)
        checkedTexture:SetHeight(iconSize)
    end


    -- 将图标字体大小设置应用到堆叠数量文本
    if countText and countText.GetFont then
        local font, _, flags = countText:GetFont()
        local fontSize = 12
        if Utils and Utils.SafeCall then
            fontSize = Utils:SafeCall("DB", "GetSetting", "iconFontSize") or fontSize
        end
        countText:SetFont(font, fontSize, flags)

        -- 根据图标尺寸调整数量文本位置，以获得更好的对齐
        countText:ClearAllPoints()
        if iconSize < 44 then
            -- 小图标的偏移更小
            countText:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
        else
            -- 大图标的偏移更大
            countText:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3, 3)
        end
    end

    -- 将图标字体大小设置应用到充能文本（位于堆叠数量上方）
    if chargesText and chargesText.GetFont then
        local font, _, flags = chargesText:GetFont()
        local fontSize = 12
        if Utils and Utils.SafeCall then
            fontSize = Utils:SafeCall("DB", "GetSetting", "iconFontSize") or fontSize
        end
        chargesText:SetFont(font, fontSize, flags)
        chargesText:SetTextColor(1, 0.82, 0)
        chargesText:ClearAllPoints()
        if iconSize < 44 then
            chargesText:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
        else
            chargesText:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3, 3)
        end
    end

    -- 实时模式下获取实时元数据（品质、链接、锁状态）
    local itemQuality, itemLink, isLocked
    if not self.isReadOnly and bagID and slotID and self.hasItem then
        -- 查询实时游戏状态获取元数据
        -- 银行主背包（bagID == -1）的特殊处理，它使用物品栏格子 API
        if self.isBank and bagID == -1 then
            local invSlot = 39 + slotID
            itemLink = GetInventoryItemLink("player", invSlot)
            isLocked = IsInventoryItemLocked(invSlot)
            -- 品质将在下方由 GetItemInfo 确定
        else
            local _, _, locked, quality = GetContainerItemInfo(bagID, slotID)
            itemLink = GetContainerItemLink(bagID, slotID)
            itemQuality = quality
            isLocked = locked
        end

        -- 如果实时查询返回 nil（银行打开时的时序问题），回退到 itemData.quality
        if itemQuality == nil and itemData and itemData.quality then
            itemQuality = itemData.quality
        end

        -- 确保实时物品的 itemData 已填充（ItemDetection 需要）
        if itemLink then
            local itemName, _, itemRarity, itemLevel, itemCategory, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemLink)
            -- 始终优先使用 GetItemInfo 的品质 —— GetContainerItemInfo 在
            -- TurtleWoW 1.12 中经常对史诗代币返回错误的品质（如 1/白色）
            if itemRarity then
                itemQuality = itemRarity
            end
            if itemQuality == nil and itemData and itemData.quality then
                itemQuality = itemData.quality
            end
            if not itemData then
                -- 创建新的 itemData
                if itemName then
                    itemData = {
                        link = itemLink,
                        name = itemName,
                        quality = itemRarity or itemQuality or 0,
                        -- Turtle WoW 的 GetItemInfo 在第 5 个位置返回物品 CLASS
                        -- （第 6 个位置是子类型）。将类名规范化为英文，
                        -- 以便检测/分类在 zhCN 上正常工作。
                        class = addon.Modules.Utils:NormalizeItemClass(itemCategory),
                        subclass = itemSubType,
                        texture = itemTexture,
                        count = 1,
                    }
                    self.itemData = itemData
                end
            else
                -- 始终用实时链接更新 itemData.link，确保交换后检测正确
                -- 这很关键：缓存的 itemData 可能带有交换前的过期链接
                itemData.link = itemLink
                -- 仅在其他字段缺失时更新
                if itemData.quality == nil then itemData.quality = itemRarity or itemQuality or 0 end
                if not itemData.class and itemCategory then itemData.class = addon.Modules.Utils:NormalizeItemClass(itemCategory) end
                if not itemData.subclass and itemSubType then itemData.subclass = itemSubType end
                if not itemData.name and itemName then itemData.name = itemName end
                self.itemData = itemData
            end
        end
    elseif itemData then
        -- 使用数据库中的缓存元数据
        itemQuality = itemData.quality
        itemLink = itemData.link
        isLocked = itemData.locked
    end

    if self.hasItem then
        -- 图标已在上面根据模式（实时 vs 缓存）设置

        -- 将锁定物品置灰（正在交易、邮寄或拍卖中）
        -- 不对其他角色的物品去饱和，反正它们都是只读的
        if not self.otherChar and not self.isReadOnly then
            SetItemButtonDesaturated(self, isLocked, 0.5, 0.5, 0.5)
        end

        -- 已填充格子隐藏 NormalTexture
        self:SetNormalTexture("")
        local normalBorder = getglobal(self:GetName().."NormalTexture")
        if normalBorder then
            normalBorder:SetTexture("")
        end

        -- 在已填充物品上显示格子背景叠加层
        if emptySlotBg then
            local slotStyle = "rounded"
            if addon.Modules and addon.Modules.Theme then
                slotStyle = addon.Modules.Theme:GetSlotStyle()
            end
            if slotStyle == "square" then
                -- 方形模式：不需要圆角叠加层，隐藏格子背景
                emptySlotBg:Hide()
            else
                -- 圆角模式：显示 UI-EmptySlot，让圆角覆盖图标
                emptySlotBg:Show()
                emptySlotBg:SetAlpha(1)
            end
        end

        -- 使用 CategoryManager 检查物品是否为垃圾并获取分类标记
        local isJunk = false
        local categoryMarkTexture = nil
        if itemData and addon.Modules.CategoryManager then
            local category = addon.Modules.CategoryManager:CategorizeItem(itemData, bagID, slotID, self.otherChar)
            isJunk = (category == "Junk")
            -- 在按钮上缓存垃圾状态，这样搜索快速路径可以
            -- 无需重新运行分类就重新应用正确的 alpha（垃圾不透明度 vs 全不透明度）。
            self._isJunk = isJunk
            -- 如果设置了分类标记图标则获取
            local catDef = addon.Modules.CategoryManager:GetCategory(category)
            if catDef and catDef.categoryMark then
                categoryMarkTexture = catDef.categoryMark
            end
        end

        -- 更新分类标记叠加层（图标贴图左下角）
        if categoryMarkTexture then
            local iconTex = getglobal(self:GetName().."IconTexture") or getglobal(self:GetName().."Icon") or self.icon or self.Icon
            local anchor = iconTex or self
            if not self.categoryMarkIcon then
                self.categoryMarkIcon = self:CreateTexture(nil, "OVERLAY", 7)
            end
            local markSize = math.max(10, math.floor(iconSize * 0.3)) + 3
            self.categoryMarkIcon:SetWidth(markSize)
            self.categoryMarkIcon:SetHeight(markSize)
            self.categoryMarkIcon:ClearAllPoints()
            local markOffX, markOffY = 1, 2
            if addon.Modules and addon.Modules.Theme and addon.Modules.Theme:GetSlotStyle() == "square" then
                markOffX, markOffY = -1, -1
            end
            self.categoryMarkIcon:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", markOffX, markOffY)
            self.categoryMarkIcon:SetTexture(categoryMarkTexture)
            self.categoryMarkIcon:SetVertexColor(1, 1, 1, 1)
            self.categoryMarkIcon:SetAlpha(1)
            self.categoryMarkIcon:Show()
        else
            if self.categoryMarkIcon then self.categoryMarkIcon:Hide() end
        end

        -- 搜索过滤和垃圾不透明度
        if matchesFilter then
            if isJunk then
                -- 垃圾物品：可配置的不透明度（默认 60%）
                local junkOpacity = 0.6
                if addon.Modules.DB and addon.Modules.DB.GetSetting then
                    junkOpacity = addon.Modules.DB:GetSetting("junkOpacity") or 0.6
                end
                self:SetAlpha(junkOpacity)
            else
                -- 普通物品：完全不透明度（1.0）
                self:SetAlpha(1.0)
            end
        else
            -- 不匹配的物品：25% 不透明度（0.25）—— 非常暗
            self:SetAlpha(0.25)
        end

        -- 显示/隐藏垃圾图标（左上角的商人出售图标）
        UpdateJunkIcon(self, isJunk, iconSize)

        -- 设置数量（使用上面根据模式确定的 displayCount）
        if displayCount and displayCount > 1 then
            countText:SetText(displayCount)
            countText:Show()
        else
            countText:Hide()
        end

        -- 设置品质边框（给格子背景着色）和内阴影
        do
            local borderApplied = false
            if itemQuality then
                -- 检查设置以确定是否应显示边框
                -- 统一开关 showItemBorder（合并了装备/其他物品边框）
                local showItemBorder = true
                if Utils and Utils.SafeCall then
                    local v = Utils:SafeCall("DB", "GetSetting", "showItemBorder")
                    if v ~= nil then showItemBorder = v end
                end

                local shouldShowBorder = (showItemBorder ~= false)

                if shouldShowBorder then
                    local r, g, b
                    if itemLink and Utils and Utils.GetLinkColor then
                        r, g, b = Utils:GetLinkColor(itemLink)
                    end
                    if not r then
                        if Utils and Utils.GetQualityColor then
                            r, g, b = Utils:GetQualityColor(itemQuality)
                        else
                            r, g, b = 1, 1, 1
                        end
                    end
                    TintSlotBorder(self, r, g, b)
                    -- 仅对彩色边框显示内阴影，白色不显示
                    if r < 0.95 or g < 0.95 or b < 0.95 then
                        ShowInnerShadow(self.innerShadow, r, g, b)
                    else
                        HideInnerShadow(self.innerShadow)
                    end
                    borderApplied = true
                end
            end

            -- 任务物品覆盖为金色边框
            if not self.otherChar and not self.isReadOnly then
                local isQuest, isQuestStarter = IsQuestItem(bagID, slotID, self.isBank, itemData)
                ItemButton_UpdateQuestIcon(self, isQuest, isQuestStarter)
                if isQuest then
                    TintSlotBorder(self, 1.0, 0.82, 0)
                    ShowInnerShadow(self.innerShadow, 1.0, 0.82, 0)
                    borderApplied = true
                end
                if self.questIcon then
                    if isQuest then
                        self.questIcon:Show()
                    else
                        self.questIcon:Hide()
                    end
                end
            end

            if not borderApplied then
                ResetSlotBorder(self)
                HideInnerShadow(self.innerShadow)
            end
		end

        -- 显示/隐藏充能文本（例如 "x5" 用于魔法油）
        if chargesText then
            local charges = nil
            -- 优先用 Nampower 直接提供的剩余次数（免 tooltip 扫描）。
            -- Nampower 对无次数物品返回 1（"无充能"哨兵值），因此只在 >1 时
            -- 才视为有效次数，避免无次数物品图标上出现 x1。
            if itemData and itemData.spellChargesRemaining and itemData.spellChargesRemaining > 1 then
                charges = itemData.spellChargesRemaining
            elseif itemData and addon.Modules.ItemDetection then
                -- 仅查充能缓存（免 tooltip 扫描）。BAG_UPDATE 会使充能缓存
                -- 失效；若在缓存未热时同步扫描，一次 BAG_UPDATE（如右键把
                -- 物品附加到邮件）触发的全量重绘会对每个格子逐个扫描提示框，
                -- 造成明显卡顿。未命中时先不显示，CacheWarmer/悬停后补上。
                charges = addon.Modules.ItemDetection:GetChargesCached(itemData, bagID, slotID)
            end
            if charges and charges > 0 then
                chargesText:SetText("x" .. charges)
                chargesText:Show()
            else
                chargesText:Hide()
            end
        end

        -- 处理点击时跟踪切换
        -- 注意：跟踪切换现在在上方的主 OnClick 脚本中处理，以避免冲突，
        -- 并与 QuestItemBar 固定逻辑统一。

        self:Show()
    else
        self.hasItem = false
        -- 对空格子，清除图标贴图
        SetItemButtonTexture(self, nil)

        -- 空格子隐藏 NormalTexture（我们使用 EmptySlotBg 代替）
        self:SetNormalTexture("")
        local normalBorder = getglobal(self:GetName().."NormalTexture")
        if normalBorder then
            normalBorder:SetTexture("")
        end

        -- 空格子显示经典背包图案背景
        if emptySlotBg then
            local slotAlpha = 0.5
            if addon.Modules and addon.Modules.Theme then
                local sa = addon.Modules.Theme:GetValue("slotBgAlpha")
                if sa then slotAlpha = sa.empty end
            end
            if slotAlpha > 0 then
                emptySlotBg:Show()
                emptySlotBg:SetAlpha(slotAlpha)
            else
                emptySlotBg:Hide()
            end
        end

        -- 搜索时调暗空格子
        if matchesFilter then
            -- 未激活搜索或通过过滤器：正常不透明度
            self:SetAlpha(1.0)
        else
            -- 搜索激活且不匹配：非常暗
            self:SetAlpha(0.25)
        end

        countText:Hide()

        -- 空格子重置格子边框并隐藏内阴影
        ResetSlotBorder(self)
        HideInnerShadow(self.innerShadow)

        -- 空格子隐藏任务图标
        if self.questIcon then
            self.questIcon:Hide()
        end

        self:Show()
    end

    -- 在 1.12.1 中，ItemButtonTemplate 创建名为 "$parentIconTexture" 的图标
    local iconTexture = getglobal(self:GetName().."IconTexture")
    if not iconTexture then
        -- 其他命名约定的后备
        iconTexture = getglobal(self:GetName().."Icon") or self.icon or self.Icon
    end

    if iconTexture then
        if self.hasItem then
            -- 图标填满整个按钮格子
            local iconDisplaySize = iconSize
            iconTexture:ClearAllPoints()
            iconTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
            iconTexture:SetWidth(iconDisplaySize)
            iconTexture:SetHeight(iconDisplaySize)
            -- 裁剪图标边缘：方形模式下 pfUI 风格内缩，圆角模式满尺寸
            local slotStyle = "rounded"
            if addon.Modules and addon.Modules.Theme then
                slotStyle = addon.Modules.Theme:GetSlotStyle()
            end
            if slotStyle == "square" then
                iconTexture:SetTexCoord(.08, .92, .08, .92)
            else
                iconTexture:SetTexCoord(0, 1, 0, 1)
            end
            iconTexture:Show()

            -- 将任务图标定位在右上角
            if self.questIcon then
                -- 根据按钮大小缩放图标尺寸
                local questIconSize = math.max(12, math.min(20, iconSize * 0.35))
                self.questIcon:SetWidth(questIconSize)
                self.questIcon:SetHeight(questIconSize)

                self.questIcon:ClearAllPoints()
                self.questIcon:SetPoint("TOPRIGHT", self, "TOPRIGHT", 1, 0)
            end
        elseif not self.isMail then
            -- 空格子隐藏图标，但邮箱自定义图标保留
            iconTexture:Hide()
        end
    end
end

-- OnEnter 处理器（显示提示）
function GudaBag.ItemButton_OnEnter(self)
    addon:Debug("OnEnter FIRED: button=%s CursorHasItem=%s", tostring(self:GetName()), tostring(CursorHasItem and CursorHasItem()))

    -- 投放目标占位：简单提示，跳过常规物品提示路径。
    if self.isDropTarget then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 10, 0)
        GameTooltip.GudaAnchorButton = self
        GameTooltip.GudaCursorMode = false
        local catName = self.dropTargetCategoryId or ""
        local catDisplay = catName
        if GudaBag.L and GudaBag.L[catDisplay] then catDisplay = GudaBag.L[catDisplay] end
        local label = (GudaBag.L and GudaBag.L["Drop to assign to %s"]) or "Drop to assign to %s"
        GameTooltip:SetText(format(label, catDisplay), 1, 1, 1)
        GameTooltip:Show()
        return
    end

    -- 分类拖放：在分类视图中光标持有物品并悬停时显示 "+" 指示器
    local hasCursor = CursorHasItem and CursorHasItem()
    if hasCursor then
        addon:Debug("DropInd OnEnter: hasItem=%s otherChar=%s isBank=%s", tostring(self.hasItem), tostring(self.otherChar), tostring(self.isBank))
    end
    if hasCursor and self.hasItem and not self.otherChar then
        local inCatView = IsInCategoryView(self.isBank)
        addon:Debug("DropInd: inCatView=%s hasItemData=%s hasCatMgr=%s", tostring(inCatView), tostring(self.itemData ~= nil), tostring(addon.Modules.CategoryManager ~= nil))
        if inCatView and self.itemData and addon.Modules.CategoryManager then
            -- 如果拖拽的物品已处于同一分类，则不显示指示器
            local targetCategory = addon.Modules.CategoryManager:CategorizeItem(self.itemData, self.bagID, self.slotID, self.otherChar)
            local cursorCategory = GetCursorItemCategory()
            addon:Debug("DropInd: targetCat=%s cursorCat=%s cooldown=%s", tostring(targetCategory), tostring(cursorCategory), tostring(GetTime() < dropCooldownTime))
            if targetCategory and cursorCategory and targetCategory ~= cursorCategory then
                self.categoryId = targetCategory
                addon:Debug("DropInd: SHOWING indicator for %s", tostring(targetCategory))
                ShowCategoryDropIndicator(self)
            else
                addon:Debug("DropInd: NOT showing - same=%s targetNil=%s cursorNil=%s", tostring(targetCategory == cursorCategory), tostring(targetCategory == nil), tostring(cursorCategory == nil))
            end
        end
    end

    -- 在底部栏高亮对应的背包按钮（空格子和已填充格子都有效）
	if not self.otherChar and self.bagID then
		if self.isBank then
		-- 银行物品 —— 高亮银行背包按钮
			GudaBag.BankFrame_HighlightBagButton(self.bagID)
		else
		-- 常规背包物品 —— 高亮背包按钮
			GudaBag.BagFrame_HighlightBagButton(self.bagID)
		end
	end

	-- 空格子提前返回（无需提示）
	if not self.hasItem and not self.isMail then
		return
	end

	-- 检查 pfUI 光标提示模式是否激活
	local pfuiCursorMode = false
	if pfUI and pfUI.env and pfUI.env.C and pfUI.env.C.tooltip and pfUI.env.C.tooltip.position == "cursor" then
		pfuiCursorMode = true
	end

	-- 设置提示的所有者和位置
	if pfuiCursorMode then
		-- pfUI 光标模式下，像 pfUI 一样使用 ANCHOR_CURSOR
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	else
		-- 相对于物品按钮的标准定位
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 10, 0)
	end

	-- 记录锚点信息，供 GameTooltip.Show 钩子重新断言位置。
	-- 某些插件（如装等/物品ID 插件，/itemid show）会在填充提示或
	-- Show 时把 GameTooltip 重新锚定到屏幕角落，导致提示固定显示在
	-- 右下角；钩子会在 Show 后按此信息把提示拉回物品按钮旁。
	GameTooltip.GudaAnchorButton = self
	GameTooltip.GudaCursorMode = pfuiCursorMode

    -- 邮箱提示处理
    if self.isMail then
        local currentPlayerName = addon.Modules.DB:GetPlayerFullName()
        local isMailboxOpen = addon.Modules.MailboxScanner and addon.Modules.MailboxScanner:IsMailboxOpen()
        
        if (not self.otherChar or self.otherChar == currentPlayerName) and self.mailIndex and isMailboxOpen then
            -- 当前角色的实时邮箱（仅当邮箱实际打开时）
            GameTooltip:SetInboxItem(self.mailIndex, self.mailItemIndex or 1)
        elseif self.itemData and (self.itemData.link or self.itemData.itemID) then
            -- 只读 / 其他角色的邮箱，或当前角色邮箱关闭时
            GameTooltip.GudaViewedCharacter = self.otherChar or currentPlayerName
            if self.itemData.link then
                GudaSetTooltipHyperlink(GameTooltip, self.itemData.link)
            else
                GameTooltip:SetHyperlink("item:" .. self.itemData.itemID .. ":0:0:0")
            end
        elseif self.itemData and self.itemData.name then
            -- 金钱或普通邮件
            GameTooltip:AddLine(self.itemData.name, 1, 1, 1)
        elseif self.mailData and self.mailData.money and self.mailData.money > 0 then
            -- 仅含金钱邮件的后备
            GameTooltip:AddLine(GudaBag.L["Money"], 1, 1, 1)
        end

        -- 可用时添加邮箱元数据
        local mailData = self.mailData
        
        if mailData then
            -- 如果已经添加了行（金钱/普通邮件），或 SetHyperlink/SetInboxItem
            -- 已添加行，则在添加发件人信息时可能需要一个分隔符。
            if GameTooltip:NumLines() > 0 then
                GameTooltip:AddLine(" ")
            end

            if mailData.sender then
                GameTooltip:AddLine((GudaBag.L["From:"] or "From:") .. " " .. mailData.sender, 1, 1, 1)
            end
            if mailData.subject then
                GameTooltip:AddLine((GudaBag.L["Subject:"] or "Subject:") .. " " .. mailData.subject, 1, 1, 0.8)
            end
            if (mailData.money or 0) > 0 and not (self.itemData and self.itemData.name == "Money") then
                GameTooltip:AddLine((GudaBag.L["Money"] or "Money") .. ": " .. addon.Modules.Utils:FormatMoney(mailData.money), 1, 1, 1)
            end
            if (mailData.CODAmount or 0) > 0 then
                GameTooltip:AddLine((GudaBag.L["COD:"] or "COD:") .. " " .. addon.Modules.Utils:FormatMoney(mailData.CODAmount), 1, 0, 0)
            end
            if mailData.daysLeft then
                GameTooltip:AddLine((GudaBag.L["Days left:"] or "Days left:") .. " " .. math.floor(mailData.daysLeft), 0.5, 0.5, 0.5)
            end
        end

        -- 在最底部为邮箱物品添加库存数量信息
        if addon.Modules.Tooltip and addon.Modules.Tooltip.AddInventoryInfo then
            local link = self.itemData and (self.itemData.link or (self.itemData.itemID and ("item:" .. self.itemData.itemID .. ":0:0:0")))
            if not link and self.mailIndex and isMailboxOpen then
                link = addon.Modules.Utils:GetInboxItemLink(self.mailIndex, self.mailItemIndex or 1)
            end
            if link then
                addon.Modules.Tooltip:AddInventoryInfo(GameTooltip, link)
            end
        end
        
        GameTooltip:Show()
        return
	elseif self.otherChar or self.isReadOnly then
		GameTooltip.GudaViewedCharacter = self.otherChar
		if self.itemData and self.itemData.link then
			local ok = pcall(GudaSetTooltipHyperlink, GameTooltip, self.itemData.link)
			if not ok then
				GameTooltip:Hide()
				return
			end
		else
			GameTooltip:Hide()
			return
		end
	-- 银行主背包的特殊处理，银行可能已关闭
	elseif self.isBank and self.bagID == -1 then
		local bankFrame = getglobal("BankFrame")
		if bankFrame and bankFrame:IsVisible() then
			-- 银行已打开 —— 使用 SetBagItem，将触发物品栏格子处理
			GameTooltip:SetBagItem(self.bagID, self.slotID)
		elseif self.itemData and self.itemData.link then
			-- 银行已关闭 —— 使用缓存链接
			GudaSetTooltipHyperlink(GameTooltip, self.itemData.link)
		end
	elseif self.bagID == -2 then
		-- 钥匙扣（背包 -2）：在 1.12 中原生 SetBagItem 通过内部调用
		-- SetHyperlink 并传入完整的彩色链接（|cff..|Hitem:..|h[Name]|h|r）
		-- 来构建钥匙扣提示。当其他插件（AtlasLoot, WoWTranslate）
		-- 以绕过 Guda 剥离钩子的顺序重新挂钩 SetHyperlink 时，那个完整
		-- 链接会到达一个捕获的原生函数是原始暴雪 SetHyperlink 的钩子 ——
		-- 它只接受 BARE "item:ID:0:0:0" 形式，否则抛出 "unknown link type"。
		-- 我们完全避免该内部路径，自己用裸形式调用 SetHyperlink
		--（GudaSetTooltipHyperlink 会提取它）。
		local link = GetContainerItemLink(self.bagID, self.slotID)
		if link then
			GudaSetTooltipHyperlink(GameTooltip, link)
		else
			GameTooltip:SetBagItem(self.bagID, self.slotID)
		end
	else
		-- 实时模式：对所有背包使用 SetBagItem
		GameTooltip:SetBagItem(self.bagID, self.slotID)
	end

	GameTooltip:Show()

	-- 通知第三方提示插件（例如 GFW_DisenchantPredictor、EnhTooltip）
	-- 这些插件挂钩 ContainerFrameItemButton_OnEnter，而 Guda 的自定义按钮绕过了它
	if self.bagID and self.slotID and not self.otherChar and not self.isReadOnly then
		local link = GetContainerItemLink(self.bagID, self.slotID)
		if link then
			local _, _, itemLink = string.find(link, "(item:%d+:%d+:%d+:%d+)")
			if itemLink then
				local itemName = GetItemInfo(itemLink)
				-- GFWTooltip 回调系统
				if GFWTooltip_Callbacks then
					GameTooltip.gfwDone = nil  -- 重置，以免回调被跳过
					for modName, callback in pairs(GFWTooltip_Callbacks) do
						if type(callback) == "function" then
							callback(GameTooltip, itemName, link, "CONTAINER")
						end
					end
					GameTooltip:Show()
				end
				-- EnhTooltip 回调系统
				if EnhTooltip and EnhTooltip.TooltipCall then
					EnhTooltip.TooltipCall(GameTooltip, itemName, link, nil, nil, self.bagID, self.slotID)
					GameTooltip:Show()
				end
			end
		end
	end

	-- 调试：当调试模式激活时，将物品分类信息打印到聊天框
	if addon.DEBUG and self.hasItem and self.bagID and self.slotID and not self._debugPrinted then
		local link = self.itemData and self.itemData.link or GetContainerItemLink(self.bagID, self.slotID)
		if link then
			local itemID = addon.Modules.Utils:ExtractItemID(link)
			if itemID then
				local itemName, _, itemRarity, itemLevel, itemCategory, itemType, _, itemSubType = GetItemInfo(itemID)
				addon:Debug("Item: %s (ID: %s)", tostring(itemName), tostring(itemID))
				addon:Debug("  Category: %s | Type: %s | SubType: %s", tostring(itemCategory), tostring(itemType), tostring(itemSubType))
				addon:Debug("  Quality: %s | iLvl: %s", tostring(itemRarity), tostring(itemLevel))
				if addon.Modules.ItemDetection then
					local props = addon.Modules.ItemDetection:GetItemProperties({link = link}, self.bagID, self.slotID)
					local flags = {}
					if props.isQuestItem then table.insert(flags, "Quest") end
					if props.isQuestStarter then table.insert(flags, "Starter") end
					if props.isQuestUsable then table.insert(flags, "Usable") end
					if props.isJunk then table.insert(flags, "Junk") end
					if props.isPermanentEnchant then table.insert(flags, "Enchant") end
					if props.isUnusable then table.insert(flags, "Unusable") end
					local flagStr = table.getn(flags) > 0 and table.concat(flags, ", ") or "none"
					addon:Debug("  Flags: %s", flagStr)
				end
				self._debugPrinted = true
			end
		end
	end

    -- 处理商人出售光标
	if MerchantFrame:IsShown() and not self.isBank and not self.otherChar and self.hasItem then
		ShowContainerSellCursor(self.bagID, self.slotID)
	else
		ResetCursor()
	end
end


-- OnLeave 处理器
function GudaBag.ItemButton_OnLeave(self)
    -- 延迟隐藏投放指示器，允许鼠标移动到指示器框架
    if activeCategoryDropIndicator == self and categoryDropIndicator and categoryDropIndicator:IsShown() then
        -- 使用池化计时器检查鼠标是否已移动到指示器（避免框架泄漏）
        GudaBag.ScheduleTimer(0.05, function()
            -- 如果鼠标悬停在指示器上，则不隐藏
            if categoryDropIndicator and categoryDropIndicator:IsMouseOver() then
                return
            end
            -- 如果鼠标悬停在父按钮上，则不隐藏
            if activeCategoryDropIndicator and MouseIsOver(activeCategoryDropIndicator) then
                return
            end
            HideCategoryDropIndicator()
        end)
    else
        HideCategoryDropIndicator()
    end
    self._debugPrinted = nil
    -- 离开时清除提示上任何已查看角色的提示信息
    if GameTooltip then
        GameTooltip.GudaViewedCharacter = nil
        GameTooltip.GudaAnchorButton = nil
        GameTooltip.GudaCursorMode = nil
    end
    GameTooltip:Hide()
    ResetCursor()

    -- 清除背包按钮高亮
    if not self.otherChar then
        if self.isBank then
            GudaBag.BankFrame_ClearBagButtonHighlight()
        else
            GudaBag.BagFrame_ClearBagButtonHighlight()
        end
    end
end
