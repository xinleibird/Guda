-- Guda SharedData 模块
-- 通过 GudaIO DLL（可选）进行跨账号角色数据共享
-- DLL 在启动时把所有账号的 SavedVariables 合并到 GudaShared.lua 中，
-- 该文件通过 .toc 加载并设置 GudaBag.SharedCharacters 全局变量。
--
-- 重要：共享角色存储在 addon.sharedCharacters（仅内存）中，
-- 而不是存储在 Guda_DB.characters 中，以防止它们泄漏到 SavedVariables。

local addon = Guda

local SharedData = {}
addon.Modules.SharedData = SharedData

function SharedData:Initialize()
    -- 清理旧方案泄漏的任何共享角色
    if Guda_DB and Guda_DB.characters then
        -- 先收集要移除的键（不能在 pairs 迭代期间修改表）
        local toRemove = {}
        for fullName, data in pairs(Guda_DB.characters) do
            if data.isShared then
                table.insert(toRemove, fullName)
            else
                -- 从自有角色中剥离泄漏的字段
                data.isShared = nil
                data.account = nil
            end
        end
        for _, fullName in ipairs(toRemove) do
            Guda_DB.characters[fullName] = nil
        end
    end

    -- 初始化内存中的共享角色表
    addon.sharedCharacters = {}

    if not GudaBag.SharedCharacters or type(GudaBag.SharedCharacters) ~= "table" then
        return
    end

    -- 确定哪些角色属于当前账号
    local myChars = {}
    if Guda_DB and Guda_DB.characters then
        for fullName in pairs(Guda_DB.characters) do
            myChars[fullName] = true
        end
    end

    -- 通过检查重叠来确定哪个账号名称属于我们
    local myAccount = nil
    local accountChars = {}
    for fullName, charData in pairs(GudaBag.SharedCharacters) do
        local acct = charData.account
        if acct then
            if not accountChars[acct] then accountChars[acct] = {} end
            accountChars[acct][fullName] = true
        end
    end

    for acct, chars in pairs(accountChars) do
        for fullName in pairs(chars) do
            if myChars[fullName] then
                myAccount = acct
                break
            end
        end
        if myAccount then break end
    end

    -- 如果无法识别我们自己的账号（例如在此角色上首次登录时，
    -- 在 Guda_DB.characters 中还没有我们的条目），则放弃导入，
    -- 而不是把每个角色都导入为"共享"。下次登录时会正确检测。
    if myAccount == nil then
        return
    end

    -- 把其他账号的角色导入内存表
    local importCount = 0
    for fullName, charData in pairs(GudaBag.SharedCharacters) do
        if charData.account and charData.account ~= myAccount then
            if not myChars[fullName] then
                addon.sharedCharacters[fullName] = {
                    name = charData.name,
                    realm = charData.realm,
                    faction = charData.faction,
                    class = charData.class,
                    classToken = charData.classToken,
                    level = charData.level,
                    money = charData.money,
                    bags = charData.bags,
                    bank = charData.bank,
                    mailbox = charData.mailbox,
                    equipped = charData.equipped,
                    lastUpdate = charData.lastUpdate,
                    account = charData.account,
                    isShared = true,
                }
                importCount = importCount + 1
            end
        end
    end

    if importCount > 0 then
        addon:Print(format(GudaBag.L["Imported %d character(s) from other accounts"], importCount))
    end

    -- 清理全局变量以释放内存
    GudaBag.SharedCharacters = nil
end
