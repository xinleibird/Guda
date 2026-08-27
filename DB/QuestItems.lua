-- Guda 任务物品数据库
-- 包含特定阵营的任务物品 ID
-- 用于即使在提示框未标注时也将物品标记为任务物品

local addon = Guda

-- 按阵营区分的任务物品
-- "both" = 联盟和部落都适用的任务物品
-- "alliance" = 仅联盟的任务物品
-- "horde" = 仅部落的任务物品
addon.QuestItemsDB = {
    both = {
        [3404] = true,
        [8483] = true,
        [8393] = true,
        [8396] = true,
        [11404] = true,
        [20404] = true,
    },
    alliance = {
        [723] = true,
        [729] = true,
        [730] = true,
        [731] = true,
        [2296] = true,
    },
    horde = {
        --[2296] = true,
    },
}

-- 检查物品 ID 是否为给定阵营的任务物品
-- 返回：isQuestItem（布尔值）、factionSpecific（字符串或 nil）
function addon:IsQuestItemByID(itemID, playerFaction)
    if not itemID then return false, nil end

    -- 先检查"双方"阵营
    if self.QuestItemsDB.both[itemID] then
        return true, "both"
    end

    -- 检查特定阵营
    if playerFaction then
        local factionKey = string.lower(playerFaction)
        if self.QuestItemsDB[factionKey] and self.QuestItemsDB[factionKey][itemID] then
            return true, factionKey
        end
    end

    return false, nil
end
