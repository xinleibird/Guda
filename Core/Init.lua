-- Guda - 乌龟魔兽背包插件
-- 核心初始化

-- 创建插件命名空间
Guda = {}
local addon = Guda

-- 版本信息
addon.VERSION = "1.0.0"
addon.BUILD = "TurtleWoW-1.12.1"

-- 调试标志
addon.DEBUG = false

-- 调试排序标志（详细的排序输出）
addon.DEBUG_SORT = false

-- 调试分类视图标志（用于排查分类视图布局问题）
addon.DEBUG_CATEGORY = false

-- 常量
addon.Constants = {
    -- 背包 ID
    BACKPACK = 0,
    BAG_1 = 1,
    BAG_2 = 2,
    BAG_3 = 3,
    BAG_4 = 4,
    BANK = -1,
    BANK_BAG_1 = 5,
    BANK_BAG_2 = 6,
    BANK_BAG_3 = 7,
    BANK_BAG_4 = 8,
    BANK_BAG_5 = 9,
    BANK_BAG_6 = 10,

    -- 所有背包 ID，便于遍历
    BAGS = {0, 1, 2, 3, 4},
    BANK_BAGS = {-1, 5, 6, 7, 8, 9, 10},
    ALL_BAGS = {0, 1, 2, 3, 4, -1, 5, 6, 7, 8, 9, 10},

    -- 物品品质（颜色）
    QUALITY_COLORS = {
        [0] = {r = 0.62, g = 0.62, b = 0.62}, -- 粗糙（灰色）
        [1] = {r = 1.00, g = 1.00, b = 1.00}, -- 普通（白色）
        [2] = {r = 0.12, g = 1.00, b = 0.00}, -- 优秀（绿色）
        [3] = {r = 0.00, g = 0.44, b = 0.87}, -- 稀有（蓝色）
        [4] = {r = 0.64, g = 0.21, b = 0.93}, -- 史诗（紫色）
        [5] = {r = 1.00, g = 0.50, b = 0.00}, -- 传说（橙色）
    },

    -- 保存间隔
    SAVE_INTERVAL = 1800, -- 30 分钟（秒）

    -- 界面常量
    BUTTON_SIZE = 37,
    BUTTON_SPACING = 3,
    BUTTONS_PER_ROW = 10,
    MIN_ICON_SIZE = 30,
    MAX_ICON_SIZE = 64,

    -- 背景配置（避免在各个界面文件中重复定义）
    Backdrops = {
        -- 标准框架背景（用于主窗口）
        DEFAULT_FRAME = {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        },

        -- 极简边框（启用"隐藏边框"设置时使用）
        MINIMALIST_BORDER = {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 2,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        },

        -- 下拉框/弹出框背景（用于角色选择下拉菜单）
        DROPDOWN = {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        }
    },

    -- 背景颜色（常用配置）
    BackdropColors = {
        DEFAULT = {r = 0, g = 0, b = 0, a = 0.85},
        DROPDOWN = {r = 0, g = 0, b = 0, a = 0.95},
    },
}

-- 初始化模块存储
addon.Modules = {
    Main = {},
    DB = {},
    Events = {},
    Utils = {},
    Tooltip = {},
    BagScanner = {},
    BankScanner = {},
    MailboxScanner = {},
    MoneyTracker = {},
    EquipmentScanner = {},
    SortEngine = {},
    BagFrame = {},
    BankFrame = {},
    MailboxFrame = {},
    QuestItemBar = {},
    TrackedItemBar = {},
    SettingsPopup = {},
}

-- 就绪标志，用于安全的早期按键绑定处理
addon._ready = false
addon._pendingToggleBags = false
addon._pendingToggleBank = false
addon._deferBagsRegistered = false
addon._deferBankRegistered = false

-- 按键绑定的全局安全包装器（早期定义且始终可用）
function GudaBag.ToggleBags()
    local a = Guda
    if a and a._ready and a.Modules and a.Modules.BagFrame and a.Modules.BagFrame.Toggle then
        a.Modules.BagFrame:Toggle()
        return
    end

    -- 延迟到 PLAYER_LOGIN 完成插件初始化
    if a and a.Modules and a.Modules.Events and not a._deferBagsRegistered then
        a._pendingToggleBags = true
        a._deferBagsRegistered = true
        a.Modules.Events:OnPlayerLogin(function()
            if Guda and Guda._pendingToggleBags then
                Guda._pendingToggleBags = false
                if Guda.Modules and Guda.Modules.BagFrame and Guda.Modules.BagFrame.Toggle then
                    Guda.Modules.BagFrame:Toggle()
                end
            end
        end, "Guda_KeybindDefer_Bags")
    else
        -- 如果 Events 尚不可用，则设置待处理标志；Main 就绪时会清除它
        if a then a._pendingToggleBags = true end
    end
end

function GudaBag.ToggleBank()
    local a = Guda
    local function doToggleBank()
        if Guda_BankFrame and Guda_BankFrame:IsShown() then
            Guda_BankFrame:Hide()
        else
            if a and a.Modules and a.Modules.DB then
                local fullName = a.Modules.DB:GetPlayerFullName()
                -- WoW 1.12 使用 getglobal/setglobal；`_G` 不可用（Lua 5.0）
                local showBankFn = GudaBag.BagFrame_ShowCharacterBank or nil
                if fullName and showBankFn then
                    -- 优先使用导出的辅助函数
                    showBankFn(fullName)
                elseif a and a.Modules and a.Modules.BankFrame then
                    a.Modules.BankFrame:ShowCharacter(fullName)
                    if Guda_BankFrame then Guda_BankFrame:Show() end
                end
            end
        end
    end

    if a and a._ready then
        doToggleBank()
        return
    end

    if a and a.Modules and a.Modules.Events and not a._deferBankRegistered then
        a._pendingToggleBank = true
        a._deferBankRegistered = true
        a.Modules.Events:OnPlayerLogin(function()
            if Guda and Guda._pendingToggleBank then
                Guda._pendingToggleBank = false
                doToggleBank()
            end
        end, "Guda_KeybindDefer_Bank")
    else
        if a then a._pendingToggleBank = true end
    end
end

-- 应用带颜色的背景的辅助函数
-- 对于主框架（DEFAULT_FRAME / MINIMALIST_BORDER），在 Theme 模块可用时委托给它。
-- 像 "DROPDOWN" 这样的显式类型会绕过主题设置。
function addon:ApplyBackdrop(frame, backdropType, colorType)
    -- 对于主框架背景类型，在 Theme 模块可用时使用它
    if (backdropType == "DEFAULT_FRAME" or backdropType == "MINIMALIST_BORDER") and self.Modules and self.Modules.Theme then
        self.Modules.Theme:ApplyToFrame(frame)
        return
    end

    local backdrop = self.Constants.Backdrops[backdropType]
    local color = self.Constants.BackdropColors[colorType or "DEFAULT"]

    if not backdrop or not color then
        self:Debug("Invalid backdrop type: %s or color type: %s",
                   tostring(backdropType), tostring(colorType))
        return
    end

    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(color.r, color.g, color.b, color.a)

    -- 为极简边框设置白色边框颜色
    if backdropType == "MINIMALIST_BORDER" then
        frame:SetBackdropBorderColor(1, 1, 1, 1)
    end
end

-- 带插件前缀的打印函数
function addon:Print(msg, a1, a2, a3, a4, a5, a6, a7)
    local text = string.format(msg, a1, a2, a3, a4, a5, a6, a7)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF96Guda:|r " .. text)
end

-- 调试打印
function addon:Debug(msg, a1, a2, a3, a4, a5, a6, a7)
    if self.DEBUG then
        local text = string.format(msg, a1, a2, a3, a4, a5, a6, a7)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r |cFF00FF96Guda:|r " .. text)
    end
end

-- 调试排序打印（仅在启用 DEBUG_SORT 时显示）
function addon:DebugSort(msg, a1, a2, a3, a4, a5, a6, a7)
    if self.DEBUG_SORT then
        local text = string.format(msg, a1, a2, a3, a4, a5, a6, a7)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF87CEEB[Sort]|r |cFF00FF96Guda:|r " .. text)
    end
end

-- 调试分类视图打印（仅在启用 DEBUG_CATEGORY 时显示）
function addon:DebugCategory(msg, a1, a2, a3, a4, a5, a6, a7)
    if self.DEBUG_CATEGORY then
        local text = string.format(msg or "nil", a1 or "", a2 or "", a3 or "", a4 or "", a5 or "", a6 or "", a7 or "")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF69B4[Category]|r |cFF00FF96Guda:|r " .. text)
    end
end

-- 错误处理
function addon:Error(msg, a1, a2, a3, a4, a5, a6, a7)
    local text = string.format(msg, a1, a2, a3, a4, a5, a6, a7)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Error]|r |cFF00FF96Guda:|r " .. text)
end

-- 将框架添加到 UISpecialFrames，以便可以用 Esc 键关闭
if not UISpecialFrames then UISpecialFrames = {} end
table.insert(UISpecialFrames, "Guda_BagFrame")
table.insert(UISpecialFrames, "Guda_BankFrame")
table.insert(UISpecialFrames, "Guda_SettingsPopup")

-- 屏蔽烦人的"物品已经被拾取"（物品已被拾取）界面错误消息
do
	local _origAddMessage = UIErrorsFrame.AddMessage
	UIErrorsFrame.AddMessage = function(self, message, r, g, b, displayTime)
		if message and strfind(message, "物品已经被拾取") then
			return -- 吞掉
		end
		return _origAddMessage(self, message, r, g, b, displayTime)
	end
end

addon:Print("Loaded v%s", addon.VERSION)
