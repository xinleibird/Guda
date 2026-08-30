-- Guda 数据库模块
-- 负责保存和加载角色数据

local addon = Guda

local DB = {}
addon.Modules.DB = DB

-- 当前玩家信息
local playerName, playerRealm, playerFaction

-- 检测是否有其他插件已经提供自动拾取，这样 Guda 自己的自动拾取可以
-- 默认保持关闭（避免双重拾取）。已知提供者：
--   * automatonEX / Automaton（自动拾取 + 各种自动化，暴露 Automaton 全局）
--   * superapi - 暴露 superapi 全局变量
-- 如果有外部自动拾取提供者，则返回 true。
function DB:HasExternalAutoLoot()
    -- 全局表探测（在 PLAYER_LOGIN 之后其他插件加载完毕时可靠）。
    -- 注意 Automatonex 暴露的是大写 Automaton（其插件的加载名是 Automatonex）。
    if Automaton or automaton or automatonEX or superapi then
        return true
    end
    -- 已加载插件探测作为回退方案（以防全局变量未暴露）。
    if IsAddOnLoaded then
        if IsAddOnLoaded("Automatonex") or IsAddOnLoaded("Automaton")
           or IsAddOnLoaded("automatonEX") or IsAddOnLoaded("automaton")
           or IsAddOnLoaded("superapi") then
            return true
        end
    end
    return false
end

-- 初始化数据库
function DB:Initialize()
-- 获取玩家信息
	playerName = UnitName("player")
	playerRealm = GetRealmName()
	playerFaction = UnitFactionGroup("player")

	local fullName = playerName .. "-" .. playerRealm

	-- 初始化全局数据库
	if not Guda_DB then
		Guda_DB = {
			version = addon.VERSION,
			characters = {},
		}
	end

	-- 初始化金币黑名单（账号级）
	if not Guda_DB.goldBlacklist then
		Guda_DB.goldBlacklist = {}
	end

	-- 初始化角色数据库
	if not Guda_CharDB then
		-- 诊断：登录时角色存档缺失（Guda.lua 未加载）。
		-- 常见原因：换客户端（WTF 目录不同）、换角色/角色改名、
		-- 插件文件夹被改名（存档文件名与文件夹名一致）。
		-- 此时只能用默认设置，提示用户以免误以为设置被重置。
		if addon and addon.Print then
			addon:Print(GudaBag.L["Character settings not found - starting with defaults. (Check: same client/WTF folder, same character, addon folder name unchanged)"])
		end
		Guda_CharDB = {
			settings = {
				showBankInBags = true,
				showOtherChars = true,
				bagColumns = 10,
				bankBagColumns = 8,
				bankColumns = 10,
				sortMethod = "quality", -- 品质、名称、类型
				iconSize = 37,
				iconSpacing = 4,
				iconFontSize = 12,
				showItemBorder = true,
			showSearchBar = true,   -- 旧版布尔值；为迁移而保留。新代码读取 searchBarMode。
			searchBarMode = "shown", -- "shown" | "hidden" | "toggle"
			showQualityBar = false, -- 在背包视图搜索框上方显示品质过滤栏（默认关闭）
				hideBagline = true,
				hideFooter = false,
				bgTransparency = 0.15,
			showTrackedItems = true,
			showTooltipCounts = true,
			showLootMarker = false, -- 在最近拾取窗口内的物品右上角显示标记（旧版布尔值，保留迁移用）
			lootMarkerPulse = false, -- 标记样式：true=红色呼吸边框，false=星星图标(xingxing.blp)（旧版布尔值，保留迁移用）
			lootMarkerMode = 0, -- 拾取标记模式：0=关闭，1=星星图标，2=呼吸边框
				markUnusableItems = true,
				bagViewType = "category", -- single、category
				bankViewType = "category", -- single、category
				trackedItems = {},
			},
		}
	end

	-- 兜底：存档存在但 settings 表缺失（如手改过的存档文件），
	-- 避免后续访问 Guda_CharDB.settings.xxx 时报错导致初始化中断。
	if not Guda_CharDB.settings then
		Guda_CharDB.settings = {}
	end

	-- 确保现有安装具有新设置
	if Guda_CharDB.settings.bagViewType == nil then
		Guda_CharDB.settings.bagViewType = "category"
	end
	if Guda_CharDB.settings.bankViewType == nil then
		Guda_CharDB.settings.bankViewType = "category"
	end
	if Guda_CharDB.settings.showTooltipCounts == nil then
		Guda_CharDB.settings.showTooltipCounts = true
	end
	if Guda_CharDB.settings.bgTransparency == nil then
		if Guda_CharDB.settings.frameOpacity ~= nil then
			Guda_CharDB.settings.bgTransparency = 1.0 - Guda_CharDB.settings.frameOpacity
			Guda_CharDB.settings.frameOpacity = nil -- 清理旧设置
		else
			Guda_CharDB.settings.bgTransparency = 0.15
		end
	end
	if Guda_CharDB.settings.hideFooter == nil then
		Guda_CharDB.settings.hideFooter = false
	end
	if Guda_CharDB.settings.hideBagline == nil then
		Guda_CharDB.settings.hideBagline = true
	end
	if Guda_CharDB.settings.showQuestBar == nil then
		Guda_CharDB.settings.showQuestBar = true
	end
	if Guda_CharDB.settings.showTrackedItems == nil then
		Guda_CharDB.settings.showTrackedItems = true
	end
	if Guda_CharDB.settings.trackedItems == nil then
		Guda_CharDB.settings.trackedItems = {}
	end
	if not Guda_CharDB.settings.bagColumns then
		Guda_CharDB.settings.bagColumns = 10
	end
	if not Guda_CharDB.settings.bankBagColumns then
		Guda_CharDB.settings.bankBagColumns = 8
	end
	if not Guda_CharDB.settings.bankColumns then
		Guda_CharDB.settings.bankColumns = 10
	end
	if not Guda_CharDB.settings.iconSize then
		Guda_CharDB.settings.iconSize = 37
	end
	if not Guda_CharDB.settings.iconSpacing then
		Guda_CharDB.settings.iconSpacing = 4
	end
	if not Guda_CharDB.settings.iconFontSize then
		Guda_CharDB.settings.iconFontSize = 12
	end
	-- 统一"物品边框"开关：合并旧的装备/其他物品边框设置（仅一次性迁移，之后
	-- 只使用 showItemBorder）。旧存档里若存在旧键则取其组合值；否则默认开启。
	if Guda_CharDB.settings.showItemBorder == nil then
		local eq = Guda_CharDB.settings.showQualityBorderEquipment
		local other = Guda_CharDB.settings.showQualityBorderOther
		if eq ~= nil or other ~= nil then
			if eq == nil then eq = true end
			if other == nil then other = true end
			Guda_CharDB.settings.showItemBorder = eq and other
		else
			Guda_CharDB.settings.showItemBorder = true
		end
	end
	if Guda_CharDB.settings.showSearchBar == nil then
		Guda_CharDB.settings.showSearchBar = true
	end
	-- 将旧版布尔值迁移为三态 searchBarMode。
	if Guda_CharDB.settings.searchBarMode == nil then
		Guda_CharDB.settings.searchBarMode =
			(Guda_CharDB.settings.showSearchBar == false) and "hidden" or "shown"
	end
	if Guda_CharDB.settings.showQualityBar == nil then
		Guda_CharDB.settings.showQualityBar = false
	end
	if Guda_CharDB.settings.questBarPinnedItems == nil then
		Guda_CharDB.settings.questBarPinnedItems = {}
	end
	if Guda_CharDB.settings.markUnusableItems == nil then
		Guda_CharDB.settings.markUnusableItems = true
	end
	if Guda_CharDB.settings.mergedGroups == nil then
		Guda_CharDB.settings.mergedGroups = {}
	end
	if Guda_CharDB.settings.showEquipSetCategories == nil then
		Guda_CharDB.settings.showEquipSetCategories = true
	end
	if Guda_CharDB.settings.markEquipmentSets == nil then
		Guda_CharDB.settings.markEquipmentSets = true
	end
	if Guda_CharDB.settings.showCategoryCount == nil then
		Guda_CharDB.settings.showCategoryCount = true
	end
	if Guda_CharDB.settings.autoVendorJunk == nil then
		Guda_CharDB.settings.autoVendorJunk = true
	end
	if Guda_CharDB.settings.whiteItemsJunk == nil then
		Guda_CharDB.settings.whiteItemsJunk = false
	end
	if Guda_CharDB.settings.autoLockSetItems == nil then
		Guda_CharDB.settings.autoLockSetItems = true
	end
	if Guda_CharDB.settings.autoLoot == nil then
		-- 仅在没有其他插件处理自动拾取时才默认开启；
		-- 否则保持关闭以避免双重拾取。一旦该值被设置过
		-- （即使是手动设置），此逻辑就不会再覆盖它。
		Guda_CharDB.settings.autoLoot = not self:HasExternalAutoLoot()
	end
	if Guda_CharDB.settings.autoOpenClams == nil then
		Guda_CharDB.settings.autoOpenClams = false
	end
	if Guda_CharDB.settings.autoFillRows == nil then
		Guda_CharDB.settings.autoFillRows = false
	end
	if Guda_CharDB.settings.showLootMarker == nil then
		Guda_CharDB.settings.showLootMarker = false
	end
	if Guda_CharDB.settings.lootMarkerPulse == nil then
		Guda_CharDB.settings.lootMarkerPulse = false
	end
	-- 将旧版 showLootMarker/lootMarkerPulse 迁移为 lootMarkerMode
	if Guda_CharDB.settings.lootMarkerMode == nil then
		if Guda_CharDB.settings.showLootMarker == true then
			Guda_CharDB.settings.lootMarkerMode =
				(Guda_CharDB.settings.lootMarkerPulse == true) and 2 or 1
		else
			Guda_CharDB.settings.lootMarkerMode = 0
		end
	end

	-- 首次加载时自动检测界面插件（主题尚未设置）。
	-- 如果存在 pfUI，则采用其外观；否则如果存在 Dragonflight（DFRL），
	-- 则采用 Dragonflight 外观；两者都不存在时默认使用 Guda 自己的
	-- 框架（常规项由 GUDA 接管，而不是退回原生/其他 UI 插件）。
	if Guda_CharDB.settings.theme == nil then
		if pfUI and pfUI.env then
			Guda_CharDB.settings.theme = "pfui"
			Guda_CharDB.settings.hideBorders = true
			Guda_CharDB.settings.bgTransparency = Guda.Constants.PFUI_DEFAULT_BG_TRANSPARENCY
			Guda_CharDB.settings.usePfUITransparency = true
			Guda_CharDB.settings.iconSpacing = 8
		elseif DFRL then
			Guda_CharDB.settings.theme = "dragonflight"
		else
			Guda_CharDB.settings.theme = "guda"
		end
	end

	-- 初始化锁定物品存储
	if not Guda_CharDB.lockedItems then
		Guda_CharDB.lockedItems = {}
	end

	-- 初始化套装保护例外存储
	if not Guda_CharDB.setProtectionExceptions then
		Guda_CharDB.setProtectionExceptions = {}
	end

	-- 初始化固定栏位存储
	if not Guda_CharDB.pinnedSlots then
		Guda_CharDB.pinnedSlots = {}
	end

	-- 为自定义分类初始化 CategoryManager
	if addon.Modules.CategoryManager then
		addon.Modules.CategoryManager:Initialize()
	end

	-- 初始化该角色的数据
	if not Guda_DB.characters[fullName] then
		local localizedClass, englishClass = UnitClass("player")
		Guda_DB.characters[fullName] = {
			name = playerName,
			realm = playerRealm,
			faction = playerFaction,
			class = localizedClass,
			classToken = englishClass, -- 供 RAID_CLASS_COLORS 使用的英文大写令牌
			level = UnitLevel("player"),
			money = 0,
			bags = {},
			bank = {},
			mailbox = {},   -- 添加邮箱存储
			equipped = {},  -- 添加已装备物品存储
			character = {}, -- 添加角色信息存储
			lastUpdate = time(),
		}
	else
	-- 迁移：为现有角色添加 classToken
		local char = Guda_DB.characters[fullName]
		if not char.classToken then
			local localizedClass, englishClass = UnitClass("player")
			char.classToken = englishClass
			addon:Debug("Added classToken to existing character")
		end

		-- 迁移：如果不存在则添加 equipped 和 character 字段
		if not char.equipped then
			char.equipped = {}
			addon:Debug("Added equipped field to existing character")
		end
		if not char.character then
			char.character = {}
			addon:Debug("Added character field to existing character")
		end
		if not char.mailbox then
			char.mailbox = {}
			addon:Debug("Added mailbox field to existing character")
		end
	end

	addon:Debug("Database initialized for %s", fullName)
end

-- 获取当前玩家的完整名称
function DB:GetPlayerFullName()
	return playerName .. "-" .. playerRealm
end

-- 获取当前角色数据
function DB:GetCurrentCharacter()
	local fullName = self:GetPlayerFullName()
	return Guda_DB.characters[fullName]
end

-- 获取当前角色数据（兼容别名）
function DB:GetCurrentCharacterData()
	return self:GetCurrentCharacter()
end

-- 保存背包数据
function DB:SaveBags(bagData)
	local char = self:GetCurrentCharacter()
	if char then
		char.bags = bagData
		char.lastUpdate = time()
		addon:Debug("Saved bag data")
	end
end

-- 保存银行数据
function DB:SaveBank(bankData)
	local char = self:GetCurrentCharacter()
	if char then
		char.bank = bankData
		char.lastUpdate = time()
		addon:Debug("Saved bank data")
	end
end

-- 保存装备数据
function DB:SaveEquipment(equipmentData)
	local char = self:GetCurrentCharacter()
	if char then
		char.equipped = equipmentData.equipped
		char.character = equipmentData.character
		char.lastUpdate = time()
		addon:Debug("Saved equipment data")
	end
end

-- 保存金币
function DB:SaveMoney(copper)
	local char = self:GetCurrentCharacter()
	if char then
		char.money = copper
		char.level = UnitLevel("player")
		addon:Debug("Saved money: %d copper", copper)
	end
end

-- 保存邮箱数据
function DB:SaveMailbox(mailboxData)
	local char = self:GetCurrentCharacter()
	if char then
		char.mailbox = mailboxData
		char.lastUpdate = time()
		addon:Debug("Saved mailbox data")
	end
end

-- 向角色的邮箱添加单条邮件条目
-- 这些是外发邮件/拍卖行成交的预测 —— 当收件人打开邮箱进行
-- 完整重扫（SaveMailbox）时，它们会被替换。
function DB:AddMailToCharacter(name, realm, mailRow)
	local fullName = name .. "-" .. (realm or playerRealm)
	local char = Guda_DB.characters[fullName]

	if char then
		if not char.mailbox then
			char.mailbox = {}
		end

		table.insert(char.mailbox, 1, mailRow)
		char.lastUpdate = time()
		addon:Debug("Added outgoing mail to %s's mailbox", fullName)
		return true
	end
	return false
end

-- 获取所有角色（可选地按阵营和/或服务器过滤）
function DB:GetAllCharacters(sameFactionOnly, currentRealmOnly)
	local chars = {}

	-- 来自 SavedVariables 的自有角色
	for fullName, data in pairs(Guda_DB.characters) do
		local factionMatch = not sameFactionOnly or data.faction == playerFaction
		local realmMatch = not currentRealmOnly or data.realm == playerRealm
		if factionMatch and realmMatch then
			table.insert(chars, {
				fullName = fullName,
				name = data.name,
				realm = data.realm,
				class = data.class,
				classToken = data.classToken,
				level = data.level,
				faction = data.faction,
				money = data.money,
				lastUpdate = data.lastUpdate,
			})
		end
	end

	-- 来自其他账号的共享角色（仅内存）
	if addon.sharedCharacters then
		for fullName, data in pairs(addon.sharedCharacters) do
			local factionMatch = not sameFactionOnly or data.faction == playerFaction
			local realmMatch = not currentRealmOnly or data.realm == playerRealm
			if factionMatch and realmMatch then
				table.insert(chars, {
					fullName = fullName,
					name = data.name,
					realm = data.realm,
					class = data.class,
					classToken = data.classToken,
					level = data.level,
					faction = data.faction,
					money = data.money,
					lastUpdate = data.lastUpdate,
					account = data.account,
					isShared = true,
				})
			end
		end
	end

	-- 按名称排序
	table.sort(chars, function(a, b)
		return a.name < b.name
	end)

	return chars
end

-- 在自己的数据库或共享角色中查找角色
function DB:GetCharacterData(fullName)
	local char = Guda_DB.characters[fullName]
	if not char and addon.sharedCharacters then
		char = addon.sharedCharacters[fullName]
	end
	return char
end

-- 获取角色的背包
function DB:GetCharacterBags(fullName)
	local char = self:GetCharacterData(fullName)
	return char and char.bags or {}
end

-- 获取角色的银行
function DB:GetCharacterBank(fullName)
	local char = self:GetCharacterData(fullName)
	return char and char.bank or {}
end

-- 获取角色的邮箱
function DB:GetCharacterMailbox(fullName)
	local char = self:GetCharacterData(fullName)
	return char and char.mailbox or {}
end

-- 在任何角色的数据中按名称查找物品 ID 和链接
function DB:FindItemByName(name)
	if not name or name == "" then return nil, nil end

	local function searchChar(char)
		if type(char) ~= "table" then return nil, nil end
		-- 检查背包
		if char.bags then
			for bagID, bagData in pairs(char.bags) do
				if type(bagData) == "table" and bagData.slots then
					for slotID, item in pairs(bagData.slots) do
						if item and item.name == name and item.link then
							local itemID = addon.Modules.Utils:ExtractItemID(item.link)
							if itemID then return itemID, item.link end
						end
					end
				end
			end
		end
		-- 检查银行
		if char.bank then
			for bagID, bagData in pairs(char.bank) do
				if type(bagData) == "table" and bagData.slots then
					for slotID, item in pairs(bagData.slots) do
						if item and item.name == name and item.link then
							local itemID = addon.Modules.Utils:ExtractItemID(item.link)
							if itemID then return itemID, item.link end
						end
					end
				end
			end
		end
		-- 检查已装备
		if char.equipped then
			for slot, item in pairs(char.equipped) do
				if item and item.name == name and item.link then
					local itemID = addon.Modules.Utils:ExtractItemID(item.link)
					if itemID then return itemID, item.link end
				end
			end
		end
		-- 检查邮箱
		if char.mailbox then
			for _, mail in ipairs(char.mailbox) do
				if mail.item and mail.item.name == name and mail.item.link then
					local itemID = addon.Modules.Utils:ExtractItemID(mail.item.link)
					if itemID then return itemID, mail.item.link end
				end
			end
		end
		return nil, nil
	end

	if Guda_DB and Guda_DB.characters then
		for fullName, char in pairs(Guda_DB.characters) do
			local id, link = searchChar(char)
			if id then return id, link end
		end
	end
	if addon.sharedCharacters then
		for fullName, char in pairs(addon.sharedCharacters) do
			local id, link = searchChar(char)
			if id then return id, link end
		end
	end
	return nil, nil
end

-- 获取角色已装备的物品
function DB:GetCharacterEquipped(fullName)
	local char = self:GetCharacterData(fullName)
	return char and char.equipped or {}
end

-- 获取角色信息
function DB:GetCharacterInfo(fullName)
	local char = self:GetCharacterData(fullName)
	return char and char.character or {}
end

-- 获取所有角色的总金币（可选地按阵营和/或服务器过滤）
function DB:GetTotalMoney(sameFactionOnly, currentRealmOnly)
	local total = 0
	for fullName, data in pairs(Guda_DB.characters) do
		local factionMatch = not sameFactionOnly or data.faction == playerFaction
		local realmMatch = not currentRealmOnly or data.realm == playerRealm
		if factionMatch and realmMatch then
			total = total + (data.money or 0)
		end
	end
	-- 包含共享角色
	if addon.sharedCharacters then
		for fullName, data in pairs(addon.sharedCharacters) do
			local factionMatch = not sameFactionOnly or data.faction == playerFaction
			local realmMatch = not currentRealmOnly or data.realm == playerRealm
			if factionMatch and realmMatch then
				total = total + (data.money or 0)
			end
		end
	end
	return total
end

-- 检查角色是否被排除在金币/物品追踪之外
function DB:IsGoldBlacklisted(fullName)
	return Guda_DB.goldBlacklist and Guda_DB.goldBlacklist[fullName]
end

-- 切换角色在金币/物品追踪中的排除状态
function DB:ToggleGoldBlacklist(fullName)
	if not Guda_DB.goldBlacklist then
		Guda_DB.goldBlacklist = {}
	end
	if Guda_DB.goldBlacklist[fullName] then
		Guda_DB.goldBlacklist[fullName] = nil
	else
		Guda_DB.goldBlacklist[fullName] = true
	end
end

-- 清理不再存在的角色的黑名单条目
-- 在 SharedData 导入后调用，以便共享角色已经存在
function DB:CleanupBlacklist()
	if not Guda_DB.goldBlacklist then return end
	for fullName in pairs(Guda_DB.goldBlacklist) do
		local exists = Guda_DB.characters[fullName] or (addon.sharedCharacters and addon.sharedCharacters[fullName])
		if not exists then
			Guda_DB.goldBlacklist[fullName] = nil
		end
	end
end

-- 完全从数据库中移除一个角色
function DB:RemoveCharacter(fullName)
	if not fullName then return end
	-- 不允许移除当前角色
	local currentFullName = playerName and playerRealm and (playerName .. "-" .. playerRealm)
	if fullName == currentFullName then return false end

	if Guda_DB.characters[fullName] then
		Guda_DB.characters[fullName] = nil
	end
	if addon.sharedCharacters and addon.sharedCharacters[fullName] then
		addon.sharedCharacters[fullName] = nil
	end
	if Guda_DB.goldBlacklist and Guda_DB.goldBlacklist[fullName] then
		Guda_DB.goldBlacklist[fullName] = nil
	end
	return true
end

-- 获取角色设置
function DB:GetSetting(key)
-- 当某些界面 OnLoad 脚本运行时，SavedVariables 可能尚未初始化
	if not Guda_CharDB or not Guda_CharDB.settings then
		return nil
	end
	return Guda_CharDB.settings[key]
end

-- 设置角色设置
function DB:SetSetting(key, value)
-- 即使提前调用也确保表存在
	if not Guda_CharDB then
		Guda_CharDB = { settings = {} }
	elseif not Guda_CharDB.settings then
		Guda_CharDB.settings = {}
	end
	Guda_CharDB.settings[key] = value
end

-------------------------------------------------
-- 锁定物品（按角色、基于 itemID）
-------------------------------------------------

function DB:IsItemLocked(itemID)
	if not itemID or not Guda_CharDB or not Guda_CharDB.lockedItems then return false end
	return Guda_CharDB.lockedItems[itemID] and true or false
end

function DB:ToggleItemLock(itemID)
	if not itemID or not Guda_CharDB then return false end
	if not Guda_CharDB.lockedItems then
		Guda_CharDB.lockedItems = {}
	end
	if Guda_CharDB.lockedItems[itemID] then
		Guda_CharDB.lockedItems[itemID] = nil
		return false
	else
		Guda_CharDB.lockedItems[itemID] = true
		return true
	end
end

-------------------------------------------------
-- 套装保护例外（按角色）
-- 用户通过 Ctrl+右键 明确选择不保护
-- 的装备套装中的物品
-------------------------------------------------

function DB:IsSetProtectionException(itemID)
	if not itemID or not Guda_CharDB or not Guda_CharDB.setProtectionExceptions then return false end
	return Guda_CharDB.setProtectionExceptions[itemID] and true or false
end

function DB:ToggleSetProtectionException(itemID)
	if not itemID or not Guda_CharDB then return false end
	if not Guda_CharDB.setProtectionExceptions then
		Guda_CharDB.setProtectionExceptions = {}
	end
	if Guda_CharDB.setProtectionExceptions[itemID] then
		Guda_CharDB.setProtectionExceptions[itemID] = nil
		return false  -- 保护已恢复
	else
		Guda_CharDB.setProtectionExceptions[itemID] = true
		return true   -- 保护已移除（例外）
	end
end

-- 移除不再属于任何装备套装的物品的例外
function DB:PruneSetProtectionExceptions()
	if not Guda_CharDB or not Guda_CharDB.setProtectionExceptions then return end
	local EquipSets = addon.Modules.EquipmentSets
	if not EquipSets or not EquipSets.IsInSet then return end
	for itemID in pairs(Guda_CharDB.setProtectionExceptions) do
		if not EquipSets:IsInSet(itemID) then
			Guda_CharDB.setProtectionExceptions[itemID] = nil
		end
	end
end

-- 检查物品是否受保护（用户锁定或位于启用 autoLockSetItems 的装备套装中）
function DB:IsItemProtected(itemID)
	if not itemID then return false end
	if self:IsItemLocked(itemID) then return true end
	if self:GetSetting("autoLockSetItems") then
		local EquipSets = addon.Modules.EquipmentSets
		if EquipSets and EquipSets.IsInSet and EquipSets:IsInSet(itemID)
		   and not self:IsSetProtectionException(itemID) then
			return true
		end
	end
	return false
end

-------------------------------------------------
-- 固定栏位（按角色、基于栏位）
-- 用户固定的栏位在排序时会被跳过。
-- 键格式：bagID * 1000 + slot
-------------------------------------------------

function DB:IsPinnedSlot(bagID, slot)
	if not bagID or not slot or not Guda_CharDB or not Guda_CharDB.pinnedSlots then return false end
	return Guda_CharDB.pinnedSlots[bagID * 1000 + slot] and true or false
end

function DB:TogglePinnedSlot(bagID, slot)
	if not bagID or not slot or not Guda_CharDB then return false end
	if not Guda_CharDB.pinnedSlots then
		Guda_CharDB.pinnedSlots = {}
	end
	local key = bagID * 1000 + slot
	if Guda_CharDB.pinnedSlots[key] then
		Guda_CharDB.pinnedSlots[key] = nil
		return false  -- 已取消固定
	else
		Guda_CharDB.pinnedSlots[key] = true
		return true   -- 已固定
	end
end

function DB:GetPinnedSlotSet()
	if not Guda_CharDB or not Guda_CharDB.pinnedSlots then return {} end
	return Guda_CharDB.pinnedSlots
end

-- 清理旧角色（90 天未更新）
function DB:CleanupOldCharacters()
	local cutoff = time() - (90 * 24 * 60 * 60) -- 90 天
	local removed = 0

	for fullName, data in pairs(Guda_DB.characters) do
		if data.lastUpdate and data.lastUpdate < cutoff then
			Guda_DB.characters[fullName] = nil
			removed = removed + 1
		end
	end

	if removed > 0 then
		addon:Print("Cleaned up %d old character(s)", removed)
	end
end