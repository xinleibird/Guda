-- Guda 蚌壳打开器
-- 依次使用玩家背包中的每个蚌壳，直到没有剩余为止。
-- 由 /guda openclams 触发。遇到 UI_ERROR_MESSAGE 时停止，这样
-- 背包已满（或 UseContainerItem 产生的任何其他错误）都能干净地中止运行。

local addon = Guda
local L = GudaBag.L

local ClamOpener = {}
addon.Modules.ClamOpener = ClamOpener

-- 硬编码的香草时代蚌壳物品 ID
local CLAM_IDS = {
    [5523]  = true,  -- 小鳞蛤
    [5524]  = true,  -- 厚壳蚌
    [7973]  = true,  -- 大嘴蚌
    [15874] = true,  -- 软壳蚌
}

local OPEN_DELAY = 0.5   -- 每次打开之间的秒数；让拾取/背包更新稳定下来
-- 在自动打开触发时，我们不会立即打开。而是先等待拾取/拾取窗口（以及
-- 任何其他阻塞窗口）完全关闭，然后在 UseContainerItem 之前加上一个
-- 最终的安全余量。在客户端仍在处理上一次拾取时打开，可能会与打开窗口
-- 竞争或使其软锁。
local CLOSE_POLL_INTERVAL = 0.05  -- 重新检查窗口是否消失的频率
local POST_CLOSE_DELAY = 0.5      -- 确认窗口关闭后等待的秒数
local running = false
local silentRun = false
local pendingToken = 0   -- 每次自动触发和 LOOT_OPENED 时递增，用于取消过期的定时器
local waitingForLoot = false
local OpenNext  -- 前向声明；在 OnClamLootClosed 之后定义

-- 如果有任何阻塞窗口（拾取/邮件/交易/商人/银行/拍卖行）当前处于打开状态，
-- 则返回 true。这些窗口处于激活状态时我们不想调用 UseContainerItem ——
-- 它可能与打开窗口竞争，或者被排队后丢失。
local function IsBlockingWindowOpen()
    local frames = {
        "LootFrame", "MailFrame", "TradeFrame", "MerchantFrame",
        "BankFrame", "AuctionFrame",
        -- Guda 自己的银行/邮箱窗口也算
        "Guda_BankFrame", "Guda_MailboxFrame",
    }
    for _, name in ipairs(frames) do
        local f = getglobal(name)
        if f and f.IsShown and f:IsShown() then
            return true
        end
    end
    return false
end

-- 查找玩家背包中的下一个蚌壳。返回 bagID、slotID、itemLink 或 nil。
local function FindNextClam()
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slotID = 1, numSlots do
                local link = GetContainerItemLink(bagID, slotID)
                if link then
                    local _, _, idStr = string.find(link, "item:(%d+)")
                    local itemID = idStr and tonumber(idStr)
                    if itemID and CLAM_IDS[itemID] then
                        return bagID, slotID
                    end
                end
            end
        end
    end
    return nil
end

local function StopRun(reason)
    if not running then return end
    running = false
    addon.Modules.Events:UnregisterOwner("ClamOpener_Run")
    addon.Modules.Events:UnregisterOwner("ClamOpener_LootWait")
    waitingForLoot = false
    if reason and not silentRun then
        addon:Print(reason)
    end
    silentRun = false
end

-- waitingForLoot：在 UseContainerItem 与确认蚌壳拾取窗口完全关闭的
-- LOOT_CLOSED 之间设置，防止并发调用 UseContainerItem。
local function OnClamLootClosed()
    -- 立即注销这个一次性监听器。
    addon.Modules.Events:UnregisterOwner("ClamOpener_LootWait")
    waitingForLoot = false
    if not running then return end
    -- 小幅延迟，让客户端在下一次打开前完全稳定。
    GudaBag.ScheduleTimer(OPEN_DELAY, OpenNext)
end

OpenNext = function()
    if not running then return end
    if waitingForLoot then return end

    -- 当有其他事情正在进行时绝不使用蚌壳：光标忙碌、
    -- 有阻塞窗口打开，或服务器端拾取仍然活跃。这些情况中的
    -- 任何一种 + UseContainerItem 都会与打开窗口竞争，或被排队后丢失。
    if CursorHasItem()
       or IsBlockingWindowOpen()
       or (GetNumLootItems and GetNumLootItems() > 0) then
        GudaBag.ScheduleTimer(OPEN_DELAY, OpenNext)
        return
    end

    local bagID, slotID = FindNextClam()
    if not bagID then
        StopRun(L["No more clams to open."])
        return
    end

    -- 在调用 UseContainerItem 之前布设一次性 LOOT_CLOSED 监听器，
    -- 这样即使它在同一帧触发，我们也不会错过该事件。
    waitingForLoot = true
    addon.Modules.Events:Register("LOOT_CLOSED", OnClamLootClosed, "ClamOpener_LootWait")
    UseContainerItem(bagID, slotID)
end

-- 在 UI_ERROR_MESSAGE 时停止（例如背包已满）。UseContainerItem 在失败时
-- 会在同一帧触发该事件，因此开始后出现的任何错误都算作中止。
local function OnUIError()
    if not running then return end
    local msg = arg1
    StopRun(string.format(L["Clam opener stopped: %s"], tostring(msg or "error")))
end

-- silent：true 时抑制聊天消息（由自动触发使用）。
function ClamOpener:Open(silent)
    if running then
        if not silent then
            addon:Print(L["Clam opener is already running."])
        end
        return
    end

    -- 快速合理性检查，避免从未开始就打印"已停止"。
    if not FindNextClam() then
        if not silent then
            addon:Print(L["No clams found in your bags."])
        end
        return
    end

    running = true
    silentRun = silent and true or false
    addon.Modules.Events:Register("UI_ERROR_MESSAGE", OnUIError, "ClamOpener_Run")
    if not silent then
        addon:Print(L["Opening clams..."])
    end
    OpenNext()
end

-- 初始化自动打开。触发条件：
--   * LOOT_CLOSED     —— 常见情况：从尸体拾取到蚌壳。
--   * MAIL_CLOSED     —— 通过邮件收到蚌壳。
--   * TRADE_CLOSED    —— 通过交易收到蚌壳。
--   * BANKFRAME_CLOSED —— 从银行取回蚌壳。
--   * LOOT_OPENED     —— 仅用于取消：静默期间出现新的拾取窗口会
--                       使任何待处理的自动打开失效。匹配的
--                       LOOT_CLOSED 会重新布设它。
-- BAG_UPDATE 故意不作为触发条件：它在 AutoLoot 的逐槽位循环中会触发多次，
-- 这会堆叠定时器，与客户端的拾取-关闭过渡竞争并使拾取窗口软锁。
-- 每次触发都会递增一个单调令牌；每个定时回调在调度时捕获它的令牌，
-- 并且只有在没有更新的事件取代它时才触发。
function ClamOpener:Initialize()
    local function OnLootOpened()
        -- 刚打开新的拾取窗口：取消任何待处理的自动打开。匹配的
        -- LOOT_CLOSED 会在该窗口完成后重新布设它。
        pendingToken = pendingToken + 1
    end

    local function tryAutoOpen()
        if running then return end
        if not (Guda.Modules.DB and Guda.Modules.DB:GetSetting("autoOpenClams")) then
            return
        end
        pendingToken = pendingToken + 1
        local myToken = pendingToken

        -- 等到拾取/拾取窗口（以及任何其他阻塞窗口）真正
        -- 关闭，然后在打开之前加上一个最终的安全余量。
        local function WaitUntilClosed()
            if myToken ~= pendingToken then return end
            if running then return end
            if IsBlockingWindowOpen() then
                -- 窗口还在 —— 继续轮询直到它消失。
                GudaBag.ScheduleTimer(CLOSE_POLL_INTERVAL, WaitUntilClosed)
                return
            end
            GudaBag.ScheduleTimer(POST_CLOSE_DELAY, function()
                if myToken ~= pendingToken then return end
                if running then return end
                if IsBlockingWindowOpen() then return end
                if GetNumLootItems and GetNumLootItems() > 0 then return end
                ClamOpener:Open(true)
            end)
        end

        WaitUntilClosed()
    end

    addon.Modules.Events:Register("LOOT_OPENED",       OnLootOpened, "ClamOpener")
    addon.Modules.Events:Register("LOOT_CLOSED",       tryAutoOpen,  "ClamOpener")
    addon.Modules.Events:Register("MAIL_CLOSED",       tryAutoOpen,  "ClamOpener")
    addon.Modules.Events:Register("TRADE_CLOSED",      tryAutoOpen,  "ClamOpener")
    addon.Modules.Events:Register("BANKFRAME_CLOSED",  tryAutoOpen,  "ClamOpener")
end
