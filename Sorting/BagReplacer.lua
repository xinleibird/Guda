--===========================================================================
-- BagReplacer: 通过先清空物品来自动替换被占用的包
--===========================================================================
local addon = Guda
local BagReplacer = {}
addon.Modules.BagReplacer = BagReplacer

BagReplacer.inProgress = false
BagReplacer.slowMode = false -- 替换银行包期间为 true（银行写入需服务器验证且更慢）

local C = addon.Constants

-- 时间缩放器：银行操作需要更长的防抖/超时，因为服务器
-- 权威地验证每一次槽位写入（锁定、包更新），并伴随往返延迟。
local function T(seconds)
    if BagReplacer.slowMode then
        return seconds * 2.5
    end
    return seconds
end

--===========================================================================
-- 锁定等待机制（独立于 SortEngine）
--===========================================================================
local replacerFrame = CreateFrame("Frame")
local pendingSlots = {}      -- 扁平数组: {bagID1, slot1, bagID2, slot2, ...}
local pendingCount = 0
local pendingSet = {}         -- bagID*1000+slot -> true
local waitingForLocks = false
local onLocksCleared = nil

local function AddPendingLock(bagID, slot)
    local key = bagID * 1000 + slot
    if not pendingSet[key] then
        pendingSet[key] = true
        pendingCount = pendingCount + 1
        pendingSlots[pendingCount * 2 - 1] = bagID
        pendingSlots[pendingCount * 2] = slot
    end
end

local function ClearPendingLocks()
    for k in pairs(pendingSet) do pendingSet[k] = nil end
    for i = 1, pendingCount * 2 do pendingSlots[i] = nil end
    pendingCount = 0
end

local function AnyPendingLocked()
    if pendingCount == 0 then return false end
    for i = 1, pendingCount do
        local bagID = pendingSlots[i * 2 - 1]
        local slot = pendingSlots[i * 2]
        if bagID and slot then
            local _, _, locked = GetContainerItemInfo(bagID, slot)
            if locked then return true end
        end
    end
    return false
end

replacerFrame:RegisterEvent("ITEM_LOCK_CHANGED")
replacerFrame:SetScript("OnEvent", function()
    if waitingForLocks and onLocksCleared then
        if not AnyPendingLocked() then
            waitingForLocks = false
            local cb = onLocksCleared
            onLocksCleared = nil
            ClearPendingLocks()
            cb()
        end
    end
end)

local function WaitForLocksCleared(callback, timeout, minDelay)
    minDelay = minDelay or T(0.15)
    timeout = timeout or T(1.5)
    GudaBag.ScheduleTimer(minDelay, function()
        if not AnyPendingLocked() then
            ClearPendingLocks()
            callback()
            return
        end
        waitingForLocks = true
        onLocksCleared = callback
        local remaining = timeout - minDelay
        if remaining < 0.3 then remaining = 0.3 end
        GudaBag.ScheduleTimer(remaining, function()
            if waitingForLocks then
                waitingForLocks = false
                onLocksCleared = nil
                ClearPendingLocks()
                ClearCursor()
                callback()
            end
        end)
    end)
end

local BATCH_SIZE = 5 -- 每批疏散的移动次数

--===========================================================================
--===========================================================================
-- 构建所有包（除目标包外）中的空闲槽位列表
-- 返回: { {bagID, slotID, bagType}, ... }
--===========================================================================
local function GetAvailableFreeSlots(excludeBagID, isBank)
    local freeSlots = {}
    local count = 0

    local function scan(bagID)
        if bagID == excludeBagID then return end
        local numSlots = GetContainerNumSlots(bagID)
        if not numSlots or numSlots == 0 then return end
        local bagType = addon.Modules.Utils:GetSpecializedBagType(bagID)
        for slot = 1, numSlots do
            local texture = GetContainerItemInfo(bagID, slot)
            if not texture then
                count = count + 1
                freeSlots[count] = { bagID = bagID, slot = slot, bagType = bagType }
            end
        end
    end

    if isBank then
        -- 主银行容器 + 已装备的银行包
        scan(-1)
        for bagID = C.BANK_FIRST, C.BANK_LAST do scan(bagID) end
    else
        -- 背包 + 背包栏
        for bagID = 0, C.BAG_LAST do scan(bagID) end
    end

    return freeSlots, count
end

--===========================================================================
-- 获取包中的物品
-- 返回: { {slot, itemLink}, ... }, count
--===========================================================================
local function GetBagItems(bagID)
    local items = {}
    local count = 0
    local numSlots = GetContainerNumSlots(bagID)

    if not numSlots or numSlots == 0 then
        return items, 0
    end

    local useNampower = addon.Modules.Nampower and addon.Modules.Nampower:IsAvailable() and true or false

    for slot = 1, numSlots do
        -- 若安装了 Nampower，用 GetBagItem 判断槽位非空（免 GetContainerItemInfo）
        local hasItem = nil
        if useNampower then
            hasItem = addon.Modules.Nampower:GetBagItemInfo(bagID, slot)
        else
            hasItem = GetContainerItemInfo(bagID, slot)
        end
        if hasItem then
            local link = GetContainerItemLink(bagID, slot)
            count = count + 1
            items[count] = { slot = slot, itemLink = link }
        end
    end

    return items, count
end

--===========================================================================
-- BuildEvacuationPlan: 将每个物品分配到一个空闲槽位，预留临时存放槽位
-- 返回: plan 表或 nil, errorMsg
--===========================================================================
function BagReplacer:BuildEvacuationPlan(targetBagID, isBank)
    local items, itemCount = GetBagItems(targetBagID)
    addon:DebugSort("[BagReplacer] BuildEvacuationPlan: bag %d has %d items (isBank=%s)", targetBagID, itemCount, tostring(isBank))
    if itemCount == 0 then
        return { moves = {}, stashBag = nil, stashSlot = nil, itemCount = 0, isBank = isBank }, nil
    end

    local freeSlots, freeCount = GetAvailableFreeSlots(targetBagID, isBank)
    local needed = itemCount + 1 -- +1 用于临时存放光标上的新包
    addon:DebugSort("[BagReplacer] Need %d free slots (items+stash), have %d", needed, freeCount)

    if freeCount < needed then
        return nil, string.format(
            GudaBag.L["Not enough free bag space. Need %d more free slots to replace this bag, have %d."],
            needed - freeCount, freeCount
        )
    end

    -- 将空闲槽位分为专用和常规
    local regularFree = {}
    local regularCount = 0
    local specializedFree = {} -- 按 bagType 键控
    for i = 1, freeCount do
        local fs = freeSlots[i]
        if fs.bagType then
            if not specializedFree[fs.bagType] then
                specializedFree[fs.bagType] = {}
            end
            local t = specializedFree[fs.bagType]
            t[table.getn(t) + 1] = fs
        else
            regularCount = regularCount + 1
            regularFree[regularCount] = fs
        end
    end

    local moves = {}
    local moveCount = 0
    local regularIdx = 1 -- 下一个要使用的常规空闲槽位

    -- 将每个物品分配到一个空闲槽位
    for i = 1, itemCount do
        local item = items[i]
        local assigned = false

        -- 若物品有首选类型，先尝试专用包
        if item.itemLink then
            local preferredType = addon.Modules.Utils:GetItemPreferredContainer(item.itemLink)
            if preferredType and specializedFree[preferredType] then
                local specSlots = specializedFree[preferredType]
                if table.getn(specSlots) > 0 then
                    local fs = specSlots[table.getn(specSlots)]
                    specSlots[table.getn(specSlots)] = nil
                    moveCount = moveCount + 1
                    moves[moveCount] = {
                        fromBag = targetBagID, fromSlot = item.slot,
                        toBag = fs.bagID, toSlot = fs.slot
                    }
                    addon:DebugSort("[BagReplacer] Plan move #%d: bag%d/slot%d -> bag%d/slot%d (specialized %s)", moveCount, targetBagID, item.slot, fs.bagID, fs.slot, preferredType)
                    assigned = true
                end
            end
        end

        -- 回退到常规空闲槽位
        if not assigned then
            if regularIdx <= regularCount then
                local fs = regularFree[regularIdx]
                regularIdx = regularIdx + 1
                moveCount = moveCount + 1
                moves[moveCount] = {
                    fromBag = targetBagID, fromSlot = item.slot,
                    toBag = fs.bagID, toSlot = fs.slot
                }
                addon:DebugSort("[BagReplacer] Plan move #%d: bag%d/slot%d -> bag%d/slot%d (regular)", moveCount, targetBagID, item.slot, fs.bagID, fs.slot)
                assigned = true
            end
        end

        if not assigned then
            addon:DebugSort("[BagReplacer] Failed to assign slot %d to a free slot", item.slot)
            return nil, string.format(
                "Not enough compatible bag space. Need %d free slots, have %d.",
                needed, freeCount
            )
        end
    end

    -- 为从光标临时存放新包预留一个常规空闲槽位
    local stashBag, stashSlot
    if regularIdx <= regularCount then
        local fs = regularFree[regularIdx]
        stashBag = fs.bagID
        stashSlot = fs.slot
        addon:DebugSort("[BagReplacer] Stash slot: bag%d/slot%d", stashBag, stashSlot)
    else
        -- 没有常规空闲槽位用于临时存放 - 检查是否有任何专用槽位可用
        -- （新包是容器物品，需要常规槽位）
        return nil, string.format(
            GudaBag.L["Not enough free bag space. Need %d more free slots to replace this bag, have %d."],
            needed - freeCount, freeCount
        )
    end

    return {
        moves = moves,
        stashBag = stashBag,
        stashSlot = stashSlot,
        itemCount = itemCount,
        targetBagID = targetBagID,
        isBank = isBank
    }, nil
end

--===========================================================================
-- Abort: 失败时清理
--===========================================================================
function BagReplacer:Abort(reason)
    addon:DebugSort("[BagReplacer] Abort: %s", reason or "unknown")
    ClearCursor()
    ClearPendingLocks()
    waitingForLocks = false
    onLocksCleared = nil
    self.inProgress = false
    self.slowMode = false
    if reason then
        addon:Print(reason)
    end
    -- 刷新 UI
    if addon.Modules.BagFrame and addon.Modules.BagFrame.Update then
        addon.Modules.BagFrame:Update()
    end
end

--===========================================================================
-- FinishReplacement: 从临时存放处拾取新包，装备它，处理旧包
--===========================================================================
local function FinalizeReplacement(plan)
    ClearPendingLocks()
    waitingForLocks = false
    onLocksCleared = nil
    BagReplacer.inProgress = false
    BagReplacer.slowMode = false
    addon:Print(GudaBag.L["Bag replaced successfully!"])

    -- 在更新前使扫描器缓存失效，以便进行完整重新扫描
    -- （包槽位数量已更改，增量更新无法处理）
    if addon.Modules.BagScanner and addon.Modules.BagScanner.InvalidateCache then
        addon.Modules.BagScanner:InvalidateCache()
    end
    if plan and plan.isBank
       and addon.Modules.BankScanner and addon.Modules.BankScanner.InvalidateCache then
        addon.Modules.BankScanner:InvalidateCache()
    end
    -- 刷新 UI
    if addon.Modules.BagFrame and addon.Modules.BagFrame.Update then
        addon.Modules.BagFrame:Update()
    end
    if plan and plan.isBank
       and addon.Modules.BankFrame and addon.Modules.BankFrame.Update then
        addon.Modules.BankFrame:Update()
    end
end

-- 等待目标包的 BAG_UPDATE 以确认服务器处理了装备，
-- 然后运行完成回调。若事件永不触发则使用安全超时。
local bagUpdateFrame = CreateFrame("Frame")
local bagUpdateCallback = nil
local bagUpdateTarget = nil

bagUpdateFrame:SetScript("OnEvent", function()
    if bagUpdateCallback and arg1 == bagUpdateTarget then
        addon:DebugSort("[BagReplacer] BAG_UPDATE received for bag %d", arg1)
        bagUpdateFrame:UnregisterEvent("BAG_UPDATE")
        local cb = bagUpdateCallback
        bagUpdateCallback = nil
        bagUpdateTarget = nil
        -- 小延迟以让所有相关事件稳定
        GudaBag.ScheduleTimer(T(0.15), cb)
    end
end)

local function WaitForBagUpdate(targetBagID, callback)
    bagUpdateCallback = callback
    bagUpdateTarget = targetBagID
    bagUpdateFrame:RegisterEvent("BAG_UPDATE")
    -- 安全超时
    GudaBag.ScheduleTimer(T(1.5), function()
        if bagUpdateCallback then
            addon:DebugSort("[BagReplacer] BAG_UPDATE timeout for bag %d, proceeding", targetBagID)
            bagUpdateFrame:UnregisterEvent("BAG_UPDATE")
            local cb = bagUpdateCallback
            bagUpdateCallback = nil
            bagUpdateTarget = nil
            cb()
        end
    end)
end

function BagReplacer:FinishReplacement(invSlot, plan)
    local stashBag, stashSlot, targetBagID = plan.stashBag, plan.stashSlot, plan.targetBagID
    addon:DebugSort("[BagReplacer] FinishReplacement: picking up new bag from bag%d/slot%d, equipping to invSlot %d (bag %d, isBank=%s)", stashBag, stashSlot, invSlot, targetBagID, tostring(plan.isBank))
    -- 验证新包仍在临时存放槽位中
    local stashTexture = GetContainerItemInfo(stashBag, stashSlot)
    if not stashTexture then
        self:Abort("Bag replacement failed: stashed bag is missing.")
        return
    end

    -- 从临时存放处拾取新包
    PickupContainerItem(stashBag, stashSlot)
    AddPendingLock(stashBag, stashSlot)

    -- 短暂等待拾取，然后装备
    GudaBag.ScheduleTimer(T(0.15), function()
        if CursorHasItem and CursorHasItem() then
            addon:DebugSort("[BagReplacer] Equipping new bag to invSlot %d", invSlot)
            EquipCursorItem(invSlot)

            -- 等待 BAG_UPDATE 确认服务器处理了包变更
            WaitForBagUpdate(targetBagID, function()
                if CursorHasItem and CursorHasItem() then
                    addon:DebugSort("[BagReplacer] Old bag on cursor, finding free slot to place it")
                    -- 旧包在光标上 - 尝试为其寻找空闲槽位
                    -- 使用与替换相同的池（银行或背包栏）
                    local freeSlots, freeCount = GetAvailableFreeSlots(-999, plan.isBank)
                    for i = 1, freeCount do
                        local fs = freeSlots[i]
                        if not fs.bagType then -- 仅常规槽位
                            addon:DebugSort("[BagReplacer] Placing old bag into bag%d/slot%d", fs.bagID, fs.slot)
                            PickupContainerItem(fs.bagID, fs.slot)
                            ClearCursor()
                            break
                        end
                    end
                    -- 若仍在光标上，也没关系 - 用户可手动放置
                end

                FinalizeReplacement(plan)
            end)
        else
            BagReplacer:Abort("Bag replacement failed: could not pick up new bag.")
        end
    end)
end

--===========================================================================
-- ExecuteNextBatch: 分批移动物品以提高速度
--===========================================================================
function BagReplacer:ExecuteNextBatch(plan, index, invSlot)
    local moves = plan.moves
    local totalMoves = table.getn(moves)

    -- 跳过任何已为空的源槽位
    while index <= totalMoves do
        local sourceTexture = GetContainerItemInfo(moves[index].fromBag, moves[index].fromSlot)
        if sourceTexture then break end
        addon:DebugSort("[BagReplacer] Source slot empty, skipping move %d", index)
        index = index + 1
    end

    -- 所有移动完成 - 结束替换
    if index > totalMoves then
        addon:DebugSort("[BagReplacer] All %d moves complete, finishing replacement", totalMoves)
        self:FinishReplacement(invSlot, plan)
        return
    end

    -- 检查批次中第一个物品是否被锁定（若是则等待）
    local firstMove = moves[index]
    local _, _, locked = GetContainerItemInfo(firstMove.fromBag, firstMove.fromSlot)
    if locked then
        addon:DebugSort("[BagReplacer] Source bag%d/slot%d locked, waiting", firstMove.fromBag, firstMove.fromSlot)
        AddPendingLock(firstMove.fromBag, firstMove.fromSlot)
        WaitForLocksCleared(function()
            BagReplacer:ExecuteNextBatch(plan, index, invSlot)
        end)
        return
    end

    -- 执行一批移动
    local batchEnd = index + BATCH_SIZE - 1
    if batchEnd > totalMoves then batchEnd = totalMoves end
    local moved = 0

    for i = index, batchEnd do
        local move = moves[i]

        -- 验证源仍有物品
        local sourceTexture = GetContainerItemInfo(move.fromBag, move.fromSlot)
        if sourceTexture then
            local _, _, sLocked = GetContainerItemInfo(move.fromBag, move.fromSlot)
            if not sLocked then
                PickupContainerItem(move.fromBag, move.fromSlot)
                PickupContainerItem(move.toBag, move.toSlot)
                ClearCursor()
                AddPendingLock(move.fromBag, move.fromSlot)
                AddPendingLock(move.toBag, move.toSlot)
                moved = moved + 1
                addon:DebugSort("[BagReplacer] Moved %d/%d: bag%d/slot%d -> bag%d/slot%d", i, totalMoves, move.fromBag, move.fromSlot, move.toBag, move.toSlot)
            else
                addon:DebugSort("[BagReplacer] Slot %d locked mid-batch, stopping batch", i)
                batchEnd = i - 1
                break
            end
        else
            addon:DebugSort("[BagReplacer] Source slot %d empty, skipping", i)
        end
    end

    local nextIndex = batchEnd + 1
    addon:DebugSort("[BagReplacer] Batch done: %d items moved, next index %d/%d", moved, nextIndex, totalMoves)

    if moved > 0 then
        -- 等待批次锁定清除，然后下一批
        WaitForLocksCleared(function()
            BagReplacer:ExecuteNextBatch(plan, nextIndex, invSlot)
        end)
    else
        -- 无移动（全部为空/锁定），立即尝试下一批
        BagReplacer:ExecuteNextBatch(plan, nextIndex, invSlot)
    end
end

--===========================================================================
-- Execute: 主入口点
--===========================================================================
function BagReplacer:Execute(targetBagID, invSlot, isBank)
    addon:DebugSort("[BagReplacer] Execute: targetBagID=%d, invSlot=%d, isBank=%s", targetBagID, invSlot, tostring(isBank))

    -- 守卫：已在进行中
    if self.inProgress then
        addon:DebugSort("[BagReplacer] Blocked: replacement already in progress")
        addon:Print(GudaBag.L["Cannot replace bag: another replacement is in progress."])
        return
    end

    -- 守卫：排序进行中
    local SortEngine = addon.Modules.SortEngine
    if SortEngine and SortEngine.sortingInProgress then
        addon:DebugSort("[BagReplacer] Blocked: sorting in progress")
        addon:Print(GudaBag.L["Cannot replace bag while sorting is in progress."])
        return
    end

    -- 守卫：战斗
    if UnitAffectingCombat("player") then
        addon:DebugSort("[BagReplacer] Blocked: in combat")
        addon:Print(GudaBag.L["Cannot replace bag during combat."])
        return
    end

    -- 守卫：银行包交换必须打开银行（否则服务器拒绝银行写入）
    if isBank and addon.Modules.BankScanner
       and not addon.Modules.BankScanner:IsBankOpen() then
        addon:DebugSort("[BagReplacer] Blocked: bank not open")
        addon:Print(GudaBag.L["Cannot replace bank bag: bank is not open."])
        return
    end

    -- 检查包是否为空（正常装备即可）
    local _, itemCount = GetBagItems(targetBagID)
    if itemCount == 0 then
        addon:DebugSort("[BagReplacer] Bag is empty, using normal equip")
        if EquipCursorItem then
            EquipCursorItem(invSlot)
        elseif PutItemInBag then
            PutItemInBag(invSlot)
        end
        return
    end

    -- 构建疏散计划
    local plan, errorMsg = self:BuildEvacuationPlan(targetBagID, isBank)
    if not plan then
        addon:DebugSort("[BagReplacer] Plan failed: %s", errorMsg)
        addon:Print(errorMsg)
        return -- 光标未动，用户继续持有新包
    end

    -- 开始替换
    self.inProgress = true
    self.slowMode = isBank and true or false
    addon:Print(string.format("Replacing bag: moving %d items...", plan.itemCount))
    addon:DebugSort("[BagReplacer] Starting replacement: %d moves, stash at bag%d/slot%d", table.getn(plan.moves), plan.stashBag, plan.stashSlot)

    -- 换包期间隐藏全部物品按钮，大幅降低每帧渲染开销，提升换包帧率。
    -- 换包结束（FinalizeReplacement/Abort）会调用 Update() 重建恢复按钮。
    if isBank then
        if GudaBag.BankFrame_HideAllItemButtons then GudaBag.BankFrame_HideAllItemButtons() end
    else
        if GudaBag.BagFrame_HideAllItemButtons then GudaBag.BagFrame_HideAllItemButtons() end
    end

    -- 步骤 1：将光标上的新包临时存放到预留的空闲槽位
    addon:DebugSort("[BagReplacer] Stashing cursor item to bag%d/slot%d", plan.stashBag, plan.stashSlot)
    PickupContainerItem(plan.stashBag, plan.stashSlot)
    -- 这将光标物品（新包）放入 stashSlot
    AddPendingLock(plan.stashBag, plan.stashSlot)

    -- 等待临时存放完成，然后开始疏散
    WaitForLocksCleared(function()
        -- 验证新包已临时存放
        local stashTexture = GetContainerItemInfo(plan.stashBag, plan.stashSlot)
        if not stashTexture then
            BagReplacer:Abort("Bag replacement failed: could not stash new bag.")
            return
        end
        addon:DebugSort("[BagReplacer] Stash confirmed, beginning evacuation")
        -- 开始将物品移出目标包
        BagReplacer:ExecuteNextBatch(plan, 1, invSlot)
    end)
end

--===========================================================================
-- 全局自动换包：拦截"非空包无法装备"错误，自动执行 BagReplacer。
-- 这样即使用户从物品栏右键装备新包（或动作条/其它路径），也能自动
-- 先清空旧包再换包，而不必手动拖放到背包槽位。
-- 思路与 Bagshui 的 UIErrorsFrame_OnEvent 相同。
--===========================================================================
local uiErrorHooked = false

-- 判断错误消息是否为"非空包无法装备/销毁"
local function IsNonEmptyBagError(message)
    if not message then return false end
    -- 匹配本地化后的错误文本（ERR_DESTROY_NONEMPTY_BAG），用子串匹配以兼容各语言
    local m = string.lower(message)
    -- enUS: "That bag is not empty."
    if string.find(m, "bag is not empty", 1, true) then return true end
    if string.find(m, "non-empty", 1, true) then return true end
    if string.find(m, "nonempty", 1, true) then return true end
    -- zhCN
    if string.find(m, "非空", 1, true) then return true end
    if string.find(m, "不是空的", 1, true) then return true end
    if string.find(m, "背包里还有", 1, true) then return true end
    -- deFR/esES/ruRU 兜底：直接匹配 "not empty"
    if string.find(m, "not empty", 1, true) then return true end
    if string.find(m, "nicht leer", 1, true) then return true end
    if string.find(m, "не пуст", 1, true) then return true end
    return false
end

-- 从锁定状态找到"用户正在尝试装备新包"的目标装备槽位（背包 1-4）。
-- 返回 invSlot（ContainerIDToInventoryID 的装备槽位）或 nil。
local function FindPendingBagEquipSlot()
    for bagID = C.BAG_FIRST, C.BAG_LAST do
        local invSlot = ContainerIDToInventoryID(bagID)
        if IsInventoryItemLocked and IsInventoryItemLocked(invSlot) then
            return invSlot
        end
    end
    return nil
end

function BagReplacer:EnableAutoSwap()
    if uiErrorHooked then return end
    uiErrorHooked = true
    addon.Modules.Events:Register("UI_ERROR_MESSAGE", function(event, message)
        -- 仅处理"非空包无法装备"错误
        if not IsNonEmptyBagError(message) then return end
        -- 需要光标上持有物品（新包）
        if not (CursorHasItem and CursorHasItem()) then return end
        -- 找到目标装备槽位
        local invSlot = FindPendingBagEquipSlot()
        if not invSlot then return end
        -- 将装备槽位 ID 转换回背包 ID（1-4）
        local bagID = nil
        for i = C.BAG_FIRST, C.BAG_LAST do
            if ContainerIDToInventoryID(i) == invSlot then
                bagID = i
                break
            end
        end
        if not bagID then return end
        -- 用户已尝试装备非空包 → 自动换包
        addon:DebugSort("[BagReplacer] Auto-swap triggered via UI_ERROR for bag %d", bagID)
        BagReplacer:Execute(bagID, invSlot, false)
    end, "BagReplacer_AutoSwap")
end
