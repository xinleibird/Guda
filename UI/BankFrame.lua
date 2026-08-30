-- 银行框架
-- 银行查看界面

local addon = Guda

local BankFrame = {}
addon.Modules.BankFrame = BankFrame

local currentViewChar = nil
function BankFrame:GetCurrentViewChar()
    return currentViewChar
end
local searchText = ""
local isReadOnlyMode = false  -- 跟踪查看的是保存的银行（只读）还是实时银行（可交互）
local hiddenBankBags = {} -- 跟踪哪些银行背包被隐藏（bagID -> true/false）
local bankBagParents = {} -- 每个银行背包的父框架（与 BagFrame 相同的方法）
local bankSlotToButton = {} -- 快速 O(1) 查找：bankSlotToButton[bagID][slotID] = button
local bankIsFrameMoving = false  -- 在银行框架上 StartMoving 与 StopMovingOrSizing 之间为 true
-- 跟踪在分类视图中应显示为占位符的空槽位
-- 格式：recentlyEmptiedSlots[bagID][slotID] = { category = "CategoryName", timestamp = time }
local recentlyEmptiedSlots = {}
-- 用于清除银行搜索焦点的全局点击捕获器
local bankClickCatcher = nil

--=====================================================
-- 延迟可用性着色系统
-- 防止银行打开时物品数据未完全加载导致的误判
-- 使用防抖机制安全处理快速开/关银行的情况
--=====================================================
local bankUsabilityCheckFrame = nil
local BANK_USABILITY_CHECK_DELAY = 0.25 -- 重新检查可用性之前的延迟（秒）

-- 取消任何待处理的延迟可用性检查
local function CancelBankDeferredUsabilityCheck()
    if bankUsabilityCheckFrame then
        bankUsabilityCheckFrame:Hide()
        bankUsabilityCheckFrame.pending = false
    end
end

-- 更新所有可见银行物品按钮的可用性着色
local function UpdateAllBankUsabilityTints()
    if not Guda_BankFrame or not Guda_BankFrame:IsShown() then return end

    for _, bagParent in pairs(bankBagParents) do
        if bagParent and bagParent.itemButtons then
            for button in pairs(bagParent.itemButtons) do
                if button.hasItem and button:IsShown() and GudaBag.ItemButton_UpdateUsableTint then
                    GudaBag.ItemButton_UpdateUsableTint(button)
                end
            end
        end
    end
end

-- 使用防抖机制调度延迟可用性检查
local function ScheduleBankDeferredUsabilityCheck()
    -- 首次使用时创建框架
    if not bankUsabilityCheckFrame then
        bankUsabilityCheckFrame = CreateFrame("Frame")
        bankUsabilityCheckFrame:Hide()
        bankUsabilityCheckFrame.elapsed = 0
        bankUsabilityCheckFrame.pending = false
        bankUsabilityCheckFrame:SetScript("OnUpdate", function()
            this.elapsed = this.elapsed + arg1
            if this.elapsed >= BANK_USABILITY_CHECK_DELAY then
                this:Hide()
                this.pending = false
                -- 仅当银行仍然打开时才运行
                if Guda_BankFrame and Guda_BankFrame:IsShown() then
                    -- 清除检测缓存并重新检查所有物品
                    if addon.Modules.ItemDetection and addon.Modules.ItemDetection.ClearCache then
                        addon.Modules.ItemDetection:ClearCache()
                    end
                    UpdateAllBankUsabilityTints()
                end
            end
        end)
    end

    -- 重置计时器（防抖行为）
    bankUsabilityCheckFrame.elapsed = 0
    bankUsabilityCheckFrame.pending = true
    bankUsabilityCheckFrame:Show()
end

-- 清除最近清空的槽位（视图重置或框架隐藏时调用）
function BankFrame:ClearRecentlyEmptiedSlots()
    for k in pairs(recentlyEmptiedSlots) do
        recentlyEmptiedSlots[k] = nil
    end
end

-- 将槽位标记为最近清空（保留其分类和排序信息用于占位符显示）
function BankFrame:MarkSlotAsEmptied(bagID, slotID, category, itemData)
    if not recentlyEmptiedSlots[bagID] then
        recentlyEmptiedSlots[bagID] = {}
    end
    -- 保存原物品中与排序相关的属性以维持位置
    recentlyEmptiedSlots[bagID][slotID] = {
        category = category or "Miscellaneous",
        timestamp = GetTime(),
        -- 保留原物品的排序属性
        quality = itemData and itemData.quality or 0,
        name = itemData and itemData.name or "",
        iLevel = itemData and itemData.iLevel or 0,
    }
    addon:DebugCategory("Marked slot %d:%d as emptied (category: %s)", bagID, slotID, category or "Miscellaneous")
end

-- 检查槽位是否被标记为最近清空
function BankFrame:IsSlotRecentlyEmptied(bagID, slotID)
    return recentlyEmptiedSlots[bagID] and recentlyEmptiedSlots[bagID][slotID]
end

-- 获取最近清空槽位的分类
function BankFrame:GetEmptiedSlotCategory(bagID, slotID)
    local info = recentlyEmptiedSlots[bagID] and recentlyEmptiedSlots[bagID][slotID]
    return info and info.category or nil
end

-- 从"最近清空"中移除槽位（物品放回时）
function BankFrame:UnmarkSlotAsEmptied(bagID, slotID)
    if recentlyEmptiedSlots[bagID] then
        recentlyEmptiedSlots[bagID][slotID] = nil
    end
end

-- 加载时（OnLoad）
function GudaBag.BankFrame_OnLoad(self)
    self:SetClampedToScreen(true)

    -- 设置初始背景
    addon:ApplyBackdrop(self, "DEFAULT_FRAME")

    -- 注册拖放接收：银行框架与物品容器需 RegisterForDrag 才能收到
    -- OnReceiveDrag（把光标物品拖到空白处时放入第一个空位）。
    if self.RegisterForDrag then
        self:RegisterForDrag("LeftButton")
    end
    local itemContainer = getglobal("Guda_BankFrame_ItemContainer")
    if itemContainer and itemContainer.RegisterForDrag then
        itemContainer:RegisterForDrag("LeftButton")
    end

    -- 设置搜索框占位文本
    local searchBox = getglobal(self:GetName().."_SearchBar_SearchBox")
    if searchBox then
        searchBox:SetText(GudaBag.L["Search bank..."])
        searchBox:SetTextColor(0.5, 0.5, 0.5, 1)
    end

    -- 创建不可见的全屏框架，在搜索输入时捕获银行框架外部的点击
    if not bankClickCatcher then
        bankClickCatcher = CreateFrame("Frame", "Guda_BankClickCatcher", UIParent)
        bankClickCatcher:SetFrameStrata("BACKGROUND")
        bankClickCatcher:SetAllPoints(UIParent)
        bankClickCatcher:EnableMouse(true)
        bankClickCatcher:Hide()

        bankClickCatcher:SetScript("OnMouseDown", function()
            if GudaBag.BankFrame_ClearSearch then
                GudaBag.BankFrame_ClearSearch()
            end
        end)
    end

end

-- 显示时（OnShow）
function GudaBag.BankFrame_OnShow(self)
    if BankFrame.EnsureBagButtonsInitialized then
        BankFrame:EnsureBagButtonsInitialized()
    end
    -- 强制设置 MoneyFrame 的底部边距，以防任何运行时代码重新定位它
    local moneyFrame = getglobal("Guda_BankFrame_MoneyFrame")
    if moneyFrame and moneyFrame.ClearAllPoints and moneyFrame.SetPoint then
        moneyFrame:ClearAllPoints()
        moneyFrame:SetPoint("BOTTOMRIGHT", Guda_BankFrame, "BOTTOMRIGHT", -15, 10)
    end

    -- 恢复保存的窗口位置，使银行在用户上次放置的位置
    -- 重新打开，而不是回到默认的中心锚点。
    GudaBag.RestoreBankFramePosition(Guda_BankFrame)

	-- 应用边框可见性设置
	if BankFrame.UpdateBorderVisibility then
		BankFrame:UpdateBorderVisibility()
	end

   	-- 应用搜索栏可见性设置。在 toggle 模式下总是以折叠状态开始，
   	-- 这样打开银行时不会残留过期的过滤状态。
   	BankFrame.searchBarExpanded = false
   	if BankFrame.UpdateSearchBarVisibility then
   		BankFrame:UpdateSearchBarVisibility()
   	end

   	-- 应用底部栏可见性设置
   	if BankFrame.UpdateFooterVisibility then
   		BankFrame:UpdateFooterVisibility()
   	end

	-- 应用框架透明度
	if GudaBag.ApplyBackgroundTransparency then
		GudaBag.ApplyBackgroundTransparency()
	end

	-- 应用锁定状态
	if BankFrame.UpdateLockState then
		BankFrame:UpdateLockState()
	end

   	BankFrame:Update()

    -- 调度延迟可用性检查，修复未缓存物品数据导致的误判
    -- 该检查会在物品信息被 WoW 客户端完全加载后延迟一小段时间运行
    ScheduleBankDeferredUsabilityCheck()
end

-- 隐藏时（OnHide）
function GudaBag.BankFrame_OnHide(self)
    -- 银行框架隐藏时关闭任何打开的下拉菜单
    CloseDropDownMenus()

    -- 清除任何待处理的更新
    bankPendingUpdate = false

    -- 取消任何待处理的限流更新
    local throttleFrame = getglobal("Guda_BankUpdateThrottle")
    if throttleFrame then
        throttleFrame:Hide()
    end

    -- 取消任何待处理的延迟可用性检查（防抖安全）
    CancelBankDeferredUsabilityCheck()

    -- 清空搜索字段
    GudaBag.BankFrame_ClearSearch()

    -- 清空最近清空槽位跟踪（重置占位符）
    BankFrame:ClearRecentlyEmptiedSlots()

    -- 清除所有按钮上的 isEmptyPlaceholder 标志（为下次打开重置）
    for bagID, slots in pairs(bankSlotToButton) do
        if type(slots) == "table" then
            for slotID, button in pairs(slots) do
                if button and button.isEmptyPlaceholder then
                    button.isEmptyPlaceholder = nil
                end
            end
        end
    end

    -- 仅在查看我们自己的真实银行时才关闭服务端银行会话；
    -- 其他角色的已保存银行没有可关闭的活动 NPC 会话。
    if not currentViewChar then
        CloseBankFrame()
    end
end

-- 切换可见性
function BankFrame:Toggle()
    if Guda_BankFrame:IsShown() then
        Guda_BankFrame:Hide()
    else
        Guda_BankFrame:Show()
    end
end

-- 显示指定角色的银行（只读模式）
function BankFrame:ShowCharacter(fullName)
    currentViewChar = fullName
    isReadOnlyMode = true  -- 正在查看保存的银行数据（只读）
    self:Update()
end

-- 显示当前角色的银行（交互模式）
function BankFrame:ShowCurrentCharacter()
    currentViewChar = nil
    isReadOnlyMode = false  -- 正在查看实时银行（交互）
    self:Update()
end

-- 保存银行框架位置（持久化保存，使窗口在用户上次放置的位置
-- 重新打开，而不是回到默认的中心锚点）。
-- 注意：特意使用全局（而非 local）—— 本文件前面定义的
-- GudaBag.BankFrame_OnShow 通过全局名引用它们；local 会解析为 nil。
function GudaBag.SaveBankFramePosition()
    local frame = getglobal("Guda_BankFrame")
    if not frame or not addon or not addon.Modules or not addon.Modules.DB then return end
    local right = frame:GetRight()
    local bottom = frame:GetBottom()
    local screenWidth = GetScreenWidth()
    if right and bottom and screenWidth then
        addon.Modules.DB:SetSetting("bankFramePosition", {
            point = "BOTTOMRIGHT",
            x = right - screenWidth,
            y = bottom,
        })
    end
end

-- 如果存在已保存的银行框架位置则恢复；否则保持
-- 默认 XML 锚点不变。
function GudaBag.RestoreBankFramePosition(frame)
    if not frame then return end
    if not addon or not addon.Modules or not addon.Modules.DB then return end
    local pos = addon.Modules.DB:GetSetting("bankFramePosition")
    if pos and pos.point and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, "UIParent", pos.relativePoint or pos.point, pos.x, pos.y)
    end
end

-- 全局辅助函数，使 XML OnMouseUp 处理函数也能持久化位置。
function GudaBag.BankFrame_SavePosition()
    GudaBag.SaveBankFramePosition()
end

-- 集中化的银行移动开始/停止逻辑，与 BagFrame 的 BeginFrameMove/EndFrameMove 对应。
-- 拖动期间隐藏全部物品按钮，降低原生 StartMoving 逐帧重绘数百个子区域的
-- 渲染成本（否则拖动时帧率会从 ~150 骤降到 30-50）。EndBankFrameMove 里的
-- Update() 重建会恢复按钮。
local function BeginBankFrameMove()
    local bankFrame = getglobal("Guda_BankFrame")
    if not bankFrame then return end
    -- 光标已持有物品时不应进入框架拖拽（与 BagFrame 一致）
    if CursorHasItem and CursorHasItem() then return end
    bankIsFrameMoving = true
    -- 暂停后台工作队列，避免每个渲染帧消耗大量时间拖垮拖拽帧率
    if addon.Modules.Utils and addon.Modules.Utils.PauseWorkQueue then
        addon.Modules.Utils:PauseWorkQueue()
    end
    GudaBag.HideItemButtonsForDrag(bankBagParents)
    bankFrame:StartMoving()
end

local function EndBankFrameMove()
    local bankFrame = getglobal("Guda_BankFrame")
    if not bankFrame then return end
    -- 未在拖拽框架（BeginBankFrameMove 因光标持有物品被跳过）：不执行框架
    -- 停止/重建，避免干扰物品放置流程。
    if not bankIsFrameMoving then return end
    bankFrame:StopMovingOrSizing()
    bankIsFrameMoving = false
    GudaBag.SaveBankFramePosition()
    if addon.Modules.Utils and addon.Modules.Utils.ResumeWorkQueue then
        addon.Modules.Utils:ResumeWorkQueue()
    end
    -- 执行一次重建，恢复拖动期间被隐藏的按钮
    BankFrame:Update()
end

-- 更新现有按钮的锁定状态（轻量，用于拖动期间）
function BankFrame:UpdateLockStates()
    GudaBag.UpdateLockStates(bankBagParents)
end

-- 排序/重整理期间隐藏所有物品按钮（提高帧数）。供 SortEngine 调用。
function GudaBag.BankFrame_HideAllItemButtons()
    GudaBag.HideItemButtons(bankBagParents)
end

-- 恢复被隐藏的物品按钮（排序结束后由 Update() 重建亦可，此函数供需要时直接恢复）
function GudaBag.BankFrame_ShowAllItemButtons()
    GudaBag.ShowItemButtons(bankBagParents)
end

-- 更新窗口锁定状态（启用/禁用拖拽）
function BankFrame:UpdateLockState()
    if not addon or not addon.Modules or not addon.Modules.DB then return end

    local frame = getglobal("Guda_BankFrame")
    if not frame then return end

    local isLocked = addon.Modules.DB:GetSetting("lockBags")
    if isLocked == nil then isLocked = false end

    local toolbar = getglobal("Guda_BankFrame_Toolbar")

    if isLocked then
        if frame.SetScript then
            frame:SetScript("OnMouseDown", function()
                local searchBox = getglobal("Guda_BankFrame_SearchBar_SearchBox")
                if searchBox then searchBox:ClearFocus() end
            end)
            frame:SetScript("OnMouseUp", nil)
        end
        if toolbar and toolbar.SetScript then
            toolbar:SetScript("OnMouseDown", function()
                local searchBox = getglobal("Guda_BankFrame_SearchBar_SearchBox")
                if searchBox then searchBox:ClearFocus() end
            end)
            toolbar:SetScript("OnMouseUp", nil)
        end
    else
        if frame and frame.SetScript then
            frame:SetScript("OnMouseDown", function()
                local searchBox = getglobal("Guda_BankFrame_SearchBar_SearchBox")
                if searchBox then searchBox:ClearFocus() end
                if arg1 == "LeftButton" then
                    BeginBankFrameMove()
                end
            end)
            frame:SetScript("OnMouseUp", function()
                EndBankFrameMove()
            end)
        end
        if toolbar and toolbar.SetScript then
            toolbar:SetScript("OnMouseDown", function()
                local searchBox = getglobal("Guda_BankFrame_SearchBar_SearchBox")
                if searchBox then searchBox:ClearFocus() end
                if arg1 == "LeftButton" then
                    BeginBankFrameMove()
                end
            end)
            toolbar:SetScript("OnMouseUp", function()
                EndBankFrameMove()
            end)
        end
    end
end

-- 不进行完整框架重绘地更新单个槽位（用于手动移动物品）
function BankFrame:UpdateSingleSlot(bagID, slotID, passedButton)
    if not Guda_BankFrame:IsShown() then
        addon:DebugCategory("UpdateSingleSlot: frame not shown")
        return false
    end
    if currentViewChar then
        addon:DebugCategory("UpdateSingleSlot: viewing other char")
        return false
    end

    -- 若可用则使用传入的按钮（来自 UpdateChangedSlots 迭代）
    -- 这避免了槽位 ID 键的类型不匹配问题（字符串 vs 数字）
    local targetButton = passedButton

    if not targetButton then
        -- 回退到使用哈希表的 O(1) 按钮查找
        if not bankSlotToButton[bagID] then
            addon:DebugCategory("UpdateSingleSlot: no slotToButton for bag %d", bagID)
            return false
        end
        -- 同时尝试数字键和字符串键以处理类型不匹配
        targetButton = bankSlotToButton[bagID][slotID] or bankSlotToButton[bagID][tonumber(slotID)]
        if not targetButton then
            addon:DebugCategory("UpdateSingleSlot: no button for bag %d slot %d", bagID, slotID)
            return false
        end
    end

    -- 获取此槽位的最新物品数据
    local itemLink = GetContainerItemLink(bagID, slotID)
    local itemData = nil

    if itemLink then
        local texture, itemCount, locked, quality = GetContainerItemInfo(bagID, slotID)
        local itemID = nil
        local _, _, idStr = string.find(itemLink, "item:(%d+)")
        if idStr then itemID = tonumber(idStr) end

        if itemID then
            local name, link, itemQuality, iLevel, itemCategory, _, stackCount, subType, _, equipLoc = GetItemInfo(itemID)
            itemData = {
                link = itemLink,
                texture = texture,
                count = itemCount or 1,
                quality = quality or itemQuality or 0,  -- 优先用 GetContainerItemInfo，回退到 GetItemInfo
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

    addon:DebugCategory("UpdateSingleSlot: bag=%d slot=%d hasItem=%s -> updating button", bagID, slotID, itemLink and "yes" or "no")

    -- 在分类视图中跟踪槽位何时变空（保持空占位符可见）
    local viewType = addon.Modules.DB:GetSetting("bankViewType") or "single"
    local hadItem = targetButton.itemData and targetButton.itemData.link
    local hasItem = itemData and itemData.link

    if viewType == "category" then
        if hadItem and not hasItem then
            -- 物品被移除 —— 显示空占位符，保持按钮可见
            addon:DebugCategory("UpdateSingleSlot: slot %d:%d emptied, showing empty placeholder", bagID, slotID)
            -- 标记为仍在使用中，使清理过程不会隐藏它
            targetButton.inUse = true
            targetButton.isEmptyPlaceholder = true
                                    -- 同时标记到 recentlyEmptiedSlots 以支持完整重绘
            local oldItemData = targetButton.itemData
            local oldCategory = "Miscellaneous"
            if oldItemData and oldItemData.link then
                oldCategory = addon.Modules.CategoryManager:CategorizeItem(oldItemData, bagID, slotID) or "Miscellaneous"
            end
            self:MarkSlotAsEmptied(bagID, slotID, oldCategory, oldItemData)
        elseif hasItem and not hadItem then
            -- 物品被添加
            targetButton.isEmptyPlaceholder = false
            self:UnmarkSlotAsEmptied(bagID, slotID)
        end
    end

    -- 视觉上更新按钮
    local matchesFilter = self:PassesSearchFilter(itemData)
    GudaBag.ItemButton_SetItem(targetButton, bagID, slotID, itemData, true, nil, matchesFilter, isReadOnlyMode)

    -- 确保空占位符保持可见
    if viewType == "category" and targetButton.isEmptyPlaceholder then
        targetButton:Show()
    end

    return true
end

-- 通过与缓存数据比较来更新银行背包中发生变化的槽位
-- 返回已更新的槽位数，需要完整重绘时返回 -1
function BankFrame:UpdateChangedSlots(bagID)
    if not Guda_BankFrame:IsShown() then
        addon:DebugCategory("UpdateChangedSlots: frame not shown")
        return -1
    end
    if currentViewChar then
        addon:DebugCategory("UpdateChangedSlots: viewing other char")
        return -1
    end

    -- 检查此银行背包是否已有槽位查找表
    if not bankSlotToButton[bagID] then
        addon:DebugCategory("UpdateChangedSlots: no slotToButton for bag %d", bagID)
        return -1
    end

    local viewType = addon.Modules.DB:GetSetting("bankViewType") or "single"
    local isCategoryView = (viewType == "category")
    addon:DebugCategory("UpdateChangedSlots: bag=%d, viewType=%s, isCategoryView=%s",
        bagID, viewType, tostring(isCategoryView))

    if isCategoryView then
        -- 分类视图中：就地更新已有按钮映射的槽位
        -- 并检查是否有新物品出现在没有按钮的槽位中
        local updatedCount = 0
        for slotID, targetButton in pairs(bankSlotToButton[bagID]) do
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
                addon:DebugCategory("  slot %d: needs update (had=%s, now=%s)", slotID,
                    cachedLink and "item" or "empty", currentLink and "item" or "empty")
                -- 直接传入按钮以避免类型不匹配查找问题
                if self:UpdateSingleSlot(bagID, slotID, targetButton) then
                    updatedCount = updatedCount + 1
                else
                    addon:DebugCategory("  slot %d: UpdateSingleSlot failed -> full redraw", slotID)
                    return -1
                end
            end
        end

        -- 关键：检查是否有新物品出现在没有按钮映射的槽位中
        -- 分类视图只为已填充的槽位创建按钮，因此新物品需要完整重绘
        local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
        if numSlots and numSlots > 0 then
            for checkSlotID = 1, numSlots do
                -- 如果槽位有物品但没有按钮映射 -> 有新物品到达
                -- 同时检查数字键和可能的字符串键
                local hasButton = bankSlotToButton[bagID][checkSlotID] or bankSlotToButton[bagID][tostring(checkSlotID)]
                if not hasButton then
                    local currentLink = GetContainerItemLink(bagID, checkSlotID)
                    if currentLink then
                        addon:DebugCategory("  slot %d: NEW item arrived (no button) -> full redraw", checkSlotID)
                        return -1  -- 触发完整重绘以对新物品进行分类
                    end
                end
            end
        end

        addon:DebugCategory("UpdateChangedSlots (category): success, updated %d slots", updatedCount)
        return updatedCount
    else
        -- 单视图：检查所有槽位
        local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
        if not numSlots or numSlots == 0 then
            addon:DebugCategory("UpdateChangedSlots: no slots for bag %d", bagID)
            return -1
        end

        local updatedCount = 0
        for slotID = 1, numSlots do
            -- 同时尝试数字键和字符串键以处理类型不匹配
            local targetButton = bankSlotToButton[bagID][slotID] or bankSlotToButton[bagID][tostring(slotID)]

            if not targetButton then
                addon:DebugCategory("  slot %d: no button in single view -> full redraw", slotID)
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
                addon:DebugCategory("  slot %d: needs update (had=%s, now=%s)", slotID,
                    cachedLink and "item" or "empty", currentLink and "item" or "empty")
                -- 直接传入按钮以避免类型不匹配查找问题
                if self:UpdateSingleSlot(bagID, slotID, targetButton) then
                    updatedCount = updatedCount + 1
                else
                    addon:DebugCategory("  slot %d: UpdateSingleSlot failed -> full redraw", slotID)
                    return -1
                end
            end
        end
        addon:DebugCategory("UpdateChangedSlots (single): success, updated %d slots", updatedCount)
        return updatedCount
    end
end

-- 用于帧预算的延迟更新状态
local bankPendingUpdate = false
local bankUpdateDebounceFrame = nil
local BANK_UPDATE_DEBOUNCE_TIME = 0.05  -- 快速更新的 50ms 防抖

-- 使用防抖调度更新（防止短时间内连续多次更新）
function BankFrame:ScheduleUpdate()
    if bankPendingUpdate then return end
    bankPendingUpdate = true

    if not bankUpdateDebounceFrame then
        bankUpdateDebounceFrame = CreateFrame("Frame")
        bankUpdateDebounceFrame.elapsed = 0
    end

    bankUpdateDebounceFrame.elapsed = 0
    bankUpdateDebounceFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= BANK_UPDATE_DEBOUNCE_TIME then
            this:SetScript("OnUpdate", nil)
            bankPendingUpdate = false
            BankFrame:Update()
        end
    end)
end

-- 更新显示
function BankFrame:Update()
    if not Guda_BankFrame:IsShown() then
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

    -- 框架正被拖拽移动：跳过完整的分类重建，仅廉价地刷新锁定状态。
    -- EndBankFrameMove 会在放下时执行一次重建。
    if bankIsFrameMoving then
        self:UpdateLockStates()
        return
    end

    -- 为帧预算跟踪记录入口
    if addon.Modules.Utils and addon.Modules.Utils.ReportEntry then
        addon.Modules.Utils:ReportEntry()
    end

    -- 如果光标正拿着物品（拖拽中），只更新锁定状态，不重建 UI
    -- 但仅当已显示物品时才这样 —— 否则仍需要进行首次构建
    if CursorHasItem and CursorHasItem() then
        -- 检查是否已显示任何物品
        local hasDisplayedItems = false
        for _, bankBagParent in pairs(bankBagParents) do
            if bankBagParent and bankBagParent.itemButtons then
                for button in pairs(bankBagParent.itemButtons) do
                    if button.hasItem and button:IsShown() then
                        hasDisplayedItems = true
                        break
                    end
                end
            end
            if hasDisplayedItems then break end
        end

        if hasDisplayedItems then
            self:UpdateLockStates()
            return
        end
        -- 如果尚未显示物品，则继续完整更新
    end

    -- 将所有现有按钮标记为未使用（显示过程中会把活跃的标记回来）
    -- 同时清空槽位查找表以进行全新重建
    for _, bankBagParent in pairs(bankBagParents) do
        if bankBagParent and bankBagParent.itemButtons then
            for button in pairs(bankBagParent.itemButtons) do
                if button.hasItem ~= nil then
                    button.inUse = false
                end
            end
        end
    end
    for k in pairs(bankSlotToButton) do
        bankSlotToButton[k] = nil
    end

    -- 判断是否处于只读模式：
    -- - 查看其他角色 → 只读
    -- - 银行实际打开 → 交互（实时）
    -- - 其他情况 → 只读（查看已保存的数据）
    local bankIsOpen = addon.Modules.BankScanner:IsBankOpen()
    isReadOnlyMode = currentViewChar ~= nil or not bankIsOpen

    local bankData
    local isOtherChar = false
    local charName = ""

    if currentViewChar then
        -- 查看其他角色已保存的银行
        bankData = addon.Modules.DB:GetCharacterBank(currentViewChar)
        isOtherChar = true
        charName = currentViewChar
        getglobal("Guda_BankFrame_Title"):SetText(format(GudaBag.L["%s's Bank"], currentViewChar))
    else
    -- 查看当前角色的银行
    -- 若银行正式打开或可访问银行数据，则使用实时数据
    -- （处理 IsBankOpen 返回 false 但银行仍可访问的边界情况）
        local useLiveData = bankIsOpen
        if not useLiveData then
            -- 无论如何都尝试获取实时数据 —— 如果银行背包可访问，则使用实时数据
            local testSlots = GetContainerNumSlots(-1)  -- 主银行
            if testSlots and testSlots > 0 then
                useLiveData = true
                addon:DebugCategory("Update: IsBankOpen=false but bank accessible, using live data")
            end
        end

        local playerName = addon.Modules.DB:GetPlayerFullName()
        if useLiveData then
            -- 银行可访问 —— 使用实时数据
            bankData = addon.Modules.BankScanner:GetBankData()
            getglobal("Guda_BankFrame_Title"):SetText(format(GudaBag.L["%s's Bank"], playerName))
        else
            -- 银行确实已关闭 —— 使用已保存的数据（只读模式）
            bankData = addon.Modules.DB:GetCharacterBank(playerName)
            getglobal("Guda_BankFrame_Title"):SetText(format(GudaBag.L["%s's Bank"], playerName))
        end
    end

    local viewType = addon.Modules.DB:GetSetting("bankViewType") or "single"
    
    -- 显示物品前重置所有分区标题
    local i = 1
    while true do
        local header = getglobal("Guda_BankFrame_SectionHeader" .. i)
        if not header then break end
        header.inUse = false
        header:Hide()
        i = i + 1
    end

    if viewType == "category" then
        -- 调试：显示前检查 bankData
        local bagCount = 0
        local totalItems = 0
        for bagID, bag in pairs(bankData or {}) do
            bagCount = bagCount + 1
            if bag and bag.slots then
                for slotID, item in pairs(bag.slots) do
                    if item then
                        totalItems = totalItems + 1
                    end
                end
            end
        end
        addon:DebugCategory("Update: bankData has %d bags, %d total items", bagCount, totalItems)
        self:DisplayItemsByCategory(bankData, isOtherChar, charName)
        -- 为分类视图显示带有合并图标/提示的排序按钮
        local sortBtn = getglobal("Guda_BankFrame_SortButton")
        if sortBtn then
            sortBtn:Show()
            sortBtn.isCategoryView = true
        end
    else
        self:DisplayItems(bankData, isOtherChar, charName)
        local sortBtn = getglobal("Guda_BankFrame_SortButton")
        if sortBtn then
            sortBtn:Show()
            sortBtn.isCategoryView = false
        end
    end

    -- 更新金钱
    self:UpdateMoney()

    -- 更新银行槽位信息
    self:UpdateBankSlotsInfo(bankData, isOtherChar)

    -- 显示完成后清理未使用的按钮（防止拖拽/放置问题）
    for _, bankBagParent in pairs(bankBagParents) do
        if bankBagParent and bankBagParent.itemButtons then
            for button in pairs(bankBagParent.itemButtons) do
                if button.hasItem ~= nil and not button.inUse then
                    button:Hide()
                    button:ClearAllPoints()
                end
            end
        end
    end

    -- 记录性能指标
    if addon.Modules.Utils and addon.Modules.Utils.RecordUpdateEnd then
        addon.Modules.Utils:RecordUpdateEnd()
    end
end

-- 使用集中式框架辅助函数处理分区标题和银行背包父框架
function BankFrame:GetSectionHeader(index)
    return GudaBag.GetSectionHeader("Guda_BankFrame", "Guda_BankFrame_ItemContainer", index)
end

function BankFrame:GetBagParent(bagID)
    return GudaBag.GetBagParent("Guda_BankFrame", bankBagParents, bagID, "Guda_BankFrame_ItemContainer")
end

-- 按分类显示物品
function BankFrame:DisplayItemsByCategory(bankData, isOtherChar, charName)
    local buttonSize = addon.Modules.DB:GetSetting("iconSize") or addon.Constants.BUTTON_SIZE
    local spacing = addon.Modules.DB:GetSetting("iconSpacing") or addon.Constants.BUTTON_SPACING
    local perRow = addon.Modules.DB:GetSetting("bankColumns") or 10
    local itemContainer = getglobal("Guda_BankFrame_ItemContainer")

    -- 使用集中式分类初始化
    local categories, specialItems = GudaBag.InitCategories()
    local categoryList = GudaBag.CategoryList

    -- 使用集中式函数对所有物品进行分类
    local totalItemsCategorized = 0
    for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
        if not hiddenBankBags[bagID] then
            local bag = bankData[bagID]
            if bag and bag.slots then
                local bagItemCount = 0
                for slotID, itemData in pairs(bag.slots) do
                    if itemData then
                        GudaBag.CategorizeItem(itemData, bagID, slotID, categories, specialItems, isOtherChar)
                        bagItemCount = bagItemCount + 1
                        totalItemsCategorized = totalItemsCategorized + 1
                    end
                end
                if bagItemCount > 0 then
                    addon:DebugCategory("DisplayItemsByCategory: bag %d has %d items", bagID, bagItemCount)
                end
            else
                addon:DebugCategory("DisplayItemsByCategory: bag %d has no data (bag=%s, slots=%s)",
                    bagID, tostring(bag ~= nil), tostring(bag and bag.slots ~= nil))
            end
        end
    end
    addon:DebugCategory("DisplayItemsByCategory: total items categorized = %d", totalItemsCategorized)

    -- 将最近清空的槽位作为空占位符添加到各自分类中
    -- 这保留了刚被移走物品的视觉位置
    if not isOtherChar then
        for bagID, slots in pairs(recentlyEmptiedSlots) do
            if not hiddenBankBags[bagID] then
                for slotID, info in pairs(slots) do
                    -- 仅当槽位确实为空时添加（未被重新填满）
                    local currentLink = GetContainerItemLink(bagID, slotID)
                    if not currentLink then
                        local catName = info.category
                        if catName and categories[catName] then
                            -- 将空占位符添加到分类中，并带上原物品的排序属性
                            -- 这使占位符与原物品保持在相同的视觉位置
                            table.insert(categories[catName], {
                                bagID = bagID,
                                slotID = slotID,
                                itemData = {
                                    -- 伪造带有原物品排序相关属性的 itemData
                                    quality = info.quality or 0,
                                    name = info.name or "",
                                    iLevel = info.iLevel or 0,
                                },
                                isEmpty = true,  -- 标记为占位符（显示时显示空槽位）
                            })
                            addon:DebugCategory("Added empty placeholder for %d:%d to category %s", bagID, slotID, catName)
                        end
                    else
                        -- 槽位现在有物品了，从跟踪中移除
                        slots[slotID] = nil
                    end
                end
            end
        end
    end

    -- 计算空槽位总数，并找出第一个可用槽位作为放置目标。
    -- 专用银行背包（灵魂/草药/附魔/箭袋/弹药）只接受其对应
    -- 类别，因此它们的槽位不属于通用的"Empty"伪分类。
    local totalFreeSlots = 0
    local firstFreeBag, firstFreeSlot
    for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
        if not hiddenBankBags[bagID]
           and not addon.Modules.Utils:GetSpecializedBagType(bagID) then
            local bag = bankData[bagID]
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

    -- 布局（感知主题的内边距）
    local _pad = { startX = 5, startY = -10 }
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

    for _, catName in ipairs(categoryList) do
        local catDef = addon.Modules.CategoryManager and addon.Modules.CategoryManager:GetCategory(catName) or nil

        -- 处理 Empty 分类：显示一个带空槽位数的单一槽位
        if catDef and catDef.isEmptyCategory then
            if totalFreeSlots > 0 and catDef.enabled then
                local blockWidth = 1 * (buttonSize + spacing)
                local blockHeight = 20 + (1 * (buttonSize + spacing)) + 5

                if currentX > 0 and currentX + blockWidth + 20 > totalWidth + 5 then
                    currentX = 0
                    currentY = currentY + rowMaxHeight
                    rowMaxHeight = 0
                end

                local header = self:GetSectionHeader(headerIdx)
                headerIdx = headerIdx + 1
                header:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", startX + currentX, startY - currentY)
                header:SetWidth(blockWidth)
                local displayName = catName
                if addon.Modules.CategoryManager and addon.Modules.CategoryManager.GetDisplayName then
                    displayName = addon.Modules.CategoryManager:GetDisplayName(catName, catDef)
                elseif catDef and catDef.name then
                    displayName = catDef.name
                end
                header.fullName = displayName
                header.isShortened = false
                header.text:SetText(displayName)
                if header.countText then header.countText:Hide() end
                header:Show()

                local itemY = currentY + 20
                local bagID = firstFreeBag or -1
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
                GudaBag.ItemButton_SetItem(button, bagID, slotID, emptyItemData, true, isOtherChar and charName or nil, true, true)
                button.isReadOnly = false
                button.inUse = true

                if blockHeight > rowMaxHeight then rowMaxHeight = blockHeight end
                currentX = currentX + blockWidth + 20
            end
        else

        local items = categories[catName]
        local numItems = items and table.getn(items) or 0
        if numItems > 0 then
            -- 使用集中式排序器对物品排序
            GudaBag.SortCategoryItems(items)

            local blockCols = numItems
            if blockCols > perRow then blockCols = perRow end
            local blockRows = math.ceil(numItems / perRow)
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
            if string.len(displayName) > 10 and numItems < 2 then
                displayName = string.sub(displayName, 1, 7) .. "..."
                header.isShortened = true
            end
            header.text:SetText(displayName)
            header:Show()
            
            local itemY = currentY + 20
            local col = 0
            local row = 0
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
                GudaBag.ItemButton_SetItem(button, bagID, slot, itemData, true, isOtherChar and charName or nil, matchesFilter, isOtherChar or isReadOnlyMode)
                button.inUse = true
                button.itemCategory = catName  -- 跟踪分类以用于空槽位占位符
                button.isEmptyPlaceholder = item.isEmpty  -- 跟踪这是否是占位符
                -- 填充槽位查找表以实现 O(1) 访问
                if not bankSlotToButton[bagID] then bankSlotToButton[bagID] = {} end
                bankSlotToButton[bagID][slot] = button
                -- 仅当槽位现在有物品（而非占位符）时才从"最近清空"中移除
                if itemData then
                    self:UnmarkSlotAsEmptied(bagID, slot)
                end

                col = col + 1
                if col >= blockCols then
                    col = 0
                    row = row + 1
                end

                -- 帧预算检查
                categoryItemsProcessed = categoryItemsProcessed + 1
                if categoryItemsProcessed >= CATEGORY_ITEMS_PER_BUDGET_CHECK then
                    categoryItemsProcessed = 0
                    if addon.Modules.Utils and addon.Modules.Utils.CheckTimeout and addon.Modules.Utils:CheckTimeout() then
                        addon.Modules.Utils:ReportEntry()
                    end
                end
            end

            if blockHeight > rowMaxHeight then rowMaxHeight = blockHeight end
            currentX = currentX + blockWidth + 20
        end
        end -- isEmptyCategory 的 else 分支结束
    end

    -- 为底部分区更新 Y 坐标
    local y = currentY + rowMaxHeight

    -- 底部的特殊分区（现在只有坐骑；主页/工具/空是真实分类）
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
                    GudaBag.ItemButton_SetItem(button, item.bagID, item.slotID, item.itemData, true, isOtherChar and charName or nil, self:PassesSearchFilter(item.itemData), isOtherChar or isReadOnlyMode)
                    button.inUse = true
                    -- 填充槽位查找表以实现 O(1) 访问
                    if not bankSlotToButton[item.bagID] then bankSlotToButton[item.bagID] = {} end
                    bankSlotToButton[item.bagID][item.slotID] = button

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
end

-- 显示物品
function BankFrame:DisplayItems(bankData, isOtherChar, charName)
    local _pad = { startX = 5, startY = -10 }
    if addon.Modules and addon.Modules.Theme and addon.Modules.Theme.GetFramePadding then
        _pad = addon.Modules.Theme:GetFramePadding()
    end
    local x, y = _pad.startX, _pad.startY
    local row = 0
    local col = 0
    local buttonSize = addon.Modules.DB:GetSetting("iconSize") or addon.Constants.BUTTON_SIZE
    local spacing = addon.Modules.DB:GetSetting("iconSpacing") or addon.Constants.BUTTON_SPACING
    local perRow = addon.Modules.DB:GetSetting("bankColumns") or 10
    local itemContainer = getglobal("Guda_BankFrame_ItemContainer")

    -- 将银行背包分为普通、附魔、草药、灵魂、箭袋和弹药类型
    local regularBags = {}
    local enchantBags = {}
    local herbBags = {}
    local soulBags = {}
    local quiverBags = {}
    local ammoBags = {}

    for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
        if not hiddenBankBags[bagID] then
            local bagType
            if isOtherChar then
                -- 对其他角色使用保存的背包类型
                local bagSaved = bankData and bankData[bagID]
                bagType = bagSaved and bagSaved.bagType or "regular"
            else
                -- 当前角色在银行打开时的统一实时检测
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

    -- 构建显示顺序：普通 -> 附魔 -> 草药 -> 灵魂 -> 箭袋 -> 弹药
    local bagsToShow = {}
    for _, bagID in ipairs(regularBags) do
        table.insert(bagsToShow, { bagID = bagID, needsSpacing = false })
    end
    if table.getn(enchantBags) > 0 then
        for i, bagID in ipairs(enchantBags) do
            table.insert(bagsToShow, { bagID = bagID, needsSpacing = (i == 1) })
        end
    end
    if table.getn(herbBags) > 0 then
        for i, bagID in ipairs(herbBags) do
            table.insert(bagsToShow, { bagID = bagID, needsSpacing = (i == 1) })
        end
    end
    if table.getn(soulBags) > 0 then
        for i, bagID in ipairs(soulBags) do
            table.insert(bagsToShow, { bagID = bagID, needsSpacing = (i == 1) })
        end
    end
    if table.getn(quiverBags) > 0 then
        for i, bagID in ipairs(quiverBags) do
            table.insert(bagsToShow, { bagID = bagID, needsSpacing = (i == 1) })
        end
    end
    if table.getn(ammoBags) > 0 then
        for i, bagID in ipairs(ammoBags) do
            table.insert(bagsToShow, { bagID = bagID, needsSpacing = (i == 1) })
        end
    end

    -- 物品处理的帧预算跟踪
    local itemsProcessed = 0
    local ITEMS_PER_BUDGET_CHECK = 8  -- 每 N 个物品检查一次预算

    for _, bagInfo in ipairs(bagsToShow) do
        local bagID = bagInfo.bagID
        local bag = bankData and bankData[bagID]

        -- 在每个专用分区第一个前面添加间距
        if bagInfo.needsSpacing then
            if col > 0 then
                col = 0
                row = row + 1
            end
            row = row + 0.5
        end

        -- 获取此背包的槽位数量
        local numSlots
        if isOtherChar and bag and bag.numSlots then
            numSlots = bag.numSlots
        else
            numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
        end

        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemData = bag and bag.slots and bag.slots[slot] or nil

                local matchesFilter = self:PassesSearchFilter(itemData)

                -- 确保每个背包都有一个父框架并携带背包 ID
                local bankBagParent = self:GetBagParent(bagID)

                local button = GudaBag.GetItemButton(bankBagParent)
                button.inUse = true

                local xPos = x + (col * (buttonSize + spacing))
                local yPos = y - (row * (buttonSize + spacing))

                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", itemContainer, "TOPLEFT", xPos, yPos)

                GudaBag.ItemButton_SetItem(button, bagID, slot, itemData, true, isOtherChar and charName or nil, matchesFilter, isReadOnlyMode)
                -- 填充槽位查找表以实现 O(1) 访问
                if not bankSlotToButton[bagID] then bankSlotToButton[bagID] = {} end
                bankSlotToButton[bagID][slot] = button

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
                        addon.Modules.Utils:ReportEntry()
                    end
                end
            end
        end
    end

    -- 根据内容动态调整框架大小
    self:ResizeFrame(row, col, perRow)
end

-- 根据行数和列数调整银行框架大小
function BankFrame:ResizeFrame(currentRow, currentCol, columns, overrideHeight)
    local buttonSize = addon.Modules.DB:GetSetting("iconSize") or addon.Constants.BUTTON_SIZE
    local spacing = addon.Modules.DB:GetSetting("iconSpacing") or addon.Constants.BUTTON_SPACING

    -- 计算实际使用的行数
    -- 如果 col==0，row 已递增（整行），因此 totalRows = row
    -- 如果 col>0，是部分行，因此 totalRows = row + 1
    local totalRows = (currentRow or 0)
    if (currentCol or 0) > 0 then
        totalRows = totalRows + 1
    end
    if totalRows < 1 then
        totalRows = 1
    end

    -- 确保至少有 1 列
    if not columns or columns < 1 then
        columns = 1
    end

    -- 获取感知主题的内边距
    local pad = { containerExtra = 20, frameExtra = 20, titleHeight = 40, searchBarHeight = 30, footerHeight = 45, footerHiddenHeight = 10 }
    if addon.Modules and addon.Modules.Theme and addon.Modules.Theme.GetFramePadding then
        pad = addon.Modules.Theme:GetFramePadding()
    end

    -- 计算所需尺寸（对称：两侧都有 startX 内边距，无尾部间距）
    local containerWidth = columns * (buttonSize + spacing) - spacing + 2 * pad.startX
    local containerHeight = overrideHeight or (totalRows * (buttonSize + spacing) - spacing + 2 * math.abs(pad.startY))
    local frameWidth = containerWidth + pad.frameExtra

    -- 检查搜索栏是否可见（三态模式：shown 常显；hidden/toggle 仅展开时预留高度）
    local searchMode = addon.Modules.DB:GetSetting("searchBarMode")
    if searchMode ~= "shown" and searchMode ~= "hidden" and searchMode ~= "toggle" then
        local legacy = addon.Modules.DB:GetSetting("showSearchBar")
        searchMode = (legacy == false) and "hidden" or "shown"
    end
    local showSearchBar
    if searchMode == "shown" then
        showSearchBar = true
    else
        showSearchBar = self.searchBarExpanded and true or false
    end

    local titleHeight = pad.titleHeight
    local searchBarHeight = pad.searchBarHeight
    local footerHeight = pad.footerHeight
    local frameHeight

    local hideFooter = addon.Modules.DB:GetSetting("hideFooter")

    if hideFooter then
        footerHeight = pad.footerHiddenHeight
        frameHeight = containerHeight + titleHeight + (showSearchBar and searchBarHeight or 0) + footerHeight
    elseif showSearchBar then
        frameHeight = containerHeight + titleHeight + searchBarHeight + footerHeight
    else
        frameHeight = containerHeight + titleHeight + footerHeight
    end

    -- 最小尺寸
    if containerWidth < 200 then
        containerWidth = 200
        frameWidth = 200 + pad.frameExtra
    end
    if containerHeight < 150 then
        containerHeight = 150
    end
    if frameHeight < 250 then
        frameHeight = 250
    end

    -- 最大尺寸
    if containerWidth > 1250 then
        containerWidth = 1250
        frameWidth = 1280
    end
    if containerHeight > 1000 then
        containerHeight = 1000
    end
    if frameHeight > 1200 then
        frameHeight = 1200
    end

    local bankFrame = getglobal("Guda_BankFrame")
    local itemContainer = getglobal("Guda_BankFrame_ItemContainer")

    if bankFrame then
        bankFrame:SetWidth(frameWidth)
        bankFrame:SetHeight(frameHeight)
    end

    if itemContainer then
        itemContainer:SetWidth(containerWidth)
        itemContainer:SetHeight(containerHeight)
    end

    -- 调整搜索栏宽度以匹配容器宽度
    local searchBar = getglobal("Guda_BankFrame_SearchBar")
    if searchBar then
        searchBar:SetWidth(containerWidth)
    end
end

-- 银行背包类型显示名称
local BANK_BAG_TYPE_NAMES = {
    soul = "Soul Bag",
    herb = "Herb Bag",
    enchant = "Enchanting Bag",
    quiver = "Quiver",
    ammo = "Ammo Pouch",
}

-- 更新银行槽位信息文本（只显示普通背包，特殊背包显示在提示中）
function BankFrame:UpdateBankSlotsInfo(bankData, isOtherChar)
    local infoText = getglobal("Guda_BankFrame_Toolbar_BankSlotsInfo_Text")
    if not infoText then return end

    local regularTotal = 0
    local regularUsed = 0
    local specialBags = {} -- { [type] = { total, used, name } }

    -- 统计银行背包中的槽位，将普通背包与特殊背包分开
    for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
        local bag = bankData[bagID]

        -- 获取此背包的槽位数量
        local numSlots
        if isOtherChar and bag and bag.numSlots then
            numSlots = bag.numSlots
        else
            numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
        end

        if numSlots and numSlots > 0 then
            -- 判断这是否是特殊背包（主银行槽位 -1 始终是普通背包）
            local bagType = nil
            if bagID ~= -1 then
                if not isOtherChar then
                    bagType = addon.Modules.Utils:GetSpecializedBagType(bagID)
                elseif bag and bag.bagType and bag.bagType ~= "regular" then
                    bagType = bag.bagType
                end
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
                    specialBags[bagType] = { total = 0, used = 0, name = BANK_BAG_TYPE_NAMES[bagType] or bagType }
                end
                specialBags[bagType].total = specialBags[bagType].total + numSlots
                specialBags[bagType].used = specialBags[bagType].used + used
            else
                -- 普通背包（包括主银行 -1）
                regularTotal = regularTotal + numSlots
                regularUsed = regularUsed + used
            end
        end
    end

    -- 格式："24 / 80"（已用 / 总数） —— 仅普通背包
    infoText:SetText(string.format("%d / %d", regularUsed, regularTotal))
    infoText:SetTextColor(0.7, 0.7, 0.7)

    -- 为提示存储数据
    local infoFrame = getglobal("Guda_BankFrame_Toolbar_BankSlotsInfo")
    if infoFrame then
        infoFrame.regularTotal = regularTotal
        infoFrame.regularUsed = regularUsed
        infoFrame.specialBags = specialBags

        -- 若尚未设置，则设置提示脚本
        if not infoFrame.tooltipSetup then
            infoFrame:EnableMouse(true)
            infoFrame:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this, "ANCHOR_TOP")
                GameTooltip:AddLine(GudaBag.L["Bank Slots"], 1, 1, 1)
                GameTooltip:AddLine(" ")
                -- 普通背包
                if this.regularTotal then
                    GameTooltip:AddDoubleLine(GudaBag.L["Regular Slots:"], string.format("%d / %d", this.regularUsed, this.regularTotal), 1, 1, 1, 0.8, 0.8, 0.8)
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

-- 更新金钱显示
function BankFrame:UpdateMoney()
    local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
    local moneyFrame = getglobal("Guda_BankFrame_MoneyFrame")

    if hideFooter then
        if moneyFrame then moneyFrame:Hide() end
        return
    end

    if not moneyFrame then
        addon:Debug("Bank MoneyFrame not found! Checking parent...")
        addon:Debug("Guda_BankFrame exists: " .. tostring(getglobal("Guda_BankFrame") ~= nil))

        -- 尝试手动创建它
        self:CreateMoneyFrame()
        moneyFrame = getglobal("Guda_BankFrame_MoneyFrame")
    end

    if moneyFrame then
        MoneyFrame_Update("Guda_BankFrame_MoneyFrame", GetMoney())
        if GudaBag.FormatMoneyFrameWithCommas then GudaBag.FormatMoneyFrameWithCommas("Guda_BankFrame_MoneyFrame") end
        moneyFrame:Show()

        -- 确保提示覆盖层存在
        self:EnsureMoneyTooltipOverlay()
    else
        addon:Debug("Still couldn't find or create Bank MoneyFrame!")
    end
end

-- 如果 MoneyFrame 不存在则创建它
function BankFrame:CreateMoneyFrame()
    local moneyFrame = CreateFrame("Frame", "Guda_BankFrame_MoneyFrame", Guda_BankFrame, "SmallMoneyFrameTemplate")
    moneyFrame:SetPoint("BOTTOMRIGHT", Guda_BankFrame, "BOTTOMRIGHT", -10, 10)
    moneyFrame:SetWidth(180)
    moneyFrame:SetHeight(35)

    -- 设置 OnLoad 处理函数
    GudaBag.BankFrame_MoneyFrame_OnLoad(moneyFrame)

    addon:Debug("Bank MoneyFrame created via CreateMoneyFrame")
end

-- 金钱框架加载时处理函数
function GudaBag.BankFrame_MoneyFrame_OnLoad(self)
    addon:Debug("Bank MoneyFrame OnLoad called for: " .. self:GetName())

    -- 禁用金币按钮的原生点击（打开 CoinPickupFrame 拆分货币）。
    -- SmallMoneyFrameTemplate 自带 OnClick；银行货币是只读显示，
    -- 不设置 CoinPickupFrame.maxMoney，点击会报错。
    -- 银行的货币交互由覆盖层（右键菜单）提供，不依赖原生拆分对话框。
    if GudaBag.DisableMoneyCoinButtons then
        GudaBag.DisableMoneyCoinButtons(self)
    end

    -- 在所有货币面额按钮上设置提示处理函数
    local buttons = {"GoldButton", "SilverButton", "CopperButton"}

    for _, buttonName in ipairs(buttons) do
        local fullName = self:GetName() .. buttonName
        local button = getglobal(fullName)
        if button then
            button:SetScript("OnEnter", function()
                GudaBag.MoneyTooltip_Show(this:GetParent())
            end)
            button:SetScript("OnLeave", function()
                GudaBag.MoneyTooltip_Hide()
            end)
        end
    end

    -- 同时在父框架上设置处理函数
    self:EnableMouse(true)
    self:SetScript("OnEnter", function()
        GudaBag.MoneyTooltip_Show(this)
    end)
    self:SetScript("OnLeave", function()
        GudaBag.MoneyTooltip_Hide()
    end)
end

-- 为金钱提示创建透明覆盖层
function BankFrame:EnsureMoneyTooltipOverlay()
    local overlayName = "Guda_BankFrame_MoneyTooltipOverlay"
    local overlay = getglobal(overlayName)

    if not overlay then
        local moneyFrame = getglobal("Guda_BankFrame_MoneyFrame")
        if not moneyFrame then return end

        -- 创建透明覆盖层框架（高层级以位于金钱按钮之上）
        overlay = CreateFrame("Frame", overlayName, moneyFrame)
        overlay:SetAllPoints(moneyFrame)
        -- 必须与银行框架共享 FULLSCREEN_DIALOG 层级（并且位于
        -- 原生金钱按钮之上），否则点击会穿透到金钱按钮，
        -- 打开原生货币拆分菜单而不是我们的菜单。
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel((moneyFrame:GetFrameLevel() or 0) + 5)
        overlay:EnableMouse(true)

        -- 在覆盖层上设置提示处理函数
        overlay:SetScript("OnEnter", function()
            GudaBag.MoneyTooltip_Show(moneyFrame)
        end)

        overlay:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        overlay:SetScript("OnMouseUp", function()
            if arg1 == "RightButton" then
                GudaBag.MoneyTooltip_Hide()
                GudaBag.ShowGoldTrackingMenu(moneyFrame)
            end
        end)

        addon:Debug("Bank money tooltip overlay created")
    end

    overlay:Show()
end

-- 检查搜索当前是否处于激活状态
function BankFrame:IsSearchActive()
    return searchText and searchText ~= "" and searchText ~= GudaBag.L["Search bank..."]
end

-- 检查物品是否通过搜索过滤（pfUI 风格）
function BankFrame:PassesSearchFilter(itemData)
    if not self:IsSearchActive() then return true end
    return GudaBag.PassesSearchFilter(itemData, searchText)
end

-- 银行搜索文本变化的快速路径（与背包框架相同的 alpha 过滤方法）：
-- 银行布局与搜索字符串无关，因此重新着色已定位的按钮
-- 而不是完整重建。
function BankFrame:ReapplySearchFilter()
    if not Guda_BankFrame or not Guda_BankFrame:IsShown() then return end

    local searchActive = self:IsSearchActive()
    local junkOpacity = 0.6
    if addon.Modules.DB and addon.Modules.DB.GetSetting then
        junkOpacity = addon.Modules.DB:GetSetting("junkOpacity") or 0.6
    end

    for _, bankBagParent in pairs(bankBagParents) do
        if bankBagParent and bankBagParent.itemButtons then
            for button in pairs(bankBagParent.itemButtons) do
                if button and button:IsShown() and button.hasItem then
                    if searchActive then
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

-- 搜索变化处理函数
function GudaBag.BankFrame_OnSearchChanged(self)
    local text = self:GetText()
    -- 忽略占位文本
    if text == GudaBag.L["Search bank..."] then
        text = ""
    end
    if text ~= searchText then
        searchText = text
        -- 快速路径：重新着色现有按钮；布局不受搜索
        -- 字符串影响，因此在这里完整重建是浪费工作。
        if BankFrame.ReapplySearchFilter then
            BankFrame:ReapplySearchFilter()
        else
            BankFrame:Update()
        end
    end
end

-- 清除银行搜索并恢复占位文本
function GudaBag.BankFrame_ClearSearch()
    local searchBox = getglobal("Guda_BankFrame_SearchBar_SearchBox")
    if searchBox then
        searchBox:SetText(GudaBag.L["Search bank..."])
        searchBox:SetTextColor(0.5, 0.5, 0.5, 1)
        if searchBox.ClearFocus then searchBox:ClearFocus() end
    end

    -- 重置搜索状态
    searchText = ""

    -- 更新显示（快速路径重新着色；布局不受清除搜索影响）
    if BankFrame.ReapplySearchFilter then
        BankFrame:ReapplySearchFilter()
    else
        BankFrame:Update()
    end

    -- 如果存在则隐藏点击捕获器
    if bankClickCatcher and bankClickCatcher.Hide then
        bankClickCatcher:Hide()
    end
end

-- 银行按钮处理函数
-- 绑定银行排序按钮：用 Lua SetScript 可靠获取鼠标按键（左键正序、右键倒序），
-- 并覆盖 XML 的 OnClick / OnEnter（增加右键倒序提示）。
local function SetupBankSortButton()
	local sortBtn = getglobal("Guda_BankFrame_SortButton")
	if not sortBtn then return end

	-- WoW 1.12：XML 按钮默认只注册左键，需显式注册右键才能触发 OnClick
	sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	sortBtn:SetScript("OnClick", function()
		-- WoW 1.12：handler 不传参数，鼠标按键在全局 arg1
		GudaBag.BankFrame_Sort(arg1)
	end)

	sortBtn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(sortBtn, "ANCHOR_TOP")
		if sortBtn.isCategoryView then
			GameTooltip:SetText(GudaBag.L["Restack and Clean"])
			GameTooltip:AddLine(GudaBag.L["Merges split stacks and refreshes the view"], 0.7, 0.7, 0.7)
		else
			GameTooltip:SetText(GudaBag.L["Sort Bank"])
			GameTooltip:AddLine(GudaBag.L["Left-click: sort ascending | Right-click: sort descending"], 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
end

function GudaBag.BankFrame_Sort(mouseButton)
	if isReadOnlyMode or currentViewChar then
		addon:Print(GudaBag.L["Cannot sort in read-only mode!"])
		return
	end

	if not addon.Modules.BankScanner:IsBankOpen() then
		addon:Print(GudaBag.L["Bank must be open to sort!"])
		return
	end

	-- 检查是否处于分类视图 —— 重整并清理
	local sortBtn = getglobal("Guda_BankFrame_SortButton")
	if sortBtn and sortBtn.isCategoryView then
		GudaBag.BankFrame_MergeStacks()
		return
	end

	-- 单视图：左键正序、右键倒序（SortEngine 内部使用移植自 OneBag 的排序算法，
	-- 会先弹出确认对话框，且只在源/目标未锁定时移动；被拦截时内部已提示）
	addon.Modules.SortEngine:ExecuteSort(nil, nil, nil, "bank", mouseButton)
end

-- 重整并清理（用于分类视图）—— 合并堆叠并刷新视图
-- 基于队列的方法
function GudaBag.BankFrame_MergeStacks()
	if isReadOnlyMode or currentViewChar then
		addon:Print(GudaBag.L["Cannot restack in read-only mode!"])
		return
	end

	if not addon.Modules.BankScanner:IsBankOpen() then
		addon:Print(GudaBag.L["Bank must be open to restack!"])
		return
	end

	-- 检查排序是否已在进行中
	if addon.Modules.SortEngine.sortingInProgress then
		addon:Print(GudaBag.L["Sorting already in progress, please wait..."])
		return
	end

	local bagIDs = addon.Constants.BANK_BAGS
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
		-- 没有需要合并的堆叠，只做一次干净的刷新
		BankFrame:ClearRecentlyEmptiedSlots()
		addon.Modules.BankScanner:InvalidateCache()
		-- 清除物品检测缓存以强制重新扫描提示
		if addon.Modules.ItemDetection and addon.Modules.ItemDetection.ClearCache then
			addon.Modules.ItemDetection:ClearCache()
		end
		BankFrame:Update()
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
			-- 重整后清除所有缓存以获得干净的视图
			BankFrame:ClearRecentlyEmptiedSlots()
			addon.Modules.BankScanner:InvalidateCache()
		-- 清除物品检测缓存以强制重新扫描提示
			if addon.Modules.ItemDetection and addon.Modules.ItemDetection.ClearCache then
				addon.Modules.ItemDetection:ClearCache()
			end
			BankFrame:Update()
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

-- 切换到暴雪银行 UI
function GudaBag.BankFrame_SwitchToBlizzardUI()
    -- 隐藏自定义银行框架
    local customBankFrame = getglobal("Guda_BankFrame")
    if customBankFrame then
        customBankFrame:Hide()
    end

    -- 恢复暴雪银行框架（重新安装原生的 OnHide）
    BankFrame:ShowBlizzardBank()

    -- 如果存在则显示 Guda 按钮
    BankFrame:ShowGudaButton()
end

-- 从暴雪银行 UI 切换回 Guda UI
function GudaBag.BankFrame_SwitchToGudaUI()
    -- 隐藏暴雪银行框架（OnHide 已被中和，因此会话保持打开）
    BankFrame:HideBlizzardBank()
    
    -- 隐藏 Guda 按钮
    local gudaButton = getglobal("BankFrame_GudaButton")
    if gudaButton then
        gudaButton:Hide()
    end

    -- 显示自定义银行框架
    local customBankFrame = getglobal("Guda_BankFrame")
    if customBankFrame then
        customBankFrame:Show()
    end

    -- 在交互模式下更新自定义银行框架
    BankFrame:ShowCurrentCharacter()
    
    addon:Print(GudaBag.L["Switched to Guda bank UI"])
end

-- 在暴雪 BankFrame 上创建切换到 Guda UI 的按钮
function BankFrame:CreateGudaButtonOnBlizzardUI()
    local blizzardBankFrame = getglobal("BankFrame")
    if not blizzardBankFrame then return end

    -- 检查按钮是否已存在
    if getglobal("BankFrame_GudaButton") then return end

    -- 在关闭按钮旁边创建按钮
    local gudaButton = CreateFrame("Button", "BankFrame_GudaButton", blizzardBankFrame)
    gudaButton:SetWidth(20)
    gudaButton:SetHeight(20)
    
    -- 定位到关闭按钮旁边（其左侧）
    local closeButton = getglobal("BankFrameCloseButton")
    if closeButton then
        gudaButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
    else
        gudaButton:SetPoint("TOPRIGHT", blizzardBankFrame, "TOPRIGHT", -61, -14)
    end

    -- 创建按钮贴图
    local texture = gudaButton:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(gudaButton)
    texture:SetTexture("Interface\\AddOns\\Guda\\Assets\\Chest")
    texture:SetTexCoord(0, 1, 0, 1)

    -- 创建高亮贴图
    local highlight = gudaButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(gudaButton)
    highlight:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- 设置脚本
    gudaButton:SetScript("OnClick", function()
        GudaBag.BankFrame_SwitchToGudaUI()
    end)

    gudaButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText(GudaBag.L["Use Guda Bank UI"])
        GameTooltip:Show()
    end)

    gudaButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- 初始时隐藏按钮
    gudaButton:Hide()
    
end

-- 在暴雪 UI 上显示 Guda 按钮
function BankFrame:ShowGudaButton()
    local gudaButton = getglobal("BankFrame_GudaButton")
    if gudaButton then
        gudaButton:Show()
    end
end

-- 确保银行背包按钮存在；如果 XML 未创建则创建它们
function BankFrame:EnsureBagButtonsInitialized()
    local toolbar = getglobal("Guda_BankFrame_Toolbar")
    if not toolbar then return end

    local function ensureButton(suffix, bagID)
        local name = "Guda_BankFrame_Toolbar_" .. suffix
        local btn = getglobal(name)
        if not btn then
            btn = CreateFrame("Button", name, toolbar, "ItemButtonTemplate")
            -- 锚点按顺序向左排列；位置与 XML 类似
            if suffix == "BankBagMain" then
                btn:SetWidth(24)
                btn:SetHeight(24)
                btn:SetPoint("LEFT", toolbar, "LEFT", 13, 0)
            else
                -- 确定上一个按钮
                local prev
                if bagID == 5 then prev = getglobal("Guda_BankFrame_Toolbar_BankBagMain")
                else prev = getglobal("Guda_BankFrame_Toolbar_BankBag"..tostring(bagID-1)) end
                btn:SetWidth(24)
                btn:SetHeight(24)
                if prev then
                    btn:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                else
                    btn:SetPoint("LEFT", toolbar, "LEFT", 13, 0)
                end
            end

            -- 像 XML 一样钩住鼠标悬停提示
            btn:SetScript("OnEnter", function()
                GudaBag.BankBagSlot_OnEnter(this, bagID)
                GudaBag.BankFrame_HighlightBagSlots(bagID)
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                GudaBag.BankFrame_ClearHighlightedSlots()
            end)
            -- 处理点击（右键切换可见性）
            if btn.RegisterForClicks then
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
            btn:SetScript("OnClick", function()
                GudaBag.BankBagSlot_OnClick(this, bagID, arg1)
            end)
            
            -- 用左键启用拖拽
            if btn.RegisterForDrag then
                btn:RegisterForDrag("LeftButton")
            end
            btn:SetScript("OnDragStart", function()
                GudaBag.BankBagSlot_OnDragStart(this, bagID)
            end)
            btn:SetScript("OnDragStop", function()
                GudaBag.BankBagSlot_OnDragStop(this, bagID)
            end)
            
            -- 接受拖放以将背包装备到此槽位
            btn:SetScript("OnReceiveDrag", function()
                GudaBag.BankBagSlot_OnReceiveDrag(this, bagID)
            end)
        end

        -- 运行我们的 OnLoad 逻辑（还会注册事件并进行初始更新）
        GudaBag.BankBagSlot_OnLoad(btn, bagID)
        return btn
    end

    -- 主（-1）和 5..10
    ensureButton("BankBagMain", -1)
    for bagID=5,10 do
        ensureButton("BankBag"..tostring(bagID), bagID)
    end
end

-- 辅助函数：将银行 bagID（5..10）映射到 bankButtonID（1..6）和库存槽位 id（香草要求第二个参数 = 1）
function BankFrame:GetBankInvSlotForBagID(bagID)
    if not bagID or bagID == -1 then return nil, nil end
    local bankButtonID = bagID - 4
    -- TurtleWoW（以及你的环境）期望传入 bagID（5..10）且 isBank=1
    local invSlot = BankButtonIDToInvSlotID(bagID, 1)
    return invSlot, bankButtonID
end

-- 根据设置更新边框可见性
function BankFrame:UpdateBorderVisibility()
    if not addon or not addon.Modules or not addon.Modules.DB then return end

    local frame = getglobal("Guda_BankFrame")
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

function BankFrame:UpdateSearchBarVisibility()
    if not addon or not addon.Modules or not addon.Modules.DB then return end

    local searchBar = getglobal("Guda_BankFrame_SearchBar")
    local itemContainer = getglobal("Guda_BankFrame_ItemContainer")
    local toggleBtn = getglobal("Guda_BankFrame_SearchToggleButton")
    if not searchBar or not itemContainer then return end

    local mode = GetSearchBarMode()
    local effectiveShown
    if mode == "shown" then
        effectiveShown = true
    else  -- "hidden" 或 "toggle"：均可通过图标按钮展开
        effectiveShown = self.searchBarExpanded and true or false
    end

    if effectiveShown then
        searchBar:Show()
        -- 将 ItemContainer 锚定到 SearchBar 底部
        itemContainer:ClearAllPoints()
        itemContainer:SetPoint("TOP", searchBar, "BOTTOM", 0, -5)
    else
        searchBar:Hide()
        -- 将 ItemContainer 直接锚定到框架顶部（跳过搜索栏空间）
        itemContainer:ClearAllPoints()
        itemContainer:SetPoint("TOP", "Guda_BankFrame", "TOP", 0, -40)
    end

    if toggleBtn then
        -- "shown" 常显搜索栏无需图标；"hidden"/"toggle" 均显示图标以便随时展开搜索
        if mode == "shown" then toggleBtn:Hide() else toggleBtn:Show() end
    end
end

-- 切换搜索栏的展开状态（"shown" 模式常显，无需切换；"hidden"/"toggle" 可切换）。
function BankFrame:ToggleSearchBar()
    local mode = GetSearchBarMode()
    if mode == "shown" then return end  -- shown 模式常显

    self.searchBarExpanded = not (self.searchBarExpanded and true or false)
    self:UpdateSearchBarVisibility()

    local searchBox = getglobal("Guda_BankFrame_SearchBar_SearchBox")
    if self.searchBarExpanded then
        if searchBox then searchBox:SetFocus() end
    else
        if searchBox then
            searchBox:SetText("")
            searchBox:ClearFocus()
            if GudaBag.BankFrame_OnSearchChanged then
                GudaBag.BankFrame_OnSearchChanged(searchBox)
            end
        end
    end

    if BankFrame.Update then BankFrame:Update() end
end

-- 根据设置更新底部栏可见性
function BankFrame:UpdateFooterVisibility()
    local hideFooter = addon.Modules.DB:GetSetting("hideFooter")
    local toolbar = getglobal("Guda_BankFrame_Toolbar")
    local moneyFrame = getglobal("Guda_BankFrame_MoneyFrame")

    if hideFooter then
        if toolbar then toolbar:Hide() end
        if moneyFrame then moneyFrame:Hide() end
    else
        if toolbar then toolbar:Show() end
        if moneyFrame then moneyFrame:Show() end
        
        -- 触发布局更新以确保它们正确定位
        self:UpdateMoney()
    end
end

-- BankFrame 的原生 OnHide 会调用 CloseBankFrame()，从而结束服务端
-- 银行会话。在 Guda 模式下我们将其中和，使 :Hide() 是安全的。
local bankFrameOriginalOnHide = nil

function BankFrame:HideBlizzardBank()
    local blizzardBankFrame = getglobal("BankFrame")
    if not blizzardBankFrame then return end

    if bankFrameOriginalOnHide == nil then
        bankFrameOriginalOnHide = blizzardBankFrame:GetScript("OnHide") or false
    end
    blizzardBankFrame:SetScript("OnHide", nil)

    -- 通过 HideUIPanel 路由以清理面板栈；否则
    -- Esc/GameMenu 会认为面板仍然打开，从而不显示菜单。
    if blizzardBankFrame:IsShown() then
        HideUIPanel(blizzardBankFrame)
    end
end

function BankFrame:ShowBlizzardBank()
    local blizzardBankFrame = getglobal("BankFrame")
    if not blizzardBankFrame then return end

    if bankFrameOriginalOnHide then
        blizzardBankFrame:SetScript("OnHide", bankFrameOriginalOnHide)
    end
    ShowUIPanel(blizzardBankFrame)
end

-- 初始化
function BankFrame:Initialize()
    self:HideBlizzardBank()
    
    -- 在暴雪 BankFrame 上创建 Guda 按钮
    self:CreateGudaButtonOnBlizzardUI()

    -- 绑定银行排序按钮：用 Lua SetScript 可靠获取鼠标按键（左键正序、右键倒序）
    SetupBankSortButton()

    -- 确保我们的银行背包按钮存在，即使 XML 未能创建它们
    if self.EnsureBagButtonsInitialized then
        self:EnsureBagButtonsInitialized()
    end

    -- 银行打开时更新
    addon.Modules.Events:OnBankOpen(function()
        -- 暴雪的默认处理函数会在 BANKFRAME_OPENED 时 Show() BankFrame；重新隐藏它。
        addon.Modules.BankFrame:HideBlizzardBank()

        -- 延迟显示自定义银行，让 TransmogUI 完成处理（使用池化计时器）
        GudaBag.ScheduleTimer(0.2, function()
            -- 以交互模式显示当前角色的银行
            currentViewChar = nil

            -- 打开 BankFrame 时不要自动隐藏 BagFrame
            -- 用户可能希望两个框架同时可见；布局问题（如果有）
            -- 应通过定位来解决，而非自动隐藏。

            -- 显示并更新自定义银行框架
            local customBankFrame = getglobal("Guda_BankFrame")
            if customBankFrame then
                customBankFrame:Show()
            end

            -- 如果启用了 pfUI，强制禁用其银行（pfUI 使用 pfBank 作为其银行框架）
            if pfUI and pfUI.bag and pfUI.bag.left and pfUI.bag.left.Hide then
                pfUI.bag.left:Hide()
            end

            addon.Modules.BankFrame:EnsureBagButtonsInitialized()
            addon.Modules.BankFrame:Update()
        end)
    end, "BankFrameUI")

    -- 银行关闭时隐藏自定义银行
    addon.Modules.Events:OnBankClose(function()
        local customBankFrame = getglobal("Guda_BankFrame")
        if customBankFrame and customBankFrame:IsShown() and not currentViewChar then
            -- 仅当查看当前角色的银行时才自动关闭（非已保存的银行）
            customBankFrame:Hide()
        end
    end, "BankFrameUI")

    --=====================================================
    -- 高效的 BankFrame 更新限流系统
    -- 使用单个可复用框架和真正的防抖
    --=====================================================
    local bankThrottle = {
        frame = nil,
        pending = false,
        delay = 0.1,
        elapsed = 0,
        minDelay = 0.05,
        maxDelay = 0.3,
    }

    local function GetBankThrottleFrame()
        if not bankThrottle.frame then
            bankThrottle.frame = CreateFrame("Frame", "Guda_BankUpdateThrottle", UIParent)
            bankThrottle.frame:Hide()
            bankThrottle.frame:SetScript("OnUpdate", function()
                bankThrottle.elapsed = bankThrottle.elapsed + arg1
                if bankThrottle.elapsed >= bankThrottle.delay then
                    bankThrottle.frame:Hide()
                    bankThrottle.pending = false
                    bankThrottle.elapsed = 0
                    -- 如果银行打开或我们的框架显示则更新（处理边界情况）
                    local bankOpen = addon.Modules.BankScanner:IsBankOpen()
                    local frameShown = Guda_BankFrame and Guda_BankFrame:IsShown()
                    addon:DebugCategory("Throttle fired: bankOpen=%s, frameShown=%s, viewingCurrent=%s",
                        tostring(bankOpen), tostring(frameShown), tostring(not currentViewChar))
                    if (bankOpen or frameShown) and not currentViewChar then
                        addon:DebugCategory("Throttle: calling BankFrame:Update()")
                        addon.Modules.BankFrame:Update()
                    else
                        addon:DebugCategory("Throttle: skipped Update (conditions not met)")
                    end
                end
            end)
        end
        return bankThrottle.frame
    end

    local function ScheduleBankFrameUpdate(delay)
        -- 如果银行打开或我们的框架显示则允许更新
        local bankOpen = addon.Modules.BankScanner:IsBankOpen()
        local frameShown = Guda_BankFrame and Guda_BankFrame:IsShown()
        if not bankOpen and not frameShown then
            addon:DebugCategory("ScheduleBankFrameUpdate: skipped (bank not open, frame not shown)")
            return
        end
        if currentViewChar then return end

        delay = delay or bankThrottle.minDelay
        if delay < bankThrottle.minDelay then
            delay = bankThrottle.minDelay
        elseif delay > bankThrottle.maxDelay then
            delay = bankThrottle.maxDelay
        end

        -- 排序进行中时使用更长的延迟
        if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then
            delay = bankThrottle.maxDelay
        end

        bankThrottle.delay = delay
        bankThrottle.elapsed = 0  -- 重置计时器（真正的防抖）

        local wasAlreadyPending = bankThrottle.pending
        if not bankThrottle.pending then
            bankThrottle.pending = true
            GetBankThrottleFrame():Show()
        end
        addon:DebugCategory("ScheduleBankFrameUpdate: delay=%s, wasAlreadyPending=%s", tostring(delay), tostring(wasAlreadyPending))
    end

    -- 取消任何待处理的限流更新（对应背包的 CancelPendingUpdate）。
    -- 增量更新成功后调用，保留当前布局与占位符位置，
    -- 使分类视图与背包一致：下次打开/刷新才重排（补位）。
    local function CancelPendingBankUpdate()
        if bankThrottle.frame then
            bankThrottle.frame:Hide()
        end
        bankThrottle.pending = false
        bankThrottle.elapsed = 0
    end

    -- 注意：银行背包（5-10）的 BAG_UPDATE 由下方的 updateFrame 处理，
    -- 它提供增量更新逻辑。这里不需要单独的 OnBagUpdate
    -- 处理函数，否则会导致重复处理。

    -- 物品锁定/解锁时更新（为交易、邮寄等做防抖）
    addon.Modules.Events:Register("ITEM_LOCK_CHANGED", function()
        -- 如果银行打开或我们的框架显示则允许处理
        local bankOpen = addon.Modules.BankScanner:IsBankOpen()
        local frameShown = Guda_BankFrame and Guda_BankFrame:IsShown()
        if not bankOpen and not frameShown then return end
        if currentViewChar then return end
        -- 在分类视图中，仅视觉上更新锁定状态，不触发完整重绘
        local viewType = addon.Modules.DB:GetSetting("bankViewType") or "single"
        if viewType == "category" then
            -- 只更新锁定的视觉状态，不触发完整重绘
            -- （伪空占位符会被完整重绘破坏）
            BankFrame:UpdateLockStates()
            return
        end
        -- 单视图中锁定变化使用稍长的延迟
        ScheduleBankFrameUpdate(0.15)
    end, "BankFrameUI")

    -- 注册银行特定的更新事件，并带增量槽位跟踪
    local updateFrame = CreateFrame("Frame")
    updateFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    updateFrame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
    updateFrame:RegisterEvent("BAG_UPDATE")
    updateFrame:SetScript("OnEvent", function()
        -- 调试：记录此处理函数收到的所有事件
        addon:DebugCategory("BankFrame EVENT: %s arg1=%s", tostring(event), tostring(arg1))

        -- 检查是否应处理银行事件：
        -- 1. 银行正式打开（IsBankOpen），或
        -- 2. 我们的 BankFrame 显示且正在查看当前角色（处理边界情况）
        local bankOpen = addon.Modules.BankScanner:IsBankOpen()
        local frameShown = Guda_BankFrame and Guda_BankFrame:IsShown()
        local viewingCurrent = not currentViewChar

        if not bankOpen and not (frameShown and viewingCurrent) then
            addon:DebugCategory("  -> ignored (bank not open, frame not shown)")
            return
        end
        if currentViewChar then
            addon:DebugCategory("  -> ignored (viewing other character)")
            return
        end

        -- 检查排序是否在进行中 —— 使用带限流的完整重绘
        local isSorting = addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress

        if event == "PLAYERBANKSLOTS_CHANGED" then
            -- arg1 是槽位编号（主银行 1-28），但某些情况下可能为 nil
            local viewType = addon.Modules.DB:GetSetting("bankViewType") or "single"

            if arg1 and type(arg1) == "number" and arg1 >= 1 then
                -- 特定槽位发生变化
                local rawTexture, rawCount = GetContainerItemInfo(-1, arg1)
                local rawLink = GetContainerItemLink(-1, arg1)
                local slotIsNowEmpty = (rawTexture == nil)
                addon:DebugCategory("  PLAYERBANKSLOTS_CHANGED slot=%d, slotIsNowEmpty=%s, isSorting=%s",
                    arg1, tostring(slotIsNowEmpty), tostring(isSorting))

                -- 未在排序时尝试单槽位更新
                if not isSorting then
                    -- 使银行扫描器缓存失效以获取新的槽位数据
                    addon.Modules.BankScanner:InvalidateBag(-1)
                    -- 尝试单槽位更新
                    local success = BankFrame:UpdateSingleSlot(-1, arg1)
                    addon:DebugCategory("  UpdateSingleSlot(-1, %d) = %s", arg1, tostring(success))
                    if success then
                        -- 增量更新成功
                        if slotIsNowEmpty then
                            addon:DebugCategory("  -> slot emptied, incremental update done, no full redraw needed")
                        else
                            addon:DebugCategory("  -> item added, incremental update done")
                        end
                        -- 与背包一致：增量成功即取消待处理的完整重绘，
                        -- 布局保持稳定（空占位符位置不动），下次打开/刷新才重排
                        CancelPendingBankUpdate()
                        return
                    end
                end

                -- 回退：需要完整重绘
                -- 但如果槽位刚变空且没有按钮，在分类视图中这没问题
                if slotIsNowEmpty and viewType == "category" then
                    addon:DebugCategory("  -> slot emptied in Category View, no button exists, updating cache only")
                    addon.Modules.BankScanner:InvalidateBag(-1)
                    return
                end

                addon:DebugCategory("  -> falling through to full redraw")
                addon.Modules.BankScanner:InvalidateBag(-1)
            else
                -- arg1 为 nil —— 通用银行变化通知
                -- 在分类视图中，检查物品是否被移除（无需完整重绘）
                addon:DebugCategory("  PLAYERBANKSLOTS_CHANGED arg1=nil (generic)")

                if viewType == "category" then
                    -- 首先，统计当前 API 状态下的物品数（这是"之后"的计数）
                    local realItems = 0
                    local numSlots = GetContainerNumSlots(-1) or 0
                    for slot = 1, numSlots do
                        local texture = GetContainerItemInfo(-1, slot)
                        if texture then realItems = realItems + 1 end
                    end

                    -- 获取更新前缓存的计数（这是"之前"的计数）
                    -- 使用 GetCachedItemCount 以避免触发不匹配检测
                    local cacheItems = addon.Modules.BankScanner:GetCachedItemCount(-1)

                    addon:DebugCategory("  -> comparing cache=%d vs API=%d", cacheItems, realItems)

                    if realItems < cacheItems then
                        -- 物品被移除 —— 显示空占位符，不完整重绘
                        addon:DebugCategory("  -> items removed (%d -> %d), showing empty placeholders", cacheItems, realItems)

                        -- 找出变空的槽位并更新它们以显示空占位符
                        if bankSlotToButton[-1] then
                            for slotID, button in pairs(bankSlotToButton[-1]) do
                                local buttonHadItem = button.itemData and button.itemData.link
                                local currentTexture = GetContainerItemInfo(-1, slotID)

                                -- 如果按钮原本有物品但 API 中没有，则此槽位被清空
                                if buttonHadItem and not currentTexture then
                                    addon:DebugCategory("  -> slot %d emptied, showing empty placeholder", slotID)
                                    -- 标记为空占位符，使其保持可见
                                    button.inUse = true
                                    button.isEmptyPlaceholder = true
            -- 同时标记到 recentlyEmptiedSlots 以支持完整重绘
                                    local oldItemData = button.itemData
                                    local oldCategory = "Miscellaneous"
                                    if oldItemData and oldItemData.link then
                                        oldCategory = addon.Modules.CategoryManager:CategorizeItem(oldItemData, -1, slotID) or "Miscellaneous"
                                    end
                                    self:MarkSlotAsEmptied(-1, slotID, oldCategory, oldItemData)
                                    -- 更新按钮以显示空状态
                                    local matchesFilter = self:PassesSearchFilter(nil)
                                    GudaBag.ItemButton_SetItem(button, -1, slotID, nil, true, nil, matchesFilter, isReadOnlyMode)
                                    -- 清除 itemData，使后续事件知道此槽位为空
                                    button.itemData = nil
                                    -- 确保它保持可见
                                    button:Show()
                                end
                            end
                        end

                        -- 不要在此处使缓存失效 —— 我们已经处理了视觉更新
                        -- 失效会使缓存=0，导致下一次事件认为物品被添加了
                        -- 缓存会在下次完整重绘时更新（如果需要）
                        return
                    elseif realItems == cacheItems then
                        -- 物品数量无变化 —— 可能是物品交换或过期数据。
                        -- 与背包一致：不做安全网重绘，保持增量视图与布局稳定
                        -- （空占位符位置不动，下次打开/刷新才重排）
                        addon:DebugCategory("  -> item count unchanged (%d), keeping incremental view", realItems)
                        CancelPendingBankUpdate()
                        return
                    end
                    -- 物品被添加 —— 需要完整重绘
                    addon:DebugCategory("  -> items added (%d -> %d), need full redraw", cacheItems, realItems)
                end

                addon.Modules.BankScanner:InvalidateBag(-1)
            end
        elseif event == "BAG_UPDATE" and arg1 then
            -- 检查这是否是银行背包（5-10）
            if arg1 >= 5 and arg1 <= 10 then
                -- 调试：通过原始 API 统计此银行背包中的物品数
                local rawItemCount = 0
                local numSlots = GetContainerNumSlots(arg1) or 0
                for slot = 1, numSlots do
                    local texture = GetContainerItemInfo(arg1, slot)
                    if texture then rawItemCount = rawItemCount + 1 end
                end
                addon:DebugCategory("EVENT: BAG_UPDATE bankBag=%d, rawItems=%d, numSlots=%d, isSorting=%s",
                    arg1, rawItemCount, numSlots, tostring(isSorting))
                -- 使银行扫描器缓存失效以获取新的槽位数据
                -- 注意：不要清除 ItemDetection 缓存 —— 物品属性不会因移动而改变
                addon.Modules.BankScanner:InvalidateBag(arg1)

                -- 未在排序时尝试增量更新
                if not isSorting then
                    -- 尝试只更新发生变化的槽位
                    local result = BankFrame:UpdateChangedSlots(arg1)
                    addon:DebugCategory("  UpdateChangedSlots(%d) = %d", arg1, result)
                    if result >= 0 then
                        -- 增量更新成功 —— 此背包无需完整重绘。
                        -- 与背包一致：取消待处理的完整重绘以保留增量更新，
                        -- 布局保持稳定（空占位符位置不动），下次打开/刷新才重排
                        CancelPendingBankUpdate()
                        return
                    end
                    -- 回退到完整重绘
                end
                addon:DebugCategory("  -> falling through to full redraw")
            else
                -- 不是银行背包，银行框架忽略
                return
            end
        elseif event == "PLAYERBANKBAGSLOTS_CHANGED" then
            -- 银行容器槽位发生变化（背包被添加/移除）
            -- 由于结构变化，清除银行扫描器缓存
            -- 注意：不要清除 ItemDetection 缓存 —— 物品属性不会变化
            addon.Modules.BankScanner:ClearCache()
        end

        -- 更长的延迟，确保物品移动后 WoW API 已完全更新
        ScheduleBankFrameUpdate(0.2)
    end)

end

-- 银行背包槽位按钮处理函数

-- 银行背包槽位按钮的加载时处理函数
function GudaBag.BankBagSlot_OnLoad(button, bagID)
    -- 配置边框和图标内缩，使其与主银行背包外观一致
    local buttonName = button:GetName()

    -- 确保普通纹理（边框）可见，并使用默认的快捷栏边框
    local normalTexture = getglobal(buttonName .. "NormalTexture")
    if normalTexture then
        normalTexture:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        normalTexture:ClearAllPoints()
        normalTexture:SetPoint("CENTER", button, "CENTER", 0, -1)
        normalTexture:SetWidth(35)
        normalTexture:SetHeight(35)
        normalTexture:Show()
    end

    -- 如果模板有 IconBorder，也显示它（某些客户端/模板提供此功能）
    local iconBorder = getglobal(buttonName .. "IconBorder")
    if iconBorder then
        iconBorder:Show()
    end

    -- 稍微内缩图标，使已装备的背包图标看起来更小一些（匹配主背包的感觉）
    local icon = getglobal(buttonName .. "IconTexture") or getglobal(buttonName .. "Icon")
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- 将其标记为背包槽位按钮，而非物品按钮
    button.isBagSlot = true
    button.hasItem = nil

    -- 用正确的 ID 设置按钮
    button.bagID = bagID

    -- 设置库存槽位 ID，使按钮知道它代表哪个槽位
    if bagID ~= -1 then
        local invSlot = addon.Modules.BankFrame:GetBankInvSlotForBagID(bagID)
        if invSlot then
            button:SetID(invSlot)
        end
    end

    -- 注册更新事件
    button:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
    button:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    button:RegisterEvent("ITEM_LOCK_CHANGED")
    button:RegisterEvent("PLAYER_MONEY")
    button:RegisterEvent("CURSOR_UPDATE")
    button:RegisterEvent("UNIT_INVENTORY_CHANGED")
    button:SetScript("OnEvent", function()
        GudaBag.BankBagSlot_Update(this, this.bagID)
    end)

    -- 确保我们对右键隐藏/显示做出响应
    if button.RegisterForClicks then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    button:SetScript("OnClick", function()
        GudaBag.BankBagSlot_OnClick(this, this.bagID, arg1)
    end)

    -- 用左键启用拖拽
    if button.RegisterForDrag then
        button:RegisterForDrag("LeftButton")
    end
    button:SetScript("OnDragStart", function()
        GudaBag.BankBagSlot_OnDragStart(this, this.bagID)
    end)
    button:SetScript("OnDragStop", function()
        GudaBag.BankBagSlot_OnDragStop(this, this.bagID)
    end)

    -- 接受拖放以将背包装备到此槽位
    button:SetScript("OnReceiveDrag", function()
        GudaBag.BankBagSlot_OnReceiveDrag(this, this.bagID)
    end)

    -- 初始更新
    GudaBag.BankBagSlot_Update(button, bagID)
end

-- 更新银行背包槽位按钮贴图
function GudaBag.BankBagSlot_Update(button, bagID)
    local isHidden = hiddenBankBags[bagID]

    if bagID == -1 then
        -- 主银行背包 —— 使用银行图标
        SetItemButtonTexture(button, "Interface\\AddOns\\Guda\\Assets\\bags")
        -- 隐藏时变暗
        if isHidden then
            SetItemButtonTextureVertexColor(button, 0.4, 0.4, 0.4)
        else
            SetItemButtonTextureVertexColor(button, 1.0, 1.0, 1.0)
        end
        button:Show()
        return
    end

    -- 银行背包槽位 5-10 对应银行按钮 1-6
    local bankButtonID = bagID - 4
    -- 集中式映射到库存槽位（TurtleWoW：传入 bagID；辅助函数也会返回 bankButtonID）
    local invSlot = BankFrame:GetBankInvSlotForBagID(bagID)

    -- 检查此槽位是否已购买
    local numSlots = GetNumBankSlots()
    local isPurchased = (bankButtonID <= numSlots)

    -- 直接从库存获取背包贴图（在 1.12 上更可靠）
    local texture = invSlot and GetInventoryItemTexture("player", invSlot) or nil


    if texture then
        -- 此槽位已装备背包且我们有贴图
        SetItemButtonTexture(button, texture)
        -- 隐藏时变暗
        if isHidden then
            SetItemButtonTextureVertexColor(button, 0.4, 0.4, 0.4)
        else
            SetItemButtonTextureVertexColor(button, 1.0, 1.0, 1.0)
        end

        -- 设置贴图坐标以裁剪图标（1.12 使用 IconTexture）
        local icon = getglobal(button:GetName() .. "IconTexture") or getglobal(button:GetName() .. "Icon")
        if icon then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        button:Show()
    elseif isPurchased then
        -- 槽位已购买但没有装备背包
        SetItemButtonTexture(button, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
        SetItemButtonTextureVertexColor(button, 1.0, 1.0, 1.0)
        button:Show()
    else
        -- 槽位未购买 —— 显示锁定的/灰色的占位符
        SetItemButtonTexture(button, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
        SetItemButtonTextureVertexColor(button, 0.5, 0.5, 0.5)
        button:Show()
    end
end

-- 银行背包槽位的点击处理函数
function GudaBag.BankBagSlot_OnClick(button, bagID, which)
    local which = which or arg1 -- 香草使用全局 arg1 表示鼠标按钮名称

    -- 处理主银行容器（bagID -1）
    if bagID == -1 then
        if which == "RightButton" then
            -- 切换主银行容器的可见性
            hiddenBankBags[bagID] = not hiddenBankBags[bagID]
            GudaBag.BankBagSlot_Update(button, bagID)
            BankFrame:Update()
        end
        return
    end

    if bagID and bagID ~= -1 then
        local invSlot, bankButtonID = BankFrame:GetBankInvSlotForBagID(bagID)
        if invSlot and bankButtonID then
            local numSlots = GetNumBankSlots()
            local isPurchased = (bankButtonID <= numSlots)
            local hasCursorItem = CursorHasItem()

            -- 处理未购买的槽位：左右键点击都显示购买对话框
            if not isPurchased then
                if not hasCursorItem then
                    -- 左右键点击都显示购买对话框
                    local cost = GetBankSlotCost(numSlots)
                    local gudaBankFrame = getglobal("Guda_BankFrame")
                    if gudaBankFrame then
                        gudaBankFrame.nextSlotCost = cost
                    end
                    StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
                end
                return
            end

            -- 处理已购买的槽位
            if which == "RightButton" then
                -- 切换已购买槽位的可见性
                hiddenBankBags[bagID] = not hiddenBankBags[bagID]
                GudaBag.BankBagSlot_Update(button, bagID)
                BankFrame:Update()
                return
            end

            if which == "LeftButton" then
                if hasCursorItem then
                    -- 将光标上的背包装备到此已购买的银行背包槽位
                    EquipCursorItem(invSlot)
                    GudaBag.BankBagSlot_Update(button, bagID)
                    BankFrame:Update()
                end
                return
            end
        end
    end
end

-- 提示框的进入处理函数
function GudaBag.BankBagSlot_OnEnter(button, bagID)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")

    if bagID == -1 then
        -- 主银行背包提示
        GameTooltip:SetText(GudaBag.L["Bank"], 1.0, 1.0, 1.0)
        local numSlots = 24
        GameTooltip:AddLine(string.format(GudaBag.L["%d Slots"], numSlots), 0.8, 0.8, 0.8)
        if hiddenBankBags[bagID] then
            GameTooltip:AddLine("(Hidden - Right-Click to show)", 0.8, 0.5, 0.5)
        else
            GameTooltip:AddLine(GudaBag.L["(Right-Click to hide)"], 0.5, 0.8, 0.5)
        end
    else
        local invSlot, bankButtonID = BankFrame:GetBankInvSlotForBagID(bagID)
        local numSlots = GetNumBankSlots()
        local isPurchased = (bankButtonID and bankButtonID <= numSlots)
        local hasItem = invSlot and GetInventoryItemTexture("player", invSlot)

        if hasItem then
            -- 显示背包物品提示（带隐藏/显示文本）
            GameTooltip:SetInventoryItem("player", invSlot)
            if hiddenBankBags[bagID] then
                GameTooltip:AddLine("(Hidden - Right-Click to show)", 0.8, 0.5, 0.5)
            else
                GameTooltip:AddLine(GudaBag.L["(Right-Click to hide)"], 0.5, 0.8, 0.5)
            end
            -- 有物品的已购买槽位重置光标
            ResetCursor()
        elseif isPurchased then
            -- 空的已购买槽位（无隐藏/显示文本，无购买光标）
            GameTooltip:SetText(string.format(GudaBag.L["Bank Bag Slot %d"], bankButtonID or -1), 1.0, 1.0, 1.0)
            GameTooltip:AddLine(GudaBag.L["Empty"], 0.8, 0.8, 0.8)
            -- 空的已购买槽位重置光标
            ResetCursor()
        else
            -- 未购买的槽位（无隐藏/显示文本，显示购买光标）
            GameTooltip:SetText(string.format(GudaBag.L["Bank Bag Slot %d"], bankButtonID or -1), 1.0, 1.0, 1.0)
            local cost = GetBankSlotCost(numSlots)
            GameTooltip:AddLine(addon.Modules.Utils:FormatMoney(cost, false, true), 1, 1, 1)
            -- 显示购买光标（硬币图标）
            SetCursor("BUY_CURSOR")
        end
    end

    GameTooltip:Show()
end

-- 通过调暗其他槽位来高亮属于特定银行背包的所有物品槽位
function GudaBag.BankFrame_HighlightBagSlots(bagID)
    -- 使用 itemButtons 跟踪而非 GetChildren 以避免分配
    local highlightCount, dimCount = 0, 0

    for _, bankBagParent in pairs(bankBagParents) do
        if bankBagParent and bankBagParent.itemButtons then
            for button in pairs(bankBagParent.itemButtons) do
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

    if addon and addon.Debug then
        addon:Debug(string.format("BankFrame HighlightBagSlots: Highlighted %d slots, dimmed %d slots for bagID %d", highlightCount, dimCount, bagID))
    end
end

-- 将所有槽位恢复为完整不透明度以清除全部高亮
function GudaBag.BankFrame_ClearHighlightedSlots()
    -- 将 alpha 恢复为搜索过滤器规定的值（pfUI 风格）。若无搜索则为完整不透明度。
    local searchActive = BankFrame and BankFrame.IsSearchActive and BankFrame:IsSearchActive()

    -- 使用 itemButtons 跟踪而非 GetChildren 以避免分配
    for _, bankBagParent in pairs(bankBagParents) do
        if bankBagParent and bankBagParent.itemButtons then
            for button in pairs(bankBagParent.itemButtons) do
                if button and button:IsShown() and button.hasItem ~= nil and not button.isBagSlot then
                    if searchActive and BankFrame and BankFrame.PassesSearchFilter then
                        local matches = BankFrame:PassesSearchFilter(button.itemData)
                        button:SetAlpha(matches and 1.0 or 0.25)
                    else
                        button:SetAlpha(1.0)
                    end
                end
            end
        end
    end
end

-- 高亮工具栏中的特定银行背包按钮
function GudaBag.BankFrame_HighlightBagButton(bagID)
    if not bagID then return end

    local buttonName
    if bagID == -1 then
        -- 主银行容器
        buttonName = "Guda_BankFrame_Toolbar_BankBagMain"
    else
        -- 银行背包的 bagID 为 5-10
        buttonName = "Guda_BankFrame_Toolbar_BankBag" .. bagID
    end

    local button = getglobal(buttonName)
    if button then
        button:LockHighlight()
    end
end

-- 清除银行背包按钮高亮
function GudaBag.BankFrame_ClearBagButtonHighlight()
    -- 清除主银行按钮的高亮
    local mainButton = getglobal("Guda_BankFrame_Toolbar_BankBagMain")
    if mainButton then
        mainButton:UnlockHighlight()
    end

    -- 清除银行背包按钮（5-10）的高亮
    for bagID = 5, 10 do
        local buttonName = "Guda_BankFrame_Toolbar_BankBag" .. bagID
        local button = getglobal(buttonName)
        if button then
            button:UnlockHighlight()
        end
    end
end

-- 银行角色下拉菜单（与 BagFrame 的银行下拉菜单类似）
local function BankCharacterMenu_Initialize()
    local DB = addon.Modules.DB
    local currentPlayerFullName = DB:GetPlayerFullName()
    local currentViewChar = addon.Modules.BankFrame:GetCurrentViewChar()
    local characters = DB:GetAllCharacters(false, true)

    -- 分为自己的和共享的
    local own, shared = {}, {}
    for _, char in ipairs(characters) do
        if not DB:IsGoldBlacklisted(char.fullName) or char.fullName == currentPlayerFullName then
            if char.isShared then
                table.insert(shared, char)
            else
                table.insert(own, char)
            end
        end
    end

    for _, char in ipairs(own) do
        local charFullName = char.fullName
        local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
        local r, g, b = 1, 1, 1
        if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

        local info = {}
        info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
        info.func = function()
            if charFullName == currentPlayerFullName then
                addon.Modules.BankFrame:ShowCurrentCharacter()
            else
                addon.Modules.BankFrame:ShowCharacter(charFullName)
            end
        end
        info.checked = (currentViewChar == charFullName or (not currentViewChar and charFullName == currentPlayerFullName))
        UIDropDownMenu_AddButton(info)
    end

    if table.getn(shared) > 0 then
        local sep = {}
        sep.text = GudaBag.L["Other Accounts"]
        sep.isTitle = 1
        sep.notCheckable = 1
        UIDropDownMenu_AddButton(sep)

        for _, char in ipairs(shared) do
            local charFullName = char.fullName
            local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
            local r, g, b = 1, 1, 1
            if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

            local info = {}
            info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
            info.func = function()
                addon.Modules.BankFrame:ShowCharacter(charFullName)
            end
            info.checked = (currentViewChar == charFullName)
            UIDropDownMenu_AddButton(info)
        end
    end
end

function GudaBag.BankFrame_ToggleBankDropdown(button)
    local menuFrame = getglobal("Guda_BankCharacterMenu")
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "Guda_BankCharacterMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(menuFrame, BankCharacterMenu_Initialize, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

-- 银行背包槽位的拖拽处理函数
function GudaBag.BankBagSlot_OnDragStart(button, bagID)
    if not bagID or bagID == -1 then return end
    if not addon.Modules.BankScanner:IsBankOpen() then return end

    local invSlot = addon.Modules.BankFrame:GetBankInvSlotForBagID(bagID)
    if not invSlot then return end

    local texture = GetInventoryItemTexture("player", invSlot)
    if texture then
        button:SetAlpha(0.6)
        PickupInventoryItem(invSlot)
        -- 立即刷新外观以反映槽位现在位于光标上
        GudaBag.BankBagSlot_Update(button, bagID)
        if BankFrame and BankFrame.Update then BankFrame:Update() end
    end
end

function GudaBag.BankBagSlot_OnDragStop(button, bagID)
    button:SetAlpha(1.0)
end

function GudaBag.BankBagSlot_OnReceiveDrag(button, bagID)
    if not bagID or bagID == -1 then return end
    if not CursorHasItem or not CursorHasItem() then return end
    if not addon.Modules.BankScanner:IsBankOpen() then return end

    local invSlot, bankButtonID = addon.Modules.BankFrame:GetBankInvSlotForBagID(bagID)
    if not invSlot then return end

    local purchased = (bankButtonID and bankButtonID <= GetNumBankSlots())
    if not purchased then return end

    -- 如果目标银行背包有物品，交换前先清空它们
    local numSlots = GetContainerNumSlots(bagID)
    local hasItems = false
    if numSlots and numSlots > 0 then
        for slot = 1, numSlots do
            if GetContainerItemInfo(bagID, slot) then hasItems = true; break end
        end
    end

    if hasItems and addon.Modules.BagReplacer then
        addon.Modules.BagReplacer:Execute(bagID, invSlot, true)
        return -- BagReplacer 自行处理 UI 更新
    end

    if EquipCursorItem then
        EquipCursorItem(invSlot)
    elseif PutItemInBag then
        PutItemInBag(invSlot)
    end

    GudaBag.BankBagSlot_Update(button, bagID)
    if BankFrame and BankFrame.Update then BankFrame:Update() end
end
