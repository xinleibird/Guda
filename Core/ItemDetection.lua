-- Guda 物品检测
-- 集中的物品属性检测，带缓存
-- 使用方：CategoryManager、SortEngine、QuestItemBar、ItemButton、BagFrame、BankFrame

local addon = Guda

local ItemDetection = {}
addon.Modules.ItemDetection = ItemDetection

--=====================================================
-- 检测结果缓存
-- 缓存工具提示扫描结果，避免重复扫描
--=====================================================
local detectionCache = {}
local chargesCache = {}  -- 以 "bagID:slotID" 为键（充能次数因槽位而异，而非因链接而异）
local cacheHits = 0
local cacheMisses = 0

-- 清空整个检测缓存（谨慎使用——仅用于重大事件）
-- 对于简单的物品移动，使用 InvalidateItem() 或完全不做失效处理
function ItemDetection:ClearCache()
    detectionCache = {}
    chargesCache = {}
    cacheHits = 0
    cacheMisses = 0
end

-- 使缓存中某个特定物品失效（按 itemLink）
-- 当某个物品的属性可能发生变化时使用
function ItemDetection:InvalidateItem(itemLink)
    if itemLink then
        detectionCache[itemLink] = nil
    end
end

-- 使多个物品从缓存中失效
-- 用于批量操作
function ItemDetection:InvalidateItems(itemLinks)
    if itemLinks then
        for _, link in ipairs(itemLinks) do
            if link then
                detectionCache[link] = nil
            end
        end
    end
end

-- 检查某个物品是否已有缓存数据（用于调试）
function ItemDetection:IsCached(itemLink)
    return itemLink and detectionCache[itemLink] ~= nil
end

-- 获取缓存统计信息
function ItemDetection:GetCacheStats()
    local total = cacheHits + cacheMisses
    local hitRate = total > 0 and (cacheHits / total * 100) or 0
    local size = 0
    for _ in pairs(detectionCache) do size = size + 1 end
    return {
        hits = cacheHits,
        misses = cacheMisses,
        total = total,
        hitRate = hitRate,
        size = size,
    }
end

-- 生成物品的缓存键
local function GetCacheKey(itemLink)
    if not itemLink then return nil end
    return itemLink
end

--=====================================================
-- 工具提示扫描辅助
-- 使用 Utils 模块共享的工具提示
--=====================================================

-- 扫描工具提示并返回所有文本行
local function ScanTooltipLines(bagID, slotID, itemLink)
    -- 使用来自 Utils 模块的共享工具提示
    local tooltip, tooltipName = addon.Modules.Utils:GetScanTooltip()

    -- 确保每次扫描前设置工具提示的拥有者
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()

    -- 辅助函数：安全调用 SetHyperlink（可能因 "Unknown link type" 而失败）
    local function SafeSetHyperlink(tip, link)
        if not link then return false end
        -- 仅提取 item:XXXX 部分用于 SetHyperlink
        local _, _, itemString = string.find(link, "|H(item:[^|]+)|h")
        if itemString then
            local success = pcall(function() tip:SetHyperlink(itemString) end)
            return success
        end
        return false
    end

    -- 根据已有信息设置工具提示
    if bagID and slotID then
        if bagID == -1 then
            -- 银行主背包：SetInventoryItem 不适用于银行槽位
            -- 改用 SetHyperlink 配合物品链接
            if not SafeSetHyperlink(tooltip, itemLink) then
                return {}
            end
        elseif bagID >= 5 and bagID <= 10 then
            -- 银行背包：先尝试 SetBagItem，它对银行背包应该有效
            tooltip:SetBagItem(bagID, slotID)
        else
            -- 普通背包 (0-4)：SetBagItem 可靠有效
            tooltip:SetBagItem(bagID, slotID)
        end
    elseif itemLink then
        if not SafeSetHyperlink(tooltip, itemLink) then
            return {}
        end
    else
        return {}
    end

    local lines = {}
    local numLines = tooltip:NumLines() or 0

    for i = 1, numLines do
        local leftLine = getglobal(tooltipName .. "TextLeft" .. i)
        local rightLine = getglobal(tooltipName .. "TextRight" .. i)

        local leftText = leftLine and leftLine:GetText() or ""
        local rightText = rightLine and rightLine:GetText() or ""

        -- 获取左侧文本颜色（用于检测黄/绿/红文本）
        local lr, lg, lb, la = 1, 1, 1, 1
        if leftLine and leftLine.GetTextColor then
            lr, lg, lb, la = leftLine:GetTextColor()
        end

        -- 获取右侧文本颜色（用于检测红色需求）
        local rr, rg, rb, ra = 1, 1, 1, 1
        if rightLine and rightLine.GetTextColor then
            rr, rg, rb, ra = rightLine:GetTextColor()
        end

        table.insert(lines, {
            left = leftText,
            right = rightText,
            leftLower = leftText and string.lower(leftText) or "",
            rightLower = rightText and string.lower(rightText) or "",
            r = lr, g = lg, b = lb,
            rightR = rr, rightG = rg, rightB = rb,
        })
    end

    return lines
end

--=====================================================
-- 核心检测函数
--=====================================================

-- 检查物品是否为永久附魔（附魔卷轴/羊皮纸）
local function DetectPermanentEnchant(lines)
    for _, line in ipairs(lines) do
        if GudaBag.MatchAnyPattern(line.leftLower, GudaBag.Patterns.permanentEnchant) then
            return true
        end
    end
    return false
end

-- 检查物品是否为任务物品和/或任务起始物品
local function DetectQuestItem(lines, itemData)
    local isQuestItem = false
    local isQuestStarter = false

    -- 提前退出：排除被 API 误分类的已知非任务物品
    if itemData and itemData.link and addon.Constants and addon.Constants.QUEST_CATEGORY_EXCLUSIONS then
        local _, _, idStr = string.find(itemData.link, "item:(%d+)")
        if idStr then
            local id = tonumber(idStr)
            if id and addon.Constants.QUEST_CATEGORY_EXCLUSIONS[id] then
                return false, false
            end
        end
    end

    -- 首先检查物品类别
    if itemData and itemData.class == "Quest" then
        isQuestItem = true
    end

    -- 扫描工具提示中与任务相关的文本
    for _, line in ipairs(lines) do
        local text = line.leftLower

        -- 任务起始模式（通过 GudaBag.Patterns 实现本地化感知）
        if GudaBag.MatchAnyPattern(text, GudaBag.Patterns.questStarter) then
            isQuestItem = true
            isQuestStarter = true
        end

        -- 任务物品模式（通过 GudaBag.Patterns 实现本地化感知）
        if GudaBag.MatchAnyPattern(text, GudaBag.Patterns.questItem) then
            isQuestItem = true
        end
    end

    return isQuestItem, isQuestStarter
end

-- 检查物品是否为垃圾（灰色或没有特殊属性的白色可装备物品）
local function DetectJunk(lines, itemData)
    if not itemData then return false end

    -- 确保品质是数字
    local quality = tonumber(itemData.quality)
    local itemClass = itemData.class or ""
    local itemSubclass = itemData.subclass or ""
    local itemName = itemData.name or ""
    local itemLink = itemData.link or ""

    -- 投掷武器属于武器，永远不算垃圾——即使是灰色/白色的也一样。
    -- 使用装备槽位标记（与语言无关）和子类，以便在任何客户端上都有效
    -- （zhCN 子类是 投掷武器；enUS 是 Thrown）。
    local equipSlot = itemData.equipSlot or itemData.equipLoc or ""
    if equipSlot == "INVTYPE_THROWN" then
        return false
    end
    local subLower = string.lower(itemSubclass)
    if GudaBag.MatchAnyPattern(subLower, GudaBag.Patterns.thrown) then
        return false
    end

    -- 灰色物品永远算垃圾
    -- 检查品质数值或链接颜色（灰色 = |cff9d9d9d）
    if quality == 0 then
        return true
    end

    -- 回退方案：检查灰色物品的链接颜色
    if itemLink and string.find(itemLink, "|cff9d9d9d") then
        return true
    end

    -- 永远不把已知的专业工具当作垃圾。按物品 ID 检查，以便在任何
    -- 语言环境下有效（下面的英文名称检查在 zhCN 等环境下会失败）。
    if itemData.link and addon.Constants and addon.Constants.PROFESSION_TOOL_IDS then
        local _, _, idStr = string.find(itemData.link, "item:(%d+)")
        if idStr and addon.Constants.PROFESSION_TOOL_IDS[tonumber(idStr)] then
            return false
        end
    end

    -- 如果品质仍为 nil，尝试从链接颜色推断
    if quality == nil then
        if string.find(itemLink, "|cffffffff") then
            quality = 1  -- 白色
        else
            return false  -- 品质未知，不标记为垃圾
        end
    end

    -- 白色可装备物品可能是垃圾（仅在启用 whiteItemsJunk 设置时）
    local whiteItemsJunk = false
    if addon and addon.Modules and addon.Modules.DB then
        whiteItemsJunk = addon.Modules.DB:GetSetting("whiteItemsJunk")
    end
    if quality == 1 and whiteItemsJunk and (itemClass == "Weapon" or itemClass == "Armor") then
        -- 排除项：饰品、戒指、项链、战袍、衬衫（本地化感知）
        local subLower = string.lower(itemSubclass)
        if GudaBag.MatchAnyPattern(subLower, GudaBag.Patterns.trinketEtc) then
            return false
        end

        -- 按常见名称检查专业工具（本地化感知）
        local nameLower = string.lower(itemName)
        if GudaBag.MatchAnyPattern(nameLower, GudaBag.Patterns.toolNames) then
            return false
        end

        -- 检查专业工具子类（本地化感知）
        if GudaBag.MatchAnyPattern(subLower, GudaBag.Patterns.toolSubtypes) then
            return false
        end

        -- 检查工具提示中的特殊文本（Use:、Equip:、绿色文本）
        for _, line in ipairs(lines) do
            local text = line.leftLower

            -- 黄色文本（Use:、Equip:）
            if line.r and line.g and line.b then
                local isYellow = (line.r > 0.9 and line.g > 0.75 and line.b < 0.2)
                local isGreen = (line.r < 0.2 and line.g > 0.9 and line.b < 0.2)

                -- 本地化感知的 "Use:"/"Equip:"（英文）或 "使用"/"装备"（zhCN）
                if isYellow and GudaBag.MatchAnyPattern(text, GudaBag.Patterns.useEquip) then
                    return false
                end

                if isGreen then
                    return false
                end
            end
        end

        -- 没有特殊属性的白色可装备物品 = 垃圾
        return true
    end

    return false
end

-- 检查物品是否可用于任务（具有与任务相关的黄色 "Use:" 文本）
local function DetectQuestUsable(lines)
    for _, line in ipairs(lines) do
        -- 检查黄色 "Use:" 文本
        if line.r and line.g and line.b then
            local isYellow = (line.r > 0.9 and line.g > 0.75 and line.b < 0.2)
            if isYellow and line.leftLower and GudaBag.MatchAnyPattern(line.leftLower, GudaBag.Patterns.questUsable) then
                return true
            end
            -- 同时检查绿色 "Use:" 文本（某些任务物品有绿色使用文本）
            local isGreen = (line.r < 0.3 and line.g > 0.9 and line.b < 0.3)
            if isGreen and line.leftLower and GudaBag.MatchAnyPattern(line.leftLower, GudaBag.Patterns.questUsable) then
                return true
            end
        end
    end
    return false
end

-- 调试函数：输出物品的工具提示行
-- 用法：/script Guda.Modules.ItemDetection:DebugTooltip(bagID, slotID)
function ItemDetection:DebugTooltip(bagID, slotID)
    local itemLink = GetContainerItemLink(bagID, slotID)
    if not itemLink then
        addon:Print("No item at " .. bagID .. ":" .. slotID)
        return
    end

    addon:Print("=== Tooltip Debug for " .. bagID .. ":" .. slotID .. " ===")
    local lines = ScanTooltipLines(bagID, slotID, itemLink)
    addon:Print("Total lines: " .. table.getn(lines))

    for i, line in ipairs(lines) do
        local text = line.left or "(no text)"
        local r, g, b = line.r or 0, line.g or 0, line.b or 0
        addon:Print(string.format("[%d] r=%.2f g=%.2f b=%.2f: %s", i, r, g, b, text))
    end
    addon:Print("=== End Tooltip Debug ===")
end

-- 耐久度模式，用于过滤损坏物品的红色文本
local durabilityPattern = DURABILITY_TEMPLATE and string.gsub(DURABILITY_TEMPLATE, "%%d", "%%d+") or nil

-- 检查文本颜色是否为红色（无法使用的要求）
local function IsRedColor(r, g, b)
    if not r or not g or not b then return false end
    -- RED_FONT_COLOR 通常为 (1.0, 0.1, 0.1)
    local dr = math.abs(r - 1.0)
    local dg = math.abs(g - 0.125)
    local db = math.abs(b - 0.125)
    return (dr < 0.15 and dg < 0.15 and db < 0.15)
end

-- 检查红色文本是否为真实需求（而非仅仅是加载状态或描述性文字）
-- 如果文本看起来是实际未满足的要求，则返回 true
local function IsRequirementText(text)
    if not text or text == "" then return false end
    local lower = string.lower(text)

    -- 已知的需求模式（通过 GudaBag.Patterns 实现本地化感知）
    if GudaBag.MatchAnyPattern(lower, GudaBag.Patterns.requirement) then return true end

    -- 职业名称（显示为红色时表示职业限制）
    if GudaBag.MatchAnyPattern(lower, GudaBag.Patterns.classNames) then return true end

    -- 种族名称（显示为红色时表示种族限制）
    if GudaBag.MatchAnyPattern(lower, GudaBag.Patterns.raceNames) then return true end

    return false
end

-- 检查物品是否无法使用（具有表示未满足要求的红色文本）
-- 排除：耐久度行、物品名称（第 1 行）、非需求文本
local function DetectUnusable(lines)
    local numLines = table.getn(lines)

    -- 如果工具提示行数太少，数据可能尚未加载——保持保守
    if numLines < 2 then
        return false
    end

    -- 从第 2 行开始，跳过物品名称（第 1 行）
    -- 当数据未完全加载时，物品名称可能显示为红色
    for i = 2, numLines do
        local line = lines[i]
        if line and line.r and line.g and line.b then
            -- 检查红色文本（未满足的要求）
            local isRed = IsRedColor(line.r, line.g, line.b) or
                          (line.r > 0.85 and line.g < 0.3 and line.b < 0.3)

            if isRed then
                local text = line.left or ""

                -- 忽略耐久度行（损坏的物品）
                if durabilityPattern and string.find(text, durabilityPattern) then
                    -- 跳过耐久度
                -- 仅当文本看起来像需求时才计为无法使用
                elseif IsRequirementText(text) then
                    return true
                end
                -- 如果为红色但不是需求模式，则忽略（可能是描述性文字或加载状态）
            end
        end

        -- 同时检查右侧列（某些需求出现在那里，例如 "Warrior" 职业）
        if line and line.rightR and line.rightG and line.rightB then
            local isRed = IsRedColor(line.rightR, line.rightG, line.rightB) or
                          (line.rightR > 0.85 and line.rightG < 0.3 and line.rightB < 0.3)

            if isRed then
                local text = line.right or ""
                if durabilityPattern and string.find(text, durabilityPattern) then
                    -- 跳过耐久度
                elseif IsRequirementText(text) then
                    return true
                end
            end
        end
    end
    return false
end

-- 检测物品充能次数（例如 Wizard Oil、Mana Oil 上的 "5 Charges" / "使用次数：5"）
local function DetectCharges(lines)
    for _, line in ipairs(lines) do
        -- 充能次数可能出现在工具提示的左列或右列，取决于语言环境
        for _, s in ipairs({ line.leftLower, line.rightLower }) do
            if s and s ~= "" then
                local num = GudaBag.MatchNumberPattern(s, GudaBag.Patterns.charges)
                if num then return num end
            end
        end
    end
    return nil
end

--=====================================================
-- 公共 API - 缓存检测
--=====================================================

-- 一次性获取所有物品属性（缓存）
-- 返回：{ isQuestItem, isQuestStarter, isQuestUsable, isJunk, isPermanentEnchant, isUnusable }
function ItemDetection:GetItemProperties(itemData, bagID, slotID)
    if not itemData then
        return {
            isQuestItem = false,
            isQuestStarter = false,
            isQuestUsable = false,
            isJunk = false,
            isPermanentEnchant = false,
            isUnusable = false,
        }
    end

    local itemLink = itemData.link
    local cacheKey = GetCacheKey(itemLink)

    -- 检查缓存
    if cacheKey and detectionCache[cacheKey] then
        cacheHits = cacheHits + 1
        return detectionCache[cacheKey]
    end
    cacheMisses = cacheMisses + 1

    -- 扫描一次工具提示
    local lines = ScanTooltipLines(bagID, slotID, itemLink)
    local numLines = table.getn(lines)

    -- 调试：记录工具提示扫描失败的情况
    if numLines == 0 and addon.DEBUG then
        addon:Debug("ItemDetection: No tooltip lines for %s (bag=%s, slot=%s)",
            tostring(itemData.name or itemLink), tostring(bagID), tostring(slotID))
    end

    -- 检查工具提示数据是否完整
    -- 正常的物品工具提示应至少有 2 行（名称 + 其他内容）
    -- 如果工具提示太短，数据可能尚未完全加载——不要缓存
    local tooltipLooksComplete = (numLines >= 2)

    -- 检测所有属性
    local isPermanentEnchant = DetectPermanentEnchant(lines)
    local isQuestItem, isQuestStarter = DetectQuestItem(lines, itemData)
    local isQuestUsable = DetectQuestUsable(lines)
    local isJunk = DetectJunk(lines, itemData)
    local isUnusable = DetectUnusable(lines)

    -- 在属性扫描期间将充能次数存入按槽位的缓存（避免重复扫描工具提示）
    if bagID and slotID and tooltipLooksComplete then
        chargesCache[bagID .. ":" .. slotID] = DetectCharges(lines)
    end

    -- 调试：记录灰色物品的垃圾检测
    if addon.DEBUG then
        local quality = tonumber(itemData.quality)
        local linkHasGray = itemLink and string.find(itemLink, "|cff9d9d9d")
        if quality == 0 or linkHasGray then
            addon:Debug("ItemDetection JUNK: %s quality=%s linkGray=%s isJunk=%s",
                tostring(itemData.name), tostring(quality), tostring(linkHasGray), tostring(isJunk))
        end
    end

    -- 永久附魔不是任务物品（即使被归类为 Quest 类别）
    if isPermanentEnchant then
        isQuestItem = false
        isQuestStarter = false
        isQuestUsable = false
    end

    local result = {
        isQuestItem = isQuestItem,
        isQuestStarter = isQuestStarter,
        isQuestUsable = isQuestUsable,
        isJunk = isJunk,
        isPermanentEnchant = isPermanentEnchant,
        isUnusable = isUnusable,
    }

    -- 仅当工具提示数据看起来完整时才缓存结果
    -- 这可以避免缓存来自部分加载的物品数据而导致的错误结果
    if cacheKey and tooltipLooksComplete then
        detectionCache[cacheKey] = result
    end

    return result
end

-- 单项属性检查的便捷函数
function ItemDetection:IsQuestItem(itemData, bagID, slotID)
    local props = self:GetItemProperties(itemData, bagID, slotID)
    return props.isQuestItem, props.isQuestStarter
end

function ItemDetection:IsQuestStarter(itemData, bagID, slotID)
    local props = self:GetItemProperties(itemData, bagID, slotID)
    return props.isQuestStarter
end

function ItemDetection:IsQuestUsable(itemData, bagID, slotID)
    local props = self:GetItemProperties(itemData, bagID, slotID)
    return props.isQuestUsable
end

function ItemDetection:IsJunk(itemData, bagID, slotID)
    local props = self:GetItemProperties(itemData, bagID, slotID)
    return props.isJunk
end

function ItemDetection:IsPermanentEnchant(itemData, bagID, slotID)
    local props = self:GetItemProperties(itemData, bagID, slotID)
    return props.isPermanentEnchant
end

function ItemDetection:IsUnusable(itemData, bagID, slotID)
    local props = self:GetItemProperties(itemData, bagID, slotID)
    return props.isUnusable
end

-- 仅缓存查找。缓存命中时返回 true/false，未知时返回 nil
-- （不扫描工具提示，无副作用）。让布局路径在冷缓存时跳过染色，
-- 而无需阻塞在约 80 次工具提示扫描上。
function ItemDetection:IsUnusableCached(itemData)
    if not itemData or not itemData.link then return nil end
    local cacheKey = GetCacheKey(itemData.link)
    if not cacheKey then return nil end
    local props = detectionCache[cacheKey]
    if not props then return nil end
    return props.isUnusable
end

function ItemDetection:GetCharges(itemData, bagID, slotID)
    if not bagID or not slotID then return nil end
    local slotKey = bagID .. ":" .. slotID
    -- 如果可用，使用按槽位的缓存
    if chargesCache[slotKey] ~= nil then
        return chargesCache[slotKey]
    end
    -- 否则重新扫描工具提示
    local itemLink = itemData and itemData.link
    local lines = ScanTooltipLines(bagID, slotID, itemLink)
    local charges = DetectCharges(lines)
    if table.getn(lines) >= 2 then
        chargesCache[slotKey] = charges
    end
    return charges
end

-- 使特定背包的充能缓存失效（在 BAG_UPDATE 时调用）
function ItemDetection:InvalidateCharges(bagID)
    if bagID then
        local prefix = bagID .. ":"
        for key in pairs(chargesCache) do
            if string.find(key, "^" .. prefix) then
                chargesCache[key] = nil
            end
        end
    else
        chargesCache = {}
    end
end

--=====================================================
-- 初始化
--=====================================================

function ItemDetection:Initialize()
    -- 进入世界时清空缓存（角色切换）
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        self:ClearCache()
    end, "ItemDetection")

    -- 背包更新时使充能缓存失效（充能次数因槽位而异）
    addon.Modules.Events:Register("BAG_UPDATE", function()
        self:InvalidateCharges(arg1)
    end, "ItemDetection_Charges")

    addon:Debug("ItemDetection module initialized")
end
