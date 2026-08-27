-- Guda 装备扫描器
-- 扫描并存储角色装备信息

local addon = Guda

local EquipmentScanner = {}
addon.Modules.EquipmentScanner = EquipmentScanner

local playerLoggedIn = false

-- 扫描所有装备并返回数据
function EquipmentScanner:ScanAll()
	local equipmentData = {
		equipped = self:ScanEquippedItems(),
		character = self:ScanCharacterInfo(),
		lastUpdated = time()
	}

	return equipmentData
end

-- 扫描所有已装备物品
function EquipmentScanner:ScanEquippedItems()
	local equipped = {}

	-- 要扫描的装备栏位列表
	local equipmentSlots = {
		"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot",
		"TabardSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
		"Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
		"MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot"
	}

	for _, slotName in ipairs(equipmentSlots) do
		local slotID = GetInventorySlotInfo(slotName)
		local itemLink = GetInventoryItemLink("player", slotID)

		if itemLink then
			local itemID = addon.Modules.Utils:ExtractItemID(itemLink)
			local itemName
			if itemID then
				itemName = addon.Modules.Utils:GetItemInfoSafe(itemID)
			end
			equipped[slotName] = {
				link = itemLink,
				name = itemName,
				texture = GetInventoryItemTexture("player", slotID)
			}
		end
	end

	return equipped
end

-- 扫描角色信息（等级、职业等）- 兼容 Lua 5.0
function EquipmentScanner:ScanCharacterInfo()
	local name = UnitName("player")
	local realm = GetRealmName()

	-- Lua 5.0：UnitClass 返回多个值，而不是表
	local class, classToken = UnitClass("player")
	local level = UnitLevel("player")
	local race = UnitRace("player")

	return {
		name = name,
		realm = realm,
		class = class,
		classToken = classToken,
		level = level,
		race = race,
		lastSeen = time()
	}
end

-- 将当前装备保存到数据库
function EquipmentScanner:SaveToDatabase()
	if not playerLoggedIn then
		return
	end

	local equipmentData = self:ScanAll()
	addon.Modules.DB:SaveEquipment(equipmentData)
	addon:Debug("Equipment data saved")
end

-- 初始化装备扫描器
function EquipmentScanner:Initialize()
	-- 玩家登录 - 保存装备数据
	addon.Modules.Events:OnPlayerLogin(function()
		playerLoggedIn = true
		addon:Print(GudaBag.L["Scanning equipped items..."])

		-- 延迟扫描以确保角色完全加载（使用池化定时器）
		GudaBag.ScheduleTimer(2.0, function()
			EquipmentScanner:SaveToDatabase()
			addon:Print(GudaBag.L["Equipped items scanned and saved!"])
		end)
	end, "EquipmentScanner")

	-- 装备变化
	addon.Modules.Events:Register("PLAYER_EQUIPMENT_CHANGED", function()
		if playerLoggedIn then
			EquipmentScanner:SaveToDatabase()
		end
	end, "EquipmentScanner")

	addon:Print("EquipmentScanner initialized successfully")
end

-- 检查玩家是否已登录
function EquipmentScanner:IsPlayerLoggedIn()
	return playerLoggedIn
end