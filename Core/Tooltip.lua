-- Guda 提示框模块 - 兼容 Lua 5.0
local addon = Guda

local Tooltip = {}
addon.Modules.Tooltip = Tooltip

-- GameTooltip 默认就处于 TOOLTIP 层（游戏中最高层，高于 guda 窗口所在的
-- HIGH / FULLSCREEN_DIALOG 层），因此无需手动提升框架层级。之前把
-- GameTooltip 提到 frame level 1000 会破坏暴雪动态创建的售价 MoneyFrame
-- 的相对层级，导致售价被压到背景之下显示为灰色。这里只锁定层到 TOOLTIP，
-- 不再改动 frame level，让售价等子框架按原生逻辑正常渲染。
-- 同时，钩住 Show 重新断言 Guda 物品按钮的锚点：某些插件（如装等/物品ID
-- 插件，/itemid show）会在填充或显示提示时重新锚定 GameTooltip 到屏幕角落，
-- 导致背包物品提示固定显示在右下角。
if GameTooltip then
    if not GameTooltip.GudaStrataLocked then
        local origShow = GameTooltip.Show
        GameTooltip.Show = function(self, ...)
            if self.SetFrameStrata then
                self:SetFrameStrata("TOOLTIP")
            end
            local ret = origShow(self, unpack(arg))
            -- Guda 物品按钮悬停：重新断言锚点，覆盖其他插件在 Show 钩子
            -- 或内容填充阶段对 GameTooltip 做的重新锚定。
            if self.GudaAnchorButton and not self.GudaCursorMode and self.GudaAnchorButton:IsShown() then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", self.GudaAnchorButton, "TOPLEFT", 10, 0)
            end
            return ret
        end
        GameTooltip.GudaStrataLocked = true
    end
end

-- 可复用的表，避免每次悬停产生垃圾数据（每次使用前清空）
local _characterCounts = {}
local _breakdownParts = {}
local _charParts = {}

--=============================================================================
-- 物品计数辅助函数（为清晰和复用而抽取）
--=============================================================================

-- 从链接中获取物品 ID 的辅助函数（兼容 Lua 5.0）
local function GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local _, _, itemID = string.find(link, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- 在已保存的背包/银行数据结构中计数物品
-- 用于从已保存的角色数据中统计背包和银行数量
local function CountFromSavedContainers(containersData, itemID)
    local count = 0
    if not containersData or type(containersData) ~= "table" then
        return count
    end

    for bagID, bagData in pairs(containersData) do
        if bagData and type(bagData) == "table" and bagData.slots and type(bagData.slots) == "table" then
            for slotID, itemData in pairs(bagData.slots) do
                if itemData and type(itemData) == "table" and itemData.link then
                    local slotItemID = GetItemIDFromLink(itemData.link)
                    if slotItemID == itemID then
                        count = count + (itemData.count or 1)
                    end
                end
            end
        end
    end

    return count
end

-- 在已保存的邮箱数据结构中计数物品
local function CountFromSavedMailbox(mailboxData, itemID)
    local count = 0
    if not mailboxData or type(mailboxData) ~= "table" then
        return count
    end

    for _, mail in ipairs(mailboxData) do
        local itemsToCheck = mail.items or (mail.item and {mail.item}) or {}
        for _, item in ipairs(itemsToCheck) do
            local slotItemID = item.link and GetItemIDFromLink(item.link)
            if slotItemID == itemID then
                count = count + (item.count or 1)
            elseif not slotItemID and item.name then
                -- 链接缺失时回退到名称匹配
                local targetName = GetItemInfo("item:" .. itemID .. ":0:0:0")
                if targetName == item.name then
                    count = count + (item.count or 1)
                end
            end
        end
    end

    return count
end

-- 在已保存的已装备数据结构中计数物品
local function CountFromSavedEquipped(equippedData, itemID)
    local count = 0
    if not equippedData or type(equippedData) ~= "table" then
        return count
    end

    for slotName, itemData in pairs(equippedData) do
        if itemData and type(itemData) == "table" and itemData.link then
            local slotItemID = GetItemIDFromLink(itemData.link)
            if slotItemID == itemID then
                count = count + 1
            end
        end
    end

    return count
end

-- 在实时容器（背包或银行）中计数物品
local function CountFromLiveContainer(bagIDs, itemID)
    local count = 0

    for _, bagID in ipairs(bagIDs) do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bagID, slot)
                if link then
                    local slotItemID = GetItemIDFromLink(link)
                    if slotItemID == itemID then
                        local _, itemCount = GetContainerItemInfo(bagID, slot)
                        count = count + (itemCount or 1)
                    end
                end
            end
        end
    end

    return count
end

-- 在实时邮箱中计数物品
local function CountFromLiveMailbox(itemID)
    local count = 0

    if not (addon.Modules.MailboxScanner and addon.Modules.MailboxScanner:IsMailboxOpen()) then
        return count
    end

    local numInboxItems = GetInboxNumItems()
    for i = 1, numInboxItems do
        local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(i)
        if hasItem then
            local numAttachments = GetInboxNumAttachments and GetInboxNumAttachments(i) or 1
            if numAttachments == 0 and hasItem then
                numAttachments = 1
            end

            for j = 1, numAttachments do
                local name, _, itemCount = GetInboxItem(i, j)
                if name then
                    local itemLink = addon.Modules.Utils:GetInboxItemLink(i, j)
                    if itemLink then
                        local slotItemID = GetItemIDFromLink(itemLink)
                        if slotItemID == itemID then
                            count = count + (itemCount or 1)
                        end
                    end
                end
            end
        end
    end

    return count
end

-- 在实时装备栏位中计数物品
local function CountFromLiveEquipped(itemID)
    local count = 0

    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local slotItemID = GetItemIDFromLink(link)
            if slotItemID == itemID then
                count = count + 1
            end
        end
    end

    return count
end

--=============================================================================
-- 主要计数函数
--=============================================================================

-- 使用实时游戏数据统计当前角色的物品
local function CountCurrentCharacterItems(itemID)
    local bagCount = 0
    local bankCount = 0
    local mailCount = 0
    local equippedCount = 0

    -- 实时统计背包
    bagCount = CountFromLiveContainer({0, 1, 2, 3, 4, -2}, itemID)

    -- 统计银行：打开时实时统计，否则使用已保存数据
    local bankFrame = getglobal("BankFrame")
    if bankFrame and bankFrame:IsVisible() then
        -- 主银行 + 银行背包
        bankCount = CountFromLiveContainer({-1, 5, 6, 7, 8, 9, 10, 11}, itemID)
    else
        -- 使用已保存数据
        local playerName = addon.Modules.DB:GetPlayerFullName()
        local charData = Guda_DB and Guda_DB.characters and Guda_DB.characters[playerName]
        if charData then
            bankCount = CountFromSavedContainers(charData.bank, itemID)
        end
    end

    -- 统计邮箱：打开时实时统计，否则使用已保存数据
    if addon.Modules.MailboxScanner and addon.Modules.MailboxScanner:IsMailboxOpen() then
        mailCount = CountFromLiveMailbox(itemID)
    else
        local playerName = addon.Modules.DB:GetPlayerFullName()
        local charData = Guda_DB and Guda_DB.characters and Guda_DB.characters[playerName]
        if charData then
            mailCount = CountFromSavedMailbox(charData.mailbox, itemID)
        end
    end

    -- 实时统计已装备物品
    equippedCount = CountFromLiveEquipped(itemID)

    return bagCount, bankCount, equippedCount, mailCount
end

-- 统计特定角色（当前或其它）的物品
local function CountItemsForCharacter(itemID, characterData, isCurrentChar)
    -- 对于当前角色，使用实时计数
    if isCurrentChar then
        return CountCurrentCharacterItems(itemID)
    end

    -- 对于其它角色，使用已保存数据
    local bagCount = CountFromSavedContainers(characterData.bags, itemID)
    local bankCount = CountFromSavedContainers(characterData.bank, itemID)
    local mailCount = CountFromSavedMailbox(characterData.mailbox, itemID)
    local equippedCount = CountFromSavedEquipped(characterData.equipped, itemID)

    return bagCount, bankCount, equippedCount, mailCount
end


-- 获取职业颜色
local function GetClassColor(classToken)
	if not classToken then return 1.0, 1.0, 1.0 end
	local color = RAID_CLASS_COLORS[classToken]
	if color then return color.r, color.g, color.b end
	return 1.0, 1.0, 1.0
end

function Tooltip:AddInventoryInfo(tooltip, link)
-- 检查设置是否启用
	if not addon.Modules.DB:GetSetting("showTooltipCounts") then
		return
	end

-- 检查数据库是否正确初始化并具有预期的结构
	if not Guda_DB or type(Guda_DB) ~= "table" then
		return
	end

	-- 安全地检查 characters - 在早期初始化期间它可能是 nil 或字符串
	if not Guda_DB.characters or type(Guda_DB.characters) ~= "table" then
	-- 如果 characters 是字符串或 nil，直接静默返回
		return
	end

	local itemID = GetItemIDFromLink(link)
	if not itemID then
		return
	end

	local totalBags = 0
	local totalBank = 0
	local totalMail = 0
	local totalEquipped = 0
	local hasAnyItems = false

	-- 复用模块级表（使用前清空，避免每次调用分配内存）
	local characterCounts = _characterCounts
	for k in pairs(characterCounts) do characterCounts[k] = nil end
	local ccIndex = 0

	local currentPlayerName = addon.Modules.DB:GetPlayerFullName()
	local currentRealm = GetRealmName()

	-- 只统计当前服务器上的角色的物品
	local sources = { { data = Guda_DB.characters, shared = false } }
	if addon.sharedCharacters then
		table.insert(sources, { data = addon.sharedCharacters, shared = true })
	end

	for _, source in ipairs(sources) do
		for charName, charData in pairs(source.data) do
			if type(charData) == "table" and charData.realm == currentRealm and not addon.Modules.DB:IsGoldBlacklisted(charName) then
				local isCurrentChar = (charName == currentPlayerName)
				local bagCount, bankCount, equippedCount, mailCount = CountItemsForCharacter(itemID, charData, isCurrentChar)

				if bagCount > 0 or bankCount > 0 or equippedCount > 0 or mailCount > 0 then
					hasAnyItems = true
					totalBags = totalBags + bagCount
					totalBank = totalBank + bankCount
					totalMail = totalMail + mailCount
					totalEquipped = totalEquipped + equippedCount
					ccIndex = ccIndex + 1
					if not characterCounts[ccIndex] then
						characterCounts[ccIndex] = {}
					end
					local entry = characterCounts[ccIndex]
					entry.name = charData.name or charName
					entry.classToken = charData.classToken
					entry.bagCount = bagCount
					entry.bankCount = bankCount
					entry.mailCount = mailCount
					entry.equippedCount = equippedCount
					entry.isCurrent = isCurrentChar
					entry.isShared = source.shared
				end
			end
		end
	end
	-- 清理超出当前数量的过时条目
	for i = ccIndex + 1, table.getn(characterCounts) do
		characterCounts[i] = nil
	end

	local totalCount = totalBags + totalBank + totalMail + totalEquipped

	if hasAnyItems then

		-- 库存块上方的顶部留白（视觉上约 10-12px）
		tooltip:AddLine(" ")

		-- 库存标签，使用与背包窗口标题完全相同的颜色
		tooltip:AddLine("|cFFFFD200" .. GudaBag.L["Inventory"] .. "|r")

		-- 总计行，青色标签 + 白色计数（复用模块级表）
		local totalText = "|cFF00FFFF" .. GudaBag.L["Total"] .. "|r: |cFFFFFFFF" .. totalCount .. "|r"
		local breakdownParts = _breakdownParts
		local bpIndex = 0
		if totalBags > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. GudaBag.L["Bags"] .. "|r: |cFFFFFFFF" .. totalBags .. "|r" end
		if totalBank > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. GudaBag.L["Bank"] .. "|r: |cFFFFFFFF" .. totalBank .. "|r" end
		if totalMail > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. GudaBag.L["Mail"] .. "|r: |cFFFFFFFF" .. totalMail .. "|r" end
		if totalEquipped > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. GudaBag.L["Equipped"] .. "|r: |cFFFFFFFF" .. totalEquipped .. "|r" end
		for i = bpIndex + 1, table.getn(breakdownParts) do breakdownParts[i] = nil end

		local breakdownText = ""
		if bpIndex > 0 then
			breakdownText = "(" .. table.concat(breakdownParts, " | ") .. ")"
		end
		tooltip:AddDoubleLine(totalText, breakdownText, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)

		-- 排序：自有角色在前（当前角色在最上方），然后是共享角色
		table.sort(characterCounts, function(a, b)
			if a.isShared ~= b.isShared then return not a.isShared end
			if a.isCurrent and not b.isCurrent then return true end
			if not a.isCurrent and b.isCurrent then return false end
			return a.name < b.name
		end)

		-- 复用模块级 parts 表，用于逐角色细分
		local parts = _charParts
		local sharedSeparatorShown = false
		for _, charInfo in ipairs(characterCounts) do
			if charInfo.isShared and not sharedSeparatorShown then
				tooltip:AddLine("|cFF80C0FF" .. GudaBag.L["Other Accounts"] .. "|r")
				sharedSeparatorShown = true
			end
			local r, g, b = GetClassColor(charInfo.classToken)
			local pIndex = 0

			if charInfo.bagCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. GudaBag.L["Bags"] .. "|r: |cFFFFFFFF" .. charInfo.bagCount .. "|r"
			end
			if charInfo.bankCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. GudaBag.L["Bank"] .. "|r: |cFFFFFFFF" .. charInfo.bankCount .. "|r"
			end
			if charInfo.mailCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. GudaBag.L["Mail"] .. "|r: |cFFFFFFFF" .. charInfo.mailCount .. "|r"
			end
			if charInfo.equippedCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. GudaBag.L["Equipped"] .. "|r: |cFFFFFFFF" .. charInfo.equippedCount .. "|r"
			end
			for i = pIndex + 1, table.getn(parts) do parts[i] = nil end

			local countText = ""
			if pIndex > 0 then
				countText = table.concat(parts, " | ")
			end

			-- 标记当前角色
			local displayName = charInfo.name
			if charInfo.isCurrent then
				displayName = displayName .. " |cFFFFFF00(*)|r"
			end

			tooltip:AddDoubleLine(displayName, countText, r, g, b, 1.0, 1.0, 1.0)
		end

		-- 库存块下方的底部留白（视觉上约 10-12px）
		--tooltip:AddLine(" ")

	end
end

function Tooltip:Initialize()
	addon:Print("Initializing tooltip module...")

	-- 延迟商人金币的辅助函数，以便我们可以在其上方插入库存块
	local Orig_SetTooltipMoney = SetTooltipMoney
	-- 垂直移动提示框的金币框架，以便在自定义块下方微调其位置
	local function AdjustMoneyFrames(tooltip, yOffset)
		if not tooltip or not tooltip.GetName then return end
		local baseName = tooltip:GetName()
		if not baseName then return end

		-- 收集魔兽世界提示框使用的可能金币框架名称
		local candidates = {}
		-- 主要金币框架
		tinsert(candidates, baseName .. "MoneyFrame")
		-- 有时会创建多个带数字后缀的金币框架
		for i = 1, 8 do
			tinsert(candidates, baseName .. "MoneyFrame" .. i)
			tinsert(candidates, baseName .. "SmallMoneyFrame" .. i)
		end

		for i = 1, getn(candidates) do
			local f = getglobal(candidates[i])
			if f and f:IsShown() and f.GetPoint then
				local point, relTo, relPoint, xOfs, yOfs = f:GetPoint(1)
				if point then
					f:SetPoint(point, relTo, relPoint, xOfs or 0, (yOfs or 0) + (yOffset or 0))
				end
			end
		end
	end
	local function WithDeferredMoney(tooltip, buildFunc)
		local queue = {}
		-- 临时覆盖全局 SetTooltipMoney
		SetTooltipMoney = function(frame, money, a1, a2, a3, a4, a5)
			if frame == tooltip then
				tinsert(queue, {frame, money, a1, a2, a3, a4, a5})
			else
				Orig_SetTooltipMoney(frame, money, a1, a2, a3, a4, a5)
			end
		end

		-- 执行原始的填充 + 我们的库存增强
		local ret = buildFunc()

		-- 恢复并刷新排队的金币，使其显示在库存块之后
		SetTooltipMoney = Orig_SetTooltipMoney
		for i = 1, getn(queue) do
			local q = queue[i]
			Orig_SetTooltipMoney(q[1], q[2], q[3], q[4], q[5], q[6], q[7])
		end

		-- 确保提示框背景调整大小，以同时容纳我们的块和金币框架
		tooltip:Show()

		-- 在库存块下方给售价/金币框架下移一点，避免与 guda 添加的行重叠，
		-- 使售价保持清晰可见（结合子框架层级提升，售价不再被压灰）。
		AdjustMoneyFrames(tooltip, 0)  --不要调整这个位置了，不然又串位置了，现在挺好——west
		return ret
	end

	-- 钩住 SetBagItem
	local oldSetBagItem = GameTooltip.SetBagItem
	local oldSetInventoryItem = GameTooltip.SetInventoryItem
	function GameTooltip:SetBagItem(bag, slot)
		return WithDeferredMoney(self, function()
			local bankFrame = getglobal("BankFrame")
			if bag == -1 and bankFrame and bankFrame:IsVisible() then
				local invSlot = BankButtonIDToInvSlotID(slot)
				if invSlot then
					-- 对于银行主背包使用物品栏方法
					local ret = oldSetInventoryItem(self, "player", invSlot)
					local link = GetInventoryItemLink("player", invSlot)
					if link then
						Tooltip:AddInventoryInfo(self, link)
					end
					return ret
				end
				return nil
			else
				local ret = oldSetBagItem(self, bag, slot)
				local link = GetContainerItemLink(bag, slot)
				if link then
					Tooltip:AddInventoryInfo(self, link)
				end
				return ret
			end
		end)
	end

 	-- 钩住 SetHyperlink，用于聊天和缓存链接的超链接
 	local oldSetHyperlink = GameTooltip.SetHyperlink
	function GameTooltip:SetHyperlink(link)
		return WithDeferredMoney(self, function()
			-- 原生暴雪 SetHyperlink 只接受裸的 "item:ID:e:e:e" 字符串。
			-- 任何在 Guda 加载之前捕获了原生函数的插件（例如 AtlasLoot）都会
			-- 直接用它调用我们传入的内容，因此我们必须去除颜色代码
			-- 和 |H...|h 包装后再转发。传入完整彩色链接会导致
			-- 那些插件出现 "unknown link type"。
			local _, _, inner = string.find(link or "", "|H(.+)|h")
			local forwarded = inner or link
			local itemLinkForCounts = inner or link
			local ret = oldSetHyperlink(self, forwarded)
			if itemLinkForCounts and strfind(itemLinkForCounts, "item:") then
				Tooltip:AddInventoryInfo(self, itemLinkForCounts)
			end

			return ret
		end)
	end

	-- 钩住 SetInventoryItem，用于角色纸娃娃
	oldSetInventoryItem = GameTooltip.SetInventoryItem
	function GameTooltip:SetInventoryItem(unit, slot)
		return WithDeferredMoney(self, function()
			local ret = oldSetInventoryItem(self, unit, slot)
			local link = GetInventoryItemLink(unit, slot)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetLootItem，用于拾取窗口
	local oldSetLootItem = GameTooltip.SetLootItem
	function GameTooltip:SetLootItem(slot)
		return WithDeferredMoney(self, function()
			local ret = oldSetLootItem(self, slot)
			local link = GetLootSlotLink(slot)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetQuestItem，用于任务奖励
	local oldSetQuestItem = GameTooltip.SetQuestItem
	function GameTooltip:SetQuestItem(itemType, index)
		return WithDeferredMoney(self, function()
			local ret = oldSetQuestItem(self, itemType, index)
			local link = GetQuestItemLink(itemType, index)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetMerchantItem，用于商人物品
	local oldSetMerchantItem = GameTooltip.SetMerchantItem
	function GameTooltip:SetMerchantItem(index)
		return WithDeferredMoney(self, function()
			local ret = oldSetMerchantItem(self, index)
			local link = GetMerchantItemLink(index)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetAuctionItem，用于拍卖行
	local oldSetAuctionItem = GameTooltip.SetAuctionItem
	function GameTooltip:SetAuctionItem(type, index)
		return WithDeferredMoney(self, function()
			local ret = oldSetAuctionItem(self, type, index)
			local link = GetAuctionItemLink(type, index)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetInboxItem，用于邮箱
	local oldSetInboxItem = GameTooltip.SetInboxItem
	function GameTooltip:SetInboxItem(index, itemIndex)
		return WithDeferredMoney(self, function()
			local ret = oldSetInboxItem(self, index, itemIndex)
			local link = addon.Modules.Utils:GetInboxItemLink(index, itemIndex)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetTradeSkillItem，用于专业技能材料和物品
	local oldSetTradeSkillItem = GameTooltip.SetTradeSkillItem
	function GameTooltip:SetTradeSkillItem(skillIndex, reagentIndex)
		return WithDeferredMoney(self, function()
			local ret = oldSetTradeSkillItem(self, skillIndex, reagentIndex)
			local link
			if reagentIndex then
				link = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
			else
				link = GetTradeSkillItemLink(skillIndex)
			end
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 钩住 SetCraftItem，用于附魔等专业技能（制作）
	local oldSetCraftItem = GameTooltip.SetCraftItem
	function GameTooltip:SetCraftItem(skillIndex, reagentIndex)
		return WithDeferredMoney(self, function()
			local ret = oldSetCraftItem(self, skillIndex, reagentIndex)
			local link
			if reagentIndex then
				link = GetCraftReagentItemLink(skillIndex, reagentIndex)
			else
				link = GetCraftItemLink(skillIndex)
			end
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
			return ret
		end)
	end

	-- 也钩住 ItemRefTooltip，用于聊天链接
	if ItemRefTooltip then
		local oldItemRefSetHyperlink = ItemRefTooltip.SetHyperlink
		function ItemRefTooltip:SetHyperlink(link)
			return WithDeferredMoney(self, function()
				local ret = oldItemRefSetHyperlink(self, link)
				if link and strfind(link, "item:") then
					Tooltip:AddInventoryInfo(self, link)
				end
				return ret
			end)
		end
	end

	-- 清除缓存函数
	function Tooltip:ClearCache()
		addon:Debug("Tooltip cache cleared")
	end

	-- 在背包更新时清除缓存（防抖，防止快速更新时卡顿）
	local frame = CreateFrame("Frame")
	local cacheClearPending = false
	frame:RegisterEvent("BAG_UPDATE")
	frame:SetScript("OnEvent", function()
		if event == "BAG_UPDATE" then
			-- 排序时跳过提示框缓存清除（物品没有变化，只是移动）
			if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then return end
			if cacheClearPending then return end
			cacheClearPending = true
			-- 防抖：批量处理快速的 BAG_UPDATE 事件（使用池化定时器）
			GudaBag.ScheduleTimer(0.2, function()
				cacheClearPending = false
				Tooltip:ClearCache()
			end)
		end
	end)

	addon:Print(GudaBag.L["Tooltip integration enabled - Inventory displays above vendor price"])
end
