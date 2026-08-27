-- Guda 事件模块
-- 负责游戏事件注册和回调

local addon = Guda

local Events = {}
addon.Modules.Events = Events

-- 事件框架
local eventFrame = CreateFrame("Frame")
Events.frame = eventFrame

-- 已注册的回调
local callbacks = {}

-- 注册一个带回调的事件
function Events:Register(event, callback, owner)
    if not callbacks[event] then
        callbacks[event] = {}
        eventFrame:RegisterEvent(event)
    end

    table.insert(callbacks[event], {
        callback = callback,
        owner = owner or "addon",
    })
end

-- 注销某个所有者注册的所有回调
function Events:UnregisterOwner(owner)
    for event, cbs in pairs(callbacks) do
        for i = table.getn(cbs), 1, -1 do
            if cbs[i].owner == owner then
                table.remove(cbs, i)
            end
        end

        -- 如果没有剩余回调则注销事件
        if table.getn(cbs) == 0 then
            eventFrame:UnregisterEvent(event)
            callbacks[event] = nil
        end
    end
end

-- 事件分发器
eventFrame:SetScript("OnEvent", function()
    if callbacks[event] then
        for _, entry in ipairs(callbacks[event]) do
            local success, err = pcall(entry.callback, event, arg1, arg2, arg3, arg4, arg5)
            if not success then
                addon:Error("Event callback error [%s]: %s", event, err)
            end
        end
    end
end)

-- 常用事件的便捷函数
function Events:OnBagUpdate(callback, owner)
    self:Register("BAG_UPDATE", callback, owner)
end

function Events:OnBankOpen(callback, owner)
    self:Register("BANKFRAME_OPENED", callback, owner)
end

function Events:OnBankClose(callback, owner)
    self:Register("BANKFRAME_CLOSED", callback, owner)
end

function Events:OnMoneyChanged(callback, owner)
    self:Register("PLAYER_MONEY", callback, owner)
end

function Events:OnPlayerLogin(callback, owner)
    self:Register("PLAYER_LOGIN", callback, owner)
end

function Events:OnPlayerLogout(callback, owner)
    self:Register("PLAYER_LOGOUT", callback, owner)
end

function Events:OnMailShow(callback, owner)
    self:Register("MAIL_SHOW", callback, owner)
end

function Events:OnMailClosed(callback, owner)
    self:Register("MAIL_CLOSED", callback, owner)
end
