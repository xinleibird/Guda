-- Guda 实用工具函数

local addon = Guda

local Utils = {}
addon.Modules.Utils = Utils

--=============================================================================
-- 计时器框架池（防止临时计时器造成内存泄漏）
-- 全局函数，方便所有模块使用
--=============================================================================
local timerPool = {}
local TIMER_POOL_MAX = 10  -- 限制池大小，防止无限制增长

function GudaBag.ScheduleTimer(delay, callback)
    -- 尝试从池中获取一个框架
    local frame = table.remove(timerPool)
    if not frame then
        frame = CreateFrame("Frame")
    end

    frame.elapsed = 0
    frame.delay = delay
    frame.callback = callback
    frame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= this.delay then
            this:SetScript("OnUpdate", nil)
            this:Hide()
            -- 如果池未满，将框架归还给池
            if table.getn(timerPool) < TIMER_POOL_MAX then
                table.insert(timerPool, this)
            end
            -- 执行回调
            this.callback()
        end
    end)
    frame:Show()
end

--=============================================================================
-- 工具提示扫描缓存
-- 缓存开销较大的工具提示扫描操作的结果
--=============================================================================
local tooltipCache = {
    questItem = {},       -- IsQuestItem 的结果
    specialText = {},     -- HasSpecialTooltipText 的结果
    bindOnEquip = {},     -- IsBindOnEquip 的结果
    bindOnPickup = {},    -- IsBindOnPickup 的结果
    uniqueItem = {},      -- IsUniqueItem 的结果
    restoreTag = {},      -- GetConsumableRestoreTag 的结果
    fullText = {},        -- GetTooltipText 的结果（完整工具提示转小写，用于 ~t: 搜索）
}
local tooltipCacheStats = {
    hits = 0,
    misses = 0,
}

-- 清空所有工具提示缓存
function Utils:ClearTooltipCache()
    tooltipCache.questItem = {}
    tooltipCache.specialText = {}
    tooltipCache.bindOnEquip = {}
    tooltipCache.bindOnPickup = {}
    tooltipCache.uniqueItem = {}
    tooltipCache.restoreTag = {}
    tooltipCache.fullText = {}
    tooltipCacheStats.hits = 0
    tooltipCacheStats.misses = 0
    addon:Debug("Tooltip cache cleared")
end

-- 获取工具提示缓存统计信息
function Utils:GetTooltipCacheStats()
    local total = tooltipCacheStats.hits + tooltipCacheStats.misses
    local hitRate = total > 0 and (tooltipCacheStats.hits / total * 100) or 0
    return {
        hits = tooltipCacheStats.hits,
        misses = tooltipCacheStats.misses,
        total = total,
        hitRate = hitRate,
    }
end

-- 根据物品链接生成缓存键
local function GetTooltipCacheKey(itemLink)
    if not itemLink then return nil end
    -- 从链接中提取物品 ID 以获得稳定的缓存
    local _, _, itemID = string.find(itemLink, "item:(%d+)")
    return itemID
end

--=============================================================================
-- 帧预算系统（受 Baganator 启发的性能优化）
-- 防止任何单个操作造成帧卡顿：当操作超出时间预算时，
-- 将工作分摊到多个帧来执行。
--=============================================================================

-- 帧预算配置
local FRAME_BUDGET_SECONDS = 0.1  -- 每帧 100ms 预算（与 Baganator 相同）
local lastEntryTime = 0
local workQueue = {}
local workQueueFrame = nil
local workQueuePaused = false  -- 为 true 时，新的 QueueWork 调用只入队但不恢复处理

-- 报告我们正在开始工作（在开销大的操作开始时调用）
-- 这会重置帧预算计时器
function Utils:ReportEntry()
    lastEntryTime = GetTime()
end

-- 检查是否已超出帧预算
-- 如果应将剩余工作推迟到下一帧，则返回 true
function Utils:CheckTimeout()
    return (GetTime() - lastEntryTime) > FRAME_BUDGET_SECONDS
end

-- 将工作排入队列，在下一帧执行
-- callback：要调用的函数
-- context：回调的可选上下文/所有者（用于调试/清理）
function Utils:QueueWork(callback, context)
    if type(callback) ~= "function" then
        addon:Error("QueueWork: callback must be a function")
        return
    end

    table.insert(workQueue, {callback = callback, context = context or "unknown"})

    -- 如果处理器框架不存在，则创建工作队列处理器框架
    if not workQueueFrame then
        workQueueFrame = CreateFrame("Frame", "Guda_WorkQueueFrame", UIParent)
        workQueueFrame.elapsed = 0
        workQueueFrame:Hide()

        workQueueFrame:SetScript("OnUpdate", function()
            -- 在帧预算内处理排队的工作
            Utils:ReportEntry()

            local processedCount = 0
            local maxPerFrame = 50  -- 防止无限循环的安全上限

            while table.getn(workQueue) > 0 and processedCount < maxPerFrame do
                -- 检查是否已超出帧预算
                if Utils:CheckTimeout() then
                    -- 仍有工作但已超出预算，继续到下一帧
                    addon:Debug("Frame budget exceeded, deferring %d items to next frame", table.getn(workQueue))
                    return
                end

                local work = table.remove(workQueue, 1)
                if work and work.callback then
                    local success, err = pcall(work.callback)
                    if not success then
                        addon:Error("QueueWork callback error [%s]: %s", tostring(work.context), tostring(err))
                    end
                end
                processedCount = processedCount + 1
            end

            -- 所有工作完成，隐藏框架以停止 OnUpdate
            if table.getn(workQueue) == 0 then
                workQueueFrame:Hide()
            end
        end)
    end

    -- 显示框架以开始处理（除非已暂停——新项目
    -- 留在队列中，调用 ResumeWorkQueue 时会被处理）。
    if not workQueuePaused then
        workQueueFrame:Show()
    end
end

-- 清空所有排队的工作（当框架隐藏时很有用）
function Utils:ClearWorkQueue()
    workQueue = {}
    if workQueueFrame then
        workQueueFrame:Hide()
    end
end

-- 暂停工作队列处理（例如在拖动框架期间）。工作保持排队状态
-- （包括暂停期间通过 QueueWork 入队的项目）；调用 ResumeWorkQueue 来清空。
function Utils:PauseWorkQueue()
    workQueuePaused = true
    if workQueueFrame then
        workQueueFrame:Hide()
    end
end

function Utils:ResumeWorkQueue()
    workQueuePaused = false
    if workQueueFrame and table.getn(workQueue) > 0 then
        workQueueFrame:Show()
    end
end

-- 获取工作队列中的项目数量（用于调试）
function Utils:GetWorkQueueSize()
    return table.getn(workQueue)
end

-- 以批处理方式处理项目，并感知帧预算
-- items：要处理的项目表
-- processor：对每个项目调用的函数(item, index)
-- onComplete：所有项目处理完毕时调用的可选函数
-- batchSize：检查超时前要处理的项目数（可选，默认 10）
function Utils:ProcessWithBudget(items, processor, onComplete, batchSize)
    if not items or table.getn(items) == 0 then
        if onComplete then onComplete() end
        return
    end

    batchSize = batchSize or 10
    local index = 1
    local totalItems = table.getn(items)

    local function processNextBatch()
        Utils:ReportEntry()
        local batchCount = 0

        while index <= totalItems and batchCount < batchSize do
            if Utils:CheckTimeout() then
                -- 超出预算，将续行排入队列
                Utils:QueueWork(processNextBatch, "ProcessWithBudget")
                return
            end

            local item = items[index]
            if item then
                local success, err = pcall(processor, item, index)
                if not success then
                    addon:Error("ProcessWithBudget processor error at index %d: %s", index, tostring(err))
                end
            end

            index = index + 1
            batchCount = batchCount + 1
        end

        -- 检查是否还有更多项目
        if index <= totalItems then
            -- 还有更多项目要处理，将下一批排入队列
            Utils:QueueWork(processNextBatch, "ProcessWithBudget")
        else
            -- 全部完成
            if onComplete then
                local success, err = pcall(onComplete)
                if not success then
                    addon:Error("ProcessWithBudget onComplete error: %s", tostring(err))
                end
            end
        end
    end

    -- 开始处理
    processNextBatch()
end

-- 性能指标跟踪
local performanceStats = {
    budgetExceededCount = 0,
    totalUpdates = 0,
    lastUpdateDuration = 0,
    averageUpdateDuration = 0,
}

-- 获取当前帧预算设置（秒）
function Utils:GetFrameBudget()
    return FRAME_BUDGET_SECONDS
end

-- 设置帧预算（秒，最小 0.016 = 60fps，最大 0.5）
function Utils:SetFrameBudget(seconds)
    if type(seconds) ~= "number" then return end
    FRAME_BUDGET_SECONDS = math.max(0.016, math.min(0.5, seconds))
    addon:Debug("Frame budget set to %.3f seconds", FRAME_BUDGET_SECONDS)
end

-- 记录更新周期结束，用于性能跟踪
function Utils:RecordUpdateEnd()
    local duration = GetTime() - lastEntryTime
    performanceStats.lastUpdateDuration = duration
    performanceStats.totalUpdates = performanceStats.totalUpdates + 1

    -- 更新滚动平均值
    local alpha = 0.1  -- 平滑因子
    performanceStats.averageUpdateDuration = performanceStats.averageUpdateDuration * (1 - alpha) + duration * alpha

    if duration > FRAME_BUDGET_SECONDS then
        performanceStats.budgetExceededCount = performanceStats.budgetExceededCount + 1
    end
end

-- 获取性能统计信息
function Utils:GetPerformanceStats()
    return {
        frameBudget = FRAME_BUDGET_SECONDS,
        lastUpdateDuration = performanceStats.lastUpdateDuration,
        averageUpdateDuration = performanceStats.averageUpdateDuration,
        totalUpdates = performanceStats.totalUpdates,
        budgetExceededCount = performanceStats.budgetExceededCount,
        workQueueSize = table.getn(workQueue),
    }
end

-- 重置性能统计信息
function Utils:ResetPerformanceStats()
    performanceStats.budgetExceededCount = 0
    performanceStats.totalUpdates = 0
    performanceStats.lastUpdateDuration = 0
    performanceStats.averageUpdateDuration = 0
end

-- 打印当前性能统计信息（用于调试）
function Utils:PrintPerformanceStats()
    local stats = self:GetPerformanceStats()
    addon:Print(GudaBag.L["=== Guda Performance Stats ==="])
    addon:Print(GudaBag.L["Frame Budget: %.0fms"], stats.frameBudget * 1000)
    addon:Print(GudaBag.L["Last Update: %.1fms"], stats.lastUpdateDuration * 1000)
    addon:Print("Avg Update: %.1fms", stats.averageUpdateDuration * 1000)
    addon:Print(GudaBag.L["Total Updates: %d"], stats.totalUpdates)
    addon:Print(GudaBag.L["Budget Exceeded: %d times"], stats.budgetExceededCount)
    addon:Print("Work Queue: %d items", stats.workQueueSize)
end

--=============================================================================
-- SafeCall：对 nil 安全的模块方法调用
-- 替代冗长的 nil 检查，例如：
--   if addon and addon.Modules and addon.Modules.Utils and addon.Modules.Utils.Method then
--       return addon.Modules.Utils:Method(arg1, arg2)
--   end
-- 改为：
--   return Utils:SafeCall("Utils", "Method", arg1, arg2)
--=============================================================================

-- 安全地调用模块上的方法，若模块/方法不存在则返回 nil
-- 参数：
--   moduleName：addon.Modules 中的模块名（例如 "Utils"、"DB"、"BagFrame"）
--   methodName：要调用的方法名（例如 "GetQualityColor"、"GetSetting"）
--   ...：传给方法的参数
-- 返回：方法的返回值，若不可调用则返回 nil
function Utils:SafeCall(moduleName, methodName, ...)
    if not addon or not addon.Modules then
        return nil
    end

    local module = addon.Modules[moduleName]
    if not module then
        return nil
    end

    local method = module[methodName]
    if not method or type(method) ~= "function" then
        return nil
    end

    -- 以模块作为 self 调用方法（用于冒号风格调用）
    return method(module, unpack(arg))
end

-- 检查模块方法是否存在而不调用它
function Utils:HasMethod(moduleName, methodName)
    if not addon or not addon.Modules then
        return false
    end

    local module = addon.Modules[moduleName]
    if not module then
        return false
    end

    local method = module[methodName]
    return method ~= nil and type(method) == "function"
end

-- 安全地获取模块引用
function Utils:GetModule(moduleName)
    if not addon or not addon.Modules then
        return nil
    end
    return addon.Modules[moduleName]
end

-- 格式化金钱（铜币转为金币/银币/铜币字符串）- WoW 1.12.1 版本
function Utils:FormatMoney(copper, showZero, useColors)
    if not copper or copper == 0 then
        if useColors then
            return "|cFFFFFFFF" .. "0" .. "|r" .. "|cFFEDA55F" .. "c" .. "|r"
        else
            return "0c"
        end
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(mod(copper, 10000) / 100)
    local bronze = mod(copper, 100)

    local str = ""

    if useColors then
        -- 用于工具提示的彩色版本 - 白色数字，彩色 g/s/c 字母
        if gold > 0 then
            str = str .. "|cFFFFFFFF" .. gold .. "|r" .. "|cFFFFD700" .. "g" .. "|r "
        end
        if silver > 0 or gold > 0 then
            str = str .. "|cFFFFFFFF" .. silver .. "|r" .. "|cFFC7C7CF" .. "s" .. "|r "
        end
        str = str .. "|cFFFFFFFF" .. bronze .. "|r" .. "|cFFEDA55F" .. "c" .. "|r"
    else
        -- 纯文本版本
        if gold > 0 then
            str = str .. gold .. "g "
        end
        if silver > 0 or gold > 0 then
            str = str .. silver .. "s "
        end
        str = str .. bronze .. "c"
    end

    return str
end

-- 获取物品信息并缓存
local itemCache = {}

-- 从 itemLink 中提取 itemID（兼容 Lua 5.0）
-- 返回：数字形式的 itemID，若提取失败则返回 nil
function Utils:ExtractItemID(itemLink)
    if not itemLink then return nil end
    local _, _, itemID = string.find(itemLink, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- 带错误处理的物品信息获取（不缓存）
-- Turtle WoW GetItemInfo 签名：
-- itemName, itemLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice
function Utils:GetItemInfoSafe(itemID)
    if not itemID then
        addon:Debug("GetItemInfoSafe: nil itemID")
        return nil
    end

    local itemName, itemLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice = GetItemInfo(itemID)

    if not itemName then
        addon:Debug("GetItemInfoSafe: GetItemInfo failed for itemID %d", itemID)
        return nil
    end

    -- 将本地化的物品类别规范化为其英文标准形式，以便
    -- 类别规则（存储英文类别名）在任何语言环境下都能匹配。
    itemCategory = self:NormalizeItemClass(itemCategory)

    return itemName, itemLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice
end

-- 带缓存的物品信息获取（向后兼容的封装）
function Utils:GetItemInfo(itemLink)
    if not itemLink then return nil end

    if itemCache[itemLink] then
        return unpack(itemCache[itemLink])
    end

    local itemID = self:ExtractItemID(itemLink)
    if not itemID then return nil end

    local itemName, retLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice = self:GetItemInfoSafe(itemID)

    if itemName then
        itemCache[itemLink] = {itemName, retLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice}
        return itemName, retLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice
    end

    return nil
end

-- 为所有扫描操作创建一个共享工具提示
-- 该工具提示被以下模块使用：Utils、ItemDetection、SortEngine
local scanTooltip = CreateFrame("GameTooltip", "GudaScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
local SCAN_TOOLTIP_NAME = "GudaScanTooltip"

-- 共享扫描工具提示的公共获取函数（供 ItemDetection、SortEngine 使用）
function Utils:GetScanTooltip()
    return scanTooltip, SCAN_TOOLTIP_NAME
end

-- 从邮箱附件获取物品链接（WoW 1.12.1 变通方案）
function Utils:GetInboxItemLink(index, itemIndex)
    -- 先尝试全局函数（如果此服务器/版本上存在）
    if GetInboxItemLink then
        -- Turtle WoW 可能支持 (index, itemIndex) 以处理多个附件
        local link = GetInboxItemLink(index, itemIndex or 1)
        if link then return link end
        
        -- 如果失败，回退到单个参数
        link = GetInboxItemLink(index)
        if link then return link end
    end

    -- 在 1.12.1 中，GameTooltip:GetHyperlink() 不存在。
    -- 让我们尝试使用 GetItemInfo(name) 作为主要方式。
    local name, texture, count, quality = GetInboxItem(index, itemIndex or 1)
    if name then
        local itemName, link = GetItemInfo(name)
        if link then
            return link
        end
    end
    
    return nil
end

-- 获取品质颜色
function Utils:GetQualityColor(quality)
    local color = addon.Constants.QUALITY_COLORS[quality] or addon.Constants.QUALITY_COLORS[1]
    return color.r, color.g, color.b
end

-- 从物品链接的 |cffRRGGBB 前缀中提取 RGB 颜色（标题颜色）
-- 返回 r, g, b（0-1 浮点数），若未找到颜色则返回 nil
function Utils:GetLinkColor(itemLink)
    if not itemLink then return nil end
    -- Lua 5.0：使用带捕获的 string.find 而非 string.match
    local _, _, hex = string.find(itemLink, "|c(%x%x%x%x%x%x%x%x)")
    if not hex then return nil end
    -- hex 是 AARRGGBB
    local r = tonumber(string.sub(hex, 3, 4), 16) / 255
    local g = tonumber(string.sub(hex, 5, 6), 16) / 255
    local b = tonumber(string.sub(hex, 7, 8), 16) / 255
    return r, g, b
end

-- 创建彩色文本
function Utils:ColorText(text, r, g, b)
    local red = math.floor(r * 255)
    local green = math.floor(g * 255)
    local blue = math.floor(b * 255)
    return string.format("|cFF%02X%02X%02X%s|r", red, green, blue, text)
end

-- 深拷贝表
function Utils:DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Utils:DeepCopy(orig_key)] = Utils:DeepCopy(orig_value)
        end
        setmetatable(copy, Utils:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- 职业颜色（在模块级别缓存，避免每次调用都创建表）
local CLASS_COLORS = {
    WARRIOR = {r = 0.78, g = 0.61, b = 0.43},
    PALADIN = {r = 0.96, g = 0.55, b = 0.73},
    HUNTER = {r = 0.67, g = 0.83, b = 0.45},
    ROGUE = {r = 1.00, g = 0.96, b = 0.41},
    PRIEST = {r = 1.00, g = 1.00, b = 1.00},
    SHAMAN = {r = 0.00, g = 0.44, b = 0.87},
    MAGE = {r = 0.41, g = 0.80, b = 0.94},
    WARLOCK = {r = 0.58, g = 0.51, b = 0.79},
    DRUID = {r = 1.00, g = 0.49, b = 0.04},
    _default = {r = 0.5, g = 0.5, b = 0.5},
}

-- 获取职业颜色（使用缓存表）
function Utils:GetClassColor(class)
    return CLASS_COLORS[class] or CLASS_COLORS._default
end

-- 格式化时间差
function Utils:FormatTimeAgo(timestamp)
    local diff = time() - timestamp
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h ago"
    else
        return math.floor(diff / 86400) .. "d ago"
    end
end

-- 创建用于扫描的隐藏工具提示（仅一次）
local function GetScanTooltip()
    return scanTooltip
end

-- 辅助：检查颜色是否为黄/金色（Use:、Equip:、Chance on hit: 效果）
-- WoW 工具提示中的黄色可以有多种色调：
--   金色：RGB ~(1, 0.82, 0) 或 (255, 209, 0)
--   黄色：RGB ~(1, 1, 0)
--   浅金色：RGB ~(1, 0.85, 0.1)
local function IsYellowColor(r, g, b)
    if not r or not g or not b then return false end
    -- 黄/金色：高红 (>0.8)、中高绿 (>0.5)、低蓝 (<0.4)
    return r > 0.8 and g > 0.5 and b < 0.4
end

-- 辅助：检查颜色是否为绿色（套装加成、特殊属性）
-- WoW 工具提示中的绿色通常为 RGB ~(0, 1, 0) 或 (0.12, 1, 0)
local function IsGreenColor(r, g, b)
    if not r or not g or not b then return false end
    -- 绿色：低红 (<0.4)、高绿 (>0.7)、低蓝 (<0.4)
    return r < 0.4 and g > 0.7 and b < 0.4
end

-- 用于特殊文本检测的快速模式查找表（针对 Lua 5.0 优化）
-- 使用基于前缀的查找，避免遍历所有模式
local SPECIAL_TEXT_PREFIXES = {
    ["use"] = true,      -- use:、use :（使用）
    ["equ"] = true,      -- equip:、equip :（装备）
    ["cha"] = true,      -- chance on hit、chance to（命中几率）
    ["inc"] = true,      -- increases（增加）
    ["imp"] = true,      -- improves（提高）
    ["res"] = true,      -- restores、resistance（恢复/抗性）
    ["reg"] = true,      -- regenerate（再生）
    ["gen"] = true,      -- generates（产生）
    ["abs"] = true,      -- absorbs（吸收）
    ["red"] = true,      -- reduces（减少）
    ["gra"] = true,      -- grants（给予）
    ["giv"] = true,      -- gives（给予）
    ["tea"] = true,      -- teaches（教授）
    ["lea"] = true,      -- learn（学习）
    ["cre"] = true,      -- creates（制造）
    ["sum"] = true,      -- summons（召唤）
    ["tel"] = true,      -- teleports（传送）
    ["ope"] = true,      -- opens（打开）
    ["act"] = true,      -- activates（激活）
    ["arm"] = true,      -- armor（护甲）
    ["dam"] = true,      -- damage（伤害）
    ["hea"] = true,      -- healing, health（治疗/生命）
    ["man"] = true,      -- mana（法力）
    ["spi"] = true,      -- spirit（精神）
    ["int"] = true,      -- intellect（智力）
    ["sta"] = true,      -- stamina（耐力）
    ["str"] = true,      -- strength（力量）
    ["agi"] = true,      -- agility（敏捷）
}

-- 前缀匹配后进行验证的完整模式（仅在前缀匹配时检查）
local SPECIAL_TEXT_PATTERNS = {
    "use:", "equip:", "chance on", "chance to",
    "increases", "improves", "restores", "regenerate", "generates",
    "absorbs", "reduces", "grants", "gives", "teaches", "learn",
    "creates", "summons", "teleports", "opens", "activates",
    "resistance", "armor", "damage", "healing", "mana", "health",
    "spirit", "intellect", "stamina", "strength", "agility",
}

-- 快速检查文本是否包含特殊模式（先使用前缀查找）
local function HasSpecialTextPattern(textLower)
    -- 快速前缀检查（3 个字符），避免完整的模式扫描
    local prefix = string.sub(textLower, 1, 3)
    if not SPECIAL_TEXT_PREFIXES[prefix] then
        return false
    end
    -- 前缀匹配——进行完整的模式检查
    for _, pattern in ipairs(SPECIAL_TEXT_PATTERNS) do
        if string.find(textLower, pattern) then
            return true
        end
    end
    return false
end

-- 检查物品的工具提示是否包含黄色或绿色描述文本
-- 这表示物品具有使用效果、装备效果或特殊属性
-- 返回：hasSpecialText（布尔值）、textType（"yellow"、"green" 或 nil）
function Utils:HasSpecialTooltipText(bagID, slotID, itemLink)
    bagID = tonumber(bagID)
    slotID = tonumber(slotID)

    -- 如果未提供，获取物品链接用于缓存键
    local cacheLink = itemLink
    if not cacheLink and bagID and slotID then
        cacheLink = GetContainerItemLink(bagID, slotID)
    end

    -- 先检查缓存
    local cacheKey = GetTooltipCacheKey(cacheLink)
    if cacheKey and tooltipCache.specialText[cacheKey] ~= nil then
        tooltipCacheStats.hits = tooltipCacheStats.hits + 1
        local cached = tooltipCache.specialText[cacheKey]
        return cached.hasSpecial, cached.textType
    end
    tooltipCacheStats.misses = tooltipCacheStats.misses + 1

    local tooltip = GetScanTooltip()
    if not tooltip then return false, nil end

    tooltip:ClearLines()

    -- 将工具提示设置为该物品
    if bagID and slotID then
        tooltip:SetBagItem(bagID, slotID)
    elseif itemLink then
        local _, _, itemString = string.find(itemLink, "(item:%d+:%d+:%d+:%d+)")
        if itemString then
            tooltip:SetHyperlink(itemString)
        else
            return false, nil
        end
    else
        return false, nil
    end

    local numLines = tooltip:NumLines() or 0
    if numLines == 0 then
        -- 缓存否定结果
        if cacheKey then
            tooltipCache.specialText[cacheKey] = { hasSpecial = false, textType = nil }
        end
        return false, nil
    end

    -- 扫描工具提示行，查找黄色或绿色文本
    for i = 2, numLines do  -- 从第 2 行开始（跳过第 1 行的物品名称）
        local leftLine = getglobal("GudaScanTooltipTextLeft" .. i)
        if leftLine and leftLine:IsShown() then
            local text = leftLine:GetText()
            local r, g, b = leftLine:GetTextColor()

            if text and r and g and b then
                local textLower = string.lower(text)

                -- 检查黄色/金色文本（Use:、Equip:、Chance on hit: 等）
                if IsYellowColor(r, g, b) then
                    -- 使用优化的基于前缀的模式检查
                    if HasSpecialTextPattern(textLower) then
                        addon:Debug("HasSpecialTooltipText: YELLOW match in: %s", text)
                        -- 缓存肯定结果
                        if cacheKey then
                            tooltipCache.specialText[cacheKey] = { hasSpecial = true, textType = "yellow" }
                        end
                        return true, "yellow"
                    end
                end

                -- 检查绿色文本（套装加成、附魔、特殊属性）
                -- 绿色文本始终被视为特殊（无需模式检查）
                if IsGreenColor(r, g, b) then
                    addon:Debug("HasSpecialTooltipText: Found GREEN text: %s (r=%.2f g=%.2f b=%.2f)", text, r, g, b)
                    -- 缓存肯定结果
                    if cacheKey then
                        tooltipCache.specialText[cacheKey] = { hasSpecial = true, textType = "green" }
                    end
                    return true, "green"
                end

                -- 同时检查 "Use:" 或 "Equip:"，不论颜色如何（某些物品可能有不同颜色）
                if string.find(textLower, "^use:") or string.find(textLower, "^equip:") then
                    addon:Debug("HasSpecialTooltipText: Found Use/Equip text: %s", text)
                    -- 缓存肯定结果
                    if cacheKey then
                        tooltipCache.specialText[cacheKey] = { hasSpecial = true, textType = "yellow" }
                    end
                    return true, "yellow"
                end
            end
        end

        -- 同时检查工具提示右侧
        local rightLine = getglobal("GudaScanTooltipTextRight" .. i)
        if rightLine and rightLine:IsShown() then
            local text = rightLine:GetText()
            local r, g, b = rightLine:GetTextColor()

            if text and r and g and b then
                if IsYellowColor(r, g, b) or IsGreenColor(r, g, b) then
                    addon:Debug("HasSpecialTooltipText: Found special text (right): %s", text)
                    local textType = IsYellowColor(r, g, b) and "yellow" or "green"
                    -- 缓存肯定结果
                    if cacheKey then
                        tooltipCache.specialText[cacheKey] = { hasSpecial = true, textType = textType }
                    end
                    return true, textType
                end
            end
        end
    end

    -- 缓存否定结果
    if cacheKey then
        tooltipCache.specialText[cacheKey] = { hasSpecial = false, textType = nil }
    end
    return false, nil
end

-- 通过扫描工具提示检查物品是否为任务物品（内部辅助函数）
-- 返回：isQuestItem、isQuestStarter
local function ScanTooltipForQuest(tooltip, tooltipName)
    local isQuestItem = false
    local isQuestStarter = false

    for i = 1, tooltip:NumLines() do
        local line = getglobal(tooltipName .. "TextLeft" .. i)
        if line then
            local text = line:GetText()
            if text then
                local tl = string.lower(text)
                -- 先检查任务起始模式（本地化感知）
                if GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.questStarter) then
                    isQuestItem = true
                    isQuestStarter = true
                    break
                -- 检查常规任务物品模式（本地化感知）
                elseif GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.questItem) or
                       GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.manual) then
                    isQuestItem = true
                    -- 不跳出循环，可能仍会找到任务起始模式
                end
            end
        end
    end

    return isQuestItem, isQuestStarter
end

-- 检查物品是否具有 "Permanently..." 文本（附魔卷轴/羊皮纸）
-- 即使这些物品具有 Quest 类别，也不应被视为任务物品
local function IsPermanentEnchantItem(tooltip, tooltipName)
    if not tooltip then return false end
    local numLines = tooltip:NumLines() or 0
    for i = 1, numLines do
        local line = getglobal(tooltipName .. "TextLeft" .. i)
        if line then
            local text = line:GetText()
            if text then
                local tl = string.lower(text)
                if GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.permanentEnchant) then
                    return true
                end
            end
        end
    end
    return false
end

-- 整合的任务物品检测函数
-- 处理工具提示扫描、类别检查、装备过滤和 QuestItemsDB 查找
-- 参数：
--   bagID, slotID：工具提示扫描所需（其他角色的物品可为 nil）
--   itemData：可选的物品数据表，包含 link、class/category、type 字段
--   isOtherChar：布尔值，检查来自其他角色存档数据的物品时为 true
--   isBank：布尔值，物品在银行中时为 true
-- 返回：isQuestItem（布尔值）、isQuestStarter（布尔值）
function Utils:IsQuestItem(bagID, slotID, itemData, isOtherChar, isBank)
    bagID = tonumber(bagID)
    slotID = tonumber(slotID)

    local isQuestItem = false
    local isQuestStarter = false

    -- 获取物品链接和类别信息
    local itemLink = itemData and itemData.link
    local itemCategory = itemData and (itemData.class or itemData.category) or ""
    local itemType = itemData and itemData.type or ""
    local itemID

    -- 对于当前物品，直接查询链接
    if not isOtherChar and bagID and slotID then
        itemLink = GetContainerItemLink(bagID, slotID)
    end

    if itemLink then
        itemID = self:ExtractItemID(itemLink)
        if itemID then
            local _, _, _, _, cat, typ = self:GetItemInfoSafe(itemID)
            itemCategory = cat or itemCategory
            itemType = typ or itemType
        end
    end

    -- 提前退出：排除 API 误分类为 "Quest" 的已知非任务物品
    if itemID and addon.Constants and addon.Constants.QUEST_CATEGORY_EXCLUSIONS and addon.Constants.QUEST_CATEGORY_EXCLUSIONS[itemID] then
        return false, false
    end

    -- 检查物品是否为装备（除非明确为 Quest 类别，否则不应归类为任务）
    local isEquipment = (itemCategory == "Weapon" or itemCategory == "Armor" or
                         itemType == "Weapon" or itemType == "Armor")
    local isQuestCategory = (itemCategory == "Quest" or itemType == "Quest")

    -- 优先级 1：如果明确归类为 Quest，先检查它是否实际上是附魔物品
    if isQuestCategory then
        -- 检查工具提示中的 "Permanently"（附魔卷轴不应是任务物品）
        if not isOtherChar and bagID and slotID then
            local tooltip = GetScanTooltip()
            tooltip:ClearLines()
            tooltip:SetBagItem(bagID, slotID)
            if IsPermanentEnchantItem(tooltip, "GudaScanTooltip") then
                return false, false  -- 不是任务物品，而是附魔卷轴
            end
            -- 同时扫描任务起始文本
            local _, starterDetected = ScanTooltipForQuest(tooltip, "GudaScanTooltip")
            return true, starterDetected
        end
        return true, false
    end

    -- 优先级 2：对当前角色物品进行工具提示扫描
    if not isOtherChar and bagID and slotID then
        local tooltip = GetScanTooltip()
        tooltip:ClearLines()

        -- 区别处理银行物品
        if isBank and bagID == -1 then
            if tooltip.SetInventoryItem then
                tooltip:SetInventoryItem("player", 39 + slotID)
            else
                tooltip:SetBagItem(bagID, slotID)
            end
        else
            tooltip:SetBagItem(bagID, slotID)
        end

        isQuestItem, isQuestStarter = ScanTooltipForQuest(tooltip, "GudaScanTooltip")

        -- 过滤掉有类似任务文本但未归类为 Quest 的装备
        if isQuestItem and isEquipment and not isQuestCategory then
            isQuestItem = false
            isQuestStarter = false
        end
    end

    -- 优先级 3：检查 QuestItemsDB 中已知的阵营专属任务物品
    if not isQuestItem and itemID and addon.IsQuestItemByID then
        local playerFaction = UnitFactionGroup("player")
        if addon:IsQuestItemByID(itemID, playerFaction) then
            isQuestItem = true
        end
    end

    return isQuestItem, isQuestStarter
end

-- 旧版兼容封装——保持旧函数名可用
function Utils:IsQuestItemTooltip(bagID, slotID)
    local isQuest, _ = self:IsQuestItem(bagID, slotID, nil, false, false)
    return isQuest
end

-- 检查物品的工具提示或链接中是否有灰色标题
function Utils:IsItemGrayTooltip(bagID, slotID, itemLink)
    -- 如果提供了链接，先检查链接（对其他角色同样有效）
    if itemLink and string.find(itemLink, "|cff9d9d9d") then
        return true
    end

    if not bagID or not slotID then return false end

    local tooltip = GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slotID)

    local line = getglobal("GudaScanTooltipTextLeft1")
    if line then
        local text = line:GetText()
        if text then
            -- 粗糙品质的颜色代码是 |cff9d9d9d
            if string.find(text, "|cff9d9d9d") then
                return true
            end
        end
    end
    return false
end

-- 获取背包槽位数量
function Utils:GetBagSlotCount(bagID)
    if bagID == -1 then
        -- 香草版本中银行有 24 个槽位
        return 24
    elseif bagID == -2 then
        -- 钥匙扣 - 香草 WoW 有 12-32 个槽位，视版本而定
        local slots = GetContainerNumSlots(bagID)
        if not slots or slots == 0 then
            -- 回退：香草版本中钥匙扣通常有 12 个槽位
            return 12
        end
        return slots
    else
        return GetContainerNumSlots(bagID) or 0
    end
end

-- 检查背包是否有效
function Utils:IsBagValid(bagID)
    if bagID == 0 or bagID == -1 or bagID == -2 then
        return true
    end
    return GetContainerNumSlots(bagID) and GetContainerNumSlots(bagID) > 0
end

-- 将文本截断到指定长度
function Utils:TruncateText(text, maxLen)
    if not text then return "" end
    if string.len(text) <= maxLen then
        return text
    end
    return string.sub(text, 1, maxLen - 3) .. "..."
end

-- 返回："soul"、"herb"、"enchant"、"quiver"、"ammo" 或 nil
-- 这是整合的背包类型检测函数，带工具提示回退
-- =============================================================================
-- 与语言环境无关的类型解析
-- =============================================================================
-- WoW 的 GetItemInfo 返回本地化的类型/子类型字符串（enUS 为 "Quiver"、
-- zhCN 为 "箭袋" 等）。我们通过查询在每个 WoW 1.12 客户端中都存在的
-- 几个参考 itemID，在运行时解析本地客户端字符串，这样其余代码无需硬编码
-- 即可匹配本地语言。
local localizedBagTypes = {}     -- 小写化的本地化子类型 -> "quiver"/"ammo"/...
local localizedProjectiles = {}  -- 本地化子类型（任意大小写）-> "arrow"/"bullet"
local localizedTypesResolved = false

-- 特定语言环境的子类型字符串位于 Localization.lua（GudaBag.LSubtypes）中。
-- 避免 GetItemInfo 缓存冷启动：查找是纯表读取，首次使用时根据当前
-- 客户端语言环境填充一次（以 enUS 作为回退）。
local function ResolveLocalizedTypes()
    if localizedTypesResolved then return end
    if not GudaBag.LSubtypes then return end
    local clientLocale = (GetLocale and GetLocale()) or "enUS"
    local map = GudaBag.LSubtypes[clientLocale] or GudaBag.LSubtypes.enUS
    local en  = GudaBag.LSubtypes.enUS or {}
    -- 先合并 enUS（这样在不完整语言环境下运行的英文客户端仍能工作），
    -- 然后在上面合并当前语言环境。
    local sources = { en, map }
    for i = 1, 2 do
        local src = sources[i]
        if src then
            if src.quiver  then localizedBagTypes[string.lower(src.quiver)]  = "quiver"  end
            if src.ammo    then localizedBagTypes[string.lower(src.ammo)]    = "ammo"    end
            if src.soul    then localizedBagTypes[string.lower(src.soul)]    = "soul"    end
            if src.herb    then localizedBagTypes[string.lower(src.herb)]    = "herb"    end
            if src.enchant then localizedBagTypes[string.lower(src.enchant)] = "enchant" end
            if src.arrow   then localizedProjectiles[src.arrow]  = "arrow"  end
            if src.bullet  then localizedProjectiles[src.bullet] = "bullet" end
        end
    end
    localizedTypesResolved = true
end

-- 与语言环境无关的物品类别解析（与 ResolveLocalizedTypes 对应）。
-- GetItemInfo 返回本地化的物品类别（TWoW 位置 5），但类别规则存储英文
-- 类别名。我们将客户端的本地化类别字符串解析为其英文标准形式，使匹配
-- 与语言环境无关。
local localizedItemClassToEnglish = {}   -- 小写化的本地化类别 -> 英文
local localizedItemClassResolved = false

local function ResolveLocalizedItemClasses()
    if localizedItemClassResolved then return end
    if not GudaBag.LItemTypes then return end
    local clientLocale = (GetLocale and GetLocale()) or "enUS"
    local map = GudaBag.LItemTypes[clientLocale] or GudaBag.LItemTypes.enUS
    local en  = GudaBag.LItemTypes.enUS or {}
    -- 每个语言环境的子表以 英文 -> 本地化 为键（例如 zhCN：
    -- Weapon = "武器"）。我们需要反向映射：本地化 -> 英文，因此我们
    -- 遍历 (english, localized) 并存储 [localized] = english。
    -- 先合并 enUS（恒等映射，无害），然后合并当前语言环境。
    local sources = { en, map }
    for i = 1, 2 do
        local src = sources[i]
        if src then
            for english, localized in pairs(src) do
                if english and localized then
                    localizedItemClassToEnglish[string.lower(localized)] = english
                end
            end
        end
    end
    localizedItemClassResolved = true
end

-- 将（可能本地化的）物品类别字符串规范化为其英文标准形式。
-- 如果不存在映射，则原样返回原字符串。
function Utils:NormalizeItemClass(localizedClass)
    if not localizedClass or localizedClass == "" then return localizedClass end
    ResolveLocalizedItemClasses()
    return localizedItemClassToEnglish[string.lower(localizedClass)] or localizedClass
end

function Utils:GetSpecializedBagType(bagID)
    -- 跳过背包、银行和钥匙扣
    if bagID == 0 or bagID == -1 or bagID == -2 then
        return nil
    end

    -- 获取背包物品
    local invSlot = ContainerIDToInventoryID(bagID)
    if not invSlot then
        return nil
    end

    local link = GetInventoryItemLink("player", invSlot)
    if not link then
        return nil
    end

    local itemID = self:ExtractItemID(link)

    -- 先尝试 GetItemInfo（可用时更可靠）
    if itemID then
        local _, _, _, _, _, itemType = self:GetItemInfoSafe(itemID)
        if itemType then
            local typeLower = string.lower(itemType)

            -- 与语言环境无关：与已解析的本地客户端字符串匹配
            ResolveLocalizedTypes()
            if localizedBagTypes[typeLower] then
                return localizedBagTypes[typeLower]
            end

            if string.find(typeLower, "soul bag") or string.find(typeLower, "soul pouch") then
                return "soul"
            end
            if string.find(typeLower, "herb bag") then
                return "herb"
            end
            if string.find(typeLower, "enchanting bag") then
                return "enchant"
            end
            if string.find(typeLower, "quiver") then
                return "quiver"
            end
            if string.find(typeLower, "ammo pouch") then
                return "ammo"
            end
        end
    end

    -- 回退：对所有背包类型进行工具提示扫描
    local tooltip = GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetInventoryItem("player", invSlot)

    for i = 1, tooltip:NumLines() do
        local line = getglobal("GudaScanTooltipTextLeft" .. i)
        if line then
            local text = line:GetText()
            if text then
                local textLower = string.lower(text)

                -- 灵魂袋 / 灵魂包
                if string.find(textLower, "soul bag") or string.find(textLower, "soul pouch") or
                   (string.find(textLower, "soul") and (string.find(textLower, "bag") or string.find(textLower, "pouch"))) then
                    return "soul"
                end

                -- 草药袋
                if string.find(textLower, "herb bag") then
                    return "herb"
                end

                -- 附魔袋
                if string.find(textLower, "enchanting bag") then
                    return "enchant"
                end

                -- 箭袋
                if string.find(textLower, "quiver") then
                    return "quiver"
                end

                -- 弹药袋
                if string.find(textLower, "ammo pouch") then
                    return "ammo"
                end
            end
        end
    end

    return nil
end

-- 简单辅助函数，检查背包是否为特定类型
function Utils:IsBagType(bagID, bagType)
    return self:GetSpecializedBagType(bagID) == bagType
end

-- 常见背包类型检查的便捷封装
function Utils:IsAmmoQuiverBag(bagID)
    local bagType = self:GetSpecializedBagType(bagID)
    return bagType == "quiver" or bagType == "ammo"
end

function Utils:IsHerbBag(bagID)
    return self:IsBagType(bagID, "herb")
end

function Utils:IsSoulBag(bagID)
    return self:IsBagType(bagID, "soul")
end

-- 获取容器排序优先级（越高越重要）
function Utils:GetContainerPriority(bagID)
    local bagType = self:GetSpecializedBagType(bagID)
    if bagType == "enchant" then
        return 50
    elseif bagType == "herb" then
        return 45
    elseif bagType == "soul" then
        return 40
    elseif bagType == "quiver" then
        return 30
    elseif bagType == "ammo" then
        return 20
    else
        return 10  -- 普通背包
    end
end

-- 灵魂碎片物品 ID
local SOUL_SHARD_ID = 6265

-- 检查物品是否为灵魂碎片
function Utils:IsSoulShard(itemLink)
    if not itemLink then return false end
    local itemID = self:ExtractItemID(itemLink)
    return itemID == SOUL_SHARD_ID
end

-- 检测消耗品是否具有 'Use: Restores' 或提及 'while eating'/'while drinking'
function Utils:GetConsumableRestoreTag(bagID, slotID, itemLink)
    if not bagID or not slotID then return nil end

    -- 如果未提供，获取物品链接用于缓存键
    local cacheLink = itemLink or GetContainerItemLink(bagID, slotID)

    -- 先检查缓存
    local cacheKey = GetTooltipCacheKey(cacheLink)
    if cacheKey and tooltipCache.restoreTag[cacheKey] ~= nil then
        tooltipCacheStats.hits = tooltipCacheStats.hits + 1
        local cached = tooltipCache.restoreTag[cacheKey]
        -- 如果缓存为 false 则返回 nil，否则返回标记
        return cached ~= false and cached or nil
    end
    tooltipCacheStats.misses = tooltipCacheStats.misses + 1

    local tooltip = GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slotID)
    local tag = nil
    for i = 1, tooltip:NumLines() do
        local line = getglobal("GudaScanTooltipTextLeft" .. i)
        if line then
            local text = line:GetText()
            if text then
                local tl = string.lower(text)
                -- 通过 GudaBag.Patterns 实现本地化感知（英文 "while eating" / 中文 "进食" 等）。
                -- 中文版刻意不匹配单独的 "饮" ——因为 "药水"（potion）中不含
                -- 饮水/喝水，因此药水永远不会被误分类为饮料，而正确地留在消耗品中。
                -- "恢复"覆盖药水/绷带。
                if GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.restoreEat) then
                    tag = "eat"
                    break
                elseif GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.restoreDrink) then
                    tag = "drink"
                    break
                elseif GudaBag.MatchAnyPattern(tl, GudaBag.Patterns.restoreRestore) then
                    tag = "restore"
                end
            end
        end
    end

    -- 缓存结果（nil 变为 false 以用于缓存检查）
    if cacheKey then
        tooltipCache.restoreTag[cacheKey] = tag or false
    end

    return tag
end

-- 将物品的完整工具提示文本作为单个小写字符串返回，行之间用换行分隔。
-- 由 ~t: 关键字搜索过滤器使用——每个会话每个物品扫描一次，按物品 ID
-- 缓存，因此重复搜索无需额外开销。
-- 接受 (bagID, slotID) 用于当前物品，或 (nil, nil, itemLink) 作为
-- 仅链接的回退（例如拍卖行/邮件物品）。
function Utils:GetTooltipText(bagID, slotID, itemLink)
    local cacheLink = itemLink or (bagID and slotID and GetContainerItemLink(bagID, slotID))
    local cacheKey = GetTooltipCacheKey(cacheLink)
    if cacheKey and tooltipCache.fullText[cacheKey] ~= nil then
        tooltipCacheStats.hits = tooltipCacheStats.hits + 1
        local cached = tooltipCache.fullText[cacheKey]
        return (cached ~= false) and cached or nil
    end
    tooltipCacheStats.misses = tooltipCacheStats.misses + 1

    local tooltip = GetScanTooltip()
    tooltip:ClearLines()
    local ok = false
    if bagID and slotID then
        pcall(function() tooltip:SetBagItem(bagID, slotID); ok = true end)
    end
    if not ok and cacheLink then
        local _, _, itemString = string.find(cacheLink, "|H(item:[^|]+)|h")
        if itemString then
            pcall(function() tooltip:SetHyperlink(itemString); ok = true end)
        end
    end
    if not ok then
        if cacheKey then tooltipCache.fullText[cacheKey] = false end
        return nil
    end

    local parts = {}
    local n = tooltip:NumLines() or 0
    for i = 1, n do
        local left = getglobal("GudaScanTooltipTextLeft" .. i)
        local right = getglobal("GudaScanTooltipTextRight" .. i)
        local lt = left and left:GetText() or nil
        local rt = right and right:GetText() or nil
        if lt and lt ~= "" then table.insert(parts, lt) end
        if rt and rt ~= "" then table.insert(parts, rt) end
    end

    -- 不缓存部分数据：香草版本有时在客户端完成加载物品记录之前返回 1 行
    -- 工具提示。2+ 行意味着至少出现了名称 + 一行属性/描述。
    if n < 2 then
        return nil
    end

    local joined = string.lower(table.concat(parts, "\n"))
    if cacheKey then
        tooltipCache.fullText[cacheKey] = joined
    end
    return joined
end

-- 检查物品是否为箭或子弹（用于箭袋路由）。
-- 与语言环境无关：也匹配本地客户端翻译后的子类型字符串，
-- 这些字符串在运行时根据参考香草物品解析。
function Utils:IsArrowOrBullet(itemType)
	if not itemType then return false end
	if itemType == "Arrow" or itemType == "Bullet" then return true end
	ResolveLocalizedTypes()
	return localizedProjectiles[itemType] ~= nil
end

-- 检查物品是否为弹药（任意类型——用于弹药袋）
function Utils:IsAmmo(itemType)
	return self:IsArrowOrBullet(itemType)
end

-- 对给定的物品子类型字符串返回 "arrow"、"bullet" 或 nil。
function Utils:GetProjectileKind(itemType)
	if not itemType then return nil end
	if itemType == "Arrow" then return "arrow" end
	if itemType == "Bullet" then return "bullet" end
	ResolveLocalizedTypes()
	return localizedProjectiles[itemType]
end

-- 获取物品的首选容器类型
-- 返回："soul"、"herb"、"enchant"、"quiver"、"ammo" 或 nil
function Utils:GetItemPreferredContainer(itemLink)
    if not itemLink then return nil end

    -- 先检查灵魂碎片
    if self:IsSoulShard(itemLink) then
        return "soul"
    end

    -- 使用工具函数获取物品信息
    local itemID = self:ExtractItemID(itemLink)
    if not itemID then return nil end

    local itemName, _, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture = self:GetItemInfoSafe(itemID)
    if not itemType then return nil end

    -- 与语言环境无关的投射物路由。不要依赖 itemCategory 字符串进行判断
    -- （它是本地化的）；投射物类型查找已通过运行时解析的参考物品
    -- 覆盖了英文和本地客户端的字符串。
    local projectileKind = self:GetProjectileKind(itemType)
    if projectileKind == "arrow" then
        return "quiver"
    elseif projectileKind == "bullet" then
        return "ammo"
    end

    -- 将草药路由到草药袋（稳健：类别/子类型或贴图模式回退）
    if self:IsHerbItem(itemLink) then
        return "herb"
    end

    -- 将附魔材料路由到附魔袋
    if self:IsEnchantingItem(itemLink) then
        return "enchant"
    end

    return nil
end

-- 共享工具提示扫描逻辑：检查绑定类文本（BoE / BoP）
-- 返回 true/false。patterns 取自 GudaBag.Patterns（enUS + zhCN）。
local function ScanTooltipForBind(bagID, slotID, itemLink, patterns)
    local tooltip = GetScanTooltip()
    if not tooltip then return false end

    tooltip:ClearLines()

    -- 先尝试 SetBagItem（适用于普通背包和打开时的银行）
    tooltip:SetBagItem(bagID, slotID)

    local numLines = tooltip:NumLines()

    -- 如果没有行且我们有 itemLink，尝试使用 itemString 调用 SetHyperlink 作为回退
    if (not numLines or numLines == 0) and itemLink then
        -- 从链接中提取 itemString（格式：item:12345:0:0:0...）
        local _, _, itemString = string.find(itemLink, "(item:%d+:%d+:%d+:%d+)")
        if itemString then
            tooltip:ClearLines()
            tooltip:SetHyperlink(itemString)
            numLines = tooltip:NumLines()
        end
    end

    if not numLines or numLines == 0 then
        return false
    end

    for i = 1, numLines do
        local line = getglobal("GudaScanTooltipTextLeft" .. i)
        if line then
            local text = line:GetText()
            if text and GudaBag.MatchAnyPattern(string.lower(text), patterns) then
                return true
            end
        end
    end

    return false
end

-- 通过扫描工具提示检查物品是否为"装备后绑定"
-- 对于银行物品，使用 itemLink，因为 SetBagItem 可能不适用于银行槽位
function Utils:IsBindOnEquip(bagID, slotID, itemLink)
    if not bagID or not slotID then return false end

    -- 如果未提供，获取物品链接用于缓存键
    local cacheLink = itemLink or GetContainerItemLink(bagID, slotID)

    -- 先检查缓存
    local cacheKey = GetTooltipCacheKey(cacheLink)
    if cacheKey and tooltipCache.bindOnEquip[cacheKey] ~= nil then
        tooltipCacheStats.hits = tooltipCacheStats.hits + 1
        return tooltipCache.bindOnEquip[cacheKey]
    end
    tooltipCacheStats.misses = tooltipCacheStats.misses + 1

    local patterns = GudaBag.Patterns and GudaBag.Patterns.bindOnEquip or { "binds when equipped" }
    local result = ScanTooltipForBind(bagID, slotID, itemLink, patterns)

    if cacheKey then tooltipCache.bindOnEquip[cacheKey] = result end
    return result
end

-- 通过扫描工具提示检查物品是否为"拾取后绑定"
-- 乌龟服团队副本 BoP 装备有 10 分钟可交易宽限期，因此 BoP 分类
-- 有助于快速定位刚拾取到、仍可交易的装备。
function Utils:IsBindOnPickup(bagID, slotID, itemLink)
    if not bagID or not slotID then return false end

    -- 如果未提供，获取物品链接用于缓存键
    local cacheLink = itemLink or GetContainerItemLink(bagID, slotID)

    -- 先检查缓存
    local cacheKey = GetTooltipCacheKey(cacheLink)
    if cacheKey and tooltipCache.bindOnPickup[cacheKey] ~= nil then
        tooltipCacheStats.hits = tooltipCacheStats.hits + 1
        return tooltipCache.bindOnPickup[cacheKey]
    end
    tooltipCacheStats.misses = tooltipCacheStats.misses + 1

    local patterns = GudaBag.Patterns and GudaBag.Patterns.bindOnPickup or { "binds when picked up" }
    local result = ScanTooltipForBind(bagID, slotID, itemLink, patterns)

    if cacheKey then tooltipCache.bindOnPickup[cacheKey] = result end
    return result
end

-- 通过扫描工具提示检查物品是否为"唯一"
function Utils:IsUniqueItem(bagID, slotID, itemLink)
    if not bagID or not slotID then return false end

    -- 如果未提供，获取物品链接用于缓存键
    local cacheLink = itemLink or GetContainerItemLink(bagID, slotID)

    -- 先检查缓存
    local cacheKey = GetTooltipCacheKey(cacheLink)
    if cacheKey and tooltipCache.uniqueItem[cacheKey] ~= nil then
        tooltipCacheStats.hits = tooltipCacheStats.hits + 1
        return tooltipCache.uniqueItem[cacheKey]
    end
    tooltipCacheStats.misses = tooltipCacheStats.misses + 1

    local tooltip = GetScanTooltip()
    if not tooltip then
        if cacheKey then tooltipCache.uniqueItem[cacheKey] = false end
        return false
    end

    tooltip:ClearLines()

    -- 先尝试 SetBagItem（适用于普通背包和打开时的银行）
    tooltip:SetBagItem(bagID, slotID)

    local numLines = tooltip:NumLines()

    -- 如果没有行且我们有 itemLink，尝试使用 itemString 调用 SetHyperlink 作为回退
    if (not numLines or numLines == 0) and itemLink then
        -- 从链接中提取 itemString（格式：item:12345:0:0:0...）
        local _, _, itemString = string.find(itemLink, "(item:%d+:%d+:%d+:%d+)")
        if itemString then
            tooltip:ClearLines()
            tooltip:SetHyperlink(itemString)
            numLines = tooltip:NumLines()
        end
    end

    if not numLines or numLines == 0 then
        if cacheKey then tooltipCache.uniqueItem[cacheKey] = false end
        return false
    end

    -- 检查工具提示行中的 "Unique"（但不含 "Unique-Equipped"）
    for i = 1, numLines do
        local line = getglobal("GudaScanTooltipTextLeft" .. i)
        if line then
            local text = line:GetText()
            if text then
                local textLower = string.lower(text)
                -- 匹配 "unique" 但不匹配 "unique-equipped"
                if textLower == "unique" or string.find(textLower, "^unique$") or string.find(textLower, "^unique%s") then
                    if cacheKey then tooltipCache.uniqueItem[cacheKey] = true end
                    return true
                end
            end
        end
    end

    if cacheKey then tooltipCache.uniqueItem[cacheKey] = false end
    return false
end

-- 检查物品是否为装备（护甲、武器或其他可装备物品）
-- 返回：如果是装备则为 true，否则为 false
function Utils:IsEquipment(itemLink)
	if not itemLink then return false end

	local itemID = self:ExtractItemID(itemLink)
	if not itemID then return false end

	local itemName, _, itemRarity, itemLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc = self:GetItemInfoSafe(itemID)

	-- 检查物品是否有装备位置（最可靠的方法）
	if itemEquipLoc and itemEquipLoc ~= "" and itemEquipLoc ~= "INVTYPE_BAG" then
		return true
	end

	-- 回退：检查类别（以防 itemEquipLoc 未设置）
	if itemCategory then
		local categoryLower = string.lower(itemCategory)
		if categoryLower == "armor" or categoryLower == "weapon" then
			return true
		end
	end

 return false
end

-- 判断物品是否为草药（用于路由到草药袋）
-- 新规则（按需求）：需要同时满足
--   1) itemCategory == "Trade Goods"
--   2) 贴图包含 "INV_Misc_Herb"（不区分大小写；允许带前缀）
function Utils:IsHerbItem(itemLink)
    if not itemLink then return false end

    local itemID = self:ExtractItemID(itemLink)
    if not itemID then return false end

    local name, _, quality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture = self:GetItemInfoSafe(itemID)

    if not itemTexture then
        return false
    end

    -- 贴图路径与语言环境无关（在每个 WoW 客户端中都是英文），
    -- 因此我们无需根据本地化的 "Trade Goods" 类别进行判断。
    local tex = string.lower(itemTexture)
    tex = string.gsub(tex, "^interface\\\\icons\\\\", "")

    if string.find(tex, "inv_misc_herb") or string.find(tex, "misc_herb") then
        return true
    end

    return false
end

-- 判断物品是否为附魔材料（用于路由到附魔袋）
-- 规则：
--   1) itemCategory == "Trade Goods"
--   2) (itemSubType == "Enchanting") 或 贴图包含 "INV_Enchant"（不区分大小写）
function Utils:IsEnchantingItem(itemLink)
    if not itemLink then return false end

    local itemID = self:ExtractItemID(itemLink)
    if not itemID then return false end

    local name, _, quality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture = self:GetItemInfoSafe(itemID)

    -- 明确的英文子类型（少见，但在某些服务器上可能出现）
    if itemType == "Enchanting" or itemSubType == "Enchanting" then
        return true
    end

    if not itemTexture then
        return false
    end

    -- 贴图路径与语言环境无关——对非英文客户端是主要信号。
    local tex = string.lower(itemTexture)
    tex = string.gsub(tex, "^interface\\\\icons\\\\", "")

    if string.find(tex, "inv_enchant") or string.find(tex, "enchant") then
        return true
    end

    return false
end

-- 检查背包是否为附魔袋
function Utils:IsEnchantBag(bagID)
    return self:IsBagType(bagID, "enchant")
end

--=============================================================================
-- 公共 API：在背包（可含银行）中查找物品位置
-- 供其他插件（如 Automatonex 自动喊话）调用，自动定位物品所在的
-- 背包编号与格子号，从而插入物品链接。
--
-- GudaBag.FindItemInBags(itemIDOrLink, includeBank)
--   itemIDOrLink：数字物品 ID；含 "item:%d" 的物品链接/文本；或物品名称
--                 （字符串，不区分大小写的子串匹配）
--   includeBank ：可选，true 时同时搜索银行（-1 与 5-10）
-- 返回：bagID, slotID, itemLink（未找到则均为 nil）
--=============================================================================
-- 从物品链接中提取显示名（|Hitem:...|h[物品名]|h 中的 [物品名]）。
-- 不依赖 GetItemInfo 缓存，因此名称匹配在任何时候都可靠。
local function GetLinkDisplayName(link)
    if not link then return nil end
    local _, _, displayName = string.find(link, "%[([^%]]+)%]")
    return displayName
end

function GudaBag.FindItemInBags(itemIDOrLink, includeBank)
    local ok, bag, slot, link = pcall(function()
        -- 解析查找目标：数字 -> ID；含 "item:<id>" -> ID；否则视为物品名
        local itemID = nil
        local itemName = nil
        if type(itemIDOrLink) == "number" then
            itemID = itemIDOrLink
        elseif itemIDOrLink then
            local _, _, idStr = string.find(tostring(itemIDOrLink), "item:(%d+)")
            if idStr then
                itemID = tonumber(idStr)
            else
                itemName = string.lower(tostring(itemIDOrLink))
            end
        end
        if not itemID and not itemName then return nil, nil, nil end

        local bags = addon.Constants and addon.Constants.BAGS or {0, 1, 2, 3, 4}
        if includeBank then
            bags = addon.Constants and addon.Constants.ALL_BAGS or {0, 1, 2, 3, 4, -1, 5, 6, 7, 8, 9, 10}
        end

        for _, bagID in ipairs(bags) do
            local numSlots = GetContainerNumSlots(bagID)
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local link = GetContainerItemLink(bagID, slot)
                    if link then
                        if itemID then
                            local _, _, idStr2 = string.find(link, "item:(%d+)")
                            if idStr2 and tonumber(idStr2) == itemID then
                                return bagID, slot, link
                            end
                        else
                            -- 名称匹配：直接从链接中提取显示名 [物品名]，
                            -- 不依赖 GetItemInfo 缓存（1.12 下可能返回 nil）。
                            local name = GetLinkDisplayName(link)
                            if name and string.find(string.lower(name), itemName, 1, true) then
                                return bagID, slot, link
                            end
                        end
                    end
                end
            end
        end
        return nil, nil, nil
    end)
    if ok then
        return bag, slot, link
    end
    return nil, nil, nil
end

-- 便捷包装：按物品 ID/链接返回其当前背包中的物品链接（未找到返回 nil）。
-- 供 Automatonex 等插件在喊话/回复消息中插入 {itemX} 链接时使用。
function GudaBag.GetItemLinkForShout(itemIDOrLink, includeBank)
    local _, _, link = GudaBag.FindItemInBags(itemIDOrLink, includeBank)
    return link
end

-- 按背包编号与格子号返回物品链接（未找到返回 nil）。
-- 是 GetContainerItemLink 的便捷别名，供需要"标记第几个背包第几格"的
-- 插件直接使用，避免它们依赖具体背包编号的细节。
function GudaBag.GetItemLinkAt(bagID, slotID)
    if bagID == nil or slotID == nil then return nil end
    return GetContainerItemLink(bagID, slotID)
end