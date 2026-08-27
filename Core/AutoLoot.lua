-- Guda 自动拾取
-- 带 SuperWoW 的乌龟魔兽移除了硬编码的 shift-自动拾取，并暴露了：
--   * SetAutoloot(0|1)            —— 全局客户端自动拾取开关
--   * LootSlot(slot, forceloot)   —— forceloot=1 是实际拾取所必需的
-- 当存在 SetAutoloot 时我们优先使用它（让客户端处理一切），
-- 同时也回退到一个调用 LootSlot(slot, 1) 的 LOOT_OPENED 处理器，
-- 这样在没有 SuperWoW 的客户端上也能工作。
--
-- 重要：若检测到其他插件已提供自动拾取（automaton / automatonEX /
-- superapi），本模块完全停用，避免双重拾取。设置界面中的自动拾取
-- 复选框也会被隐藏（见 SettingsPopup.lua）。

local addon = Guda

local AutoLoot = {}
addon.Modules.AutoLoot = AutoLoot

-- 外部插件是否已接管自动拾取（此时 guda 不参与）
local function HasExternalLoot()
    return addon.Modules.DB and addon.Modules.DB.HasExternalAutoLoot
           and addon.Modules.DB:HasExternalAutoLoot() or false
end

local function ApplyClientSetting()
    if HasExternalLoot() then return end
    local enabled = Guda.Modules.DB and Guda.Modules.DB:GetSetting("autoLoot")
    if SetAutoloot then
        SetAutoloot(enabled and 1 or 0)
    elseif SetAutoLootDefault then
        SetAutoLootDefault(enabled and true or false)
    end
end

local function OnLootOpened()
    -- 外部插件接管时完全不参与，避免重复拾取
    if HasExternalLoot() then return end
    if not (Guda.Modules.DB and Guda.Modules.DB:GetSetting("autoLoot")) then
        return
    end
    -- 如果存在 SuperWoW 的 SetAutoloot 并且已启用，那么在 LOOT_OPENED
    -- 到达我们之前客户端就已经拾取了所有物品 —— 这个循环对普通客户端
    -- 和任何遗留物（BoP 确认等）来说只是一个无害的安全网。
    local n = GetNumLootItems()
    if not n or n == 0 then return end
    for slot = n, 1, -1 do
        LootSlot(slot, 1)  -- forceloot=1 用于 SuperWoW 兼容性
        if ConfirmLootSlot then ConfirmLootSlot(slot) end
    end
end

function AutoLoot:Initialize()
    -- 外部插件已接管时，不注册也不应用任何设置
    if HasExternalLoot() then
        addon:Debug("AutoLoot disabled: external addon provides auto-loot")
        return
    end
    addon.Modules.Events:Register("LOOT_OPENED", OnLootOpened, "AutoLoot")
    ApplyClientSetting()
end

-- 由设置复选框调用，以便客户端开关立即翻转。
function AutoLoot:Apply()
    ApplyClientSetting()
end
