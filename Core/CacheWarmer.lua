-- Guda 缓存预热器
-- 在 PLAYER_LOGIN 后不久，于后台预热 ItemDetection 的提示框扫描缓存和
-- BagScanner 的背包数据缓存，这样用户第一次打开背包窗口时不会为
-- 大约 80 次同步提示框扫描而付出代价。
--
-- 复用 Utils:QueueWork（Core/Utils.lua）进行按帧预算的后台处理
-- —— 不需要新的调度器。

local addon = Guda

local CacheWarmer = {}
addon.Modules.CacheWarmer = CacheWarmer

-- 遍历玩家背包 0-4，预热 BagScanner 的逐包缓存。成本低，内联运行。
function CacheWarmer:WarmBagScanner()
    local BagScanner = Guda.Modules.BagScanner
    if not BagScanner or not BagScanner.ScanBag then return end
    -- ScanBag 填充稍后 GetBagData 使用的逐包缓存。
    for bagID = 0, 4 do
        local ok = pcall(function() BagScanner:ScanBag(bagID) end)
        if not ok then break end
    end
end

-- 遍历玩家背包 0-4，并为背包打开路径读取的每个缓存排队提示框扫描工作，
-- 这样第一次 DisplayItemsByCategory 就不会在冷查找时阻塞。目标：
--   * ItemDetection.detectionCache  —— 用于 isJunk / isQuestItem 规则
--   * Utils.tooltipCache.restoreTag —— 用于消耗品的食物/饮品分组
--   * Utils.tooltipCache.bindOnEquip —— 用于 isBoE 规则
--   * CategoryManager.categoryCache —— 直接由布局路径使用
-- 队列顺序是 FIFO，并以每帧 100ms 为预算限制，所以这一切都在
-- PLAYER_LOGIN 后的 0.5s–~2s 窗口内运行。
function CacheWarmer:WarmItemDetectionCache()
    local Utils = Guda.Modules.Utils
    local ItemDetection = Guda.Modules.ItemDetection
    local CategoryManager = Guda.Modules.CategoryManager
    local BagScanner = Guda.Modules.BagScanner
    if not (Utils and Utils.QueueWork) then return end
    if not (ItemDetection and ItemDetection.GetItemProperties) then return end

    -- WarmBagScanner 就在我们之前运行，所以 GetBagData() 是缓存命中，
    -- 并返回已经填充了 class/subclass/quality 的 itemData。
    local bagData = BagScanner and BagScanner.GetBagData and BagScanner:GetBagData()

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slotID = 1, numSlots do
                local link = GetContainerItemLink(bagID, slotID)
                if link then
                    -- 捕获 upvalue，使闭包拥有稳定的 bag/slot/link。
                    local b, s, l = bagID, slotID, link

                    Utils:QueueWork(function()
                        -- 极简的 itemData —— GetItemProperties 只需要
                        -- .link 来计算缓存键；bagID/slotID 提供给
                        -- 提示框扫描。
                        ItemDetection:GetItemProperties({ link = l }, b, s)
                    end, "CacheWarmer.itemDetection")

                    -- 消耗品 restoreTag 缓存（只有消耗品带有
                    -- "while eating" / "while drinking" / "use: restores"）。
                    Utils:QueueWork(function()
                        local _, _, _, _, itemType = GetItemInfo(l)
                        -- 规范化为英文，使消耗品门槛在 zhCN 客户端也能工作。
                        itemType = Utils:NormalizeItemClass(itemType)
                        if itemType == "Consumable" and Utils.GetConsumableRestoreTag then
                            Utils:GetConsumableRestoreTag(b, s, l)
                        end
                    end, "CacheWarmer.restoreTag")

                    -- BoE / BoP 提示框缓存。只有武器/护甲可以是 BoE/BoP；
                    -- 跳过所有其他物品，这样我们就不会白白扫描消耗品/贸易
                    -- 物品的提示框。
                    Utils:QueueWork(function()
                        local _, _, _, _, class = GetItemInfo(l)
                        -- 规范化为英文，使 Weapon/Armor 门槛在 zhCN 客户端也能工作。
                        class = Utils:NormalizeItemClass(class)
                        if (class == "Weapon" or class == "Armor") then
                            if Utils.IsBindOnEquip then
                                Utils:IsBindOnEquip(b, s, l)
                            end
                            if Utils.IsBindOnPickup then
                                Utils:IsBindOnPickup(b, s, l)
                            end
                        end
                    end, "CacheWarmer.boe")

                    -- CategoryManager 缓存。快照 itemData 字段，因为
                    -- BagScanner 使用对象池，稍后可能回收该表。
                    -- restoreTag 字段在回调内部填充（不是在这里），因为
                    -- restoreTag 预热器通过 FIFO 队列顺序先运行 ——
                    -- 所以到它触发时，tooltipCache.restoreTag 查找已是缓存命中。
                    if CategoryManager and CategoryManager.CategorizeItem and bagData then
                        local bag = bagData[b]
                        local slotData = bag and bag.slots and bag.slots[s]
                        if slotData and slotData.link then
                            local snapshot = {
                                link = slotData.link,
                                name = slotData.name,
                                class = slotData.class,
                                type = slotData.type,
                                subclass = slotData.subclass,
                                quality = slotData.quality,
                                texture = slotData.texture,
                                equipSlot = slotData.equipSlot,
                            }
                            Utils:QueueWork(function()
                                -- 从预热缓存中取出 restoreTag，以便以它
                                -- 为键的规则（食物/饮品分类）能够匹配。
                                if snapshot.class == "Consumable"
                                   and Utils.GetConsumableRestoreTag then
                                    snapshot.restoreTag =
                                        Utils:GetConsumableRestoreTag(b, s, snapshot.link)
                                end
                                CategoryManager:CategorizeItem(snapshot, b, s, false)
                            end, "CacheWarmer.category")
                        end
                    end
                end
            end
        end
    end
end

-- 运行一次预热：重新扫描背包，并重新排队提示框/分类工作，使
-- 先前某次扫描时 GetItemInfo 仍为 nil 的物品现在能解析出来。
local function WarmOnce()
    CacheWarmer:WarmBagScanner()
    CacheWarmer:WarmItemDetectionCache()

    -- 完成标记 —— 在之前所有预热器排空后运行。重新布局背包，
    -- 使在第一次（冷缓存）渲染时回退到其类别桶的物品现在落到
    -- 真正的分类中，并重新扫描在背包已经打开时其检测才完成的
    -- 物品的着色。
    local Utils = Guda.Modules.Utils
    if Utils and Utils.QueueWork then
        Utils:QueueWork(function()
            if Guda_BagFrame and Guda_BagFrame:IsShown()
               and Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
                Guda.Modules.BagFrame:Update()
            end
            if GudaBag.BagFrame_UpdateAllUsabilityTints then
                GudaBag.BagFrame_UpdateAllUsabilityTints()
            end
        end, "CacheWarmer.completionSweep")
    end
end

-- 检查每个背包物品的 GetItemInfo 是否已解析（名称非 nil）。
-- 一旦物品数据从服务器到达，就提前停止重新预热。
local function AreBagItemsResolved()
    local BagScanner = Guda.Modules.BagScanner
    if not BagScanner or not BagScanner.GetBagData then return false end
    local bagData = BagScanner:GetBagData()
    if not bagData then return false end
    for bagID = 0, 4 do
        local bag = bagData[bagID]
        if bag and bag.slots then
            for _, slotData in pairs(bag.slots) do
                if slotData and slotData.link then
                    local name = GetItemInfo(slotData.link)
                    if not name then return false end
                end
            end
        end
    end
    return true
end

function CacheWarmer:Initialize()
    -- 物品文本数据（名称/分类）在 PLAYER_LOGIN 后从服务器异步获取。
    -- 在首次登录（或客户端的物品缓存冷启动后）时，+0.5s 时刻
    -- GetItemInfo 仍然返回 nil，因此单次扫描会缓存 nil 分类，背包
    -- 看起来会"空"/未分类，直到 /reload 预热本地物品缓存。修复方法：
    -- 错开多次扫描 —— 后面的扫描（一旦物品数据到达）会用正确的值
    -- 覆盖错误的 nil 缓存。一旦所有物品都已解析就提前停止。
    local passes = { 0.5, 2, 5, 10 }

    for _, delay in ipairs(passes) do
        GudaBag.ScheduleTimer(delay, function()
            -- 一旦物品数据完全到达，跳过重新预热；之后的扫描
            -- 就变成廉价的空操作。
            if AreBagItemsResolved() then return end
            WarmOnce()
        end)
    end
end
