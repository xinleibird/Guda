-- Guda 排序引擎
-- 适用于 WoW 1.12.1 / Turtle WoW 的背包/银行排序引擎（排序算法移植自 OneBag）

local addon = Guda

local SortEngine = {}
addon.Modules.SortEngine = SortEngine

-- 标记当前是否正在进行排序
SortEngine.sortingInProgress = false

-- 根据排序状态更新排序按钮外观
function SortEngine:UpdateSortButtonState(isDisabled)
	local buttons = {
		getglobal("Guda_BagFrame_SortButton"),
		getglobal("Guda_BankFrame_SortButton")
	}

	for _, btn in ipairs(buttons) do
		if btn then
			local icon = getglobal(btn:GetName() .. "_Icon")
			if icon then
				if isDisabled then
					icon:SetVertexColor(0.4, 0.4, 0.4)
				else
					icon:SetVertexColor(0.8, 0.8, 0.8)
				end
			end
		end
	end
end

-- 通过纹理路径检查物品是否为坐骑
function SortEngine.IsMount(itemTexture)
	if not itemTexture then return false end

	local textureLower = string.lower(itemTexture)

	-- 检查纹理路径中的坐骑模式
	-- 坐骑纹理通常包含 "mount" 或 "ability_mount"
	if string.find(textureLower, "_mount_") then
		return true
	end

	return false
end

--===========================================================================
-- 排序实现：移植自 OneBag 的 SortBags（shirsig）
--
-- 核心思路：一次性为每个槽位分配"目标物品"构建 model，然后通过
-- OnUpdate 分批移动（每次 Sort() + Stack()）。Move 只在源/目标都未
-- 锁定时执行，避免最后物品放不回或物品变灰锁死；7 秒超时兜底。
-- 入口 SortEngine:CleanUp 会先弹出确认对话框。
--
-- 对外接口（SortEngine:SortBags/SortBank/ExecuteSort/sortingInProgress/
-- UpdateSortButtonState/IsMount）由排序引擎统一提供。
--===========================================================================

-- 用于排序扫描物品 tooltip 的专用提示框
CreateFrame('GameTooltip', 'SortBagsTooltip', nil, 'GameTooltipTemplate')

-- 反向整理标记（默认正向），存于 GudaBag 命名空间避免全局冲突
GudaBag.SortBagsRightToLeft = nil

-- 前向声明：SE_Start 等在 do 块/后续赋值，须在引用它们的闭包（OnAccept 等）之前声明
local SE_Start, SE_Move, SE_TooltipInfo, SE_Sort, SE_Stack, SE_Initialize, SE_ContainerClass, SE_GetItemInfoCached, SE_Item

-- 确认对话框（整理前询问）
StaticPopupDialogs["SORT_BAGS_CONFIRM"] = {
	text = "确认整理%s？",
	button1 = "确认",
	button2 = "取消",
	OnAccept = function()
		SE_Start()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local SE_CONTAINERS
local SE_REVERSE

-- 排序工具函数（OneBag 移植）
local function SE_Set(...)
	local t = {}
	for i = 1, arg.n do
		t[arg[i]] = true
	end
	return t
end

local function SE_Union(...)
	local t = {}
	for i = 1, arg.n do
		for k in arg[i] do
			t[k] = true
		end
	end
	return t
end

local SE_ITEM_TYPES = {GetAuctionItemClasses()}

local SE_MOUNT = SE_Set(
	5864, 5872, 5873, 18785, 18786, 18787, 18244, 19030, 13328, 13329,
	2411, 2414, 5655, 5656, 18778, 18776, 18777, 18241, 12353, 12354,
	8629, 8631, 8632, 18766, 18767, 18902, 18242, 13086, 19902, 12302, 12303, 8628, 12326,
	8563, 8595, 13321, 13322, 18772, 18773, 18774, 18243, 13326, 13327,
	15277, 15290, 18793, 18794, 18795, 18247, 15292, 15293,
	1132, 5665, 5668, 18796, 18797, 18798, 18245, 12330, 12351,
	8588, 8591, 8592, 18788, 18789, 18790, 18246, 19872, 8586, 13317,
	13331, 13332, 13333, 13334, 18791, 18248, 13335,
	21218, 21321, 21323, 21324, 21176
)

local SE_SPECIAL = SE_Set(5462, 9173, 17056, 17696, 17117, 13347, 13289, 11511, 41915, 61000)

local SE_KEY = SE_Set(9240, 17191, 13544, 12324, 16309, 12384, 20402)

local SE_TOOL = SE_Set(6218, 6339, 11130, 11145, 16207, 5060, 7005, 12709, 19727, 5956, 2901, 6219, 10498, 9149, 15846, 6256, 6365, 6366, 6367, 55155, 41326, 41327, 41328, 12225, 19022, 19970)

local SE_ENCHANTING = SE_Set(
	10940, 11083, 11137, 11176, 16204,
	10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,
	10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344,
	20725
)

local SE_HERBS = SE_Set(765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820, 3821, 4625, 8153, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468)

local SE_SEEDS = SE_Set(17034, 17035, 17036, 17037, 17038)

local SE_CLASSES = {
	{
		containers = {2101, 5439, 7278, 11362, 3573, 3605, 7371, 8217, 2662, 19319, 18714, 61549},
		items = SE_Set(2512, 2515, 3030, 3464, 9399, 11285, 12654, 18042, 19316, 42198, 42199, 42200, 42201),
	},
	{
		containers = {2102, 5441, 7279, 11363, 3574, 3604, 7372, 8218, 2663, 19320},
		items = SE_Set(2516, 2519, 3033, 3465, 4960, 5568, 8067, 8068, 8069, 10512, 10513, 11284, 11630, 13377, 15997, 19317),
	},
	{
		containers = {22243, 22244, 21340, 21341, 21342},
		items = SE_Set(6265, 6990, 16583, 5565),
	},
	{
		containers = {22246, 22248, 22249},
		items = SE_Union(SE_ENCHANTING, SE_Set(6218, 6339, 11130, 11145, 16207)),
	},
	{
		containers = {22250, 22251, 22252},
		items = SE_Union(SE_HERBS, SE_SEEDS),
	},
}

-- 每轮移动之间的等待秒数（移植自 OneBag 原版）。每轮扫描会移动所有可移动
-- 的物品（锁定的跳过），间隔给服务器时间清除移动锁定；0.2s 在速度与防锁
-- 之间取得平衡，TurtleWoW（有目标血条）下放慢到 1.2s 更安全。
local SE_DEFAULT_DELAY = 0.2
if TargetHPText ~= nil and TargetHPPercText ~= nil then
	SE_DEFAULT_DELAY = 1.2
end

local seModel, seItemStacks, seItemClasses, seItemSortKeys

do
	local f = CreateFrame("Frame", "Clean_UpFrame", UIParent)
	f:Hide()

	local timeout

	SE_Start = function()
		if f:IsShown() then return end
		SE_Initialize()
		-- 每轮移动多个物品，超时需足够容纳整个背包的移动。
		-- 按槽位数量估算（含余量），最低 30 秒。
		local slots = 0
		for _, slot in seModel do slots = slots + 1 end
		timeout = GetTime() + max(30, slots * 0.6 + 10)
		SortEngine.sortingInProgress = true
		SortEngine:UpdateSortButtonState(true)
		-- 排序期间隐藏全部物品按钮，大幅降低每帧渲染开销，提升排序帧率。
		-- 排序结束的 finishSort 会调用 Update() 重建恢复按钮。
		if SortEngine.currentTarget == "bank" then
			if GudaBag.BankFrame_HideAllItemButtons then GudaBag.BankFrame_HideAllItemButtons() end
		else
			if GudaBag.BagFrame_HideAllItemButtons then GudaBag.BagFrame_HideAllItemButtons() end
		end
		f:Show()
	end

	local delay = 0

	-- 排序完成：清理状态、刷新缓存与视图
	local function finishSort()
		f:Hide()
		SortEngine.sortingInProgress = false
		SortEngine:UpdateSortButtonState(false)
		ClearCursor()
		if SortEngine.currentTarget == "bank" then
			if addon.Modules.BankScanner then addon.Modules.BankScanner:ClearCache() end
		else
			if addon.Modules.BagScanner then addon.Modules.BagScanner:ClearCache() end
		end
		if addon.Modules.BagFrame and addon.Modules.BagFrame.Update then
			addon.Modules.BagFrame:Update()
		end
		if addon.Modules.BankFrame and addon.Modules.BankFrame.Update then
			local bankFrame = getglobal("Guda_BankFrame")
			if bankFrame and bankFrame:IsShown() then
				addon.Modules.BankFrame:Update()
			end
		end
		if addon.Modules.QuestItemBar and addon.Modules.QuestItemBar.Update then addon.Modules.QuestItemBar:Update() end
		if addon.Modules.TrackedItemBar and addon.Modules.TrackedItemBar.Update then addon.Modules.TrackedItemBar:Update() end
	end

	f:SetScript('OnUpdate', function()
		delay = delay - arg1
		if delay <= 0 then
			delay = SE_DEFAULT_DELAY
			local complete = SE_Sort()
			if complete or GetTime() > timeout then
				finishSort()
				return
			end
			SE_Stack()
		end
	end)
end

local function SE_KeyIn(table, value)
	for k, v in table do
		if v == value then
			return k
		end
	end
end

local function SE_ItemTypeKey(itemClass)
	return SE_KeyIn(SE_ITEM_TYPES, itemClass) or 0
end

local function SE_ItemSubTypeKey(itemClass, itemSubClass)
	return SE_KeyIn({GetAuctionItemSubClasses(SE_ItemTypeKey(itemClass))}, itemSubClass) or 0
end

local function SE_ItemInvTypeKey(itemClass, itemSubClass, itemSlot)
	return SE_KeyIn({GetAuctionInvTypes(SE_ItemTypeKey(itemClass), SE_ItemSubTypeKey(itemClass, itemSubClass))}, itemSlot) or 0
end

local function SE_LT(a, b)
	local i = 1
	while true do
		if a[i] and b[i] and a[i] ~= b[i] then
			return a[i] < b[i]
		elseif not a[i] and b[i] then
			return true
		elseif not b[i] then
			return false
		end
		i = i + 1
	end
end

-- 移动（仅当源/目标均未锁定时执行，避免物品变灰卡死）
SE_Move = function(src, dst)
	local texture, _, srcLocked = GetContainerItemInfo(src.container, src.position)
	local _, _, dstLocked = GetContainerItemInfo(dst.container, dst.position)

	if texture and not srcLocked and not dstLocked then
		ClearCursor()
		PickupContainerItem(src.container, src.position)
		PickupContainerItem(dst.container, dst.position)

		if src.item == dst.item then
			local count = min(src.count, seItemStacks[dst.item] - dst.count)
			src.count = src.count - count
			dst.count = dst.count + count
			if src.count == 0 then
				src.item = nil
			end
		else
			src.item, dst.item = dst.item, src.item
			src.count, dst.count = dst.count, src.count
		end

		return true
	end
end

local seTooltipCache = {}
SE_TooltipInfo = function(itemID, container, position)
	if itemID and seTooltipCache[itemID] then
		local cached = seTooltipCache[itemID]
		return cached[1], cached[2], cached[3], cached[4], cached[5]
	end

	local chargesPattern = '^' .. gsub(gsub(ITEM_SPELL_CHARGES_P1, '%%d', '(%%d+)'), '%%%d+%$d', '(%%d+)') .. '$'

	SortBagsTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	SortBagsTooltip:ClearLines()

	if container == BANK_CONTAINER then
		SortBagsTooltip:SetInventoryItem('player', BankButtonIDToInvSlotID(position))
	else
		SortBagsTooltip:SetBagItem(container, position)
	end

	local charges, usable, soulbound, quest, conjured
	for i = 1, SortBagsTooltip:NumLines() do
		local text = getglobal('SortBagsTooltipTextLeft' .. i):GetText()

		local _, _, chargeString = strfind(text, chargesPattern)
		if chargeString then
			charges = tonumber(chargeString)
		elseif strfind(text, '^' .. ITEM_SPELL_TRIGGER_ONUSE) then
			usable = true
		elseif text == ITEM_SOULBOUND then
			soulbound = true
		elseif text == ITEM_BIND_QUEST then
			quest = true
		elseif text == ITEM_CONJURED then
			conjured = true
		end
	end

	local result = {charges or 1, usable, soulbound, quest, conjured}
	if itemID then
		seTooltipCache[itemID] = result
	end
	return result[1], result[2], result[3], result[4], result[5]
end

-- 整理（移植自 OneBag 原版）：一轮扫描所有目标槽位，每个都尝试移动一次；
-- Move 只在源/目标均未锁定时执行，锁定的槽位直接跳过（不卡死）。
-- 每轮可移动多个物品，配合 defaultDelay 间隔，速度与防锁死取得平衡。
-- 返回 true 表示本轮所有目标均已满足（排序完成）。
SE_Sort = function()
	local complete = true

	for _, dst in seModel do
		if dst.targetItem and (dst.item ~= dst.targetItem or dst.count < dst.targetCount) then
			complete = false

			local sources, rank = {}, {}

			for _, src in seModel do
				if src.item == dst.targetItem
					and src ~= dst
					and not (dst.item and src.class and src.class ~= seItemClasses[dst.item])
					and not (src.targetItem and src.item == src.targetItem and src.count <= src.targetCount)
				then
					rank[src] = abs(src.count - dst.targetCount + (dst.item == dst.targetItem and dst.count or 0))
					tinsert(sources, src)
				end
			end

			sort(sources, function(a, b) return rank[a] < rank[b] end)

			for _, src in sources do
				if SE_Move(src, dst) then
					break
				end
			end
		end
	end

	return complete
end

-- 堆叠（移植自 OneBag 原版）：一轮扫描所有可堆叠的源/目标，合并相邻同类堆叠。
SE_Stack = function()
	for _, src in seModel do
		if src.item and src.count < seItemStacks[src.item] and src.item ~= src.targetItem then
			for _, dst in seModel do
				if dst ~= src and dst.item and dst.item == src.item and dst.count < seItemStacks[dst.item] and dst.item ~= dst.targetItem then
					SE_Move(src, dst)
				end
			end
		end
	end
end

do
	local counts
	-- 是否把"非整堆的余数（小堆）"分配到先处理的槽位。
	-- 由 reverseStackSort 设置决定，并与整理方向（SE_REVERSE）结合，
	-- 保证开关在左/右键两种方向下结果一致：
	--   反向堆叠 OFF → 大堆在前（先放整堆，余数小堆放后面）
	--   反向堆叠 ON  → 小堆在前（先放余数，整堆放后面）
	-- 判定：remainderFirst = (reverseStackSort == SE_REVERSE)
	local seRemainderFirst = false

	local function insert(t, v)
		if SE_REVERSE then
			tinsert(t, v)
		else
			tinsert(t, 1, v)
		end
	end

	local function assign(slot, item)
		if counts[item] > 0 then
			local count
			if seRemainderFirst and mod(counts[item], seItemStacks[item]) ~= 0 then
				count = mod(counts[item], seItemStacks[item])
			else
				count = min(counts[item], seItemStacks[item])
			end
			slot.targetItem = item
			slot.targetCount = count
			counts[item] = counts[item] - count
			return true
		end
	end

	SE_Initialize = function()
		seModel, counts, seItemStacks, seItemClasses, seItemSortKeys = {}, {}, {}, {}, {}

		-- 读取"反向堆叠排序"设置，计算本次整理的余数优先标志。
		-- SE_REVERSE 取值为 true/nil，统一转布尔后参与同或判定。
		local reverseStackSort = false
		if addon.Modules and addon.Modules.DB then
			if addon.Modules.DB:GetSetting("reverseStackSort") == true then
				reverseStackSort = true
			end
		end
		seRemainderFirst = (reverseStackSort == (SE_REVERSE == true))

		for _, container in SE_CONTAINERS do
			local class = SE_ContainerClass(container)
			for position = 1, GetContainerNumSlots(container) do
				local slot = {container=container, position=position, class=class}
				local item = SE_Item(container, position)
				if item then
					local _, countOrCharges = GetContainerItemInfo(container, position)
					local count = countOrCharges
					if SetAutoloot and countOrCharges < 0 then count = 1 end
					slot.item = item
					slot.count = count
					counts[item] = (counts[item] or 0) + count
				end
				insert(seModel, slot)
			end
		end

		local free = {}
		for item, count in counts do
			local stacks = ceil(count / seItemStacks[item])
			free[item] = stacks
			if seItemClasses[item] then
				free[seItemClasses[item]] = (free[seItemClasses[item]] or 0) + stacks
			end
		end
		for _, slot in seModel do
			if slot.class and free[slot.class] then
				free[slot.class] = free[slot.class] - 1
			end
		end

		local items = {}
		for item in counts do
			tinsert(items, item)
		end
		sort(items, function(a, b) return SE_LT(seItemSortKeys[a], seItemSortKeys[b]) end)

		for _, slot in seModel do
			if slot.class then
				for _, item in items do
					if seItemClasses[item] == slot.class and assign(slot, item) then
						break
					end
				end
			else
				for _, item in items do
					if (not seItemClasses[item] or free[seItemClasses[item]] > 0) and assign(slot, item) then
						if seItemClasses[item] then
							free[seItemClasses[item]] = free[seItemClasses[item]] - 1
						end
						break
					end
				end
			end
		end
	end
end

SE_ContainerClass = function(container)
	if container ~= 0 and container ~= BANK_CONTAINER then
		local name = GetBagName(container)
		if name then
			for class, info in SE_CLASSES do
				for _, itemID in info.containers do
					if name == SE_GetItemInfoCached(itemID) then
						return class
					end
				end
			end
		end
	end
end

local seItemInfoCache = {}
SE_GetItemInfoCached = function(id)
	id = tonumber(id)
	if not id then return nil end
	local cached = seItemInfoCache[id]
	if cached then
		return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6], cached[7], cached[8], cached[9]
	end
	local name, link, quality, level, itemType, subType, count, slot, texture = GetItemInfo(id)
	if name then
		seItemInfoCache[id] = {name, link, quality, level, itemType, subType, count, slot, texture}
	end
	return name, link, quality, level, itemType, subType, count, slot, texture
end

SE_Item = function(container, position)
	local link = GetContainerItemLink(container, position)
	if link then
		local _, _, itemID, enchantID, suffixID, uniqueID = strfind(link, 'item:(%d+):(%d*):(%d*):(%d*)')
		itemID = tonumber(itemID)
		local _, _, quality, _, type, subType, stack, invType = SE_GetItemInfoCached(itemID)
		local charges, usable, soulbound, quest, conjured = SE_TooltipInfo(itemID, container, position)

		local sortKey = {}

		if itemID == 6948 then
			tinsert(sortKey, 1)
		elseif SE_MOUNT[itemID] then
			tinsert(sortKey, 2)
		elseif SE_SPECIAL[itemID] then
			tinsert(sortKey, 3)
		elseif SE_KEY[itemID] then
			tinsert(sortKey, 4)
		elseif SE_TOOL[itemID] then
			tinsert(sortKey, 5)
		elseif itemID == 6265 then
			tinsert(sortKey, 14)
		elseif conjured then
			tinsert(sortKey, 15)
		elseif soulbound then
			tinsert(sortKey, 6)
		elseif SE_ENCHANTING[itemID] then
			tinsert(sortKey, 7)
		elseif type == SE_ITEM_TYPES[9] then
			tinsert(sortKey, 8)
		elseif quest then
			tinsert(sortKey, 10)
		elseif usable and type ~= SE_ITEM_TYPES[1] and type ~= SE_ITEM_TYPES[2] and type ~= SE_ITEM_TYPES[8] or type == SE_ITEM_TYPES[4] then
			tinsert(sortKey, 9)
		elseif quality > 1 then
			tinsert(sortKey, 11)
		elseif quality == 1 then
			tinsert(sortKey, 12)
		elseif quality == 0 then
			tinsert(sortKey, 13)
		end

		tinsert(sortKey, SE_ItemTypeKey(type))
		tinsert(sortKey, SE_ItemInvTypeKey(type, subType, invType))
		tinsert(sortKey, SE_ItemSubTypeKey(type, subType))
		tinsert(sortKey, -quality)
		tinsert(sortKey, itemID)
		tinsert(sortKey, (SE_REVERSE and 1 or -1) * charges)
		tinsert(sortKey, suffixID)
		tinsert(sortKey, enchantID)
		tinsert(sortKey, uniqueID)

		local key = format('%s:%s:%s:%s:%s:%s', itemID, enchantID, suffixID, uniqueID, charges, (soulbound and 1 or 0))

		seItemStacks[key] = stack
		seItemSortKeys[key] = sortKey

		for class, info in SE_CLASSES do
			if info.items[itemID] then
				seItemClasses[key] = class
				break
			end
		end

		return key
	end
end

-- 统一入口：整理背包/银行（含确认对话框）
function SortEngine:CleanUp(containers)
	if self.sortingInProgress then
		addon:Print(GudaBag.L["Sorting already in progress, please wait..."])
		return false
	end
	if containers == 'bank' then
		if not addon.Modules.BankScanner or not addon.Modules.BankScanner:IsBankOpen() then
			addon:Print(GudaBag.L["Bank must be open to sort!"])
			return false
		end
		SE_CONTAINERS = {-1, 5, 6, 7, 8, 9, 10}
	else
		SE_CONTAINERS = {0, 1, 2, 3, 4}
	end
	-- 记录本次排序目标，供 SE_Start/finishSort 决定隐藏/恢复哪个框架的按钮
	self.currentTarget = containers
	SE_REVERSE = GudaBag.SortBagsRightToLeft
	local typeText = (containers == "bags") and "背包" or "银行"
	StaticPopup_Show("SORT_BAGS_CONFIRM", typeText)
	return true
end

-- 对外兼容：整理背包（确认后执行）
function SortEngine:SortBags()
	return self:CleanUp('bags')
end

-- 对外兼容：整理银行（确认后执行）
function SortEngine:SortBank()
	return self:CleanUp('bank')
end

-- 对外兼容：ExecuteSort 转发到 OneBag 风格整理。
-- 现有调用方传入 sortFunction/analyzeFunction/updateFrame/sortType/mouseButton，
-- 这里忽略旧算法参数，统一走 OneBag 排序（含确认对话框）。
-- mouseButton：LeftButton=正序，RightButton=倒序（写入 GudaBag.SortBagsRightToLeft）
function SortEngine:ExecuteSort(sortFunction, analyzeFunction, updateFrame, sortType, mouseButton)
	local target = (sortType == "bank") and 'bank' or 'bags'
	GudaBag.SortBagsRightToLeft = (mouseButton == "RightButton") and true or nil
	return self:CleanUp(target)
end
