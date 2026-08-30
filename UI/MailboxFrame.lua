-- 邮箱窗口
-- 邮箱查看界面

local addon = Guda

local MailboxFrame = {}
addon.Modules.MailboxFrame = MailboxFrame

local currentViewChar = nil
local searchText = ""
local isReadOnlyMode = true -- 本插件中邮箱始终为只读模式（查看离线数据）
local itemButtons = {}
local mailboxRows = {}
local currentPage = 1
local ITEMS_PER_PAGE = 7
local mailboxClickCatcher = nil

-- 加载时
function GudaBag.MailboxFrame_OnLoad(self)
    self:SetClampedToScreen(true)

    -- 应用边框可见性设置
    if MailboxFrame.UpdateBorderVisibility then
        MailboxFrame:UpdateBorderVisibility()
    end

    -- 设置初始背景
    -- (此处已不再需要，UpdateBorderVisibility 会处理)

    -- 设置搜索框占位文字
    local searchBox = getglobal(self:GetName().."_SearchBar_SearchBox")
    if searchBox then
        searchBox:SetText(GudaBag.L["Search mailbox..."])
        searchBox:SetTextColor(0.5, 0.5, 0.5, 1)
    end

    -- 本地化翻页按钮（XML 中写死了 "Prev"/"Next"，在此覆盖）
    local prevBtn = getglobal("Guda_MailboxFrame_PrevPageButton")
    if prevBtn then prevBtn:SetText(GudaBag.L["Prev"]) end
    local nextBtn = getglobal("Guda_MailboxFrame_NextPageButton")
    if nextBtn then nextBtn:SetText(GudaBag.L["Next"]) end

    -- 创建不可见的全屏框架，用于在搜索输入时捕获邮箱窗口外部的点击
    if not mailboxClickCatcher then
        mailboxClickCatcher = CreateFrame("Frame", "Guda_MailboxClickCatcher", UIParent)
        mailboxClickCatcher:SetFrameStrata("BACKGROUND")
        mailboxClickCatcher:SetAllPoints(UIParent)
        mailboxClickCatcher:EnableMouse(true)
        mailboxClickCatcher:Hide()

        mailboxClickCatcher:SetScript("OnMouseDown", function()
            if GudaBag.MailboxFrame_ClearSearch then
                GudaBag.MailboxFrame_ClearSearch()
            end
        end)
    end
end

-- 清除搜索焦点
function GudaBag.MailboxFrame_ClearSearch()
    local searchBox = getglobal("Guda_MailboxFrame_SearchBar_SearchBox")
    if searchBox then
        searchBox:ClearFocus()
    end
end

-- 显示时
function GudaBag.MailboxFrame_OnShow(self)
    -- 应用边框可见性设置
    if MailboxFrame.UpdateBorderVisibility then
        MailboxFrame:UpdateBorderVisibility()
    end

    -- 应用窗口透明度
    if GudaBag.ApplyBackgroundTransparency then
        GudaBag.ApplyBackgroundTransparency()
    end

    MailboxFrame:Update()
end

-- 更新边框可见性
function MailboxFrame:UpdateBorderVisibility()
    -- 若可用则使用主题模块
    if addon.Modules and addon.Modules.Theme then
        addon.Modules.Theme:ApplyToFrame(Guda_MailboxFrame)
        return
    end

    local hideBorders = addon.Modules.DB:GetSetting("hideBorders")
    if hideBorders then
        Guda:ApplyBackdrop(Guda_MailboxFrame, "MINIMALIST_BORDER", "DEFAULT")
    else
        Guda:ApplyBackdrop(Guda_MailboxFrame, "DEFAULT_FRAME", "DEFAULT")
    end
end

-- 隐藏时
function GudaBag.MailboxFrame_OnHide(self)
    -- 邮箱窗口隐藏时关闭所有打开的下拉菜单
    CloseDropDownMenus()
end

-- 切换可见性
function MailboxFrame:Toggle()
    if Guda_MailboxFrame:IsShown() then
        Guda_MailboxFrame:Hide()
    else
        Guda_MailboxFrame:Show()
    end
end

-- 显示指定角色的邮箱
function MailboxFrame:GetCurrentViewChar()
    return currentViewChar
end

function MailboxFrame:ShowCharacter(fullName)
    currentViewChar = fullName
    currentPage = 1
    self:Update()
end

-- 分页
function MailboxFrame:NextPage()
    currentPage = currentPage + 1
    self:Update()
end

function MailboxFrame:PrevPage()
    if currentPage > 1 then
        currentPage = currentPage - 1
        self:Update()
    end
end

-- 初始化模块
function MailboxFrame:Initialize()
    -- 如需则注册事件
end

-- 更新邮箱窗口
function MailboxFrame:Update()
    if not Guda_MailboxFrame:IsShown() then return end

    -- 决定显示哪个角色
    local charFullName = currentViewChar or addon.Modules.DB:GetPlayerFullName()
    local mailboxData = addon.Modules.DB:GetCharacterMailbox(charFullName)
    
    -- 从全名中提取角色名
    local charName = charFullName
    local dashPos = string.find(charFullName, "-")
    if dashPos then
        charName = string.sub(charFullName, 1, dashPos - 1)
    end

    getglobal("Guda_MailboxFrame_Title"):SetText(format(GudaBag.L["%s's Mailbox"], charName))

    -- 根据搜索文本筛选邮件
    local filteredItems = {}
    local totalItems = table.getn(mailboxData)
    for i, mail in ipairs(mailboxData) do
        local matchesSearch = true
        if searchText ~= "" then
            matchesSearch = false
            if mail.sender and string.find(string.lower(mail.sender), searchText) then
                matchesSearch = true
            elseif mail.subject and string.find(string.lower(mail.subject), searchText) then
                matchesSearch = true
            elseif mail.item and mail.item.name and string.find(string.lower(mail.item.name), searchText) then
                matchesSearch = true
            end
        end

        if matchesSearch then
            table.insert(filteredItems, mail)
        end
    end

    -- 显示邮件
    local emptyMessage = getglobal("Guda_MailboxFrame_EmptyMessage")
    if emptyMessage then
        if totalItems == 0 then
            emptyMessage:SetText(GudaBag.L["No mailbox data found for this character.\n\nVisit a mailbox in-game to save your mail data."])
            emptyMessage:Show()
        else
            emptyMessage:Hide()
        end
    end

    self:DisplayItems(filteredItems, charFullName, totalItems)
end

-- 以列表形式显示邮箱邮件
function MailboxFrame:DisplayItems(items, charFullName, totalMails)
    local container = getglobal("Guda_MailboxFrame_ItemContainer")
    
    -- 先隐藏所有已有行
    for _, row in pairs(mailboxRows) do
        row:Hide()
    end

    local totalItems = table.getn(items)
    local totalPages = math.max(1, math.ceil(totalItems / ITEMS_PER_PAGE))
    
    if currentPage > totalPages then
        currentPage = totalPages
    end

    local startIndex = (currentPage - 1) * ITEMS_PER_PAGE + 1
    local endIndex = math.min(startIndex + ITEMS_PER_PAGE - 1, totalItems)

    local rowIndex = 1
    for i = startIndex, endIndex do
        local mail = items[i]
        local row = mailboxRows[rowIndex]
        if not row then
            row = CreateFrame("Frame", "Guda_MailboxRow" .. rowIndex, container, "Guda_MailboxRowTemplate")
            mailboxRows[rowIndex] = row
        end
        
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(rowIndex - 1) * 55)

        -- 行内金币框架
        local moneyFrame = getglobal(row:GetName() .. "_MoneyFrame")
        if moneyFrame then
            -- 确保行内金币框架不会自动更新为角色金币
            moneyFrame.moneyType = "STATIC"
            moneyFrame:UnregisterAllEvents()
            moneyFrame:SetScript("OnShow", nil) -- 禁用暴雪自带的自动更新 OnShow
            moneyFrame:SetScript("OnEvent", nil)

            -- 禁用金币按钮的原生点击（打开 CoinPickupFrame 拆分货币）。
            -- 邮箱中的货币是只读的（不是玩家自己的钱），CoinPickupFrame.maxMoney
            -- 未设置，点击会报错；且 SmallMoneyFrameTemplate 自带 OnClick。
            if GudaBag.DisableMoneyCoinButtons then
                GudaBag.DisableMoneyCoinButtons(moneyFrame)
            end
            
            -- 恢复金币框架的右对齐，避免与图标重叠
            moneyFrame:ClearAllPoints()
            moneyFrame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 8)
        end

        if (mail.money or 0) > 0 then
            moneyFrame:Show()
            MoneyFrame_Update(moneyFrame:GetName(), mail.money)
        else
            if moneyFrame then moneyFrame:Hide() end
        end
        
        -- 填充行数据
        local sender = mail.sender or "Unknown"
        getglobal(row:GetName() .. "_Sender"):SetText(sender)

        local subject = mail.subject or "No Subject"
        if mail.item and mail.item.quality then
            local r, g, b = addon.Modules.Utils:GetQualityColor(mail.item.quality)
            subject = addon.Modules.Utils:ColorText(subject, r, g, b)
        end
        getglobal(row:GetName() .. "_Subject"):SetText(subject)
        
        local expireText = ""
        if mail.daysLeft then
            if mail.daysLeft < 1 then
                expireText = string.format("|cffff0000%dh|r", math.floor(mail.daysLeft * 24))
            else
                expireText = string.format("%dd", math.floor(mail.daysLeft))
            end
        end
        getglobal(row:GetName() .. "_ExpireTime"):SetText(expireText)
        
        -- 物品按钮
        local itemButton = getglobal(row:GetName() .. "_ItemButton")
        -- 如需可重新赋值共享命名空间的函数，但它应通过全局或插件可用
        
        itemButton.isBank = false
        itemButton.otherChar = charFullName
        itemButton.mailData = mail
        itemButton.isMail = true
        itemButton.mailIndex = mail.mailIndex
        itemButton.mailItemIndex = mail.itemIndex or 1

        -- 在行内垂直居中
        if itemButton then
            itemButton:ClearAllPoints()
            itemButton:SetPoint("LEFT", row, "LEFT", 10, 0)
        end
        
        if mail.item and (mail.item.texture or mail.item.link) then
            GudaBag.ItemButton_SetItem(itemButton, nil, nil, mail.item, false, charFullName, true, true)
            itemButton.isMail = true
            itemButton.mailData = mail
            itemButton.mailIndex = mail.mailIndex
            itemButton.mailItemIndex = mail.itemIndex or 1
        else
            GudaBag.ItemButton_SetItem(itemButton, nil, nil, nil, false, charFullName, true, true)
            itemButton.isMail = true
            itemButton.mailData = mail
            itemButton.mailIndex = mail.mailIndex
            itemButton.mailItemIndex = 1
            
            local icon = getglobal(itemButton:GetName().."IconTexture") or getglobal(itemButton:GetName().."Icon")
            if icon then
                if (mail.money or 0) > 0 then
                    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
                elseif mail.packageIcon then
                    icon:SetTexture(mail.packageIcon)
                else
                    icon:SetTexture("Interface\\Icons\\INV_Letter_15")
                end
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:Show()
            end
            -- 为邮件物品隐藏品质边框
            if itemButton._borderTinted then
                if itemButton._qualityBorder then
                    itemButton._qualityBorder:Hide()
                end
                itemButton._borderTinted = false
            end
        end

        row:Show()
        rowIndex = rowIndex + 1
    end

    -- 更新翻页按钮
    local prevBtn = getglobal("Guda_MailboxFrame_PrevPageButton")
    local nextBtn = getglobal("Guda_MailboxFrame_NextPageButton")
    
    if currentPage > 1 then
        prevBtn:Enable()
    else
        prevBtn:Disable()
    end
    
    if currentPage < totalPages then
        nextBtn:Enable()
    else
        nextBtn:Disable()
    end
    
    -- 更新分页文本
    local paginationText = getglobal("Guda_MailboxFrame_Pagination_Text")
    if paginationText then
        if totalMails == 0 then
            paginationText:SetText(GudaBag.L["No Mail"])
        else
            paginationText:SetText(string.format("%d/%d (items: %d)", currentPage, totalPages, totalMails or 0))
        end
    end
end

-- 搜索文本变化
function GudaBag.MailboxFrame_OnSearchTextChanged()
    local searchBox = getglobal("Guda_MailboxFrame_SearchBar_SearchBox")
    local text = searchBox:GetText()
    if text == GudaBag.L["Search mailbox..."] then
        searchText = ""
    else
        searchText = string.lower(text)
    end
    currentPage = 1
    MailboxFrame:Update()
end

-- 显示角色选择菜单
local function MailboxCharacterMenu_Initialize()
    local DB = addon.Modules.DB
    local currentPlayerFullName = DB:GetPlayerFullName()
    local characters = DB:GetAllCharacters(true, true)

    local own, shared = {}, {}
    for _, char in ipairs(characters) do
        if not DB:IsGoldBlacklisted(char.fullName) or char.fullName == currentPlayerFullName then
            if char.isShared then
                table.insert(shared, char)
            else
                table.insert(own, char)
            end
        end
    end

    for _, char in ipairs(own) do
        local charFullName = char.fullName
        local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
        local r, g, b = 1, 1, 1
        if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

        local info = {}
        info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
        info.func = function() MailboxFrame:ShowCharacter(charFullName) end
        local currentViewChar = MailboxFrame.GetCurrentViewChar and MailboxFrame:GetCurrentViewChar()
        info.checked = (currentViewChar == charFullName or (not currentViewChar and charFullName == currentPlayerFullName))
        UIDropDownMenu_AddButton(info)
    end

    if table.getn(shared) > 0 then
        local sep = {}
        sep.text = GudaBag.L["Other Accounts"]
        sep.isTitle = 1
        sep.notCheckable = 1
        UIDropDownMenu_AddButton(sep)

        for _, char in ipairs(shared) do
            local charFullName = char.fullName
            local classColor = char.classToken and RAID_CLASS_COLORS[char.classToken]
            local r, g, b = 1, 1, 1
            if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

            local info = {}
            info.text = addon.Modules.Utils:ColorText(char.name, r, g, b)
            info.func = function() MailboxFrame:ShowCharacter(charFullName) end
            local currentViewChar = MailboxFrame.GetCurrentViewChar and MailboxFrame:GetCurrentViewChar()
            info.checked = (currentViewChar == charFullName)
            UIDropDownMenu_AddButton(info)
        end
    end
end

function GudaBag.MailboxFrame_ShowCharacterMenu()
    local menuFrame = getglobal("Guda_MailboxCharacterMenu")
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "Guda_MailboxCharacterMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(menuFrame, MailboxCharacterMenu_Initialize, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end
