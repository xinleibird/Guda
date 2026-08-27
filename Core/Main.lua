-- Guda 主初始化
-- 设置所有模块和自动保存系统

local addon = Guda
local L = GudaBag.L

local Main = {}
addon.Modules.Main = Main

-- 初始化插件
function Main:Initialize()
    -- 等待 PLAYER_LOGIN 以确保已保存变量加载完成
    addon.Modules.Events:OnPlayerLogin(function()
        addon:Print(L["Initializing..."])

        -- 初始化数据库
        addon.Modules.DB:Initialize()

        -- 初始化跨账号共享（可选，需要 GudaIO DLL）
        if addon.Modules.SharedData and addon.Modules.SharedData.Initialize then
            addon.Modules.SharedData:Initialize()
        end

        -- 初始化物品检测（在扫描器之前，因为它们可能会用到它）
        if addon.Modules.ItemDetection then
            addon.Modules.ItemDetection:Initialize()
        end

        -- 初始化扫描器
        addon.Modules.BagScanner:Initialize()
        addon.Modules.BankScanner:Initialize()
        addon.Modules.MailboxScanner:Initialize()
        addon.Modules.MoneyTracker:Initialize()
		addon.Modules.EquipmentScanner:Initialize()

        -- 启用非空包自动换包（拦截"非空包无法装备"错误 → 自动清空旧包再换包）
        if addon.Modules.BagReplacer and addon.Modules.BagReplacer.EnableAutoSwap then
            addon.Modules.BagReplacer:EnableAutoSwap()
        end

        -- 初始化最近拾取跟踪（供 "Recently Looted" 分类使用）
        if addon.Modules.RecentLoot and addon.Modules.RecentLoot.Initialize then
            addon.Modules.RecentLoot:Initialize()
        end

        -- 初始化装备套装（Outfitter/ItemRack 集成）
        if addon.Modules.EquipmentSets then
            addon.Modules.EquipmentSets:Initialize()
        end

        -- 初始化界面
        addon:Print(L["Initializing UI..."])
        addon.Modules.BagFrame:Initialize()
        addon.Modules.BankFrame:Initialize()
        addon.Modules.MailboxFrame:Initialize()
        
        addon:Debug("Checking QuestItemBar module...")
        if addon.Modules.QuestItemBar and addon.Modules.QuestItemBar.isLoaded then
            addon:Debug("QuestItemBar module found and loaded, initializing...")
            local success, err = pcall(function() addon.Modules.QuestItemBar:Initialize() end)
            if not success then
                addon:Error("Failed to initialize QuestItemBar: %s", tostring(err))
            end
        else
            if not addon.Modules.QuestItemBar then
                addon:Error("QuestItemBar module table is MISSING from addon.Modules!")
            else
                addon:Error("QuestItemBar module file failed to load (isLoaded is nil)!")
            end
        end

        addon:Debug("Checking TrackedItemBar module...")
        if addon.Modules.TrackedItemBar and addon.Modules.TrackedItemBar.isLoaded then
            addon:Debug("TrackedItemBar module found and loaded, initializing...")
            local success, err = pcall(function() addon.Modules.TrackedItemBar:Initialize() end)
            if not success then
                addon:Error("Failed to initialize TrackedItemBar: %s", tostring(err))
            end
        end
        
        addon.Modules.SettingsPopup:Initialize()

        -- 应用初始透明度设置
        if GudaBag.ApplyBackgroundTransparency then
            GudaBag.ApplyBackgroundTransparency()
        end

        -- 初始化提示框
        if addon.Modules.Tooltip then
            addon.Modules.Tooltip:Initialize()
        else
            addon:Error("Tooltip module not loaded!")
        end

        -- 初始化自动拾取处理（LOOT_OPENED 监听器）
        if addon.Modules.AutoLoot and addon.Modules.AutoLoot.Initialize then
            addon.Modules.AutoLoot:Initialize()
        end

        -- 初始化蚌壳打开器（注册 BAG_UPDATE 以自动打开）
        if addon.Modules.ClamOpener and addon.Modules.ClamOpener.Initialize then
            addon.Modules.ClamOpener:Initialize()
        end

        -- 在后台预加载 ItemDetection / BagScanner 缓存，这样登录后第一次
        -- 打开背包窗口不会因为提示框扫描而卡顿。
        if addon.Modules.CacheWarmer and addon.Modules.CacheWarmer.Initialize then
            addon.Modules.CacheWarmer:Initialize()
        end

        -- 设置斜杠命令
        Main:SetupSlashCommands()

        -- 标记插件就绪以供按键绑定包装器使用，并处理任何待处理的切换
        addon._ready = true
        if addon._pendingToggleBags then
            addon._pendingToggleBags = false
            if addon.Modules.BagFrame and addon.Modules.BagFrame.Toggle then
                addon.Modules.BagFrame:Toggle()
            end
        end
        if addon._pendingToggleBank then
            addon._pendingToggleBank = false
            if addon.Modules.BankFrame and addon.Modules.BankFrame.Toggle then
                addon.Modules.BankFrame:Toggle()
            end
        end

        addon:Debug("Initialization complete")
        addon:Print(L["Ready! Type /guda to open bags"])
    end, "Main")
end

-- 设置斜杠命令
function Main:SetupSlashCommands()
    SLASH_Guda1 = "/Guda"
    SLASH_Guda2 = "/guda"

    SlashCmdList["Guda"] = function(msg)
        msg = string.lower(msg or "")

        if msg == "" or msg == "bags" then
            -- 切换背包
            addon.Modules.BagFrame:Toggle()

        elseif msg == "bank" then
            -- 切换银行
            addon.Modules.BankFrame:Toggle()

        elseif msg == "mail" or msg == "mailbox" then
            -- 切换邮箱
            addon.Modules.MailboxFrame:Toggle()

        elseif msg == "sort" then
            -- 整理背包
            addon.Modules.SortEngine:SortBags()

        elseif msg == "sortbank" then
            -- 整理银行
            addon.Modules.SortEngine:SortBank()

        elseif msg == "openclams" or msg == "clams" then
            -- 打开背包中的所有蚌壳
            addon.Modules.ClamOpener:Open()

        elseif msg == "debug" then
            -- 切换调试
            addon.DEBUG = not addon.DEBUG
            addon:Print(L["Debug mode: %s"], addon.DEBUG and L["ON"] or L["OFF"])

        elseif msg == "debugsort" then
            -- 切换调试排序（详细的排序输出）
            addon.DEBUG_SORT = not addon.DEBUG_SORT
            addon:Print(L["Debug sort mode: %s"], addon.DEBUG_SORT and L["ON"] or L["OFF"])

        elseif msg == "debugcat" then
            -- 切换调试分类视图（用于排查布局问题）
            addon.DEBUG_CATEGORY = not addon.DEBUG_CATEGORY
            addon:Print(L["Debug category mode: %s"], addon.DEBUG_CATEGORY and L["ON"] or L["OFF"])

        elseif msg == "quest" then
            -- 切换任务栏
            local show = not addon.Modules.DB:GetSetting("showQuestBar")
            addon.Modules.DB:SetSetting("showQuestBar", show)
            addon.Modules.QuestItemBar:Update()
            addon:Print(L["Quest bar: %s"], show and L["ON"] or L["OFF"])

        elseif msg == "track" then
            -- 切换追踪物品栏可见性
            local frame = Guda_TrackedItemBar
            if frame then
                if frame:IsShown() then
                    frame:Hide()
                else
                    frame:Show()
                end
            end

        elseif msg == "settings" or msg == "options" or msg == "config" then
            -- 打开设置窗口
            if GudaBag.OpenSettings then
                GudaBag.OpenSettings()
            elseif addon.Modules.SettingsPopup and addon.Modules.SettingsPopup.Toggle then
                addon.Modules.SettingsPopup:Toggle()
            else
                addon:Print(L["Settings window not available"])
            end

        elseif msg == "cleanup" then
            -- 清理旧角色
            addon.Modules.DB:CleanupOldCharacters()

        elseif msg == "perf" or msg == "performance" then
            -- 显示性能统计
            if addon.Modules.Utils and addon.Modules.Utils.PrintPerformanceStats then
                addon.Modules.Utils:PrintPerformanceStats()
            else
                addon:Print(L["Performance stats not available"])
            end
            -- 同时显示分类缓存统计
            if addon.Modules.CategoryManager and addon.Modules.CategoryManager.GetCacheStats then
                local stats = addon.Modules.CategoryManager:GetCacheStats()
                addon:Print("Category Cache: %d hits, %d misses (%.1f%% hit rate)",
                    stats.hits, stats.misses, stats.hitRate)
            end
            -- 显示提示框缓存统计
            if addon.Modules.Utils and addon.Modules.Utils.GetTooltipCacheStats then
                local stats = addon.Modules.Utils:GetTooltipCacheStats()
                addon:Print("Tooltip Cache: %d hits, %d misses (%.1f%% hit rate)",
                    stats.hits, stats.misses, stats.hitRate)
            end
            -- 显示物品检测缓存统计
            if addon.Modules.ItemDetection and addon.Modules.ItemDetection.GetCacheStats then
                local stats = addon.Modules.ItemDetection:GetCacheStats()
                addon:Print("ItemDetection Cache: %d hits, %d misses (%.1f%% hit rate, %d items)",
                    stats.hits, stats.misses, stats.hitRate, stats.size)
            end
            -- 显示按钮池统计
            if GudaBag.GetButtonPoolStats then
                local stats = GudaBag.GetButtonPoolStats()
                addon:Print("Button Pool: %d total (%d shown, %d hidden, %d inUse, %d available, max %d)",
                    stats.total, stats.shown, stats.hidden, stats.inUse, stats.available, stats.maxSize)
            end

        elseif msg == "perfreset" then
            -- 重置性能统计
            if addon.Modules.Utils and addon.Modules.Utils.ResetPerformanceStats then
                addon.Modules.Utils:ResetPerformanceStats()
                addon:Print(L["Performance stats reset"])
            end
            -- 同时清除分类缓存
            if addon.Modules.CategoryManager and addon.Modules.CategoryManager.ClearCache then
                addon.Modules.CategoryManager:ClearCache()
            end
            -- 清除提示框缓存
            if addon.Modules.Utils and addon.Modules.Utils.ClearTooltipCache then
                addon.Modules.Utils:ClearTooltipCache()
            end
            -- 清除物品检测缓存
            if addon.Modules.ItemDetection and addon.Modules.ItemDetection.ClearCache then
                addon.Modules.ItemDetection:ClearCache()
            end

        elseif msg == "poolreset" then
            -- 重置按钮池（仅在没有可见窗口时安全）
            local bagFrame = getglobal("Guda_BagFrame")
            local bankFrame = getglobal("Guda_BankFrame")
            if (bagFrame and bagFrame:IsShown()) or (bankFrame and bankFrame:IsShown()) then
                addon:Print(L["Cannot reset pool while bag/bank frames are open. Close them first."])
            else
                if GudaBag.ResetButtonPool then
                    GudaBag.ResetButtonPool()
                    addon:Print(L["Button pool reset. Pool is now empty."])
                else
                    addon:Print(L["Button pool reset function not available."])
                end
            end

        elseif msg == "help" then
            -- 显示帮助
            addon:Print(L["Commands:"])
            addon:Print(L["/guda - Toggle bags"])
            addon:Print(L["/guda bank - Toggle bank"])
            addon:Print(L["/guda mail - Toggle mailbox"])
            addon:Print(L["/guda settings - Open settings"])
            addon:Print(L["/guda sort - Sort bags"])
            addon:Print(L["/guda sortbank - Sort bank"])
            addon:Print(L["/guda openclams - Open all clams in bags"])
            addon:Print(L["/guda track - Toggle item tracking"])
            addon:Print(L["/guda debug - Toggle debug mode"])
            addon:Print(L["/guda debugsort - Toggle sort debug output"])
            addon:Print(L["/guda cleanup - Remove old characters"])
            addon:Print(L["/guda perf - Show performance stats"])
            addon:Print(L["/guda perfreset - Reset performance stats"])
            addon:Print(L["/guda poolreset - Reset button pool (debug)"])

        else
            addon:Print(L["Unknown command. Type /guda help for commands"])
        end
    end

    addon:Debug("Slash commands registered")
end

-- 运行初始化
Main:Initialize()
