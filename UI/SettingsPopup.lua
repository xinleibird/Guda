-- Guda 设置弹窗
-- 调整插件设置的界面

local addon = Guda

local SettingsPopup = {}
addon.Modules.SettingsPopup = SettingsPopup

-- 章节标题辅助函数：创建金色章节标签并带分隔线
local function CreateSectionHeader(parent, text, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
    label:SetText(GudaBag.L[text] or text)
    label:SetTextColor(1, 0.82, 0, 1)

    -- 从标签延伸到右边缘的分隔线
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -5, 0)
    line:SetTexture(0.6, 0.6, 0.6, 0.3)

    return label
end

-- 打开/切换设置的全局函数（从 XML 调用，点击可开可关）
function GudaBag.OpenSettings()
    local frame = getglobal("Guda_SettingsPopup")
    if frame then
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

-- OnLoad
function GudaBag.SettingsPopup_OnLoad(self)
    self:SetClampedToScreen(true)

    -- 设置初始底板
    Guda:ApplyBackdrop(self, "DEFAULT_FRAME")

    local title = getglobal(self:GetName().."_Title")
    title:SetText(GudaBag.L["Guda Settings"])
    -- 增大标题字体大小
    local titleFont, _, titleFlags = title:GetFont()
    if titleFont then
        title:SetFont(titleFont, 16, titleFlags)
    end

    -- 运行时本地化 XML 中定义的页签按钮标签
    local function localizeTabBtn(btnName, key)
        local fs = getglobal(btnName .. "_Text")
        if fs then fs:SetText(GudaBag.L[key]) end
    end
    localizeTabBtn("Guda_SettingsPopup_GeneralTabButton",    "General")
    localizeTabBtn("Guda_SettingsPopup_LayoutTabButton",     "Layout")
    localizeTabBtn("Guda_SettingsPopup_IconsTabButton",      "Icons")
    localizeTabBtn("Guda_SettingsPopup_BarTabButton",        "Bar")
    localizeTabBtn("Guda_SettingsPopup_CategoriesTabButton", "Categories")
    localizeTabBtn("Guda_SettingsPopup_GuideTabButton",      "Guide")

    -- 本地化分类页签页眉（在 XML 中设置）
    local catHeader = getglobal("Guda_SettingsPopup_CategoriesTab_Header")
    if catHeader then catHeader:SetText(GudaBag.L["Manage item categories and their display order:"]) end

    -- 设置使用说明文本（已本地化）
    local instructions = getglobal("Guda_SettingsPopup_GuideTab_Instructions")
    if instructions then
        instructions:SetText(GudaBag.L["GUIDE_TEXT"])
    end

    -- 为每个页签创建章节标题
    local generalTab = getglobal("Guda_SettingsPopup_GeneralTab")
    if generalTab then
        CreateSectionHeader(generalTab, "Appearance", -12)
        CreateSectionHeader(generalTab, "Options", -140)
        CreateSectionHeader(generalTab, "Automation", -250)
    end

    local layoutTab = getglobal("Guda_SettingsPopup_LayoutTab")
    if layoutTab then
        CreateSectionHeader(layoutTab, "View", -12)
        CreateSectionHeader(layoutTab, "Columns", -100)
        CreateSectionHeader(layoutTab, "Options", -240)
    end

    local iconsTab = getglobal("Guda_SettingsPopup_IconsTab")
    if iconsTab then
        CreateSectionHeader(iconsTab, "Icon", -12)
        CreateSectionHeader(iconsTab, "Icon Options", -190)
    end

    local barTab = getglobal("Guda_SettingsPopup_BarTab")
    if barTab then
        CreateSectionHeader(barTab, "Quest Bar", -12)
        CreateSectionHeader(barTab, "Tracked", -120)
    end

    Guda:Debug("Settings popup loaded")
end

-- 页签切换逻辑（GudaPlates 风格）
function GudaBag.SettingsPopup_SelectTab(tabName)
    -- 隐藏所有页签内容界面
    local tabs = {
        general = getglobal("Guda_SettingsPopup_GeneralTab"),
        layout = getglobal("Guda_SettingsPopup_LayoutTab"),
        icons = getglobal("Guda_SettingsPopup_IconsTab"),
        bar = getglobal("Guda_SettingsPopup_BarTab"),
        categories = getglobal("Guda_SettingsPopup_CategoriesTab"),
        guide = getglobal("Guda_SettingsPopup_GuideTab"),
    }

    local bgs = {
        general = getglobal("Guda_SettingsPopup_GeneralTabButton_Bg"),
        layout = getglobal("Guda_SettingsPopup_LayoutTabButton_Bg"),
        icons = getglobal("Guda_SettingsPopup_IconsTabButton_Bg"),
        bar = getglobal("Guda_SettingsPopup_BarTabButton_Bg"),
        categories = getglobal("Guda_SettingsPopup_CategoriesTabButton_Bg"),
        guide = getglobal("Guda_SettingsPopup_GuideTabButton_Bg"),
    }

    -- 隐藏所有页签并重置背景
    for _, tab in pairs(tabs) do
        if tab then tab:Hide() end
    end
    for _, bg in pairs(bgs) do
        if bg then bg:SetTexture(1, 1, 1, 0.1) end
    end

    -- 显示选中的页签并高亮其按钮
    if tabs[tabName] then tabs[tabName]:Show() end
    if bgs[tabName] then bgs[tabName]:SetTexture(1, 1, 1, 0.3) end

    -- 分类页签的特殊处理
    if tabName == "categories" then
        GudaBag.SettingsPopup_CategoriesTab_Update()
    end
end

-- OnShow
function GudaBag.SettingsPopup_OnShow(self)
    -- 默认选中常规页签
    GudaBag.SettingsPopup_SelectTab("general")

    -- 加载当前设置
    local bagColumns = Guda.Modules.DB:GetSetting("bagColumns") or 10
    local bankColumns = Guda.Modules.DB:GetSetting("bankColumns") or 10
    local iconSize = Guda.Modules.DB:GetSetting("iconSize") or 37
    local iconFontSize = Guda.Modules.DB:GetSetting("iconFontSize") or 12
    local iconSpacing = Guda.Modules.DB:GetSetting("iconSpacing") or 4
    local lockBags = Guda.Modules.DB:GetSetting("lockBags")
    if lockBags == nil then
        lockBags = false
    end
    local hideBorders = Guda.Modules.DB:GetSetting("hideBorders")
    if hideBorders == nil then
        hideBorders = false
    end
    local showItemBorder = Guda.Modules.DB:GetSetting("showItemBorder")
    if showItemBorder == nil then
        showItemBorder = true
    end
    local showSearchBar = Guda.Modules.DB:GetSetting("showSearchBar")
    if showSearchBar == nil then
        showSearchBar = true
    end
    local showQuestBar = Guda.Modules.DB:GetSetting("showQuestBar")
    if showQuestBar == nil then
        showQuestBar = true
    end
    local hideBagline = Guda.Modules.DB:GetSetting("hideBagline")
    if hideBagline == nil then
        hideBagline = true  -- 默认：隐藏（“显示所有背包”未勾选）
    end
    local bgTransparency = Guda.Modules.DB:GetSetting("bgTransparency") or 0.15
    local bagViewType = Guda.Modules.DB:GetSetting("bagViewType") or "single"
    local bankViewType = Guda.Modules.DB:GetSetting("bankViewType") or "single"
    local questBarSize = Guda.Modules.DB:GetSetting("questBarSize") or 36
    local trackedBarSize = Guda.Modules.DB:GetSetting("trackedBarSize") or 36
    local junkOpacity = Guda.Modules.DB:GetSetting("junkOpacity") or 0.6

    -- 更新滑条和复选框
    local bagSlider = getglobal("Guda_SettingsPopup_BagColumnsSlider")
    local bankSlider = getglobal("Guda_SettingsPopup_BankColumnsSlider")
    local iconSizeSlider = getglobal("Guda_SettingsPopup_IconSizeSlider")
    local iconFontSizeSlider = getglobal("Guda_SettingsPopup_IconFontSizeSlider")
    local iconSpacingSlider = getglobal("Guda_SettingsPopup_IconSpacingSlider")
    local bgTransparencySlider = getglobal("Guda_SettingsPopup_BgTransparencySlider")
    local questBarSizeSlider = getglobal("Guda_SettingsPopup_QuestBarSizeSlider")
    local trackedBarSizeSlider = getglobal("Guda_SettingsPopup_TrackedBarSizeSlider")
    local junkOpacitySlider = getglobal("Guda_SettingsPopup_JunkOpacitySlider")
    local lockCheckbox = getglobal("Guda_SettingsPopup_LockBagsCheckbox")
    local hideBordersCheckbox = getglobal("Guda_SettingsPopup_HideBordersCheckbox")
    local itemBorderCheckbox = getglobal("Guda_SettingsPopup_ItemBorderCheckbox")
    local showSearchBarCheckbox = getglobal("Guda_SettingsPopup_ShowSearchBarCheckbox")
    local showQuestBarCheckbox = getglobal("Guda_SettingsPopup_ShowQuestBarCheckbox")
    local hoverBaglineCheckbox = getglobal("Guda_SettingsPopup_HoverBaglineCheckbox")
    local hideFooterCheckbox = getglobal("Guda_SettingsPopup_HideFooterCheckbox")
    local showTooltipCountsCheckbox = getglobal("Guda_SettingsPopup_ShowTooltipCountsCheckbox")
    local showEquipSetCategoriesCheckbox = getglobal("Guda_SettingsPopup_ShowEquipSetCategoriesCheckbox")
    local bagViewDropdown = getglobal("Guda_SettingsPopup_BagViewDropdown")
    local bankViewDropdown = getglobal("Guda_SettingsPopup_BankViewDropdown")
    local themeDropdown = getglobal("Guda_SettingsPopup_ThemeDropdown")

    local showTooltipCounts = Guda.Modules.DB:GetSetting("showTooltipCounts")
    if showTooltipCounts == nil then
        showTooltipCounts = true
    end

    if bagSlider then
        bagSlider:SetValue(bagColumns)
    end

    if bankSlider then
        bankSlider:SetValue(bankColumns)
    end

    if iconSizeSlider then
        iconSizeSlider:SetValue(iconSize)
    end

    if iconFontSizeSlider then
        iconFontSizeSlider:SetValue(iconFontSize)
    end

    if iconSpacingSlider then
        iconSpacingSlider:SetValue(iconSpacing)
    end

    if bgTransparencySlider then
        bgTransparencySlider:SetValue(bgTransparency)
    end

    if questBarSizeSlider then
        questBarSizeSlider:SetValue(questBarSize)
    end

    if trackedBarSizeSlider then
        trackedBarSizeSlider:SetValue(trackedBarSize)
    end

    if junkOpacitySlider then
        junkOpacitySlider:SetValue(junkOpacity)
    end

    if lockCheckbox then
        lockCheckbox:SetChecked(lockBags and 1 or 0)
    end

    if hideBordersCheckbox then
        hideBordersCheckbox:SetChecked(hideBorders and 1 or 0)
    end

    -- 刷新 pfUI 透明度复选框可见性
    local pfuiTranspCB = getglobal("Guda_SettingsPopup_UsePfUITransparencyCheckbox")
    if pfuiTranspCB then
        local currentTheme = Guda.Modules.DB:GetSetting("theme") or "guda"
        if currentTheme == "pfui" then
            local val = Guda.Modules.DB:GetSetting("usePfUITransparency")
            if val == nil then val = true end
            pfuiTranspCB:SetChecked(val and 1 or 0)
            pfuiTranspCB:Show()
        else
            pfuiTranspCB:Hide()
        end
    end

    if itemBorderCheckbox then
        itemBorderCheckbox:SetChecked(showItemBorder and 1 or 0)
    end

    if showSearchBarCheckbox then
        -- 勾选 = 常显搜索栏（"shown"）；不勾选 = 通过图标按钮显示
        local sbMode = Guda.Modules.DB:GetSetting("searchBarMode")
        if sbMode ~= "shown" and sbMode ~= "hidden" and sbMode ~= "toggle" then
            local legacy = Guda.Modules.DB:GetSetting("showSearchBar")
            sbMode = (legacy == false) and "toggle" or "shown"
        end
        showSearchBarCheckbox:SetChecked((sbMode == "shown") and 1 or 0)
    end

    if showQuestBarCheckbox then
        showQuestBarCheckbox:SetChecked(showQuestBar and 1 or 0)
    end

    if hoverBaglineCheckbox then
        -- 反向：勾选 = 显示背包 = 未隐藏
        hoverBaglineCheckbox:SetChecked(hideBagline and 0 or 1)
    end

    if showTooltipCountsCheckbox then
        showTooltipCountsCheckbox:SetChecked(showTooltipCounts and 1 or 0)
    end

    -- 新复选框
    local showEquipSetCategories = Guda.Modules.DB:GetSetting("showEquipSetCategories")
    if showEquipSetCategories == nil then showEquipSetCategories = true end
    if showEquipSetCategoriesCheckbox then
        showEquipSetCategoriesCheckbox:SetChecked(showEquipSetCategories and 1 or 0)
    end

    -- 自动锁定装备方案物品复选框
    local autoLockSetItemsCheckbox = getglobal("Guda_SettingsPopup_AutoLockSetItemsCheckbox")
    local autoLockSetItems = Guda.Modules.DB:GetSetting("autoLockSetItems")
    if autoLockSetItems == nil then autoLockSetItems = true end
    if autoLockSetItemsCheckbox then
        autoLockSetItemsCheckbox:SetChecked(autoLockSetItems and 1 or 0)
    end

    -- 显示分类计数复选框
    local showCategoryCountCheckbox = getglobal("Guda_SettingsPopup_ShowCategoryCountCheckbox")
    local showCategoryCount = Guda.Modules.DB:GetSetting("showCategoryCount")
    if showCategoryCount == nil then showCategoryCount = true end
    if showCategoryCountCheckbox then
        showCategoryCountCheckbox:SetChecked(showCategoryCount and 1 or 0)
    end

    -- 显示品质过滤栏复选框
    local showQualityBarCheckbox = getglobal("Guda_SettingsPopup_ShowQualityBarCheckbox")
    local showQualityBar = Guda.Modules.DB:GetSetting("showQualityBar")
    if showQualityBar == nil then showQualityBar = true end
    if showQualityBarCheckbox then
        showQualityBarCheckbox:SetChecked(showQualityBar and 1 or 0)
    end

    -- 显示分类侧栏复选框（移植自 OneBag 分类模块）
    local showCategoryBarCheckbox = getglobal("Guda_SettingsPopup_ShowCategoryBarCheckbox")
    local showCategoryBar = Guda.Modules.DB:GetSetting("showCategoryBar")
    if showCategoryBar == nil then showCategoryBar = false end
    if showCategoryBarCheckbox then
        showCategoryBarCheckbox:SetChecked(showCategoryBar and 1 or 0)
    end

    -- 自动化复选框
    local autoVendorJunkCheckbox = getglobal("Guda_SettingsPopup_AutoVendorJunkCheckbox")
    local autoVendorJunk = Guda.Modules.DB:GetSetting("autoVendorJunk")
    if autoVendorJunk == nil then autoVendorJunk = true end
    if autoVendorJunkCheckbox then
        autoVendorJunkCheckbox:SetChecked(autoVendorJunk and 1 or 0)
    end

    -- 白色物品作为垃圾复选框
    local whiteItemsJunkCheckbox = getglobal("Guda_SettingsPopup_WhiteItemsJunkCheckbox")
    local whiteItemsJunk = Guda.Modules.DB:GetSetting("whiteItemsJunk")
    if whiteItemsJunk == nil then whiteItemsJunk = false end
    if whiteItemsJunkCheckbox then
        whiteItemsJunkCheckbox:SetChecked(whiteItemsJunk and 1 or 0)
    end

    -- 自动拾取复选框
    local autoLootCheckbox = getglobal("Guda_SettingsPopup_AutoLootCheckbox")
    local autoFillRowsCheckbox = getglobal("Guda_SettingsPopup_AutoFillRowsCheckbox")
    if autoLootCheckbox then
        -- 其他插件已接管自动拾取时，隐藏复选框并强制 guda 的 autoLoot 关闭
        local externalLoot = false
        if Guda.Modules.DB and Guda.Modules.DB.HasExternalAutoLoot then
            externalLoot = Guda.Modules.DB:HasExternalAutoLoot()
        end
        if externalLoot then
            Guda.Modules.DB:SetSetting("autoLoot", false)
            autoLootCheckbox:Hide()
            -- 自动拾取隐藏后，把"自动补位"复选框上移到原自动拾取的位置，
            -- 避免该行左侧留下难看的空位。
            if autoFillRowsCheckbox then
                autoFillRowsCheckbox:ClearAllPoints()
                autoFillRowsCheckbox:SetPoint("TOPLEFT", "Guda_SettingsPopup_AutoVendorJunkCheckbox", "BOTTOMLEFT", 0, -8)
            end
        else
            autoLootCheckbox:Show()
            local autoLoot = Guda.Modules.DB:GetSetting("autoLoot") and true or false
            autoLootCheckbox:SetChecked(autoLoot and 1 or 0)
            -- 未隐藏时，把自动补位恢复为锚定到自动拾取右侧
            if autoFillRowsCheckbox then
                autoFillRowsCheckbox:ClearAllPoints()
                autoFillRowsCheckbox:SetPoint("LEFT", "Guda_SettingsPopup_AutoLootCheckbox", "RIGHT", 200, 0)
            end
        end
    end

    -- 自动打开蚌壳复选框
    local autoOpenClamsCheckbox = getglobal("Guda_SettingsPopup_AutoOpenClamsCheckbox")
    if autoOpenClamsCheckbox then
        local autoOpenClams = Guda.Modules.DB:GetSetting("autoOpenClams") and true or false
        autoOpenClamsCheckbox:SetChecked(autoOpenClams and 1 or 0)
    end

    -- 自动补位复选框
    autoFillRowsCheckbox = autoFillRowsCheckbox or getglobal("Guda_SettingsPopup_AutoFillRowsCheckbox")
    if autoFillRowsCheckbox then
        local autoFillRows = Guda.Modules.DB:GetSetting("autoFillRows") and true or false
        autoFillRowsCheckbox:SetChecked(autoFillRows and 1 or 0)
    end

    -- 自动关闭背包复选框（仅由 XML OnLoad 设置初始状态，而 OnLoad 运行时
    -- SavedVariables 可能尚未加载，会显示默认值；必须在这里按存档刷新）
    local autoCloseBagsCheckbox = getglobal("Guda_SettingsPopup_AutoCloseBagsCheckbox")
    if autoCloseBagsCheckbox then
        local autoClose = Guda.Modules.DB:GetSetting("autoCloseBags")
        if autoClose == nil then autoClose = true end
        autoCloseBagsCheckbox:SetChecked(autoClose and 1 or 0)
    end

    -- 自动打开背包复选框（同上，OnShow 时按存档刷新）
    local autoOpenBagsCheckbox = getglobal("Guda_SettingsPopup_AutoOpenBagsCheckbox")
    if autoOpenBagsCheckbox then
        local autoOpen = Guda.Modules.DB:GetSetting("autoOpenBags")
        if autoOpen == nil then autoOpen = true end
        autoOpenBagsCheckbox:SetChecked(autoOpen and 1 or 0)
    end

    -- 反向堆叠排序复选框（同上，OnShow 时按存档刷新）
    local reverseStackSortCheckbox = getglobal("Guda_SettingsPopup_ReverseStackSortCheckbox")
    if reverseStackSortCheckbox then
        local reverseStackSort = Guda.Modules.DB:GetSetting("reverseStackSort") and true or false
        reverseStackSortCheckbox:SetChecked(reverseStackSort and 1 or 0)
    end

    -- 标记不可用物品复选框（同上，OnShow 时按存档刷新）
    local markUnusableCheckbox = getglobal("Guda_SettingsPopup_MarkUnusableCheckbox")
    if markUnusableCheckbox then
        local markUnusable = Guda.Modules.DB:GetSetting("markUnusableItems")
        if markUnusable == nil then markUnusable = true end
        markUnusableCheckbox:SetChecked(markUnusable and 1 or 0)
    end

    -- 拾取标记样式下拉框
    local lootMarkerDropdown = getglobal("Guda_SettingsPopup_LootMarkerDropdown")
    if lootMarkerDropdown then
        local mode = GudaBag.GetLootMarkerMode()
        local names = GudaBag.LootMarkerModeNames()
        UIDropDownMenu_SetSelectedValue(lootMarkerDropdown, mode)
        UIDropDownMenu_SetText(names[mode] or names[0], lootMarkerDropdown)
    end

    if bagViewDropdown then
        UIDropDownMenu_SetSelectedValue(bagViewDropdown, bagViewType)
        local viewLabel = (bagViewType == "single" and (GudaBag.L["Single"] or "Single")) or (GudaBag.L["Category"] or "Category")
        UIDropDownMenu_SetText(viewLabel, bagViewDropdown)
    end

    if bankViewDropdown then
        UIDropDownMenu_SetSelectedValue(bankViewDropdown, bankViewType)
        local viewLabel = (bankViewType == "single" and (GudaBag.L["Single"] or "Single")) or (GudaBag.L["Category"] or "Category")
        UIDropDownMenu_SetText(viewLabel, bankViewDropdown)
    end

    -- 初始化主题下拉框
    local themeDropdown = getglobal("Guda_SettingsPopup_ThemeDropdown")
    if themeDropdown then
        local currentTheme = Guda.Modules.DB:GetSetting("theme") or "guda"
        local names = { guda = "Guda", blizzard = "Blizzard", pfui = "pfUI", dragonflight = "Dragonflight" }
        UIDropDownMenu_SetSelectedValue(themeDropdown, currentTheme)
        UIDropDownMenu_SetText(names[currentTheme] or currentTheme, themeDropdown)
    end

    -- 应用边框可见性
    if SettingsPopup.UpdateBorderVisibility then
        SettingsPopup:UpdateBorderVisibility()
    end
end

-- 根据设置更新边框可见性
function SettingsPopup:UpdateBorderVisibility()
    if not addon or not addon.Modules or not addon.Modules.DB then return end

    local frame = getglobal("Guda_SettingsPopup")
    if not frame then return end

    local hideBorders = addon.Modules.DB:GetSetting("hideBorders")
    if hideBorders == nil then
        hideBorders = false
    end

    if hideBorders then
        addon:ApplyBackdrop(frame, "MINIMALIST_BORDER", "DEFAULT")
    else
        addon:ApplyBackdrop(frame, "DEFAULT_FRAME", "DEFAULT")
    end
end

-- 切换可见性
function SettingsPopup:Toggle()
    local frame = getglobal("Guda_SettingsPopup")
    if frame then
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

-- 背包列数滑条 OnLoad
function GudaBag.SettingsPopup_BagColumnsSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("5")
    getglobal(self:GetName().."High"):SetText("20")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Bag columns"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(5, 20)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("bagColumns") or 10
    self:SetValue(currentValue)
end

-- 背包列数滑条 OnValueChanged
function GudaBag.SettingsPopup_BagColumnsSlider_OnValueChanged(self)
    local value = self:GetValue()
    
    -- 更新显示文本
    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Bag columns: %d"], value))
    
    -- 保存设置
    Guda.Modules.DB:SetSetting("bagColumns", value)
    
    -- 如果背包界面打开则刷新
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end
end

-- 银行列数滑条 OnLoad
function GudaBag.SettingsPopup_BankColumnsSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("5")
    getglobal(self:GetName().."High"):SetText("20")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Bank columns"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(5, 20)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("bankColumns") or 10
    self:SetValue(currentValue)
end

-- 银行列数滑条 OnValueChanged
function GudaBag.SettingsPopup_BankColumnsSlider_OnValueChanged(self)
    local value = self:GetValue()
    
    -- 更新显示文本
    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Bank columns: %d"], value))
    
    -- 保存设置
    Guda.Modules.DB:SetSetting("bankColumns", value)
    
    -- 如果银行界面打开则刷新
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 背景透明度滑条 OnLoad
function GudaBag.SettingsPopup_BgTransparencySlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("0%")
    getglobal(self:GetName().."High"):SetText("100%")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Background Transparency"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(0.0, 1.0)
    self:SetValueStep(0.05)

    local currentValue = Guda.Modules.DB:GetSetting("bgTransparency") or 0.15
    self:SetValue(currentValue)
end

-- 背景透明度滑条 OnValueChanged
function GudaBag.SettingsPopup_BgTransparencySlider_OnValueChanged(self)
    local value = self:GetValue()
    -- 四舍五入到两位小数
    value = math.floor(value * 100 + 0.5) / 100

    -- 更新显示文本
    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Background Transparency: %d%%"], math.floor(value * 100)))

    -- 保存设置
    Guda.Modules.DB:SetSetting("bgTransparency", value)

    -- 应用透明度
    GudaBag.ApplyBackgroundTransparency()
end

-- 将背景透明度应用到背包和银行界面
function GudaBag.ApplyBackgroundTransparency()
    -- 如果 Theme 模块可用，委托给它（正确处理两种主题）
    if Guda.Modules and Guda.Modules.Theme then
        Guda.Modules.Theme:ApplyToAllFrames()
        return
    end

    -- 后备：原始行为
    local transparency = Guda.Modules.DB:GetSetting("bgTransparency") or 0.15
    local alpha = 1.0 - transparency

    local frames = { "Guda_BagFrame", "Guda_BankFrame", "Guda_MailboxFrame", "Guda_SettingsPopup" }
    for _, frameName in ipairs(frames) do
        local frame = getglobal(frameName)
        if frame then
            frame:SetAlpha(1.0)
            frame:SetBackdropColor(0, 0, 0, alpha)
        end
    end
end

-- 图标大小滑条 OnLoad
function GudaBag.SettingsPopup_IconSizeSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("22px")
    getglobal(self:GetName().."High"):SetText("64px")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Icon size"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(22, 64)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("iconSize") or 37
    self:SetValue(currentValue)
end

-- 图标大小滑条 OnValueChanged
function GudaBag.SettingsPopup_IconSizeSlider_OnValueChanged(self)
    local value = math.floor(self:GetValue() + 0.5)

    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Icon size: %dpx"], value))

    Guda.Modules.DB:SetSetting("iconSize", value)

    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 图标字体大小滑条 OnLoad
function GudaBag.SettingsPopup_IconFontSizeSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("8px")
    getglobal(self:GetName().."High"):SetText("20px")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Icon font size"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(8, 20)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("iconFontSize") or 12
    self:SetValue(currentValue)
end

-- 图标字体大小滑条 OnValueChanged
function GudaBag.SettingsPopup_IconFontSizeSlider_OnValueChanged(self)
    local value = math.floor(self:GetValue() + 0.5)

    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Icon font size: %dpx"], value))

    Guda.Modules.DB:SetSetting("iconFontSize", value)

    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 图标间距滑条 OnLoad
function GudaBag.SettingsPopup_IconSpacingSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("0px")
    getglobal(self:GetName().."High"):SetText("20px")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Icon spacing"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(0, 20)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("iconSpacing") or 4
    self:SetValue(currentValue)
end

-- 图标间距滑条 OnValueChanged
function GudaBag.SettingsPopup_IconSpacingSlider_OnValueChanged(self)
    local value = math.floor(self:GetValue() + 0.5)
    local displayValue = value >= 0 and value .. "px" or value .. "px"
    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Icon spacing: %s"], tostring(displayValue)))

    -- 保存设置
    Guda.Modules.DB:SetSetting("iconSpacing", value)

    -- 更新背包界面
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    -- 更新银行界面
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        if Guda.Modules.BankFrame.UpdateFooterVisibility then
            Guda.Modules.BankFrame:UpdateFooterVisibility()
        end
        Guda.Modules.BankFrame:Update()
    end
end

-- 任务栏大小滑条 OnLoad
function GudaBag.SettingsPopup_QuestBarSizeSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("22px")
    getglobal(self:GetName().."High"):SetText("64px")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Quest bar size"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(22, 64)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("questBarSize") or 36
    self:SetValue(currentValue)
end

-- 任务栏大小滑条 OnValueChanged
function GudaBag.SettingsPopup_QuestBarSizeSlider_OnValueChanged(self)
    local value = math.floor(self:GetValue() + 0.5)

    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Quest bar size: %dpx"], value))

    Guda.Modules.DB:SetSetting("questBarSize", value)

    -- 更新任务物品栏
    if Guda.Modules.QuestItemBar and Guda.Modules.QuestItemBar.Update then
        Guda.Modules.QuestItemBar:Update()
    end
end

-- 跟踪栏大小滑条 OnLoad
function GudaBag.SettingsPopup_TrackedBarSizeSlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("22px")
    getglobal(self:GetName().."High"):SetText("64px")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Tracked bar size"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(22, 64)
    self:SetValueStep(1)

    local currentValue = Guda.Modules.DB:GetSetting("trackedBarSize") or 36
    self:SetValue(currentValue)
end

-- 跟踪栏大小滑条 OnValueChanged
function GudaBag.SettingsPopup_TrackedBarSizeSlider_OnValueChanged(self)
    local value = math.floor(self:GetValue() + 0.5)

    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Tracked bar size: %dpx"], value))

    Guda.Modules.DB:SetSetting("trackedBarSize", value)

    -- 更新跟踪物品栏
    if Guda.Modules.TrackedItemBar and Guda.Modules.TrackedItemBar.Update then
        Guda.Modules.TrackedItemBar:Update()
    end
end

-- 锁定背包复选框 OnLoad
function GudaBag.SettingsPopup_LockBagsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Lock Window"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_LOCK_BAGS_TT

    local isLocked = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        isLocked = Guda.Modules.DB:GetSetting("lockBags")
        if isLocked == nil then
            isLocked = false
        end
    end

    self:SetChecked(isLocked and 1 or 0)
end

-- 锁定背包复选框 OnClick
function GudaBag.SettingsPopup_LockBagsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("lockBags", isChecked)
    end

    -- 更新背包界面可拖动性
    if Guda and Guda.Modules and Guda.Modules.BagFrame and Guda.Modules.BagFrame.UpdateLockState then
        Guda.Modules.BagFrame:UpdateLockState()
    end

    -- 更新银行界面可拖动性
    if Guda and Guda.Modules and Guda.Modules.BankFrame and Guda.Modules.BankFrame.UpdateLockState then
        Guda.Modules.BankFrame:UpdateLockState()
    end
end

-- 隐藏边框复选框 OnLoad
function GudaBag.SettingsPopup_HideBordersCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Hide Frame Borders"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_HIDE_BORDERS_TT

    local hideBorders = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        hideBorders = Guda.Modules.DB:GetSetting("hideBorders")
        if hideBorders == nil then
            hideBorders = false
        end
    end

    self:SetChecked(hideBorders and 1 or 0)
end

-- 隐藏边框复选框 OnClick
function GudaBag.SettingsPopup_HideBordersCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("hideBorders", isChecked)
    end

    -- 将主题应用到所有界面（遵守 hideBorders 设置）
    if Guda.Modules and Guda.Modules.Theme then
        Guda.Modules.Theme:ApplyToAllFrames()
    else
        -- 如果主题模块未加载则回退
        local bagFrame = getglobal("Guda_BagFrame")
        if bagFrame then
            Guda:ApplyBackdrop(bagFrame, isChecked and "MINIMALIST_BORDER" or "DEFAULT_FRAME", "DEFAULT")
        end
        local bankFrame = getglobal("Guda_BankFrame")
        if bankFrame then
            Guda:ApplyBackdrop(bankFrame, isChecked and "MINIMALIST_BORDER" or "DEFAULT_FRAME", "DEFAULT")
        end
        local mailboxFrame = getglobal("Guda_MailboxFrame")
        if mailboxFrame then
            Guda:ApplyBackdrop(mailboxFrame, isChecked and "MINIMALIST_BORDER" or "DEFAULT_FRAME", "DEFAULT")
        end
        if SettingsPopup.UpdateBorderVisibility then
            SettingsPopup:UpdateBorderVisibility()
        end
    end
end

-- 物品边框复选框 OnLoad（合并原装备边框/其他物品边框，同时控制两者）
function GudaBag.SettingsPopup_ItemBorderCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Item Borders"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_QUALITY_BORDER_EQ_TT

    -- 统一"物品边框"开关
    local showBorders = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        local v = Guda.Modules.DB:GetSetting("showItemBorder")
        if v == nil then v = true end
        showBorders = v
    end

    self:SetChecked(showBorders and 1 or 0)
end

-- 物品边框复选框 OnClick（只写统一设置 showItemBorder）
function GudaBag.SettingsPopup_ItemBorderCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showItemBorder", isChecked)
    end

    -- 更新背包和银行界面
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 显示搜索栏复选框 OnLoad
function GudaBag.SettingsPopup_ShowSearchBarCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Show Search Bar"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_SHOW_SEARCH_BAR_TT

    -- 复选框含义：勾选 = 常显搜索栏（"shown"）；不勾选 = 通过图标按钮
    -- 显示（"toggle"，搜索栏默认隐藏，点击背包上的放大镜图标展开）。
    local mode = "shown"
    if Guda and Guda.Modules and Guda.Modules.DB then
        mode = Guda.Modules.DB:GetSetting("searchBarMode")
        if mode ~= "shown" and mode ~= "hidden" and mode ~= "toggle" then
            local legacy = Guda.Modules.DB:GetSetting("showSearchBar")
            mode = (legacy == false) and "toggle" or "shown"
        end
    end

    self:SetChecked((mode == "shown") and 1 or 0)
end

-- 显示搜索栏复选框 OnClick
function GudaBag.SettingsPopup_ShowSearchBarCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 勾选 = 常显搜索栏（"shown"）；不勾选 = 通过图标按钮显示
    --（"toggle"，搜索栏默认隐藏，点击背包上的放大镜图标展开）。
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showSearchBar", isChecked)
        Guda.Modules.DB:SetSetting("searchBarMode", isChecked and "shown" or "toggle")
    end

    -- 更新背包界面中的搜索栏可见性
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        -- 使用处理锚定的 UpdateSearchBarVisibility 函数
        if Guda.Modules.BagFrame.UpdateSearchBarVisibility then
            Guda.Modules.BagFrame:UpdateSearchBarVisibility()
        end
        Guda.Modules.BagFrame:Update()
    end

    -- 更新银行界面中的搜索栏可见性
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        -- 使用处理锚定的 UpdateSearchBarVisibility 函数
        if Guda.Modules.BankFrame.UpdateSearchBarVisibility then
            Guda.Modules.BankFrame:UpdateSearchBarVisibility()
        end
        Guda.Modules.BankFrame:Update()
    end
end

-- 显示任务栏复选框 OnLoad
function GudaBag.SettingsPopup_ShowQuestBarCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Show Quest Bar"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_SHOW_QUEST_BAR_TT

    local showQuestBar = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        showQuestBar = Guda.Modules.DB:GetSetting("showQuestBar")
        if showQuestBar == nil then
            showQuestBar = true
        end
    end

    self:SetChecked(showQuestBar and 1 or 0)
end

-- 显示任务栏复选框 OnClick
function GudaBag.SettingsPopup_ShowQuestBarCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showQuestBar", isChecked)
    end

    -- 更新任务栏可见性
    if Guda.Modules.QuestItemBar and Guda.Modules.QuestItemBar.Update then
        Guda.Modules.QuestItemBar:Update()
    end
end

-- 悬停背包栏复选框 OnLoad
function GudaBag.SettingsPopup_HoverBaglineCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Show All Bags"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_HIDE_BAGLINE_TT

    local hideBagline = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        local val = Guda.Modules.DB:GetSetting("hideBagline")
        if val == nil then
            hideBagline = true  -- 默认：隐藏（“显示所有背包”未勾选）
        else
            hideBagline = val
        end
    end

    -- 反向：勾选 = 未隐藏
    self:SetChecked(hideBagline and 0 or 1)
end

-- 显示所有背包复选框 OnClick（反向的 hideBagline）
function GudaBag.SettingsPopup_HoverBaglineCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置（反向：勾选表示显示，因此 hideBagline = false）
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("hideBagline", not isChecked)
    end

    -- 更新背包 0 图标
    local bag0 = getglobal("Guda_BagFrame_Toolbar_BagSlot0")
    if bag0 then
        GudaBag.BagSlot_Update(bag0, 0)
    end

    -- 更新背包界面
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end
end

-- 隐藏底部栏复选框 OnLoad
function GudaBag.SettingsPopup_HideFooterCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Hide Footer"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = L_HIDE_FOOTER_TT

    local hideFooter = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        hideFooter = Guda.Modules.DB:GetSetting("hideFooter")
        if hideFooter == nil then
            hideFooter = false
        end
    end

    self:SetChecked(hideFooter and 1 or 0)
end

-- 隐藏底部栏复选框 OnClick
function GudaBag.SettingsPopup_HideFooterCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("hideFooter", isChecked)
    end

    -- 更新背包界面
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        if Guda.Modules.BagFrame.UpdateFooterVisibility then
            Guda.Modules.BagFrame:UpdateFooterVisibility()
        end
        Guda.Modules.BagFrame:Update()
    end

    -- 更新银行界面
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        if Guda.Modules.BankFrame.UpdateFooterVisibility then
            Guda.Modules.BankFrame:UpdateFooterVisibility()
        end
        Guda.Modules.BankFrame:Update()
    end
end

-- 显示提示扩展复选框 OnLoad
function GudaBag.SettingsPopup_ShowTooltipCountsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Tooltip Extension"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end
    
    -- 提示文本
    self.tooltipText = GudaBag.L["Show how many of this item you have across all your characters in the item tooltip."]

    local showTooltipCounts = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        showTooltipCounts = Guda.Modules.DB:GetSetting("showTooltipCounts")
        if showTooltipCounts == nil then
            showTooltipCounts = true
        end
    end

    self:SetChecked(showTooltipCounts and 1 or 0)
end

-- 显示提示扩展复选框 OnClick
function GudaBag.SettingsPopup_ShowTooltipCountsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showTooltipCounts", isChecked)
    end
end

-- 垃圾物品不透明度滑条 OnLoad
function GudaBag.SettingsPopup_JunkOpacitySlider_OnLoad(self)
    getglobal(self:GetName().."Low"):SetText("10%")
    getglobal(self:GetName().."High"):SetText("100%")

    local text = getglobal(self:GetName().."Text")
    text:SetText(GudaBag.L["Junk item opacity"])

    -- 增大字体大小
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, 12, flags)
    end

    self:SetMinMaxValues(0.1, 1.0)
    self:SetValueStep(0.05)

    local currentValue = Guda.Modules.DB:GetSetting("junkOpacity") or 0.6
    self:SetValue(currentValue)
end

-- 垃圾物品不透明度滑条 OnValueChanged
function GudaBag.SettingsPopup_JunkOpacitySlider_OnValueChanged(self)
    local value = self:GetValue()
    -- 四舍五入到两位小数
    value = math.floor(value * 100 + 0.5) / 100

    -- 更新显示文本
    getglobal(self:GetName().."Text"):SetText(format(GudaBag.L["Junk item opacity: %d%%"], math.floor(value * 100)))

    -- 保存设置
    Guda.Modules.DB:SetSetting("junkOpacity", value)

    -- 如果背包界面可见则更新
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    -- 如果银行界面可见则更新
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 标记不可用物品复选框 OnLoad
function GudaBag.SettingsPopup_MarkUnusableCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Mark Unusable Items"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = GudaBag.L["Show a red tint on items that your character cannot use (wrong class, level, etc.)."]

    local markUnusable = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        markUnusable = Guda.Modules.DB:GetSetting("markUnusableItems")
        if markUnusable == nil then
            markUnusable = true
        end
    end

    self:SetChecked(markUnusable and 1 or 0)
end

-- 标记不可用物品复选框 OnClick
function GudaBag.SettingsPopup_MarkUnusableCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("markUnusableItems", isChecked)
    end

    -- 更新背包和银行界面以应用/移除红色色调
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 显示装备方案分类复选框 OnLoad
function GudaBag.SettingsPopup_ShowEquipSetCategoriesCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Equip Set Categories"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Show equipment set categories in category view."]

    local enabled = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("showEquipSetCategories")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 显示装备方案分类复选框 OnClick
function GudaBag.SettingsPopup_ShowEquipSetCategoriesCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showEquipSetCategories", isChecked)
    end

    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 自动锁定装备方案物品复选框 OnLoad
function GudaBag.SettingsPopup_AutoLockSetItemsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Lock Set Items"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Prevent selling and deleting items saved in equipment sets."]

    local enabled = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoLockSetItems")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 自动锁定装备方案物品复选框 OnClick
function GudaBag.SettingsPopup_AutoLockSetItemsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoLockSetItems", isChecked)
    end
end

-- 显示分类计数复选框 OnLoad
function GudaBag.SettingsPopup_ShowCategoryCountCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Show Category Count"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Show the item count next to each category header in category view."]

    local enabled = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("showCategoryCount")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 显示分类计数复选框 OnClick
function GudaBag.SettingsPopup_ShowCategoryCountCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showCategoryCount", isChecked)
    end

    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 显示品质过滤栏复选框 OnLoad
function GudaBag.SettingsPopup_ShowQualityBarCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Show Quality Bar"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Show the quality filter bar above the search box in the bag view."]

    local enabled = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("showQualityBar")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 显示品质过滤栏复选框 OnClick
function GudaBag.SettingsPopup_ShowQualityBarCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showQualityBar", isChecked)
    end

    -- 立即更新背包/银行中的品质过滤栏可见性
    if Guda.Modules.BagFrame and Guda.Modules.BagFrame.UpdateQualityBarVisibility then
        Guda.Modules.BagFrame:UpdateQualityBarVisibility()
    end
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 显示分类侧栏复选框 OnLoad（移植自 OneBag 分类模块）
function GudaBag.SettingsPopup_ShowCategoryBarCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Show Category Bar"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Show a vertical category filter bar on the left side of the bag (ported from OneBag). Click a category to filter items by type; click again to clear. Mutually exclusive with the quality filter."]

    local enabled = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("showCategoryBar")
        if enabled == nil then enabled = false end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 显示分类侧栏复选框 OnClick
function GudaBag.SettingsPopup_ShowCategoryBarCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("showCategoryBar", isChecked)
    end

    -- 更新分类侧栏可见性
    if Guda and Guda.Modules and Guda.Modules.BagFrame and Guda.Modules.BagFrame.UpdateCategoryBarVisibility then
        Guda.Modules.BagFrame:UpdateCategoryBarVisibility()
    end
end

-- 自动拾取复选框 OnLoad
function GudaBag.SettingsPopup_AutoLootCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Loot"])
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, 13, flags) end
    end

    -- 若其他插件（automaton / automatonEX / superapi）已接管自动拾取，
    -- 则隐藏本复选框且不生效，避免双重拾取。
    local externalLoot = false
    if Guda and Guda.Modules and Guda.Modules.DB and Guda.Modules.DB.HasExternalAutoLoot then
        externalLoot = Guda.Modules.DB:HasExternalAutoLoot()
    end
    if externalLoot then
        self:Hide()
        self._gudaSoftDisabled = true
        return
    end

    -- TurtleWoW 需要 SuperWoW 才能让插件驱动的自动拾取生效
    --（SetAutoloot 和 LootSlot 都被限制）。如果它不存在，则软
    -- 禁用：保持鼠标启用以便悬停时仍显示提示，但
    -- 标记按钮使 OnClick 成为无操作，并调暗标签。
    local hasSuperWoW = SetAutoloot ~= nil
    self._gudaSoftDisabled = not hasSuperWoW
    if hasSuperWoW then
        self.tooltipText = GudaBag.L["Automatically loot all items when looting a corpse or container."]
        if text then text:SetTextColor(1, 1, 1) end
    else
        self.tooltipText = GudaBag.L["Auto Loot requires the SuperWoW client mod. Install SuperWoW to enable this option."]
        if text then text:SetTextColor(0.5, 0.5, 0.5) end
    end

    local enabled = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoLoot") and true or false
    end
    self:SetChecked(enabled and 1 or 0)
end

-- 自动拾取复选框 OnClick
function GudaBag.SettingsPopup_AutoLootCheckbox_OnClick(self)
    -- 外部插件接管时，始终强制保持 guda 的 autoLoot 为关闭
    if Guda and Guda.Modules and Guda.Modules.DB and Guda.Modules.DB.HasExternalAutoLoot
       and Guda.Modules.DB:HasExternalAutoLoot() then
        Guda.Modules.DB:SetSetting("autoLoot", false)
        self:SetChecked(0)
        return
    end
    -- 软禁用：当 SuperWoW 缺失时回滚点击并退出。
    if self._gudaSoftDisabled then
        local enabled = Guda.Modules.DB:GetSetting("autoLoot") and true or false
        self:SetChecked(enabled and 1 or 0)
        return
    end
    local isChecked = self:GetChecked() == 1
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoLoot", isChecked)
    end
    -- 立即应用到客户端（SuperWoW 的 SetAutoloot 或 vanilla
    -- SetAutoLootDefault），使切换在下次拾取时生效。
    if Guda.Modules.AutoLoot and Guda.Modules.AutoLoot.Apply then
        Guda.Modules.AutoLoot:Apply()
    end
end

-- 自动打开蚌壳复选框 OnLoad
function GudaBag.SettingsPopup_AutoOpenClamsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Open Clams"])
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, 13, flags) end
    end

    self.tooltipText = GudaBag.L["Automatically open clams in your bags when you loot one."]

    local enabled = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoOpenClams") and true or false
    end
    self:SetChecked(enabled and 1 or 0)
end

-- 自动打开蚌壳复选框 OnClick
function GudaBag.SettingsPopup_AutoOpenClamsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoOpenClams", isChecked)
    end
    -- 如果启用，立即为背包中已有的蚌壳执行一次打开。
    if isChecked and Guda.Modules.ClamOpener then
        Guda.Modules.ClamOpener:Open(true)
    end
end

-- 自动补位复选框 OnLoad
function GudaBag.SettingsPopup_AutoFillRowsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Fill Rows"])
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, 13, flags) end
    end

    self.tooltipText = GudaBag.L["Reorder categories so each row is filled. When a row has empty space, a category whose size best fills the gap is moved in."]

    local enabled = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoFillRows") and true or false
    end
    self:SetChecked(enabled and 1 or 0)
end

-- 自动补位复选框 OnClick
function GudaBag.SettingsPopup_AutoFillRowsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoFillRows", isChecked)
    end
    -- 立即重排已打开的背包，使排序即时生效，无需 /reload。
    if Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
        Guda.Modules.BagFrame:Update()
    end
end

-- 拾取标记复选框 OnLoad
-- 拾取标记模式：0=关闭，1=星星图标，2=呼吸边框
-- 读取设置（兼容旧的 showLootMarker / lootMarkerPulse 布尔值）
function GudaBag.GetLootMarkerMode()
    local DB = Guda.Modules.DB
    local mode = DB:GetSetting("lootMarkerMode")
    if mode ~= nil then return mode end
    -- 旧版迁移：showLootMarker=false → 0；true 且 pulse → 2；true → 1
    local show = DB:GetSetting("showLootMarker") and true or false
    if not show then return 0 end
    local pulse = DB:GetSetting("lootMarkerPulse") and true or false
    return pulse and 2 or 1
end

-- 拾取标记模式显示名称
function GudaBag.LootMarkerModeNames()
    return {
        [0] = (GudaBag.L and GudaBag.L["Off"]) or "Off",
        [1] = (GudaBag.L and GudaBag.L["Star Icon"]) or "Star Icon",
        [2] = (GudaBag.L and GudaBag.L["Pulsing Border"]) or "Pulsing Border",
    }
end

-- 拾取标记样式下拉框初始化
local function LootMarkerDropdown_Initialize()
    local names = GudaBag.LootMarkerModeNames()
    local current = GudaBag.GetLootMarkerMode()
    for mode = 0, 2 do
        local info = {}
        info.text = names[mode]
        info.value = mode
        info.func = function()
            local val = this.value
            local DB = Guda.Modules.DB
            DB:SetSetting("lootMarkerMode", val)
            UIDropDownMenu_SetSelectedValue(getglobal("Guda_SettingsPopup_LootMarkerDropdown"), val)
            UIDropDownMenu_SetText(names[val], getglobal("Guda_SettingsPopup_LootMarkerDropdown"))
            -- 立即刷新已打开的背包/银行，使标记即时出现/消失/切换样式
            if Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
                Guda.Modules.BagFrame:Update()
            end
            if Guda.Modules.BankFrame and Guda.Modules.BankFrame.Update then
                Guda.Modules.BankFrame:Update()
            end
        end
        info.checked = (current == mode)
        UIDropDownMenu_AddButton(info)
    end
end

-- 拾取标记样式下拉框 OnLoad
function GudaBag.SettingsPopup_LootMarkerDropdown_OnLoad(self)
    UIDropDownMenu_Initialize(self, LootMarkerDropdown_Initialize)
    UIDropDownMenu_SetWidth(130, self)
    local names = GudaBag.LootMarkerModeNames()
    local mode = GudaBag.GetLootMarkerMode()
    UIDropDownMenu_SetSelectedValue(self, mode)
    UIDropDownMenu_SetText(names[mode] or names[0], self)

    -- 在下拉框上方添加标签
    local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 20, 2)
    label:SetText((GudaBag.L and GudaBag.L["Pickup Marker"]) or "Pickup Marker")
    label:SetTextColor(1, 0.82, 0, 1)
end

-- 自动出售垃圾复选框 OnLoad
function GudaBag.SettingsPopup_AutoVendorJunkCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Sell Junk"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Automatically sell gray (junk) items when you visit a vendor."]

    local enabled = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoVendorJunk")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 自动出售垃圾复选框 OnClick
function GudaBag.SettingsPopup_AutoVendorJunkCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoVendorJunk", isChecked)
    end
end

-- 自动打开背包复选框 OnLoad
function GudaBag.SettingsPopup_AutoOpenBagsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Open Bags"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Automatically open bags when interacting with bank, auction house, mail, or trade."]

    local enabled = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoOpenBags")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 自动打开背包复选框 OnClick
function GudaBag.SettingsPopup_AutoOpenBagsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoOpenBags", isChecked)
    end
end

-- 自动关闭背包复选框 OnLoad
function GudaBag.SettingsPopup_AutoCloseBagsCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Auto Close Bags"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Automatically close bags when closing bank, auction house, mail, trade, or vendor."]

    local enabled = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("autoCloseBags")
        if enabled == nil then enabled = true end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 自动关闭背包复选框 OnClick
function GudaBag.SettingsPopup_AutoCloseBagsCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("autoCloseBags", isChecked)
    end
end

-- 白色物品作为垃圾复选框 OnLoad
function GudaBag.SettingsPopup_WhiteItemsJunkCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["White Items as Junk"])

        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    self.tooltipText = GudaBag.L["Treat white (common) equippable items as junk. They will be dimmed and auto-sold if auto-sell is enabled."]

    local enabled = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        enabled = Guda.Modules.DB:GetSetting("whiteItemsJunk")
        if enabled == nil then enabled = false end
    end

    self:SetChecked(enabled and 1 or 0)
end

-- 白色物品作为垃圾复选框 OnClick
function GudaBag.SettingsPopup_WhiteItemsJunkCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("whiteItemsJunk", isChecked)
    end

    -- 清除物品检测缓存，使垃圾状态被重新评估
    if Guda.Modules.ItemDetection and Guda.Modules.ItemDetection.ClearCache then
        Guda.Modules.ItemDetection:ClearCache()
    end

    -- 更新背包和银行界面
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-- 主题下拉框（暴雪 UIDropDownMenu）
local themeOptions = {
    { text = "Guda", value = "guda" },
    { text = "Blizzard", value = "blizzard" },
    { text = "pfUI", value = "pfui" },
    { text = "Dragonflight", value = "dragonflight" },
}

-- pfUI 透明度复选框
function GudaBag.SettingsPopup_UsePfUITransparencyCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["pfUI Transparency"])
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end
    self.tooltipText = GudaBag.L["When enabled, uses pfUI's background transparency instead of the slider below."]

    local val = true
    if Guda and Guda.Modules and Guda.Modules.DB then
        local stored = Guda.Modules.DB:GetSetting("usePfUITransparency")
        if stored ~= nil then val = stored end
    end
    self:SetChecked(val and 1 or 0)

    -- 仅当 pfUI 主题激活时显示
    local theme = "guda"
    if Guda and Guda.Modules and Guda.Modules.DB then
        theme = Guda.Modules.DB:GetSetting("theme") or "guda"
    end
    if theme == "pfui" then self:Show() else self:Hide() end
end

function GudaBag.SettingsPopup_UsePfUITransparencyCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("usePfUITransparency", isChecked)
    end
    if Guda.Modules and Guda.Modules.Theme then
        Guda.Modules.Theme:ClearCache()
        Guda.Modules.Theme:ApplyToAllFrames()
    end
end

local function ThemeDropdown_Initialize()
    local currentTheme = Guda.Modules.DB:GetSetting("theme") or "guda"
    for _, option in ipairs(themeOptions) do
        local info = {}
        info.text = option.text
        info.value = option.value
        info.func = function()
            local val = this.value
            UIDropDownMenu_SetSelectedValue(getglobal("Guda_SettingsPopup_ThemeDropdown"), val)
            GudaBag.SettingsPopup_ApplyTheme(val)
        end
        info.checked = (currentTheme == option.value)
        UIDropDownMenu_AddButton(info)
    end
end

function GudaBag.SettingsPopup_ThemeDropdown_OnLoad(self)
    UIDropDownMenu_Initialize(self, ThemeDropdown_Initialize)
    UIDropDownMenu_SetWidth(130, self)
    local currentTheme = Guda.Modules.DB:GetSetting("theme") or "guda"
    local names = { guda = "Guda", blizzard = "Blizzard", pfui = "pfUI", dragonflight = "Dragonflight" }
    UIDropDownMenu_SetSelectedValue(self, currentTheme)
    UIDropDownMenu_SetText(names[currentTheme] or currentTheme, self)

    -- 在下拉框上方添加标签
    local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 20, 2)
    label:SetText(GudaBag.L["Theme"])
    label:SetTextColor(1, 0.82, 0, 1)
end

-- 应用选中的主题
function GudaBag.SettingsPopup_ApplyTheme(themeId)
    local DB = Guda.Modules.DB
    local oldTheme = DB:GetSetting("theme") or "guda"

    -- 离开 pfUI 主题时保存当前的 hideBorders/bgTransparency
    if oldTheme == "pfui" and themeId ~= "pfui" then
        -- 恢复之前保存的值（应用 pfUI 之前的值）
        local prevHide = DB:GetSetting("_prePfui_hideBorders")
        local prevTransp = DB:GetSetting("_prePfui_bgTransparency")
        if prevHide ~= nil then
            DB:SetSetting("hideBorders", prevHide)
        else
            DB:SetSetting("hideBorders", false)
        end
        if prevTransp ~= nil then
            DB:SetSetting("bgTransparency", prevTransp)
        else
            DB:SetSetting("bgTransparency", 0.15)
        end
    end

    -- 切换到 pfUI 前保存当前值，然后应用 pfUI 默认值
    if themeId == "pfui" and oldTheme ~= "pfui" then
        DB:SetSetting("_prePfui_hideBorders", DB:GetSetting("hideBorders"))
        DB:SetSetting("_prePfui_bgTransparency", DB:GetSetting("bgTransparency"))
        DB:SetSetting("hideBorders", true)
        DB:SetSetting("bgTransparency", Guda.Constants.PFUI_DEFAULT_BG_TRANSPARENCY)
        -- 默认使用 pfUI 透明度
        if DB:GetSetting("usePfUITransparency") == nil then
            DB:SetSetting("usePfUITransparency", true)
        end
    end

    DB:SetSetting("theme", themeId)

    -- 清除主题缓存
    if Guda.Modules.Theme then
        Guda.Modules.Theme:ClearCache()
    end

    -- 更新下拉框文本
    local dropdown = getglobal("Guda_SettingsPopup_ThemeDropdown")
    if dropdown then
        local names = { guda = "Guda", blizzard = "Blizzard", pfui = "pfUI", dragonflight = "Dragonflight" }
        UIDropDownMenu_SetSelectedValue(dropdown, themeId)
        UIDropDownMenu_SetText(names[themeId] or themeId, dropdown)
    end

    -- 将主题应用到所有界面（同时更新格子背景 alpha）
    if Guda.Modules.Theme then
        Guda.Modules.Theme:ApplyToAllFrames()
    end

    -- 任务栏/追踪栏按钮的图标边框样式跟随主题，切换后即时刷新
    if Guda.Modules.QuestItemBar and Guda.Modules.QuestItemBar.RefreshIconStyles then
        Guda.Modules.QuestItemBar:RefreshIconStyles()
    end
    if Guda.Modules.TrackedItemBar and Guda.Modules.TrackedItemBar.RefreshIconStyles then
        Guda.Modules.TrackedItemBar:RefreshIconStyles()
    end

    -- 刷新设置界面控件以反映更改后的 hideBorders/bgTransparency
    local hideBordersCheckbox = getglobal("Guda_SettingsPopup_HideBordersCheckbox")
    if hideBordersCheckbox then
        local hb = DB:GetSetting("hideBorders")
        hideBordersCheckbox:SetChecked(hb and 1 or 0)
    end
    local bgTransparencySlider = getglobal("Guda_SettingsPopup_BgTransparencySlider")
    if bgTransparencySlider then
        bgTransparencySlider:SetValue(DB:GetSetting("bgTransparency") or 0.15)
    end

    -- 根据主题显示/隐藏 pfUI 透明度复选框
    local pfuiTranspCB = getglobal("Guda_SettingsPopup_UsePfUITransparencyCheckbox")
    if pfuiTranspCB then
        if themeId == "pfui" then
            local val = DB:GetSetting("usePfUITransparency")
            if val == nil then val = true end
            pfuiTranspCB:SetChecked(val and 1 or 0)
            pfuiTranspCB:Show()
        else
            pfuiTranspCB:Hide()
        end
    end
end

-- 背包视图下拉框
local bagViewOptions = {
    { text = (GudaBag.L and GudaBag.L["Category"]) or "Category", value = "category" },
    { text = (GudaBag.L and GudaBag.L["Single"]) or "Single", value = "single" },
}

local function BagViewDropdown_Initialize()
    local current = Guda.Modules.DB:GetSetting("bagViewType") or "single"
    for _, option in ipairs(bagViewOptions) do
        local info = {}
        info.text = option.text
        info.value = option.value
        info.func = function()
            local val = this.value
            UIDropDownMenu_SetSelectedValue(getglobal("Guda_SettingsPopup_BagViewDropdown"), val)
            local viewLabel = (val == "single" and (GudaBag.L["Single"] or "Single")) or (GudaBag.L["Category"] or "Category")
            UIDropDownMenu_SetText(viewLabel, getglobal("Guda_SettingsPopup_BagViewDropdown"))
            Guda.Modules.DB:SetSetting("bagViewType", val)
            if GudaBag.ReleaseAllButtons then GudaBag.ReleaseAllButtons() end
            if Guda_BagFrame:IsShown() then Guda.Modules.BagFrame:Update() end
            if Guda_BankFrame and Guda_BankFrame:IsShown() then Guda.Modules.BankFrame:Update() end
        end
        info.checked = (current == option.value)
        UIDropDownMenu_AddButton(info)
    end
end

function GudaBag.SettingsPopup_BagViewDropdown_OnLoad(self)
    UIDropDownMenu_Initialize(self, BagViewDropdown_Initialize)
    UIDropDownMenu_SetWidth(130, self)
    local current = Guda.Modules.DB:GetSetting("bagViewType") or "single"
    UIDropDownMenu_SetSelectedValue(self, current)
    local viewLabel = (current == "single" and (GudaBag.L["Single"] or "Single")) or (GudaBag.L["Category"] or "Category")
    UIDropDownMenu_SetText(viewLabel, self)

    local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 20, 2)
    label:SetText(GudaBag.L["Bag View"])
    label:SetTextColor(1, 0.82, 0, 1)
end

-- 银行视图下拉框
local bankViewOptions = {
    { text = (GudaBag.L and GudaBag.L["Category"]) or "Category", value = "category" },
    { text = (GudaBag.L and GudaBag.L["Single"]) or "Single", value = "single" },
}

local function BankViewDropdown_Initialize()
    local current = Guda.Modules.DB:GetSetting("bankViewType") or "single"
    for _, option in ipairs(bankViewOptions) do
        local info = {}
        info.text = option.text
        info.value = option.value
        info.func = function()
            local val = this.value
            UIDropDownMenu_SetSelectedValue(getglobal("Guda_SettingsPopup_BankViewDropdown"), val)
            local viewLabel = (val == "single" and (GudaBag.L["Single"] or "Single")) or (GudaBag.L["Category"] or "Category")
            UIDropDownMenu_SetText(viewLabel, getglobal("Guda_SettingsPopup_BankViewDropdown"))
            Guda.Modules.DB:SetSetting("bankViewType", val)
            if GudaBag.ReleaseAllButtons then GudaBag.ReleaseAllButtons() end
            if Guda_BankFrame and Guda_BankFrame:IsShown() then Guda.Modules.BankFrame:Update() end
            if Guda_BagFrame:IsShown() then Guda.Modules.BagFrame:Update() end
        end
        info.checked = (current == option.value)
        UIDropDownMenu_AddButton(info)
    end
end

function GudaBag.SettingsPopup_BankViewDropdown_OnLoad(self)
    UIDropDownMenu_Initialize(self, BankViewDropdown_Initialize)
    UIDropDownMenu_SetWidth(130, self)
    local current = Guda.Modules.DB:GetSetting("bankViewType") or "single"
    UIDropDownMenu_SetSelectedValue(self, current)
    local viewLabel = (current == "single" and (GudaBag.L["Single"] or "Single")) or (GudaBag.L["Category"] or "Category")
    UIDropDownMenu_SetText(viewLabel, self)

    local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 20, 2)
    label:SetText(GudaBag.L["Bank View"])
    label:SetTextColor(1, 0.82, 0, 1)
end

-- 反向堆叠排序复选框 OnLoad
function GudaBag.SettingsPopup_ReverseStackSortCheckbox_OnLoad(self)
    local text = getglobal(self:GetName().."Text")
    if text then
        text:SetText(GudaBag.L["Reverse Stack Sort"])

        -- 增大字体大小
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, 13, flags)
        end
    end

    -- 提示文本
    self.tooltipText = GudaBag.L["When enabled, smaller stacks of the same item will be sorted before larger stacks (e.g., stack of 16 before stack of 20)."]

    local reverseStackSort = false
    if Guda and Guda.Modules and Guda.Modules.DB then
        reverseStackSort = Guda.Modules.DB:GetSetting("reverseStackSort")
        if reverseStackSort == nil then
            reverseStackSort = false
        end
    end

    self:SetChecked(reverseStackSort and 1 or 0)
end

-- 反向堆叠排序复选框 OnClick
function GudaBag.SettingsPopup_ReverseStackSortCheckbox_OnClick(self)
    local isChecked = self:GetChecked() == 1

    -- 保存设置
    if Guda and Guda.Modules and Guda.Modules.DB then
        Guda.Modules.DB:SetSetting("reverseStackSort", isChecked)
    end

    -- 注意：排序将在下次排序操作时使用新设置
    -- 无需立即更新界面
end

-------------------------------------------
-- 分类页签函数
-------------------------------------------

-- 分类列表中可见行数
local CATEGORY_ROW_HEIGHT = 22
local CATEGORY_VISIBLE_ROWS = 14
local categoryRowFrames = {}

-- 创建或获取分类行框架
local function GetCategoryRowFrame(index)
    if categoryRowFrames[index] then
        return categoryRowFrames[index]
    end

    local container = getglobal("Guda_SettingsPopup_CategoryListContainer")
    if not container then return nil end

    local rowName = "Guda_SettingsPopup_CategoryRow" .. index
    local row = CreateFrame("Frame", rowName, container)
    row:SetHeight(CATEGORY_ROW_HEIGHT)
    row:SetWidth(420)
    row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((index - 1) * CATEGORY_ROW_HEIGHT))

    -- 背景高亮
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetTexture(1, 1, 1, 0)
    row.bg = bg

    -- 启用复选框
    local checkbox = CreateFrame("CheckButton", rowName .. "_Checkbox", row, "UICheckButtonTemplate")
    checkbox:SetWidth(20)
    checkbox:SetHeight(20)
    checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)
    checkbox:SetScript("OnClick", function()
        local catId = this:GetParent().categoryId
        if catId and Guda.Modules.CategoryManager then
            Guda.Modules.CategoryManager:ToggleCategory(catId)
            GudaBag.SettingsPopup_CategoriesTab_Update()
            GudaBag.SettingsPopup_RefreshBagFrames()
        end
    end)
    row.checkbox = checkbox

    -- 分类名称
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
    nameText:SetWidth(160)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- 编辑按钮
    local editBtn = CreateFrame("Button", rowName .. "_EditBtn", row, "UIPanelButtonTemplate")
    editBtn:SetWidth(40)
    editBtn:SetHeight(18)
    editBtn:SetPoint("LEFT", nameText, "RIGHT", 5, 0)
    editBtn:SetText(GudaBag.L["Edit"])
    editBtn:SetScript("OnClick", function()
        local catId = this:GetParent().categoryId
        if catId then
            GudaBag.CategoryEditor_Open(catId)
        end
    end)
    row.editBtn = editBtn

    -- 上移按钮
    local upBtn = CreateFrame("Button", rowName .. "_UpBtn", row)
    upBtn:SetWidth(20)
    upBtn:SetHeight(20)
    upBtn:SetPoint("LEFT", editBtn, "RIGHT", 5, 0)
    upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    upBtn:SetScript("OnClick", function()
        local catId = this:GetParent().categoryId
        if catId and Guda.Modules.CategoryManager then
            Guda.Modules.CategoryManager:MoveCategoryUp(catId)
            GudaBag.SettingsPopup_CategoriesTab_Update()
            GudaBag.SettingsPopup_RefreshBagFrames()
        end
    end)
    row.upBtn = upBtn

    -- 下移按钮
    local downBtn = CreateFrame("Button", rowName .. "_DownBtn", row)
    downBtn:SetWidth(20)
    downBtn:SetHeight(20)
    downBtn:SetPoint("LEFT", upBtn, "RIGHT", 2, 0)
    downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
    downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
    downBtn:SetScript("OnClick", function()
        local catId = this:GetParent().categoryId
        if catId and Guda.Modules.CategoryManager then
            Guda.Modules.CategoryManager:MoveCategoryDown(catId)
            GudaBag.SettingsPopup_CategoriesTab_Update()
            GudaBag.SettingsPopup_RefreshBagFrames()
        end
    end)
    row.downBtn = downBtn

    -- 删除按钮（仅用于自定义分类）
    local deleteBtn = CreateFrame("Button", rowName .. "_DeleteBtn", row, "UIPanelCloseButton")
    deleteBtn:SetWidth(20)
    deleteBtn:SetHeight(20)
    deleteBtn:SetPoint("LEFT", downBtn, "RIGHT", 5, 0)
    deleteBtn:SetScript("OnClick", function()
        local catId = this:GetParent().categoryId
        if catId and Guda.Modules.CategoryManager then
            local def = Guda.Modules.CategoryManager:GetCategory(catId)
            if def and not def.isBuiltIn then
                Guda.Modules.CategoryManager:DeleteCategory(catId)
                GudaBag.SettingsPopup_CategoriesTab_Update()
                GudaBag.SettingsPopup_RefreshBagFrames()
            end
        end
    end)
    row.deleteBtn = deleteBtn

    -- 内置指示器
    local builtInText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    builtInText:SetPoint("LEFT", deleteBtn, "RIGHT", 5, 0)
    builtInText:SetText(GudaBag.L["(Built-in)"])
    builtInText:SetTextColor(0.5, 0.5, 0.5)
    row.builtInText = builtInText

    -- 合并复选框（显示在分组标题行上）
    local mergeCheckbox = CreateFrame("CheckButton", rowName .. "_MergeCheckbox", row, "UICheckButtonTemplate")
    mergeCheckbox:SetWidth(20)
    mergeCheckbox:SetHeight(20)
    mergeCheckbox:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    mergeCheckbox:SetScript("OnClick", function()
        local groupName = this:GetParent().groupName
        if groupName then
            local mergedGroups = Guda.Modules.DB:GetSetting("mergedGroups") or {}
            if this:GetChecked() == 1 then
                mergedGroups[groupName] = true
            else
                mergedGroups[groupName] = nil
            end
            Guda.Modules.DB:SetSetting("mergedGroups", mergedGroups)
            GudaBag.SettingsPopup_RefreshBagFrames()
        end
    end)
    local mergeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mergeLabel:SetPoint("RIGHT", mergeCheckbox, "LEFT", -2, 0)
    mergeLabel:SetText(GudaBag.L["Merge"])
    mergeLabel:SetTextColor(0.8, 0.8, 0.8)
    row.mergeCheckbox = mergeCheckbox
    row.mergeLabel = mergeLabel

    -- 悬停高亮
    row:EnableMouse(true)
    row:SetScript("OnEnter", function()
        this.bg:SetTexture(1, 1, 1, 0.1)
    end)
    row:SetScript("OnLeave", function()
        this.bg:SetTexture(1, 1, 1, 0)
    end)

    categoryRowFrames[index] = row
    return row
end

-- 构建带分组标题插入的扁平显示列表
local function BuildCategoryDisplayList()
    if not Guda.Modules.CategoryManager then return {}, 0 end

    local categoryOrder = Guda.Modules.CategoryManager:GetCategoryOrder()
    local displayList = {}  -- 条目：{ type = "header"|"category", groupName, categoryId, categoryDef }
    local lastGroup = nil

    for _, catId in ipairs(categoryOrder) do
        local catDef = Guda.Modules.CategoryManager:GetCategory(catId)
        if catDef then
            local group = catDef.group or "Main"
            -- 分组变化时插入分组标题
            if group ~= lastGroup then
                table.insert(displayList, { type = "header", groupName = group })
                lastGroup = group
            end
            table.insert(displayList, { type = "category", categoryId = catId, categoryDef = catDef })
        end
    end

    return displayList, table.getn(displayList)
end

-- 更新分类列表显示
function GudaBag.SettingsPopup_CategoriesTab_Update()
    if not Guda.Modules.CategoryManager then return end

    local scrollFrame = getglobal("Guda_SettingsPopup_CategoriesScrollFrame")
    if not scrollFrame then return end

    local displayList, totalEntries = BuildCategoryDisplayList()

    -- 更新滚动框架
    FauxScrollFrame_Update(scrollFrame, totalEntries, CATEGORY_VISIBLE_ROWS, CATEGORY_ROW_HEIGHT)

    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i = 1, CATEGORY_VISIBLE_ROWS do
        local row = GetCategoryRowFrame(i)
        if row then
            local dataIndex = i + offset
            if dataIndex <= totalEntries then
                local entry = displayList[dataIndex]

                if entry.type == "header" then
                    -- 显示为分组标题行
                    row.categoryId = nil
                    row.groupName = entry.groupName
                    local groupLabel = (GudaBag.L and GudaBag.L[entry.groupName]) or entry.groupName
                    row.nameText:SetText("|cffffd100-- " .. groupLabel .. " --|r")
                    row.nameText:SetTextColor(1, 0.82, 0)
                    row.checkbox:Hide()
                    row.editBtn:Hide()
                    row.upBtn:Hide()
                    row.downBtn:Hide()
                    row.deleteBtn:Hide()
                    row.builtInText:Hide()

                    -- 为分组标题显示合并复选框
                    local mergedGroups = Guda.Modules.DB:GetSetting("mergedGroups") or {}
                    row.mergeCheckbox:SetChecked(mergedGroups[entry.groupName] and 1 or 0)
                    row.mergeCheckbox:Show()
                    row.mergeLabel:Show()

                    row:Show()
                elseif entry.type == "category" then
                    local categoryId = entry.categoryId
                    local categoryDef = entry.categoryDef

                    row.categoryId = categoryId
                    row.groupName = nil
                    local rowName = categoryDef.name or categoryId
                    if GudaBag.L and GudaBag.L[rowName] then rowName = GudaBag.L[rowName] end
                    row.nameText:SetText(rowName)
                    row.checkbox:Show()
                    row.checkbox:SetChecked(categoryDef.enabled and 1 or 0)
                    row.mergeCheckbox:Hide()
                    row.mergeLabel:Hide()

                    -- 根据是否内置显示/隐藏删除按钮
                    if categoryDef.isBuiltIn then
                        row.deleteBtn:Hide()
                        row.builtInText:Show()
                    else
                        row.deleteBtn:Show()
                        row.builtInText:Hide()
                    end

                    -- 对 hideControls 分类隐藏所有控件（仅复选框可见）
                    if categoryDef.hideControls then
                        row.editBtn:Hide()
                        row.upBtn:Hide()
                        row.downBtn:Hide()
                        row.deleteBtn:Hide()
                        row.builtInText:Hide()
                    else
                        row.editBtn:Show()
                        row.upBtn:Show()
                        row.downBtn:Show()

                        -- 根据分组感知的边界启用/禁用移动按钮
                        if Guda.Modules.CategoryManager:CanMoveUp(categoryId) then
                            row.upBtn:Enable()
                        else
                            row.upBtn:Disable()
                        end

                        if Guda.Modules.CategoryManager:CanMoveDown(categoryId) then
                            row.downBtn:Enable()
                        else
                            row.downBtn:Disable()
                        end
                    end

                    -- 根据启用状态设置文本颜色
                    if categoryDef.enabled then
                        row.nameText:SetTextColor(1, 1, 1)
                    else
                        row.nameText:SetTextColor(0.5, 0.5, 0.5)
                    end

                    row:Show()
                else
                    row:Hide()
                end
            else
                row:Hide()
            end
        end
    end

    -- 设置按钮文本
    local addBtn = getglobal("Guda_SettingsPopup_AddCategoryButton")
    if addBtn then
        addBtn:SetText(GudaBag.L["+ Add Category"])
    end

    local resetBtn = getglobal("Guda_SettingsPopup_ResetCategoriesButton")
    if resetBtn then
        resetBtn:SetText(GudaBag.L["Reset Defaults"])
    end
end

-- 添加新的自定义分类
function GudaBag.SettingsPopup_AddCategory_OnClick()
    if not Guda.Modules.CategoryManager then return end

    -- 创建新的分类定义
    local newDef = {
        name = (GudaBag.L and GudaBag.L["Custom Category"]) or "Custom Category",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        rules = {},
        matchMode = "any",
        priority = 80,
        enabled = true,
        isBuiltIn = false,
        group = Guda.Modules.CategoryManager:GetGroupMain(),
    }

    -- 以自动生成的 ID 添加到数据库
    local success, newId = Guda.Modules.CategoryManager:AddCategory(nil, newDef)
    if success and newId then
        -- 更新显示
        GudaBag.SettingsPopup_CategoriesTab_Update()
        -- 打开新分类的编辑器
        GudaBag.CategoryEditor_Open(newId)
    end
end

-- 将分类重置为默认值
function GudaBag.SettingsPopup_ResetCategories_OnClick()
    if Guda.Modules.CategoryManager then
        Guda.Modules.CategoryManager:ResetToDefaults()
        GudaBag.SettingsPopup_CategoriesTab_Update()
        GudaBag.SettingsPopup_RefreshBagFrames()
    Guda:Print((GudaBag.L and GudaBag.L["Categories reset to defaults."]) or "Categories reset to defaults.")
    end
end

-- 分类更改后刷新背包和银行界面
function GudaBag.SettingsPopup_RefreshBagFrames()
    -- 刷新分类列表
    GudaBag.RefreshCategoryList()

    -- 如果背包界面可见则更新
    local bagFrame = getglobal("Guda_BagFrame")
    if bagFrame and bagFrame:IsShown() then
        Guda.Modules.BagFrame:Update()
    end

    -- 如果银行界面可见则更新
    local bankFrame = getglobal("Guda_BankFrame")
    if bankFrame and bankFrame:IsShown() then
        Guda.Modules.BankFrame:Update()
    end
end

-------------------------------------------
-- 分类编辑器函数
-------------------------------------------

local editorCategoryId = nil
local editorMatchMode = "any"
local editorGroup = "Main"
local editorMark = nil  -- 当前分类标记贴图路径或 nil
local editorRules = {}
local editorRuleFrames = {}

-- 可用的标记图标（贴图路径）
local MARK_ICONS = {
    "Interface\\AddOns\\Guda\\Assets\\equipment",
    "Interface\\AddOns\\Guda\\Assets\\plus",
    "Interface\\AddOns\\Guda\\Assets\\fav",
    "Interface\\AddOns\\Guda\\Assets\\combat",
    "Interface\\AddOns\\Guda\\Assets\\Cog",
    "Interface\\AddOns\\Guda\\Assets\\guild",
}
local RULE_ROW_HEIGHT = 28
local MAX_RULES = 22

-- 下拉框的规则类型选项
local RULE_TYPE_OPTIONS = {
    { id = "itemType", name = "Item Type" },
    { id = "itemSubtype", name = "Item Subtype" },
    { id = "namePattern", name = "Name Contains" },
    { id = "itemID", name = "Item ID" },
    { id = "quality", name = "Quality (exact)" },
    { id = "qualityMin", name = "Quality (min)" },
    { id = "isBoE", name = "Bind on Equip" },
    { id = "isBoP", name = "Bind on Pickup" },
    { id = "isQuestItem", name = "Quest Item" },
    { id = "isJunk", name = "Is Junk" },
    { id = "restoreTag", name = "Restore Type" },
    { id = "isSoulShard", name = "Soul Shard" },
    { id = "isProjectile", name = "Projectile" },
    { id = "isRecentlyLooted", name = "Recently Looted" },
}

-- 特定规则类型的值选项
local RULE_VALUE_OPTIONS = {
    itemType = { "Armor", "Weapon", "Consumable", "Container", "Trade Goods", "Projectile", "Quiver", "Reagent", "Recipe", "Key", "Miscellaneous", "Quest" },
    quality = { "0 - Poor", "1 - Common", "2 - Uncommon", "3 - Rare", "4 - Epic", "5 - Legendary" },
    qualityMin = { "0 - Poor", "1 - Common", "2 - Uncommon", "3 - Rare", "4 - Epic", "5 - Legendary" },
    isBoE = { "true", "false" },
    isBoP = { "true", "false" },
    isQuestItem = { "true", "false" },
    isJunk = { "true", "false" },
    isSoulShard = { "true", "false" },
    isProjectile = { "true", "false" },
    isRecentlyLooted = { "600", "300", "1200" },
    restoreTag = { "eat", "drink", "restore" },
}

-- 分类编辑器的 OnLoad
function GudaBag.CategoryEditor_OnLoad(self)
    Guda:ApplyBackdrop(self, "DEFAULT_FRAME")

    -- 本地化匹配模式标签（在 XML 中硬编码为 "Match Mode:"）
    local matchModeLabel = getglobal("Guda_CategoryEditor_MatchModeLabel")
    if matchModeLabel then matchModeLabel:SetText(GudaBag.L["Match Mode:"]) end

    -- 设置按钮文本
    local addBtn = getglobal("Guda_CategoryEditor_AddRuleButton")
    if addBtn then addBtn:SetText(GudaBag.L["+ Add Rule"]) end

    local saveBtn = getglobal("Guda_CategoryEditor_SaveButton")
    if saveBtn then saveBtn:SetText(GudaBag.L["Save"]) end

    local cancelBtn = getglobal("Guda_CategoryEditor_CancelButton")
    if cancelBtn then cancelBtn:SetText(GudaBag.L["Cancel"]) end

    -- 创建分组 EditBox（如果不存在）
    if not getglobal("Guda_CategoryEditor_GroupEditBox") then
        local nameBox = getglobal("Guda_CategoryEditor_NameEditBox")
        if nameBox then
            -- 标签
            local groupLabel = self:CreateFontString("Guda_CategoryEditor_GroupLabel", "OVERLAY", "GameFontNormalSmall")
            groupLabel:SetPoint("LEFT", nameBox, "RIGHT", 14, 0)
            groupLabel:SetText(GudaBag.L["Group:"])
            groupLabel:SetTextColor(0.7, 0.7, 0.7)

            -- EditBox
            local groupBox = CreateFrame("EditBox", "Guda_CategoryEditor_GroupEditBox", self, "InputBoxTemplate")
            groupBox:SetWidth(100)
            groupBox:SetHeight(22)
            groupBox:SetPoint("LEFT", groupLabel, "RIGHT", 6, 0)
            groupBox:SetAutoFocus(false)
            groupBox:SetMaxLetters(20)
            groupBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
            groupBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        end
    end

    -- 创建标记图标选择器行
    if not getglobal("Guda_CategoryEditor_MarkLabel") then
        local MARK_BTN_SIZE = 22
        local MARK_BTN_SPACING = 6

        local markLabel = self:CreateFontString("Guda_CategoryEditor_MarkLabel", "OVERLAY", "GameFontNormalSmall")
        markLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 20, -78)
        markLabel:SetText(GudaBag.L["Mark:"])
        markLabel:SetTextColor(0.7, 0.7, 0.7)

        -- "无"按钮（第一个）
        local noneBtn = CreateFrame("Button", "Guda_CategoryEditor_MarkNone", self)
        noneBtn:SetWidth(MARK_BTN_SIZE)
        noneBtn:SetHeight(MARK_BTN_SIZE)
        noneBtn:SetPoint("LEFT", markLabel, "RIGHT", 8, 0)
        noneBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        noneBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        noneBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        noneBtn.markPath = nil

        local noneTex = noneBtn:CreateTexture(nil, "ARTWORK")
        noneTex:SetWidth(12)
        noneTex:SetHeight(12)
        noneTex:SetPoint("CENTER", noneBtn, "CENTER", 0, 0)
        noneTex:SetTexture("Interface\\Buttons\\UI-StopButton")
        noneTex:SetVertexColor(0.6, 0.6, 0.6)

        noneBtn:SetScript("OnClick", function()
            editorMark = nil
            GudaBag.CategoryEditor_UpdateMarkButtons()
        end)

        self.markButtons = { noneBtn }

        -- 图标按钮
        local prevBtn = noneBtn
        for i = 1, table.getn(MARK_ICONS) do
            local iconPath = MARK_ICONS[i]
            local btn = CreateFrame("Button", "Guda_CategoryEditor_Mark" .. i, self)
            btn:SetWidth(MARK_BTN_SIZE)
            btn:SetHeight(MARK_BTN_SIZE)
            btn:SetPoint("LEFT", prevBtn, "RIGHT", MARK_BTN_SPACING, 0)
            btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            btn.markPath = iconPath

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetWidth(16)
            tex:SetHeight(16)
            tex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            tex:SetTexture(iconPath)

            btn:SetScript("OnClick", function()
                editorMark = this.markPath
                GudaBag.CategoryEditor_UpdateMarkButtons()
            end)

            table.insert(self.markButtons, btn)
            prevBtn = btn
        end
    end

    -- 创建单选按钮标签
    local anyRadio = getglobal("Guda_CategoryEditor_MatchAny")
    if anyRadio then
        local label = anyRadio:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", anyRadio, "RIGHT", 2, 0)
        label:SetText(GudaBag.L["Any rule"])
    end

    local allRadio = getglobal("Guda_CategoryEditor_MatchAll")
    if allRadio then
        local label = allRadio:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", allRadio, "RIGHT", 2, 0)
        label:SetText(GudaBag.L["All rules"])
    end
end

-- 更新标记按钮高亮（金色 = 选中，灰色 = 未选中）
function GudaBag.CategoryEditor_UpdateMarkButtons()
    local editor = getglobal("Guda_CategoryEditor")
    if not editor or not editor.markButtons then return end
    for _, btn in ipairs(editor.markButtons) do
        if btn.markPath == editorMark then
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

-- 分类编辑器的 OnShow
function GudaBag.CategoryEditor_OnShow(self)
    GudaBag.CategoryEditor_UpdateRulesDisplay()
end

-- 为特定分类打开分类编辑器
function GudaBag.CategoryEditor_Open(categoryId)
    if not Guda.Modules.CategoryManager then return end

    local categoryDef = Guda.Modules.CategoryManager:GetCategory(categoryId)
    if not categoryDef then return end

    editorCategoryId = categoryId
    editorMatchMode = categoryDef.matchMode or "any"
    editorGroup = categoryDef.group or "Main"
    editorMark = categoryDef.categoryMark or nil

    -- 复制规则
    editorRules = {}
    if categoryDef.rules then
        for i, rule in ipairs(categoryDef.rules) do
            table.insert(editorRules, {
                type = rule.type,
                value = rule.value,
                required = rule.required and true or false,
            })
        end
    end

    -- 设置标题
    local title = getglobal("Guda_CategoryEditor_Title")
    if title then
        if categoryDef.isBuiltIn then
            title:SetText(GudaBag.L["Edit Category (Built-in)"])
        else
            title:SetText(GudaBag.L["Edit Category"])
        end
    end

    -- 设置名称
    local nameBox = getglobal("Guda_CategoryEditor_NameEditBox")
    if nameBox then
        local editName = categoryDef.name or categoryId
        if GudaBag.L and GudaBag.L[editName] then editName = GudaBag.L[editName] end
        nameBox:SetText(editName)
        -- 禁用内置分类的名称编辑
        if categoryDef.isBuiltIn then
            nameBox:EnableMouse(false)
            nameBox:EnableKeyboard(false)
            nameBox:SetTextColor(0.5, 0.5, 0.5)
        else
            nameBox:EnableMouse(true)
            nameBox:EnableKeyboard(true)
            nameBox:SetTextColor(1, 1, 1)
        end
    end

    -- 设置分组 EditBox
    local groupBox = getglobal("Guda_CategoryEditor_GroupEditBox")
    if groupBox then
        groupBox:SetText(editorGroup or "")
        -- 禁用内置分类的分组编辑
        if categoryDef.isBuiltIn then
            groupBox:EnableMouse(false)
            groupBox:EnableKeyboard(false)
            groupBox:SetTextColor(0.5, 0.5, 0.5)
        else
            groupBox:EnableMouse(true)
            groupBox:EnableKeyboard(true)
            groupBox:SetTextColor(1, 1, 1)
        end
        groupBox:ClearFocus()
    end

    -- 设置匹配模式
    GudaBag.CategoryEditor_SetMatchMode(editorMatchMode)

    -- 更新标记按钮高亮
    GudaBag.CategoryEditor_UpdateMarkButtons()

    -- 显示编辑器
    local editor = getglobal("Guda_CategoryEditor")
    if editor then
        editor:Show()
    end
end

-- （分组现在是 EditBox —— 不需要下拉框）

-- 设置匹配模式（单选按钮）
function GudaBag.CategoryEditor_SetMatchMode(mode)
    editorMatchMode = mode

    local anyRadio = getglobal("Guda_CategoryEditor_MatchAny")
    local allRadio = getglobal("Guda_CategoryEditor_MatchAll")

    if anyRadio then anyRadio:SetChecked(mode == "any" and 1 or 0) end
    if allRadio then allRadio:SetChecked(mode == "all" and 1 or 0) end

    -- 重新渲染规则行，使图钉按钮反映新的启用状态
    if GudaBag.CategoryEditor_UpdateRulesDisplay then
        GudaBag.CategoryEditor_UpdateRulesDisplay()
    end
end

-- 创建或获取规则行框架
local function GetRuleRowFrame(index)
    if editorRuleFrames[index] then
        return editorRuleFrames[index]
    end

    local container = getglobal("Guda_CategoryEditor_RulesContainer")
    if not container then return nil end

    local rowName = "Guda_CategoryEditor_RuleRow" .. index
    local row = CreateFrame("Frame", rowName, container)
    row:SetHeight(RULE_ROW_HEIGHT)
    row:SetWidth(310)
    row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((index - 1) * RULE_ROW_HEIGHT))

    -- 必需（图钉）切换按钮
    local reqBtn = CreateFrame("Button", rowName .. "_ReqBtn", row)
    reqBtn:SetWidth(18)
    reqBtn:SetHeight(18)
    reqBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    local reqTex = reqBtn:CreateTexture(nil, "ARTWORK")
    reqTex:SetAllPoints(reqBtn)
    reqTex:SetTexture("Interface\\AddOns\\Guda\\Assets\\pin")
    reqBtn.tex = reqTex
    reqBtn.ruleIndex = index
    reqBtn:SetScript("OnClick", function()
        local idx = this.ruleIndex
        if editorMatchMode == "all" then return end
        if editorRules[idx] then
            editorRules[idx].required = not editorRules[idx].required
            GudaBag.CategoryEditor_UpdateRulesDisplay()
        end
    end)
    reqBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(GudaBag.L["Required rule"], 1, 0.82, 0)
        GameTooltip:AddLine(GudaBag.L["Required rule tooltip"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reqBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.reqBtn = reqBtn

    -- 规则类型下拉按钮
    local typeBtn = CreateFrame("Button", rowName .. "_TypeBtn", row, "UIPanelButtonTemplate")
    typeBtn:SetWidth(105)
    typeBtn:SetHeight(22)
    typeBtn:SetPoint("LEFT", reqBtn, "RIGHT", 4, 0)
    typeBtn:SetText(GudaBag.L["Select Type"])
    typeBtn.ruleIndex = index
    typeBtn:SetScript("OnClick", function()
        GudaBag.CategoryEditor_ShowTypeDropdown(this, this.ruleIndex)
    end)
    row.typeBtn = typeBtn

    -- 值输入（文本用 EditBox，下拉框用按钮）
    local valueBox = CreateFrame("EditBox", rowName .. "_ValueBox", row, "InputBoxTemplate")
    valueBox:SetWidth(140)
    valueBox:SetHeight(22)
    valueBox:SetPoint("LEFT", typeBtn, "RIGHT", 5, 0)
    valueBox:SetAutoFocus(false)
    valueBox.ruleIndex = index
    valueBox:SetScript("OnTextChanged", function()
        local idx = this.ruleIndex
        if editorRules[idx] then
            editorRules[idx].value = this:GetText()
        end
    end)
    valueBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    valueBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    row.valueBox = valueBox

    -- 值下拉按钮（用于预定义值）
    local valueBtn = CreateFrame("Button", rowName .. "_ValueBtn", row, "UIPanelButtonTemplate")
    valueBtn:SetWidth(140)
    valueBtn:SetHeight(22)
    valueBtn:SetPoint("LEFT", typeBtn, "RIGHT", 5, 0)
    valueBtn:SetText(GudaBag.L["Select Value"])
    valueBtn.ruleIndex = index
    valueBtn:SetScript("OnClick", function()
        GudaBag.CategoryEditor_ShowValueDropdown(this, this.ruleIndex)
    end)
    valueBtn:Hide()
    row.valueBtn = valueBtn

    -- 物品投放区（仅对 itemID 规则类型可见）
    local dropZone = CreateFrame("Button", rowName .. "_DropZone", row)
    dropZone:SetWidth(22)
    dropZone:SetHeight(22)
    dropZone:SetPoint("LEFT", valueBox, "RIGHT", 4, 0)
    dropZone:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    dropZone:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    dropZone:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- 图标贴图（投放后显示物品图标）
    local dzIcon = dropZone:CreateTexture(nil, "ARTWORK")
    dzIcon:SetPoint("TOPLEFT", dropZone, "TOPLEFT", 2, -2)
    dzIcon:SetPoint("BOTTOMRIGHT", dropZone, "BOTTOMRIGHT", -2, 2)
    dzIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dzIcon:Hide()
    dropZone.icon = dzIcon

    -- 为空时的 "?" 提示
    local dzHint = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dzHint:SetPoint("CENTER", dropZone, "CENTER", 0, 0)
    dzHint:SetText("?")
    dzHint:SetTextColor(0.5, 0.5, 0.5)
    dropZone.hint = dzHint

    -- "(投放物品)" 标签
    local dzLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dzLabel:SetPoint("LEFT", dropZone, "RIGHT", 4, 0)
    dzLabel:SetText(GudaBag.L["(Drop Item)"])
    dzLabel:SetTextColor(0.5, 0.5, 0.5)
    dropZone.label = dzLabel

    dropZone:EnableMouse(true)
    dropZone:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    dropZone:RegisterForDrag("LeftButton")
    dropZone.ruleIndex = index

    -- 处理通过拖拽投放物品
    dropZone:SetScript("OnReceiveDrag", function()
        local idx = this.ruleIndex
        if not editorRules[idx] or editorRules[idx].type ~= "itemID" then return end
        if CursorHasItem and CursorHasItem() then
            -- 在 1.12.1 中，通过跟踪从光标获取物品信息
            local info = GudaBag.GetCursorItemInfo()
            if info and info.itemID then
                -- 用物品 ID 填充值输入框
                editorRules[idx].value = tostring(info.itemID)
                -- 更新图标
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(info.link or info.itemID)
                if texture then
                    this.icon:SetTexture(texture)
                    this.icon:Show()
                    this.hint:Hide()
                end
                -- 把物品放回去
                PickupContainerItem(info.bagID, info.slotID)
                GudaBag.ClearCursorItem()
                GudaBag.CategoryEditor_UpdateRulesDisplay()
            end
        end
    end)

    -- 处理点击（左键 = 从光标投放物品，右键 = 清除）
    dropZone:SetScript("OnClick", function()
        local idx = this.ruleIndex
        if not editorRules[idx] or editorRules[idx].type ~= "itemID" then return end
        if arg1 == "LeftButton" then
            if CursorHasItem and CursorHasItem() then
                local info = GudaBag.GetCursorItemInfo()
                if info and info.itemID then
                    editorRules[idx].value = tostring(info.itemID)
                    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(info.link or info.itemID)
                    if texture then
                        this.icon:SetTexture(texture)
                        this.icon:Show()
                        this.hint:Hide()
                    end
                    PickupContainerItem(info.bagID, info.slotID)
                    GudaBag.ClearCursorItem()
                    GudaBag.CategoryEditor_UpdateRulesDisplay()
                end
            end
        elseif arg1 == "RightButton" then
            -- 清除
            this.icon:SetTexture(nil)
            this.icon:Hide()
            this.hint:Show()
            editorRules[idx].value = ""
            GudaBag.CategoryEditor_UpdateRulesDisplay()
        end
    end)

    -- 提示文本
    dropZone:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(GudaBag.L["Item ID Slot"] or "Item ID Slot", 1, 0.82, 0)
        GameTooltip:AddLine(GudaBag.L["Drag an item here to get its ID"] or "Drag an item here to get its ID", 1, 1, 1, true)
        GameTooltip:AddLine(GudaBag.L["Right-click to clear"] or "Right-click to clear", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    dropZone:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    dropZone:Hide()
    row.dropZone = dropZone

    -- 删除按钮
    local deleteBtn = CreateFrame("Button", rowName .. "_DeleteBtn", row, "UIPanelCloseButton")
    deleteBtn:SetWidth(22)
    deleteBtn:SetHeight(22)
    deleteBtn:SetPoint("LEFT", dropZone, "RIGHT", 50, 0)
    deleteBtn.ruleIndex = index
    deleteBtn:SetScript("OnClick", function()
        GudaBag.CategoryEditor_RemoveRule(this.ruleIndex)
    end)
    row.deleteBtn = deleteBtn

    editorRuleFrames[index] = row
    return row
end

-- 滚动框架中可见规则行数
local VISIBLE_RULES = 10

-- 更新规则显示（带滚动支持）
function GudaBag.CategoryEditor_UpdateRulesDisplay()
    local numRules = table.getn(editorRules)
    local scrollFrame = getglobal("Guda_CategoryEditor_RulesScrollFrame")

    -- 更新规则计数标签
    local rulesLabel = getglobal("Guda_CategoryEditor_RulesLabel")
    if rulesLabel then
        rulesLabel:SetText(format(GudaBag.L["Rules (%d/%d):"], numRules, MAX_RULES))
    end

    -- 更新滚动框架
    if scrollFrame then
        FauxScrollFrame_Update(scrollFrame, numRules, VISIBLE_RULES, RULE_ROW_HEIGHT)
    end

    -- 获取滚动偏移
    local offset = 0
    if scrollFrame then
        offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
    end

    for i = 1, VISIBLE_RULES do
        local row = GetRuleRowFrame(i)
        local ruleIndex = i + offset

        if row then
            if ruleIndex <= numRules then
                local rule = editorRules[ruleIndex]
                row.ruleIndex = ruleIndex
                row.typeBtn.ruleIndex = ruleIndex
                row.valueBox.ruleIndex = ruleIndex
                row.valueBtn.ruleIndex = ruleIndex
                row.deleteBtn.ruleIndex = ruleIndex
                if row.reqBtn then
                    row.reqBtn.ruleIndex = ruleIndex
                    if rule.required then
                        row.reqBtn.tex:SetVertexColor(1, 0.82, 0)
                        row.reqBtn.tex:SetDesaturated(nil)
                    else
                        row.reqBtn.tex:SetVertexColor(0.45, 0.45, 0.45)
                        row.reqBtn.tex:SetDesaturated(1)
                    end
                    if editorMatchMode == "all" then
                        row.reqBtn:Disable()
                        row.reqBtn.tex:SetAlpha(0.35)
                    else
                        row.reqBtn:Enable()
                        row.reqBtn.tex:SetAlpha(1)
                    end
                end

                -- 设置类型按钮文本
                local typeName = GudaBag.L["Select Type"] or "Select Type"
                for _, opt in ipairs(RULE_TYPE_OPTIONS) do
                    if opt.id == rule.type then
                        typeName = GudaBag.L[opt.name] or opt.name
                        break
                    end
                end
                row.typeBtn:SetText(typeName)

                -- 显示合适的值输入控件
                local isItemID = (rule.type == "itemID")
                if RULE_VALUE_OPTIONS[rule.type] then
                    -- 对预定义值使用下拉框
                    row.valueBox:Hide()
                    row.valueBtn:Show()
                    local displayValue = GudaBag.L[tostring(rule.value or "Select")] or tostring(rule.value or "Select")
                    -- 格式化品质显示
                    if (rule.type == "quality" or rule.type == "qualityMin") and type(rule.value) == "number" then
                        local qualNames = { [0]="Poor", [1]="Common", [2]="Uncommon", [3]="Rare", [4]="Epic", [5]="Legendary" }
                        displayValue = rule.value .. " - " .. (GudaBag.L[qualNames[rule.value]] or qualNames[rule.value] or "")
                    end
                    row.valueBtn:SetText(displayValue)
                else
                    -- 对文本输入使用 EditBox
                    row.valueBtn:Hide()
                    row.valueBox:Show()
                    row.valueBox:SetText(tostring(rule.value or ""))
                end

                -- 对 itemID 规则显示/隐藏投放区
                if row.dropZone then
                    if isItemID then
                        row.dropZone:Show()
                        row.dropZone.label:Show()
                        -- 如果值是有效的物品 ID 则更新图标
                        local itemID = tonumber(rule.value)
                        if itemID and itemID > 0 then
                            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
                            if texture then
                                row.dropZone.icon:SetTexture(texture)
                                row.dropZone.icon:Show()
                                row.dropZone.hint:Hide()
                            else
                                row.dropZone.icon:Hide()
                                row.dropZone.hint:Show()
                            end
                        else
                            row.dropZone.icon:Hide()
                            row.dropZone.hint:Show()
                        end
                        -- 在投放区标签后重新定位删除按钮
                        row.deleteBtn:ClearAllPoints()
                        row.deleteBtn:SetPoint("LEFT", row.dropZone, "RIGHT", 50, 0)
                    else
                        row.dropZone:Hide()
                        row.dropZone.label:Hide()
                        -- 在值输入控件后重新定位删除按钮
                        row.deleteBtn:ClearAllPoints()
                        local valueAnchor = row.valueBtn
                        if row.valueBox:IsShown() then valueAnchor = row.valueBox end
                        row.deleteBtn:SetPoint("LEFT", valueAnchor, "RIGHT", 5, 0)
                    end
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- 启用/禁用添加规则按钮
    local addBtn = getglobal("Guda_CategoryEditor_AddRuleButton")
    if addBtn then
        if numRules >= MAX_RULES then
            addBtn:Disable()
        else
            addBtn:Enable()
        end
    end
end

-- 添加新规则
function GudaBag.CategoryEditor_AddRule()
    if table.getn(editorRules) >= MAX_RULES then return end

    table.insert(editorRules, { type = "itemType", value = "Consumable" })
    GudaBag.CategoryEditor_UpdateRulesDisplay()
end

-- 移除规则
function GudaBag.CategoryEditor_RemoveRule(index)
    -- 删除规则时，若该规则的类型/值下拉正打开，一并关闭，避免残留显示
    GudaBag.CloseSimpleDropdown()
    if index > 0 and index <= table.getn(editorRules) then
        table.remove(editorRules, index)
        GudaBag.CategoryEditor_UpdateRulesDisplay()
    end
end

-- 辅助函数：设置规则类型（从下拉框调用）
function GudaBag.CategoryEditor_SetRuleType(ruleIndex, typeId)
    if not editorRules[ruleIndex] then return end

    editorRules[ruleIndex].type = typeId
    -- 类型改变时重置值
    if RULE_VALUE_OPTIONS[typeId] then
        editorRules[ruleIndex].value = RULE_VALUE_OPTIONS[typeId][1]
        -- 转换为正确的类型
        if typeId == "quality" or typeId == "qualityMin" then
            editorRules[ruleIndex].value = 0
        elseif typeId == "isBoE" or typeId == "isBoP" or typeId == "isQuestItem" or typeId == "isSoulShard" or typeId == "isProjectile" then
            editorRules[ruleIndex].value = true
        elseif typeId == "isRecentlyLooted" then
            editorRules[ruleIndex].value = 600
        end
    else
        editorRules[ruleIndex].value = ""
    end
    GudaBag.CategoryEditor_UpdateRulesDisplay()
end

-- 辅助函数：设置规则值（从下拉框调用）
function GudaBag.CategoryEditor_SetRuleValue(ruleIndex, val, ruleType)
    if not editorRules[ruleIndex] then return end

    if ruleType == "quality" or ruleType == "qualityMin" then
        local num = tonumber(string.sub(val, 1, 1))
        editorRules[ruleIndex].value = num or 0
    elseif ruleType == "isBoE" or ruleType == "isBoP" or ruleType == "isQuestItem" or ruleType == "isSoulShard" or ruleType == "isProjectile" then
        editorRules[ruleIndex].value = (val == "true")
    elseif ruleType == "isRecentlyLooted" then
        editorRules[ruleIndex].value = tonumber(val) or 600
    else
        editorRules[ruleIndex].value = val
    end
    GudaBag.CategoryEditor_UpdateRulesDisplay()
end

-- 显示类型下拉菜单
function GudaBag.CategoryEditor_ShowTypeDropdown(button, ruleIndex)
    local menu = {}
    for i = 1, table.getn(RULE_TYPE_OPTIONS) do
        local opt = RULE_TYPE_OPTIONS[i]
        table.insert(menu, {
            text = GudaBag.L[opt.name] or opt.name,
            ruleIndex = ruleIndex,
            typeId = opt.id,
        })
    end

    GudaBag.ShowSimpleDropdown(button, menu, "type")
end

-- 显示值下拉菜单
function GudaBag.CategoryEditor_ShowValueDropdown(button, ruleIndex)
    local rule = editorRules[ruleIndex]
    if not rule then return end

    local options = RULE_VALUE_OPTIONS[rule.type]
    if not options then return end

    local menu = {}
    for i = 1, table.getn(options) do
        local val = options[i]
        -- "最近拾取"规则的值是秒数（300/600/1200），显示时补上"秒"单位，
        -- 避免用户看不懂纯数字。底层 value 仍是纯数字串，逻辑不受影响。
        local displayText = GudaBag.L[val] or val
        if rule.type == "isRecentlyLooted" then
            displayText = displayText .. " 秒"
        end
        table.insert(menu, {
            text = displayText,
            ruleIndex = ruleIndex,
            ruleType = rule.type,
            value = val,
        })
    end

    GudaBag.ShowSimpleDropdown(button, menu, "value")
end

-- 简易下拉菜单辅助函数
local dropdownFrame = nil
local dropdownAnchor = nil  -- 当前下拉所锚定的按钮（用于再次点击时收起）
-- 关闭简易下拉（供编辑器关闭、设置切换等场合调用）
function GudaBag.CloseSimpleDropdown()
    if dropdownFrame then
        dropdownFrame:Hide()
        dropdownFrame.hideTimer = nil
        dropdownAnchor = nil
    end
end
function GudaBag.ShowSimpleDropdown(anchor, menuItems, menuType)
    -- 再次点击同一触发按钮时收起下拉（toggle）
    if dropdownFrame and dropdownFrame:IsShown() and dropdownAnchor == anchor then
        GudaBag.CloseSimpleDropdown()
        return
    end
    if not dropdownFrame then
        dropdownFrame = CreateFrame("Frame", "Guda_SimpleDropdown", UIParent)
        -- 编辑分类框架（CategoryEditor）是 toplevel，交互时引擎会把它置于
        -- 所在 strata（FULLSCREEN_DIALOG）的顶层，同 strata 内即便 frame level
        -- 更高也会被盖住。因此把下拉放到最高 TOOLTIP strata，天然在所有
        -- FULLSCREEN_DIALOG 内容之上。
        dropdownFrame:SetFrameStrata("TOOLTIP")
        dropdownFrame:SetFrameLevel(200)
        dropdownFrame:SetWidth(150)
        dropdownFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        dropdownFrame:SetBackdropColor(0, 0, 0, 1)
        dropdownFrame:EnableMouse(true)
        dropdownFrame:Hide()

        dropdownFrame:SetScript("OnLeave", function()
            -- 鼠标离开后经过短暂延迟隐藏
            this.hideTimer = 0.5
        end)
        dropdownFrame:SetScript("OnUpdate", function()
            if this.hideTimer then
                this.hideTimer = this.hideTimer - arg1
                if this.hideTimer <= 0 then
                    this.hideTimer = nil
                    -- 检查鼠标是否悬停在任意子项上
                    if not MouseIsOver(this) then
                        this:Hide()
                    end
                end
            end
        end)
    end

    -- 清除旧按钮
    local children = { dropdownFrame:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    -- 创建菜单按钮
    local btnHeight = 20
    local totalHeight = 10
    for i, item in ipairs(menuItems) do
        local btn = CreateFrame("Button", nil, dropdownFrame)
        btn:SetWidth(140)
        btn:SetHeight(btnHeight)
        btn:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 5, -(5 + (i-1) * btnHeight))

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", btn, "LEFT", 5, 0)
        text:SetText(item.text)
        btn.text = text

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(btn)
        highlight:SetTexture(1, 1, 1, 0.2)

        -- 为 vanilla Lua 闭包兼容性在按钮上存储数据
        btn.menuType = menuType
        btn.ruleIndex = item.ruleIndex
        btn.typeId = item.typeId
        btn.ruleType = item.ruleType
        btn.value = item.value
        btn.themeId = item.themeId

        btn:SetScript("OnClick", function()
            dropdownFrame:Hide()
            if this.menuType == "type" then
                GudaBag.CategoryEditor_SetRuleType(this.ruleIndex, this.typeId)
            elseif this.menuType == "value" then
                GudaBag.CategoryEditor_SetRuleValue(this.ruleIndex, this.value, this.ruleType)
            elseif this.menuType == "theme" then
                GudaBag.SettingsPopup_ApplyTheme(this.themeId)
            end
        end)
        btn:SetScript("OnEnter", function()
            dropdownFrame.hideTimer = nil
        end)

        totalHeight = totalHeight + btnHeight
    end
    totalHeight = totalHeight + 5

    dropdownFrame:SetHeight(totalHeight)
    dropdownFrame:ClearAllPoints()
    dropdownFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    dropdownFrame:Show()
    dropdownFrame.hideTimer = nil
    dropdownAnchor = anchor
end

-- 保存分类更改
function GudaBag.CategoryEditor_Save()
    if not editorCategoryId or not Guda.Modules.CategoryManager then return end

    local categoryDef = Guda.Modules.CategoryManager:GetCategory(editorCategoryId)
    if not categoryDef then return end

    -- 获取名称（仅用于自定义分类）
    local nameBox = getglobal("Guda_CategoryEditor_NameEditBox")
    if nameBox and not categoryDef.isBuiltIn then
        categoryDef.name = nameBox:GetText()
    end

    -- 设置匹配模式
    categoryDef.matchMode = editorMatchMode

    -- 设置分类标记
    categoryDef.categoryMark = editorMark

    -- 设置规则
    categoryDef.rules = {}
    for _, rule in ipairs(editorRules) do
        if rule.type and rule.type ~= "" then
            table.insert(categoryDef.rules, {
                type = rule.type,
                value = rule.value,
                required = rule.required and true or nil,
            })
        end
    end

    -- 从 EditBox 读取分组
    local groupBox = getglobal("Guda_CategoryEditor_GroupEditBox")
    local newGroup = "Main" -- 默认
    if groupBox then
        local text = groupBox:GetText() or ""
        -- 去除首尾空白
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        if text ~= "" then
            newGroup = text
        end
    end

    -- 设置分组（通过 SetCategoryGroup 处理分组更改以获得正确的重新排序）
    local oldGroup = categoryDef.group or "Main"
    if newGroup ~= oldGroup then
        -- 先保存定义，再移动分组
        Guda.Modules.CategoryManager:UpdateCategory(editorCategoryId, categoryDef)
        Guda.Modules.CategoryManager:SetCategoryGroup(editorCategoryId, newGroup)
    else
        -- 保存到数据库
        Guda.Modules.CategoryManager:UpdateCategory(editorCategoryId, categoryDef)
    end

    -- 刷新显示
    GudaBag.SettingsPopup_CategoriesTab_Update()
    GudaBag.SettingsPopup_RefreshBagFrames()

    -- 关闭编辑器
    local editor = getglobal("Guda_CategoryEditor")
    if editor then editor:Hide() end

    Guda:Print(format((GudaBag.L and GudaBag.L["Category '%s' saved."]) or "Category '%s' saved.", categoryDef.name or editorCategoryId))
end

-- 初始化
function SettingsPopup:Initialize()
    Guda:Debug("Settings popup initialized")
end

