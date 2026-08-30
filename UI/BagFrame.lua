-- Guda 背包框架
-- 主背包查看界面

local addon = Guda

-- 前置声明（稍后在背包槽位处理函数附近定义）
local Guda_TryEquipBagOnSlot

local BagFrame = {}
addon.Modules.BagFrame = BagFrame

-- 使用集中式框架辅助函数处理分区标题和背包父框架
function BagFrame:GetSectionHeader(index)
    return GudaBag.GetSectionHeader("Guda_BagFrame", "Guda_BagFrame_ItemContainer", index)
end

function BagFrame:GetBagParent(bagID)
    return GudaBag.GetBagParent("Guda_BagFrame", bagParents, bagID, "Guda_BagFrame_ItemContainer")
end

local currentViewChar = nil -- nil = 当前角色
function BagFrame:GetCurrentViewChar()
    return currentViewChar
end
local searchText = ""
local itemButtons = {}
local slotToButton = {} -- 快速 O(1) 查找：slotToButton[bagID][slotID] = button
local showKeyring = false -- 钥匙链显示开关
local activeQuality = nil -- 品质过滤（nil = 不过滤），移植自 OneBag 品质模块
local activeCategory = nil -- 分类过滤（nil = 不过滤），移植自 OneBag 分类模块

-- 跟踪在分类视图中应显示为占位符的空槽位
-- 格式：bagRecentlyEmptiedSlots[bagID][slotID] = { category = "CategoryName", timestamp = time, ... }
local bagRecentlyEmptiedSlots = {}

function BagFrame:ClearRecentlyEmptiedSlots()
    for k in pairs(bagRecentlyEmptiedSlots) do
        bagRecentlyEmptiedSlots[k] = nil
    end
end

function BagFrame:MarkSlotAsEmptied(bagID, slotID, category, itemData)
    if not bagRecentlyEmptiedSlots[bagID] then
        bagRecentlyEmptiedSlots[bagID] = {}
    end
    bagRecentlyEmptiedSlots[bagID][slotID] = {
        category = category or "Miscellaneous",
        timestamp = GetTime(),
        quality = itemData and itemData.quality or 0,
        name = itemData and itemData.name or "",
        iLevel = itemData and itemData.iLevel or 0,
    }
    addon:DebugCategory("BagFrame: Marked slot %d:%d as emptied (category: %s)", bagID, slotID, category or "Miscellaneous")
end

function BagFrame:UnmarkSlotAsEmptied(bagID, slotID)
    if bagRecentlyEmptiedSlots[bagID] then
        bagRecentlyEmptiedSlots[bagID][slotID] = nil
    end
end
local showSoulBag = false -- 灵魂袋显示开关
local hiddenBags = {} -- 跟踪哪些背包被隐藏（bagID -> true/false）
local bagParents = {} -- 每个背包的父框架，用于为暴雪物品按钮模板携带 bagID
local isMerchantOpen = false -- 跟踪商贩窗口当前是否打开，防止自动关闭背包
local isDragging = false  -- 当光标携带着物品且背包在分类视图中打开时为 true
local isFrameMoving = false  -- 在背包框架上 StartMoving 与 StopMovingOrSizing 之间为 true

function BagFrame:IsDragging()
    return isDragging
end

function BagFrame:IsFrameMoving()
    return isFrameMoving
end

-- 由 ItemButton.lua 中的光标监视器在 CURSOR_UPDATE 边界处调用。
-- 切换拖拽标志并触发重绘，使分类视图中的空分类放置目标
-- 能够随之出现/消失。
function BagFrame:SetDragging(state)
    state = state and true or false
    if isDragging == state then return end
    isDragging = state
    if Guda_BagFrame and Guda_BagFrame:IsShown() then
        BagFrame:Update()
    end
end

-- 用于清除搜索焦点的全局点击捕获器
local clickCatcher = nil

--=====================================================
-- 延迟可用性着色系统
-- 防止背包打开时物品数据未完全加载导致的误判
-- 使用防抖机制安全处理快速开/关背包的情况
--=====================================================
local usabilityCheckFrame = nil
local USABILITY_CHECK_DELAY = 0.25 -- 重新检查可用性之前的延迟（秒）

-- 取消任何待处理的延迟可用性检查
local function CancelDeferredUsabilityCheck()
    if usabilityCheckFrame then
        usabilityCheckFrame:Hide()
        usabilityCheckFrame.pending = false
    end
end

-- 更新所有可见物品按钮的可用性着色 —— 仅使用缓存。
-- 对未缓存的物品执行每次 SetBagItem 提示扫描都可能阻塞 50-500ms，因此我们
-- 绝不会在打开背包的路径中触发扫描。着色只会出现在
-- 已缓存的物品上；未缓存的物品保持不着色，直到 CacheWarmer
-- 将其填充（它的 BagFrame 钩子在完成后会触发一次重新扫描）。
function GudaBag.BagFrame_UpdateAllUsabilityTints()
    if not Guda_BagFrame or not Guda_BagFrame:IsShown() then return end
    if isFrameMoving then return end

    for _, bagParent in pairs(bagParents) do
        if bagParent and bagParent.itemButtons then
            for button in pairs(bagParent.itemButtons) do
                if button.hasItem and button:IsShown() and GudaBag.ItemButton_UpdateUsableTint then
                    GudaBag.ItemButton_UpdateUsableTint(button, true)  -- 仅缓存
                end
            end
        end
    end
end

local UpdateAllUsabilityTints = GudaBag.BagFrame_UpdateAllUsabilityTints

-- 使用防抖机制调度延迟可用性检查
local function ScheduleDeferredUsabilityCheck()
    -- 首次使用时创建框架
    if not usabilityCheckFrame then
        usabilityCheckFrame = CreateFrame("Frame")
        usabilityCheckFrame:Hide()
        usabilityCheckFrame.elapsed = 0
        usabilityCheckFrame.pending = false
        usabilityCheckFrame:SetScript("OnUpdate", function()
            -- 用户拖动框架时，将计时器保持在当前 elapsed 值上暂停。
            -- 在拖动期间恢复倒计时，会在引擎帧时间紧张时
            -- 立即触发约 80 次同步提示扫描，
            -- 造成持续数秒的假性冻结。
            if isFrameMoving then return end
            this.elapsed = this.elapsed + arg1
            if this.elapsed >= USABILITY_CHECK_DELAY then
                this:Hide()
                this.pending = false
                -- 仅当背包仍然打开时才运行。
                -- 注意：我们有意不在此处调用 ClearCache。GetItemProperties
                -- 已经拒绝缓存不完整的提示扫描
                --（ItemDetection 中的 tooltipLooksComplete 守卫），因此重新扫描
                -- 自然会使首次扫描不完整的物品被重新命中，同时保留完好的缓存条目
                -- —— 清空缓存会破坏 CacheWarmer，
                -- 并迫使每次打开背包都触发一次完整的约 80 件物品的提示扫描。
                if Guda_BagFrame and Guda_BagFrame:IsShown() then
                    UpdateAllUsabilityTints()
                end
            end
        end)
    end

    -- 重置计时器（防抖行为）
    usabilityCheckFrame.elapsed = 0
    usabilityCheckFrame.pending = true
    usabilityCheckFrame:Show()
end

-- 加载时（OnLoad）
function GudaBag.BagFrame_OnLoad(self)
    -- 防止框架被拖出屏幕
    self:SetClampedToScreen(true)

    -- 设置初始背景
    addon:ApplyBackdrop(self, "DEFAULT_FRAME")

    -- 注册拖放接收：背包框架与物品容器需 RegisterForDrag 才能收到
    -- OnReceiveDrag（把光标物品拖到空白处时放入背包第一个空位）。
    if self.RegisterForDrag then
        self:RegisterForDrag("LeftButton")
    end
    local itemContainer = getglobal("Guda_BagFrame_ItemContainer")
    if itemContainer and itemContainer.RegisterForDrag then
        itemContainer:RegisterForDrag("LeftButton")
    end

-- 设置搜索框占位文本
	local searchBox = getglobal(self:GetName().."_SearchBar_SearchBox")
	if searchBox then
		searchBox:SetText(GudaBag.L["Search, try ~equipment"])
		searchBox:SetTextColor(0.5, 0.5, 0.5, 1)
	end

	-- 创建不可见的全屏框架，用于捕获背包外部的点击
	if not clickCatcher then
		clickCatcher = CreateFrame("Frame", "Guda_ClickCatcher", UIParent)
		clickCatcher:SetFrameStrata("BACKGROUND")
		clickCatcher:SetAllPoints(UIParent)
		clickCatcher:EnableMouse(true)
		clickCatcher:Hide()

		clickCatcher:SetScript("OnMouseDown", function()
			GudaBag.BagFrame_ClearSearch()
		end)
	end

end


-- 显示时（OnShow）
function GudaBag.BagFrame_OnShow(self)
	-- 播放背包打开音效
	PlaySound("igBackPackOpen")

-- 打开背包时保存背包数据
	addon.Modules.BagScanner:SaveToDatabase()
	addon.Modules.MoneyTracker:Update()

	-- 如果存在已保存的位置则恢复（仅当保存为 BOTTOMRIGHT 时）
	if addon and addon.Modules and addon.Modules.DB then
		local pos = addon.Modules.DB:GetSetting("bagFramePosition")
		if pos and pos.point == "BOTTOMRIGHT" and pos.x and pos.y then
			self:ClearAllPoints()
			self:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", pos.x, pos.y)
		end
	end

	-- 框架显示时设置锁定状态（确保所有子框架都已加载）
	if BagFrame.UpdateLockState then
		BagFrame:UpdateLockState()
	end

	-- 应用边框可见性设置
	if BagFrame.UpdateBorderVisibility then
		BagFrame:UpdateBorderVisibility()
	end

	-- 应用搜索栏可见性设置。在 toggle 模式下总是以折叠状态开始，
	-- 这样打开背包时不会残留过期的过滤状态。
	BagFrame.searchBarExpanded = false
	if BagFrame.UpdateSearchBarVisibility then
		BagFrame:UpdateSearchBarVisibility()
	end

	-- 创建并显示品质过滤栏（位于搜索框上一行）
	if BagFrame.CreateQualityBar then
		BagFrame:CreateQualityBar()
	end
	BagFrame:UpdateQualityBarVisibility()
	if BagFrame.UpdateQualityBarButtons then
		BagFrame:UpdateQualityBarButtons()
	end

	-- 创建并显示分类过滤侧栏（移植自 OneBag 分类模块）
	if BagFrame.UpdateCategoryBarVisibility then
		BagFrame:UpdateCategoryBarVisibility()
	end

	-- 应用底部栏可见性设置
	if BagFrame.UpdateFooterVisibility then
		BagFrame:UpdateFooterVisibility()
	end

	-- 应用框架透明度
	if GudaBag.ApplyBackgroundTransparency then
		GudaBag.ApplyBackgroundTransparency()
	end

	BagFrame:Update()

	-- 调度延迟可用性检查，修复未缓存物品数据导致的误判
	-- 该检查会在物品信息被 WoW 客户端完全加载后延迟一小段时间运行
	ScheduleDeferredUsabilityCheck()
end

-- 隐藏时（OnHide）
function GudaBag.BagFrame_OnHide(self)
	-- 播放背包关闭音效
	PlaySound("igBackPackClose")

	-- 背包框架隐藏时关闭任何打开的下拉菜单
	CloseDropDownMenus()

	-- 隐藏背包弹出层
	BagFrame:HideBagFlyout()

	-- 隐藏提示框（它可能正显示在灵魂袋或其他底部按钮上）
	GameTooltip:Hide()

    -- 清空搜索字段
    GudaBag.BagFrame_ClearSearch()

    -- 隐藏品质过滤栏（过滤状态保持，与 OneBag 一致；重新打开时继续生效）
    local qualityBar = getglobal("Guda_BagFrame_QualityBar")
    if qualityBar then qualityBar:Hide() end

    -- 隐藏分类过滤侧栏（过滤状态保持）
    local categoryBar = getglobal("Guda_BagFrame_CategoryBar")
    if categoryBar then categoryBar:Hide() end

    -- 清空任何待处理的更新和工作队列项
    pendingUpdate = false
    if addon.Modules.Utils and addon.Modules.Utils.ClearWorkQueue then
        addon.Modules.Utils:ClearWorkQueue()
    end

    -- 取消任何待处理的限流更新
    local throttleFrame = getglobal("Guda_BagUpdateThrottle")
    if throttleFrame then
        throttleFrame:Hide()
    end

    -- 取消任何待处理的延迟可用性检查（防抖安全）
    CancelDeferredUsabilityCheck()

    -- 清空最近清空槽位跟踪（重置占位符）
    BagFrame:ClearRecentlyEmptiedSlots()

    -- 重置自动补位标记：下次打开背包时重新执行 autoFillRows 补位
    BagFrame.bagAutoFilledThisSession = false
    BagFrame.autoFillCategoryOrder = nil

	-- 框架隐藏时清理所有按钮（不显示时这样做是安全的）
	-- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
	for _, bagParent in pairs(bagParents) do
		if bagParent and bagParent.itemButtons then
			for button in pairs(bagParent.itemButtons) do
				if button.hasItem ~= nil then
					button:Hide()
					button:ClearAllPoints()
				end
			end
		end
	end
end

-- 切换可见性
function BagFrame:Toggle()
	if Guda_BagFrame:IsShown() then
		Guda_BagFrame:Hide()
	else
		Guda_BagFrame:Show()
	end
end

-- 显示指定角色的背包
function BagFrame:ShowCharacter(fullName)
	currentViewChar = fullName
	self:Update()
end

-- 显示当前角色
function BagFrame:ShowCurrentCharacter()
	currentViewChar = nil
	self:Update()
end

-- 更新现有按钮的锁定状态（轻量，用于拖动期间）
function BagFrame:UpdateLockStates()
    GudaBag.UpdateLockStates(bagParents)
end

-- 排序/重整理期间隐藏所有物品按钮（提高帧数）。供 SortEngine 调用。
function GudaBag.BagFrame_HideAllItemButtons()
    GudaBag.HideItemButtons(bagParents)
end

-- 恢复被隐藏的物品按钮（排序结束后由 Update() 重建亦可，此函数供需要时直接恢复）
function GudaBag.BagFrame_ShowAllItemButtons()
    GudaBag.ShowItemButtons(bagParents)
end

-- 不进行完整框架重绘地更新单个槽位（用于手动移动物品）
-- 成功返回 true，需要完整重绘返回 false
function BagFrame:UpdateSingleSlot(bagID, slotID, passedButton)
    if not Guda_BagFrame:IsShown() then return false end
    if currentViewChar then return false end  -- 无法为其他角色执行单槽位更新

    -- 若可用则使用传入的按钮（来自 UpdateChangedSlots 迭代）
    -- 这避免了槽位 ID 键的类型不匹配问题（字符串 vs 数字）
    local targetButton = passedButton

    if not targetButton then
        -- 回退方案：使用查找表找到此槽位的按钮
        if slotToButton[bagID] then
            -- 同时尝试数字键和字符串键以处理类型不匹配
            targetButton = slotToButton[bagID][slotID] or slotToButton[bagID][tonumber(slotID)]
        end
        -- 最终回退：搜索 itemButtons 数组
        if not targetButton then
            for _, button in ipairs(itemButtons) do
                if button.bagID == bagID and button.slotID == slotID then
                    targetButton = button
                    break
                end
            end
        end
    end

    if not targetButton then return false end

    -- 获取此槽位的最新物品数据
    local itemLink = GetContainerItemLink(bagID, slotID)
    local itemData = nil

    if itemLink then
        local texture, itemCount, locked, slotQuality = GetContainerItemInfo(bagID, slotID)
        local itemID = nil
        local _, _, idStr = string.find(itemLink, "item:(%d+)")
        if idStr then itemID = tonumber(idStr) end

        if itemID then
            local name, link, quality, iLevel, itemCategory, _, stackCount, subType, _, equipLoc = GetItemInfo(itemID)
            itemData = {
                link = itemLink,
                texture = texture,
                count = itemCount or 1,
                quality = quality or slotQuality or 0,
                name = name,
                iLevel = iLevel,
                -- Turtle WoW 的 GetItemInfo 在第 5 位返回物品类别
                -- （第 6 位是子类型，而非类别）。将类别归一化
                -- 为英文，以便 CategorizeItem 在 zhCN 客户端上正确匹配。
                class = addon.Modules.Utils:NormalizeItemClass(itemCategory),
                subclass = subType,
                equipLoc = equipLoc,
                stackSize = stackCount or 1,
                locked = locked,
            }
        end
    end

    -- 更新按钮
    local matchesFilter = self:PassesSearchFilter(itemData)
    GudaBag.ItemButton_SetItem(targetButton, bagID, slotID, itemData, false, nil, matchesFilter, false)

    return true
end

-- 通过与缓存数据比较来更新背包中发生变化的槽位
-- 返回已更新的槽位数，需要完整重绘时返回 -1
function BagFrame:UpdateChangedSlots(bagID)
    if not Guda_BagFrame:IsShown() then return -1 end
    if currentViewChar then return -1 end

    -- 检查此背包是否已有槽位查找表
    if not slotToButton[bagID] then return -1 end

    local viewType = addon.Modules.DB:GetSetting("bagViewType") or "single"
    local isCategoryView = (viewType == "category")

    if isCategoryView then
        -- 分类视图中：就地更新已有按钮映射的槽位
        -- 并检查是否有新物品出现在没有按钮的槽位中
        local updatedCount = 0
        for slotID, targetButton in pairs(slotToButton[bagID]) do
            local currentLink = GetContainerItemLink(bagID, slotID)
            local cachedLink = targetButton.itemData and targetButton.itemData.link or nil

            local needsUpdate = false
            if currentLink ~= cachedLink then
                needsUpdate = true
            elseif currentLink then
                local _, currentCount = GetContainerItemInfo(bagID, slotID)
                local cachedCount = targetButton.itemData and targetButton.itemData.count or 0
                if currentCount ~= cachedCount then
                    needsUpdate = true
                end
            end

            if needsUpdate then
                addon:DebugCategory("  bag %d slot %d: needs update (had=%s, now=%s)", bagID, slotID,
                    cachedLink and "item" or "empty", currentLink and "item" or "empty")
                if self:UpdateSingleSlot(bagID, slotID, targetButton) then
                    updatedCount = updatedCount + 1
                else
                    addon:DebugCategory("  bag %d slot %d: UpdateSingleSlot failed -> full redraw", bagID, slotID)
                    return -1
                end
            end
        end

        -- 关键：检查是否有新物品出现在没有按钮映射的槽位中
        -- 分类视图只为已填充的槽位创建按钮，因此新物品需要完整重绘
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for checkSlotID = 1, numSlots do
                local hasButton = slotToButton[bagID][checkSlotID] or slotToButton[bagID][tostring(checkSlotID)]
                if not hasButton then
                    local currentLink = GetContainerItemLink(bagID, checkSlotID)
                    if currentLink then
                        addon:DebugCategory("  bag %d slot %d: NEW item arrived (no button) -> full redraw", bagID, checkSlotID)
                        return -1  -- 触发完整重绘以对新物品进行分类
                    end
                end
            end
        end

        addon:DebugCategory("UpdateChangedSlots (category): bag=%d, success, updated %d slots", bagID, updatedCount)
        return updatedCount
    elseif not isCategoryView then
        -- 单视图：检查所有槽位
        local numSlots = GetContainerNumSlots(bagID)
        if not numSlots or numSlots == 0 then return -1 end

        local updatedCount = 0
        for slotID = 1, numSlots do
            -- 同时尝试数字键和字符串键以处理类型不匹配
            local targetButton = slotToButton[bagID][slotID] or slotToButton[bagID][tostring(slotID)]

            if not targetButton then
                return -1
            end

            local currentLink = GetContainerItemLink(bagID, slotID)
            local cachedLink = targetButton.itemData and targetButton.itemData.link or nil

            local needsUpdate = false
            if currentLink ~= cachedLink then
                needsUpdate = true
            elseif currentLink then
                local _, currentCount = GetContainerItemInfo(bagID, slotID)
                local cachedCount = targetButton.itemData and targetButton.itemData.count or 0
                if currentCount ~= cachedCount then
                    needsUpdate = true
                end
            end

            if needsUpdate then
                -- 直接传入按钮以避免类型不匹配查找问题
                if self:UpdateSingleSlot(bagID, slotID, targetButton) then
                    updatedCount = updatedCount + 1
                else
                    return -1
                end
            end
        end
        return updatedCount
    end
end

-- 背包弹出层状态
local bagFlyout = nil
local bagFlyoutExpanded = false

-- 为背包 1-4 创建弹出层框架
local function CreateBagFlyout(parent)
	if bagFlyout then return bagFlyout end

	local flyout = CreateFrame("Frame", "Guda_BagFlyout", parent)
	flyout:SetFrameStrata("DIALOG")
	flyout:SetFrameLevel(150)

	local slotSize = 32
	local padding = 4
	local numBags = 4
	flyout:SetWidth(slotSize + padding * 2)
	flyout:SetHeight(slotSize * numBags + padding * 2)

	flyout:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	flyout:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
	flyout:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)

	flyout:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", -15, -9)
	flyout:EnableMouse(true)
	flyout:Hide()

	-- 在弹出层内创建 4 个背包槽位按钮（背包 1-4，从下往上堆叠）
	flyout.bagSlots = {}
	for i = 1, numBags do
		local bagID = i
		local btn = CreateFrame("Button", "Guda_BagFlyout_Slot" .. i, flyout, "ItemButtonTemplate")
		btn:SetWidth(slotSize)
		btn:SetHeight(slotSize)

		if i == 1 then
			btn:SetPoint("BOTTOM", flyout, "BOTTOM", 0, padding)
		else
			btn:SetPoint("BOTTOM", flyout.bagSlots[i - 1], "TOP", 0, 0)
		end

		btn.bagID = bagID
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		-- 隐藏模板边框
		local normalTex = getglobal(btn:GetName() .. "NormalTexture")
		if normalTex then normalTex:SetTexture(nil); normalTex:Hide() end
		local iconBorder = getglobal(btn:GetName() .. "IconBorder")
		if iconBorder then iconBorder:Hide() end

		-- 应用底部按钮背景样式
		GudaBag.BagSlot_ApplyBackdrop(btn)

		-- 注册拖拽（装备背包）
		btn:RegisterForDrag("LeftButton")
		btn:SetScript("OnDragStart", function()
			GudaBag.BagSlot_OnDragStart(this, this.bagID)
		end)
		btn:SetScript("OnDragStop", function()
			GudaBag.BagSlot_OnDragStop(this, this.bagID)
		end)

		btn:SetScript("OnClick", function()
			GudaBag.BagSlot_OnClick(this, this.bagID)
		end)
		btn:SetScript("OnEnter", function()
			GudaBag.BagSlot_OnEnter(this, this.bagID)
		end)
		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
			GudaBag.BagFrame_ClearHighlightedSlots()
			GudaBag.BagSlot_OnLeave(this, this.bagID)
		end)

		-- 注册背包更新事件
		btn:RegisterEvent("BAG_UPDATE")
		btn:RegisterEvent("ITEM_LOCK_CHANGED")
		btn:RegisterEvent("CURSOR_UPDATE")
		btn:RegisterEvent("UNIT_INVENTORY_CHANGED")
		btn:SetScript("OnEvent", function()
			GudaBag.BagSlot_OnEvent(this, event, arg1)
		end)

		-- 接受拖放
		btn:SetScript("OnReceiveDrag", function()
			if this and this.bagID and this.bagID ~= 0 and CursorHasItem and CursorHasItem() then
				local inv = ContainerIDToInventoryID(this.bagID)
				Guda_TryEquipBagOnSlot(this.bagID, inv, this)
			end
		end)

		flyout.bagSlots[i] = btn
	end

	bagFlyout = flyout
	return flyout
end

-- 更新弹出层的背包槽位贴图
local function UpdateBagFlyout()
	if not bagFlyout then return end
	for i, btn in ipairs(bagFlyout.bagSlots) do
		GudaBag.BagSlot_Update(btn, btn.bagID)
	end
end

-- 切换背包弹出层
function BagFrame:ToggleBagFlyout()
	local bag0 = getglobal("Guda_BagFrame_Toolbar_BagSlot0")
	if not bag0 then return end

	if not bagFlyout then
		CreateBagFlyout(bag0)
	end

	bagFlyoutExpanded = not bagFlyoutExpanded

	if bagFlyoutExpanded then
		UpdateBagFlyout()
		bagFlyout:Show()
		-- 激活时使用金色边框
		bag0:SetBackdropBorderColor(1, 0.82, 0, 1)
	else
		bagFlyout:Hide()
		-- 非激活时恢复主题边框
		local fb = addon.Modules.Theme:GetValue("footerButtonBorder") or { 0.30, 0.30, 0.30, 1 }
		bag0:SetBackdropBorderColor(fb[1], fb[2], fb[3], fb[4])
	end
end

-- 隐藏背包弹出层（框架关闭等时使用）
function BagFrame:HideBagFlyout()
	bagFlyoutExpanded = false
	if bagFlyout then bagFlyout:Hide() end
	-- 恢复 bag0 的主题边框
	local bag0 = getglobal("Guda_BagFrame_Toolbar_BagSlot0")
	if bag0 then
		local fb = addon.Modules.Theme:GetValue("footerButtonBorder") or { 0.30, 0.30, 0.30, 1 }
		bag0:SetBackdropBorderColor(fb[1], fb[2], fb[3], fb[4])
	end
end

-- 更新背包栏布局
function BagFrame:UpdateBaglineLayout()
	local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
	local toolbar = getglobal("Guda_BagFrame_Toolbar")
	if not toolbar then return end

	if hideFooter then
		toolbar:Hide()
		return
	end

	local hideBagline = addon.Modules.DB:GetSetting("hideBagline")

	local bag0 = getglobal("Guda_BagFrame_Toolbar_BagSlot0")
	local bag1 = getglobal("Guda_BagFrame_Toolbar_BagSlot1")
	local bag2 = getglobal("Guda_BagFrame_Toolbar_BagSlot2")
	local bag3 = getglobal("Guda_BagFrame_Toolbar_BagSlot3")
	local bag4 = getglobal("Guda_BagFrame_Toolbar_BagSlot4")
	local keyring = getglobal("Guda_BagFrame_Toolbar_KeyringButton")
	local soulbag = getglobal("Guda_BagFrame_Toolbar_SoulBagButton")
	local info = getglobal("Guda_BagFrame_Toolbar_BagSlotsInfo")
	local hearthstone = getglobal("Guda_BagFrame_HearthstoneFrame")

	-- 确定信息锚点所用的最后一个可见特殊按钮
	local lastButton = keyring
	if soulbag and soulbag:IsShown() then
		lastButton = soulbag
	end

	-- 根据背包栏设置更新背包贴图
	if bag0 then
		if hideBagline then
			SetItemButtonTexture(bag0, "Interface\\AddOns\\Guda\\Assets\\bags")
		else
			SetItemButtonTexture(bag0, "Interface\\Buttons\\Button-Backpack-Up")
		end
	end

	if hideBagline then
		-- 隐藏背包 1-4，仅显示 bag0 + keyring + soulbag
		if bag1 then bag1:Hide() end
		if bag2 then bag2:Hide() end
		if bag3 then bag3:Hide() end
		if bag4 then bag4:Hide() end

		-- 将钥匙链锚定到 bag0 旁边
		if keyring and bag0 then
			keyring:ClearAllPoints()
			keyring:SetPoint("LEFT", bag0, "RIGHT", 2, 0)
		end

		-- 将灵魂袋锚定到钥匙链旁边
		if soulbag and soulbag:IsShown() then
			soulbag:ClearAllPoints()
			soulbag:SetPoint("LEFT", keyring, "RIGHT", 2, 0)
		end

		-- 将信息文本锚定到最后一个按钮旁边
		if info then
			info:Show()
			info:ClearAllPoints()
			info:SetPoint("LEFT", lastButton, "RIGHT", 8, 0)
		end

		-- 将炉石锚定到信息文本旁边
		if hearthstone then
			hearthstone:ClearAllPoints()
			hearthstone:SetPoint("LEFT", info, "RIGHT", 6, 0)
		end
	else
		-- 标准水平布局 —— 所有背包都可见
		if bag1 then
			bag1:Show()
			bag1:ClearAllPoints()
			bag1:SetPoint("LEFT", bag0, "RIGHT", 2, 0)
		end
		if bag2 then
			bag2:Show()
			bag2:ClearAllPoints()
			bag2:SetPoint("LEFT", bag1, "RIGHT", 2, 0)
		end
		if bag3 then
			bag3:Show()
			bag3:ClearAllPoints()
			bag3:SetPoint("LEFT", bag2, "RIGHT", 2, 0)
		end
		if bag4 then
			bag4:Show()
			bag4:ClearAllPoints()
			bag4:SetPoint("LEFT", bag3, "RIGHT", 2, 0)
		end
		if keyring then
			keyring:Show()
			keyring:ClearAllPoints()
			keyring:SetPoint("LEFT", bag4, "RIGHT", 2, 0)
		end
		-- 将灵魂袋锚定到钥匙链旁边
		if soulbag and soulbag:IsShown() then
			soulbag:ClearAllPoints()
			soulbag:SetPoint("LEFT", keyring, "RIGHT", 2, 0)
		end
		if info then
			info:Show()
			info:ClearAllPoints()
			info:SetPoint("LEFT", lastButton, "RIGHT", 8, 0)
		end

		-- 将炉石锚定到信息文本旁边
		if hearthstone then
			hearthstone:ClearAllPoints()
			hearthstone:SetPoint("LEFT", info, "RIGHT", 6, 0)
		end

		-- 切换到完整背包栏时隐藏弹出层
		self:HideBagFlyout()
	end

	-- 更新灵魂碎片数量
	GudaBag.BagFrame_UpdateSoulBagCount()
end

-- 用于帧预算的延迟更新状态
local pendingUpdate = false
local updateDebounceFrame = nil
local UPDATE_DEBOUNCE_TIME = 0.05  -- 快速更新的 50ms 防抖

-- 使用防抖调度更新（防止短时间内连续多次更新）
function BagFrame:ScheduleUpdate()
    if pendingUpdate then return end
    pendingUpdate = true

    if not updateDebounceFrame then
        updateDebounceFrame = CreateFrame("Frame")
        updateDebounceFrame.elapsed = 0
    end

    updateDebounceFrame.elapsed = 0
    updateDebounceFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= UPDATE_DEBOUNCE_TIME then
            this:SetScript("OnUpdate", nil)
            pendingUpdate = false
            BagFrame:Update()
        end
    end)
end

-- 更新显示
function BagFrame:Update()
	if not Guda_BagFrame:IsShown() then
		return
	end

	-- 整理排序进行中：跳过完整的分类重建（排序引擎已隐藏全部物品按钮
	-- 以提升帧率；重建会重新显示按钮并拖慢排序）。排序结束由
	-- finishSort 调用 Update() 恢复。
	if addon.Modules and addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then
		return
	end

	-- 换包进行中：跳过完整的分类重建（BagReplacer 已隐藏全部物品按钮
	-- 以提升帧率；换包期间的 BAG_UPDATE 会频繁触发 Update，重建会重新
	-- 显示按钮并拖慢换包）。换包结束由 FinalizeReplacement/Abort 调用
	-- Update() 恢复。
	if addon.Modules and addon.Modules.BagReplacer and addon.Modules.BagReplacer.inProgress then
		return
	end

	-- 框架正被拖拽移动：跳过完整的分类重建
	-- （满背包时可能耗时约 100ms 以上，且发生在原生 StartMoving 循环内，
	-- 造成持续数秒的假性冻结）。改为廉价地刷新锁定状态；
	-- EndFrameMove 会在放下时执行一次重建，
	-- 以补上拖动期间发生的任何变化。
	if isFrameMoving then
		self:UpdateLockStates()
		return
	end

	local viewType = addon.Modules.DB:GetSetting("bagViewType") or "single"
	addon:DebugCategory("Update() START: viewType=%s", viewType)

    -- 为帧预算跟踪记录入口
    if addon.Modules.Utils and addon.Modules.Utils.ReportEntry then
        addon.Modules.Utils:ReportEntry()
    end

	-- 如果光标正拿着物品（拖拽中），只更新锁定状态，不重建 UI
	-- 但仅当已显示物品时才这样 —— 否则仍需要进行首次构建。
	-- 例外：在分类视图中我们确实需要完整重建，以便空分类的
	-- 放置目标能随拖拽状态一起出现/消失。
	if CursorHasItem and CursorHasItem() then
		local inCategoryView = viewType == "category"
		-- 检查是否已显示任何物品
		-- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
		local hasDisplayedItems = false
		for _, bagParent in pairs(bagParents) do
			if bagParent and bagParent.itemButtons then
				for button in pairs(bagParent.itemButtons) do
					if button.hasItem and button:IsShown() then
						hasDisplayedItems = true
						break
					end
				end
			end
			if hasDisplayedItems then break end
		end

		if hasDisplayedItems and not inCategoryView then
			self:UpdateLockStates()
			return
		end
		-- 如果没有显示任何物品，或处于分类视图（放置目标
		-- 占位符需要渲染），则继续完整更新
	end

	-- 将所有现有按钮标记为未使用（显示过程中会把活跃的标记回来）
	-- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
	local totalButtonsBefore = 0
	local shownButtonsBefore = 0
	for _, bagParent in pairs(bagParents) do
		if bagParent and bagParent.itemButtons then
			for button in pairs(bagParent.itemButtons) do
				if button.hasItem ~= nil then
					totalButtonsBefore = totalButtonsBefore + 1
					if button:IsShown() then
						shownButtonsBefore = shownButtonsBefore + 1
					end
					button.inUse = false
				end
			end
		end
	end
	addon:DebugCategory("Update() BEFORE: totalButtons=%d, shownButtons=%d", totalButtonsBefore, shownButtonsBefore)

	local bagData
	local isOtherChar = false
	local charName = ""

	local titleFont = getglobal("Guda_BagFrame_Title")
	local displayName

	if currentViewChar then
	-- 正在查看其他角色
		bagData = addon.Modules.DB:GetCharacterBags(currentViewChar)
		isOtherChar = true
		charName = currentViewChar

		local dash = string.find(currentViewChar, "-")
		if dash then
			displayName = string.sub(currentViewChar, 1, dash - 1)
		else
			displayName = currentViewChar
		end
	else
	-- 正在查看当前角色 —— 使用缓存数据以获得性能
		bagData = addon.Modules.BagScanner:GetBagData()
		displayName = UnitName("player") or "Character"
	end

	if titleFont and displayName then
		titleFont:SetText(string.format(GudaBag.L["%s's Bags"], displayName))
	end

	-- 显示物品
	local viewType = addon.Modules.DB:GetSetting("bagViewType") or "single"

	-- 重建前清空 itemButtons 表和槽位查找表（防止残留的引用）
	for k in pairs(itemButtons) do
		itemButtons[k] = nil
	end
	for k in pairs(slotToButton) do
		slotToButton[k] = nil
	end

    -- 显示物品前重置所有分区标题
    local i = 1
    while true do
        local header = getglobal("Guda_BagFrame_SectionHeader" .. i)
        if not header then break end
        header.inUse = false
        header:Hide()
        i = i + 1
    end

	if viewType == "category" then
		addon:DebugCategory("Update() calling DisplayItemsByCategory")
		self:DisplayItemsByCategory(bagData, isOtherChar, charName)
		addon:DebugCategory("Update() DisplayItemsByCategory returned, itemButtons count=%d", table.getn(itemButtons))
		-- 为分类视图显示带有合并图标/提示的排序按钮
		local sortBtn = getglobal("Guda_BagFrame_SortButton")
		if sortBtn then
			sortBtn:Show()
			sortBtn.isCategoryView = true
		end
	else
		self:DisplayItems(bagData, isOtherChar, charName)
		local sortBtn = getglobal("Guda_BagFrame_SortButton")
		if sortBtn then
			sortBtn:Show()
			sortBtn.isCategoryView = false
		end
	end

	-- 更新金钱
	self:UpdateMoney()

	-- 更新炉石
	self:UpdateHearthstone()

	-- 更新分解 / 开锁表头快捷按钮
	self:RefreshUtilityButtons()

	-- 更新背包槽位信息
	self:UpdateBagSlotsInfo(bagData, isOtherChar)

	-- 更新背包栏布局（悬停选项）
	self:UpdateBaglineLayout()

	-- 品质过滤栏重新布局后，重新对齐左边缘（动态计算）
	if BagFrame.AlignQualityBar then
		BagFrame:AlignQualityBar()
	end

	-- 更新分类侧栏按钮状态
	if BagFrame.UpdateCategoryBarButtons then
		BagFrame:UpdateCategoryBarButtons()
	end

	-- 显示完成后清理未使用的按钮（防止拖拽/放置问题）
	-- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
	local hiddenCount = 0
	local stillShownCount = 0
	for _, bagParent in pairs(bagParents) do
		if bagParent and bagParent.itemButtons then
			for button in pairs(bagParent.itemButtons) do
				if button.hasItem ~= nil and not button.inUse then
					button:Hide()
					button:ClearAllPoints()
					hiddenCount = hiddenCount + 1
				elseif button.hasItem ~= nil and button:IsShown() then
					stillShownCount = stillShownCount + 1
				end
			end
		end
	end
	addon:DebugCategory("Update() CLEANUP: hidden=%d, stillShown=%d", hiddenCount, stillShownCount)

    -- 记录性能指标
    if addon.Modules.Utils and addon.Modules.Utils.RecordUpdateEnd then
        addon.Modules.Utils:RecordUpdateEnd()
    end
	addon:DebugCategory("Update() END")
end

-- 委托给集中式辅助函数
function BagFrame:GetSectionHeader(index)
    return GudaBag.GetSectionHeader("Guda_BagFrame", "Guda_BagFrame_ItemContainer", index)
end

function BagFrame:GetBagParent(bagID)
    return GudaBag.GetBagParent("Guda_BagFrame", bagParents, bagID, "Guda_BagFrame_ItemContainer")
end

-- 按分类显示物品
function BagFrame:DisplayItemsByCategory(bagData, isOtherChar, charName)
    local buttonSize = addon.Modules.DB:GetSetting("iconSize") or addon.Constants.BUTTON_SIZE
    local spacing = addon.Modules.DB:GetSetting("iconSpacing") or addon.Constants.BUTTON_SPACING
    local perRow = addon.Modules.DB:GetSetting("bagColumns") or 10
    local itemContainer = getglobal("Guda_BagFrame_ItemContainer")

    addon:DebugCategory("DisplayItemsByCategory START: buttonSize=%d, spacing=%d, perRow=%d", buttonSize, spacing, perRow)

    -- 使用集中式分类初始化
    local categories, specialItems = GudaBag.InitCategories()
    local categoryList = GudaBag.CategoryList

    -- 使用集中式函数对所有物品进行分类
    -- 此处跳过灵魂袋；它们像钥匙链一样在下方单独处理
    local totalItemsCategorized = 0
    for _, bagID in ipairs(addon.Constants.BAGS) do
        if not hiddenBags[bagID] then
            local isSoulBag = false
            if isOtherChar then
                local bag = bagData[bagID]
                isSoulBag = bag and bag.bagType == "soul"
            else
                isSoulBag = addon.Modules.Utils:GetSpecializedBagType(bagID) == "soul"
            end

            if not isSoulBag then
                local bag = bagData[bagID]
                if bag and bag.slots then
                    for slotID, itemData in pairs(bag.slots) do
                        if itemData then
                            GudaBag.CategorizeItem(itemData, bagID, slotID, categories, specialItems, isOtherChar)
                            totalItemsCategorized = totalItemsCategorized + 1
                        end
                    end
                end
            end
        end
    end
    addon:DebugCategory("DisplayItemsByCategory: totalItemsCategorized=%d", totalItemsCategorized)

    -- 计算空槽位总数，并找出第一个可用槽位作为放置目标。
    -- 专用背包（灵魂/草药/附魔/箭袋/弹药）只接受其对应类别，
    -- 因此它们的槽位不属于通用的"Empty"伪分类。
    local totalFreeSlots = 0
    local firstFreeBag, firstFreeSlot
    for _, bagID in ipairs(addon.Constants.BAGS) do
        if not hiddenBags[bagID]
           and not addon.Modules.Utils:GetSpecializedBagType(bagID) then
            local bag = bagData[bagID]
            if bag then
                totalFreeSlots = totalFreeSlots + (bag.freeSlots or 0)
                if not firstFreeBag and (bag.freeSlots or 0) > 0 then
                    for s = 1, (bag.numSlots or 0) do
                        if not bag.slots or not bag.slots[s] then
                            firstFreeBag = bagID
                            firstFreeSlot = s
                            break
                        end
                    end
                end
            end
        end
    end

    -- 处理可见的钥匙链
    if showKeyring and not hiddenBags[-2] then
        local bag = bagData[-2]
        if bag and bag.slots then
            for slotID, itemData in pairs(bag.slots) do
                if itemData then
                    table.insert(categories["Keyring"], {bagID = -2, slotID = slotID, itemData = itemData})
                end
            end
        end
    end

    -- 处理可见的灵魂袋
    if showSoulBag then
        for _, bagID in ipairs(addon.Constants.BAGS) do
            if not hiddenBags[bagID] then
                local isSoulBag = false
                if isOtherChar then
                    local bag = bagData[bagID]
                    isSoulBag = bag and bag.bagType == "soul"
                else
                    isSoulBag = addon.Modules.Utils:GetSpecializedBagType(bagID) == "soul"
                end
                if isSoulBag then
                    local bag = bagData[bagID]
                    if bag and bag.slots then
                        for slotID, itemData in pairs(bag.slots) do
                            if itemData then
                                table.insert(categories["Soul Bag"], {bagID = bagID, slotID = slotID, itemData = itemData})
                            end
                        end
                    end
                end
            end
        end
    end

    -- 确保钥匙链和灵魂袋在拥有物品时出现在显示列表中
    -- （如果用户自定义了分类顺序，它们可能不在 categoryList 中）
    local hasKeyringInList, hasSoulBagInList = false, false
    for _, catName in ipairs(categoryList) do
        if catName == "Keyring" then hasKeyringInList = true end
        if catName == "Soul Bag" then hasSoulBagInList = true end
    end
    if not hasKeyringInList and categories["Keyring"] and table.getn(categories["Keyring"]) > 0 then
        table.insert(categoryList, "Keyring")
    end
    if not hasSoulBagInList and categories["Soul Bag"] and table.getn(categories["Soul Bag"]) > 0 then
        table.insert(categoryList, "Soul Bag")
    end

    -- 将最近清空的槽位作为空占位符添加到各自分类中
    -- 这保留了刚被移走物品的视觉位置
    if not isOtherChar then
        for bagID, slots in pairs(bagRecentlyEmptiedSlots) do
            if not hiddenBags[bagID] then
                for slotID, info in pairs(slots) do
                    -- 仅当槽位确实为空时添加（未被重新填满）
                    local currentLink = GetContainerItemLink(bagID, slotID)
                    if not currentLink then
                        local catName = info.category
                        if catName and categories[catName] then
                            table.insert(categories[catName], {
                                bagID = bagID,
                                slotID = slotID,
                                itemData = {
                                    quality = info.quality or 0,
                                    name = info.name or "",
                                    iLevel = info.iLevel or 0,
                                },
                                isEmpty = true,
                            })
                            addon:DebugCategory("BagFrame: Added empty placeholder for %d:%d to category %s", bagID, slotID, catName)
                        end
                    else
                        -- 槽位现在有物品了，从跟踪中移除
                        slots[slotID] = nil
                    end
                end
            end
        end
    end

    -- 在用户拖拽期间，为分类注入放置目标的伪物品。它们渲染在每个
    -- 分类块的末尾（绿光空格子）：
    --   * 空分类：bagID=0/slotID=0 的虚拟目标，拖放仅 AssignItemToCategory。
    --   * 非空分类：末尾追加一个指向"真实空槽"的放置目标，拖放时物理放入
    --     空槽并 AssignItemToCategory，方便拆分/移动物品时直接放进当前分类。
    -- 排除项：系统伪分类（钥匙链/灵魂袋/空），以及其成员由物品类别决定的
    -- 仅自动分类（箭袋、容器、职业物品），还有 EquipSet:* 覆盖。
    if not isOtherChar and isDragging and addon.Modules.CategoryManager then
        local DROP_TARGET_BLOCKLIST = {
            ["Keyring"] = true, ["Soul Bag"] = true, ["Empty"] = true,
            ["Quiver"] = true, ["Container"] = true, ["Class Items"] = true,
        }
        -- 查找背包中的第一个真实空槽（用于非空分类末尾的物理放置目标）
        local dropBag, dropSlot = nil, nil
        for _, bID in ipairs(addon.Constants.BAGS) do
            local n = addon.Modules.Utils:GetBagSlotCount(bID)
            if addon.Modules.Utils:IsBagValid(bID) and n and n > 0 then
                for s = 1, n do
                    if not GetContainerItemInfo(bID, s) then
                        dropBag, dropSlot = bID, s
                        break
                    end
                end
            end
            if dropBag then break end
        end

        local allCats = addon.Modules.CategoryManager:GetCategories()
        local defs = allCats and allCats.definitions or {}
        for _, catName in ipairs(GudaBag.CategoryList) do
            if not DROP_TARGET_BLOCKLIST[catName]
               and string.sub(catName, 1, 9) ~= "EquipSet:"
               and categories[catName] and defs[catName] and defs[catName].enabled ~= false then
                local icon = defs[catName].icon or "Interface\\AddOns\\Guda\\Assets\\plus"
                local isEmptyCat = (table.getn(categories[catName]) == 0)
                -- 空分类用虚拟目标（只归类）；非空分类用真实空槽目标（可放置）。
                -- 统一插入到分类的最前面（左侧），使用户能直接看到并投放。
                local tb, ts = 0, 0
                if not isEmptyCat and dropBag and dropSlot then
                    tb, ts = dropBag, dropSlot
                end
                table.insert(categories[catName], 1, {
                    bagID = tb, slotID = ts,
                    itemData = {
                        isDropTarget = true,
                        categoryId   = catName,
                        texture      = icon,
                        name         = catName,
                        quality      = 0,
                    },
                })
            end
        end
    end

    -- 布局（感知主题的内边距）
    local _pad = { startX = 10, startY = -10 }
    if addon.Modules and addon.Modules.Theme and addon.Modules.Theme.GetFramePadding then
        _pad = addon.Modules.Theme:GetFramePadding()
    end
    local startX, startY = _pad.startX, _pad.startY
    local currentX, currentY = 0, 0
    local rowMaxHeight = 0
    local headerIdx = 1
    local totalWidth = perRow * (buttonSize + spacing)

    -- 分类物品处理的帧预算跟踪
    local categoryItemsProcessed = 0
    local CATEGORY_ITEMS_PER_BUDGET_CHECK = 8

    -- 检查合并分组设置
    local mergedGroups = addon.Modules.DB:GetSetting("mergedGroups") or {}

    -- 构建分类顺序索引表，用于在合并分组内排序
    local catOrderIndex = {}
    for idx, catId in ipairs(categoryList) do
        catOrderIndex[catId] = idx
    end

    -- 若任何分组被合并，构建合并分组的显示列表
    local mergedDisplayList = {}  -- { { name, items, icon, catDef } }
    local processedCats = {}     -- 跟踪哪些分类已被合并

    if addon.Modules.CategoryManager then
        local groupsByName = addon.Modules.CategoryManager:GetCategoriesByGroup()
        for groupName, catIds in pairs(groupsByName) do
            if mergedGroups[groupName] then
                -- 将此分组内所有分类的物品合并到一个分区
                local mergedItems = {}
                local mergedName = (GudaBag.L and GudaBag.L[groupName]) or groupName
                local mergedIcon = nil
                for _, catId in ipairs(catIds) do
                    local items = categories[catId]
                    if items then
                        local orderIdx = catOrderIndex[catId] or 999
                        for _, item in ipairs(items) do
                            item.categoryOrderIndex = orderIdx
                            table.insert(mergedItems, item)
                        end
                    end
                    processedCats[catId] = true
                end
                if table.getn(mergedItems) > 0 then
                    table.insert(mergedDisplayList, {
                        name = mergedName,
                        items = mergedItems,
                        icon = nil, -- 分组表头，没有单一图标
                    })
                end
            end
        end
    end

    -- 跟踪所有分类区块创建的按钮总数
    local totalButtonsCreated = 0

    -- 渲染分类区块的辅助函数
    local function RenderCategoryBlock(catName, items, numItems, catDef, isEmptyCat)
        addon:DebugCategory("  Category '%s': %d items, pos=(%d,%d)", catName, numItems, currentX, currentY)
        GudaBag.SortCategoryItems(items)

        local effectiveItems = numItems
        if isEmptyCat then effectiveItems = 1 end

        local blockCols = effectiveItems
        if blockCols > perRow then blockCols = perRow end
        local blockRows = math.ceil(effectiveItems / perRow)
        local blockWidth = blockCols * (buttonSize + spacing)
        local blockHeight = 20 + (blockRows * (buttonSize + spacing)) + 5

        -- 检查当前行是否能容纳
        if currentX > 0 and currentX + blockWidth + 20 > totalWidth + 5 then
            currentX = 0
            currentY = currentY + rowMaxHeight
            rowMaxHeight = 0
        end

        -- 添加表头
        local header = self:GetSectionHeader(headerIdx)
        headerIdx = headerIdx + 1
        header:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", startX + currentX, startY - currentY)
        header:SetWidth(blockWidth)

        -- 从分类定义获取显示名称（内置名称已本地化）
        local displayName = catName
        if addon.Modules.CategoryManager and addon.Modules.CategoryManager.GetDisplayName then
            displayName = addon.Modules.CategoryManager:GetDisplayName(catName, catDef)
        elseif catDef and catDef.name then
            displayName = catDef.name
        end

        -- 设置物品数量（受 showCategoryCount 设置控制）
        if header.countText then
            local showCount = addon.Modules.DB:GetSetting("showCategoryCount")
            if showCount == nil then showCount = true end
            if showCount and numItems > 1 then
                header.countText:SetText("(" .. numItems .. ")")
                header.countText:Show()
            else
                header.countText:Hide()
            end
        end

        header.fullName = displayName
        header.isShortened = false
        if string.len(displayName) > 8 and effectiveItems < 2 then
            displayName = string.sub(displayName, 1, 6) .. "..."
            header.isShortened = true
        end
        header.text:SetText(displayName)
        header:Show()

        local itemY = currentY + 20
        local col = 0
        local row = 0

        if isEmptyCat then
            -- 渲染空槽位指示器
            local bagID = firstFreeBag or 0
            local slotID = firstFreeSlot or 1
            local bagParent = self:GetBagParent(bagID)
            local button = GudaBag.GetItemButton(bagParent)
            button:SetParent(bagParent)
            button:SetWidth(buttonSize)
            button:SetHeight(buttonSize)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", startX + currentX, startY - itemY)
            button:Show()

            local emptyItemData = {
                texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag",
                count = totalFreeSlots,
                name = (GudaBag.L and GudaBag.L["Empty Slots"]) or "Empty Slots"
            }
            GudaBag.ItemButton_SetItem(button, bagID, slotID, emptyItemData, false, isOtherChar and charName or nil, true, true)
            button.isReadOnly = false
            button.inUse = true
            table.insert(itemButtons, button)
        else
            for _, item in ipairs(items) do
                local bagID = item.bagID
                local slot = item.slotID
                -- 对于空占位符，传入 nil itemData 使按钮显示为空槽位
                local itemData = item.isEmpty and nil or item.itemData

                local bagParent = self:GetBagParent(bagID)
                local button = GudaBag.GetItemButton(bagParent)

                button:SetParent(bagParent)
                button:SetWidth(buttonSize)
                button:SetHeight(buttonSize)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", startX + currentX + (col * (buttonSize + spacing)), startY - (itemY + (row * (buttonSize + spacing))))
                button:Show()

                local matchesFilter = self:PassesSearchFilter(itemData)
                GudaBag.ItemButton_SetItem(button, bagID, slot, itemData, false, isOtherChar and charName or nil, matchesFilter, isOtherChar)
                button.inUse = true
                button.isEmptyPlaceholder = item.isEmpty or false
                table.insert(itemButtons, button)
                if not slotToButton[bagID] then slotToButton[bagID] = {} end
                slotToButton[bagID][slot] = button
                -- 如果槽位现在有物品，从"最近清空"中移除
                if itemData and not item.isEmpty then
                    self:UnmarkSlotAsEmptied(bagID, slot)
                end

                col = col + 1
                if col >= blockCols then
                    col = 0
                    row = row + 1
                end

                categoryItemsProcessed = categoryItemsProcessed + 1
                if categoryItemsProcessed >= CATEGORY_ITEMS_PER_BUDGET_CHECK then
                    categoryItemsProcessed = 0
                    if addon.Modules.Utils and addon.Modules.Utils.CheckTimeout and addon.Modules.Utils:CheckTimeout() then
                        addon.Modules.Utils:ReportEntry()
                    end
                end
            end
        end

        totalButtonsCreated = totalButtonsCreated + effectiveItems
        if blockHeight > rowMaxHeight then rowMaxHeight = blockHeight end
        currentX = currentX + blockWidth + 20
    end

    -- 首先渲染合并分组的分区
    for _, merged in ipairs(mergedDisplayList) do
        local numItems = table.getn(merged.items)
        if numItems > 0 then
            RenderCategoryBlock(merged.name, merged.items, numItems, { name = merged.name, icon = merged.icon })
        end
    end

    -- 构建待渲染的独立分类列表（跳过已合并的）。当启用"自动补位"时，
    -- 重新排列此列表，使连续的分类块能最佳地填满每一行（把仍能放下、
    -- 且宽度最大的块提前），从而最小化分类之间的空位。渲染循环本身不变：
    -- 块放不下时照旧换行。
    local renderCats = {}
    for _, catName in ipairs(categoryList) do
        if not processedCats[catName] then
            local catDef = addon.Modules.CategoryManager and addon.Modules.CategoryManager:GetCategory(catName) or nil
            if catDef and catDef.isEmptyCategory then
                if totalFreeSlots > 0 and catDef.enabled then
                    table.insert(renderCats, catName)
                end
            else
                local items = categories[catName]
                local numItems = items and table.getn(items) or 0
                if numItems > 0 then
                    table.insert(renderCats, catName)
                end
            end
        end
    end

    -- 自动补位：重新排列分类块以填满每一行。
    -- 仅在本次打开背包的首次渲染时执行（bagAutoFilledThisSession 控制），
    -- 这样背包打开期间卖出/移动物品时分类块位置保持稳定，不会每次
    -- Update 都跳动；关闭背包（OnHide）会重置标志，下次打开重新补位。
    -- 注意：补位后的顺序保存到 self.autoFillCategoryOrder，本次会话内
    -- 后续 Update 都按该顺序渲染（只保留仍存在的分类），避免任意点击
    -- 触发 Update 后布局回到未补位的原始顺序。
    if addon.Modules.DB:GetSetting("autoFillRows") and not self.bagAutoFilledThisSession then
        self.bagAutoFilledThisSession = true
        -- 分类块在其网格行首所占的宽度（像素）。
        local function blockWidthOf(cat)
            local catDef = addon.Modules.CategoryManager and addon.Modules.CategoryManager:GetCategory(cat) or nil
            local n = 1
            if not (catDef and catDef.isEmptyCategory) then
                local items = categories[cat]
                n = items and table.getn(items) or 0
            end
            local cols = n
            if cols > perRow then cols = perRow end
            return cols * (buttonSize + spacing)
        end
        local function fits(curX, w)
            if curX == 0 then return true end
            return (curX + w + 20) <= (totalWidth + 5)
        end
        local remaining = {}
        for _, c in ipairs(renderCats) do remaining[c] = true end
        local ordered = {}
        local curX = 0
        while true do
            local best, bestW
            for _, c in ipairs(renderCats) do
                if remaining[c] then
                    local w = blockWidthOf(c)
                    if fits(curX, w) and (not best or w > bestW) then
                        best, bestW = c, w
                    end
                end
            end
            if not best then
                -- 当前行放不下任何块：换行并拉出剩余中最大的一块开启下一行。
                curX = 0
                local largest, lw
                for _, c in ipairs(renderCats) do
                    if remaining[c] then
                        local w = blockWidthOf(c)
                        if not largest or w > lw then largest, lw = c, w end
                    end
                end
                if not largest then break end
                best, bestW = largest, lw
            end
            table.insert(ordered, best)
            remaining[best] = nil
            curX = curX + bestW + 20
        end
        -- 缓存本次补位后的顺序，会话内后续 Update 复用，保持布局稳定
        self.autoFillCategoryOrder = ordered
        renderCats = ordered
    elseif addon.Modules.DB:GetSetting("autoFillRows")
       and self.autoFillCategoryOrder then
        -- 后续渲染：按已缓存的补位顺序渲染，只保留仍存在的分类。
        -- 先记录当前 live 集合（renderCats 已基于最新物品状态重建），
        -- 再按缓存的顺序输出；不在缓存中的新分类追加到末尾。
        local alive = {}
        for _, c in ipairs(renderCats) do alive[c] = true end
        local reordered = {}
        for _, c in ipairs(self.autoFillCategoryOrder) do
            if alive[c] then
                table.insert(reordered, c)
                alive[c] = nil
            end
        end
        for _, c in ipairs(renderCats) do
            if alive[c] then table.insert(reordered, c) end
        end
        renderCats = reordered
    end

    -- 渲染各个分类（跳过已合并的和 Empty 分类）
    for _, catName in ipairs(renderCats) do
        local catDef = addon.Modules.CategoryManager and addon.Modules.CategoryManager:GetCategory(catName) or nil

        -- 特殊处理 Empty 分类
        if catDef and catDef.isEmptyCategory then
            if totalFreeSlots > 0 and catDef.enabled then
                RenderCategoryBlock(catName, {}, 0, catDef, true)
            end
        else
            local items = categories[catName]
            local numItems = items and table.getn(items) or 0
            if numItems > 0 then
                RenderCategoryBlock(catName, items, numItems, catDef, false)
            end
        end
    end
    addon:DebugCategory("DisplayItemsByCategory: totalButtonsCreated=%d from categories", totalButtonsCreated)

    -- 为底部分区更新 Y 坐标
    local y = currentY + rowMaxHeight

    -- 底部的特殊分区（现在只有坐骑）
    local bottomSections = {
        { name = "Mounts", items = specialItems.Mount },
    }

    local x = startX
    y = startY - y

    local hasAnyBottom = false
    for _, sec in ipairs(bottomSections) do
        if table.getn(sec.items) > 0 then
            hasAnyBottom = true
            break
        end
    end

    if hasAnyBottom then
        y = y - 10
        local currentBottomX = 0
        local sectionMaxHeight = 0

        for _, sec in ipairs(bottomSections) do
            local items = sec.items
            local numItems = table.getn(items)
            if numItems > 0 then
                local blockCols = numItems
                if blockCols > perRow then blockCols = perRow end
                local blockRows = math.ceil(numItems / perRow)
                local blockWidth = blockCols * (buttonSize + spacing)
                local blockHeight = 20 + (blockRows * (buttonSize + spacing))

                if currentBottomX > 0 and currentBottomX + blockWidth + 20 > totalWidth + 5 then
                    currentBottomX = 0
                    y = y - sectionMaxHeight - 5
                    sectionMaxHeight = 0
                end

                local header = self:GetSectionHeader(headerIdx)
                headerIdx = headerIdx + 1
                header:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", x + currentBottomX, y)
                header:SetWidth(blockWidth)
                header.text:SetText(sec.name)
                if header.countText then header.countText:SetText("(" .. numItems .. ")"); header.countText:Show() end
                header:Show()

                local itemY = y - 20
                local sCol = 0
                local sRow = 0

                for _, item in ipairs(items) do
                    local bagParent = self:GetBagParent(item.bagID)
                    local button = GudaBag.GetItemButton(bagParent)
                    button:SetParent(bagParent)
                    button:SetWidth(buttonSize)
                    button:SetHeight(buttonSize)
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", x + currentBottomX + (sCol * (buttonSize + spacing)), itemY - (sRow * (buttonSize + spacing)))
                    button:Show()
                    GudaBag.ItemButton_SetItem(button, item.bagID, item.slotID, item.itemData, false, isOtherChar and charName or nil, self:PassesSearchFilter(item.itemData), isOtherChar)
                    button.inUse = true
                    table.insert(itemButtons, button)
                    if not slotToButton[item.bagID] then slotToButton[item.bagID] = {} end
                    slotToButton[item.bagID][item.slotID] = button

                    sCol = sCol + 1
                    if sCol >= blockCols then
                        sCol = 0
                        sRow = sRow + 1
                    end
                end

                if blockHeight > sectionMaxHeight then sectionMaxHeight = blockHeight end
                currentBottomX = currentBottomX + blockWidth + 20

                if currentBottomX >= totalWidth then
                    currentBottomX = 0
                    y = y - sectionMaxHeight - 5
                    sectionMaxHeight = 0
                end
            end
        end

        if currentBottomX > 0 then
            y = y - sectionMaxHeight
        end
    end

    local finalHeight = math.abs(y) + 20
    itemContainer:SetHeight(finalHeight)
    self:ResizeFrame(nil, nil, perRow, finalHeight)
    addon:DebugCategory("DisplayItemsByCategory END: finalHeight=%d, itemButtons=%d", finalHeight, table.getn(itemButtons))
end

-- 显示物品
function BagFrame:DisplayItems(bagData, isOtherChar, charName)
	local _pad = { startX = 10, startY = -10 }
	if addon.Modules and addon.Modules.Theme and addon.Modules.Theme.GetFramePadding then
		_pad = addon.Modules.Theme:GetFramePadding()
	end
	local x, y = _pad.startX, _pad.startY
	local row = 0
	local col = 0
	local buttonSize = addon.Modules.DB:GetSetting("iconSize") or addon.Constants.BUTTON_SIZE
	local spacing = addon.Modules.DB:GetSetting("iconSpacing") or addon.Constants.BUTTON_SPACING
	local perRow = addon.Modules.DB:GetSetting("bagColumns") or 10
	local itemContainer = getglobal("Guda_BagFrame_ItemContainer")

 -- 将背包分为普通、附魔、草药、灵魂、箭袋和弹药类型
 local regularBags = {}
 local enchantBags = {}
 local herbBags = {}
 local soulBags = {}
 local quiverBags = {}
 local ammoBags = {}

	for _, bagID in ipairs(addon.Constants.BAGS) do
	-- 跳过隐藏的背包
		if not hiddenBags[bagID] then
            local bagType
            if isOtherChar then
                -- 对于其他角色，使用保存的背包类型
                local bag = bagData[bagID]
                bagType = bag and bag.bagType or "regular"
            else
                -- 对于当前角色，使用统一检测器实时检测背包类型
                bagType = addon.Modules.Utils:GetSpecializedBagType(bagID) or "regular"
            end

            if bagType == "enchant" then
                table.insert(enchantBags, bagID)
            elseif bagType == "herb" then
                table.insert(herbBags, bagID)
            elseif bagType == "soul" then
                table.insert(soulBags, bagID)
            elseif bagType == "quiver" then
                table.insert(quiverBags, bagID)
            elseif bagType == "ammo" then
                table.insert(ammoBags, bagID)
            else
                table.insert(regularBags, bagID)
            end
        end
    end

    -- 构建显示顺序：普通 -> 附魔 -> 草药 -> 灵魂 -> 箭袋 -> 弹药 -> 钥匙链
    local bagsToShow = {}
    for _, bagID in ipairs(regularBags) do
        table.insert(bagsToShow, {bagID = bagID, needsSpacing = false})
    end

    -- 附魔
    if table.getn(enchantBags) > 0 then
        for i, bagID in ipairs(enchantBags) do
            table.insert(bagsToShow, {bagID = bagID, needsSpacing = (i == 1)})
        end
    end
    -- 草药
    if table.getn(herbBags) > 0 then
        for i, bagID in ipairs(herbBags) do
            table.insert(bagsToShow, {bagID = bagID, needsSpacing = (i == 1)})
        end
    end
    -- 灵魂（仅当灵魂袋开关开启时）
    if showSoulBag and table.getn(soulBags) > 0 then
        for i, bagID in ipairs(soulBags) do
            table.insert(bagsToShow, {bagID = bagID, needsSpacing = (i == 1)})
        end
    end
    -- 箭袋
    if table.getn(quiverBags) > 0 then
        for i, bagID in ipairs(quiverBags) do
            table.insert(bagsToShow, {bagID = bagID, needsSpacing = (i == 1)})
        end
    end
    -- 弹药
    if table.getn(ammoBags) > 0 then
        for i, bagID in ipairs(ammoBags) do
            table.insert(bagsToShow, {bagID = bagID, needsSpacing = (i == 1)})
        end
    end

	-- 如果钥匙链开关已开启且未被隐藏，则添加到末尾
	if showKeyring and not hiddenBags[-2] then
		table.insert(bagsToShow, {bagID = -2, needsSpacing = true})
	end

    -- 物品处理的帧预算跟踪
    local itemsProcessed = 0
    local ITEMS_PER_BUDGET_CHECK = 8  -- 每 N 个物品检查一次预算

	for _, bagInfo in ipairs(bagsToShow) do
		local bagID = bagInfo.bagID
		local bag = bagData[bagID]

  -- 在附魔、草药、灵魂、箭袋、弹药或钥匙链分区前添加间距
  if bagInfo.needsSpacing then
			if col > 0 then
			-- 如果不在行首，则移到下一行
				col = 0
				row = row + 1
			end
			-- 添加额外的间距（0.5 行以获得更紧凑的间隔）
			row = row + 0.5
		end

		-- 获取此背包的槽位数量
		local numSlots
		if isOtherChar and bag and bag.numSlots then
		-- 对其他角色使用保存的槽位数量
			numSlots = bag.numSlots
		else
		-- 使用当前角色的背包槽位数量
			numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
		end

		-- 只显示有槽位的背包
		if numSlots and numSlots > 0 then
		-- 遍历所有槽位（1 到 numSlots），也显示空槽位
		-- 确保每个背包都有一个父框架并携带背包 ID（暴雪期望 parent:GetID() == bagID）
			local bagParent = self:GetBagParent(bagID)

			for slot = 1, numSlots do
				local itemData = bag and bag.slots and bag.slots[slot] or nil

				-- 检查物品是否匹配搜索过滤器
				local matchesFilter = self:PassesSearchFilter(itemData)

				local button = GudaBag.GetItemButton(bagParent)
				button.inUse = true  -- 将此按钮标记为正在使用

				-- 定位按钮
				local xPos = x + (col * (buttonSize + spacing))
				local yPos = y - (row * (buttonSize + spacing))

				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", xPos, yPos)

				-- 设置带过滤匹配信息的物品数据
				-- 查看其他角色时 isReadOnly = true（无法与他们的物品交互）
				GudaBag.ItemButton_SetItem(button, bagID, slot, itemData, false, isOtherChar and charName or nil, matchesFilter, isOtherChar)

				table.insert(itemButtons, button)
				-- 填充槽位查找表以实现 O(1) 访问
				if not slotToButton[bagID] then slotToButton[bagID] = {} end
				slotToButton[bagID][slot] = button

				-- 前进位置
				col = col + 1
				if col >= perRow then
					col = 0
					row = row + 1
				end

                -- 帧预算检查：定期检查是否超出帧预算
                itemsProcessed = itemsProcessed + 1
                if itemsProcessed >= ITEMS_PER_BUDGET_CHECK then
                    itemsProcessed = 0
                    if addon.Modules.Utils and addon.Modules.Utils.CheckTimeout and addon.Modules.Utils:CheckTimeout() then
                        -- 超出预算 —— 重置入口时间并继续
                        -- （要实现完全延迟，需要将剩余工作排队，但那需要
                        -- 更复杂的状态管理。目前我们只记录预算使用情况。）
                        addon.Modules.Utils:ReportEntry()
                    end
                end
			end
		end
	end

    -- 根据内容动态调整框架大小
    self:ResizeFrame(row, col, perRow)
    
    -- 确保（重新）构建按钮后冷却显示是最新的
    if self.RefreshCooldowns then
        self:RefreshCooldowns()
    end
end

-- 根据行数和列数调整框架大小
function BagFrame:ResizeFrame(currentRow, currentCol, columns, overrideHeight)
    return GudaBag.ResizeFrame("Guda_BagFrame", "Guda_BagFrame_ItemContainer", currentRow, currentCol, columns, overrideHeight)
end

-- 检查搜索当前是否处于激活状态
function BagFrame:IsSearchActive()
	return searchText and searchText ~= "" and searchText ~= GudaBag.L["Search, try ~equipment"]
end

-- 检查物品是否通过品质过滤（移植自 OneBag 品质模块）
-- 品质 1 覆盖粗糙(0)与普通(1)
function BagFrame:PassesQualityFilter(itemData)
    if not activeQuality then return true end
    -- 品质过滤激活时，空格子与搜索行为一致变暗（与 OneBag 一致）
    if not itemData then return false end
    -- 投放目标 / 空占位符等伪物品不受品质过滤影响
    if itemData.isDropTarget or itemData.isEmpty then return true end
    local quality = itemData.quality or 0
    local match = (activeQuality == 1 and (quality == 0 or quality == 1)) or (quality == activeQuality)
    return match
end

-- 检查物品是否通过搜索过滤（pfUI 风格）
function BagFrame:PassesSearchFilter(itemData)
    if self:IsSearchActive() then
        if not GudaBag.PassesSearchFilter(itemData, searchText) then
            return false
        end
    end
    if not self:PassesQualityFilter(itemData) then return false end
    return self:PassesCategoryFilter(itemData)
end

-- 是否有任意过滤（搜索、品质或分类）处于激活状态
function BagFrame:IsAnyFilterActive()
    return self:IsSearchActive() or (activeQuality ~= nil) or (activeCategory ~= nil)
end

-- 搜索文本变化的快速路径（借鉴 OneBag 的 alpha 过滤方法）：
-- 背包布局与搜索字符串无关 —— 不匹配的物品就地变暗 ——
-- 因此重新着色已定位的按钮，而不是重建整个框架
--（那样会从对象池重新获取每个按钮，ClearAllPoints/SetPoint
-- 它们并调整框架大小）。
function BagFrame:ReapplySearchFilter()
    if not Guda_BagFrame or not Guda_BagFrame:IsShown() then return end

    local filterActive = self:IsAnyFilterActive()
    local junkOpacity = 0.6
    if addon.Modules.DB and addon.Modules.DB.GetSetting then
        junkOpacity = addon.Modules.DB:GetSetting("junkOpacity") or 0.6
    end

    for _, bagParent in pairs(bagParents) do
        if bagParent and bagParent.itemButtons then
            for button in pairs(bagParent.itemButtons) do
                if button and button:IsShown() and button.hasItem and not button.isBagSlot then
                    if filterActive then
                        if self:PassesSearchFilter(button.itemData) then
                            button:SetAlpha(button._isJunk and junkOpacity or 1.0)
                        else
                            button:SetAlpha(0.25)
                        end
                    else
                        button:SetAlpha(button._isJunk and junkOpacity or 1.0)
                    end
                end
            end
        end
    end
end

--=====================================================
-- 品质过滤栏（移植自 OneBag 品质模块）
--=====================================================
local QUALITY_LIST = {
    { id = 5, name = GudaBag.L["Legendary"] },
    { id = 4, name = GudaBag.L["Epic"] },
    { id = 3, name = GudaBag.L["Rare"] },
    { id = 2, name = GudaBag.L["Uncommon"] },
    { id = 1, name = GudaBag.L["Common/Poor"] },
}
local qualityBarButtons = {}
local qualityBarCreated = false

-- 根据设置更新品质过滤栏的可见性。
-- 隐藏时把品质栏行也收掉：重新锚定搜索栏到标题栏下方，使搜索栏/物品
-- 容器整体上移占据品质栏那一行（与搜索栏隐藏时收缩行高的行为一致）。
function BagFrame:UpdateQualityBarVisibility()
	local qualityBar = getglobal("Guda_BagFrame_QualityBar")
	if not qualityBar then return end
	local show = true
	if addon.Modules and addon.Modules.DB then
		local s = addon.Modules.DB:GetSetting("showQualityBar")
		if s == nil then s = true end
		show = s and true or false
	end
	self.qualityBarHidden = not show
	if show then
		qualityBar:Show()
	else
		qualityBar:Hide()
	end
	-- 搜索栏锚定在品质栏下方，品质栏行高变化后需重新应用搜索栏布局
	if BagFrame.UpdateSearchBarVisibility then
		BagFrame:UpdateSearchBarVisibility()
	end
end

-- 创建品质过滤栏上的按钮（懒加载，首次打开背包时创建）
function BagFrame:CreateQualityBar()
    if qualityBarCreated then return end
    local qualityBar = getglobal("Guda_BagFrame_QualityBar")
    if not qualityBar then return end
    qualityBarCreated = true

    qualityBarButtons = {}
    for i, info in ipairs(QUALITY_LIST) do
        local color = addon.Constants.QUALITY_COLORS[info.id] or { r = 1, g = 1, b = 1 }

        local btn = CreateFrame("CheckButton", "Guda_BagFrame_QualityBar_Quality" .. info.id, qualityBar)
        btn:SetWidth(20)
        btn:SetHeight(20)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if i == 1 then
            btn:SetPoint("LEFT", qualityBar, "LEFT", 2, 0)
        else
            btn:SetPoint("LEFT", qualityBarButtons[i - 1], "RIGHT", 2, 0)
        end

        -- 彩色背景（按品质色）
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(color.r, color.g, color.b, 1)
        bg:SetAlpha(0.55)
        btn.bg = bg

        -- 边框（仅边线，不设置背景填充以免遮挡彩色背景）
        btn:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

        -- 悬停高亮
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        highlight:SetBlendMode("ADD")
        highlight:SetVertexColor(1, 1, 1, 0.3)

        -- 选中标记（金色圆点，显示当前激活的品质）
        local activeDot = btn:CreateTexture(nil, "OVERLAY")
        activeDot:SetWidth(6)
        activeDot:SetHeight(6)
        activeDot:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
        activeDot:SetTexture("Interface\\Buttons\\WHITE8x8")
        activeDot:SetVertexColor(1, 0.82, 0, 1)
        activeDot:Hide()
        btn.activeDot = activeDot

        -- 品质首字母文本
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        text:SetText(string.sub(info.name, 1, 1))
        text:SetTextColor(0.95, 0.95, 0.95)
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 0.8)

        btn.qualityId = info.id
        btn.qualityName = info.name
        btn.qualityColor = color

        btn:SetScript("OnClick", function()
            -- 香草使用全局 arg1 作为鼠标按键
            local mouseButton = arg1 or "LeftButton"
            -- 右键清除过滤；左键切换该品质
            if mouseButton == "RightButton" then
                BagFrame:SetActiveQuality(nil)
            else
                BagFrame:ToggleQualityFilter(btn.qualityId)
            end
        end)

        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(btn.qualityName, btn.qualityColor.r, btn.qualityColor.g, btn.qualityColor.b)
            GameTooltip:AddLine(string.format(GudaBag.L["%d items"] or "%d items", BagFrame:CountQualityItems(btn.qualityId)), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(GudaBag.L["Click: filter this quality"], 0, 1, 0)
            GameTooltip:AddLine(GudaBag.L["Right-click: clear filter"], 1, 1, 0)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        qualityBarButtons[i] = btn
    end
    self:UpdateQualityBarButtons()
    self:AlignQualityBar()
end

-- 将品质过滤栏左边缘与标题栏左侧按钮（角色）左边缘对齐。
-- 品质栏本身水平居中，其左缘距框架左缘 = frameExtra/2；
-- 角色按钮左缘 = charsX（圆角主题 21，pfUI 方形主题 10）。
-- 因此固定偏移 = charsX - frameExtra/2（圆角 11，方形 5）。
-- 用主题常量直接计算，不依赖 GetLeft()，首次打开背包即正确。
function BagFrame:AlignQualityBar()
    if not qualityBarCreated then return end
    local qualityBar = getglobal("Guda_BagFrame_QualityBar")
    local first = qualityBarButtons[1]
    if not qualityBar or not first then return end

    local style = "rounded"
    if addon.Modules and addon.Modules.Theme and addon.Modules.Theme.GetSlotStyle then
        style = addon.Modules.Theme:GetSlotStyle()
    end
    local charsX = 21
    local frameExtra = 20
    if style == "square" then
        charsX = 10
        frameExtra = 10
    end
    local offset = charsX - frameExtra / 2

    first:ClearAllPoints()
    first:SetPoint("LEFT", qualityBar, "LEFT", offset, 0)
end

-- 获取当前激活的品质（nil = 不过滤）
function BagFrame:GetActiveQuality()
    return activeQuality
end

-- 设置激活品质并刷新显示（nil = 清除过滤）
function BagFrame:SetActiveQuality(qualityId)
    if activeQuality == qualityId then
        activeQuality = nil
    else
        activeQuality = qualityId
        -- 与分类过滤互斥：激活品质时清除分类过滤
        if activeCategory then
            activeCategory = nil
            if categoryBarCreated then
                self:UpdateCategoryBarButtons()
            end
        end
    end
    self:UpdateQualityBarButtons()
    self:ReapplySearchFilter()
end

-- 切换品质过滤（左键点击时调用）
function BagFrame:ToggleQualityFilter(qualityId)
    self:SetActiveQuality(qualityId)
end

-- 刷新品质栏按钮的选中状态
function BagFrame:UpdateQualityBarButtons()
    if not qualityBarCreated then return end
    for _, btn in ipairs(qualityBarButtons) do
        if activeQuality == btn.qualityId then
            btn.activeDot:Show()
            btn.bg:SetAlpha(1.0)
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            btn.activeDot:Hide()
            btn.bg:SetAlpha(0.55)
            btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
        end
    end
end

-- 统计当前视图中指定品质的物品数量（用于提示框）
function BagFrame:CountQualityItems(qualityId)
    local count = 0
    if currentViewChar then
        -- 其他角色：使用保存的背包数据
        local bagData = addon.Modules.DB:GetCharacterBags(currentViewChar)
        if bagData then
            for _, bagID in ipairs(addon.Constants.BAGS) do
                local bag = bagData[bagID]
                if bag and bag.slots then
                    for _, itemData in pairs(bag.slots) do
                        if itemData and itemData.quality ~= nil then
                            local q = (itemData.quality == 0 and 1) or itemData.quality
                            if q == qualityId then
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
        return count
    end
    -- 当前角色：使用实时容器信息
    for _, bagID in ipairs(addon.Constants.BAGS) do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local texture, _, _, quality = GetContainerItemInfo(bagID, slot)
                if texture then
                    local q = (quality == 0 and 1) or quality
                    if q == qualityId then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

--=====================================================
-- 分类过滤侧栏（移植自 OneBag 分类模块）
-- 位于背包框架左侧的竖排图标栏，按物品类型筛选：
-- 点击某分类后非匹配物品变暗，再次点击取消筛选。
-- 与品质过滤互斥（激活其一自动清除另一个）。
-- 仅当设置 showCategoryBar 开启时显示。
--=====================================================

-- OneBag 风格的 8 个粗粒度分类（基于 GetItemInfo 的物品类别）
local CATEGORY_BAR_LIST = {
    { id = "quest",      name = GudaBag.L["Quest"],         icon = "Interface\\Icons\\INV_Misc_Book_08",          color = { 1.0, 0.82, 0.0 } },
    { id = "equipment",  name = GudaBag.L["Equipment"],     icon = "Interface\\Icons\\INV_Chest_Chain",          color = { 0.7, 0.7, 0.9 } },
    { id = "consumable", name = GudaBag.L["Consumable"],    icon = "Interface\\Icons\\INV_Potion_54",            color = { 0.4, 0.9, 0.4 } },
    { id = "tradeskill", name = GudaBag.L["Trade Goods"],   icon = "Interface\\Icons\\INV_Fabric_Silk_02",       color = { 0.9, 0.6, 1.0 } },
    { id = "reagent",    name = GudaBag.L["Reagent"],       icon = "Interface\\Icons\\INV_Misc_Dust_02",         color = { 1.0, 0.9, 0.5 } },
    { id = "container",  name = GudaBag.L["Container"],     icon = "Interface\\Icons\\INV_Misc_Bag_07",          color = { 0.7, 0.7, 0.7 } },
    { id = "projectile", name = GudaBag.L["Projectile"],    icon = "Interface\\Icons\\INV_Ammo_Arrow_01",        color = { 0.5, 0.8, 1.0 } },
    { id = "misc",       name = GudaBag.L["Miscellaneous"], icon = "Interface\\Icons\\INV_Misc_Rune_01",         color = { 0.6, 0.6, 0.6 } },
}
local categoryBarButtons = {}
local categoryBarCreated = false

-- 按 OneBag 风格将 itemData.class 映射到分类过滤 ID
local function MapItemClassToCategoryBar(class)
    if not class then return "misc" end
    if class == "Quest" or class == "Key" then return "quest" end
    if class == "Armor" or class == "Weapon" then return "equipment" end
    if class == "Consumable" then return "consumable" end
    if class == "Trade Goods" or class == "Recipe" then return "tradeskill" end
    if class == "Reagent" then return "reagent" end
    if class == "Container" or class == "Quiver" then return "container" end
    if class == "Projectile" then return "projectile" end
    return "misc"
end

-- 创建分类过滤侧栏按钮（懒加载，首次显示时创建）
function BagFrame:CreateCategoryBar()
    if categoryBarCreated then return end
    local bar = getglobal("Guda_BagFrame_CategoryBar")
    if not bar then return end
    categoryBarCreated = true

    categoryBarButtons = {}
    for i, info in ipairs(CATEGORY_BAR_LIST) do
        local btn = CreateFrame("CheckButton", "Guda_BagFrame_CategoryBar_Btn" .. i, bar)
        btn:SetWidth(36)
        btn:SetHeight(36)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        if i == 1 then
            btn:SetPoint("TOP", bar, "TOP", 0, 0)
        else
            btn:SetPoint("TOP", categoryBarButtons[i - 1], "BOTTOM", 0, -3)
        end

        -- 深色背景
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0, 0, 0, 0.5)
        btn.bg = bg

        -- 边框
        local normalBorder = btn:CreateTexture(nil, "BORDER")
        normalBorder:SetWidth(40)
        normalBorder:SetHeight(40)
        normalBorder:SetPoint("CENTER", btn, "CENTER", 0, 0)
        normalBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        normalBorder:SetVertexColor(0.5, 0.5, 0.5, 1)
        btn.normalBorder = normalBorder

        -- 图标
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(30)
        icon:SetHeight(30)
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetTexture(info.icon)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        btn.icon = icon

        -- 悬停高亮
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetWidth(40)
        highlight:SetHeight(40)
        highlight:SetPoint("CENTER", btn, "CENTER", 0, 0)
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetBlendMode("ADD")

        -- 选中边框
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetWidth(64)
        border:SetHeight(64)
        border:SetPoint("CENTER", btn, "CENTER", 0, 0)
        border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        border:SetBlendMode("ADD")
        border:SetVertexColor(1, 0.8, 0, 1)
        border:Hide()
        btn.border = border

        btn.categoryId = info.id
        btn.categoryName = info.name
        btn.categoryColor = info.color

        btn:SetScript("OnClick", function()
            BagFrame:OnCategoryBarClick(btn.categoryId)
        end)

        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(btn.categoryName, unpack(btn.categoryColor))
            GameTooltip:AddLine(string.format(GudaBag.L["%d items"], BagFrame:CountCategoryBarItems(btn.categoryId)), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(GudaBag.L["Click: filter this category"], 0, 1, 0)
            GameTooltip:AddLine(GudaBag.L["Right-click: clear filter"], 1, 1, 0)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        categoryBarButtons[i] = btn
    end
    self:UpdateCategoryBarButtons()
end

-- 分类侧栏按钮点击处理
function BagFrame:OnCategoryBarClick(categoryId)
    if activeCategory == categoryId then
        activeCategory = nil
    else
        activeCategory = categoryId
        -- 与品质过滤互斥：激活分类时清除品质过滤
        if activeQuality then
            activeQuality = nil
            self:UpdateQualityBarButtons()
        end
    end
    self:UpdateCategoryBarButtons()
    self:ReapplySearchFilter()
end

-- 刷新分类侧栏按钮的选中状态
function BagFrame:UpdateCategoryBarButtons()
    if not categoryBarCreated then return end
    for _, btn in ipairs(categoryBarButtons) do
        if activeCategory == btn.categoryId then
            btn.border:Show()
        else
            btn.border:Hide()
        end
    end
end

-- 获取当前激活的分类过滤 ID（nil = 不过滤）
function BagFrame:GetActiveCategory()
    return activeCategory
end

-- 设置激活分类并刷新显示（nil = 清除过滤）
function BagFrame:SetActiveCategory(categoryId)
    if activeCategory == categoryId then
        activeCategory = nil
    else
        activeCategory = categoryId
        -- 与品质过滤互斥
        if activeQuality then
            activeQuality = nil
            self:UpdateQualityBarButtons()
        end
    end
    self:UpdateCategoryBarButtons()
    self:ReapplySearchFilter()
end

-- 统计当前视图中指定分类的物品数量（用于提示框）
function BagFrame:CountCategoryBarItems(categoryId)
    local count = 0
    if currentViewChar then
        local bagData = addon.Modules.DB:GetCharacterBags(currentViewChar)
        if bagData then
            for _, bagID in ipairs(addon.Constants.BAGS) do
                local bag = bagData[bagID]
                if bag and bag.slots then
                    for _, itemData in pairs(bag.slots) do
                        if itemData and MapItemClassToCategoryBar(itemData.class) == categoryId then
                            count = count + 1
                        end
                    end
                end
            end
        end
        return count
    end
    for _, bagID in ipairs(addon.Constants.BAGS) do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local texture, _, _, quality = GetContainerItemInfo(bagID, slot)
                if texture then
                    local link = GetContainerItemLink(bagID, slot)
                    if link then
                        local itemID = nil
                        local _, _, idStr = string.find(link, "item:(%d+)")
                        if idStr then itemID = tonumber(idStr) end
                        if itemID then
                            local _, _, _, _, itemClass = GetItemInfo(itemID)
                            if MapItemClassToCategoryBar(itemClass) == categoryId then
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return count
end

-- 检查物品是否通过分类过滤
function BagFrame:PassesCategoryFilter(itemData)
    if not activeCategory then return true end
    -- 分类过滤激活时，空格子与搜索行为一致变暗
    if not itemData then return false end
    -- 投放目标 / 空占位符等伪物品不受分类过滤影响
    if itemData.isDropTarget or itemData.isEmpty then return true end
    return MapItemClassToCategoryBar(itemData.class) == activeCategory
end

-- 更新分类侧栏可见性（根据设置开关）
function BagFrame:UpdateCategoryBarVisibility()
    local showBar = addon.Modules.DB:GetSetting("showCategoryBar")
    if showBar == nil then showBar = false end
    local bar = getglobal("Guda_BagFrame_CategoryBar")
    if not bar then
        -- 首次启用：创建框架（懒加载）
        bar = CreateFrame("Frame", "Guda_BagFrame_CategoryBar", Guda_BagFrame)
        bar:SetFrameStrata("HIGH")
        bar:SetFrameLevel(Guda_BagFrame:GetFrameLevel() + 5)
        bar:SetWidth(40)
        bar:SetHeight(300)
        bar:SetPoint("TOPRIGHT", Guda_BagFrame, "TOPLEFT", -6, -40)
        bar:EnableMouse(true)
        bar:Hide()
        if BagFrame.CreateCategoryBar then
            BagFrame:CreateCategoryBar()
        end
    end
    if showBar then
        bar:Show()
        self:UpdateCategoryBarButtons()
    else
        bar:Hide()
    end
end

function BagFrame:UpdateMoney()
	local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
	local moneyFrame = getglobal("Guda_BagFrame_MoneyFrame")

	if hideFooter then
		if moneyFrame then moneyFrame:Hide() end
		return
	end

	if not moneyFrame then
		addon:Debug("Guda_BagFrame exists: " .. tostring(getglobal("Guda_BagFrame") ~= nil))

		-- 尝试手动创建它
		self:CreateMoneyFrame()
		moneyFrame = getglobal("Guda_BagFrame_MoneyFrame")
	end

	if moneyFrame then
		MoneyFrame_Update("Guda_BagFrame_MoneyFrame", GetMoney())
		GudaBag.FormatMoneyFrameWithCommas("Guda_BagFrame_MoneyFrame")
		moneyFrame:Show()

		-- 确保提示覆盖层存在
		self:EnsureMoneyTooltipOverlay()

		-- 同时为工具栏空白区域添加提示
		self:SetupToolbarTooltip()
	else
		addon:Debug("Still couldn't find or create MoneyFrame!")
	end
end

-- 背包类型显示名称
local BAG_TYPE_NAMES = {
	soul = "Soul Bag",
	herb = "Herb Bag",
	enchant = "Enchanting Bag",
	quiver = "Quiver",
	ammo = "Ammo Pouch",
}

-- 更新背包槽位信息文本（只显示普通背包，特殊背包显示在提示中）
function BagFrame:UpdateBagSlotsInfo(bagData, isOtherChar)
	local infoText = getglobal("Guda_BagFrame_Toolbar_BagSlotsInfo_Text")
	if not infoText then return end

	local regularTotal = 0
	local regularUsed = 0
	local specialBags = {} -- { [type] = { total, used, name } }

	-- 统计背包 0-4 中的槽位，将普通背包与特殊背包分开
	for _, bagID in ipairs(addon.Constants.BAGS) do
		local bag = bagData[bagID]

		-- 获取此背包的槽位数量
		local numSlots
		if isOtherChar and bag and bag.numSlots then
			numSlots = bag.numSlots
		else
			numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
		end

		if numSlots and numSlots > 0 then
			-- 判断这是否是特殊背包
			local bagType = nil
			if not isOtherChar then
				bagType = addon.Modules.Utils:GetSpecializedBagType(bagID)
			elseif bag and bag.bagType and bag.bagType ~= "regular" then
				bagType = bag.bagType
			end

			-- 统计已使用的槽位
			local used = 0
			if bag and bag.slots then
				for slot = 1, numSlots do
					if bag.slots[slot] then
						used = used + 1
					end
				end
			end

			if bagType then
				-- 特殊背包
				if not specialBags[bagType] then
					specialBags[bagType] = { total = 0, used = 0, name = BAG_TYPE_NAMES[bagType] or bagType }
				end
				specialBags[bagType].total = specialBags[bagType].total + numSlots
				specialBags[bagType].used = specialBags[bagType].used + used
			else
				-- 普通背包
				regularTotal = regularTotal + numSlots
				regularUsed = regularUsed + used
			end
		end
	end

	-- 格式："24 / 80"（已用 / 总数） —— 仅普通背包
	infoText:SetText(string.format("%d / %d", regularUsed, regularTotal))
	infoText:SetTextColor(0.7, 0.7, 0.7)

	-- 调整信息框架大小以适配文本，使炉石能紧密锚定
	local infoFrame = getglobal("Guda_BagFrame_Toolbar_BagSlotsInfo")
	if infoFrame then
		local textWidth = infoText:GetStringWidth()
		if textWidth and textWidth > 0 then
			infoFrame:SetWidth(textWidth + 4)
		end
		infoFrame.regularTotal = regularTotal
		infoFrame.regularUsed = regularUsed
		infoFrame.specialBags = specialBags

		-- 若尚未设置，则设置提示脚本
		if not infoFrame.tooltipSetup then
			infoFrame:EnableMouse(true)
			infoFrame:SetScript("OnEnter", function()
				GameTooltip:SetOwner(this, "ANCHOR_TOP")
				GameTooltip:AddLine(GudaBag.L["Bag Slots"], 1, 1, 1)
				GameTooltip:AddLine(" ")
				-- 普通背包
				if this.regularTotal then
					GameTooltip:AddDoubleLine(GudaBag.L["Regular Bags:"], string.format("%d / %d", this.regularUsed, this.regularTotal), 1, 1, 1, 0.8, 0.8, 0.8)
				end
				-- 特殊背包
				if this.specialBags then
					for bagType, data in pairs(this.specialBags) do
						GameTooltip:AddDoubleLine(data.name .. ":", string.format("%d / %d", data.used, data.total), 1, 0.82, 0, 0.8, 0.8, 0.8)
					end
				end
				GameTooltip:Show()
			end)
			infoFrame:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			infoFrame.tooltipSetup = true
		end
	end
end

function BagFrame:CreateMoneyFrame()
	local moneyFrame = CreateFrame("Frame", "Guda_BagFrame_MoneyFrame", Guda_BagFrame, "SmallMoneyFrameTemplate")
	moneyFrame:SetPoint("BOTTOMRIGHT", Guda_BagFrame, "BOTTOMRIGHT", -15, 10)
	moneyFrame:SetWidth(180)
	moneyFrame:SetHeight(35)
	addon:Debug("MoneyFrame created via CreateMoneyFrame")
end

-- 炉石物品 ID
local HEARTHSTONE_ID = 6948

-- 法术搜索缓存（避免重复扫描法术书）
local _hearthSpellIndex = nil   -- 炉石法术（通用/法师传送门等）
local _astralSpellIndex = nil   -- 萨满星界传送
local _spellSearchDone = false

-- 创建炉石显示框架
function BagFrame:CreateHearthstoneFrame()
	local frameName = "Guda_BagFrame_HearthstoneFrame"
	if getglobal(frameName) then return end

	local toolbar = getglobal("Guda_BagFrame_Toolbar") or Guda_BagFrame
	local frame = CreateFrame("Button", frameName, toolbar)
	frame:SetWidth(20)
	frame:SetHeight(20)
	-- 默认锚点；稍后由 UpdateBaglineLayout 重新定位
	local info = getglobal("Guda_BagFrame_Toolbar_BagSlotsInfo")
	if info then
		frame:SetPoint("LEFT", info, "RIGHT", 6, 0)
	else
		frame:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
	end
	frame:SetFrameLevel((toolbar:GetFrameLevel() or 5) + 5)

	-- 图标贴图
	local icon = frame:CreateTexture(frameName .. "_Icon", "ARTWORK")
	icon:SetAllPoints(frame)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")

	-- 冷却框架（香草中使用 Model 类型配合 CooldownFrameTemplate）
	local cooldown = CreateFrame("Model", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
	cooldown:SetAllPoints(frame)
	cooldown:EnableMouse(false)
	frame.cooldown = cooldown

	-- 启用鼠标和点击
	frame:EnableMouse(true)
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	frame:SetScript("OnEnter", function()
		BagFrame:ShowHearthstoneTooltip(this)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame:SetScript("OnClick", function()
		BagFrame:UseHearthstone()
	end)
	frame:SetScript("OnMouseUp", function()
		if arg1 == "LeftButton" or arg1 == "RightButton" then
			BagFrame:UseHearthstone()
		end
	end)

	addon:Debug("HearthstoneFrame created")
end

-- 在背包中查找炉石
function BagFrame:FindHearthstone()
	-- 1. 先在背包中查找炉石物品
	for bag = 0, 4 do
		local numSlots = GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local itemId = addon.Modules.Utils:ExtractItemID(link)
				if itemId and itemId == HEARTHSTONE_ID then
					return bag, slot, link
				end
			end
		end
	end

	-- 2. 乌龟服：检查法术书中是否有炉石/星界传送
	if not _spellSearchDone then
		_spellSearchDone = true
		_hearthSpellIndex = self:FindUtilitySpell(
			{ "Hearthstone", "炉石", "Teleport" },
			{ "inv_misc_rune_01", "spell_nature_astralrecal" }
		)
		if not _hearthSpellIndex then
			_astralSpellIndex = self:FindUtilitySpell(
				{ "Astral Recall", "星界传送" },
				{ "spell_nature_astralrecal" }
			)
		end
	end

	return nil, nil, nil  -- 无物品炉石（可能有法术）
end

-- 检查法术炉石是否可用（非冷却中）
function BagFrame:FindHearthstoneSpell()
	local idx = _hearthSpellIndex or _astralSpellIndex
	if not idx then return nil end
	local name = GetSpellName(idx, BOOKTYPE_SPELL)
	local start, duration, enable = GetSpellCooldown(idx, BOOKTYPE_SPELL)
	-- 检查是否在冷却中
	if start and duration and duration > 0 then
		return idx, name, start, duration, enable, true
	end
	return idx, name, nil, nil, nil, false
end

-- 更新炉石显示
function BagFrame:UpdateHearthstone()
	local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
	local frame = getglobal("Guda_BagFrame_HearthstoneFrame")

	if hideFooter then
		if frame then frame:Hide() end
		return
	end

	if not frame then
		self:CreateHearthstoneFrame()
		frame = getglobal("Guda_BagFrame_HearthstoneFrame")
	end

	if not frame then return end

	-- 重置法术来源标记
	frame.useSpell = false
	frame.spellIndex = nil

	-- 1. 优先检查背包中的炉石物品
	local bag, slot, link = self:FindHearthstone()

	if bag then
		frame:SetAlpha(1)
		frame:Show()

		-- 更新图标为炉石物品图标
		local frameIcon = getglobal(frame:GetName() .. "_Icon")
		if frameIcon then frameIcon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01") end

		-- 更新冷却（物品）
		local start, duration, enable = GetContainerItemCooldown(bag, slot)
		if frame.cooldown and start and duration and duration > 0 then
			CooldownFrame_SetTimer(frame.cooldown, start, duration, enable)
		elseif frame.cooldown then
			frame.cooldown:Hide()
		end

		-- 存储位置以供使用
		frame.bag = bag
		frame.slot = slot
		frame.link = link
	else
		-- 2. 背包无炉石 → 检查法术炉石
		local spellIdx, spellName, sStart, sDuration, sEnable, onCooldown =
			self:FindHearthstoneSpell()

		if spellIdx then
			frame:SetAlpha(1)
			frame:Show()

			-- 更新图标为法术图标
			local frameIcon = getglobal(frame:GetName() .. "_Icon")
			local spellTex = GetSpellTexture(spellIdx, BOOKTYPE_SPELL)
			if frameIcon and spellTex then
				frameIcon:SetTexture(spellTex)
			end

			-- 更新冷却（法术）
			if onCooldown and frame.cooldown and sStart and sDuration and sDuration > 0 then
				CooldownFrame_SetTimer(frame.cooldown, sStart, sDuration, sEnable)
			elseif frame.cooldown then
				frame.cooldown:Hide()
			end

			-- 存储法术信息
			frame.useSpell = true
			frame.spellIndex = spellIdx
			frame.link = nil
			frame.bag = nil
			frame.slot = nil
		else
			-- 3. 既无法石物品也无炉石法术 → 半透明占位
			frame:SetAlpha(0.3)
			frame:Show()
			frame.bag = nil
			frame.slot = nil
			frame.link = nil
			frame.useSpell = false
			if frame.cooldown then
				frame.cooldown:Hide()
			end
		end
	end
end

-- 显示炉石提示
function BagFrame:ShowHearthstoneTooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_TOP")

	if frame.bag and frame.slot then
		GameTooltip:SetBagItem(frame.bag, frame.slot)
	elseif frame.useSpell and frame.spellIndex then
		GameTooltip:SetSpell(frame.spellIndex, BOOKTYPE_SPELL)
	else
		GameTooltip:ClearLines()
		GameTooltip:AddLine(GudaBag.L["Hearthstone"], 1, 1, 1)
		GameTooltip:AddLine(GudaBag.L["Not in bags"], 1, 0, 0)
	end

	GameTooltip:Show()
end

-- 使用炉石：物品用 UseContainerItem，法术用 CastSpellByName
function BagFrame:UseHearthstone()
	local frame = getglobal("Guda_BagFrame_HearthstoneFrame")
	if not frame then return end

	if frame.useSpell and frame.spellIndex then
		local spellName = GetSpellName(frame.spellIndex, BOOKTYPE_SPELL)
		if spellName then
			CastSpellByName(spellName)
		end
		return
	end

	if frame.bag and frame.slot then
		UseContainerItem(frame.bag, frame.slot)
	end
end

-- ============================================================================
-- 分解 / 开锁快捷按钮（背包表头）
-- 移植自 OneBag：排序按钮左侧的一键施法按钮。
-- 仅在玩家已学会相应技能时显示。
-- ============================================================================

-- 与语言环境无关的法术书扫描。`names` 是要匹配的本地化法术名称
--（英文 + zhCN + 其他任何语言）；`iconKeys` 是法术图标路径中
-- 用于兜底的子串（覆盖我们未列出名称的语言环境）。
-- 返回法术书索引，或 nil。
function BagFrame:FindUtilitySpell(names, iconKeys)
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if numSpells and numSpells > 0 then
            for spellIndex = (offset or 0) + 1, (offset or 0) + numSpells do
                local spellName = GetSpellName(spellIndex, BOOKTYPE_SPELL)
                if spellName then
                    for _, n in ipairs(names) do
                        if spellName == n then return spellIndex end
                    end
                end
                if iconKeys then
                    local tex = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
                    if tex then
                        local tl = string.lower(tex)
                        for _, key in ipairs(iconKeys) do
                            if string.find(tl, key, 1, true) then return spellIndex end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- 检查玩家是否拥有分解法术（即拥有附魔专业）
function BagFrame:HasDisenchant()
    local idx = self:FindUtilitySpell({ "Disenchant", "分解" }, nil)
    if idx then self._disenchantSpellIndex = idx end
    return idx ~= nil
end

-- ============================================================================
-- 开锁按钮（盗贼：开锁）
-- ============================================================================

-- 检查玩家是否学会了开锁的盗贼。职业检查与语言环境无关；
-- 法术匹配回退到英文名称和图标路径候选，
-- 这样在大多数语言环境下无需翻译表即可工作。
-- 盗贼工具（物品 5060）的存在 —— 实际使用开锁所需的物品。
function BagFrame:HasThievesTools()
	for bagID = 0, 4 do
		local numSlots = GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local link = GetContainerItemLink(bagID, slotID)
				if link then
					local _, _, idStr = string.find(link, "item:(%d+)")
					if idStr and tonumber(idStr) == 5060 then
						return true
					end
				end
			end
		end
	end
	return false
end

function BagFrame:HasLockpick()
	local idx = self:FindUtilitySpell({ "Pick Lock", "开锁" }, { "spell_nature_slow", "ability_rogue_pickpocket", "inv_misc_key_03" })
	if idx then self._lockpickSpellIndex = idx end
	return idx ~= nil
end

-- 显示/隐藏表头快捷按钮（排序按钮左侧）并设置其
-- 法术图标/索引。在背包打开时以及法术书变化时调用。
function BagFrame:RefreshUtilityButtons()
	local disBtn = getglobal("Guda_BagFrame_DisenchantButton")
	local pickBtn = getglobal("Guda_BagFrame_PickLockButton")

	-- 分解按钮
	if disBtn then
		if not disBtn._gudaTooltipSetup then
			disBtn._gudaTooltipSetup = true
			disBtn:SetScript("OnEnter", function()
				GameTooltip:SetOwner(this, "ANCHOR_TOP")
				GameTooltip:ClearLines()
				GameTooltip:SetText(GudaBag.L["Disenchant"] or "Disenchant")
				GameTooltip:AddLine(GudaBag.L["Click to cast Disenchant"] or "Click to cast Disenchant", 0.7, 0.7, 0.7)
				GameTooltip:Show()
			end)
			disBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		local disIdx = self:HasDisenchant() and self._disenchantSpellIndex
		if disIdx then
			disBtn:SetID(disIdx)
			disBtn:Show()
			local icon = getglobal(disBtn:GetName() .. "_Icon")
			if icon then
				-- OneBag 风格图标（打包的 Assets/soul）
				icon:SetTexture("Interface\\AddOns\\Guda\\Assets\\soul")
				icon:SetVertexColor(1, 1, 1)
			end
		else
			disBtn:Hide()
		end
	end

	-- 开锁按钮
	if pickBtn then
		if not pickBtn._gudaTooltipSetup then
			pickBtn._gudaTooltipSetup = true
			pickBtn:SetScript("OnEnter", function()
				GameTooltip:SetOwner(this, "ANCHOR_TOP")
				GameTooltip:ClearLines()
				GameTooltip:SetText(GudaBag.L["Lockpicking"] or "Pick Lock")
				if BagFrame and BagFrame.HasThievesTools and BagFrame:HasThievesTools() then
					GameTooltip:AddLine(GudaBag.L["Click to cast Pick Lock"] or "Click to cast Pick Lock", 0.7, 0.7, 0.7)
				else
					GameTooltip:AddLine(GudaBag.L["Requires Thieves' Tools"] or "Requires Thieves' Tools", 1, 0.3, 0.3)
				end
				GameTooltip:Show()
			end)
			pickBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		local pickIdx = self:HasLockpick() and self._lockpickSpellIndex
		if pickIdx then
			pickBtn:SetID(pickIdx)
			pickBtn:Show()
			local icon = getglobal(pickBtn:GetName() .. "_Icon")
			if icon then
				-- OneBag 风格图标（打包的 Assets/unlock）
				icon:SetTexture("Interface\\AddOns\\Guda\\Assets\\unlock")
				-- 缺少盗贼工具时调暗图标
				if self:HasThievesTools() then
					icon:SetVertexColor(1, 1, 1)
				else
					icon:SetVertexColor(0.4, 0.4, 0.4)
				end
			end
		else
			pickBtn:Hide()
		end
	end

	-- 将搜索切换按钮重新锚定到最左侧可见的工具按钮左侧，
	-- 使其始终紧贴 开锁/分解/排序 中最靠左的那个（间距一致）。
	local toggleBtn = getglobal("Guda_BagFrame_SearchToggleButton")
	local sortBtn   = getglobal("Guda_BagFrame_SortButton")
	if toggleBtn and sortBtn then
		local anchor = sortBtn
		if pickBtn and pickBtn:IsShown() then
			anchor = pickBtn
		elseif disBtn and disBtn:IsShown() then
			anchor = disBtn
		end
		toggleBtn:ClearAllPoints()
		toggleBtn:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
	end
end

-- 表头快捷按钮使用的全局点击处理函数（XML OnClick）
function GudaBag.BagFrame_UseDisenchant()
	if not BagFrame or not BagFrame.HasDisenchant then return end
	local idx = BagFrame._disenchantSpellIndex or (BagFrame:HasDisenchant() and BagFrame._disenchantSpellIndex)
	if idx then
		CastSpell(idx, BOOKTYPE_SPELL)
	end
end

function GudaBag.BagFrame_UsePickLock()
	if not BagFrame or not BagFrame.HasThievesTools then return end
	-- 没有盗贼工具时阻止点击 —— 法术只会报错。
	if not BagFrame:HasThievesTools() then return end
	local idx = BagFrame._lockpickSpellIndex or (BagFrame:HasLockpick() and BagFrame._lockpickSpellIndex)
	if idx then
		CastSpell(idx, BOOKTYPE_SPELL)
	end
end

-- 在工具栏空白区域设置提示
function BagFrame:SetupToolbarTooltip()
	local toolbar = getglobal("Guda_BagFrame_Toolbar")
	if not toolbar then return end

	-- 只设置一次
	if toolbar.tooltipSetup then return end

	-- 获取现有的 OnEnter 脚本（如果有）
	local originalOnEnter = toolbar:GetScript("OnEnter")

	-- 设置显示金钱提示的新 OnEnter
	toolbar:SetScript("OnEnter", function()
	-- 如果存在则调用原函数
		if originalOnEnter then
			originalOnEnter()
		end

		-- 显示金钱提示
		addon:Debug("Toolbar OnEnter - showing money tooltip")
		GudaBag.BagFrame_MoneyOnEnter(getglobal("Guda_BagFrame_MoneyFrame"))
	end)

	-- 设置 OnLeave 以隐藏提示
	toolbar:SetScript("OnLeave", function()
		addon:Debug("Toolbar OnLeave - hiding tooltip")
		GameTooltip:Hide()
	end)

	toolbar.tooltipSetup = true
	addon:Debug("Toolbar tooltip handlers set up")
end

-- 保存背包框架位置（始终保存为 BOTTOMRIGHT）
local function SaveBagFramePosition()
	local frame = getglobal("Guda_BagFrame")
	if not frame or not addon or not addon.Modules or not addon.Modules.DB then return end

	-- 始终保存为 BOTTOMRIGHT 坐标
	local right = frame:GetRight()
	local bottom = frame:GetBottom()
	local screenWidth = GetScreenWidth()

	if right and bottom and screenWidth then
		local xOffset = right - screenWidth
		local yOffset = bottom

		addon.Modules.DB:SetSetting("bagFramePosition", {
			point = "BOTTOMRIGHT",
			x = xOffset,
			y = yOffset
		})
	end
end

-- 集中化的移动开始/停止逻辑，使每个拖拽处理函数设置相同的标志，
-- 避免在六个重复的调用点之间发生漂移。
local function BeginFrameMove()
	local bagFrame = getglobal("Guda_BagFrame")
	if not bagFrame then return end
	-- 光标已持有物品时不应进入框架拖拽：用户是在拖物品/装备到背包，
	-- 而不是移动背包框架。若此处触发 StartMoving 会隐藏全部物品按钮
	-- 并令 isFrameMoving=true，导致物品放置事件无法正确路由。
	if CursorHasItem and CursorHasItem() then return end
	isFrameMoving = true
	-- 暂停后台工作队列（CacheWarmer 提示扫描等），使其
	-- 不会在每个渲染帧消耗 100ms 并拖垮拖拽帧率。
	if addon.Modules.Utils and addon.Modules.Utils.PauseWorkQueue then
		addon.Modules.Utils:PauseWorkQueue()
	end
	-- 隐藏全部物品按钮，降低原生 StartMoving 逐帧重绘数百个子区域
	-- 的渲染成本（否则拖动时帧率会从 ~150 骤降到 30-50）。
	-- 拖动结束后 EndFrameMove 里的 Update() 重建会恢复按钮。
	GudaBag.HideItemButtonsForDrag(bagParents)
	bagFrame:StartMoving()
end

local function EndFrameMove()
	local bagFrame = getglobal("Guda_BagFrame")
	if not bagFrame then return end
	-- 未在拖拽框架（BeginFrameMove 因光标持有物品被跳过）：不执行框架
	-- 停止/重建，避免干扰物品放置流程。
	if not isFrameMoving then return end
	bagFrame:StopMovingOrSizing()
	isFrameMoving = false
	SaveBagFramePosition()
	if addon.Modules.Utils and addon.Modules.Utils.ResumeWorkQueue then
		addon.Modules.Utils:ResumeWorkQueue()
	end
	-- 执行一次重建，以补上移动期间被短路跳过的任何内容。
	BagFrame:Update()
end


-- 为金钱提示创建透明覆盖层
function BagFrame:EnsureMoneyTooltipOverlay()
	local overlayName = "Guda_BagFrame_MoneyTooltipOverlay"
	local overlay = getglobal(overlayName)

	if not overlay then
		local moneyFrame = getglobal("Guda_BagFrame_MoneyFrame")
		if not moneyFrame then return end

		-- 创建透明覆盖层框架（高层级以位于金钱按钮之上）
		overlay = CreateFrame("Frame", overlayName, moneyFrame)
		overlay:SetAllPoints(moneyFrame)
		-- 必须与背包框架共享 FULLSCREEN_DIALOG 层级（并且位于
		-- 原生金钱按钮之上），否则点击会穿透到金钱按钮，
		-- 打开原生货币拆分菜单而不是我们的菜单。
		overlay:SetFrameStrata("FULLSCREEN_DIALOG")
		overlay:SetFrameLevel((moneyFrame:GetFrameLevel() or 0) + 5)
		overlay:EnableMouse(true)

		-- 在覆盖层上设置提示处理函数
		overlay:SetScript("OnEnter", function()
			addon:Debug("Money overlay OnEnter triggered")
			GudaBag.BagFrame_MoneyOnEnter(moneyFrame)
		end)

		overlay:SetScript("OnLeave", function()
			addon:Debug("Money overlay OnLeave triggered")
			GameTooltip:Hide()
		end)

		-- 将拖拽事件转发给背包框架（如果未锁定）
		overlay:SetScript("OnMouseDown", function()
			local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
			if searchBox then
				searchBox:ClearFocus()
			end

			local isLocked = addon.Modules.DB and addon.Modules.DB:GetSetting("lockBags")

			if not isLocked and arg1 == "LeftButton" then
				BeginFrameMove()
			end
		end)

		overlay:SetScript("OnMouseUp", function()
			if arg1 == "RightButton" then
				GudaBag.MoneyTooltip_Hide()
				GudaBag.ShowGoldTrackingMenu(moneyFrame)
				return
			end
			local isLocked = addon.Modules.DB and addon.Modules.DB:GetSetting("lockBags")

			if not isLocked then
				EndFrameMove()
			end
		end)

		addon:Debug("Money tooltip overlay created")
	end

	overlay:Show()
end

-- 金钱框架加载时处理函数
function GudaBag.BagFrame_MoneyFrame_OnLoad(self)
	addon:Debug("MoneyFrame OnLoad called for: " .. self:GetName())

	-- 禁用金币按钮的原生点击（打开 CoinPickupFrame 拆分货币）。
	-- SmallMoneyFrameTemplate 自带 OnClick；若未设置 maxMoney，点击会报错。
	-- 背包的货币交互由覆盖层（右键菜单）提供，不依赖原生拆分对话框。
	if GudaBag.DisableMoneyCoinButtons then
		GudaBag.DisableMoneyCoinButtons(self)
	end

	-- 在所有货币面额按钮上设置提示处理函数
	local buttons = {"GoldButton", "SilverButton", "CopperButton"}

	for _, buttonName in ipairs(buttons) do
		local fullName = self:GetName() .. buttonName
		local button = getglobal(fullName)
		addon:Debug("Looking for button: " .. fullName .. " - Found: " .. tostring(button ~= nil))
		if button then
			button:SetScript("OnEnter", function()
				addon:Debug("Money button OnEnter triggered")
				GudaBag.BagFrame_MoneyOnEnter(this:GetParent())
			end)
			button:SetScript("OnLeave", function()
				GudaBag.MoneyTooltip_Hide()
			end)
		end
	end

	-- 也尝试直接在父框架上设置处理函数
	addon:Debug("Setting handlers on parent frame as fallback")
	self:EnableMouse(true)
	self:SetScript("OnEnter", function()
		addon:Debug("Parent frame OnEnter triggered")
		GudaBag.BagFrame_MoneyOnEnter(this)
	end)
	self:SetScript("OnLeave", function()
		GudaBag.MoneyTooltip_Hide()
	end)
end

-- 带硬币图标的自定义金钱提示
local moneyTooltip = nil
local moneyTooltipRows = {}

-- 用千位分隔符格式化数字（例如 1234567 -> "1,234,567"）
local function FormatWithCommas(n)
	local s = tostring(n)
	local len = string.len(s)
	if len <= 3 then return s end
	local parts = {}
	local pos = len
	while pos > 0 do
		local start = pos - 2
		if start < 1 then start = 1 end
		table.insert(parts, 1, string.sub(s, start, pos))
		pos = start - 1
	end
	return table.concat(parts, ",")
end

-- 对 MoneyFrame 的金币按钮文本应用逗号格式化（全局函数，供 BankFrame 复用）
function GudaBag.FormatMoneyFrameWithCommas(frameName)
	local goldBtn = getglobal(frameName .. "GoldButtonText")
	if goldBtn then
		local text = goldBtn:GetText()
		if text then
			local num = tonumber(text)
			if num and num >= 1000 then
				goldBtn:SetText(FormatWithCommas(num))
			end
		end
	end
end

local function DisableMoneyFrameAutoUpdate(frameName)
	local frame = getglobal(frameName)
	if frame then
		frame.moneyType = "STATIC"
		frame:UnregisterAllEvents()
		frame:SetScript("OnShow", nil)
		frame:SetScript("OnEvent", nil)
	end
	-- 禁用面额按钮的点击/悬停
	local buttons = {"GoldButton", "SilverButton", "CopperButton"}
	for _, btn in ipairs(buttons) do
		local b = getglobal(frameName .. btn)
		if b then
			b:EnableMouse(false)
		end
	end
end

local function CreateMoneyTooltip()
	local f = CreateFrame("Frame", "Guda_MoneyTooltip", UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0, 0, 0, 0.9)
	f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
	f:EnableMouse(false)
	f:Hide()

	-- 鼠标离开锚点和提示区域时自动隐藏
	local elapsed = 0
	f:SetScript("OnUpdate", function()
		elapsed = elapsed + arg1
		if elapsed < 0.2 then return end
		elapsed = 0
		if not this.anchor then this:Hide(); return end
		if MouseIsOver(this) then return end
		if MouseIsOver(this.anchor) then return end
		this.anchor = nil
		this:Hide()
	end)

	-- 表头标签
	f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
	f.header:SetText(GudaBag.L["Current realm gold"])
	f.header:SetTextColor(1, 0.82, 0)

	-- 表头金钱框架（总额）—— 锚定到右边缘，与表头同一行
	f.totalMoney = CreateFrame("Frame", "Guda_MoneyTooltip_Total", f, "SmallMoneyFrameTemplate")
	f.totalMoney:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
	DisableMoneyFrameAutoUpdate("Guda_MoneyTooltip_Total")

	-- 底部提示文本
	f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.hint:SetText(GudaBag.L["Right-click to manage characters"])
	f.hint:SetTextColor(0.5, 0.5, 0.5)

	return f
end

local function GetOrCreateMoneyRow(index)
	if moneyTooltipRows[index] then return moneyTooltipRows[index] end
	local row = {}
	local frameName = "Guda_MoneyTooltip_Row" .. index
	row.label = moneyTooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.money = CreateFrame("Frame", frameName, moneyTooltip, "SmallMoneyFrameTemplate")
	DisableMoneyFrameAutoUpdate(frameName)
	moneyTooltipRows[index] = row
	return row
end

-- 共享的金钱提示处理函数（BagFrame 和 BankFrame 都使用）
function GudaBag.MoneyTooltip_Show(anchor)
	if not anchor then return end

	if not moneyTooltip then
		moneyTooltip = CreateMoneyTooltip()
	end

	-- 隐藏 GameTooltip 以避免重叠
	GameTooltip:Hide()

	local allChars = addon.Modules.DB:GetAllCharacters(false, false) -- 所有服务器
	local totalMoney = 0

	-- 将非黑名单角色先按账号分组，再按服务器分组
	local accounts = {} -- 账号 -> { realms = { realm -> { chars, money } }, money, order }
	local accountOrder = {}
	local myAccountLabel = "Current Account"

	for _, char in ipairs(allChars) do
		if not addon.Modules.DB:IsGoldBlacklisted(char.fullName) then
			local acctKey = char.isShared and (char.account or "Other") or myAccountLabel
			if not accounts[acctKey] then
				accounts[acctKey] = { realms = {}, realmOrder = {}, money = 0 }
				table.insert(accountOrder, acctKey)
			end
			local acct = accounts[acctKey]
			local realm = char.realm or "Unknown"
			if not acct.realms[realm] then
				acct.realms[realm] = { chars = {}, money = 0 }
				table.insert(acct.realmOrder, realm)
			end
			table.insert(acct.realms[realm].chars, char)
			acct.realms[realm].money = acct.realms[realm].money + (char.money or 0)
			acct.money = acct.money + (char.money or 0)
			totalMoney = totalMoney + (char.money or 0)
		end
	end

	-- 排序：自己的账号在前，其余按字母顺序排列
	table.sort(accountOrder, function(a, b)
		if a == myAccountLabel then return true end
		if b == myAccountLabel then return false end
		return a < b
	end)
	for _, acct in pairs(accounts) do
		table.sort(acct.realmOrder)
	end

	-- 更新表头金钱
	moneyTooltip.header:SetText(GudaBag.L["Total gold"])
	MoneyFrame_Update("Guda_MoneyTooltip_Total", totalMoney)
	GudaBag.FormatMoneyFrameWithCommas("Guda_MoneyTooltip_Total")

	-- 布局行
	local rowHeight = 18
	local padding = 10
	local yOffset = -10 - 20 - 14  -- 顶部内边距 + 表头高度 + 间距
	local rowIndex = 0
	local hasMultipleAccounts = table.getn(accountOrder) > 1

	for _, acctKey in ipairs(accountOrder) do
		local acctData = accounts[acctKey]

		-- 账号表头（仅当存在多个账号时显示）
		if hasMultipleAccounts then
			rowIndex = rowIndex + 1
			local row = GetOrCreateMoneyRow(rowIndex)
			row.label:SetTextColor(0.5, 0.8, 1) -- 账号表头使用浅蓝色
			row.label:SetText(acctKey)
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", moneyTooltip, "TOPLEFT", padding, yOffset)
			row.label:Show()

			local frameName = "Guda_MoneyTooltip_Row" .. rowIndex
			MoneyFrame_Update(frameName, acctData.money)
			GudaBag.FormatMoneyFrameWithCommas(frameName)
			row.money:ClearAllPoints()
			row.money:SetPoint("TOPRIGHT", moneyTooltip, "TOPRIGHT", -padding, yOffset)
			row.money:Show()

			yOffset = yOffset - rowHeight
		end

		local indent = hasMultipleAccounts and "  " or ""

		for _, realm in ipairs(acctData.realmOrder) do
			local realmData = acctData.realms[realm]

			-- 服务器表头行
			rowIndex = rowIndex + 1
			local row = GetOrCreateMoneyRow(rowIndex)
			row.label:SetTextColor(1, 0.82, 0) -- 服务器表头使用金色
			row.label:SetText(indent .. realm)
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", moneyTooltip, "TOPLEFT", padding, yOffset)
			row.label:Show()

			local frameName = "Guda_MoneyTooltip_Row" .. rowIndex
			MoneyFrame_Update(frameName, realmData.money)
			GudaBag.FormatMoneyFrameWithCommas(frameName)
			row.money:ClearAllPoints()
			row.money:SetPoint("TOPRIGHT", moneyTooltip, "TOPRIGHT", -padding, yOffset)
			row.money:Show()

			yOffset = yOffset - rowHeight

			-- 角色行
			for _, char in ipairs(realmData.chars) do
				rowIndex = rowIndex + 1
				row = GetOrCreateMoneyRow(rowIndex)

				local classToken = char.classToken
				local classColor = classToken and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
				local r, g, b = 0.7, 0.7, 0.7
				if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

				row.label:SetTextColor(r, g, b)
				row.label:SetText(indent .. "  " .. char.name)
				row.label:ClearAllPoints()
				row.label:SetPoint("TOPLEFT", moneyTooltip, "TOPLEFT", padding, yOffset)
				row.label:Show()

				frameName = "Guda_MoneyTooltip_Row" .. rowIndex
				MoneyFrame_Update(frameName, char.money or 0)
				GudaBag.FormatMoneyFrameWithCommas(frameName)
				row.money:ClearAllPoints()
				row.money:SetPoint("TOPRIGHT", moneyTooltip, "TOPRIGHT", -padding, yOffset)
				row.money:Show()

				yOffset = yOffset - rowHeight
			end
		end
	end

	-- 隐藏未使用的行
	for i = rowIndex + 1, table.getn(moneyTooltipRows) do
		if moneyTooltipRows[i] then
			moneyTooltipRows[i].label:Hide()
			moneyTooltipRows[i].money:Hide()
		end
	end

	-- 定位提示
	local hintHeight = 14
	local hintGap = 6
	moneyTooltip.hint:ClearAllPoints()
	moneyTooltip.hint:SetPoint("TOPLEFT", moneyTooltip, "TOPLEFT", padding, yOffset - hintGap)
	moneyTooltip.hint:Show()

	-- 计算框架尺寸
	local totalHeight = 10 + 20 + 14 + (rowIndex * rowHeight) + hintGap + hintHeight + padding
	local maxNameWidth = moneyTooltip.header:GetStringWidth()
	local hintWidth = moneyTooltip.hint:GetStringWidth()
	if hintWidth > maxNameWidth then maxNameWidth = hintWidth end
	local maxMoneyWidth = moneyTooltip.totalMoney:GetWidth()
	for i = 1, rowIndex do
		local row = moneyTooltipRows[i]
		if row and row.label:IsShown() then
			local nw = row.label:GetStringWidth()
			if nw > maxNameWidth then maxNameWidth = nw end
			local mw = row.money:GetWidth()
			if mw > maxMoneyWidth then maxMoneyWidth = mw end
		end
	end
	local gap = 20
	moneyTooltip:SetWidth(maxNameWidth + gap + maxMoneyWidth + padding * 2 + 10)
	moneyTooltip:SetHeight(totalHeight)

	-- 锚定到金钱框架上方
	moneyTooltip:ClearAllPoints()
	moneyTooltip:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
	moneyTooltip.anchor = anchor
	moneyTooltip:Show()
end

function GudaBag.MoneyTooltip_Hide()
	if moneyTooltip then
		moneyTooltip.anchor = nil
		moneyTooltip:Hide()
	end
end

-- 移除角色的确认对话框
StaticPopupDialogs["GUDA_REMOVE_CHARACTER"] = {
	text = (GudaBag.L and GudaBag.L["Remove from Guda tracking?"]) or "Remove %s from Guda tracking?\n\nThis will delete all saved data for this character.",
	button1 = (GudaBag.L and GudaBag.L["Remove"]) or "Remove",
	button2 = (GudaBag.L and GudaBag.L["Cancel"]) or "Cancel",
	OnAccept = function()
		local fullName = Guda._pendingRemoveChar
		if fullName then
			addon.Modules.DB:RemoveCharacter(fullName)
			Guda._pendingRemoveChar = nil
			if moneyTooltip and moneyTooltip:IsShown() and moneyTooltip.anchor then
				GudaBag.MoneyTooltip_Show(moneyTooltip.anchor)
			end
		end
	end,
	OnCancel = function()
		Guda._pendingRemoveChar = nil
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

-- 辅助函数：在给定层级为金币跟踪下拉菜单添加角色条目
local function AddGoldTrackingCharEntries(chars, level)
	local currentPlayerFullName = addon.Modules.DB:GetPlayerFullName()
	for _, char in ipairs(chars) do
		local charFullName = char.fullName
		local charName = char.name
		local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
		local r, g, b = 1, 1, 1
		if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

		-- 第 1 行：带角色名的复选框
		local info = {}
		info.text = addon.Modules.Utils:ColorText(charName, r, g, b)
		info.checked = not addon.Modules.DB:IsGoldBlacklisted(charFullName)
		info.keepShownOnClick = 1
		info.func = function()
			addon.Modules.DB:ToggleGoldBlacklist(charFullName)
			if moneyTooltip and moneyTooltip:IsShown() and moneyTooltip.anchor then
				GudaBag.MoneyTooltip_Show(moneyTooltip.anchor)
			end
		end
		UIDropDownMenu_AddButton(info, level)

		-- 第 2 行：[X] 移除（缩进，感觉更小，当前角色跳过）
		if charFullName ~= currentPlayerFullName then
			local del = {}
			del.text = "     |cFF888888[|r|cFFFF4444X|r|cFF888888]|r |cFF666666" .. ((GudaBag.L and GudaBag.L["Remove"]) or "Remove") .. "|r"
			del.notCheckable = 1
			del.func = function()
				Guda._pendingRemoveChar = charFullName
				CloseDropDownMenus()
				StaticPopup_Show("GUDA_REMOVE_CHARACTER", charName)
			end
			UIDropDownMenu_AddButton(del, level)
		end
	end
end

-- 金币跟踪下拉菜单（按账号 > 服务器 > 角色分组）
local function GoldTrackingMenu_Initialize()
	local characters = addon.Modules.DB:GetAllCharacters(false, false) -- 所有服务器
	local myAccountLabel = "Current Account"

	-- 先按账号分组，再按服务器分组
	local accounts = {}
	local accountOrder = {}
	for _, char in ipairs(characters) do
		local acctKey = char.isShared and (char.account or "Other") or myAccountLabel
		if not accounts[acctKey] then
			accounts[acctKey] = { realms = {}, realmOrder = {} }
			table.insert(accountOrder, acctKey)
		end
		local acct = accounts[acctKey]
		local realm = char.realm or "Unknown"
		if not acct.realms[realm] then
			acct.realms[realm] = {}
			table.insert(acct.realmOrder, realm)
		end
		table.insert(acct.realms[realm], char)
	end

	table.sort(accountOrder, function(a, b)
		if a == myAccountLabel then return true end
		if b == myAccountLabel then return false end
		return a < b
	end)
	for _, acct in pairs(accounts) do
		table.sort(acct.realmOrder)
	end

	local level = UIDROPDOWNMENU_MENU_LEVEL or 1

	if level == 1 then
		-- 第 1 层："账号 - 服务器"合并条目（最多两层深度）
		for _, acctKey in ipairs(accountOrder) do
			local acct = accounts[acctKey]
			for _, realm in ipairs(acct.realmOrder) do
				local info = {}
				if table.getn(accountOrder) > 1 then
					info.text = acctKey .. " - " .. realm
				else
					info.text = realm
				end
				info.notCheckable = 1
				info.hasArrow = 1
				info.value = acctKey .. "|" .. realm
				UIDropDownMenu_AddButton(info, 1)
			end
		end
	elseif level == 2 then
		-- 第 2 层：角色
		local parentValue = UIDROPDOWNMENU_MENU_VALUE
		local _, _, acctKey, realm = string.find(parentValue, "^(.+)|(.+)$")
		local acct = accounts[acctKey]
		local chars = acct and acct.realms[realm]
		if chars then
			AddGoldTrackingCharEntries(chars, 2)
		end
		GudaBag.ScaleDropdownFonts(12)
	end
end

function GudaBag.ShowGoldTrackingMenu(anchor)
	local menuFrame = getglobal("Guda_GoldTrackingMenu")
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "Guda_GoldTrackingMenu", UIParent, "UIDropDownMenuTemplate")
	end
	UIDropDownMenu_Initialize(menuFrame, GoldTrackingMenu_Initialize, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
	GudaBag.ScaleDropdownFonts(12)
end

-- 金钱提示处理函数（BagFrame 入口）
function GudaBag.BagFrame_MoneyOnEnter(self)
	GudaBag.MoneyTooltip_Show(self)
end

-- 辅助函数：将角色分为自己的和共享的，并按黑名单过滤
local function GetSplitCharacters(currentRealmOnly)
	local characters = addon.Modules.DB:GetAllCharacters(false, currentRealmOnly)
	local currentPlayerFullName = addon.Modules.DB:GetPlayerFullName()
	local own, shared = {}, {}
	for _, char in ipairs(characters) do
		if not addon.Modules.DB:IsGoldBlacklisted(char.fullName) or char.fullName == currentPlayerFullName then
			if char.isShared then
				table.insert(shared, char)
			else
				table.insert(own, char)
			end
		end
	end
	return own, shared, currentPlayerFullName
end

-- 辅助函数：向下拉菜单添加账号分隔表头
local function AddAccountSeparator(label)
	local info = {}
	info.text = label
	info.isTitle = 1
	info.notCheckable = 1
	UIDropDownMenu_AddButton(info)
end

-- 下拉菜单管理
local function BagCharacterMenu_Initialize()
	local own, shared, currentPlayerFullName = GetSplitCharacters(true)
	local currentViewChar = addon.Modules.BagFrame:GetCurrentViewChar()

	for _, char in ipairs(own) do
		local charFullName = char.fullName
		local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
		local r, g, b = 1, 1, 1
		if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

		local info = {}
		info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
		info.func = function()
			if charFullName == currentPlayerFullName then
				addon.Modules.BagFrame:ShowCurrentCharacter()
			else
				addon.Modules.BagFrame:ShowCharacter(charFullName)
			end
		end
		info.checked = (currentViewChar == charFullName or (not currentViewChar and charFullName == currentPlayerFullName))
		UIDropDownMenu_AddButton(info)
	end

	if table.getn(shared) > 0 then
		AddAccountSeparator("Other Accounts")
		for _, char in ipairs(shared) do
			local charFullName = char.fullName
			local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
			local r, g, b = 1, 1, 1
			if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

			local info = {}
			info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
			info.func = function()
				addon.Modules.BagFrame:ShowCharacter(charFullName)
			end
			info.checked = (currentViewChar == charFullName)
			UIDropDownMenu_AddButton(info)
		end
	end
end

-- 切换角色下拉菜单
function GudaBag.BagFrame_ToggleCharacterDropdown(button)
	local menuFrame = getglobal("Guda_BagCharacterMenu")
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "Guda_BagCharacterMenu", UIParent, "UIDropDownMenuTemplate")
	end
	UIDropDownMenu_Initialize(menuFrame, BagCharacterMenu_Initialize, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
	GudaBag.ScaleDropdownFonts(12)
end

-- 邮箱角色下拉菜单
local function BagMailboxMenu_Initialize()
	local own, shared, currentPlayerFullName = GetSplitCharacters(true)
	local mailboxViewChar = addon.Modules.MailboxFrame and addon.Modules.MailboxFrame.GetCurrentViewChar and addon.Modules.MailboxFrame:GetCurrentViewChar()

	for _, char in ipairs(own) do
		local charFullName = char.fullName
		local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
		local r, g, b = 1, 1, 1
		if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

		local info = {}
		info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
		info.func = function()
			if addon.Modules.MailboxFrame and addon.Modules.MailboxFrame.ShowCharacter then
				addon.Modules.MailboxFrame:ShowCharacter(charFullName)
			end
			if Guda_MailboxFrame and not Guda_MailboxFrame:IsShown() then
				Guda_MailboxFrame:Show()
			end
		end
		info.checked = (mailboxViewChar == charFullName or (not mailboxViewChar and charFullName == currentPlayerFullName))
		UIDropDownMenu_AddButton(info)
	end

	if table.getn(shared) > 0 then
		AddAccountSeparator("Other Accounts")
		for _, char in ipairs(shared) do
			local charFullName = char.fullName
			local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
			local r, g, b = 1, 1, 1
			if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

			local info = {}
			info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
			info.func = function()
				if addon.Modules.MailboxFrame and addon.Modules.MailboxFrame.ShowCharacter then
					addon.Modules.MailboxFrame:ShowCharacter(charFullName)
				end
				if Guda_MailboxFrame and not Guda_MailboxFrame:IsShown() then
					Guda_MailboxFrame:Show()
				end
			end
			info.checked = (mailboxViewChar == charFullName)
			UIDropDownMenu_AddButton(info)
		end
	end
end

-- 切换邮件下拉菜单
function GudaBag.BagFrame_ToggleMailDropdown(button)
	local menuFrame = getglobal("Guda_BagMailboxMenu")
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "Guda_BagMailboxMenu", UIParent, "UIDropDownMenuTemplate")
	end
	UIDropDownMenu_Initialize(menuFrame, BagMailboxMenu_Initialize, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
	GudaBag.ScaleDropdownFonts(12)
end

-- 银行角色下拉菜单
local function BagBankMenu_Initialize()
	local own, shared, currentPlayerFullName = GetSplitCharacters(true)
	local bankViewChar = addon.Modules.BankFrame:GetCurrentViewChar()

	for _, char in ipairs(own) do
		local charFullName = char.fullName
		local charName = char.name
		local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
		local r, g, b = 1, 1, 1
		if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

		local info = {}
		info.text = addon.Modules.Utils:ColorText(charName, r, g, b)
		info.func = function()
			GudaBag.BagFrame_ShowCharacterBank(charFullName, charName)
		end
		info.checked = (bankViewChar == charFullName or (not bankViewChar and charFullName == currentPlayerFullName))
		UIDropDownMenu_AddButton(info)
	end

	if table.getn(shared) > 0 then
		AddAccountSeparator("Other Accounts")
		for _, char in ipairs(shared) do
			local charFullName = char.fullName
			local charName = char.name
			local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
			local r, g, b = 1, 1, 1
			if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

			local info = {}
			info.text = addon.Modules.Utils:ColorText(charName, r, g, b)
			info.func = function()
				GudaBag.BagFrame_ShowCharacterBank(charFullName, charName)
			end
			info.checked = (bankViewChar == charFullName)
			UIDropDownMenu_AddButton(info)
		end
	end
end

-- 切换银行下拉菜单
function GudaBag.BagFrame_ToggleBankDropdown(button)
	local menuFrame = getglobal("Guda_BagBankMenu")
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "Guda_BagBankMenu", UIParent, "UIDropDownMenuTemplate")
	end
	UIDropDownMenu_Initialize(menuFrame, BagBankMenu_Initialize, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
	GudaBag.ScaleDropdownFonts(12)
end

-- 显示角色的银行
function GudaBag.BagFrame_ShowCharacterBank(fullName, displayName)
-- 使用现有的 BankFrame 模块
	if not addon.Modules.BankFrame then
		addon:Print(GudaBag.L["Bank frame module not available"])
		return
	end

	-- 显示角色的银行（位置从保存的变量中恢复，
	-- 因此窗口会在用户上次放置的位置重新打开）。
	addon.Modules.BankFrame:ShowCharacter(fullName)

	-- 确保框架被显示
	if Guda_BankFrame then
		Guda_BankFrame:Show()
	end
end

-- 清除搜索并恢复占位文本
function GudaBag.BagFrame_ClearSearch()
	local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
	if searchBox then
		searchBox:SetText(GudaBag.L["Search, try ~equipment"])
		searchBox:SetTextColor(0.5, 0.5, 0.5, 1)
		searchBox:ClearFocus()
	end

	-- 重置搜索状态
	searchText = ""
	BagFrame.foundFirstMatch = false
	BagFrame.warnedAboutParsing = false
	BagFrame.warnedAboutNoName = false

	-- 更新显示（快速路径重新着色；布局不受清除搜索影响）
	if BagFrame.ReapplySearchFilter then
		BagFrame:ReapplySearchFilter()
	else
		BagFrame:Update()
	end
end

-- 为当前可见的每个有物品的背包槽位排队一次 Utils:GetTooltipText 预热。
-- 用户第一次输入 ~t: 查询时，在每个会话中运行一次 —— 后续击键
-- 会命中已预热的缓存并即时过滤。通过 Utils:QueueWork 做帧预算
-- 控制，因此输入保持响应。
local tooltipTextWarmed = false
local function WarmTooltipTextCache()
	if tooltipTextWarmed then return end
	tooltipTextWarmed = true
	local Utils = addon.Modules.Utils
	if not Utils or not Utils.QueueWork or not Utils.GetTooltipText then return end
	for bagID = 0, 4 do
		local numSlots = GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local link = GetContainerItemLink(bagID, slotID)
				if link then
					local b, s, l = bagID, slotID, link
					Utils:QueueWork(function()
						Utils:GetTooltipText(b, s, l)
					end, "tooltipTextSearchWarmup")
				end
			end
		end
	end
end

-- 搜索变化处理函数
function GudaBag.BagFrame_OnSearchChanged(self)
	local text = self:GetText()
	-- 忽略占位文本
	if text == GudaBag.L["Search, try ~equipment"] then
		text = ""
	end
	if text ~= searchText then
		searchText = text
		BagFrame.foundFirstMatch = false  -- 重置调试标志
		BagFrame.warnedAboutParsing = false
		BagFrame.warnedAboutNoName = false
		-- 如果查询使用了 ~t:，启动一次性的提示文本预热。
		-- 模式不存在时 string.find 返回 nil；使用 plain=true 来按字面
		-- 匹配 "~t:"（模式中没有魔法字符）。
		if string.find(text, "~t:", 1, true) then
			WarmTooltipTextCache()
		end
		-- 快速路径：重新着色现有按钮；布局不受搜索
		-- 字符串影响，因此在这里完整重建是浪费工作。
		if BagFrame.ReapplySearchFilter then
			BagFrame:ReapplySearchFilter()
		else
			BagFrame:Update()
		end
	end
end

-- 钥匙链开关处理函数
function GudaBag.BagFrame_ToggleKeyring()
	showKeyring = not showKeyring

	-- 更新按钮外观以显示开关状态
	local button = getglobal("Guda_BagFrame_Toolbar_KeyringButton")
	if button then
		if showKeyring then
			-- 激活时使用金色边框
			button:SetBackdropBorderColor(1, 0.82, 0, 1)
		else
			-- 非激活时恢复主题边框
			local fb = addon.Modules.Theme:GetValue("footerButtonBorder") or { 0.30, 0.30, 0.30, 1 }
			button:SetBackdropBorderColor(fb[1], fb[2], fb[3], fb[4])
		end
	end

	-- 刷新显示
	BagFrame:Update()
end

-- 灵魂袋开关处理函数
function GudaBag.BagFrame_ToggleSoulBag()
	showSoulBag = not showSoulBag

	-- 更新按钮外观以显示开关状态
	local button = getglobal("Guda_BagFrame_Toolbar_SoulBagButton")
	if button then
		if showSoulBag then
			-- 激活时使用金色边框
			button:SetBackdropBorderColor(1, 0.82, 0, 1)
		else
			-- 非激活时恢复主题边框
			local fb = addon.Modules.Theme:GetValue("footerButtonBorder") or { 0.30, 0.30, 0.30, 1 }
			button:SetBackdropBorderColor(fb[1], fb[2], fb[3], fb[4])
		end
	end

	-- 刷新显示
	BagFrame:Update()
end

-- 更新灵魂袋按钮上的灵魂碎片数量
function GudaBag.BagFrame_UpdateSoulBagCount()
	local button = getglobal("Guda_BagFrame_Toolbar_SoulBagButton")
	if not button or not button:IsShown() then return end

	local count = 0
	for _, bagID in ipairs(addon.Constants.BAGS) do
		local bagType = addon.Modules.Utils:GetSpecializedBagType(bagID)
		if bagType == "soul" then
			local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
			for slotID = 1, numSlots do
				local texture, itemCount = GetContainerItemInfo(bagID, slotID)
				if texture then
					count = count + (itemCount or 1)
				end
			end
		end
	end

	button.soulShardCount = count
	if button.countText then
		if count > 0 then
			button.countText:SetText(tostring(count))
			button.countText:Show()
		else
			button.countText:SetText("")
			button.countText:Hide()
		end
	end
end

-- 绑定背包排序按钮：用 Lua SetScript 可靠获取鼠标按键（左键正序、右键倒序），
-- 并覆盖 XML 的 OnClick / OnEnter（增加右键倒序提示）。
local function SetupSortButton()
	local sortBtn = getglobal("Guda_BagFrame_SortButton")
	if not sortBtn then return end

	-- WoW 1.12：XML 按钮默认只注册左键，需显式注册右键才能触发 OnClick
	sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	sortBtn:SetScript("OnClick", function()
		-- WoW 1.12：handler 不传参数，鼠标按键在全局 arg1
		GudaBag.BagFrame_Sort(arg1)
	end)

	sortBtn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(sortBtn, "ANCHOR_TOP")
		if sortBtn.isCategoryView then
			GameTooltip:SetText(GudaBag.L["Restack and Clean"])
			GameTooltip:AddLine(GudaBag.L["Merges split stacks and refreshes the view"], 0.7, 0.7, 0.7)
		else
			GameTooltip:SetText(GudaBag.L["Sort Bags"])
			GameTooltip:AddLine(GudaBag.L["Left-click: sort ascending | Right-click: sort descending"], 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
end

function GudaBag.BagFrame_Sort(mouseButton)
	if currentViewChar then
		addon:Print(GudaBag.L["Cannot sort another character's bags!"])
		return
	end

	-- 检查是否处于分类视图 —— 重整并清理
	local sortBtn = getglobal("Guda_BagFrame_SortButton")
	if sortBtn and sortBtn.isCategoryView then
		GudaBag.BagFrame_MergeStacks()
		return
	end

	-- 单视图：左键正序、右键倒序（SortEngine 内部使用移植自 OneBag 的排序算法，
	-- 会先弹出确认对话框，且只在源/目标未锁定时移动；被拦截时内部已提示）
	addon.Modules.SortEngine:ExecuteSort(nil, nil, nil, "bags", mouseButton)
end

-- 重整并清理（用于分类视图）—— 合并堆叠并刷新视图
-- 基于队列的方法
function GudaBag.BagFrame_MergeStacks()
	if currentViewChar then
		addon:Print(GudaBag.L["Cannot restack for another character!"])
		return
	end

	-- 检查排序是否已在进行中
	if addon.Modules.SortEngine.sortingInProgress then
		addon:Print(GudaBag.L["Sorting already in progress, please wait..."])
		return
	end

	local bagIDs = addon.Constants.BAGS
	local moveQueue = {}

	-- 按物品分组收集所有不完整的堆叠
	local partialStacks = {}
	for _, bagID in ipairs(bagIDs) do
		local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
		if numSlots and numSlots > 0 then
			for slot = 1, numSlots do
				local link = GetContainerItemLink(bagID, slot)
				if link then
					local texture, count = GetContainerItemInfo(bagID, slot)
					local _, _, itemID = string.find(link, "item:(%d+)")
					itemID = tonumber(itemID)
					
					if itemID then
						local _, _, _, _, _, _, itemStackCount = GetItemInfo(itemID)
						local maxStack = tonumber(itemStackCount) or 1
						
						-- 只跟踪可以堆叠且未满的物品
						if maxStack > 1 and count < maxStack then
							local groupKey = tostring(itemID)
							if not partialStacks[groupKey] then
								partialStacks[groupKey] = {
									maxStack = maxStack,
									stacks = {}
								}
							end
							table.insert(partialStacks[groupKey].stacks, {
								bagID = bagID,
								slot = slot,
								count = count
							})
						end
					end
				end
			end
		end
	end

	-- 为每个物品分组构建移动队列
	for _, group in pairs(partialStacks) do
		if table.getn(group.stacks) > 1 then
			-- 排序堆叠：大堆叠在前（目标），小堆叠在后（来源）
			table.sort(group.stacks, function(a, b)
				if not a then return false end
				if not b then return true end
				return (a.count or 0) > (b.count or 0)
			end)

			local sourceLoopStart = table.getn(group.stacks)

			-- 从头处理目标，从尾处理来源
			for targetIdx = 1, table.getn(group.stacks) - 1 do
				local target = group.stacks[targetIdx]
				
				if target.count < group.maxStack and target.count > 0 then
					for sourceIdx = sourceLoopStart, targetIdx + 1, -1 do
						local source = group.stacks[sourceIdx]
						
						if source.count > 0 and target.count < group.maxStack then
							-- 将此移动加入队列
							table.insert(moveQueue, {
								source = source,
								target = target,
								maxStack = group.maxStack
							})
							
							-- 计算变化（用于队列规划）
							local oldTargetCount = target.count
							target.count = math.min(target.count + source.count, group.maxStack)
							source.count = source.count - (target.count - oldTargetCount)
							
							-- 如果来源耗尽则移动来源指针
							if source.count == 0 then
								sourceLoopStart = sourceLoopStart - 1
							end
							
							-- 如果目标已满则停止
							if target.count >= group.maxStack then
								break
							end
						end
					end
				end
			end
		end
	end

	if table.getn(moveQueue) == 0 then
		-- 没有需要合并的堆叠 —— 清除占位符并刷新视图
		BagFrame:ClearRecentlyEmptiedSlots()
		-- 清除物品检测缓存以强制重新扫描提示
		if addon.Modules.ItemDetection and addon.Modules.ItemDetection.ClearCache then
			addon.Modules.ItemDetection:ClearCache()
		end
		BagFrame:Update()
		addon:Print(GudaBag.L["View refreshed (no stacks to merge)"])
		return
	end

	-- 设置排序标志并更新按钮外观
	addon.Modules.SortEngine.sortingInProgress = true
	addon.Modules.SortEngine:UpdateSortButtonState(true)

	-- 带延迟处理队列
	local queueIndex = 1
	local retryCount = 0
	local totalMoves = table.getn(moveQueue)
	
	local function ProcessNextMove()
		if queueIndex > table.getn(moveQueue) then
			addon.Modules.SortEngine.sortingInProgress = false
			addon.Modules.SortEngine:UpdateSortButtonState(false)
			-- 清除占位符和物品检测缓存
			BagFrame:ClearRecentlyEmptiedSlots()
			if addon.Modules.ItemDetection and addon.Modules.ItemDetection.ClearCache then
				addon.Modules.ItemDetection:ClearCache()
			end
			-- 刷新视图
			BagFrame:Update()
			addon:Print(format(GudaBag.L["Restacked %d stack(s)"], totalMoves))
			return
		end
		
		local move = moveQueue[queueIndex]
		local source = move.source
		local target = move.target
		
		-- 检查物品是否被锁定
		local _, _, sourceLocked = GetContainerItemInfo(source.bagID, source.slot)
		local _, _, targetLocked = GetContainerItemInfo(target.bagID, target.slot)
		
		if sourceLocked or targetLocked then
			retryCount = retryCount + 1
			if retryCount < 10 then
				-- 延迟后重试
				GudaBag.ScheduleTimer(0.3, ProcessNextMove)
				return
			else
				-- 放弃此移动
				retryCount = 0
				queueIndex = queueIndex + 1
				GudaBag.ScheduleTimer(0.1, ProcessNextMove)
				return
			end
		end
		
		-- 执行移动
		ClearCursor()
		PickupContainerItem(source.bagID, source.slot)
		PickupContainerItem(target.bagID, target.slot)
		ClearCursor()
		
		-- 移动到下一个
		retryCount = 0
		queueIndex = queueIndex + 1
		GudaBag.ScheduleTimer(0.15, ProcessNextMove)
	end
	
	ProcessNextMove()
end

-- 注意：GudaBag.ScheduleTimer 在 Core/Utils.lua 中定义（更早加载），
-- 以确保它对所有需要计时器的模块都可用

-- 钩住背包容器按钮以打开 Guda 背包视图
local function HookBagContainers()
-- 钩住主背包容器按钮（背包 1-4）
	for i = 1, 4 do
		local buttonName = "CharacterBag"..i.."Slot"
		local button = getglobal(buttonName)

		if button then
			local bagID = i
			local originalOnClick = button:GetScript("OnClick")
			button:SetScript("OnClick", function()
				local mouseButton = arg1 or "LeftButton" -- 香草使用全局 arg1
				if mouseButton == "LeftButton" then
					-- 如果光标有物品，尝试替换背包而非切换
					if CursorHasItem and CursorHasItem() then
						local invSlot = ContainerIDToInventoryID(bagID)
						Guda_TryEquipBagOnSlot(bagID, invSlot, nil)
					else
						BagFrame:Toggle()
					end
				else
				-- 允许右键和其他按钮正常工作
					if originalOnClick then
						originalOnClick()
					end
				end
			end)

			-- 钩住 OnReceiveDrag 以实现拖放替换背包
			button:SetScript("OnReceiveDrag", function()
				if CursorHasItem and CursorHasItem() then
					local invSlot = ContainerIDToInventoryID(bagID)
					Guda_TryEquipBagOnSlot(bagID, invSlot, nil)
				end
			end)
		end
	end

	-- 也钩住背包按钮
	local backpackButton = getglobal("MainMenuBarBackpackButton")
	if backpackButton then
		local originalOnClick = backpackButton:GetScript("OnClick")
		backpackButton:SetScript("OnClick", function()
			local mouseButton = arg1 or "LeftButton" -- 香草使用全局 arg1
			if mouseButton == "LeftButton" then
			-- 打开 Guda 背包视图而非默认背包
				BagFrame:Toggle()
			else
			-- 允许右键和其他按钮正常工作
				if originalOnClick then
					originalOnClick()
				end
			end
		end)
	end

	-- 钩住钥匙链按钮（如果存在）
	local keyringButton = getglobal("KeyRingButton")
	if keyringButton then
		local originalOnClick = keyringButton:GetScript("OnClick")
		keyringButton:SetScript("OnClick", function()
			local mouseButton = arg1 or "LeftButton" -- 香草使用全局 arg1
			if mouseButton == "LeftButton" then
			-- 在 Guda 背包视图中切换钥匙链
				GudaBag.BagFrame_ToggleKeyring()
				BagFrame:Toggle() -- 同时打开背包框架
			else
			-- 允许右键和其他按钮正常工作
				if originalOnClick then
					originalOnClick()
				end
			end
		end)
	end
end

-- 替代方法：完全替换背包打开函数
local function ReplaceBagOpenFunctions()
-- 覆盖 OpenBag（如果存在）
	if OpenBag then
		local originalOpenBag = OpenBag
		function OpenBag(bagId)
			if bagId and bagId >= 0 and bagId <= 4 then
			-- 对于普通背包，打开 Guda 背包视图
				BagFrame:Toggle()
			else
			-- 对于其他容器，使用原函数
				if originalOpenBag then
					originalOpenBag(bagId)
				end
			end
		end
	end

	-- 覆盖 ToggleBag（如果存在）
	if ToggleBag then
		local originalToggleBag = ToggleBag
		function ToggleBag(bagId)
			if bagId and bagId >= 0 and bagId <= 4 then
			-- 对于普通背包，切换 Guda 背包视图
				BagFrame:Toggle()
			else
			-- 对于其他容器，使用原函数
				if originalToggleBag then
					originalToggleBag(bagId)
				end
			end
		end
	end
end

-- 钩住默认的背包打开方式
local function HookDefaultBags()
	-- 覆盖 ToggleBackpack（如果存在）
	if ToggleBackpack then
		local originalToggleBackpack = ToggleBackpack
		function ToggleBackpack()
			BagFrame:Toggle()

			-- 如果启用了 pfUI，强制禁用其背包
			if pfUI and pfUI.bag and pfUI.bag.right and pfUI.bag.right.Hide then
				pfUI.bag.right:Hide()
			end
		end
	end

	-- 覆盖 OpenBackpack（如果存在）。
	-- 第三方"虚拟"入口（如小地图背包按钮）有时会调用
	-- OpenBackpack 并期望切换行为；将其路由到 Guda 的切换函数，
	-- 这样它们既能打开也能关闭背包视图。
	if OpenBackpack then
		local originalOpenBackpack = OpenBackpack
		function OpenBackpack()
			BagFrame:Toggle()

			if pfUI and pfUI.bag and pfUI.bag.right and pfUI.bag.right.Hide then
				pfUI.bag.right:Hide()
			end
		end
	end

	-- 覆盖 OpenAllBags（如果存在）。
	-- 注意：通过 BagFrame:Toggle() 路由（而非 Show），因为某些插件
	--（如 diminfo）误将 OpenAllBags 用作切换按钮。如果不这样处理，
	-- 通过这些入口打开的背包将永远无法关闭。
	if OpenAllBags then
		local originalOpenAllBags = OpenAllBags
		function OpenAllBags()
			BagFrame:Toggle()

			-- 如果启用了 pfUI，强制禁用其背包
			if pfUI and pfUI.bag and pfUI.bag.right and pfUI.bag.right.Hide then
				pfUI.bag.right:Hide()
			end
		end
	end

	-- 覆盖 CloseAllBags（如果存在）
	if CloseAllBags then
		local originalCloseAllBags = CloseAllBags
		function CloseAllBags()
			-- 与商贩交互时不自动关闭背包
			if isMerchantOpen then
				return
			end
			Guda_BagFrame:Hide()
		end
	end

	-- 钩住各个背包打开函数（用于背包槽位按钮）
	ReplaceBagOpenFunctions()

	-- 直接钩住背包槽位按钮的点击
	HookBagContainers()
end

-- 更新锁定状态（控制框架是否可拖拽）
function BagFrame:UpdateLockState()
-- 安全检查：确保 addon 和模块存在
	if not addon or not addon.Modules then return end

	local frame = getglobal("Guda_BagFrame")
	if not frame then return end

	-- 检查 DB 模块是否可用
	if not addon.Modules.DB or not addon.Modules.DB.GetSetting then return end

	local success, isLocked = pcall(function()
		return addon.Modules.DB:GetSetting("lockBags")
	end)

	if not success then return end

	if isLocked == nil then
		isLocked = false
	end

	-- 获取可拖拽区域
	local toolbar = getglobal("Guda_BagFrame_Toolbar")
	local moneyFrame = getglobal("Guda_BagFrame_MoneyFrame")
	local itemContainer = getglobal("Guda_BagFrame_ItemContainer")

	if isLocked then
	-- 禁用主框架上的拖拽
		if frame.SetScript then
			frame:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end
			end)
			frame:SetScript("OnMouseUp", nil)
		end

		-- 禁用工具栏上的拖拽
		if toolbar and toolbar.SetScript then
			toolbar:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end
			end)
			toolbar:SetScript("OnMouseUp", nil)
		end

		-- 禁用金钱框架上的拖拽（保留子按钮的提示处理函数）
		if moneyFrame and moneyFrame.SetScript then
			moneyFrame:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end
			end)
			moneyFrame:SetScript("OnMouseUp", nil)
		end

		-- 禁用物品容器上的拖拽
		if itemContainer and itemContainer.SetScript then
			itemContainer:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end
			end)
			itemContainer:SetScript("OnMouseUp", nil)
		end
	else
	-- 启用主框架上的拖拽
		if frame and frame.SetScript then
			frame:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end

				if arg1 == "LeftButton" then
					BeginFrameMove()
				end
			end)
			frame:SetScript("OnMouseUp", function()
				EndFrameMove()
			end)
		end

		-- 启用工具栏上的拖拽（标题区域）
		if toolbar and toolbar.SetScript then
			toolbar:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end

				if arg1 == "LeftButton" then
					BeginFrameMove()
				end
			end)
			toolbar:SetScript("OnMouseUp", function()
				EndFrameMove()
			end)
		end

		-- 启用金钱框架上的拖拽（保留子按钮的提示处理函数）
		if moneyFrame and moneyFrame.SetScript then
			moneyFrame:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end

				if arg1 == "LeftButton" then
					BeginFrameMove()
				end
			end)
			moneyFrame:SetScript("OnMouseUp", function()
				EndFrameMove()
			end)
		end

		-- 启用物品容器上的拖拽
		if itemContainer and itemContainer.SetScript then
			itemContainer:SetScript("OnMouseDown", function()
				local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
				if searchBox then
					searchBox:ClearFocus()
				end

				if arg1 == "LeftButton" then
					BeginFrameMove()
				end
			end)
			itemContainer:SetScript("OnMouseUp", function()
				EndFrameMove()
			end)
		end
	end
end

-- 根据设置更新边框可见性
function BagFrame:UpdateBorderVisibility()
	if not addon or not addon.Modules or not addon.Modules.DB then return end

	local frame = getglobal("Guda_BagFrame")
	if not frame then return end

	-- 若可用则使用 Theme 模块
	if addon.Modules.Theme then
		addon.Modules.Theme:ApplyToFrame(frame)
		return
	end

	local hideBorders = addon.Modules.DB:GetSetting("hideBorders")
	if hideBorders == nil then
		hideBorders = false
	end

	-- 使用带常量的辅助函数
	if hideBorders then
		addon:ApplyBackdrop(frame, "MINIMALIST_BORDER", "DEFAULT")
	else
		addon:ApplyBackdrop(frame, "DEFAULT_FRAME", "DEFAULT")
	end
end

-- 根据设置更新搜索栏可见性
-- 读取三态 searchBarMode 设置。
-- 返回 "shown"、"hidden" 或 "toggle" 之一。若新设置尚未设置，
-- 则回退到旧版布尔型 showSearchBar。
local function GetSearchBarMode()
	if not addon or not addon.Modules or not addon.Modules.DB then return "shown" end
	local mode = addon.Modules.DB:GetSetting("searchBarMode")
	if mode == "shown" or mode == "hidden" or mode == "toggle" then
		return mode
	end
	local legacy = addon.Modules.DB:GetSetting("showSearchBar")
	if legacy == false then return "hidden" end
	return "shown"
end

function BagFrame:UpdateSearchBarVisibility()
	if not addon or not addon.Modules or not addon.Modules.DB then return end

	local searchBar     = getglobal("Guda_BagFrame_SearchBar")
	local qualityBar    = getglobal("Guda_BagFrame_QualityBar")
	local itemContainer = getglobal("Guda_BagFrame_ItemContainer")
	local toggleBtn     = getglobal("Guda_BagFrame_SearchToggleButton")
	if not searchBar or not itemContainer then return end

	-- 品质栏隐藏时，搜索栏应直接锚定到标题栏下方（跳过品质栏那一行）
	local qualityBarHidden = self.qualityBarHidden and true or false

	local mode = GetSearchBarMode()
	local effectiveShown
	if mode == "shown" then
		effectiveShown = true
	else  -- "hidden" 或 "toggle"：均可通过图标按钮展开
		effectiveShown = self.searchBarExpanded and true or false
	end

	if effectiveShown then
		searchBar:Show()
		searchBar:ClearAllPoints()
		if qualityBarHidden then
			-- 品质栏隐藏：搜索栏占据原品质栏位置（标题栏下方 -40）
			searchBar:SetPoint("TOP", "Guda_BagFrame", "TOP", 0, -40)
		else
			searchBar:SetPoint("TOP", qualityBar, "BOTTOM", 0, -5)
		end
		itemContainer:ClearAllPoints()
		itemContainer:SetPoint("TOP", searchBar, "BOTTOM", 0, -5)
	else
		searchBar:Hide()
		itemContainer:ClearAllPoints()
		-- 搜索栏隐藏时，物品容器锚定到品质栏或标题栏下方
		if qualityBar and not qualityBarHidden then
			itemContainer:SetPoint("TOP", qualityBar, "BOTTOM", 0, -5)
		else
			itemContainer:SetPoint("TOP", "Guda_BagFrame", "TOP", 0, -40)
		end
	end

	if toggleBtn then
		-- "shown" 常显搜索栏无需图标；"hidden"/"toggle" 均显示图标以便随时展开搜索
		if mode == "shown" then toggleBtn:Hide() else toggleBtn:Show() end
	end
end

-- 切换搜索栏的展开状态（"shown" 模式常显，无需切换；"hidden"/"toggle" 可切换）。
function BagFrame:ToggleSearchBar()
	local mode = GetSearchBarMode()
	if mode == "shown" then return end  -- shown 模式常显

	self.searchBarExpanded = not (self.searchBarExpanded and true or false)
	self:UpdateSearchBarVisibility()

	local searchBox = getglobal("Guda_BagFrame_SearchBar_SearchBox")
	if self.searchBarExpanded then
		if searchBox then searchBox:SetFocus() end
	else
		if searchBox then
			searchBox:SetText("")
			searchBox:ClearFocus()
			if GudaBag.BagFrame_OnSearchChanged then
				GudaBag.BagFrame_OnSearchChanged(searchBox)
			end
		end
	end

	if BagFrame.Update then BagFrame:Update() end
end

-- 根据设置更新底部栏可见性
function BagFrame:UpdateFooterVisibility()
	local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
	local toolbar = getglobal("Guda_BagFrame_Toolbar")
	local moneyFrame = getglobal("Guda_BagFrame_MoneyFrame")
	local hearthstoneFrame = getglobal("Guda_BagFrame_HearthstoneFrame")

	if hideFooter then
		if toolbar then toolbar:Hide() end
		if moneyFrame then moneyFrame:Hide() end
		if hearthstoneFrame then hearthstoneFrame:Hide() end
	else
		if toolbar then toolbar:Show() end
		if moneyFrame then moneyFrame:Show() end
		if hearthstoneFrame then hearthstoneFrame:Show() end

		-- 触发布局更新以确保它们正确定位
		self:UpdateBaglineLayout()
		self:UpdateMoney()
		self:UpdateHearthstone()
		self:RefreshUtilityButtons()
	end
end

-- 背包槽位按钮处理函数

-- 应用底部按钮背景样式
function GudaBag.BagSlot_ApplyBackdrop(button)
	local Theme = addon.Modules.Theme
	local qStyle = Theme:GetQualityBorderStyle()
	if qStyle == "square" then
		button:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
			insets = { left = -1, right = -1, top = -1, bottom = -1 },
		})
	else
		button:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
	end
	local fbBg = Theme:GetValue("footerButtonBg") or { 0.12, 0.12, 0.12, 1 }
	local fbBorder = Theme:GetValue("footerButtonBorder") or { 0.30, 0.30, 0.30, 1 }
	button:SetBackdropColor(fbBg[1], fbBg[2], fbBg[3], fbBg[4])
	button:SetBackdropBorderColor(fbBorder[1], fbBorder[2], fbBorder[3], fbBorder[4])
end

-- 尝试将光标上的背包装备到背包槽位，若已占用则自动替换
Guda_TryEquipBagOnSlot = function(bagID, invSlot, button)
	if not CursorHasItem or not CursorHasItem() then return end

	-- 检查当前背包是否有物品
	local numSlots = GetContainerNumSlots(bagID)
	local hasItems = false
	if numSlots and numSlots > 0 then
		for slot = 1, numSlots do
			local texture = GetContainerItemInfo(bagID, slot)
			if texture then hasItems = true; break end
		end
	end

	if hasItems and addon.Modules.BagReplacer then
		addon.Modules.BagReplacer:Execute(bagID, invSlot)
		return -- BagReplacer 自行处理 UI 更新
	end

	-- 空背包或没有背包 —— 标准装备，然后延迟刷新
	if EquipCursorItem then
		EquipCursorItem(invSlot)
	elseif PutItemInBag then
		PutItemInBag(invSlot)
	end

	if button then GudaBag.BagSlot_Update(button, bagID) end

	-- 延迟 UI 刷新，让服务器有时间处理背包装备
	-- （GetContainerNumSlots 不会立即反映新背包的大小）
	GudaBag.ScheduleTimer(0.3, function()
		if addon.Modules.BagScanner and addon.Modules.BagScanner.InvalidateCache then
			addon.Modules.BagScanner:InvalidateCache()
		end
		if BagFrame and BagFrame.Update then BagFrame:Update() end
	end)
end

-- 背包槽位按钮的加载时处理函数
function GudaBag.BagSlot_OnLoad(button, bagID)
-- 隐藏 ItemButtonTemplate 的边框
	local buttonName = button:GetName()

	-- 隐藏普通纹理边框
	local normalTexture = getglobal(buttonName .. "NormalTexture")
	if normalTexture then
		normalTexture:SetTexture(nil)
		normalTexture:Hide()
	end

	-- 隐藏图标边框
	local iconBorder = getglobal(buttonName .. "IconBorder")
	if iconBorder then
		iconBorder:Hide()
	end

	-- 应用底部按钮背景样式
	GudaBag.BagSlot_ApplyBackdrop(button)

	-- 用正确的 ID 设置按钮
	if bagID == 0 then
	-- 背包（背包 0）
		button.bagID = 0
		button.hasItem = 1
		local hideBagline = addon.Modules.DB:GetSetting("hideBagline")
		if hideBagline then
			SetItemButtonTexture(button, "Interface\\AddOns\\Guda\\Assets\\bags")
		else
			SetItemButtonTexture(button, "Interface\\Buttons\\Button-Backpack-Up")
		end
	else
	-- 背包 1-4
		local invSlot = ContainerIDToInventoryID(bagID)
		button:SetID(invSlot)
		button.bagID = bagID

		-- 注册拖拽 —— 这对 Classic 至关重要
		button:RegisterForDrag("LeftButton")

		-- 注册更新事件
		button:RegisterEvent("BAG_UPDATE")
		button:RegisterEvent("ITEM_LOCK_CHANGED")
		button:RegisterEvent("CURSOR_UPDATE")
		button:RegisterEvent("UNIT_INVENTORY_CHANGED")

		-- 接受拖放（当背包被放到此槽位时装备它）
		button:SetScript("OnReceiveDrag", function()
			if this and this.bagID and this.bagID ~= 0 and CursorHasItem and CursorHasItem() then
				local inv = ContainerIDToInventoryID(this.bagID)
				Guda_TryEquipBagOnSlot(this.bagID, inv, this)
			end
		end)
	end

	-- 确保我们像 BankFrame 一样处理右键切换
	if button.RegisterForClicks then
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	end

	-- 初始更新
	GudaBag.BagSlot_Update(button, bagID)
end

function GudaBag.BagSlot_OnDragStart(frame, bagID)
	if bagID == 0 then return end

	-- 检查是否应开始拖拽（仅当有物品时）
	local invSlot = ContainerIDToInventoryID(bagID)
	local texture = GetInventoryItemTexture("player", invSlot)

	if texture then
		frame:SetAlpha(0.6)
		-- 为 Classic 立即拾取
		PickupInventoryItem(invSlot)
		-- 立即在 UI 中反映变化（光标拾取后槽位现在为空）
		GudaBag.BagSlot_Update(frame, bagID)
		if BagFrame and BagFrame.Update then BagFrame:Update() end
	end
-- 如果没有贴图（空槽位），不做任何事 —— 拖拽不会开始
end

function GudaBag.BagSlot_OnDragStop(frame, bagID)
	frame:SetAlpha(1.0)
end

-- 更新背包槽位按钮贴图
function GudaBag.BagSlot_Update(button, bagID)
	local isHidden = hiddenBags[bagID]

	if bagID == 0 then
	-- 背包贴图取决于背包栏设置
		local hideBagline = addon.Modules.DB:GetSetting("hideBagline")
		if hideBagline then
			SetItemButtonTexture(button, "Interface\\AddOns\\Guda\\Assets\\bags")
		else
			SetItemButtonTexture(button, "Interface\\Buttons\\Button-Backpack-Up")
		end
		-- 隐藏时变暗
		if isHidden then
			SetItemButtonTextureVertexColor(button, 0.4, 0.4, 0.4)
		else
			SetItemButtonTextureVertexColor(button, 1.0, 1.0, 1.0)
		end
		return
	end

	-- 获取此背包的库存槽位 ID
	local invSlot = ContainerIDToInventoryID(bagID)
	local texture = GetInventoryItemTexture("player", invSlot)

	if texture then
	-- 背包已装备
		SetItemButtonTexture(button, texture)
		-- 隐藏时变暗
		if isHidden then
			SetItemButtonTextureVertexColor(button, 0.4, 0.4, 0.4)
		else
			SetItemButtonTextureVertexColor(button, 1.0, 1.0, 1.0)
		end
	else
	-- 此槽位没有背包
		SetItemButtonTexture(button, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
		SetItemButtonTextureVertexColor(button, 0.5, 0.5, 0.5)
	end
end

-- 事件处理函数
function GudaBag.BagSlot_OnEvent(button, event, arg1)
	local bagID = button.bagID
	if not bagID then
		return
	end

	if event == "BAG_UPDATE" then
		if arg1 == bagID then
			GudaBag.BagSlot_Update(button, bagID)
		end
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if arg1 == "player" then
			GudaBag.BagSlot_Update(button, bagID)
		end
	elseif event == "ITEM_LOCK_CHANGED" or event == "CURSOR_UPDATE" then
		GudaBag.BagSlot_Update(button, bagID)
	end
end

-- 点击处理函数
function GudaBag.BagSlot_OnClick(button, bagID)
	local which = arg1 -- 香草使用全局 arg1 表示鼠标按钮名称

	-- 右键：切换可见性
	if which == "RightButton" then
		hiddenBags[bagID] = not hiddenBags[bagID]

		-- 更新背包槽位外观（变暗/恢复）
		GudaBag.BagSlot_Update(button, bagID)

		-- 刷新背包显示
		BagFrame:Update()

		return
	end

	-- 左键点击 bag0：若背包栏已隐藏则切换弹出层
	if which == "LeftButton" and bagID == 0 then
		local hideBagline = addon.Modules.DB:GetSetting("hideBagline")
		if hideBagline then
			BagFrame:ToggleBagFlyout()
			return
		end
	end

	-- 左键：将光标上的背包装备到此槽位（仅背包 1-4）
	if which == "LeftButton" then
		if bagID ~= 0 and CursorHasItem and CursorHasItem() then
			local invSlot = ContainerIDToInventoryID(bagID)
			Guda_TryEquipBagOnSlot(bagID, invSlot, button)
		end
		return
	end
end

-- 提示框的进入处理函数
function GudaBag.BagSlot_OnEnter(button, bagID)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")

	if bagID == 0 then
	-- 背包提示
		GameTooltip:SetText(GudaBag.L["Backpack"], 1.0, 1.0, 1.0)
		local numSlots = GetContainerNumSlots(0)
		GameTooltip:AddLine(string.format(GudaBag.L["%d Slots"], numSlots), 0.8, 0.8, 0.8)
		if hiddenBags[bagID] then
			GameTooltip:AddLine(GudaBag.L["(Hidden - Right-Click to show)"], 0.8, 0.5, 0.5)
		else
			GameTooltip:AddLine(GudaBag.L["(Right-Click to hide)"], 0.5, 0.8, 0.5)
		end
		GudaBag.BagFrame_HighlightBagSlots(0)
	elseif bagID == -2 then
		-- 钥匙链提示
		GameTooltip:SetText(GudaBag.L["Keyring"], 1.0, 1.0, 1.0)
		local numSlots = GetContainerNumSlots(-2) or 0
		GameTooltip:AddLine(string.format(GudaBag.L["%d Slots"], numSlots), 0.8, 0.8, 0.8)
		if hiddenBags[bagID] then
			GameTooltip:AddLine(GudaBag.L["(Hidden - Right-Click to show)"], 0.8, 0.5, 0.5)
		else
			GameTooltip:AddLine(GudaBag.L["(Right-Click to hide)"], 0.5, 0.8, 0.5)
		end
		GudaBag.BagFrame_HighlightBagSlots(-2)
	else
	-- 背包槽位提示
		local invSlot = ContainerIDToInventoryID(bagID)
		local hasItem = GetInventoryItemTexture("player", invSlot)

		if hasItem then
		-- 显示背包物品提示
			GameTooltip:SetInventoryItem("player", invSlot)
			if hiddenBags[bagID] then
				GameTooltip:AddLine(GudaBag.L["(Hidden - Right-Click to show)"], 0.8, 0.5, 0.5)
			else
				GameTooltip:AddLine(GudaBag.L["(Right-Click to hide)"], 0.5, 0.8, 0.5)
			end
			GudaBag.BagFrame_HighlightBagSlots(bagID)
		else
		-- 空槽位
			GameTooltip:SetText(string.format(GudaBag.L["Bag %d"], bagID), 1.0, 1.0, 1.0)
			GameTooltip:AddLine(GudaBag.L["Empty"], 0.5, 0.5, 0.5)
			if hiddenBags[bagID] then
				GameTooltip:AddLine(GudaBag.L["(Hidden - Right-Click to show)"], 0.8, 0.5, 0.5)
			else
				GameTooltip:AddLine(GudaBag.L["(Right-Click to hide)"], 0.5, 0.8, 0.5)
			end
			GudaBag.BagFrame_HighlightBagSlots(bagID)
		end
	end

	GameTooltip:Show()
end

-- 提示框的离开处理函数
function GudaBag.BagSlot_OnLeave(button, bagID)
end

-- 通过调暗其他槽位来高亮属于特定背包的所有物品槽位
function GudaBag.BagFrame_HighlightBagSlots(bagID)
    -- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
    local highlightCount, dimCount = 0, 0

    for _, bagParent in pairs(bagParents) do
        if bagParent and bagParent.itemButtons then
            for button in pairs(bagParent.itemButtons) do
                if button and button:IsShown() and button.hasItem ~= nil and not button.isBagSlot then
                    if button.bagID == bagID then
                        button:SetAlpha(1.0)
                        highlightCount = highlightCount + 1
                    else
                        button:SetAlpha(0.25)
                        dimCount = dimCount + 1
                    end
                end
            end
        end
    end
end

-- 将所有槽位恢复为完整不透明度以清除全部高亮
function GudaBag.BagFrame_ClearHighlightedSlots()
    -- 将 alpha 恢复为搜索过滤器规定的值（pfUI 风格）。若无搜索则为完整不透明度。
    -- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
    local searchActive = BagFrame and BagFrame.IsSearchActive and BagFrame:IsSearchActive()

    for _, bagParent in pairs(bagParents) do
        if bagParent and bagParent.itemButtons then
            for button in pairs(bagParent.itemButtons) do
                if button and button:IsShown() and button.hasItem ~= nil and not button.isBagSlot then
                    if searchActive and BagFrame and BagFrame.PassesSearchFilter then
                        local matches = BagFrame:PassesSearchFilter(button.itemData)
                        button:SetAlpha(matches and 1.0 or 0.25)
                    else
                        button:SetAlpha(1.0)
                    end
                end
            end
        end
    end
end

-- 高亮工具栏中的特定背包按钮
function GudaBag.BagFrame_HighlightBagButton(bagID)
	if not bagID then return end

	local buttonName
	if bagID == -2 then
	-- 钥匙链按钮
		buttonName = "Guda_BagFrame_Toolbar_KeyringButton"
	elseif bagID >= 0 and bagID <= 4 then
	-- 背包按钮 0-4（0 是背包）
		buttonName = "Guda_BagFrame_Toolbar_BagSlot" .. bagID
	else
		return
	end

	local button = getglobal(buttonName)
	if button then
	-- 设置按钮的按下贴图以高亮它
		button:LockHighlight()
	end
end

-- 清除背包按钮高亮
function GudaBag.BagFrame_ClearBagButtonHighlight()
-- 清除所有背包按钮（0-4）的高亮
	for bagID = 0, 4 do
		local buttonName = "Guda_BagFrame_Toolbar_BagSlot" .. bagID
		local button = getglobal(buttonName)
		if button then
			button:UnlockHighlight()
		end
	end

	-- 清除钥匙链按钮高亮
	local keyringButton = getglobal("Guda_BagFrame_Toolbar_KeyringButton")
	if keyringButton then
		keyringButton:UnlockHighlight()
	end

	-- 清除灵魂袋按钮高亮
	local soulBagButton = getglobal("Guda_BagFrame_Toolbar_SoulBagButton")
	if soulBagButton then
		soulBagButton:UnlockHighlight()
	end
end

-- 初始化
function BagFrame:Initialize()
-- 钩住默认背包函数（稍作延迟以确保 UI 已加载）
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function()
		HookDefaultBags()

		-- 绑定排序按钮：用 Lua SetScript 可靠获取鼠标按键（左键正序、右键倒序），
		-- 并覆盖 XML 的 OnClick / OnEnter（右键倒序提示）
		SetupSortButton()

		-- 打开角色框架时重新钩住（为安全起见）
		local charFrame = getglobal("CharacterFrame")
		if charFrame then
			local originalShow = charFrame:GetScript("OnShow")
			charFrame:SetScript("OnShow", function()
				HookBagContainers()
				if originalShow then
					originalShow()
				end
			end)
		end
	end)

	-- 当法术书变化（例如学习新等级）或进入世界时，
	-- 刷新分解 / 开锁表头快捷按钮，并重置炉石法术搜索（学习新法术后更新）
	if addon.Modules and addon.Modules.Events then
		addon.Modules.Events:Register("SPELLS_CHANGED", function()
			_spellSearchDone = false  -- 法术书变化，重新搜索炉石/星界传送
			BagFrame:RefreshUtilityButtons()
			BagFrame:UpdateHearthstone()
		end, "BagFrame")
		addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
			BagFrame:RefreshUtilityButtons()
		end, "BagFrame")
	end

 --=====================================================
 -- 高效的更新限流系统
 -- 使用单个可复用框架和真正的防抖
 --（新事件到来时重置计时器）
 --=====================================================
 local updateThrottle = {
     frame = nil,
     pending = false,
     delay = 0.1,        -- 默认延迟（100ms）
     elapsed = 0,
     minDelay = 0.05,    -- 最小延迟（50ms），保证响应性
     maxDelay = 0.3,     -- 重操作期间的最大延迟（300ms）
 }

 -- 初始化限流框架（创建一次，重复使用）
 local function GetThrottleFrame()
     if not updateThrottle.frame then
         updateThrottle.frame = CreateFrame("Frame", "Guda_BagUpdateThrottle", UIParent)
         updateThrottle.frame:Hide()
         updateThrottle.frame:SetScript("OnUpdate", function()
             updateThrottle.elapsed = updateThrottle.elapsed + arg1
             if updateThrottle.elapsed >= updateThrottle.delay then
                 updateThrottle.frame:Hide()
                 updateThrottle.pending = false
                 updateThrottle.elapsed = 0
                 -- 仅当框架显示且正在查看当前角色时更新
                 if not currentViewChar and Guda_BagFrame and Guda_BagFrame:IsShown() then
                     BagFrame:Update()
                 end
             end
         end)
     end
     return updateThrottle.frame
 end

 -- 调度防抖的 BagFrame 更新
 -- 如果已有待处理，则重置计时器（真正的防抖行为）
 local function ScheduleBagFrameUpdate(delay)
     delay = delay or updateThrottle.minDelay

     -- 将延迟限制在合理范围内
     if delay < updateThrottle.minDelay then
         delay = updateThrottle.minDelay
     elseif delay > updateThrottle.maxDelay then
         delay = updateThrottle.maxDelay
     end

     -- 排序进行中时使用更长的延迟
     if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then
         delay = updateThrottle.maxDelay
     end

     updateThrottle.delay = delay
     updateThrottle.elapsed = 0  -- 重置计时器（真正的防抖）

     if not updateThrottle.pending then
         updateThrottle.pending = true
         GetThrottleFrame():Show()
     end
 end

 -- 取消任何待处理的更新（框架隐藏时有用）
 local function CancelPendingUpdate()
     if updateThrottle.frame then
         updateThrottle.frame:Hide()
     end
     updateThrottle.pending = false
     updateThrottle.elapsed = 0
 end

 -- 背包变化时更新（防抖，防止快速背包更新导致卡顿）
 -- 直接注册以访问 arg1（变化的 bagID），用于增量缓存更新
 local bagUpdateFrame = CreateFrame("Frame")
 bagUpdateFrame:RegisterEvent("BAG_UPDATE")
 bagUpdateFrame:SetScript("OnEvent", function()
     if currentViewChar then return end
     if not Guda_BagFrame:IsShown() then return end

     -- 只处理玩家背包（0-4）—— 使用 tonumber 进行安全比较
     local bagID = tonumber(arg1)
     if not bagID or bagID < 0 or bagID > 4 then
         return  -- 跳过银行背包（5-10）和无效背包
     end

     local viewType = addon.Modules.DB:GetSetting("bagViewType") or "single"
     addon:DebugCategory("BAG_UPDATE (BagFrame): bagID=%d, viewType=%s", bagID, viewType)

     -- 检查排序是否在进行中 —— 使用带限流的完整重绘
     local isSorting = addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress

     if not isSorting then
         -- 为手动移动物品尝试增量更新
         -- 注意：不要清除 ItemDetection 缓存 —— 物品属性不会因移动而改变
         addon.Modules.BagScanner:InvalidateBag(arg1)

         -- 尝试只更新此背包中发生变化的槽位
         local result = BagFrame:UpdateChangedSlots(arg1)
         addon:DebugCategory("BAG_UPDATE: UpdateChangedSlots result=%s", tostring(result))
         if result >= 0 then
             -- 成功 —— 未完整重绘即更新了槽位
             -- 取消任何待处理的完整重绘以保留增量更新
             CancelPendingUpdate()
             addon:DebugCategory("BAG_UPDATE: Incremental update succeeded, skipping full redraw")
             return
         end
         -- 增量更新失败则回退到完整重绘
         addon:DebugCategory("BAG_UPDATE: Incremental update failed, doing full redraw")
     end

     -- 在分类视图中，检测刚变空的槽位以显示占位符
     if viewType == "category" and not isSorting then
         local numSlots = GetContainerNumSlots(bagID)
         if numSlots and numSlots > 0 then
             for slotID = 1, numSlots do
                 local currentLink = GetContainerItemLink(bagID, slotID)
                 local button = slotToButton[bagID] and slotToButton[bagID][slotID]
                 if button and button.hasItem and not currentLink and not button.isEmptyPlaceholder then
                     -- 此槽位原本有物品但现在为空 —— 标记为最近清空
                     local oldCategory = nil
                     if button.itemData and addon.Modules.CategoryManager then
                         oldCategory = addon.Modules.CategoryManager:CategorizeItem(button.itemData, bagID, slotID)
                     end
                     BagFrame:MarkSlotAsEmptied(bagID, slotID, oldCategory, button.itemData)
                 end
             end
         end
     end

     -- 排序进行中或增量更新失败 —— 使用限流的完整重绘
     addon.Modules.BagScanner:InvalidateBag(arg1)
     ScheduleBagFrameUpdate(0.1)
 end)

 -- 物品冷却变化时更新冷却覆盖层
 addon.Modules.Events:Register("BAG_UPDATE_COOLDOWN", function()
     if not currentViewChar then
         if BagFrame.RefreshCooldowns then
             BagFrame:RefreshCooldowns()
         end
     end
 end, "BagFrame")

	-- 金钱变化时更新
	addon.Modules.Events:OnMoneyChanged(function()
		BagFrame:UpdateMoney()
	end, "BagFrame")

	-- 物品锁定/解锁时更新（为交易、邮寄等做防抖）
	local lockUpdatePending = false
	addon.Modules.Events:Register("ITEM_LOCK_CHANGED", function()
		if currentViewChar then return end
		if not Guda_BagFrame:IsShown() then return end
		-- 在分类视图中，防抖锁定状态更新（拖动期间触发非常频繁）
		local viewType = addon.Modules.DB:GetSetting("bagViewType") or "single"
		if viewType == "category" then
			if not lockUpdatePending then
				lockUpdatePending = true
				GudaBag.ScheduleTimer(0.05, function()
					lockUpdatePending = false
					if Guda_BagFrame:IsShown() and not currentViewChar then
						BagFrame:UpdateLockStates()
					end
				end)
			end
			return
		end
		-- 单视图中锁定变化使用稍长的延迟（拖动期间触发非常频繁）
		ScheduleBagFrameUpdate(0.15)
	end, "BagFrame")

	-- 与邮件、银行、拍卖行、交易交互时自动打开背包框架
	local function AutoOpenBags()
		local autoOpen = addon.Modules.DB:GetSetting("autoOpenBags")
		if autoOpen == nil then autoOpen = true end
		if autoOpen then
			Guda_BagFrame:Show()
		end
	end

	addon.Modules.Events:Register("MAIL_SHOW", AutoOpenBags, "BagFrame")
	addon.Modules.Events:Register("BANKFRAME_OPENED", AutoOpenBags, "BagFrame")
	addon.Modules.Events:Register("AUCTION_HOUSE_SHOW", AutoOpenBags, "BagFrame")
	addon.Modules.Events:Register("TRADE_SHOW", AutoOpenBags, "BagFrame")

	-- 跟踪商贩交互，避免打开商贩时关闭背包
	addon.Modules.Events:Register("MERCHANT_SHOW", function()
		isMerchantOpen = true
		-- 访问商贩时自动打开背包（遵循设置）
		local autoOpen = addon.Modules.DB:GetSetting("autoOpenBags")
		if autoOpen == nil then autoOpen = true end
		if autoOpen then
			local frameRef = getglobal("Guda_BagFrame")
			if frameRef and not frameRef:IsShown() then
				frameRef:Show()
			end
		end

		-- 自动出售垃圾物品（分散到多帧执行以避免物品锁定）
		local autoVendor = addon.Modules.DB:GetSetting("autoVendorJunk")
		if autoVendor == nil then autoVendor = true end
		if autoVendor then
			local junkItems = {}
			local DB = addon.Modules.DB
			local Utils = addon.Modules.Utils
			for bag = 0, 4 do
				local numSlots = GetContainerNumSlots(bag)
				for slot = 1, numSlots do
					local link = GetContainerItemLink(bag, slot)
					if link and string.find(link, "|cff9d9d9d") then
						local skip = false
						if DB and Utils then
							local itemID = Utils:ExtractItemID(link)
							if itemID and DB:IsItemProtected(itemID) then
								skip = true
							end
						end
						if not skip then
							table.insert(junkItems, { bag = bag, slot = slot })
						end
					end
				end
			end
			if table.getn(junkItems) > 0 then
				local idx = 0
				local soldCount = 0
				local sellFrame = CreateFrame("Frame")
				sellFrame:SetScript("OnUpdate", function()
					if not isMerchantOpen then
						this:SetScript("OnUpdate", nil)
						if soldCount > 0 then
							addon:Print(format(GudaBag.L["Sold %d junk item(s)"], soldCount))
						end
						return
					end
					idx = idx + 1
					local item = junkItems[idx]
					if item then
						local link = GetContainerItemLink(item.bag, item.slot)
						if link and string.find(link, "|cff9d9d9d") then
							UseContainerItem(item.bag, item.slot)
							soldCount = soldCount + 1
						end
					else
						this:SetScript("OnUpdate", nil)
						if soldCount > 0 then
							addon:Print(format(GudaBag.L["Sold %d junk item(s)"], soldCount))
						end
					end
				end)
			end
		end
	end, "BagFrame")

	addon.Modules.Events:Register("MERCHANT_CLOSED", function()
		isMerchantOpen = false
		local autoClose = addon.Modules.DB:GetSetting("autoCloseBags")
		if autoClose == nil then autoClose = true end
		if autoClose then
			Guda_BagFrame:Hide()
		end
	end, "BagFrame")

	-- 关闭邮件、银行、拍卖行、交易时自动关闭背包框架
	local function AutoCloseBags()
		local autoClose = addon.Modules.DB:GetSetting("autoCloseBags")
		if autoClose == nil then autoClose = true end
		if autoClose then
			Guda_BagFrame:Hide()
		end
	end

	addon.Modules.Events:Register("MAIL_CLOSED", AutoCloseBags, "BagFrame")
	addon.Modules.Events:Register("BANKFRAME_CLOSED", AutoCloseBags, "BagFrame")
	addon.Modules.Events:Register("AUCTION_HOUSE_CLOSED", AutoCloseBags, "BagFrame")
	addon.Modules.Events:Register("TRADE_CLOSED", AutoCloseBags, "BagFrame")

	-- 点击背包框架时隐藏角色下拉菜单
	local bagFrame = getglobal("Guda_BagFrame")
	if bagFrame then
		local originalOnMouseDown = bagFrame:GetScript("OnMouseDown")
		bagFrame:SetScript("OnMouseDown", function()
			if originalOnMouseDown then
				originalOnMouseDown()
			end
		end)
	end

    addon:Debug("Bag frame initialized")
end

-- 为所有可见物品按钮刷新冷却覆盖层
function BagFrame:RefreshCooldowns()
    -- 使用 itemButtons 哈希表而非 GetChildren() 以避免表分配
    for _, bagParent in pairs(bagParents) do
        if bagParent and bagParent.itemButtons then
            for button in pairs(bagParent.itemButtons) do
                if button and button.hasItem and button:IsShown() and GudaBag.ItemButton_UpdateCooldown then
                    GudaBag.ItemButton_UpdateCooldown(button)
                end
            end
        end
    end
end