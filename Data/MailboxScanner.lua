-- Guda 邮箱扫描器
-- 扫描并存储邮箱内容

local addon = Guda

local MailboxScanner = {}
addon.Modules.MailboxScanner = MailboxScanner

local mailboxOpen = false
local savePending = false
local SAVE_DEBOUNCE = 0.5

-- 防抖保存：把突发的 MAIL_INBOX_UPDATE 合并为一次重新扫描。
-- 每次事件都扫描 100+ 封邮件曾导致客户端崩溃。
local function ScheduleSave()
    if savePending then return end
    if not mailboxOpen then return end
    savePending = true
    GudaBag.ScheduleTimer(SAVE_DEBOUNCE, function()
        savePending = false
        if mailboxOpen then
            MailboxScanner:SaveToDatabase()
        end
    end)
end

-- 扫描所有邮箱物品并返回数据
function MailboxScanner:ScanMailbox()
    if not mailboxOpen then
        addon:Debug("Cannot scan mailbox - not open")
        return {}
    end

    local mailboxData = {}
    local numItems = GetInboxNumItems()

    for i = 1, numItems do
        local mailRows = self:ScanMailItemRows(i)
        for _, row in ipairs(mailRows) do
            table.insert(mailboxData, row)
        end
    end

    return mailboxData
end

-- 将单个邮件扫描成一行或多行（展平）
function MailboxScanner:ScanMailItemRows(index)
    -- GetInboxHeaderInfo(index) 返回：packageIcon、stationeryIcon、sender、subject、money、CODAmount、daysLeft、hasItem、wasRead、wasReturned、textCreated、canReply、isGM
    local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM = GetInboxHeaderInfo(index)

    local rows = {}
    
    if hasItem then
        -- 乌龟魔兽每封邮件支持最多 12 个附件。
        -- 如果可用，我们使用 GetInboxNumAttachments 以避免在可能
        -- 忽略 GetInboxItem 第二个参数的服务器上过度扫描。
        local numAttachments = 0
        if GetInboxNumAttachments then
            numAttachments = GetInboxNumAttachments(index) or 0
        end

        -- 回退：如果我们没有计数但邮件头说有物品，则假定至少 1 个。
        if numAttachments == 0 and hasItem then
            numAttachments = 1
        end

        for itemIndex = 1, numAttachments do
            -- GetInboxItem(index, itemIndex) 返回：name、texture、count、quality、canUse
            local name, texture, count, quality, canUse = GetInboxItem(index, itemIndex)
            if not name then break end

            local itemLink = addon.Modules.Utils:GetInboxItemLink(index, itemIndex)
            local itemID = itemLink and addon.Modules.Utils:ExtractItemID(itemLink)

            -- 回退 1：如果链接/物品 ID 缺失，尝试 GetItemInfo(name)，它现在可能已被缓存
            if not itemID or not itemLink then
                local _, link = GetItemInfo(name)
                if link then
                    itemLink = link
                    itemID = addon.Modules.Utils:ExtractItemID(link)
                    addon:Debug("Recovered link from GetItemInfo for %s", name)
                end
            end

            -- （已移除）FindItemByName 跨角色回退：使用跨账号数据时，
            -- 这会按 邮件 × 附件 × 角色 × 栏位 增长，并且可能
            -- 在大型邮箱上使客户端崩溃。上面的 GetItemInfo 处理了
            -- 常见情况；缺失的链接在下次重扫时一旦被缓存就会解析。


            local itemData = {
                link = itemLink,
                texture = texture or "Interface\\Icons\\INV_Misc_Bag_08",
                count = count or 1,
                quality = quality or 0,
                name = name,
                itemID = itemID,
            }

            -- 如果有 itemID 则确保我们有链接
            if itemData.itemID and not itemData.link then
                itemData.link = "item:" .. itemData.itemID .. ":0:0:0"
            end

            -- 如果有链接，尝试从缓存获取更详细的信息
            if itemData.link then
                local itemName, link, itemQuality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice = addon.Modules.Utils:GetItemInfo(itemData.link)
                if itemName then
                    itemData.name = itemName
                    itemData.quality = itemQuality or itemData.quality
                    itemData.iLevel = iLevel
                    itemData.type = itemType
                    itemData.class = itemCategory
                    itemData.subclass = itemSubType
                    itemData.equipSlot = itemEquipLoc
                    if itemTexture then itemData.texture = itemTexture end
                end
            end

            table.insert(rows, {
                sender = sender,
                subject = subject,
                money = (itemIndex == 1) and money or 0, -- 只把金币附加到这封邮件的第一行
                CODAmount = (itemIndex == 1) and CODAmount or 0,
                daysLeft = daysLeft,
                hasItem = true,
                item = itemData,
                mailIndex = index,
                itemIndex = itemIndex,
                wasRead = wasRead,
                packageIcon = packageIcon,
            })
        end
    end

    -- 如果没有找到物品但有金币或只是信件
    if table.getn(rows) == 0 then
        table.insert(rows, {
            sender = sender,
            subject = subject,
            money = money,
            CODAmount = CODAmount,
            daysLeft = daysLeft,
            hasItem = false,
            item = nil,
            mailIndex = index,
            itemIndex = 1,
            wasRead = wasRead,
            packageIcon = packageIcon,
        })
    end

    return rows
end

-- 将当前邮箱保存到数据库
function MailboxScanner:SaveToDatabase()
    if not mailboxOpen then
        return
    end

    local mailboxData = self:ScanMailbox()
    addon.Modules.DB:SaveMailbox(mailboxData)
    addon:Debug("Mailbox data saved")
end

-- 从名称/纹理/数量/品质构建物品数据
local function BuildSendMailItemData(name, texture, count, quality)
    local _, link = GetItemInfo(name)
    local itemData = {
        name = name,
        texture = texture or "Interface\\Icons\\INV_Misc_Bag_08",
        count = count or 1,
        quality = quality or 0,
        link = link,
        itemID = addon.Modules.Utils:ExtractItemID(link),
    }

    local itemName, retLink, itemQuality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc = addon.Modules.Utils:GetItemInfo(name)
    if itemName then
        itemData.link = retLink or itemData.link
        itemData.itemID = addon.Modules.Utils:ExtractItemID(itemData.link) or itemData.itemID
        itemData.quality = itemQuality or itemData.quality
        itemData.iLevel = iLevel
        itemData.type = itemType
        itemData.class = itemCategory
        itemData.subclass = itemSubType
        itemData.equipSlot = itemEquipLoc
        if itemTexture then itemData.texture = itemTexture end
    end

    if not itemData.itemID and itemData.link then
        itemData.itemID = addon.Modules.Utils:ExtractItemID(itemData.link)
    end

    return itemData
end

-- 处理外发邮件
function MailboxScanner:OnSendMail(recipient, subject, body)
    if not recipient or recipient == "" then return end

    local moneyAmount = GetSendMailMoney()
    local subjectText = (subject and subject ~= "") and subject or "No Subject"
    local senderName = UnitName("player")
    local addedAny = false

    -- 尝试多附件（乌龟魔兽）：检查 HasSendMailItem 是否存在
    if HasSendMailItem then
        for itemIndex = 1, 12 do
            if not HasSendMailItem(itemIndex) then break end
            local name, texture, count, quality = GetSendMailItem(itemIndex)
            if not name then break end

            local mailRow = {
                sender = senderName,
                subject = subjectText,
                money = (itemIndex == 1) and moneyAmount or 0,
                CODAmount = 0,
                daysLeft = 30,
                hasItem = true,
                item = BuildSendMailItemData(name, texture, count, quality),
                wasRead = false,
            }
            addon.Modules.DB:AddMailToCharacter(recipient, nil, mailRow)
            addedAny = true
        end
    end

    -- 回退：单个附件（香草 API）
    if not addedAny then
        local name, texture, count, quality = GetSendMailItem()
        if name then
            local mailRow = {
                sender = senderName,
                subject = subjectText,
                money = moneyAmount,
                CODAmount = 0,
                daysLeft = 30,
                hasItem = true,
                item = BuildSendMailItemData(name, texture, count, quality),
                wasRead = false,
            }
            addon.Modules.DB:AddMailToCharacter(recipient, nil, mailRow)
            addedAny = true
        end
    end

    -- 仅金币的邮件（无物品）
    if not addedAny and moneyAmount > 0 then
        local mailRow = {
            sender = senderName,
            subject = subjectText,
            money = moneyAmount,
            CODAmount = 0,
            daysLeft = 30,
            hasItem = false,
            item = nil,
            wasRead = false,
        }
        addon.Modules.DB:AddMailToCharacter(recipient, nil, mailRow)
    end
end

-- 处理拍卖行买断
function MailboxScanner:OnAuctionBid(type, index, bid)
    local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo(type, index)
    
    if name and buyoutPrice > 0 and bid >= buyoutPrice then
        local link = GetAuctionItemLink(type, index)
        local itemData = {
            name = name,
            texture = texture or "Interface\\Icons\\INV_Misc_Bag_08",
            count = count or 1,
            quality = quality or 0,
            link = link,
            itemID = addon.Modules.Utils:ExtractItemID(link),
        }
        
        -- 如果它在缓存中，尝试获取更多信息
        local itemName, retLink, itemQuality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice = addon.Modules.Utils:GetItemInfo(link or name)
        if itemName then
            itemData.link = retLink or itemData.link
            itemData.itemID = addon.Modules.Utils:ExtractItemID(itemData.link) or itemData.itemID
            itemData.quality = itemQuality or itemData.quality
            itemData.iLevel = iLevel
            itemData.type = itemType
            itemData.class = itemCategory
            itemData.subclass = itemSubType
            itemData.equipSlot = itemEquipLoc
            if itemTexture then itemData.texture = itemTexture end
        end

        local mailRow = {
            sender = "Auction House",
            subject = "Auction won: " .. name,
            money = 0,
            CODAmount = 0,
            daysLeft = 30,
            hasItem = true,
            item = itemData,
            wasRead = false,
        }
        
        addon.Modules.DB:AddMailToCharacter(UnitName("player"), nil, mailRow)
        addon:Debug("Captured AH buyout: %s", name)
    end
end

-- 初始化邮箱扫描器
function MailboxScanner:Initialize()
    -- 钩住 SendMail 以捕获发给小号的外发邮件
    local originalSendMail = SendMail
    SendMail = function(recipient, subject, body)
        MailboxScanner:OnSendMail(recipient, subject, body)
        return originalSendMail(recipient, subject, body)
    end

    -- 钩住 PlaceAuctionBid 以捕获拍卖行买断
    local originalPlaceAuctionBid = PlaceAuctionBid
    PlaceAuctionBid = function(type, index, bid)
        MailboxScanner:OnAuctionBid(type, index, bid)
        return originalPlaceAuctionBid(type, index, bid)
    end

    -- 钩住取走物品/金币（只调用原始函数，数据库保存由 MAIL_INBOX_UPDATE 处理）
    local originalTakeInboxItem = TakeInboxItem
    TakeInboxItem = function(index, attachmentIndex)
        return originalTakeInboxItem(index, attachmentIndex)
    end

    local originalTakeInboxMoney = TakeInboxMoney
    TakeInboxMoney = function(index)
        return originalTakeInboxMoney(index)
    end

    local originalAutoLootMailItem = AutoLootMailItem
    AutoLootMailItem = function(index)
        return originalAutoLootMailItem(index)
    end

    -- 当服务器确认收件箱变化时重新扫描邮箱（防抖）
    addon.Modules.Events:Register("MAIL_INBOX_UPDATE", function()
        ScheduleSave()
    end, "MailboxScanner_InboxUpdate")

    -- 邮箱打开
    addon.Modules.Events:OnMailShow(function()
        mailboxOpen = true
        addon:Debug("Mailbox opened")
        ScheduleSave()
    end, "MailboxScanner")

    -- 邮箱关闭
    addon.Modules.Events:OnMailClosed(function()
        -- 关闭时进行最终保存（同步执行，避免与 mailboxOpen=false 竞争）
        if mailboxOpen then
            MailboxScanner:SaveToDatabase()
        end
        mailboxOpen = false
        savePending = false
        addon:Debug("Mailbox closed")
    end, "MailboxScanner")
end

-- 检查邮箱当前是否打开
function MailboxScanner:IsMailboxOpen()
    return mailboxOpen
end
