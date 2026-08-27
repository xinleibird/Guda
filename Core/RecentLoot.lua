-- Guda 最近拾取跟踪
-- 记录物品最近一次"真实获得"的时间，供 "Recently Looted"（最近拾取）分类
-- 与拾取标记（星星/呼吸边框）使用。
--
-- 背景：乌龟服对团队副本拾取的 BoP 装备有 10 分钟可交易宽限期。
-- 该模块帮助玩家快速定位刚拾取/交易到的装备。
--
-- 识别"真实获得"（参考 LootAlert 的拾取识别方式）：
--   * 只监听 CHAT_MSG_LOOT 事件。只有真正拾取/交易进包时才会产生
--     LOOT_ITEM_SELF / LOOT_ITEM_PUSHED_SELF 等消息（"你获得了..."）。
--     从消息文本中提取 itemLink 并记录时间戳。
--   * 脱装备、背包内移动、整理背包等都不会触发此事件，因此天然不会误判，
--     无需依赖 BAG_UPDATE 的总数 diff（该方案不可靠，已移除）。

local addon = Guda

local RecentLoot = {}
addon.Modules.RecentLoot = RecentLoot

-- 默认时间窗口（秒）：10 分钟，与乌龟服 BoP 交易宽限期一致
RecentLoot.DEFAULT_WINDOW = 600

-- recentLoot[itemLink] = GetTime() （最近一次真实获得的绝对时间）
local recentLoot = {}

-- 从 CHAT_MSG_LOOT 消息文本中提取物品链接。
-- 返回 itemLink；无物品链接时返回 nil。
local function ExtractLootLink(msg)
    if not msg or msg == "" then return nil end
    -- 格式：|cff0070dd|Hitem:12345:0:0:0:0:0:0:0:0|h[物品名]|h|r
    local link = string.match(msg, "(|c%x+|Hitem:%d+:[^|]*|h%[[^%]]+%]|h|r)")
    if not link then
        -- 兜底：只匹配 Hitem 链接核心部分
        link = string.match(msg, "(|Hitem:%d+:[^|]*|h%[[^%]]+%]|h|r)")
    end
    return link
end

-- 判断 CHAT_MSG_LOOT 消息是否属于"自己的拾取"。
-- 参考 LootAlert：用拾取者名字或 LOOT_ITEM_SELF 等消息模板的前缀匹配。
local function IsSelfLootMessage(msg, name)
    if not msg or msg == "" then return false end
    -- 优先用拾取者名字（arg2）判断；名字在回调中实时获取
    local pname = UnitName and UnitName("player")
    if name and pname and name ~= "" then
        return name == pname
    end
    -- 中英文前缀匹配（LOOT_ITEM_SELF 模板："你获得了物品：%s。" / "You receive loot: %s."）
    return strfind(msg, "你获得了") ~= nil
        or strfind(msg, "你赢得了") ~= nil
        or strfind(msg, "You receive") ~= nil
        or strfind(msg, "You get") ~= nil
        or strfind(msg, "You won") ~= nil
end

-- 初始化：注册拾取事件。
-- 注意：本函数由 Main 在 PLAYER_LOGIN 事件分发期间调用。
function RecentLoot:Initialize()
    addon.Modules.Events:Register("CHAT_MSG_LOOT", function(event, msg, name)
        if not IsSelfLootMessage(msg, name) then return end
        local link = ExtractLootLink(msg)
        if not link then return end
        recentLoot[link] = GetTime()
        addon:Debug("RecentLoot: loot msg -> %s", link)
    end, "RecentLoot")

    addon.Modules.Events:OnPlayerLogin(function()
        -- 重新登录时清空旧状态（避免跨会话残留）
        recentLoot = {}
    end)
end

-- 判断指定物品链接是否为最近获得（在 windowSec 秒内）
function RecentLoot:IsRecentlyLooted(itemLink, windowSec)
    local t = recentLoot[itemLink]
    if not t then return false end
    local w = windowSec or self.DEFAULT_WINDOW
    return (GetTime() - t) <= w
end

-- 计算"拾取标记"应使用的时间窗口（秒）。
-- 跟随分类里所有 "最近拾取"(isRecentlyLooted) 规则的值：取其中的最大值，
-- 这样只要某物品落在任意一个最近拾取分类的窗口内，红圈就会被点亮。
-- 若没有任何该规则，则回退到 DEFAULT_WINDOW（600）。
function RecentLoot:GetMarkerWindow()
    local w = self.DEFAULT_WINDOW
    local cm = addon.Modules and addon.Modules.CategoryManager
    if cm and cm.GetCategories then
        local cats = cm:GetCategories()
        if cats then
            for _, cat in pairs(cats) do
                if cat and cat.rules then
                    for _, rule in ipairs(cat.rules) do
                        if rule and rule.type == "isRecentlyLooted" and rule.value then
                            local v = tonumber(rule.value)
                            if v and v > w then w = v end
                        end
                    end
                end
            end
        end
    end
    return w
end
