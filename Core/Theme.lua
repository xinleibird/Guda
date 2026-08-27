-- Guda 主题系统
-- 提供 Guda 暗色与 Blizzard 经典外观之间的主题选择

local addon = Guda

local Theme = {}
addon.Modules.Theme = Theme

-- 主题调试标记 — 设为 true 并 /reload 以跟踪每次 ApplyToFrame 调用
addon.DEBUG_THEME = false

local function ThemeDebug(msg, a1, a2, a3, a4, a5, a6, a7)
    if addon.DEBUG_THEME then
        local text = string.format(msg or "nil", a1 or "", a2 or "", a3 or "", a4 or "", a5 or "", a6 or "", a7 or "")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r " .. text)
    end
end

-- 从 pfUI_config.appearance.border 读取颜色（例如 "background" 或 "color"）
-- pfUI 将颜色存储为逗号分隔的字符串: "R,G,B,A"
local function ParseColorString(str)
    if not str then return nil end
    local vals = {}
    for v in string.gfind(str, "[^,]+") do
        table.insert(vals, tonumber(v))
    end
    if vals[1] then
        return vals[1], vals[2], vals[3], vals[4]
    end
    return nil
end

local function GetPfUIColor(key)
    if pfUI_config and pfUI_config.appearance and pfUI_config.appearance.border then
        return ParseColorString(pfUI_config.appearance.border[key])
    end
    return nil
end

-- 主题定义
-- 背景通过独立的 Texture 子对象渲染（而非 bgFile）。
local themes = {
    guda = {
        bgTexture = "Interface\\ChatFrame\\ChatFrameBackground",
        bgColor = { r = 0.08, g = 0.08, b = 0.08 },
        bgTile = true,
        bgTileSize = 16,
        border = {
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        },
        borderMinimal = {
            edgeFile = "",
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        },
        nineSlice = {
            corner = "Interface\\AddOns\\Guda\\Assets\\NineSlice-Corner",
            edgeH  = "Interface\\AddOns\\Guda\\Assets\\NineSlice-EdgeH",
            edgeV  = "Interface\\AddOns\\Guda\\Assets\\NineSlice-EdgeV",
            cornerSize = 32,
            edgeThickness = 16,
        },
        titleColor = { r = 1, g = 0.82, b = 0 },
        slotBgAlpha = { empty = 0.5, filled = 0.3 },
        footerButtonBg = { 0.12, 0.12, 0.12, 1 },
        footerButtonBorder = { 0.30, 0.30, 0.30, 1 },
        showHeaderButtonBg = false,
    },
    blizzard = {
        bgTexture = "Interface\\ChatFrame\\ChatFrameBackground",
        bgColor = { r = 0, g = 0, b = 0 },
        bgTile = true,
        bgTileSize = 16,
        bgOverlay = "Interface\\AddOns\\Guda\\Assets\\UI-Background-Rock",
        border = {
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        },
        borderMinimal = {
            edgeFile = "",
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        },
        nineSlice = {
            corner = "Interface\\AddOns\\Guda\\Assets\\NineSlice-Corner",
            edgeH  = "Interface\\AddOns\\Guda\\Assets\\NineSlice-EdgeH",
            edgeV  = "Interface\\AddOns\\Guda\\Assets\\NineSlice-EdgeV",
            cornerSize = 32,
            edgeThickness = 16,
        },
        titleColor = { r = 1, g = 0.82, b = 0 },
        slotBgAlpha = { empty = 1, filled = 1 },
        footerButtonBg = { 0.12, 0.12, 0.12, 1 },
        footerButtonBorder = { 0.30, 0.30, 0.30, 1 },
        showHeaderButtonBg = true,
        headerButtonBg = { 0.15, 0.12, 0.10, 0.6 },
        headerButtonBorder = { 0.45, 0.40, 0.35, 1 },
    },
    pfui = {
        bgTexture = "Interface\\Buttons\\WHITE8x8",
        bgColor = { r = 0, g = 0, b = 0 },
        bgTile = false,
        bgTileSize = 1,
        border = {
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = -1, right = -1, top = -1, bottom = -1 }
        },
        borderMinimal = {
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = -1, right = -1, top = -1, bottom = -1 }
        },
        nineSlice = nil,
        titleColor = { r = 1, g = 1, b = 1 },
        slotBgAlpha = { empty = 0.5, filled = 0.3 },
        footerButtonBg = { 0, 0, 0, 1 },
        footerButtonBorder = { 0.2, 0.2, 0.2, 1 },
        showHeaderButtonBg = false,
        slotStyle = "square",
        borderColor = { 0.2, 0.2, 0.2, 1 },
        qualityBorderStyle = "square",
    },
    dragonflight = {
        bgTexture = "Interface\\ChatFrame\\ChatFrameBackground",
        bgColor = { r = 0, g = 0, b = 0 },
        bgTile = true,
        bgTileSize = 16,
        border = {
            edgeFile = "",
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        },
        borderMinimal = {
            edgeFile = "",
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        },
        nineSlice = {
            corner = "Interface\\AddOns\\Guda\\Assets\\NineSlice-Corner",
            edgeH  = "Interface\\AddOns\\Guda\\Assets\\NineSlice-EdgeH",
            edgeV  = "Interface\\AddOns\\Guda\\Assets\\NineSlice-EdgeV",
            cornerSize = 32,
            edgeThickness = 16,
        },
        -- 金色渐变边框（Dragonflight 风格的金色外框）
        gradientBorder = true,
        goldBorder = {
            bright = { 1.0, 0.86, 0.38 },
            dark   = { 0.72, 0.48, 0.10 },
        },
        titleColor = { r = 1.0, g = 0.82, b = 0.35 },
        slotBgAlpha = { empty = 0.5, filled = 0.3 },
        footerButtonBg = { 0.12, 0.10, 0.04, 1 },
        footerButtonBorder = { 0.85, 0.68, 0.25, 1 },
        showHeaderButtonBg = true,
        headerButtonBg = { 0.14, 0.11, 0.04, 0.8 },
        headerButtonBorder = { 0.85, 0.68, 0.25, 1 },
        borderColor = { 1.0, 0.82, 0.35, 1 },
    },
}

-- 缓存的活动主题
local cachedTheme = nil
local cachedThemeName = nil

-- 从数据库获取活动主题名称
local function GetThemeName()
    if addon.Modules and addon.Modules.DB then
        return addon.Modules.DB:GetSetting("theme") or "guda"
    end
    return "guda"
end

-- 获取活动主题表（缓存）
function Theme:Get()
    local name = GetThemeName()
    if cachedTheme and cachedThemeName == name then
        return cachedTheme
    end
    cachedThemeName = name
    local base = themes[name] or themes.guda

    -- 当 pfUI 主题处于活动状态且 pfUI 已加载时，继承 pfUI 的颜色
    if name == "pfui" then
        -- 浅拷贝，以免修改静态主题表
        local t = {}
        for k, v in pairs(base) do t[k] = v end

        local br, bg, bb, ba = GetPfUIColor("background")
        if br then
            t.bgColor = { r = br, g = bg, b = bb }
            t.footerButtonBg = { br, bg, bb, ba or 1 }
        end
        local er, eg, eb, ea = GetPfUIColor("color")
        if er then
            t.borderColor = { er, eg, eb, ea or 1 }
            t.footerButtonBorder = { er, eg, eb, ea or 1 }
        end
        cachedTheme = t
    else
        cachedTheme = base
    end

    return cachedTheme
end

-- 单一属性查找
function Theme:GetValue(key)
    local t = self:Get()
    return t[key]
end

-- 获取槽位样式（pfUI 为方形，其他为圆角）
function Theme:GetSlotStyle()
    return self:GetValue("slotStyle") or "rounded"
end

-- 获取品质边框样式
function Theme:GetQualityBorderStyle()
    return self:GetValue("qualityBorderStyle") or "rounded"
end

-- 获取框架内边距值（为 pfUI 无边框样式减少）
function Theme:GetFramePadding()
    local style = self:GetSlotStyle()
    if style == "square" then
        return {
            containerExtra = 10,  -- 加到 columns*size 上作为容器宽度
            frameExtra = 10,      -- 加到 containerWidth 上作为框架宽度
            titleHeight = 28,
            qualityBarHeight = 27,
            searchBarHeight = 28,
            footerHeight = 55,
            footerHiddenHeight = 5,
            startX = 10,
            startY = -5,
        }
    else
        return {
            containerExtra = 20,
            frameExtra = 20,
            titleHeight = 40,
            qualityBarHeight = 27,
            searchBarHeight = 30,
            footerHeight = 55,
            footerHiddenHeight = 10,
            startX = 10,
            startY = -2,
        }
    end
end

-- 根据 hideBorders 设置获取边框配置
local function GetBorderConfig(t)
    local hideBorders = false
    if addon.Modules and addon.Modules.DB then
        hideBorders = addon.Modules.DB:GetSetting("hideBorders")
        if hideBorders == nil then hideBorders = false end
    end
    if hideBorders then
        return t.borderMinimal, true
    else
        return t.border, false
    end
end

-- 隐藏 NineSlice 纹理
local function HideNineSlice(frame)
    if not frame._gudaNineSlice then return end
    for i = 1, 8 do
        frame._gudaNineSlice[i]:Hide()
    end
end

-- 应用或隐藏 TGA 背景纹理（用于 bgFile TGA 无法与 SetBackdrop 协同的主题）
-- 使用 ARTWORK 图层，使其始终渲染在背景的 BACKGROUND 填充之上，
-- 避免两者共享同一 BACKGROUND 图层时出现的间歇性 z-order 问题。
local function ApplyBgTexture(frame, texturePath, alpha, padding)
    if not frame._gudaBgTex then
        frame._gudaBgTex = frame:CreateTexture(nil, "ARTWORK")
    end
    local p = padding or 6
    local tex = frame._gudaBgTex
    tex:ClearAllPoints()
    tex:SetTexture(texturePath)
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", p, -p)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -p, p)
    tex:SetAlpha(alpha or 1)
    tex:Show()
end

local function HideBgTexture(frame)
    if frame._gudaBgTex then
        frame._gudaBgTex:Hide()
    end
end

local function HideBgQuadrants(frame)
    if not frame._gudaBgQuad then return end
    for i = 1, 4 do
        frame._gudaBgQuad[i]:Hide()
    end
end

-- 使用独立纹理文件应用 NineSlice 金属边框
-- 使用 3 个 TGA 源文件: Corner、EdgeH、EdgeV
-- 角通过 SetTexCoord 翻转（仅 0/1 交换）
local function ApplyNineSlice(frame, cfg, tint)
    local cs = cfg.cornerSize   -- 32
    local et = cfg.edgeThickness -- 16

    -- 创建或复用 8 个纹理: BL, TL, TR, BR, Bottom, Top, Left, Right
    if not frame._gudaNineSlice then
        frame._gudaNineSlice = {}
        for i = 1, 8 do
            frame._gudaNineSlice[i] = frame:CreateTexture(nil, "OVERLAY")
        end
    end

    local ns = frame._gudaNineSlice

    -- 1: 左下角（原样）
    local bl = ns[1]
    bl:ClearAllPoints()
    bl:SetTexture(cfg.corner)
    bl:SetWidth(cs)
    bl:SetHeight(cs)
    bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bl:SetTexCoord(0, 1, 0, 1)
    bl:Show()

    -- 2: 左上角（垂直翻转）
    local tl = ns[2]
    tl:ClearAllPoints()
    tl:SetTexture(cfg.corner)
    tl:SetWidth(cs)
    tl:SetHeight(cs)
    tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tl:SetTexCoord(0, 1, 1, 0)
    tl:Show()

    -- 3: 右上角（双向翻转）
    local tr = ns[3]
    tr:ClearAllPoints()
    tr:SetTexture(cfg.corner)
    tr:SetWidth(cs)
    tr:SetHeight(cs)
    tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tr:SetTexCoord(1, 0, 1, 0)
    tr:Show()

    -- 4: 右下角（水平翻转）
    local br = ns[4]
    br:ClearAllPoints()
    br:SetTexture(cfg.corner)
    br:SetWidth(cs)
    br:SetHeight(cs)
    br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    br:SetTexCoord(1, 0, 0, 1)
    br:Show()

    -- 5: 底边（在 BL 和 BR 角之间拉伸）
    local bottom = ns[5]
    bottom:ClearAllPoints()
    bottom:SetTexture(cfg.edgeH)
    bottom:SetHeight(et)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", cs, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -cs, 0)
    bottom:SetTexCoord(0, 1, 0, 1)
    bottom:Show()

    -- 6: 顶边（垂直翻转）
    local top = ns[6]
    top:ClearAllPoints()
    top:SetTexture(cfg.edgeH)
    top:SetHeight(et)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", cs, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -cs, 0)
    top:SetTexCoord(0, 1, 1, 0)
    top:Show()

    -- 7: 左边（在 TL 和 BL 角之间拉伸）
    local left = ns[7]
    left:ClearAllPoints()
    left:SetTexture(cfg.edgeV)
    left:SetWidth(et)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -cs)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, cs)
    left:SetTexCoord(0, 1, 0, 1)
    left:Show()

    -- 8: 右边（水平翻转）
    local right = ns[8]
    right:ClearAllPoints()
    right:SetTexture(cfg.edgeV)
    right:SetWidth(et)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -cs)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, cs)
    right:SetTexCoord(1, 0, 0, 1)
    right:Show()

    -- 可选着色（例如 Dragonflight 蓝色边框）应用于全部 8 片
    if tint then
        for i = 1, 8 do
            frame._gudaNineSlice[i]:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
        end
    end
end

-- 应用 Dragonflight 风格的金色渐变外边框。
-- 在框架边缘使用 4 条实心渐变条（上/下/左/右），使
-- 边缘呈现金色渐变描边效果。这避免了拉伸
-- UI-DialogBox-Border 边缘文件纹理，该纹理在用作
-- 全框架覆盖层时会产生不想要的条纹。
local function ApplyGoldGradientBorder(frame, bright, dark)
    if not frame._gudaGoldBorder then
        frame._gudaGoldBorder = {}
        for i = 1, 4 do
            frame._gudaGoldBorder[i] = frame:CreateTexture(nil, "OVERLAY")
        end
    end
    local ns = frame._gudaGoldBorder
    local thickness = 3

    -- 顶边：左侧亮 -> 右侧暗
    ns[1]:ClearAllPoints()
    ns[1]:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    ns[1]:SetGradient("HORIZONTAL", bright[1], bright[2], bright[3], dark[1], dark[2], dark[3])
    ns[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    ns[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    ns[1]:SetHeight(thickness)
    ns[1]:Show()

    -- 底边：左侧暗 -> 右侧亮（反向以使渐变环绕）
    ns[2]:ClearAllPoints()
    ns[2]:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    ns[2]:SetGradient("HORIZONTAL", dark[1], dark[2], dark[3], bright[1], bright[2], bright[3])
    ns[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    ns[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    ns[2]:SetHeight(thickness)
    ns[2]:Show()

    -- 左边：顶部亮 -> 底部暗
    ns[3]:ClearAllPoints()
    ns[3]:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    ns[3]:SetGradient("VERTICAL", bright[1], bright[2], bright[3], dark[1], dark[2], dark[3])
    ns[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    ns[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    ns[3]:SetWidth(thickness)
    ns[3]:Show()

    -- 右边：顶部暗 -> 底部亮
    ns[4]:ClearAllPoints()
    ns[4]:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    ns[4]:SetGradient("VERTICAL", dark[1], dark[2], dark[3], bright[1], bright[2], bright[3])
    ns[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    ns[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    ns[4]:SetWidth(thickness)
    ns[4]:Show()
end

local function HideGoldGradientBorder(frame)
    if frame._gudaGoldBorder then
        for i = 1, 4 do
            frame._gudaGoldBorder[i]:Hide()
        end
    end
end

-- 将主题应用到单个框架
function Theme:ApplyToFrame(frame)
    if not frame then
        ThemeDebug("ApplyToFrame called with nil frame")
        return
    end

    local frameName = frame:GetName() or "unnamed"
    ThemeDebug("--- ApplyToFrame: %s ---", frameName)

    local t = self:Get()
    local borderCfg, isMinimal = GetBorderConfig(t)

    ThemeDebug("  theme=%s  minimal=%s", tostring(cachedThemeName), tostring(isMinimal))
    ThemeDebug("  bgTexture=%s  tileSize=%s", tostring(t.bgTexture), tostring(t.bgTileSize))

    -- 确定是否使用 NineSlice（完整边框模式 + 主题具有 nineSlice 配置）
    local useNineSlice = t.nineSlice and not isMinimal
    local useGoldBorder = t.gradientBorder and not isMinimal

    -- 当主题不使用金色边框时，确保金色边框已隐藏
    if not useGoldBorder then
        HideGoldGradientBorder(frame)
    end

    if useGoldBorder then
        -- 纯黑色背景（无 edgeFile）；金色渐变边框单独绘制
        local backdrop = {
            bgFile = t.bgTexture,
            tile = true,
            tileSize = t.bgTileSize,
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        }
        frame:SetBackdrop(nil)
        frame:SetBackdrop(backdrop)
        HideNineSlice(frame)
        local gb = t.goldBorder or {}
        local bright = gb.bright or { 1.0, 0.86, 0.38 }
        local dark = gb.dark or { 0.72, 0.48, 0.10 }
        ApplyGoldGradientBorder(frame, bright, dark)
        ThemeDebug("  SetBackdrop done (pure black bg + gold gradient border)")
    elseif useNineSlice then
        -- 仅背景（无 edgeFile），NineSlice 处理边框
        local backdrop = {
            bgFile = t.bgTexture,
            tile = true,
            tileSize = t.bgTileSize,
            edgeSize = 0,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        }
        frame:SetBackdrop(nil)
        frame:SetBackdrop(backdrop)
        ApplyNineSlice(frame, t.nineSlice, t.borderColor)
        ThemeDebug("  SetBackdrop done (bgFile + NineSlice border)")
    else
        -- 带 edgeFile 边框的标准背景（或隐藏时无边框）
        local hasEdge = borderCfg.edgeFile and borderCfg.edgeFile ~= ""
        local backdrop
        if hasEdge then
            backdrop = {
                bgFile = t.bgTexture,
                edgeFile = borderCfg.edgeFile,
                tile = true,
                tileSize = t.bgTileSize,
                edgeSize = borderCfg.edgeSize,
                insets = {
                    left = borderCfg.insets.left,
                    right = borderCfg.insets.right,
                    top = borderCfg.insets.top,
                    bottom = borderCfg.insets.bottom,
                }
            }
        else
            -- 无边框：完全省略 edgeFile 键（WoW 1.12 会在
            -- edgeFile 为 "" 或 nil 时渲染黑色线条）
            backdrop = {
                bgFile = t.bgTexture,
                tile = true,
                tileSize = t.bgTileSize,
                edgeSize = 0,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            }
        end
        frame:SetBackdrop(nil)
        frame:SetBackdrop(backdrop)
        HideNineSlice(frame)
        ThemeDebug("  SetBackdrop done (bgFile + %s border)", hasEdge and "edgeFile" or "none")
    end

    -- 当存在边框时应用边框颜色
    local hasEdge = borderCfg.edgeFile and borderCfg.edgeFile ~= ""
    if hasEdge then
        local bc = t.borderColor or { 1, 1, 1, 1 }
        if isMinimal or t.borderColor then
            frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
        end
    end

    -- 背景象限纹理（为测试禁用）
    HideBgQuadrants(frame)

    -- TGA 背景覆盖层（CreateTexture，因为 TGA 无法与 SetBackdrop 的 bgFile 协同）
    if t.bgOverlay then
        local transparency = 0.15
        if addon.Modules and addon.Modules.DB then
            transparency = addon.Modules.DB:GetSetting("bgTransparency") or 0.15
        end
        local bgPadding = isMinimal and 0 or 6
        ApplyBgTexture(frame, t.bgOverlay, 1.0 - transparency, bgPadding)
    else
        HideBgTexture(frame)
    end

    -- 背景颜色 / 透明度
    local bg = t.bgColor
    local alpha
    local usePfUITransp = false
    if addon.Modules and addon.Modules.DB then
        usePfUITransp = addon.Modules.DB:GetSetting("usePfUITransparency")
    end
    if cachedThemeName == "pfui" and usePfUITransp ~= false then
        local _, _, _, ba = GetPfUIColor("background")
        alpha = ba or 1
    else
        local transparency = 0.15
        if addon.Modules and addon.Modules.DB then
            transparency = addon.Modules.DB:GetSetting("bgTransparency") or 0.15
        end
        alpha = 1.0 - transparency
    end
    frame:SetBackdropColor(bg.r, bg.g, bg.b, alpha)
    ThemeDebug("  SetBackdropColor(%s,%s,%s,%s)", tostring(bg.r), tostring(bg.g), tostring(bg.b), tostring(alpha))

    -- 清理先前方法的遗留子框架 / 纹理
    if frame._gudaBgFrame then
        frame._gudaBgFrame:Hide()
        frame._gudaBgFrame:SetParent(nil)
        frame._gudaBgFrame = nil
    end
    if frame._gudaBg then
        frame._gudaBg:Hide()
    end

    -- 若主题定义了标题颜色则应用（让窗口标题跟随主题）
    local tc = t.titleColor
    if tc then
        local title = frameName and getglobal(frameName .. "_Title")
        if title and title.SetTextColor then
            title:SetTextColor(tc.r, tc.g, tc.b)
        end
    end

    -- 验证
    local bd = frame:GetBackdrop()
    if bd then
        ThemeDebug("  VERIFY: bgFile=%s tile=%s tileSize=%s",
            tostring(bd.bgFile), tostring(bd.tile), tostring(bd.tileSize))
    end
    ThemeDebug("  VERIFY: frame size=%sx%s  visible=%s  level=%s  strata=%s",
        tostring(frame:GetWidth()), tostring(frame:GetHeight()),
        tostring(frame:IsVisible()), tostring(frame:GetFrameLevel()),
        tostring(frame:GetFrameStrata()))
end

-- 将主题应用到所有主框架
function Theme:ApplyToAllFrames()
    ThemeDebug("=== ApplyToAllFrames ===")
    local frameNames = { "Guda_BagFrame", "Guda_BankFrame", "Guda_MailboxFrame", "Guda_SettingsPopup", "Guda_CategoryEditor" }
    for _, frameName in ipairs(frameNames) do
        local frame = getglobal(frameName)
        if frame then
            self:ApplyToFrame(frame)
        else
            ThemeDebug("  frame %s NOT FOUND (nil)", frameName)
        end
    end

    -- 更新所有现有物品按钮上的槽位背景透明度
    local sa = self:GetValue("slotBgAlpha")
    if sa then
        self:UpdateAllSlotBackgrounds(sa)
    end

    -- 更新底部按钮背景（包槽 + 钥匙串）
    if GudaBag.BagSlot_ApplyBackdrop then
        local footerButtons = {
            "Guda_BagFrame_Toolbar_BagSlot0",
            "Guda_BagFrame_Toolbar_BagSlot1",
            "Guda_BagFrame_Toolbar_BagSlot2",
            "Guda_BagFrame_Toolbar_BagSlot3",
            "Guda_BagFrame_Toolbar_BagSlot4",
            "Guda_BagFrame_Toolbar_KeyringButton",
            "Guda_BagFrame_Toolbar_SoulBagButton",
        }
        for _, name in ipairs(footerButtons) do
            local btn = getglobal(name)
            if btn then GudaBag.BagSlot_ApplyBackdrop(btn) end
        end
        -- 也更新弹出按钮
        for i = 1, 4 do
            local btn = getglobal("Guda_BagFlyout_Slot" .. i)
            if btn then GudaBag.BagSlot_ApplyBackdrop(btn) end
        end
    end

    -- 更新标题按钮背景
    self:ApplyHeaderButtonBackgrounds()

    -- 更新搜索框样式
    self:ApplySearchBoxStyle()

    -- 为无边框/pfUI 主题调整框架内边距
    self:ApplyFramePadding()

    ThemeDebug("=== ApplyToAllFrames done ===")
end

-- 更新所有可见物品按钮上的 emptySlotBg 透明度和样式
function Theme:UpdateAllSlotBackgrounds(sa)
    local slotStyle = self:GetSlotStyle()
    local i = 1
    while true do
        local btn = getglobal("Guda_ItemButton" .. i)
        if not btn then break end
        local bg = getglobal(btn:GetName() .. "_EmptySlotBg")
        if bg then
            -- 根据槽位样式更新纹理和锚点
            if slotStyle == "square" then
                bg:SetTexture("Interface\\Buttons\\WHITE8x8")
                bg:SetVertexColor(0.05, 0.05, 0.05, 1)
                bg:ClearAllPoints()
                bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                bg:SetTexCoord(0, 1, 0, 1)
            else
                bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                bg:SetVertexColor(1, 1, 1, 1)
                bg:ClearAllPoints()
                bg:SetPoint("TOPLEFT", btn, "TOPLEFT", -9, 9)
                bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 9, -9)
                bg:SetTexCoord(0, 1, 0, 1)
            end
            local alpha = btn.hasItem and sa.filled or sa.empty
            if alpha > 0 then
                bg:SetAlpha(alpha)
                bg:Show()
            else
                bg:Hide()
            end
        end
        i = i + 1
    end
end

-- 基于主题应用或移除标题按钮背景
local headerButtonBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

function Theme:ApplyHeaderButtonBg(button)
    local showBg = self:GetValue("showHeaderButtonBg")
    if showBg then
        -- 创建或复用图标后面的背景框架
        if not button._themeBg then
            local bg = CreateFrame("Frame", nil, button)
            bg:SetWidth(button:GetWidth() + 4)
            bg:SetHeight(button:GetHeight() + 4)
            bg:SetPoint("CENTER", button, "CENTER", 0, 0)
            bg:SetFrameLevel(button:GetFrameLevel())
            bg:SetBackdrop(headerButtonBackdrop)
            button._themeBg = bg
        end
        local hbBg = self:GetValue("headerButtonBg") or { 0.5, 0.06, 0.06, 0.6 }
        local hbBorder = self:GetValue("headerButtonBorder") or { 0.5, 0.06, 0.06, 1 }
        button._themeBg:SetBackdropColor(hbBg[1], hbBg[2], hbBg[3], hbBg[4])
        button._themeBg:SetBackdropBorderColor(hbBorder[1], hbBorder[2], hbBorder[3], hbBorder[4])
        button._themeBg:Show()
    else
        if button._themeBg then
            button._themeBg:Hide()
        end
    end
end

function Theme:ApplyHeaderButtonBackgrounds()
    local headerButtons = {
        -- BagFrame（背包框架）
        "Guda_BagFrame_SettingsButton",
        "Guda_BagFrame_SortButton",
        "Guda_BagFrame_DisenchantButton",
        "Guda_BagFrame_PickLockButton",
        "Guda_BagFrame_CharsButton",
        "Guda_BagFrame_BankButton",
        "Guda_BagFrame_MailButton",
        -- BankFrame（银行框架）
        "Guda_BankFrame_SettingsButton",
        "Guda_BankFrame_SortButton",
        "Guda_BankFrame_CharsButton",
        "Guda_BankFrame_BlizzardUIButton",
        -- MailboxFrame（邮箱框架）
        "Guda_MailboxFrame_CharacterButton",
    }
    for _, name in ipairs(headerButtons) do
        local btn = getglobal(name)
        if btn then
            self:ApplyHeaderButtonBg(btn)
        end
    end
end

-- 将方形/圆角样式应用于搜索框
function Theme:ApplySearchBoxStyle()
    local slotStyle = self:GetSlotStyle()
    local searchBoxNames = {
        "Guda_BagFrame_SearchBar_SearchBox",
        "Guda_BankFrame_SearchBar_SearchBox",
    }
    for _, name in ipairs(searchBoxNames) do
        local box = getglobal(name)
        if box then
            -- 隐藏 InputBoxTemplate 边框纹理（Left、Right、Middle）
            local left = getglobal(name .. "Left")
            local right = getglobal(name .. "Right")
            local mid = getglobal(name .. "Middle")
            if slotStyle == "square" then
                if left then left:Hide() end
                if right then right:Hide() end
                if mid then mid:Hide() end
                -- 应用 pfUI 风格背景
                box:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                    insets = { left = -1, right = -1, top = -1, bottom = -1 },
                })
                local t = self:Get()
                local sbg = t.bgColor
                box:SetBackdropColor(sbg.r, sbg.g, sbg.b, 1)
                local sbc = t.borderColor or { 0.2, 0.2, 0.2, 1 }
                box:SetBackdropBorderColor(sbc[1], sbc[2], sbc[3], sbc[4])
                -- 重新定位到 x=10 处平齐左侧
                box:ClearAllPoints()
                box:SetPoint("LEFT", box:GetParent(), "LEFT", 8, 0)
                box:SetPoint("RIGHT", box:GetParent(), "RIGHT", -7, 0)
                -- 在字段内部添加文本内边距
                box:SetTextInsets(5, 5, 0, 0)
            else
                if left then left:Show() end
                if right then right:Show() end
                if mid then mid:Show() end
                box:SetBackdrop(nil)
                -- 恢复默认锚点
                box:ClearAllPoints()
                box:SetPoint("LEFT", box:GetParent(), "LEFT", 15, 0)
                box:SetPoint("RIGHT", box:GetParent(), "RIGHT", -12, 0)
                -- 恢复默认文本内边距
                box:SetTextInsets(3, 3, 0, 0)
            end
        end
    end
end

-- 调整标题/底部内边距以匹配主题边框样式
function Theme:ApplyFramePadding()
    local slotStyle = self:GetSlotStyle()
    -- 仅对 pfUI/方形样式调整；否则恢复默认
    local isPfui = (slotStyle == "square")

    -- BagFrame 调整
    local bagFrameElements = {
        { name = "Guda_BagFrame_Title",       pfui = { "TOP", nil, "TOP", 0, -8 },        default = { "TOP", nil, "TOP", 0, -12 } },
        { name = "Guda_BagFrame_CloseButton", pfui = { "TOPRIGHT", nil, "TOPRIGHT", -5, -5 }, default = { "TOPRIGHT", nil, "TOPRIGHT", -13, -10 } },
        { name = "Guda_BagFrame_CharsButton", pfui = { "TOPLEFT", nil, "TOPLEFT", 10, -8 },   default = { "TOPLEFT", nil, "TOPLEFT", 21, -15 } },
        { name = "Guda_BagFrame_QualityBar",  pfui = { "TOP", nil, "TOP", 0, -30 },       default = { "TOP", nil, "TOP", 0, -40 } },
        { name = "Guda_BagFrame_SearchBar",   pfui = { "TOP", "Guda_BagFrame_QualityBar", "BOTTOM", 0, -5 }, default = { "TOP", "Guda_BagFrame_QualityBar", "BOTTOM", 0, -5 } },
        { name = "Guda_BagFrame_Toolbar",     pfui = { "BOTTOMLEFT", nil, "BOTTOMLEFT", 5, 5 }, default = { "BOTTOMLEFT", nil, "BOTTOMLEFT", 10, 5 } },
        { name = "Guda_BagFrame_MoneyFrame", pfui = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -5, 7 }, default = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -5, 7 } },
    }
    for _, elem in ipairs(bagFrameElements) do
        local frame = getglobal(elem.name)
        if frame then
            local pos = isPfui and elem.pfui or elem.default
            local relTo = pos[2] or frame:GetParent()
            frame:ClearAllPoints()
            frame:SetPoint(pos[1], relTo, pos[3], pos[4], pos[5])
        end
    end

    -- BankFrame 调整（结构相似）
    local bankFrameElements = {
        { name = "Guda_BankFrame_Title",          pfui = { "TOP", nil, "TOP", 0, -8 },            default = { "TOP", nil, "TOP", 0, -12 } },
        { name = "Guda_BankFrame_CloseButton",  pfui = { "TOPRIGHT", nil, "TOPRIGHT", -5, -5 }, default = { "TOPRIGHT", nil, "TOPRIGHT", -13, -10 } },
        { name = "Guda_BankFrame_BlizzardUIButton", pfui = { "TOPLEFT", nil, "TOPLEFT", 10, -8 }, default = { "TOPLEFT", nil, "TOPLEFT", 23, -15 } },
        { name = "Guda_BankFrame_SearchBar",    pfui = { "TOP", nil, "TOP", 0, -30 },       default = { "TOP", nil, "TOP", 0, -40 } },
        { name = "Guda_BankFrame_Toolbar",      pfui = { "BOTTOMLEFT", nil, "BOTTOMLEFT", 5, 5 }, default = { "BOTTOMLEFT", nil, "BOTTOMLEFT", 15, 5 } },
    }
    for _, elem in ipairs(bankFrameElements) do
        local frame = getglobal(elem.name)
        if frame then
            local pos = isPfui and elem.pfui or elem.default
            local relTo = pos[2] or frame:GetParent()
            frame:ClearAllPoints()
            frame:SetPoint(pos[1], relTo, pos[3], pos[4], pos[5])
        end
    end
end

-- 清除缓存（主题设置更改时调用）
function Theme:ClearCache()
    cachedTheme = nil
    cachedThemeName = nil
end

-- 切换主题调试的斜杠命令
SLASH_GUDATHEME1 = "/gudatheme"
SlashCmdList["GUDATHEME"] = function(msg)
    if msg == "on" then
        addon.DEBUG_THEME = true
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r Debug ON — reapplying all frames...")
        Theme:ApplyToAllFrames()
    elseif msg == "off" then
        addon.DEBUG_THEME = false
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r Debug OFF")
    elseif msg == "apply" then
        local prev = addon.DEBUG_THEME
        addon.DEBUG_THEME = true
        Theme:ApplyToAllFrames()
        addon.DEBUG_THEME = prev
    elseif msg == "inspect" then
        -- 在不重新应用的情况下转储所有框架的背景状态
        local frameNames = { "Guda_BagFrame", "Guda_BankFrame", "Guda_MailboxFrame", "Guda_SettingsPopup", "Guda_CategoryEditor" }
        -- 显示当前透明度设置
        local transp = "N/A"
        if addon.Modules and addon.Modules.DB then
            transp = tostring(addon.Modules.DB:GetSetting("bgTransparency"))
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF8800[Theme]|r === Inspect Backdrop === (bgTransparency=%s, alpha=%s)",
            transp, tostring(1.0 - (tonumber(transp) or 0.15))))
        for _, fn in ipairs(frameNames) do
            local f = getglobal(fn)
            if f then
                local bd = f:GetBackdrop()
                if bd then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFF00%s|r: bgFile=%s edgeFile=%s tile=%s tileSize=%s",
                        fn, tostring(bd.bgFile), tostring(bd.edgeFile), tostring(bd.tile), tostring(bd.tileSize)))
                else
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFF00%s|r: backdrop=nil", fn))
                end
                DEFAULT_CHAT_FRAME:AddMessage(string.format("    visible=%s  size=%dx%d  level=%s  strata=%s",
                    tostring(f:IsVisible()), f:GetWidth(), f:GetHeight(),
                    tostring(f:GetFrameLevel()), tostring(f:GetFrameStrata())))
                -- 检查子背景框架
                if f._gudaBgFrame then
                    local cbd = f._gudaBgFrame:GetBackdrop()
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("    bgFrame: bgFile=%s shown=%s visible=%s level=%s",
                        cbd and tostring(cbd.bgFile) or "nil",
                        tostring(f._gudaBgFrame:IsShown()),
                        tostring(f._gudaBgFrame:IsVisible()),
                        tostring(f._gudaBgFrame:GetFrameLevel())))
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFF0000%s|r: frame not found", fn))
            end
        end
    elseif msg == "test" then
        -- 创建独立测试框架，以隔离哪些纹理通过 Lua 渲染
        local p = DEFAULT_CHAT_FRAME
        p:AddMessage("|cFFFF8800[Theme]|r === Texture Test ===")

        -- 测试 1: ChatFrameBackground（已知可用）
        local f1 = CreateFrame("Frame", "GudaThemeTest1", UIParent)
        f1:SetWidth(200); f1:SetHeight(200)
        f1:SetPoint("CENTER", -220, 0)
        f1:SetFrameStrata("TOOLTIP")
        f1:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        f1:SetBackdropColor(0, 0, 0, 1)
        f1:Show()
        p:AddMessage("  Test 1 (LEFT): ChatFrameBackground — should be solid black")

        -- 测试 2: UI-DialogBox-Background（有问题的那个）
        local f2 = CreateFrame("Frame", "GudaThemeTest2", UIParent)
        f2:SetWidth(200); f2:SetHeight(200)
        f2:SetPoint("CENTER", 0, 0)
        f2:SetFrameStrata("TOOLTIP")
        f2:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        f2:SetBackdropColor(1, 1, 1, 1)
        f2:Show()
        p:AddMessage("  Test 2 (CENTER): UI-DialogBox-Background — should be parchment")

        -- 测试 3: UI-Tooltip-Background（另一种常用纹理）
        local f3 = CreateFrame("Frame", "GudaThemeTest3", UIParent)
        f3:SetWidth(200); f3:SetHeight(200)
        f3:SetPoint("CENTER", 220, 0)
        f3:SetFrameStrata("TOOLTIP")
        f3:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        f3:SetBackdropColor(1, 1, 1, 1)
        f3:Show()
        p:AddMessage("  Test 3 (RIGHT): UI-Tooltip-Background — should be purple/blue")

        p:AddMessage("|cFFFF8800[Theme]|r /gudatheme clear to remove test frames")

    elseif msg == "scan" then
        -- 启用悬停扫描：悬停任意框架以打印其背景信息
        if addon._themeScanFrame then
            addon._themeScanFrame:Hide()
            addon._themeScanFrame = nil
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r Scan OFF")
        else
            local scanner = CreateFrame("Frame", nil, UIParent)
            scanner:SetAllPoints(UIParent)
            scanner:SetFrameStrata("TOOLTIP")
            scanner:EnableMouse(false)
            scanner._lastFrame = nil
            scanner:SetScript("OnUpdate", function()
                local f = GetMouseFocus()
                if f and f ~= this._lastFrame then
                    this._lastFrame = f
                    local name = f:GetName() or "unnamed"
                    local p = DEFAULT_CHAT_FRAME

                    -- 若有背景则打印
                    local bd = f.GetBackdrop and f:GetBackdrop()
                    if bd and (bd.bgFile or bd.edgeFile) then
                        p:AddMessage(string.format(
                            "|cFFFF8800[Scan]|r |cFFFFFF00%s|r bgFile=%s edgeFile=%s tile=%s tileSize=%s",
                            name, tostring(bd.bgFile), tostring(bd.edgeFile),
                            tostring(bd.tile), tostring(bd.tileSize)))
                    end

                    -- 通过 GetRegions() 打印纹理
                    if f.GetRegions then
                        local regions = { f:GetRegions() }
                        for i, region in ipairs(regions) do
                            if region and region.GetTexture then
                                local tex = region:GetTexture()
                                if tex and tex ~= "" then
                                    local rname = region:GetName() or ("region" .. i)
                                    local layer = region.GetDrawLayer and region:GetDrawLayer() or "?"
                                    p:AddMessage(string.format(
                                        "|cFFFF8800[Scan]|r   |cFF88FF88%s|r tex=%s layer=%s",
                                        rname, tostring(tex), tostring(layer)))
                                end
                            end
                        end
                    end

                    -- 若未打印任何内容，至少显示框架名称
                    if not (bd and (bd.bgFile or bd.edgeFile)) then
                        local hasTextures = false
                        if f.GetRegions then
                            local regions = { f:GetRegions() }
                            for _, region in ipairs(regions) do
                                if region and region.GetTexture and region:GetTexture() and region:GetTexture() ~= "" then
                                    hasTextures = true
                                    break
                                end
                            end
                        end
                        if not hasTextures then
                            p:AddMessage(string.format("|cFFFF8800[Scan]|r |cFF888888%s|r (no backdrop, no textures)", name))
                        end
                    end
                end
            end)
            scanner:Show()
            addon._themeScanFrame = scanner
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r Scan ON — hover any frame to see its backdrop. /gudatheme scan again to stop.")
        end

    elseif msg == "clear" then
        for _, name in ipairs({"GudaThemeTest1", "GudaThemeTest2", "GudaThemeTest3"}) do
            local f = getglobal(name)
            if f then f:Hide() end
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r Test frames hidden")

    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[Theme]|r Usage:")
        DEFAULT_CHAT_FRAME:AddMessage("  /gudatheme on      — Enable debug logging")
        DEFAULT_CHAT_FRAME:AddMessage("  /gudatheme off     — Disable debug logging")
        DEFAULT_CHAT_FRAME:AddMessage("  /gudatheme apply   — Reapply all frames (with debug)")
        DEFAULT_CHAT_FRAME:AddMessage("  /gudatheme inspect — Dump backdrop state")
        DEFAULT_CHAT_FRAME:AddMessage("  /gudatheme test    — Show 3 test frames with different textures")
        DEFAULT_CHAT_FRAME:AddMessage("  /gudatheme clear   — Hide test frames")
    end
end

addon:Debug("Theme module loaded")
