-- Guda 金币追踪器
-- 追踪玩家金币并保存到数据库

local addon = Guda

local MoneyTracker = {}
addon.Modules.MoneyTracker = MoneyTracker

local lastMoney = 0

-- 更新数据库中的金币
function MoneyTracker:Update()
    local currentMoney = GetMoney()

    if currentMoney ~= lastMoney then
        addon.Modules.DB:SaveMoney(currentMoney)
        lastMoney = currentMoney
        addon:Debug("Money updated: %s", addon.Modules.Utils:FormatMoney(currentMoney))
    end
end

-- 获取当前金币
function MoneyTracker:GetCurrentMoney()
    return GetMoney()
end

-- 获取所有角色的总金币（可选地按阵营和/或服务器过滤）
function MoneyTracker:GetTotalMoney(sameFactionOnly, currentRealmOnly)
    return addon.Modules.DB:GetTotalMoney(sameFactionOnly, currentRealmOnly)
end

-- 初始化金币追踪器
function MoneyTracker:Initialize()
    -- 追踪金币变化并立即保存
    addon.Modules.Events:OnMoneyChanged(function()
        MoneyTracker:Update()
    end, "MoneyTracker")

    -- 登录时进行初始更新和保存（使用池化定时器）
    addon.Modules.Events:OnPlayerLogin(function()
        GudaBag.ScheduleTimer(1, function()
            MoneyTracker:Update()
            addon:Debug("Initial money saved")
        end)
    end, "MoneyTracker")
end
