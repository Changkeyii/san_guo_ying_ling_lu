-- ============================================================================
-- CloudManager - 云存档架构模块
-- 职责: 个人存档拆分、公开档案发布、好友系统、阵营系统
-- ============================================================================
---@diagnostic disable: undefined-global

local CloudManager = {}

-- ============================================================================
-- 常量 & 配置
-- ============================================================================
local PREFIX = "p_49dd_"

-- 个人存档 domain 定义
local DOMAINS = {
    core     = PREFIX .. "sv_core",
    heroes   = PREFIX .. "sv_heroes",
    equip    = PREFIX .. "sv_equip",
    skills   = PREFIX .. "sv_skills",
    progress = PREFIX .. "sv_progress",
    welfare  = PREFIX .. "sv_welfare",
    social   = PREFIX .. "sv_social",
    explore  = PREFIX .. "sv_explore",
}

-- 公开/社交 key
local KEYS = {
    combat_power  = PREFIX .. "combat_power",
    pub_profile   = PREFIX .. "pub_profile",
    realm_level   = PREFIX .. "realm_level",
    -- 好友公共申请池 (排行榜模拟公共信箱)
    freq_outbox_ts = PREFIX .. "freq_outbox_ts",  -- SetInt: 最新申请时间戳 (排行用)
    freq_outbox    = PREFIX .. "freq_outbox",      -- Set: 出站申请列表 JSON
    freq_resp_ts   = PREFIX .. "freq_resp_ts",     -- SetInt: 最新回复时间戳
    freq_resp      = PREFIX .. "freq_resp",        -- Set: 回复列表 JSON
    -- 阵营公共存储 (排行榜模拟阵营总表)
    camp_leader_ts = PREFIX .. "camp_leader_ts",   -- SetInt: 阵营创建时间 (排行用, 仅盟主)
    camp_meta      = PREFIX .. "camp_meta",        -- Set: 阵营元数据 (仅盟主维护)
    camp_apply_ts  = PREFIX .. "camp_apply_ts",    -- SetInt: 入营申请时间
    camp_apply     = PREFIX .. "camp_apply",       -- Set: 入营申请 JSON
    camp_resp_ts   = PREFIX .. "camp_resp_ts",     -- SetInt: 盟主审批回复时间
    camp_resp      = PREFIX .. "camp_resp",        -- Set: 审批回复 JSON
    -- 阵营聊天 (每人发布自己的最近消息, 轮询合并)
    camp_chat_ts   = PREFIX .. "camp_chat_ts",      -- SetInt: 最新聊天时间戳 (排行用)
    camp_chat      = PREFIX .. "camp_chat",          -- Set: 最近消息列表 JSON [{text,time,ts}]
    world_chat_ts  = PREFIX .. "world_chat_ts",      -- SetInt: 世界聊天时间戳 (排行用)
    world_chat     = PREFIX .. "world_chat",          -- Set: 世界聊天消息列表
    -- 封禁系统 (开发者通过排行榜发布封禁名单)
    ban_ts        = PREFIX .. "ban_ts",            -- SetInt: 封禁发布时间
    ban_data      = PREFIX .. "ban_data",           -- Set: 封禁名单 JSON
    -- 存档校验
    save_hash     = PREFIX .. "save_hash",          -- Set: 存档哈希校验值
    -- 兼容旧存档
    legacy_save   = PREFIX .. "savegame",
    -- 玩家邮件 (公共信箱模式)
    mail_ts       = PREFIX .. "mail_ts",           -- SetInt: 最新发件时间戳 (排行用)
    mail_outbox   = PREFIX .. "mail_outbox",       -- Set: 发件箱 JSON [{to,subject,body,rewards,time,id}]
}

local MAX_FRIENDS = 50
local REQUEST_EXPIRE_SECONDS = 7 * 86400  -- 申请7天过期
local MAX_OUTBOX = 20       -- 每人最多20条待处理出站申请
local MAX_CAMP_MEMBERS = 20 -- 阵营最大人数（1级阵营上限）
local CAMP_CREATE_COST = 5000 -- 创建阵营消耗虎符
local SAVE_VERSION = 2  -- 存档版本 (1=旧单key, 2=新多domain)

-- ============================================================================
-- 阵营职位体系 (仿率土之滨同盟)
-- 继承链: leader → vice_leader → strategist → vanguard → diplomat → elite → member
-- ============================================================================
local FACTION_ROLES = {
    leader      = { level = 6, name = "盟主",   max = 1  },
    vice_leader = { level = 5, name = "副盟主", max = 2  },
    strategist  = { level = 4, name = "军师",   max = 4  },
    vanguard    = { level = 3, name = "先锋官", max = 4  },
    diplomat    = { level = 2, name = "外交官", max = 2  },
    elite       = { level = 1, name = "精英",   max = -1 }, -- 不限
    member      = { level = 0, name = "成员",   max = -1 }, -- 不限
}

-- 按等级降序排列的角色列表 (用于继承链遍历)
local ROLE_SUCCESSION = { "vice_leader", "strategist", "vanguard", "diplomat", "elite", "member" }

--- 获取角色等级 (数字越大权限越高)
local function _getRoleLevel(role)
    local def = FACTION_ROLES[role or "member"]
    return def and def.level or 0
end

--- 获取角色中文名
local function _getRoleName(role)
    local def = FACTION_ROLES[role or "member"]
    return def and def.name or "成员"
end

--- 检查操作者是否有权对目标执行操作 (操作者等级必须高于目标)
local function _hasAuthorityOver(operatorRole, targetRole)
    return _getRoleLevel(operatorRole) > _getRoleLevel(targetRole)
end

--- 统计指定角色当前人数
local function _countRole(roles, roleName)
    local count = 0
    for _, r in pairs(roles or {}) do
        if r == roleName then count = count + 1 end
    end
    return count
end

-- 封禁系统常量
local BAN_LEVEL_NONE    = 0  -- 无封禁
local BAN_LEVEL_SOCIAL  = 1  -- 社交封禁(无法好友/阵营)
local BAN_LEVEL_CORE    = 2  -- 核心封禁(无法排行/竞技/抽卡)
local BAN_LEVEL_FULL    = 3  -- 全封禁(只能看不能玩)

-- 频率限制常量 (秒)
local COOLDOWN_FRIEND_REQUEST  = 30   -- 好友申请间隔
local COOLDOWN_PROFILE_PUBLISH = 300  -- 档案发布间隔(5分钟)
local COOLDOWN_SAVE_ALL        = 10   -- 全量保存间隔
local COOLDOWN_REJECTED_RETRY  = 86400 -- 被拒绝后重新申请冷却(24小时)

-- 哈希校验密钥 (混淆用, 非加密安全)
local HASH_SEED = 37829
local HASH_SECRET = 0x5F3759DF

-- 内部状态
local initialized = false
local retryCount = 0
local retryTimer = 0
local retryData = nil
local lastSyncTime = 0

-- 封禁状态
local banLevel = BAN_LEVEL_NONE  -- 当前玩家的封禁等级
local banReason = ""             -- 封禁原因
local banChecked = false         -- 是否已完成封禁检查

-- 频率限制: 各操作最后执行时间戳
local cooldownTimestamps = {}

-- 被拒绝记录: { [targetUid] = rejectTime }
local rejectedByCache = {}

-- 云端加载中标志: 防止 LoadAll 异步期间 SaveAll 覆盖云端数据
local cloudLoadPending = false
-- 云端加载期间积攒的保存请求 (LoadAll 完成后执行)
local pendingSaveCallback = nil

-- ============================================================================
-- 初始化
-- ============================================================================

---@param opts? { prefix?: string, onBanned?: fun(level: number, reason: string) }
function CloudManager.Init(opts)
    if opts and opts.prefix then
        -- 允许覆盖前缀(测试用)
    end
    initialized = true
    print("[CloudManager] 初始化完成, prefix=" .. PREFIX)

    -- 启动时先检查封禁状态 (封禁检查优先于一切)
    CloudManager.CheckBanStatus(function(level, reason)
        if level >= BAN_LEVEL_FULL then
            print("[CloudManager] 玩家被全封禁: " .. tostring(reason))
            if opts and opts.onBanned then
                opts.onBanned(level, reason)
            end
            return -- 全封禁: 不加载任何数据
        end
        if level >= BAN_LEVEL_SOCIAL then
            print("[CloudManager] 玩家被社交封禁: " .. tostring(reason))
        end
        -- 非全封禁: 正常加载好友/阵营出站信箱
        if level < BAN_LEVEL_SOCIAL then
            CloudManager._loadMyOutbox()
        end
    end)
end

-- ============================================================================
-- 数据打包: 将游戏全局变量按 domain 打包
-- ============================================================================

--- 收集指定 domain 的数据 (从全局变量读取)
---@param domain string
---@return table
function CloudManager.CollectDomainData(domain)
    local now = os.time()

    if domain == "core" then
        return {
            savedAt = now,
            saveVersion = SAVE_VERSION,
            playerInfo = {
                name = playerInfo.name, level = playerInfo.level, exp = playerInfo.exp,
                rankIdx = playerInfo.rankIdx, jade = playerInfo.jade, avatarIdx = playerInfo.avatarIdx,
                profileSet = playerInfo.profileSet, abyssTickets = playerInfo.abyssTickets,
                lingshi = playerInfo.lingshi, totalBattles = playerInfo.totalBattles,
                totalWins = playerInfo.totalWins, totalGachas = playerInfo.totalGachas,
                totalEquips = playerInfo.totalEquips, totalDecompose = playerInfo.totalDecompose,
                totalEnhance = playerInfo.totalEnhance,
                ad_free = playerInfo.ad_free or false,
                tradeData = playerInfo.tradeData,
                tradeProcessed = playerInfo.tradeProcessed,
            },
        }

    elseif domain == "heroes" then
        return {
            savedAt = now,
            playerHeroes = playerHeroes,
            heroFragments = heroFragments,
        }

    elseif domain == "equip" then
        return {
            savedAt = now,
            playerEquipment = playerEquipment,
        }

    elseif domain == "skills" then
        local ul = {}
        for i, sk in pairs(SKILL_DEFS) do
            if sk.unlocked then ul[#ul + 1] = i end
        end
        return {
            savedAt = now,
            playerEquippedSkills = playerEquippedSkills,
            unlockedSkills = ul,
            skillFragments = skillFragments,
            skillLayers = skillLayers,
        }

    elseif domain == "progress" then
        return {
            savedAt = now,
            stageMaxUnlocked = stageState.maxUnlocked,
            stageCurrentPage = stageState.currentPage,
            stageStars = stageStars,
            stageStarClaimed = stageStarClaimed,
            stageChestClaimed = stageChestClaimed,
            abyssCleared = abyssCleared,
            towerHighestFloor = towerState.highestFloor,
            towerCurrentFloor = towerState.currentFloor,
            rankedScore = rankedState.score,
            rankedWins = rankedState.wins,
            rankedLosses = rankedState.losses,
            rankedStreak = rankedState.streak,
            rankedHighestScore = rankedState.highestScore,
            gachaPity = gachaState.pityCounter,
            limitedGachaPity = gachaState.limitedPityCounter,
        }

    elseif domain == "welfare" then
        -- nil 保护: 这些全局变量可能在首次登录时尚未初始化
        local ws = rawget(_G, "welfareState") or {}
        local sw = ws.spinWheel or {}
        local cf = ws.cardFlip or {}
        local ml = ws.mail or {}
        local dds = rawget(_G, "dailyDungeonState") or {}
        local rds = rawget(_G, "resourceDungeonState") or {}
        local bps = rawget(_G, "battlePassState") or {}
        local gs = rawget(_G, "gameSettings") or {}

        return {
            savedAt = now,
            dailyTaskState = rawget(_G, "dailyTaskState") or {},
            weeklyTaskState = rawget(_G, "weeklyTaskState") or {},
            achievementClaimed = rawget(_G, "achievementClaimed") or {},
            welfareState = {
                signInClaimed = ws.signInClaimed,
                signInTimestamps = ws.signInTimestamps,
                dailySignInClaimed = ws.dailySignInClaimed,
                dailySignInTimestamps = ws.dailySignInTimestamps,
                onlineRewards = ws.onlineRewards,
                onlineTime = ws.onlineTime,

                spinWheel = {
                    lastDate = sw.lastDate,
                    freeUsed = sw.freeUsed,
                    adSpins = sw.adSpins,
                },
                cardFlip = {
                    lastDate = cf.lastDate,
                    freeUsed = cf.freeUsed,
                    adFlips = cf.adFlips,
                    cards = cf.cards,
                    flipped = cf.flipped,
                },
            },
            cdkRedeemed = rawget(_G, "cdkState") and cdkState.redeemed or {},
            mailClaimed = ml.claimed or {},
            cloudMailClaimed = CloudManager._mailClaimed or {},
            lastWeeklySettled = ws.lastWeeklySettled,
            tutorialRewardClaimed = gs.tutorialRewardClaimed or false,
            sealData = rawget(_G, "sealData"),
            sealExpItems = rawget(_G, "sealExpItems"),
            sealInventory = rawget(_G, "sealInventory"),
            sealInventoryNextId = rawget(_G, "sealInventoryNextId"),
            dailyDungeonState = {
                lastResetDay = dds.lastResetDay,
                completed = dds.completed,
                todaySlot = dds.todaySlot,
                selectedSet = dds.selectedSet,
            },
            resourceDungeonState = {
                lastResetDay = rds.lastResetDay,
                completed = rds.completed,
            },
            battlePassState = {
                seasonStartDay = bps.seasonStartDay,
                level = bps.level,
                exp = bps.exp,
                dailyProgress = bps.dailyProgress,
                weeklyProgress = bps.weeklyProgress,
                seasonProgress = bps.seasonProgress,
                dailyClaimed = bps.dailyClaimed,
                weeklyClaimed = bps.weeklyClaimed,
                seasonClaimed = bps.seasonClaimed,
                freeRewardClaimed = bps.freeRewardClaimed,
                premiumRewardClaimed = bps.premiumRewardClaimed,
                lastDailyReset = bps.lastDailyReset,
                lastWeeklyReset = bps.lastWeeklyReset,
            },
        }

    elseif domain == "social" then
        return {
            savedAt = now,
            friendIds = CloudManager._friendIds or {},
            factionId = CloudManager._factionId or 0,
            factionName = CloudManager._factionName or "",
            factionRole = CloudManager._factionRole or "none",  -- "leader" / "member" / "none"
        }

    elseif domain == "explore" then
        local exploreData = nil
        if rawget(_G, "Exploration") and Exploration.GetState then
            exploreData = Exploration.GetState()
        end
        return {
            savedAt = now,
            explorationState = exploreData,
        }
    end

    return { savedAt = now }
end

-- ============================================================================
-- 全量保存 (本地 + 云端多domain)
-- ============================================================================

--- 全量保存: 本地JSON + 云端多domain BatchSet
---@param callback? fun(success: boolean, msg: string)
---@param forceBypass? boolean 跳过频率限制(内部用)
function CloudManager.SaveAll(callback, forceBypass)
    -- 封禁检查: 全封禁禁止保存
    if banLevel >= BAN_LEVEL_FULL then
        if callback then callback(false, "账号已被封禁, 无法保存") end
        return
    end

    -- 云端加载中保护: 只保存本地, 不上传云端 (防止旧数据覆盖云端新数据)
    if cloudLoadPending then
        print("[CloudManager] 云端加载中, 仅保存本地 (防止竞态覆盖)")
        CloudManager._sanitizeResources()
        local allData = {}
        for name, _ in pairs(DOMAINS) do
            allData[name] = CloudManager.CollectDomainData(name)
        end
        CloudManager._saveLocalJSON(allData)
        -- 记录待保存回调, LoadAll 完成后会触发一次完整 SaveAll
        pendingSaveCallback = callback
        return
    end

    -- 频率限制: 防止高频保存 (但本地文件仍然保存)
    if not forceBypass and not CloudManager._checkCooldown("save_all", COOLDOWN_SAVE_ALL) then
        -- 即使被冷却阻断, 仍然保存本地文件 (防止崩溃丢失数据)
        CloudManager._sanitizeResources()
        local allData = {}
        for name, _ in pairs(DOMAINS) do
            allData[name] = CloudManager.CollectDomainData(name)
        end
        CloudManager._saveLocalJSON(allData)
        if callback then callback(false, "保存过于频繁, 仅本地保存") end
        return
    end

    -- 0. 负值防护: 关键资源不允许为负
    CloudManager._sanitizeResources()

    -- 1. 收集所有 domain 数据
    local allData = {}
    for name, _ in pairs(DOMAINS) do
        allData[name] = CloudManager.CollectDomainData(name)
    end

    -- 2. 保存本地JSON (保留完整单文件兜底)
    CloudManager._saveLocalJSON(allData)

    -- 3. 云端 BatchSet (多domain + 公开档案)
    if not rawget(_G, "clientCloud") then
        if callback then callback(true, "本地保存成功(无云端)") end
        return
    end

    -- 安全检查: 防止空数据覆盖有效存档
    local coreData = allData.core
    if coreData and coreData.playerInfo then
        local pi = coreData.playerInfo
        local weight = (pi.totalBattles or 0) + (pi.totalWins or 0)
            + (pi.rankIdx or 0) * 100 + (pi.totalGachas or 0) + (pi.totalEquips or 0)
        if weight <= 100 and not pi.profileSet then
            print("[CloudManager] 跳过云端同步: 数据权重过低(" .. tostring(weight) .. ")")
            if callback then callback(true, "本地保存成功(权重过低跳过云端)") end
            return
        end
    end

    -- 构建 BatchSet
    local batch = clientCloud:BatchSet()
    for name, key in pairs(DOMAINS) do
        batch:Set(key, allData[name])
    end

    -- 同时更新旧格式 savegame key (向下兼容)
    local legacyData = CloudManager._buildLegacyData(allData)
    batch:Set(KEYS.legacy_save, legacyData)

    -- 计算并保存存档哈希
    local hash = CloudManager._computeSaveHash(allData)
    batch:Set(KEYS.save_hash, { hash = hash, time = os.time() })

    batch:Save("CloudManager.SaveAll", {
        ok = function()
            print("[CloudManager] 云端多domain同步成功")
            retryCount = 0
            lastSyncTime = os.time()
            if callback then callback(true, "云端同步成功") end
        end,
        error = function(code, reason)
            print("[CloudManager] 云端同步失败: " .. tostring(code) .. " " .. tostring(reason))
            retryCount = retryCount + 1
            if retryCount <= 3 then
                retryTimer = 30
                retryData = allData
            end
            if callback then callback(false, tostring(reason)) end
        end,
    })

    -- 4. 发布公开档案 (异步，不阻塞保存, 有频率限制)
    CloudManager._publishProfile(allData)
end

--- 单域保存 (仅更新指定domain)
---@param domain string domain名称
---@param callback? fun(success: boolean)
function CloudManager.SaveDomain(domain, callback)
    local key = DOMAINS[domain]
    if not key then
        print("[CloudManager] 未知domain: " .. tostring(domain))
        return
    end

    local data = CloudManager.CollectDomainData(domain)

    -- 更新本地JSON (全量重写)
    CloudManager._saveLocalJSON(nil) -- 触发全量本地保存

    if not rawget(_G, "clientCloud") then
        if callback then callback(true) end
        return
    end

    clientCloud:Set(key, data, {
        ok = function()
            print("[CloudManager] domain " .. domain .. " 云端保存成功")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudManager] domain " .. domain .. " 云端保存失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

-- ============================================================================
-- 全量加载 (本地优先 + 云端对比)
-- ============================================================================

--- 全量加载: 先加载本地 -> 再对比云端取更新的
---@param callback? fun(source: string) "local" | "cloud" | "none"
function CloudManager.LoadAll(callback)
    -- 1. 加载本地
    local localData = CloudManager._loadLocalJSON()
    local localVersion = nil

    if localData then
        -- 判断是旧格式还是新格式
        if localData._multiDomain then
            -- 新格式: 按domain恢复
            localVersion = "multi"
            CloudManager._applyMultiDomain(localData)
        else
            -- 旧格式: 用原有 ApplySaveData
            localVersion = "legacy"
            if rawget(_G, "ApplySaveData") then
                ApplySaveData(localData)
            end
        end
        print("[CloudManager] 本地存档已加载, format=" .. localVersion)
    else
        print("[CloudManager] 本地无存档")
    end

    -- 2. 云端对比
    if not rawget(_G, "clientCloud") then
        if callback then callback(localData and "local" or "none") end
        return
    end

    -- 设置云端加载中标志, 防止 SaveAll 在此期间覆盖云端数据
    cloudLoadPending = true
    pendingSaveCallback = nil
    print("[CloudManager] 开始云端加载, 已锁定云端写入")

    -- BatchGet 所有 domain + 旧格式key + 哈希校验
    local batchGet = clientCloud:BatchGet()
    for _, key in pairs(DOMAINS) do
        batchGet:Key(key)
    end
    batchGet:Key(KEYS.legacy_save)
    batchGet:Key(KEYS.save_hash)

    batchGet:Fetch({
        ok = function(values, iscores)
            -- 检查云端是否有新格式数据
            local cloudHasMulti = values[DOMAINS.core] ~= nil
            local cloudHasLegacy = values[KEYS.legacy_save] ~= nil

            if not cloudHasMulti and not cloudHasLegacy then
                -- 云端无存档, 上传本地
                cloudLoadPending = false
                print("[CloudManager] 云端加载完成(无云端存档), 已解锁云端写入")
                if localData then
                    print("[CloudManager] 云端无存档, 上传本地")
                    CloudManager.SaveAll()
                end
                if callback then callback(localData and "local" or "none") end
                return
            end

            -- 获取云端时间戳
            local cloudTime = 0
            if cloudHasMulti then
                local coreData = values[DOMAINS.core]
                cloudTime = (coreData and coreData.savedAt) or 0
            elseif cloudHasLegacy then
                local legData = values[KEYS.legacy_save]
                cloudTime = (legData and legData.savedAt) or 0
            end

            -- 获取本地时间戳
            local localTime = 0
            if localData then
                if localVersion == "multi" and localData.domains and localData.domains.core then
                    localTime = localData.domains.core.savedAt or 0
                elseif localData.savedAt then
                    localTime = localData.savedAt
                end
            end

            -- 对比决策
            -- 关键数据诊断: 在决策前记录本地和云端的兵符/虎符值
            local localJade = rawget(_G, "playerInfo") and playerInfo.jade or -1
            local localSealCount = 0
            if rawget(_G, "sealData") then
                for _ in pairs(sealData) do localSealCount = localSealCount + 1 end
            end
            local cloudJade = -1
            local cloudSealCount = 0
            if cloudHasMulti and values[DOMAINS.core] and values[DOMAINS.core].playerInfo then
                cloudJade = values[DOMAINS.core].playerInfo.jade or -1
            end
            if cloudHasMulti and values[DOMAINS.welfare] and values[DOMAINS.welfare].sealData then
                for _ in pairs(values[DOMAINS.welfare].sealData) do cloudSealCount = cloudSealCount + 1 end
            end
            print(string.format("[CloudManager] 数据对比: 本地jade=%s sealCount=%d | 云端jade=%s sealCount=%d",
                tostring(localJade), localSealCount, tostring(cloudJade), cloudSealCount))

            local useCloud = false
            if not localData then
                useCloud = true
                print("[CloudManager] 本地无存档, 使用云端")
            elseif cloudTime > 0 and localTime > 0 then
                useCloud = cloudTime > localTime
                print(string.format("[CloudManager] 本地time=%d vs 云端time=%d -> %s",
                    localTime, cloudTime, useCloud and "用云端" or "用本地"))
            end

            if useCloud then
                if cloudHasMulti then
                    -- 新格式: 按domain恢复
                    local cloudDomains = {}
                    for name, key in pairs(DOMAINS) do
                        cloudDomains[name] = values[key]
                    end
                    -- 哈希校验: 验证云端存档完整性
                    local storedHashData = values[KEYS.save_hash]
                    if storedHashData and storedHashData.hash then
                        local recalcHash = CloudManager._computeSaveHash(cloudDomains)
                        if recalcHash ~= storedHashData.hash then
                            print("[CloudManager] 云端存档哈希校验失败! stored="
                                .. tostring(storedHashData.hash) .. " calc=" .. tostring(recalcHash))
                            -- 存档可能被篡改: 仍然加载但标记警告
                            CloudManager._hashMismatch = true
                        else
                            CloudManager._hashMismatch = false
                        end
                    end
                    CloudManager._applyMultiDomain({ domains = cloudDomains })
                    -- 负值防护
                    CloudManager._sanitizeResources()
                    -- 保存到本地
                    CloudManager._saveLocalJSON(nil)
                    print("[CloudManager] 已应用云端多domain存档")
                else
                    -- 旧格式
                    local legData = values[KEYS.legacy_save]
                    if rawget(_G, "ApplySaveData") then
                        ApplySaveData(legData)
                    end
                    CloudManager._saveLocalJSON(nil)
                    print("[CloudManager] 已应用云端旧格式存档")
                end
                if callback then callback("cloud") end
            else
                -- 本地更新, 同步到云端
                CloudManager.SaveAll()
                if callback then callback("local") end
            end

            -- 解锁云端写入
            cloudLoadPending = false
            print("[CloudManager] 云端加载完成, 已解锁云端写入")

            -- 如果加载期间有延迟的保存请求, 现在执行一次完整 SaveAll
            if pendingSaveCallback then
                local cb = pendingSaveCallback
                pendingSaveCallback = nil
                print("[CloudManager] 执行延迟保存请求")
                CloudManager.SaveAll(cb, true) -- forceBypass=true 跳过冷却
            end

            -- 好友/阵营信箱: 拉取出站数据 (申请池模式)
            CloudManager._loadMyOutbox()
        end,
        error = function(code, reason)
            print("[CloudManager] 云端加载失败: " .. tostring(reason))
            -- 解锁云端写入 (即使失败也要解锁, 否则永远无法保存到云端)
            cloudLoadPending = false
            print("[CloudManager] 云端加载失败, 已解锁云端写入")
            -- 执行延迟保存
            if pendingSaveCallback then
                local cb = pendingSaveCallback
                pendingSaveCallback = nil
                CloudManager.SaveAll(cb, true)
            end
            if callback then callback(localData and "local" or "none") end
        end,
    })
end

-- ============================================================================
-- 公开档案
-- ============================================================================

--- 发布公开档案 (自动从全局变量提取, 有频率限制)
function CloudManager._publishProfile(allData)
    if not rawget(_G, "clientCloud") then return end
    -- 封禁检查
    if banLevel >= BAN_LEVEL_CORE then return end
    -- 频率限制
    if not CloudManager._checkCooldown("publish_profile", COOLDOWN_PROFILE_PUBLISH) then return end

    local coreData = allData and allData.core or CloudManager.CollectDomainData("core")
    local pi = coreData.playerInfo or {}

    -- 构建轻量公开资料
    local profile = {
        heroLineup = {},
        skillLineup = {},
        mainEquipTier = 0,
        level = pi.rankIdx or 1,
        totalWins = pi.totalWins or 0,
        totalBattles = pi.totalBattles or 0,
        avatarIdx = pi.avatarIdx or 1,
        factionId = CloudManager._factionId or 0,
        factionName = CloudManager._factionName or "",
        updatedAt = os.time(),
    }

    -- 上阵武灵
    if rawget(_G, "playerHeroes") then
        for idx, hero in pairs(playerHeroes) do
            if hero.owned then
                profile.heroLineup[#profile.heroLineup + 1] = tonumber(idx) or idx
            end
        end
        -- 只保留前6个
        while #profile.heroLineup > 6 do table.remove(profile.heroLineup) end
    end

    -- 装备武技
    if rawget(_G, "playerEquippedSkills") then
        for _, skillIdx in ipairs(playerEquippedSkills) do
            profile.skillLineup[#profile.skillLineup + 1] = skillIdx
        end
    end

    -- 最高装备品阶
    if rawget(_G, "playerEquipment") and playerEquipment.owned then
        for _, item in ipairs(playerEquipment.owned) do
            if item.tier and item.tier > profile.mainEquipTier then
                profile.mainEquipTier = item.tier
            end
        end
    end

    -- 计算战力 (与现有逻辑保持一致)
    local combatPower = 0
    if rawget(_G, "CalcPlayerTotalPower") then
        combatPower = CalcPlayerTotalPower() or 0
    else
        combatPower = (pi.rankIdx or 1) * 100 + (pi.totalWins or 0) * 10
    end

    -- BatchSet: 公开资料 + 战力排行
    clientCloud:BatchSet()
        :Set(KEYS.pub_profile, profile)
        :SetInt(KEYS.combat_power, combatPower)
        :SetInt(KEYS.realm_level, pi.rankIdx or 1)
        :Save("发布公开档案")
end

--- 手动发布公开档案
function CloudManager.PublishProfile()
    CloudManager._publishProfile(nil)
end

--- 获取其他玩家的公开档案 (通过战力排行榜)
---@param start number 起始位置 (0开始)
---@param count number 获取数量
---@param callback fun(profiles: table[])
function CloudManager.GetPublicProfiles(start, count, callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end

    clientCloud:GetRankList(KEYS.combat_power, start, count, {
        ok = function(rankList)
            local profiles = {}
            local userIds = {}

            for i, item in ipairs(rankList) do
                local profile = item.score[KEYS.pub_profile] or {}
                local entry = {
                    rank = start + i,
                    userId = item.userId or item.player,
                    combatPower = (item.iscore and item.iscore[KEYS.combat_power]) or 0,
                    realmLevel = (item.iscore and item.iscore[KEYS.realm_level]) or 1,
                    profile = profile,
                    nickname = "",
                    isMe = (item.userId or item.player) == clientCloud.userId,
                }
                profiles[#profiles + 1] = entry
                userIds[#userIds + 1] = entry.userId
            end

            -- 批量查询昵称
            if #userIds > 0 and rawget(_G, "GetUserNickname") then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, entry in ipairs(profiles) do
                            entry.nickname = map[entry.userId] or "未知"
                        end
                        if callback then callback(profiles) end
                    end,
                    onError = function()
                        if callback then callback(profiles) end
                    end,
                })
            else
                if callback then callback(profiles) end
            end
        end,
        error = function(code, reason)
            print("[CloudManager] 获取排行榜失败: " .. tostring(reason))
            if callback then callback({}) end
        end,
    }, KEYS.pub_profile, KEYS.realm_level)
end

-- ============================================================================
-- 好友系统 (公共申请池模型 — 安全版)
-- 核心: 排行榜做公共信箱, 每人只写自己数据, 永不写别人存档
-- ============================================================================

CloudManager._friendIds = {}           -- 已确认好友 { userId1, userId2, ... }
CloudManager._outgoingRequests = {}    -- 本地缓存: 我发出的申请 { [toUid]={time=ts}, ... }
CloudManager._outgoingResponses = {}   -- 本地缓存: 我的回复 { [toUid]={accepted=bool, time=ts}, ... }

-- ── 工具: 过期清理 ──

local function _purgeExpired(tbl)
    local now = os.time()
    local removed = 0
    for uid, entry in pairs(tbl) do
        if entry.time and (now - entry.time) > REQUEST_EXPIRE_SECONDS then
            tbl[uid] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function _tableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ── 初始化时从云端拉取自己的出站信箱 ──

function CloudManager._loadMyOutbox(callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback() end
        return
    end
    clientCloud:BatchGet()
        :Key(KEYS.freq_outbox)
        :Key(KEYS.freq_resp)
        :Key(KEYS.camp_apply)
        :Key(KEYS.camp_resp)
        :Key(KEYS.camp_meta)
        :Fetch({
            ok = function(values, _)
                -- 好友出站
                if values[KEYS.freq_outbox] then
                    CloudManager._outgoingRequests = values[KEYS.freq_outbox] or {}
                    _purgeExpired(CloudManager._outgoingRequests)
                end
                if values[KEYS.freq_resp] then
                    CloudManager._outgoingResponses = values[KEYS.freq_resp] or {}
                    _purgeExpired(CloudManager._outgoingResponses)
                end
                -- 阵营出站
                if values[KEYS.camp_apply] and type(values[KEYS.camp_apply]) == "table"
                   and values[KEYS.camp_apply].campId then
                    CloudManager._campOutApply = values[KEYS.camp_apply]
                end
                if values[KEYS.camp_resp] and type(values[KEYS.camp_resp]) == "table" then
                    CloudManager._campOutResp = values[KEYS.camp_resp]
                end
                -- 盟主阵营元数据
                if values[KEYS.camp_meta] and type(values[KEYS.camp_meta]) == "table"
                   and values[KEYS.camp_meta].id then
                    CloudManager._factionMeta = values[KEYS.camp_meta]
                end
                print("[社交] 出站信箱已加载: 好友申请=" .. _tableCount(CloudManager._outgoingRequests)
                    .. " 好友回复=" .. _tableCount(CloudManager._outgoingResponses)
                    .. " 阵营申请=" .. (CloudManager._campOutApply and "有" or "无"))
                -- 阵营继位检测: 如果有阵营归属, 自动检查是否发生了盟主转让
                if CloudManager._factionId ~= 0 then
                    CloudManager._refreshFactionStatus()
                end
                if callback then callback() end
            end,
            error = function(_, reason)
                print("[社交] 加载出站信箱失败: " .. tostring(reason))
                if callback then callback() end
            end,
        })
end

-- ── 发布自己的出站信箱到排行榜 ──

function CloudManager._publishOutbox()
    if not rawget(_G, "clientCloud") then return end
    _purgeExpired(CloudManager._outgoingRequests)
    clientCloud:BatchSet()
        :SetInt(KEYS.freq_outbox_ts, os.time())
        :Set(KEYS.freq_outbox, CloudManager._outgoingRequests)
        :Save("发布好友申请出站")
end

function CloudManager._publishResponses()
    if not rawget(_G, "clientCloud") then return end
    _purgeExpired(CloudManager._outgoingResponses)
    clientCloud:BatchSet()
        :SetInt(KEYS.freq_resp_ts, os.time())
        :Set(KEYS.freq_resp, CloudManager._outgoingResponses)
        :Save("发布好友回复")
end

-- ── 发送好友申请 ──

--- 向目标玩家发送好友申请 (写入自己的出站信箱)
---@param targetUserId number
---@param message? string 申请留言
---@return boolean success
---@return string? reason
function CloudManager.SendFriendRequest(targetUserId, message)
    -- 封禁检查: 社交封禁及以上禁止
    if banLevel >= BAN_LEVEL_SOCIAL then
        return false, "社交功能已被限制"
    end
    if not targetUserId or targetUserId == 0 then
        return false, "无效的用户ID"
    end
    local myUid = rawget(_G, "clientCloud") and clientCloud.userId or 0
    if targetUserId == myUid then
        return false, "不能添加自己"
    end
    -- 频率限制
    if not CloudManager._checkCooldown("friend_request", COOLDOWN_FRIEND_REQUEST) then
        return false, "操作过于频繁, 请" .. COOLDOWN_FRIEND_REQUEST .. "秒后再试"
    end
    -- 已是好友
    if CloudManager.IsFriend(targetUserId) then
        return false, "已是好友"
    end
    -- 已有待处理申请 (7天内防重复)
    local uidKey = tostring(targetUserId)
    if CloudManager._outgoingRequests[uidKey] then
        return false, "已发送过申请, 等待对方回应"
    end
    -- 被拒绝冷却: 24小时内不能重复申请同一人
    local rejectTime = rejectedByCache[uidKey]
    if rejectTime and (os.time() - rejectTime) < COOLDOWN_REJECTED_RETRY then
        local remaining = COOLDOWN_REJECTED_RETRY - (os.time() - rejectTime)
        local hours = math.ceil(remaining / 3600)
        return false, "对方曾拒绝你的申请, " .. hours .. "小时后可重试"
    end
    -- 出站上限
    if _tableCount(CloudManager._outgoingRequests) >= MAX_OUTBOX then
        _purgeExpired(CloudManager._outgoingRequests)
        if _tableCount(CloudManager._outgoingRequests) >= MAX_OUTBOX then
            return false, "待处理申请过多, 请等待回应或清理"
        end
    end

    CloudManager._outgoingRequests[uidKey] = {
        time = os.time(),
        msg = message or "",
    }
    CloudManager._publishOutbox()
    print("[好友] 已发送申请给 " .. uidKey)
    return true
end

-- ── 拉取发给我的好友申请 (扫描所有人的出站信箱) ──

--- 检查收到的好友申请
---@param callback fun(requests: table[]) {fromUid, time, msg, nickname}
function CloudManager.CheckIncomingRequests(callback)
    if banLevel >= BAN_LEVEL_SOCIAL then
        if callback then callback({}) end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end
    local myUid = clientCloud.userId

    -- 扫描 freq_outbox_ts 排行榜 (按最近更新排序, 拉200人)
    clientCloud:GetRankList(KEYS.freq_outbox_ts, 0, 200, {
        ok = function(rankList)
            local incoming = {}
            local senderIds = {}
            local myUidStr = tostring(myUid)

            for _, item in ipairs(rankList) do
                local senderId = item.userId or item.player
                if senderId ~= myUid then
                    local outbox = item.score[KEYS.freq_outbox]
                    if type(outbox) == "table" and outbox[myUidStr] then
                        local req = outbox[myUidStr]
                        -- 检查过期
                        if req.time and (os.time() - req.time) <= REQUEST_EXPIRE_SECONDS then
                            -- 排除已是好友 & 已回复的
                            if not CloudManager.IsFriend(senderId)
                               and not CloudManager._outgoingResponses[tostring(senderId)] then
                                table.insert(incoming, {
                                    fromUid = senderId,
                                    time = req.time,
                                    msg = req.msg or "",
                                    nickname = "",
                                })
                                table.insert(senderIds, senderId)
                            end
                        end
                    end
                end
            end

            -- 批量查昵称
            if #senderIds > 0 and rawget(_G, "GetUserNickname") then
                GetUserNickname({
                    userIds = senderIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, r in ipairs(incoming) do
                            r.nickname = map[r.fromUid] or "未知"
                        end
                        if callback then callback(incoming) end
                    end,
                    onError = function()
                        if callback then callback(incoming) end
                    end,
                })
            else
                if callback then callback(incoming) end
            end
        end,
        error = function(_, reason)
            print("[好友] 扫描入站申请失败: " .. tostring(reason))
            if callback then callback({}) end
        end,
    }, KEYS.freq_outbox)
end

-- ── 同意好友申请 ──

--- 同意来自 fromUserId 的好友申请
---@param fromUserId number
---@return boolean
function CloudManager.AcceptFriendRequest(fromUserId)
    if banLevel >= BAN_LEVEL_SOCIAL then return false end
    if not fromUserId or fromUserId == 0 then return false end
    if CloudManager.IsFriend(fromUserId) then return false end
    if #CloudManager._friendIds >= MAX_FRIENDS then
        print("[好友] 好友数已满 " .. MAX_FRIENDS)
        return false
    end

    -- 1. 加入自己好友列表
    table.insert(CloudManager._friendIds, fromUserId)

    -- 2. 发布回复到自己的 resp 信箱 (对方下次登录会扫到)
    CloudManager._outgoingResponses[tostring(fromUserId)] = {
        accepted = true,
        time = os.time(),
    }
    CloudManager._publishResponses()
    CloudManager._syncSocialDomain()

    print("[好友] 已同意 " .. tostring(fromUserId) .. " 的申请, 当前好友 " .. #CloudManager._friendIds .. " 人")
    return true
end

--- 拒绝来自 fromUserId 的好友申请 (仅标记, 不加好友)
---@param fromUserId number
function CloudManager.RejectFriendRequest(fromUserId)
    if not fromUserId or fromUserId == 0 then return end
    CloudManager._outgoingResponses[tostring(fromUserId)] = {
        accepted = false,
        time = os.time(),
    }
    CloudManager._publishResponses()
    print("[好友] 已拒绝 " .. tostring(fromUserId) .. " 的申请")
end

-- ── 检查我发出的申请的回复 (自动完成双向加好友) ──

--- 检查我发出的申请是否被对方回复, 自动完成互加
---@param callback? fun(results: table[]) {toUid, accepted, nickname}
function CloudManager.CheckMyRequestResponses(callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end
    local myUid = clientCloud.userId
    local myUidStr = tostring(myUid)

    -- 我有哪些待处理的出站申请?
    local pendingUids = {}
    for uidStr, _ in pairs(CloudManager._outgoingRequests) do
        table.insert(pendingUids, tonumber(uidStr))
    end
    if #pendingUids == 0 then
        if callback then callback({}) end
        return
    end

    -- 扫描 freq_resp_ts 排行榜, 找对方的回复
    clientCloud:GetRankList(KEYS.freq_resp_ts, 0, 200, {
        ok = function(rankList)
            local results = {}
            local completedUids = {}

            for _, item in ipairs(rankList) do
                local responder = item.userId or item.player
                local respData = item.score[KEYS.freq_resp]
                if type(respData) == "table" and respData[myUidStr] then
                    local resp = respData[myUidStr]
                    if resp.accepted then
                        -- 对方同意了! 加入我的好友列表
                        if not CloudManager.IsFriend(responder)
                           and #CloudManager._friendIds < MAX_FRIENDS then
                            table.insert(CloudManager._friendIds, responder)
                            table.insert(completedUids, responder)
                        end
                    else
                        -- 对方拒绝了, 记录到被拒缓存 (24h冷却)
                        rejectedByCache[tostring(responder)] = os.time()
                    end
                    table.insert(results, {
                        toUid = responder,
                        accepted = resp.accepted or false,
                    })
                    -- 从出站信箱移除已处理的
                    CloudManager._outgoingRequests[tostring(responder)] = nil
                end
            end

            -- 如果有新增好友, 同步
            if #completedUids > 0 then
                CloudManager._publishOutbox()  -- 更新出站 (移除已处理)
                CloudManager._syncSocialDomain()
                print("[好友] 自动互加完成: +" .. #completedUids .. " 人")
            end

            if callback then callback(results) end
        end,
        error = function(_, reason)
            print("[好友] 扫描回复失败: " .. tostring(reason))
            if callback then callback({}) end
        end,
    }, KEYS.freq_resp)
end

-- ── 随机推荐玩家 ──

--- 从战力排行榜随机抽取 count 个玩家 (排除自己和已有好友)
---@param count number
---@param callback fun(players: table[])
function CloudManager.GetRandomPlayers(count, callback)
    count = count or 10
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end

    -- 先获取排行榜总人数
    clientCloud:GetRankTotal(KEYS.combat_power, {
        ok = function(total)
            if total <= 0 then
                if callback then callback({}) end
                return
            end
            -- 随机偏移, 拉 count*3 条 (留余量过滤)
            local fetchCount = math.min(total, count * 3, 200)
            local maxStart = math.max(0, total - fetchCount)
            local startPos = math.random(0, maxStart)

            CloudManager.GetPublicProfiles(startPos, fetchCount, function(profiles)
                -- 过滤自己、好友、3天未在线
                local myUid = clientCloud.userId
                local now = os.time()
                local friendSet = {}
                for _, fid in ipairs(CloudManager._friendIds) do friendSet[fid] = true end

                local candidates = {}
                for _, p in ipairs(profiles) do
                    if p.userId ~= myUid and not friendSet[p.userId] then
                        local updatedAt = (p.profile and p.profile.updatedAt) or 0
                        if updatedAt > 0 and (now - updatedAt) <= 3 * 86400 then
                            table.insert(candidates, p)
                        end
                    end
                end

                -- 随机打乱 & 截取
                for i = #candidates, 2, -1 do
                    local j = math.random(1, i)
                    candidates[i], candidates[j] = candidates[j], candidates[i]
                end
                local result = {}
                for i = 1, math.min(count, #candidates) do
                    result[i] = candidates[i]
                end
                if callback then callback(result) end
            end)
        end,
        error = function()
            if callback then callback({}) end
        end,
    })
end

--- 搜索玩家 (按userId精确匹配)
---@param targetUserId number
---@param callback fun(player: table|nil)
function CloudManager.SearchPlayer(targetUserId, callback)
    if not rawget(_G, "clientCloud") or not targetUserId then
        if callback then callback(nil) end
        return
    end

    -- 通过 GetUserRank 查找
    clientCloud:GetUserRank(targetUserId, KEYS.combat_power, {
        ok = function(rank, scoreValue)
            if not rank then
                if callback then callback(nil) end
                return
            end
            -- 找到了, 拉取详细资料 (从排行榜偏移)
            local startPos = math.max(0, rank - 1)
            CloudManager.GetPublicProfiles(startPos, 1, function(profiles)
                local found = nil
                for _, p in ipairs(profiles) do
                    if p.userId == targetUserId then
                        found = p
                        break
                    end
                end
                if callback then callback(found) end
            end)
        end,
        error = function()
            if callback then callback(nil) end
        end,
    })
end

-- ── 好友管理 ──

--- 移除好友
---@param userId number
---@return boolean
function CloudManager.RemoveFriend(userId)
    for i, id in ipairs(CloudManager._friendIds) do
        if id == userId then
            table.remove(CloudManager._friendIds, i)
            CloudManager._syncSocialDomain()
            print("[好友] 移除好友: " .. tostring(userId))
            return true
        end
    end
    return false
end

--- 获取好友ID列表
---@return number[]
function CloudManager.GetFriendIds()
    return CloudManager._friendIds
end

-- ============================================================================
-- 阵营养成系统 (升级 / 捐献 / 公告)
-- ============================================================================

-- 阵营等级经验表: 升到该等级所需的累计经验
-- 公式: Lv N → 成员上限 (10+10N), 每人捐 N×10000, 单级需 (10+10N)×N×10000
local FACTION_LEVEL_EXP = {
    [1]  = 0,          -- 起始
    [2]  = 200000,     -- 20人×1w = 20w
    [3]  = 800000,     -- +30人×2w = +60w
    [4]  = 2000000,    -- +40人×3w = +120w
    [5]  = 4000000,    -- +50人×4w = +200w
    [6]  = 7000000,    -- +60人×5w = +300w
    [7]  = 11200000,   -- +70人×6w = +420w
    [8]  = 16800000,   -- +80人×7w = +560w
    [9]  = 24000000,   -- +90人×8w = +720w
    [10] = 33000000,   -- +100人×9w = +900w
}
-- 阵营每级成员上限: Lv N → 10 + 10×N
local FACTION_LEVEL_MAX_MEMBERS = {
    [1]  = 20,  [2]  = 30,  [3]  = 40,  [4]  = 50,  [5]  = 60,
    [6]  = 70,  [7]  = 80,  [8]  = 90,  [9]  = 100, [10] = 100,
}
local FACTION_MAX_LEVEL = 10
local FACTION_DONATE_MIN = 100         -- 单次最少捐献

-- 职位额外加成系数 (每阵营等级额外+x%战力, 盟主最高, 成员无额外)
local ROLE_BUFF_PER_LEVEL = {
    leader      = 0.6,
    vice_leader = 0.5,
    strategist  = 0.4,
    vanguard    = 0.3,
    diplomat    = 0.2,
    elite       = 0.1,
    member      = 0,
}

--- 获取阵营等级信息
---@return table { level, exp, nextExp, maxLevel, buffPercent, roleBonusPercent, totalBuffPercent }
function CloudManager.GetFactionLevelInfo()
    local meta = CloudManager._factionMeta
    local lv = (meta and meta.level) or 1
    local exp = (meta and meta.exp) or 0
    if lv < 1 then lv = 1 end
    if lv > FACTION_MAX_LEVEL then lv = FACTION_MAX_LEVEL end
    local nextExp = FACTION_LEVEL_EXP[lv + 1] or FACTION_LEVEL_EXP[FACTION_MAX_LEVEL]
    local curNeed = FACTION_LEVEL_EXP[lv] or 0
    local baseBuff = lv * 2  -- 每级+2%战力加成(全员)
    local role = CloudManager._factionRole or "member"
    local roleCoeff = ROLE_BUFF_PER_LEVEL[role] or 0
    local roleBonus = lv * roleCoeff  -- 职位额外加成
    return {
        level = lv,
        exp = exp,
        curLevelExp = curNeed,
        nextLevelExp = nextExp,
        maxLevel = FACTION_MAX_LEVEL,
        buffPercent = baseBuff,          -- 全员基础加成%
        roleBonusPercent = roleBonus,    -- 职位额外加成%
        totalBuffPercent = baseBuff + roleBonus,  -- 总加成%
        maxMembers = FACTION_LEVEL_MAX_MEMBERS[lv] or 20,
    }
end

--- 获取当日个人已捐献额度 (本地追踪)
---@return number
function CloudManager.GetTodayDonation()
    local meta = CloudManager._factionMeta
    if not meta then return 0 end
    local myUid = rawget(_G, "clientCloud") and clientCloud.userId or 0
    local uidStr = tostring(myUid)
    local today = os.date("%Y%m%d")
    if not meta.donateDaily then return 0 end
    if not meta.donateDaily[uidStr] then return 0 end
    if meta.donateDaily[uidStr].day ~= today then return 0 end
    return meta.donateDaily[uidStr].amount or 0
end

--- 捐献虎符给阵营
---@param amount number 捐献数量
---@param callback? fun(success: boolean, reason: string)
function CloudManager.DonateFaction(amount, callback)
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end
    amount = math.floor(amount)
    if amount < FACTION_DONATE_MIN then
        if callback then callback(false, "最少捐献" .. FACTION_DONATE_MIN .. "虎符") end
        return
    end
    if not rawget(_G, "playerInfo") or (playerInfo.jade or 0) < amount then
        if callback then callback(false, "虎符不足") end
        return
    end

    local myUid = clientCloud.userId or 0
    local uidStr = tostring(myUid)
    local today = os.date("%Y%m%d")

    -- 检查每日限额
    if not meta.donateDaily then meta.donateDaily = {} end
    if not meta.donateDaily[uidStr] then meta.donateDaily[uidStr] = { day = today, amount = 0 } end
    if meta.donateDaily[uidStr].day ~= today then
        meta.donateDaily[uidStr] = { day = today, amount = 0 }
    end
    local todayDone = meta.donateDaily[uidStr].amount or 0

    -- 扣虎符
    playerInfo.jade = playerInfo.jade - amount

    -- 更新 meta
    meta.exp = (meta.exp or 0) + amount
    meta.funds = (meta.funds or 0) + amount
    meta.donateDaily[uidStr].amount = todayDone + amount

    -- 个人累计贡献
    if not meta.contributions then meta.contributions = {} end
    meta.contributions[uidStr] = (meta.contributions[uidStr] or 0) + amount

    -- 检查升级
    local oldLevel = meta.level or 1
    local newLevel = oldLevel
    for lv = oldLevel + 1, FACTION_MAX_LEVEL do
        if meta.exp >= (FACTION_LEVEL_EXP[lv] or 999999999) then
            newLevel = lv
        else
            break
        end
    end
    local leveled = newLevel > oldLevel
    meta.level = newLevel
    -- 升级后更新成员上限
    if leveled then
        meta.maxMembers = FACTION_LEVEL_MAX_MEMBERS[newLevel] or meta.maxMembers
    end

    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("阵营捐献", {
            ok = function()
                print("[阵营] 捐献成功: " .. amount .. "虎符, 经验=" .. meta.exp .. ", 等级=" .. meta.level)
                -- 上报阵营等级到排行榜 (等级*1000000+经验, 等级优先)
                local rankScore = meta.level * 1000000 + math.min(meta.exp, 999999)
                local rankKey = (rawget(_G, "PROJECT_PREFIX") or "p_49dd_") .. "faction_level"
                clientCloud:SetInt(rankKey, rankScore, {})
                if rawget(_G, "SaveGameProgress") then SaveGameProgress() end
                if callback then callback(true, leveled and ("阵营升级到Lv." .. newLevel .. "!") or nil) end
            end,
            error = function(_, reason)
                -- 回滚
                playerInfo.jade = playerInfo.jade + amount
                meta.exp = meta.exp - amount
                meta.funds = meta.funds - amount
                meta.donateDaily[uidStr].amount = todayDone
                meta.contributions[uidStr] = (meta.contributions[uidStr] or 0) - amount
                meta.level = oldLevel
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

--- 检查今日是否已签到
---@return boolean
function CloudManager.HasSignedInToday()
    local meta = CloudManager._factionMeta
    if not meta then return false end
    local myUid = rawget(_G, "clientCloud") and clientCloud.userId or 0
    local uidStr = tostring(myUid)
    local today = os.date("%Y%m%d")
    if not meta.donateDaily then return false end
    if not meta.donateDaily[uidStr] then return false end
    return meta.donateDaily[uidStr].day == today and meta.donateDaily[uidStr].signedIn == true
end

--- 阵营签到 (每日免费捐献500经验，不消耗虎符)
---@param callback? fun(success: boolean, reason: string)
function CloudManager.FactionSignIn(callback)
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    local myUid = clientCloud.userId or 0
    local uidStr = tostring(myUid)
    local today = os.date("%Y%m%d")
    local signInAmount = 500

    -- 初始化每日记录
    if not meta.donateDaily then meta.donateDaily = {} end
    if not meta.donateDaily[uidStr] then meta.donateDaily[uidStr] = { day = today, amount = 0 } end
    if meta.donateDaily[uidStr].day ~= today then
        meta.donateDaily[uidStr] = { day = today, amount = 0 }
    end

    -- 检查是否已签到
    if meta.donateDaily[uidStr].signedIn then
        if callback then callback(false, "今日已签到") end
        return
    end

    -- 更新 meta (不扣虎符)
    meta.exp = (meta.exp or 0) + signInAmount
    meta.funds = (meta.funds or 0) + signInAmount
    meta.donateDaily[uidStr].signedIn = true
    meta.donateDaily[uidStr].amount = (meta.donateDaily[uidStr].amount or 0) + signInAmount

    -- 个人累计贡献
    if not meta.contributions then meta.contributions = {} end
    meta.contributions[uidStr] = (meta.contributions[uidStr] or 0) + signInAmount

    -- 检查升级
    local oldLevel = meta.level or 1
    local newLevel = oldLevel
    for lv = oldLevel + 1, FACTION_MAX_LEVEL do
        if meta.exp >= (FACTION_LEVEL_EXP[lv] or 999999999) then
            newLevel = lv
        else
            break
        end
    end
    local leveled = newLevel > oldLevel
    meta.level = newLevel
    if leveled then
        meta.maxMembers = FACTION_LEVEL_MAX_MEMBERS[newLevel] or meta.maxMembers
    end

    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("阵营签到", {
            ok = function()
                print("[阵营] 签到成功: +" .. signInAmount .. " 经验")
                local rankScore = meta.level * 1000000 + math.min(meta.exp, 999999)
                local rankKey = (rawget(_G, "PROJECT_PREFIX") or "p_49dd_") .. "faction_level"
                clientCloud:SetInt(rankKey, rankScore, {})
                if rawget(_G, "SaveGameProgress") then SaveGameProgress() end
                if callback then callback(true, leveled and ("阵营升级到Lv." .. newLevel .. "!") or nil) end
            end,
            error = function(_, reason)
                -- 回滚
                meta.exp = meta.exp - signInAmount
                meta.funds = meta.funds - signInAmount
                meta.donateDaily[uidStr].signedIn = false
                meta.donateDaily[uidStr].amount = meta.donateDaily[uidStr].amount - signInAmount
                meta.contributions[uidStr] = (meta.contributions[uidStr] or 0) - signInAmount
                meta.level = oldLevel
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

--- 获取阵营成员贡献排行 (从meta.contributions排序)
---@return table[] { uid, amount, name }
function CloudManager.GetContributionRank()
    local meta = CloudManager._factionMeta
    if not meta or not meta.contributions then return {} end
    local list = {}
    for uid, amt in pairs(meta.contributions) do
        table.insert(list, { uid = tonumber(uid) or 0, amount = amt })
    end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    return list
end

--- 设置阵营公告 (盟主/副盟主)
---@param text string 公告内容
---@param callback? fun(success: boolean, reason: string)
function CloudManager.SetFactionAnnouncement(text, callback)
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end
    local myRole = CloudManager._factionRole
    if _getRoleLevel(myRole) < _getRoleLevel("vice_leader") then
        if callback then callback(false, "副盟主及以上才能设置公告") end
        return
    end
    if text and #text > 200 then
        if callback then callback(false, "公告最多200字") end
        return
    end

    local oldAnn = meta.announcement
    meta.announcement = text or ""

    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("设置公告", {
            ok = function()
                print("[阵营] 公告已更新")
                if callback then callback(true, nil) end
            end,
            error = function(_, reason)
                meta.announcement = oldAnn
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

--- 获取个人累计贡献
---@return number
function CloudManager.GetMyContribution()
    local meta = CloudManager._factionMeta
    if not meta or not meta.contributions then return 0 end
    local myUid = rawget(_G, "clientCloud") and clientCloud.userId or 0
    return meta.contributions[tostring(myUid)] or 0
end

--- 获取阵营公告
---@return string
function CloudManager.GetFactionAnnouncement()
    local meta = CloudManager._factionMeta
    if not meta then return "" end
    return meta.announcement or ""
end

--- 获取阵营资金总额
---@return number
function CloudManager.GetFactionFunds()
    local meta = CloudManager._factionMeta
    if not meta then return 0 end
    return meta.funds or 0
end

--- 获取捐献配置常量
---@return table { minAmount: number }
function CloudManager.GetDonateConfig()
    return { minAmount = FACTION_DONATE_MIN }
end

--- 获取好友档案列表 (通过排行榜匹配)
---@param callback fun(friends: table[])
function CloudManager.GetFriendProfiles(callback)
    if #CloudManager._friendIds == 0 then
        if callback then callback({}) end
        return
    end
    CloudManager.GetPublicProfiles(0, 100, function(profiles)
        local friendSet = {}
        for _, id in ipairs(CloudManager._friendIds) do friendSet[id] = true end
        local friends = {}
        for _, p in ipairs(profiles) do
            if friendSet[p.userId] then
                friends[#friends + 1] = p
            end
        end
        if callback then callback(friends) end
    end)
end

--- 是否是好友
---@param userId number
---@return boolean
function CloudManager.IsFriend(userId)
    for _, id in ipairs(CloudManager._friendIds) do
        if id == userId then return true end
    end
    return false
end

--- 同步社交域到云端 (好友列表 + 阵营归属)
function CloudManager._syncSocialDomain()
    if not rawget(_G, "clientCloud") then return end
    local data = CloudManager.CollectDomainData("social")
    clientCloud:Set(DOMAINS.social, data, {
        ok = function()
            print("[社交] social域已同步")
        end,
    })
end

-- ============================================================================
-- 阵营系统 (公共申请池模型 — 安全版)
-- 核心: 盟主通过排行榜发布阵营, 申请者通过排行榜提交, 盟主审批后更新成员表
-- 角色体系: leader(盟主) > vice_leader(副盟主) > member(成员)
-- 继承链: 盟主退出 → 副盟主继位 → 最早成员继位 → 最后一人退出=解散
-- ============================================================================

CloudManager._factionId = 0
CloudManager._factionName = ""
CloudManager._factionRole = "none"  -- "leader" / "vice_leader" / "member" / "none"
CloudManager._factionMeta = nil     -- 阵营元数据 (盟主维护, 含 roles 字段)
CloudManager._campOutApply = nil    -- 本地缓存: 我的入营申请
CloudManager._campOutResp = {}      -- 本地缓存: 盟主的审批回复

-- ── 创建阵营 ──

--- 创建阵营 (消耗虎符, 先扣再建)
---@param name string
---@param desc string
---@param callback? fun(success: boolean, reason: string)
function CloudManager.CreateFaction(name, desc, callback)
    -- 封禁检查
    if banLevel >= BAN_LEVEL_SOCIAL then
        if callback then callback(false, "社交功能已被限制") end
        return
    end
    if CloudManager._factionId ~= 0 then
        if callback then callback(false, "已有阵营, 请先离开") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end
    -- 检查虎符
    if not rawget(_G, "playerInfo") or (playerInfo.jade or 0) < CAMP_CREATE_COST then
        if callback then callback(false, "虎符不足(需要" .. CAMP_CREATE_COST .. ")") end
        return
    end

    local uid = clientCloud.userId or 0
    local ts = os.time()
    -- 生成唯一阵营ID: 时间戳后6位 * 10000 + uid后4位
    local campId = (ts % 1000000) * 10000 + (uid % 10000)

    -- 1. 先扣虎符 (写入自己存档)
    playerInfo.jade = playerInfo.jade - CAMP_CREATE_COST

    local uidStr = tostring(uid)
    local meta = {
        id = campId,
        name = name,
        desc = desc or "",
        leaderId = uid,
        createdAt = ts,
        maxMembers = MAX_CAMP_MEMBERS,
        members = { uid },  -- 盟主自己是首个成员
        memberCount = 1,
        roles = { [uidStr] = "leader" },  -- 角色映射: uid→角色
    }

    CloudManager._factionId = campId
    CloudManager._factionName = name
    CloudManager._factionRole = "leader"
    CloudManager._factionMeta = meta

    -- 2. 发布到排行榜 (camp_leader_ts + camp_meta)
    clientCloud:BatchSet()
        :SetInt(KEYS.camp_leader_ts, ts)
        :Set(KEYS.camp_meta, meta)
        :Save("创建阵营", {
            ok = function()
                print("[阵营] 创建成功: " .. name .. " (ID=" .. campId .. "), 盟主, 消耗" .. CAMP_CREATE_COST .. "虎符")
                CloudManager._syncSocialDomain()
                CloudManager.PublishProfile()
                if callback then callback(true, "创建成功") end
            end,
            error = function(_, reason)
                -- 回滚虎符
                playerInfo.jade = playerInfo.jade + CAMP_CREATE_COST
                CloudManager._factionId = 0
                CloudManager._factionName = ""
                CloudManager._factionRole = "none"
                CloudManager._factionMeta = nil
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

-- ── 列出所有阵营 ──

--- 列出阵营列表 (从 camp_leader_ts 排行榜, 按campId去重保留最新)
---@param callback fun(factions: table[])
function CloudManager.ListFactions(callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end

    clientCloud:GetRankList(KEYS.camp_leader_ts, 0, 100, {
        ok = function(rankList)
            -- 按 campId 去重: 盟主转让后可能存在新旧两条, 保留排行靠前(时间戳更大)的
            local campMap = {}  -- campId → faction entry
            local campOrder = {} -- 保持顺序

            for _, item in ipairs(rankList) do
                local meta = item.score[KEYS.camp_meta]
                if type(meta) == "table" and meta.id then
                    local cid = meta.id
                    local ts = (item.iscore and item.iscore[KEYS.camp_leader_ts]) or 0
                    if not campMap[cid] or ts > (campMap[cid]._ts or 0) then
                        if not campMap[cid] then
                            table.insert(campOrder, cid)
                        end
                        campMap[cid] = {
                            _ts = ts,
                            campId = cid,
                            name = meta.name or "未命名",
                            desc = meta.desc or "",
                            leaderId = meta.leaderId or (item.userId or item.player),
                            leaderNickname = "",
                            createdAt = meta.createdAt or 0,
                            maxMembers = meta.maxMembers or MAX_CAMP_MEMBERS,
                            memberCount = meta.memberCount or 0,
                            members = meta.members or {},
                            roles = meta.roles or {},
                            level = meta.level or 1,
                            exp = meta.exp or 0,
                        }
                    end
                end
            end

            -- 转为有序列表
            local factions = {}
            local leaderIds = {}
            for _, cid in ipairs(campOrder) do
                local f = campMap[cid]
                f._ts = nil  -- 清除内部字段
                table.insert(factions, f)
                table.insert(leaderIds, f.leaderId)
            end

            -- 批量查昵称
            if #leaderIds > 0 and rawget(_G, "GetUserNickname") then
                GetUserNickname({
                    userIds = leaderIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do map[info.userId] = info.nickname or "" end
                        for _, f in ipairs(factions) do f.leaderNickname = map[f.leaderId] or "未知" end
                        if callback then callback(factions) end
                    end,
                    onError = function() if callback then callback(factions) end end,
                })
            else
                if callback then callback(factions) end
            end
        end,
        error = function(_, reason)
            print("[阵营] 列出阵营失败: " .. tostring(reason))
            if callback then callback({}) end
        end,
    }, KEYS.camp_meta)
end

-- ── 申请加入阵营 ──

--- 申请加入指定阵营
---@param campId number
---@param campName string
---@param callback? fun(success: boolean, reason: string)
function CloudManager.ApplyToFaction(campId, campName, callback)
    -- 封禁检查
    if banLevel >= BAN_LEVEL_SOCIAL then
        if callback then callback(false, "社交功能已被限制") end
        return
    end
    if CloudManager._factionId ~= 0 then
        if callback then callback(false, "已有阵营, 请先离开") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    local apply = {
        campId = campId,
        campName = campName or "",
        time = os.time(),
    }
    CloudManager._campOutApply = apply

    clientCloud:BatchSet()
        :SetInt(KEYS.camp_apply_ts, os.time())
        :Set(KEYS.camp_apply, apply)
        :Save("申请加入阵营", {
            ok = function()
                print("[阵营] 已提交申请: " .. (campName or "") .. " (ID=" .. campId .. ")")
                if callback then callback(true, "申请已提交") end
            end,
            error = function(_, reason)
                CloudManager._campOutApply = nil
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

-- ── 盟主审批 ──

--- 盟主/副盟主查看阵营申请 (扫描 camp_apply_ts 排行榜)
---@param callback fun(applications: table[])
function CloudManager.CheckFactionApplications(callback)
    -- 副盟主及以上可审批 (level >= 5)
    if _getRoleLevel(CloudManager._factionRole) < _getRoleLevel("vice_leader")
       or CloudManager._factionId == 0 then
        if callback then callback({}) end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end
    local myCampId = CloudManager._factionId

    clientCloud:GetRankList(KEYS.camp_apply_ts, 0, 200, {
        ok = function(rankList)
            local applications = {}
            local applicantIds = {}

            for _, item in ipairs(rankList) do
                local applyData = item.score[KEYS.camp_apply]
                if type(applyData) == "table" and applyData.campId == myCampId then
                    local applicantId = item.userId or item.player
                    -- 排除过期 & 已在成员列表中
                    if applyData.time and (os.time() - applyData.time) <= REQUEST_EXPIRE_SECONDS then
                        local alreadyMember = false
                        if CloudManager._factionMeta and CloudManager._factionMeta.members then
                            for _, mid in ipairs(CloudManager._factionMeta.members) do
                                if mid == applicantId then alreadyMember = true; break end
                            end
                        end
                        -- 排除已回复拒绝/同意的
                        local alreadyResp = CloudManager._campOutResp[tostring(applicantId)]
                        if not alreadyMember and not alreadyResp then
                            table.insert(applications, {
                                userId = applicantId,
                                time = applyData.time,
                                nickname = "",
                            })
                            table.insert(applicantIds, applicantId)
                        end
                    end
                end
            end

            if #applicantIds > 0 and rawget(_G, "GetUserNickname") then
                GetUserNickname({
                    userIds = applicantIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do map[info.userId] = info.nickname or "" end
                        for _, a in ipairs(applications) do a.nickname = map[a.userId] or "未知" end
                        if callback then callback(applications) end
                    end,
                    onError = function() if callback then callback(applications) end end,
                })
            else
                if callback then callback(applications) end
            end
        end,
        error = function(_, reason)
            print("[阵营] 扫描申请失败: " .. tostring(reason))
            if callback then callback({}) end
        end,
    }, KEYS.camp_apply)
end

--- 盟主/副盟主同意申请
---@param applicantUserId number
---@param callback? fun(success: boolean)
function CloudManager.ApproveFactionApplication(applicantUserId, callback)
    -- 副盟主及以上可审批
    if _getRoleLevel(CloudManager._factionRole) < _getRoleLevel("vice_leader")
       or not CloudManager._factionMeta then
        if callback then callback(false) end
        return
    end

    local meta = CloudManager._factionMeta
    -- 人数上限
    if (meta.memberCount or 0) >= (meta.maxMembers or MAX_CAMP_MEMBERS) then
        print("[阵营] 成员已满")
        if callback then callback(false) end
        return
    end

    -- 追加成员
    if not meta.members then meta.members = {} end
    -- 检查重复
    for _, mid in ipairs(meta.members) do
        if mid == applicantUserId then
            if callback then callback(true) end -- 已在列表
            return
        end
    end
    table.insert(meta.members, applicantUserId)
    meta.memberCount = #meta.members
    -- 新成员默认角色
    if not meta.roles then meta.roles = {} end
    meta.roles[tostring(applicantUserId)] = "member"

    -- 记录审批回复
    CloudManager._campOutResp[tostring(applicantUserId)] = {
        approved = true,
        campId = meta.id,
        campName = meta.name,
        time = os.time(),
    }

    -- 先读再合并: 更新 camp_meta + 发布审批回复
    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :SetInt(KEYS.camp_resp_ts, os.time())
        :Set(KEYS.camp_resp, CloudManager._campOutResp)
        :Save("同意入营", {
            ok = function()
                print("[阵营] 已同意 " .. tostring(applicantUserId) .. " 加入, 当前" .. meta.memberCount .. "人")
                if callback then callback(true) end
            end,
            error = function()
                -- 回滚
                for i, mid in ipairs(meta.members) do
                    if mid == applicantUserId then table.remove(meta.members, i); break end
                end
                meta.memberCount = #meta.members
                CloudManager._campOutResp[tostring(applicantUserId)] = nil
                if callback then callback(false) end
            end,
        })
end

--- 盟主拒绝申请
---@param applicantUserId number
function CloudManager.RejectFactionApplication(applicantUserId)
    CloudManager._campOutResp[tostring(applicantUserId)] = {
        approved = false,
        campId = CloudManager._factionId,
        time = os.time(),
    }
    if rawget(_G, "clientCloud") then
        clientCloud:BatchSet()
            :SetInt(KEYS.camp_resp_ts, os.time())
            :Set(KEYS.camp_resp, CloudManager._campOutResp)
            :Save("拒绝入营")
    end
end

-- ── 申请者检查审批结果 ──

--- 检查我的入营申请是否被批准 (自动完成入营)
---@param callback? fun(result: string) "approved" | "rejected" | "pending" | "none"
function CloudManager.CheckMyFactionApplication(callback)
    if not CloudManager._campOutApply then
        if callback then callback("none") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback("pending") end
        return
    end

    local myUid = clientCloud.userId
    local myUidStr = tostring(myUid)
    local targetCampId = CloudManager._campOutApply.campId

    -- 扫描盟主的审批回复
    clientCloud:GetRankList(KEYS.camp_resp_ts, 0, 100, {
        ok = function(rankList)
            for _, item in ipairs(rankList) do
                local respData = item.score[KEYS.camp_resp]
                if type(respData) == "table" and respData[myUidStr] then
                    local resp = respData[myUidStr]
                    if resp.campId == targetCampId then
                        if resp.approved then
                            -- 入营成功!
                            CloudManager._factionId = targetCampId
                            CloudManager._factionName = CloudManager._campOutApply.campName or ""
                            CloudManager._factionRole = "member"
                            CloudManager._campOutApply = nil
                            -- 清理申请排行
                            clientCloud:BatchSet()
                                :SetInt(KEYS.camp_apply_ts, 0)
                                :Set(KEYS.camp_apply, {})
                                :Save("清理入营申请")
                            CloudManager._syncSocialDomain()
                            CloudManager.PublishProfile()
                            -- 拉取阵营meta(盟主名/人数等), 供UI显示
                            CloudManager._refreshFactionStatus()
                            print("[阵营] 入营审批通过!")
                            if callback then callback("approved") end
                        else
                            CloudManager._campOutApply = nil
                            print("[阵营] 入营申请被拒绝")
                            if callback then callback("rejected") end
                        end
                        return
                    end
                end
            end
            if callback then callback("pending") end
        end,
        error = function()
            if callback then callback("pending") end
        end,
    }, KEYS.camp_resp)
end

-- ── 离开阵营 ──

--- 从成员列表中找到继任者 (按率土职位继承链: 副盟主→军师→先锋官→外交官→精英→成员)
--- 同级别内按加入顺序(members数组顺序)优先
---@param meta table 阵营元数据
---@param excludeUid number 要排除的uid(即将离开的人)
---@return number|nil successorUid
local function _findSuccessor(meta, excludeUid)
    if not meta or not meta.members then return nil end
    local roles = meta.roles or {}
    -- 按继承链顺序逐级查找
    for _, roleName in ipairs(ROLE_SUCCESSION) do
        for _, mid in ipairs(meta.members) do
            if mid ~= excludeUid and (roles[tostring(mid)] or "member") == roleName then
                return mid
            end
        end
    end
    return nil  -- 没有其他人了
end

--- 离开当前阵营
--- 盟主退出: 有其他成员→转让盟主(副盟主优先), 无其他成员→解散
--- 非盟主退出: 直接离开, 本地清除
---@param callback? fun(success: boolean, info: string)
function CloudManager.LeaveFaction(callback)
    if CloudManager._factionId == 0 then
        if callback then callback(true, "未加入阵营") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    local myUid = clientCloud.userId
    local oldName = CloudManager._factionName
    local wasLeader = CloudManager._factionRole == "leader"
    local meta = CloudManager._factionMeta

    if wasLeader and meta then
        -- ── 盟主离开 ──
        local successor = _findSuccessor(meta, myUid)

        if successor then
            -- 有继任者: 转让盟主, 阵营存续
            -- 从成员列表移除自己
            local newMembers = {}
            for _, mid in ipairs(meta.members) do
                if mid ~= myUid then
                    table.insert(newMembers, mid)
                end
            end
            meta.members = newMembers
            meta.memberCount = #newMembers
            meta.leaderId = successor
            -- 更新角色: 继任者→leader, 移除旧盟主
            if not meta.roles then meta.roles = {} end
            meta.roles[tostring(myUid)] = nil
            meta.roles[tostring(successor)] = "leader"

            -- 清除本地状态
            CloudManager._factionId = 0
            CloudManager._factionName = ""
            CloudManager._factionRole = "none"

            -- 发布更新后的meta (旧盟主最后一次写入, 保留排行条目供阵营继续可见)
            clientCloud:BatchSet()
                :Set(KEYS.camp_meta, meta)
                :SetInt(KEYS.camp_resp_ts, 0)
                :Set(KEYS.camp_resp, {})
                :Save("盟主退位, 转让给" .. tostring(successor), {
                    ok = function()
                        print("[阵营] 盟主退出: " .. oldName
                            .. ", 转让给 " .. tostring(successor)
                            .. ", 剩余" .. meta.memberCount .. "人")
                        CloudManager._factionMeta = nil
                        CloudManager._campOutResp = {}
                        CloudManager._syncSocialDomain()
                        CloudManager.PublishProfile()
                        if callback then callback(true, "已退出, 盟主已转让") end
                    end,
                    error = function()
                        -- 回滚
                        CloudManager._factionId = meta.id
                        CloudManager._factionName = oldName
                        CloudManager._factionRole = "leader"
                        if callback then callback(false, "退出失败") end
                    end,
                })
        else
            -- 无继任者: 最后一人, 解散阵营
            CloudManager._factionId = 0
            CloudManager._factionName = ""
            CloudManager._factionRole = "none"

            clientCloud:BatchSet()
                :SetInt(KEYS.camp_leader_ts, 0)
                :Set(KEYS.camp_meta, {})
                :SetInt(KEYS.camp_resp_ts, 0)
                :Set(KEYS.camp_resp, {})
                :Save("解散阵营(最后一人)", {
                    ok = function()
                        print("[阵营] 最后一人离开, 阵营已解散: " .. oldName)
                        CloudManager._factionMeta = nil
                        CloudManager._campOutResp = {}
                        CloudManager._syncSocialDomain()
                        CloudManager.PublishProfile()
                        if callback then callback(true, "阵营已解散") end
                    end,
                    error = function()
                        if callback then callback(false, "解散失败") end
                    end,
                })
        end
    else
        -- ── 非盟主离开 ──
        -- 非盟主无法直接修改camp_meta(存在盟主的排行条目下)
        -- 只能清除本地状态; 盟主侧会通过成员活跃度检测到离开
        CloudManager._factionId = 0
        CloudManager._factionName = ""
        CloudManager._factionRole = "none"
        CloudManager._campOutApply = nil

        -- 清理自己的申请排行条目
        clientCloud:BatchSet()
            :SetInt(KEYS.camp_apply_ts, 0)
            :Set(KEYS.camp_apply, {})
            :Save("成员退出阵营", {
                ok = function()
                    print("[阵营] 已退出: " .. oldName)
                    CloudManager._syncSocialDomain()
                    CloudManager.PublishProfile()
                    if callback then callback(true, "已退出阵营") end
                end,
                error = function()
                    if callback then callback(false, "退出失败") end
                end,
            })
    end
end

-- ── 获取阵营成员列表 ──

--- 获取当前阵营成员档案
---@param callback fun(members: table[])
function CloudManager.GetFactionMembers(callback)
    if CloudManager._factionId == 0 then
        if callback then callback({}) end
        return
    end

    -- 如果是盟主, 直接用本地 meta
    if CloudManager._factionRole == "leader" and CloudManager._factionMeta then
        local memberIds = CloudManager._factionMeta.members or {}
        if #memberIds == 0 then
            if callback then callback({}) end
            return
        end

        --- 内部: 拿到全量 profiles 后, 过滤 + 校验离开 + 补查缺失成员
        local function _processMembers(profiles)
            local memberSet = {}
            for _, mid in ipairs(memberIds) do memberSet[mid] = true end
            local result = {}
            local profileMap = {}
            for _, p in ipairs(profiles) do
                profileMap[p.userId] = p
                if memberSet[p.userId] then table.insert(result, p) end
            end

            -- 找出排行榜中未出现的成员, 用 SearchPlayer 补查
            local missing = {}
            for _, mid in ipairs(memberIds) do
                if not profileMap[mid] then missing[#missing + 1] = mid end
            end

            -- 补查完成后执行验证清理
            local function _afterFetchMissing()
                -- 验证: 只清理 factionId>0 且 != myFid 的（明确加入了其他阵营）
                local myFid = CloudManager._factionId
                local myUid = clientCloud.userId
                local removed = {}
                for _, mid in ipairs(memberIds) do
                    if mid ~= myUid then
                        local mp = profileMap[mid]
                        if mp and mp.profile then
                            local theirFid = mp.profile.factionId
                            if theirFid and theirFid ~= 0 and theirFid ~= myFid then
                                removed[#removed + 1] = mid
                                print("[阵营] 检测到成员 " .. tostring(mid) .. " 已加入其他阵营(factionId=" .. tostring(theirFid) .. ")")
                            end
                        end
                        -- 注意: 找不到的成员(mp==nil)不清理, 可能是新成员还没发布profile
                    end
                end
                if #removed > 0 then
                    local meta = CloudManager._factionMeta
                    local removedSet = {}
                    for _, rid in ipairs(removed) do removedSet[rid] = true end
                    local newMembers = {}
                    for _, mid in ipairs(meta.members or {}) do
                        if not removedSet[mid] then newMembers[#newMembers + 1] = mid end
                    end
                    meta.members = newMembers
                    meta.memberCount = #newMembers
                    local cleanResult = {}
                    for _, r in ipairs(result) do
                        if not removedSet[r.userId] then cleanResult[#cleanResult + 1] = r end
                    end
                    result = cleanResult
                    clientCloud:BatchSet()
                        :Set(KEYS.camp_meta, meta)
                        :Save("盟主自动清理已离开成员", {
                            ok = function()
                                print("[阵营] 已自动清理 " .. #removed .. " 名离开成员, 剩余" .. meta.memberCount .. "人")
                            end,
                        })
                end
                if callback then callback(result) end
            end

            if #missing == 0 then
                _afterFetchMissing()
            else
                -- 逐个补查缺失成员
                local pending = #missing
                for _, mid in ipairs(missing) do
                    CloudManager.SearchPlayer(mid, function(found)
                        if found then
                            profileMap[found.userId] = found
                            table.insert(result, found)
                        end
                        pending = pending - 1
                        if pending <= 0 then _afterFetchMissing() end
                    end)
                end
            end
        end

        -- 先拉取 top-200 profiles, 覆盖大多数成员
        CloudManager.GetPublicProfiles(0, 200, function(profiles)
            _processMembers(profiles)
        end)
        return
    end

    -- 普通成员: 从盟主的 camp_meta 获取成员列表
    clientCloud:GetRankList(KEYS.camp_leader_ts, 0, 50, {
        ok = function(rankList)
            local memberIds = {}
            for _, item in ipairs(rankList) do
                local meta = item.score[KEYS.camp_meta]
                if type(meta) == "table" and meta.id == CloudManager._factionId then
                    memberIds = meta.members or {}
                    break
                end
            end
            if #memberIds == 0 then
                if callback then callback({}) end
                return
            end
            CloudManager.GetPublicProfiles(0, 100, function(profiles)
                local memberSet = {}
                for _, mid in ipairs(memberIds) do memberSet[mid] = true end
                local result = {}
                for _, p in ipairs(profiles) do
                    if memberSet[p.userId] then table.insert(result, p) end
                end
                if callback then callback(result) end
            end)
        end,
        error = function()
            if callback then callback({}) end
        end,
    }, KEYS.camp_meta)
end

--- 获取当前阵营信息
---@return table
function CloudManager.GetFactionInfo()
    return {
        id = CloudManager._factionId,
        name = CloudManager._factionName,
        role = CloudManager._factionRole,
        meta = CloudManager._factionMeta,
    }
end

-- ── 设置成员职位 (仿率土之滨) ──

--- 设置成员职位 (需要操作者权限高于目标当前职位和目标职位)
--- 有效职位: "vice_leader"(副盟主), "strategist"(军师), "vanguard"(先锋官),
---           "diplomat"(外交官), "elite"(精英), "member"(成员)
---@param targetUserId number 目标成员uid
---@param newRole string 新职位名称
---@param callback? fun(success: boolean, reason: string)
function CloudManager.SetMemberRole(targetUserId, newRole, callback)
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    local myUid = clientCloud.userId
    local myRole = CloudManager._factionRole
    if targetUserId == myUid then
        if callback then callback(false, "不能对自己操作") end
        return
    end

    -- 验证目标职位合法性
    if newRole == "leader" then
        if callback then callback(false, "盟主只能通过转让设置") end
        return
    end
    if not FACTION_ROLES[newRole] then
        if callback then callback(false, "无效的职位: " .. tostring(newRole)) end
        return
    end

    -- 检查目标是否在阵营中
    local isMember = false
    for _, mid in ipairs(meta.members or {}) do
        if mid == targetUserId then isMember = true; break end
    end
    if not isMember then
        if callback then callback(false, "对方不在阵营中") end
        return
    end

    if not meta.roles then meta.roles = {} end
    local targetUidStr = tostring(targetUserId)
    local oldRole = meta.roles[targetUidStr] or "member"

    -- 权限检查: 操作者必须比目标当前职位高, 也必须比目标新职位高
    if not _hasAuthorityOver(myRole, oldRole) then
        if callback then callback(false, "你的职位不够, 无法操作" .. _getRoleName(oldRole)) end
        return
    end
    if not _hasAuthorityOver(myRole, newRole) then
        if callback then callback(false, "你的职位不够, 无法授予" .. _getRoleName(newRole)) end
        return
    end

    -- 人数上限检查 (有限职位)
    local roleDef = FACTION_ROLES[newRole]
    if roleDef.max > 0 then
        local current = _countRole(meta.roles, newRole)
        -- 如果目标已经是这个职位, 不占额外名额
        if oldRole ~= newRole and current >= roleDef.max then
            if callback then callback(false, _getRoleName(newRole) .. "名额已满(上限" .. roleDef.max .. "人)") end
            return
        end
    end

    if oldRole == newRole then
        if callback then callback(true, "已经是" .. _getRoleName(newRole)) end
        return
    end

    meta.roles[targetUidStr] = newRole

    -- 发布更新
    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("设置职位", {
            ok = function()
                print("[阵营] " .. tostring(targetUserId) .. " "
                    .. _getRoleName(oldRole) .. "→" .. _getRoleName(newRole))
                if callback then callback(true, "已设为" .. _getRoleName(newRole)) end
            end,
            error = function(_, reason)
                -- 回滚
                meta.roles[targetUidStr] = oldRole
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

--- 兼容旧接口: 设置/取消副盟主
---@param targetUserId number
---@param setAsVice boolean
---@param callback? fun(success: boolean, reason: string)
function CloudManager.SetViceLeader(targetUserId, setAsVice, callback)
    CloudManager.SetMemberRole(targetUserId, setAsVice and "vice_leader" or "member", callback)
end

-- ── 阵营改名 (仅盟主) ──

---@param newName string
---@param callback? fun(success: boolean, reason: string)
function CloudManager.RenameFaction(newName, callback)
    if CloudManager._factionRole ~= "leader" then
        if callback then callback(false, "只有盟主才能改名") end
        return
    end
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not newName or #newName == 0 then
        if callback then callback(false, "名称不能为空") end
        return
    end
    if #newName > 24 then
        if callback then callback(false, "名称过长(最多8个汉字)") end
        return
    end
    local oldName = meta.name
    meta.name = newName
    CloudManager._factionName = newName

    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("阵营改名", {
            ok = function()
                print("[阵营] 改名成功: " .. tostring(oldName) .. " → " .. newName)
                if callback then callback(true, nil) end
            end,
            error = function(_, reason)
                meta.name = oldName
                CloudManager._factionName = oldName
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

-- ── 踢出成员 (副盟主及以上, 只能踢低于自己职位的) ──

--- 踢出指定成员
---@param targetUserId number
---@param callback? fun(success: boolean, reason: string)
function CloudManager.KickMember(targetUserId, callback)
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    local myUid = clientCloud.userId
    local myRole = CloudManager._factionRole
    if targetUserId == myUid then
        if callback then callback(false, "不能踢自己, 请使用退出") end
        return
    end

    -- 操作权限: 副盟主及以上
    if _getRoleLevel(myRole) < _getRoleLevel("vice_leader") then
        if callback then callback(false, "副盟主及以上才能踢人") end
        return
    end

    -- 检查目标是否在阵营中
    local targetIdx = nil
    for i, mid in ipairs(meta.members or {}) do
        if mid == targetUserId then targetIdx = i; break end
    end
    if not targetIdx then
        if callback then callback(false, "对方不在阵营中") end
        return
    end

    if not meta.roles then meta.roles = {} end
    local targetUidStr = tostring(targetUserId)
    local targetRole = meta.roles[targetUidStr] or "member"

    -- 只能踢低于自己职位的
    if not _hasAuthorityOver(myRole, targetRole) then
        if callback then callback(false, "无法踢出" .. _getRoleName(targetRole) .. ", 职位不低于你") end
        return
    end

    -- 从成员列表移除
    local removedUid = table.remove(meta.members, targetIdx)
    meta.memberCount = #meta.members
    meta.roles[targetUidStr] = nil

    -- 发布更新
    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("踢出成员", {
            ok = function()
                print("[阵营] 踢出 " .. tostring(targetUserId) .. " (" .. _getRoleName(targetRole) .. ")"
                    .. ", 剩余" .. meta.memberCount .. "人")
                if callback then callback(true, "已踢出") end
            end,
            error = function(_, reason)
                -- 回滚
                table.insert(meta.members, targetIdx, removedUid)
                meta.memberCount = #meta.members
                meta.roles[targetUidStr] = targetRole
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

-- ── 转让盟主 ──

--- 盟主主动转让给指定成员
---@param targetUserId number
---@param callback? fun(success: boolean, reason: string)
function CloudManager.TransferLeadership(targetUserId, callback)
    if CloudManager._factionRole ~= "leader" then
        if callback then callback(false, "只有盟主才能转让") end
        return
    end
    local meta = CloudManager._factionMeta
    if not meta then
        if callback then callback(false, "阵营数据未加载") end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    local myUid = clientCloud.userId
    if targetUserId == myUid then
        if callback then callback(false, "不能转让给自己") end
        return
    end

    -- 检查目标是否在阵营中
    local isMember = false
    for _, mid in ipairs(meta.members or {}) do
        if mid == targetUserId then isMember = true; break end
    end
    if not isMember then
        if callback then callback(false, "对方不在阵营中") end
        return
    end

    if not meta.roles then meta.roles = {} end
    local myUidStr = tostring(myUid)
    local targetUidStr = tostring(targetUserId)

    -- 转让: 自己降为成员, 目标升为盟主
    meta.leaderId = targetUserId
    meta.roles[myUidStr] = "member"
    meta.roles[targetUidStr] = "leader"

    CloudManager._factionRole = "member"

    clientCloud:BatchSet()
        :Set(KEYS.camp_meta, meta)
        :Save("转让盟主", {
            ok = function()
                print("[阵营] 盟主已转让给 " .. tostring(targetUserId))
                CloudManager._factionMeta = nil  -- 不再是盟主, 不持有meta
                CloudManager._syncSocialDomain()
                if callback then callback(true, "盟主已转让") end
            end,
            error = function(_, reason)
                -- 回滚
                meta.leaderId = myUid
                meta.roles[myUidStr] = "leader"
                meta.roles[targetUidStr] = meta.roles[targetUidStr]  -- 保持
                CloudManager._factionRole = "leader"
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

-- ── 继位检测: 新盟主上线后接管 ──

--- 刷新阵营状态 (登录时自动调用)
--- 检测当前玩家是否因盟主退出而被提升为新盟主, 如果是则重新发布 camp_meta
---@param callback? fun(transferred: boolean)
function CloudManager._refreshFactionStatus(callback)
    if CloudManager._factionId == 0 then
        if callback then callback(false) end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false) end
        return
    end

    local myUid = clientCloud.userId
    local myCampId = CloudManager._factionId

    -- 从排行榜获取当前阵营的 meta
    clientCloud:GetRankList(KEYS.camp_leader_ts, 0, 100, {
        ok = function(rankList)
            local latestMeta = nil
            local latestTs = 0

            -- 找到自己阵营的最新meta (按campId去重, 保留最新时间戳)
            for _, item in ipairs(rankList) do
                local meta = item.score[KEYS.camp_meta]
                if type(meta) == "table" and meta.id == myCampId then
                    local ts = (item.iscore and item.iscore[KEYS.camp_leader_ts]) or 0
                    if ts > latestTs then
                        latestTs = ts
                        latestMeta = meta
                    end
                end
            end

            if not latestMeta then
                -- 阵营已不存在 (可能已解散)
                print("[阵营] 阵营已不存在, 清除本地状态")
                CloudManager._factionId = 0
                CloudManager._factionName = ""
                CloudManager._factionRole = "none"
                CloudManager._factionMeta = nil
                CloudManager._syncSocialDomain()
                if callback then callback(false) end
                return
            end

            -- 检查自己是否在成员列表中
            local inMembers = false
            for _, mid in ipairs(latestMeta.members or {}) do
                if mid == myUid then inMembers = true; break end
            end

            if not inMembers then
                -- 我已不在阵营中 (可能被踢)
                print("[阵营] 我已不在阵营成员中, 清除本地状态")
                CloudManager._factionId = 0
                CloudManager._factionName = ""
                CloudManager._factionRole = "none"
                CloudManager._factionMeta = nil
                CloudManager._syncSocialDomain()
                if callback then callback(false) end
                return
            end

            -- 同步阵营名称和meta
            CloudManager._factionName = latestMeta.name or CloudManager._factionName

            -- 关键: 检查 leaderId 是否是自己
            if latestMeta.leaderId == myUid then
                if CloudManager._factionRole ~= "leader" then
                    -- 我被提升为新盟主! 重新发布 camp_meta 到自己的排行条目
                    print("[阵营] 检测到盟主继位! 重新发布 camp_meta")
                    CloudManager._factionRole = "leader"
                    CloudManager._factionMeta = latestMeta

                    clientCloud:BatchSet()
                        :SetInt(KEYS.camp_leader_ts, os.time())
                        :Set(KEYS.camp_meta, latestMeta)
                        :Save("新盟主接管阵营", {
                            ok = function()
                                print("[阵营] 新盟主接管完成: " .. (latestMeta.name or ""))
                                CloudManager._syncSocialDomain()
                                CloudManager.PublishProfile()
                                if callback then callback(true) end
                            end,
                            error = function()
                                print("[阵营] 接管发布失败, 下次登录重试")
                                if callback then callback(false) end
                            end,
                        })
                    return
                else
                    -- 已经是盟主, 更新meta缓存
                    CloudManager._factionMeta = latestMeta
                end
            else
                -- 非盟主: 更新角色, 保留meta供UI显示(盟主名/人数等)
                local roles = latestMeta.roles or {}
                local myRole = roles[tostring(myUid)] or "member"
                CloudManager._factionRole = myRole
                CloudManager._factionMeta = latestMeta
            end

            if callback then callback(false) end
        end,
        error = function(_, reason)
            print("[阵营] 刷新阵营状态失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    }, KEYS.camp_meta)
end

-- ============================================================================
-- 阵营聊天 (云端同步)
-- ============================================================================

local MAX_CHAT_HISTORY = 10   -- 每人在排行榜保留的最近消息数
local CHAT_POLL_INTERVAL = 12 -- 聊天轮询间隔(秒)
CloudManager._chatLastPoll = 0
CloudManager._chatLastSentTs = 0
CloudManager._chatPendingMsgs = {}  -- 待发布的本地消息队列
CloudManager._chatMerged = {}       -- 合并后的全部消息 (按 ts 排序)
CloudManager._chatSeenTs = {}       -- 已见过的最大 ts (per uid)

--- 发送阵营聊天消息 (写入本地队列 + 立即发布到排行榜)
---@param text string 消息内容
---@param senderName string 发送者昵称
function CloudManager.SendFactionChat(text, senderName)
    if CloudManager._factionId == 0 then return false, "未加入阵营" end
    if not rawget(_G, "clientCloud") then return false, "云端不可用" end
    if not text or #text == 0 then return false, "消息为空" end

    local avIdx = (rawget(_G, "playerInfo") and playerInfo.avatarIdx) or 1
    local ts = os.time()
    local msg = {
        text = text,
        name = senderName or "???",
        time = os.date("%H:%M", ts),
        ts = ts,
        uid = clientCloud.userId,
        av = avIdx,
    }
    -- 追加到本地队列
    table.insert(CloudManager._chatPendingMsgs, msg)
    -- 也追加到合并列表以便立刻显示
    table.insert(CloudManager._chatMerged, msg)

    -- 标记自己的时间戳已见，防止轮询时重复拉取本条消息
    CloudManager._chatSeenTs[clientCloud.userId] = ts

    -- 发布到排行榜 (保留最近 N 条)
    local toPublish = {}
    local start = math.max(1, #CloudManager._chatPendingMsgs - MAX_CHAT_HISTORY + 1)
    for i = start, #CloudManager._chatPendingMsgs do
        local m = CloudManager._chatPendingMsgs[i]
        toPublish[#toPublish + 1] = { text = m.text, name = m.name, time = m.time, ts = m.ts, av = m.av }
    end

    clientCloud:BatchSet()
        :SetInt(KEYS.camp_chat_ts, ts)
        :Set(KEYS.camp_chat, toPublish)
        :Save("发送阵营聊天")

    CloudManager._chatLastSentTs = ts
    return true
end

--- 生成类型安全的聊天去重 key（避免 int/float tostring 差异导致去重失败）
local function chatMsgKey(uid, ts)
    return string.format("%d_%d", math.floor(tonumber(uid) or 0), math.floor(tonumber(ts) or 0))
end

--- 拉取阵营聊天消息 (从排行榜获取所有成员的最近消息)
---@param callback? fun(messages: table[])
function CloudManager.PollFactionChat(callback)
    if CloudManager._factionId == 0 then
        if callback then callback({}) end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end

    clientCloud:GetRankList(KEYS.camp_chat_ts, 0, 100, {
        ok = function(rankList)
            local newMsgs = {}
            for _, item in ipairs(rankList) do
                local chatData = item.score[KEYS.camp_chat]
                if type(chatData) == "table" then
                    local senderUid = item.uid or 0
                    local seenTs = CloudManager._chatSeenTs[senderUid] or 0
                    for _, m in ipairs(chatData) do
                        if type(m) == "table" and m.ts and m.ts > seenTs then
                            -- 新消息
                            newMsgs[#newMsgs + 1] = {
                                text = m.text or "",
                                name = m.name or "???",
                                time = m.time or "",
                                ts = m.ts,
                                uid = senderUid,
                                av = m.av or 1,
                            }
                        end
                    end
                    -- 更新已见时间戳
                    if #chatData > 0 then
                        local maxTs = seenTs
                        for _, m in ipairs(chatData) do
                            if type(m) == "table" and m.ts and m.ts > maxTs then maxTs = m.ts end
                        end
                        CloudManager._chatSeenTs[senderUid] = maxTs
                    end
                end
            end

            -- 合并到全局列表 (去重, 使用类型安全的 key)
            local existingTs = {}
            for _, m in ipairs(CloudManager._chatMerged) do
                existingTs[chatMsgKey(m.uid, m.ts)] = true
            end
            for _, m in ipairs(newMsgs) do
                local key = chatMsgKey(m.uid, m.ts)
                if not existingTs[key] then
                    table.insert(CloudManager._chatMerged, m)
                end
            end

            -- 按 ts 排序
            table.sort(CloudManager._chatMerged, function(a, b) return (a.ts or 0) < (b.ts or 0) end)

            -- 保留最近 50 条
            while #CloudManager._chatMerged > 50 do
                table.remove(CloudManager._chatMerged, 1)
            end

            if callback then callback(CloudManager._chatMerged) end
        end,
        error = function()
            if callback then callback(CloudManager._chatMerged) end
        end,
    }, KEYS.camp_chat)
end

--- 获取当前合并的聊天消息列表 (供UI直接读取)
---@return table[]
function CloudManager.GetFactionChatMessages()
    return CloudManager._chatMerged
end

-- ============================================================================
-- 世界聊天 (全服公共频道, 排行榜存储)
-- ============================================================================
local WORLD_CHAT_MAX_PER_USER = 5     -- 每人在排行榜保留的最近消息数
local WORLD_CHAT_POLL_INTERVAL = 6    -- 世界聊天轮询间隔(秒) - 更实时
local WORLD_CHAT_MAX_MERGED = 100     -- 本地合并列表最大条数

CloudManager._worldChatLastPoll = 0
CloudManager._worldChatPendingMsgs = {}
CloudManager._worldChatMerged = {}
CloudManager._worldChatSeenTs = {}

--- 发送世界聊天消息
---@param text string 消息内容
---@param senderName string 发送者名字
---@return boolean, string?
function CloudManager.SendWorldChat(text, senderName)
    if not rawget(_G, "clientCloud") then return false, "云端不可用" end
    if not text or #text == 0 then return false, "消息为空" end

    local avIdx = (rawget(_G, "playerInfo") and playerInfo.avatarIdx) or 1
    local ts = os.time()
    -- 防止同一秒内重复发送相同内容（移动端键盘回车+按钮可能双触发）
    if CloudManager._lastWorldChatTs == ts and CloudManager._lastWorldChatText == text then
        return true
    end
    CloudManager._lastWorldChatTs = ts
    CloudManager._lastWorldChatText = text
    local msg = {
        text = text,
        name = senderName or "???",
        time = os.date("%H:%M", ts),
        ts = ts,
        uid = clientCloud.userId,
        av = avIdx,
    }
    table.insert(CloudManager._worldChatPendingMsgs, msg)
    table.insert(CloudManager._worldChatMerged, msg)

    -- 标记自己的时间戳已见，防止轮询时重复拉取本条消息
    CloudManager._worldChatSeenTs[clientCloud.userId] = ts

    -- 发布到排行榜 (保留最近 N 条)
    local toPublish = {}
    local start = math.max(1, #CloudManager._worldChatPendingMsgs - WORLD_CHAT_MAX_PER_USER + 1)
    for i = start, #CloudManager._worldChatPendingMsgs do
        local m = CloudManager._worldChatPendingMsgs[i]
        toPublish[#toPublish + 1] = { text = m.text, name = m.name, time = m.time, ts = m.ts, av = m.av }
    end

    clientCloud:BatchSet()
        :SetInt(KEYS.world_chat_ts, ts)
        :Set(KEYS.world_chat, toPublish)
        :Save("发送世界聊天")

    return true
end

--- 拉取世界聊天消息 (从排行榜获取最近30个用户的消息)
---@param callback? fun(messages: table[])
function CloudManager.PollWorldChat(callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end

    clientCloud:GetRankList(KEYS.world_chat_ts, 0, 30, {
        ok = function(rankList)
            local newMsgs = {}
            for _, item in ipairs(rankList) do
                local chatData = item.score[KEYS.world_chat]
                if type(chatData) == "table" then
                    local senderUid = item.uid or 0
                    local seenTs = CloudManager._worldChatSeenTs[senderUid] or 0
                    for _, m in ipairs(chatData) do
                        if type(m) == "table" and m.ts and m.ts > seenTs then
                            newMsgs[#newMsgs + 1] = {
                                text = m.text or "",
                                name = m.name or "???",
                                time = m.time or "",
                                ts = m.ts,
                                uid = senderUid,
                                av = m.av or 1,
                            }
                        end
                    end
                    if #chatData > 0 then
                        local maxTs = seenTs
                        for _, m in ipairs(chatData) do
                            if type(m) == "table" and m.ts and m.ts > maxTs then maxTs = m.ts end
                        end
                        CloudManager._worldChatSeenTs[senderUid] = maxTs
                    end
                end
            end

            -- 合并到全局列表 (去重, 使用类型安全的 key)
            local existingTs = {}
            for _, m in ipairs(CloudManager._worldChatMerged) do
                existingTs[chatMsgKey(m.uid, m.ts)] = true
            end
            for _, m in ipairs(newMsgs) do
                local key = chatMsgKey(m.uid, m.ts)
                if not existingTs[key] then
                    table.insert(CloudManager._worldChatMerged, m)
                end
            end

            -- 按 ts 排序
            table.sort(CloudManager._worldChatMerged, function(a, b) return (a.ts or 0) < (b.ts or 0) end)

            -- 保留最近 100 条
            while #CloudManager._worldChatMerged > WORLD_CHAT_MAX_MERGED do
                table.remove(CloudManager._worldChatMerged, 1)
            end

            -- 批量查询 nickname 覆盖 name 字段
            local uidSet = {}
            local uidList = {}
            for _, m in ipairs(CloudManager._worldChatMerged) do
                local uid = m.uid or 0
                if uid > 0 and not uidSet[uid] then
                    uidSet[uid] = true
                    uidList[#uidList + 1] = uid
                end
            end
            if #uidList > 0 and rawget(_G, "GetUserNickname") then
                pcall(function()
                    GetUserNickname({
                        userIds = uidList,
                        onSuccess = function(nicknames)
                            local nameMap = {}
                            for _, info in ipairs(nicknames) do
                                nameMap[info.userId] = info.nickname
                            end
                            -- 缓存自己的 TapTap nickname，供发送时直接使用
                            local myUid = clientCloud.userId
                            if myUid and nameMap[myUid] and #nameMap[myUid] > 0 then
                                CloudManager._myTapNickname = nameMap[myUid]
                            end
                            for _, m in ipairs(CloudManager._worldChatMerged) do
                                local nick = nameMap[m.uid or 0]
                                if nick and #nick > 0 then m.name = nick end
                            end
                            if callback then callback(CloudManager._worldChatMerged) end
                        end,
                        onError = function()
                            if callback then callback(CloudManager._worldChatMerged) end
                        end,
                    })
                end)
            else
                if callback then callback(CloudManager._worldChatMerged) end
            end
        end,
        error = function()
            if callback then callback(CloudManager._worldChatMerged) end
        end,
    }, KEYS.world_chat)
end

--- 获取当前世界聊天消息列表 (供UI直接读取)
---@return table[]
function CloudManager.GetWorldChatMessages()
    return CloudManager._worldChatMerged
end

-- ============================================================================
-- 内部工具函数
-- ============================================================================

--- 保存本地JSON (多domain格式)
function CloudManager._saveLocalJSON(allData)
    local cjson_m = rawget(_G, "cjson")
    if not cjson_m then return end

    -- 如果没传allData, 重新收集
    if not allData then
        allData = {}
        for name, _ in pairs(DOMAINS) do
            allData[name] = CloudManager.CollectDomainData(name)
        end
    end

    local saveObj = {
        _multiDomain = true,
        _version = SAVE_VERSION,
        savedAt = os.time(),
        domains = allData,
    }

    local ok, json = pcall(cjson_m.encode, saveObj)
    if ok then
        local file = File("p_49dd_savegame.json", FILE_WRITE)
        if file:IsOpen() then
            file:WriteString(json)
            file:Close()
        end
    end
end

--- 加载本地JSON
---@return table|nil
function CloudManager._loadLocalJSON()
    if not fileSystem:FileExists("p_49dd_savegame.json") then
        return nil
    end
    local cjson_m = rawget(_G, "cjson")
    if not cjson_m then return nil end

    local file = File("p_49dd_savegame.json", FILE_READ)
    if not file:IsOpen() then return nil end

    local ok, data = pcall(cjson_m.decode, file:ReadString())
    file:Close()
    if ok and data then return data end
    return nil
end

--- 从多domain数据恢复游戏状态
function CloudManager._applyMultiDomain(saveObj)
    local domains = saveObj.domains
    if not domains then return end

    -- core -> playerInfo
    if domains.core and domains.core.playerInfo then
        for k, v in pairs(domains.core.playerInfo) do
            playerInfo[k] = v
        end
    end

    -- heroes
    if domains.heroes then
        local d = domains.heroes
        if d.playerHeroes then
            for k in pairs(playerHeroes) do playerHeroes[k] = nil end
            for k, v in pairs(d.playerHeroes) do
                local idx = tonumber(k) or k
                if type(v) == "table" then
                    if v.owned == nil then v.owned = true end
                    if v.constellation == nil then v.constellation = 0 end
                    v.constellation = tonumber(v.constellation) or 0
                    playerHeroes[idx] = v
                end
            end
        end
        if d.heroFragments then
            for k, v in pairs(d.heroFragments) do heroFragments[tonumber(k) or k] = v end
        end
    end

    -- equip
    if domains.equip and domains.equip.playerEquipment then
        -- 复用 ApplySaveData 的装备恢复逻辑 (含新旧格式迁移)
        if rawget(_G, "ApplySaveData") then
            ApplySaveData({ playerEquipment = domains.equip.playerEquipment })
        end
    end

    -- skills
    if domains.skills then
        local d = domains.skills
        if d.playerEquippedSkills then playerEquippedSkills = d.playerEquippedSkills end
        if d.unlockedSkills then
            for _, idx in ipairs(d.unlockedSkills) do
                if SKILL_DEFS[idx] then SKILL_DEFS[idx].unlocked = true end
            end
        end
        if d.skillFragments then
            for k, v in pairs(d.skillFragments) do skillFragments[tonumber(k) or k] = v end
        end
        if d.skillLayers then
            for k, v in pairs(d.skillLayers) do skillLayers[tonumber(k) or k] = v end
        end
        for idx = 1, #SKILL_DEFS do
            if SKILL_DEFS[idx].unlocked and not skillLayers[idx] then
                skillLayers[idx] = 1
            end
        end
    end

    -- progress
    if domains.progress then
        local d = domains.progress
        if d.stageMaxUnlocked then stageState.maxUnlocked = d.stageMaxUnlocked end
        if d.stageCurrentPage then stageState.currentPage = d.stageCurrentPage end
        if d.stageStars then stageStars = d.stageStars end
        if d.stageStarClaimed then stageStarClaimed = d.stageStarClaimed end
        if d.stageChestClaimed then stageChestClaimed = d.stageChestClaimed end
        if d.abyssCleared then abyssCleared = d.abyssCleared end
        if d.towerHighestFloor then towerState.highestFloor = d.towerHighestFloor end
        if d.towerCurrentFloor then towerState.currentFloor = math.min(d.towerCurrentFloor, 1000) end
        if d.rankedScore then rankedState.score = d.rankedScore end
        if d.rankedWins then rankedState.wins = d.rankedWins end
        if d.rankedLosses then rankedState.losses = d.rankedLosses end
        if d.rankedStreak then rankedState.streak = d.rankedStreak end
        if d.rankedHighestScore then rankedState.highestScore = d.rankedHighestScore end
        if d.gachaPity then gachaState.pityCounter = d.gachaPity end
        if d.limitedGachaPity then gachaState.limitedPityCounter = d.limitedGachaPity end
    end

    -- welfare (复用 ApplySaveData 的恢复逻辑)
    if domains.welfare then
        if rawget(_G, "ApplySaveData") then
            ApplySaveData(domains.welfare)
        end
    end

    -- social
    if domains.social then
        local d = domains.social
        CloudManager._friendIds = d.friendIds or {}
        CloudManager._factionId = d.factionId or 0
        CloudManager._factionName = d.factionName or ""
        CloudManager._factionRole = d.factionRole or "none"
    end

    -- explore
    if domains.explore and domains.explore.explorationState then
        if rawget(_G, "Exploration") and Exploration.RestoreState then
            Exploration.Init(vg, fontId, IMG)
            if rawget(_G, "SyncPlayerDataToExploration") then
                SyncPlayerDataToExploration()
            end
            Exploration.RestoreState(domains.explore.explorationState)
            print("[CloudManager] 探索状态已恢复")
        end
    end

    -- 向下兼容: level 与 rankIdx 同步
    playerInfo.level = playerInfo.rankIdx or 1
    if rawget(_G, "CheckPlayerLevelUp") then
        CheckPlayerLevelUp()
    end
end

--- 构建旧格式存档数据 (向下兼容)
function CloudManager._buildLegacyData(allData)
    -- 合并所有domain到一个扁平table (与旧 SaveGameProgress 结构一致)
    local legacy = { savedAt = os.time() }

    if allData.core then
        legacy.playerInfo = allData.core.playerInfo
    end
    if allData.heroes then
        legacy.playerHeroes = allData.heroes.playerHeroes
        legacy.heroFragments = allData.heroes.heroFragments
    end
    if allData.equip then
        legacy.playerEquipment = allData.equip.playerEquipment
    end
    if allData.skills then
        legacy.playerEquippedSkills = allData.skills.playerEquippedSkills
        legacy.unlockedSkills = allData.skills.unlockedSkills
        legacy.skillFragments = allData.skills.skillFragments
        legacy.skillLayers = allData.skills.skillLayers
    end
    if allData.progress then
        local d = allData.progress
        legacy.stageMaxUnlocked = d.stageMaxUnlocked
        legacy.stageCurrentPage = d.stageCurrentPage
        legacy.stageStars = d.stageStars
        legacy.stageStarClaimed = d.stageStarClaimed
        legacy.stageChestClaimed = d.stageChestClaimed
        legacy.abyssCleared = d.abyssCleared
        legacy.towerHighestFloor = d.towerHighestFloor
        legacy.towerCurrentFloor = d.towerCurrentFloor
        legacy.rankedScore = d.rankedScore
        legacy.rankedWins = d.rankedWins
        legacy.rankedLosses = d.rankedLosses
        legacy.rankedStreak = d.rankedStreak
        legacy.rankedHighestScore = d.rankedHighestScore
        legacy.gachaPity = d.gachaPity
        legacy.limitedGachaPity = d.limitedGachaPity
    end
    if allData.welfare then
        local d = allData.welfare
        legacy.dailyTaskState = d.dailyTaskState
        legacy.weeklyTaskState = d.weeklyTaskState
        legacy.achievementClaimed = d.achievementClaimed
        legacy.welfareState = d.welfareState
        legacy.cdkRedeemed = d.cdkRedeemed
        legacy.mailClaimed = d.mailClaimed
        legacy.tutorialRewardClaimed = d.tutorialRewardClaimed
        legacy.sealData = d.sealData
        legacy.sealExpItems = d.sealExpItems
        legacy.sealInventory = d.sealInventory
        legacy.sealInventoryNextId = d.sealInventoryNextId
        legacy.dailyDungeonState = d.dailyDungeonState
        legacy.resourceDungeonState = d.resourceDungeonState
        legacy.battlePassState = d.battlePassState
    end
    if allData.explore then
        legacy.explorationState = allData.explore.explorationState
    end

    return legacy
end

-- ── 社交轮询定时器 ──
local socialPollTimer = 0
local SOCIAL_POLL_INTERVAL = 15  -- 每15秒轮询一次社交状态
local socialPollBusy = false     -- 防止并发轮询

--- 更新重试定时器 + 社交轮询 (在 HandleUpdate 中调用)
function CloudManager.Update(dt)
    if retryTimer > 0 then
        retryTimer = retryTimer - dt
        if retryTimer <= 0 and retryData then
            print("[CloudManager] 重试云端同步...")
            CloudManager.SaveAll()
            retryData = nil
        end
    end

    -- 社交轮询: 好友回复 + 阵营审批结果
    if not rawget(_G, "clientCloud") then return end
    socialPollTimer = socialPollTimer + dt
    if socialPollTimer >= SOCIAL_POLL_INTERVAL and not socialPollBusy then
        socialPollTimer = 0
        socialPollBusy = true

        -- 1) 好友回复轮询: 检查我发出的好友请求是否被对方回复
        CloudManager.CheckMyRequestResponses(function(results)
            if results and #results > 0 then
                for _, r in ipairs(results) do
                    if r.accepted then
                        print("[社交轮询] 好友请求被 " .. tostring(r.toUid) .. " 同意, 已互加!")
                        if rawget(_G, "ShowToast") then ShowToast("你与玩家" .. tostring(r.toUid) .. "已成为好友!") end
                        if rawget(_G, "playerInfo") then
                            playerInfo.totalFriends = (playerInfo.totalFriends or 0) + 1
                        end
                    end
                end
                -- 刷新好友界面
                if rawget(_G, "friendsUI") then
                    friendsUI.loaded = false; friendsUI.loading = false
                end
            end

            -- 2) 阵营审批轮询: 检查我的入营申请是否被批准
            CloudManager.CheckMyFactionApplication(function(result)
                socialPollBusy = false
                if result == "approved" then
                    print("[社交轮询] 入营申请已通过!")
                    if rawget(_G, "ShowToast") then ShowToast("你的入营申请已通过!") end
                    if rawget(_G, "playerInfo") then playerInfo.factionJoined = 1 end
                    if rawget(_G, "factionUI") then
                        factionUI.loaded = false; factionUI.loading = false
                        factionUI.applyStatus = nil
                    end
                elseif result == "rejected" then
                    print("[社交轮询] 入营申请被拒绝")
                    if rawget(_G, "ShowToast") then ShowToast("你的入营申请被拒绝") end
                    if rawget(_G, "factionUI") then factionUI.applyStatus = nil end
                end
            end)
        end)
    end

    -- 阵营聊天轮询
    if CloudManager._factionId ~= 0 then
        CloudManager._chatLastPoll = (CloudManager._chatLastPoll or 0) + dt
        if CloudManager._chatLastPoll >= CHAT_POLL_INTERVAL then
            CloudManager._chatLastPoll = 0
            CloudManager.PollFactionChat()
        end
    end

    -- 世界聊天轮询 (始终运行)
    CloudManager._worldChatLastPoll = (CloudManager._worldChatLastPoll or 0) + dt
    if CloudManager._worldChatLastPoll >= WORLD_CHAT_POLL_INTERVAL then
        CloudManager._worldChatLastPoll = 0
        CloudManager.PollWorldChat()
    end
end

-- ============================================================================
-- 便捷访问
-- ============================================================================

--- 获取所有domain key名
function CloudManager.GetDomainKeys()
    return DOMAINS
end

--- 获取前缀
function CloudManager.GetPrefix()
    return PREFIX
end

--- 获取上次同步时间
function CloudManager.GetLastSyncTime()
    return lastSyncTime
end

--- 云端数据是否正在加载中 (LoadAll 异步期间为 true)
--- 用于 UI 层阻断玩家操作, 防止在云数据到达前产生脏数据
---@return boolean
function CloudManager.IsCloudLoading()
    return cloudLoadPending
end

-- ============================================================================
-- 封禁系统
-- ============================================================================

--- 封禁等级常量 (供外部使用)
CloudManager.BAN_LEVEL_NONE   = BAN_LEVEL_NONE
CloudManager.BAN_LEVEL_SOCIAL = BAN_LEVEL_SOCIAL
CloudManager.BAN_LEVEL_CORE   = BAN_LEVEL_CORE
CloudManager.BAN_LEVEL_FULL   = BAN_LEVEL_FULL

--- 检查当前玩家是否被封禁 (启动时调用)
--- 原理: 扫描 ban_ts 排行榜, 找到管理员发布的封禁名单, 检查自己是否在列表中
---@param callback fun(level: number, reason: string)
function CloudManager.CheckBanStatus(callback)
    if not rawget(_G, "clientCloud") then
        banChecked = true
        if callback then callback(BAN_LEVEL_NONE, "") end
        return
    end

    local myUid = clientCloud.userId
    local myUidStr = tostring(myUid)

    -- 扫描 ban_ts 排行榜 (管理员通过 SetInt 发布, 按时间倒序)
    clientCloud:GetRankList(KEYS.ban_ts, 0, 50, {
        ok = function(rankList)
            local foundLevel = BAN_LEVEL_NONE
            local foundReason = ""

            for _, item in ipairs(rankList) do
                local banData = item.score[KEYS.ban_data]
                if type(banData) == "table" then
                    -- 封禁名单格式: { bans = { ["uid"] = { level=1-3, reason="...", until=timestamp } } }
                    local bans = banData.bans
                    if type(bans) == "table" and bans[myUidStr] then
                        local entry = bans[myUidStr]
                        -- 检查是否已过期
                        local untilTime = entry["until"] or 0
                        if untilTime == 0 or untilTime > os.time() then
                            local lvl = entry.level or BAN_LEVEL_FULL
                            if lvl > foundLevel then
                                foundLevel = lvl
                                foundReason = entry.reason or "违规操作"
                            end
                        end
                    end
                end
            end

            -- 加载隐藏名单 (管理员用)
            if not CloudManager._hiddenPlayers then CloudManager._hiddenPlayers = {} end
            for _, item2 in ipairs(rankList) do
                local bd2 = item2.score[KEYS.ban_data]
                if type(bd2) == "table" and type(bd2.bans) == "table" then
                    for uid2, info2 in pairs(bd2.bans) do
                        if type(info2) == "table" and info2.rankHidden then
                            CloudManager._hiddenPlayers[tostring(uid2)] = true
                        end
                    end
                end
            end

            banLevel = foundLevel
            banReason = foundReason
            banChecked = true

            if foundLevel > BAN_LEVEL_NONE then
                print("[封禁] 检测到封禁: 等级=" .. foundLevel .. " 原因=" .. foundReason)
            else
                print("[封禁] 未被封禁")
            end

            if callback then callback(foundLevel, foundReason) end
        end,
        error = function(_, reason)
            print("[封禁] 检查封禁状态失败: " .. tostring(reason))
            banChecked = true
            -- 网络失败时不封禁 (宽松策略)
            if callback then callback(BAN_LEVEL_NONE, "") end
        end,
    }, KEYS.ban_data)
end

--- 获取当前封禁等级
---@return number 0=无, 1=社交, 2=核心, 3=全封
function CloudManager.GetBanLevel()
    return banLevel
end

--- 获取封禁原因
---@return string
function CloudManager.GetBanReason()
    return banReason
end

--- 是否已完成封禁检查
---@return boolean
function CloudManager.IsBanChecked()
    return banChecked
end

--- 检查是否被封禁到指定等级
---@param level number 要检查的等级
---@return boolean
function CloudManager.IsBanned(level)
    return banLevel >= (level or BAN_LEVEL_SOCIAL)
end

--- 获取封禁等级的中文描述
---@param level number
---@return string
function CloudManager.GetBanLevelName(level)
    if level >= BAN_LEVEL_FULL then return "全面封禁"
    elseif level >= BAN_LEVEL_CORE then return "核心功能封禁"
    elseif level >= BAN_LEVEL_SOCIAL then return "社交封禁"
    else return "无" end
end

--- 管理员: 获取当前封禁名单 (从排行榜读取自己发布的)
---@param callback fun(bans: table|nil, err: string|nil)
function CloudManager.AdminGetBanList(callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback(nil, "clientCloud不可用") end
        return
    end
    local myUid = clientCloud.userId
    clientCloud:Get(KEYS.ban_data, {
        ok = function(values)
            local data = values and values[KEYS.ban_data]
            if type(data) == "table" and type(data.bans) == "table" then
                if callback then callback(data.bans, nil) end
            else
                if callback then callback({}, nil) end
            end
        end,
        error = function(_, reason)
            if callback then callback(nil, tostring(reason)) end
        end,
    })
end

--- 管理员: 发布封禁名单 (覆盖式写入)
--- bans 格式: { ["uid_str"] = { level=1-3, reason="...", until=0 }, ... }
---@param bans table 封禁名单
---@param callback fun(ok: boolean, err: string|nil)
function CloudManager.AdminPublishBanList(bans, callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "clientCloud不可用") end
        return
    end
    local ts = os.time()
    clientCloud:BatchSet()
        :SetInt(KEYS.ban_ts, ts)
        :Set(KEYS.ban_data, { bans = bans, updated = ts })
        :Save("admin_ban_update", {
            ok = function()
                print("[管理员] 封禁名单已发布, 条目数: " .. CloudManager._tableCount(bans))
                if callback then callback(true, nil) end
            end,
            error = function(_, reason)
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

--- 管理员: 将排行榜分数设为极小值来隐藏 (SetInt 设为 -999999)
---@param targetUid number 目标玩家UID
---@param callback fun(ok: boolean, msg: string)
function CloudManager.AdminHidePlayerRank(targetUid, callback)
    -- 注意: clientCloud 只能操作自己的数据, 无法直接删除他人排行榜
    -- 隐藏策略: 将该 UID 加入本地隐藏列表, 在排行榜渲染时过滤
    if not CloudManager._hiddenPlayers then
        CloudManager._hiddenPlayers = {}
    end
    CloudManager._hiddenPlayers[tostring(targetUid)] = true
    -- 持久化到 ban_data 中
    CloudManager.AdminGetBanList(function(bans, err)
        if not bans then bans = {} end
        local uidStr = tostring(targetUid)
        if not bans[uidStr] then
            bans[uidStr] = { level = 0, reason = "排行榜隐藏", ["until"] = 0 }
        end
        bans[uidStr].rankHidden = true
        CloudManager.AdminPublishBanList(bans, function(ok)
            if callback then callback(ok, ok and "已隐藏" or "操作失败") end
        end)
    end)
end

--- 管理员: 恢复玩家排行榜显示
---@param targetUid number
---@param callback fun(ok: boolean, msg: string)
function CloudManager.AdminUnhidePlayerRank(targetUid, callback)
    if CloudManager._hiddenPlayers then
        CloudManager._hiddenPlayers[tostring(targetUid)] = nil
    end
    CloudManager.AdminGetBanList(function(bans, err)
        if not bans then bans = {} end
        local uidStr = tostring(targetUid)
        if bans[uidStr] then
            bans[uidStr].rankHidden = nil
            -- 如果这条记录只有 rankHidden, level=0, 那就删掉整条
            if (bans[uidStr].level or 0) == 0 then
                bans[uidStr] = nil
            end
        end
        CloudManager.AdminPublishBanList(bans, function(ok)
            if callback then callback(ok, ok and "已恢复显示" or "操作失败") end
        end)
    end)
end

--- 检查某个玩家是否被隐藏排行榜
---@param uid number|string
---@return boolean
function CloudManager.IsPlayerRankHidden(uid)
    if not CloudManager._hiddenPlayers then return false end
    return CloudManager._hiddenPlayers[tostring(uid)] == true
end

--- 管理员: 获取封禁名单摘要（供 UI 列表展示）
--- 返回两个数组: tempBans(暂时封禁), permBans(永久封禁/已删除)
---@param callback fun(tempBans: table, permBans: table, err: string|nil)
function CloudManager.AdminGetBanListSummary(callback)
    CloudManager.AdminGetBanList(function(bans, err)
        if err then
            if callback then callback({}, {}, err) end
            return
        end
        local tempList = {}
        local permList = {}
        for uidStr, info in pairs(bans or {}) do
            if type(info) == "table" then
                local entry = {
                    uid = uidStr,
                    level = info.level or 0,
                    reason = info.reason or "",
                    rankHidden = info.rankHidden or false,
                    permanent = info.permanent or false,
                }
                if info.permanent then
                    table.insert(permList, entry)
                elseif (info.level or 0) > 0 or info.rankHidden then
                    table.insert(tempList, entry)
                end
            end
        end
        -- 按 UID 排序
        table.sort(tempList, function(a, b) return a.uid < b.uid end)
        table.sort(permList, function(a, b) return a.uid < b.uid end)
        if callback then callback(tempList, permList, nil) end
    end)
end

--- 管理员: 永久封禁（标记为已删除，全面封禁 + 排行榜隐藏）
---@param targetUid number|string 目标UID
---@param callback fun(ok: boolean, msg: string)
function CloudManager.AdminPermanentBan(targetUid, callback)
    local uidStr = tostring(targetUid)
    -- 加入隐藏列表
    if not CloudManager._hiddenPlayers then CloudManager._hiddenPlayers = {} end
    CloudManager._hiddenPlayers[uidStr] = true

    CloudManager.AdminGetBanList(function(bans, err)
        if not bans then bans = {} end
        bans[uidStr] = bans[uidStr] or {}
        bans[uidStr].level = 3          -- BAN_LEVEL_FULL
        bans[uidStr].reason = "永久封禁(数据已删除)"
        bans[uidStr]["until"] = 0       -- 永久
        bans[uidStr].rankHidden = true  -- 隐藏排行榜
        bans[uidStr].permanent = true   -- 标记为永久封禁
        CloudManager.AdminPublishBanList(bans, function(ok)
            if callback then callback(ok, ok and "已永久封禁" or "操作失败") end
        end)
    end)
end

--- 管理员: 将暂时封禁恢复（完全解禁，包括排行榜）
---@param targetUid number|string
---@param callback fun(ok: boolean, msg: string)
function CloudManager.AdminFullUnban(targetUid, callback)
    local uidStr = tostring(targetUid)
    -- 移出隐藏列表
    if CloudManager._hiddenPlayers then
        CloudManager._hiddenPlayers[uidStr] = nil
    end

    CloudManager.AdminGetBanList(function(bans, err)
        if not bans then bans = {} end
        bans[uidStr] = nil  -- 完全移除
        CloudManager.AdminPublishBanList(bans, function(ok)
            if callback then callback(ok, ok and "已完全解禁" or "操作失败") end
        end)
    end)
end

--- 内部工具: 计算table元素数
function CloudManager._tableCount(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

-- ============================================================================
-- 频率限制
-- ============================================================================

--- 检查操作冷却 (通过返回true/false表示是否可执行)
--- 如果可执行, 同时更新时间戳
---@param action string 操作名称
---@param cooldownSeconds number 冷却秒数
---@return boolean 是否允许执行
function CloudManager._checkCooldown(action, cooldownSeconds)
    local now = os.time()
    local lastTime = cooldownTimestamps[action] or 0
    if (now - lastTime) < cooldownSeconds then
        return false
    end
    cooldownTimestamps[action] = now
    return true
end

--- 获取操作剩余冷却时间
---@param action string
---@param cooldownSeconds number
---@return number 剩余秒数 (0=可执行)
function CloudManager.GetCooldownRemaining(action, cooldownSeconds)
    local now = os.time()
    local lastTime = cooldownTimestamps[action] or 0
    local elapsed = now - lastTime
    if elapsed >= cooldownSeconds then return 0 end
    return cooldownSeconds - elapsed
end

-- ============================================================================
-- 负值防护
-- ============================================================================

--- 清理关键资源的负值 (防止作弊/数据异常)
function CloudManager._sanitizeResources()
    if not rawget(_G, "playerInfo") then return end
    local pi = playerInfo
    -- 虎符 (jade)
    if (pi.jade or 0) < 0 then
        print("[安全] 虎符为负值(" .. tostring(pi.jade) .. "), 强制归零")
        pi.jade = 0
    end
    -- 灵石 (lingshi)
    if (pi.lingshi or 0) < 0 then
        print("[安全] 灵石为负值(" .. tostring(pi.lingshi) .. "), 强制归零")
        pi.lingshi = 0
    end
    -- 经验 (exp)
    if (pi.exp or 0) < 0 then
        print("[安全] 经验为负值(" .. tostring(pi.exp) .. "), 强制归零")
        pi.exp = 0
    end
    -- 等级 (rankIdx)
    if (pi.rankIdx or 1) < 1 then
        print("[安全] 等级为负值(" .. tostring(pi.rankIdx) .. "), 强制归1")
        pi.rankIdx = 1
        pi.level = 1
    end
    -- 深渊门票
    if (pi.abyssTickets or 0) < 0 then
        print("[安全] 深渊门票为负值, 强制归零")
        pi.abyssTickets = 0
    end
end

-- ============================================================================
-- 存档哈希校验
-- ============================================================================

--- 计算存档哈希 (简单混淆校验, 非加密级别)
--- 原理: 提取关键字段 → 数值求和 → 混合uid和secret → 取模得到校验值
---@param allData table 所有domain数据 (或domain名→data的映射)
---@return number hash值
function CloudManager._computeSaveHash(allData)
    local uid = 0
    if rawget(_G, "clientCloud") then
        uid = clientCloud.userId or 0
    end

    local sum = 0

    -- 从 core 提取关键字段
    local coreData = allData.core or allData[DOMAINS.core]
    if coreData and coreData.playerInfo then
        local pi = coreData.playerInfo
        sum = sum + (pi.jade or 0)
        sum = sum + (pi.lingshi or 0)
        sum = sum + (pi.rankIdx or 0) * 137
        sum = sum + (pi.totalBattles or 0) * 7
        sum = sum + (pi.totalWins or 0) * 13
        sum = sum + (pi.totalGachas or 0) * 31
        sum = sum + (pi.totalEquips or 0) * 17
        sum = sum + (pi.exp or 0)
    end

    -- 从 progress 提取
    local progData = allData.progress or allData[DOMAINS.progress]
    if progData then
        sum = sum + (progData.stageMaxUnlocked or 0) * 53
        sum = sum + (progData.towerHighestFloor or 0) * 41
        sum = sum + (progData.rankedHighestScore or 0) * 3
    end

    -- 混合 uid 和 secret
    local mixed = (uid * HASH_SEED + sum) ~ HASH_SECRET
    -- 确保正整数 (Lua 5.4 整数可能为负)
    if mixed < 0 then mixed = -mixed end
    return mixed % 999999937  -- 大素数取模
end

--- 检查存档哈希是否不匹配
---@return boolean true=哈希不匹配(可能被篡改)
function CloudManager.IsHashMismatch()
    return CloudManager._hashMismatch == true
end

-- ============================================================================
-- 阵营职位查询 (导出供外部使用)
-- ============================================================================

--- 导出职位定义表 (供UI渲染用)
CloudManager.FACTION_ROLES = FACTION_ROLES

--- 获取指定角色的中文名
---@param role string
---@return string
function CloudManager.GetRoleName(role)
    return _getRoleName(role)
end

--- 获取指定角色的等级
---@param role string
---@return number
function CloudManager.GetRoleLevel(role)
    return _getRoleLevel(role)
end

--- 获取所有可分配职位列表 (不含 leader, 供UI下拉框用)
---@return table[] { id, name, level, max }
function CloudManager.GetAssignableRoles()
    local result = {}
    for _, roleName in ipairs(ROLE_SUCCESSION) do
        local def = FACTION_ROLES[roleName]
        result[#result + 1] = {
            id = roleName,
            name = def.name,
            level = def.level,
            max = def.max,
        }
    end
    return result
end

--- 获取阵营成员的职位信息 (带中文名)
---@param userId number
---@return string role, string roleName
function CloudManager.GetMemberRole(userId)
    local meta = CloudManager._factionMeta
    if not meta or not meta.roles then
        return "member", "成员"
    end
    local role = meta.roles[tostring(userId)] or "member"
    return role, _getRoleName(role)
end

--- 获取职位等级数值 (数字越大权限越高, leader=6, member=0)
function CloudManager.GetRoleLevel(role)
    return _getRoleLevel(role)
end

-- ============================================================================
-- 邮件系统 (公共信箱模式: 发件人写 outbox, 收件人轮询扫描)
-- ============================================================================

local MAIL_MAX_OUTBOX = 20         -- 每人发件箱最多保留20封
local MAIL_EXPIRE_DAYS = 7        -- 邮件7天过期
local MAIL_POLL_CD = 30           -- 轮询冷却秒数

CloudManager._mailOutbox = {}     -- 本地发件箱缓存
CloudManager._mailOutboxLoaded = false -- 是否已从云端加载过发件箱
CloudManager._mailInbox = {}      -- 扫描到的收件列表
CloudManager._mailLastPoll = 0    -- 上次轮询时间
CloudManager._mailLoading = false
CloudManager._mailClaimed = {}    -- 已领取的邮件ID集合 {[mailId]=true}
CloudManager.ADMIN_UIDS = {}      -- 管理员UID列表, 由 main.lua 设置

--- 从云端加载已有发件箱（防止重启后覆盖）
---@param callback? fun(ok:boolean)
function CloudManager.LoadMailOutbox(callback)
    if CloudManager._mailOutboxLoaded then
        if callback then callback(true) end
        return
    end
    if not rawget(_G, "clientCloud") then
        if callback then callback(false) end
        return
    end
    clientCloud:BatchGet()
        :Key(KEYS.mail_outbox)
        :Fetch({
            ok = function(values, iscores)
                local outbox = values and values[KEYS.mail_outbox]
                if outbox and type(outbox) == "table" then
                    -- 过滤过期邮件
                    local now = os.time()
                    local kept = {}
                    for _, m in ipairs(outbox) do
                        if (now - (m.time or 0)) < MAIL_EXPIRE_DAYS * 86400 then
                            kept[#kept + 1] = m
                        end
                    end
                    CloudManager._mailOutbox = kept
                    print("[邮件] 云端发件箱加载成功: " .. #kept .. " 封")
                else
                    CloudManager._mailOutbox = {}
                    print("[邮件] 云端发件箱为空")
                end
                CloudManager._mailOutboxLoaded = true
                if callback then callback(true) end
            end,
            error = function(_, reason)
                print("[邮件] 云端发件箱加载失败: " .. tostring(reason))
                -- 加载失败也标记，避免反复重试阻塞发信
                CloudManager._mailOutboxLoaded = true
                if callback then callback(false) end
            end,
        })
end

--- 发送邮件给指定玩家
---@param targetUid number 目标玩家 UID
---@param subject string 标题
---@param body string 正文
---@param rewards? table 附件奖励 [{type,amount,label}] (仅管理员可发)
---@param callback? fun(ok:boolean, msg:string)
function CloudManager.SendMail(targetUid, subject, body, rewards, callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback(false, "云端不可用") end
        return
    end

    -- 如果发件箱未从云端加载过，先加载再发送（防止覆盖旧邮件）
    if not CloudManager._mailOutboxLoaded then
        print("[邮件] 发件箱未加载，先从云端加载...")
        CloudManager.LoadMailOutbox(function(ok)
            -- 无论加载成功失败都继续发送
            CloudManager.SendMail(targetUid, subject, body, rewards, callback)
        end)
        return
    end

    local myUid = clientCloud.userId
    local myName = rawget(_G, "playerInfo") and playerInfo.name or ("玩家" .. tostring(myUid))

    -- 只有管理员可以发带奖励的邮件
    if rewards and #rewards > 0 then
        if not CloudManager.IsAdmin() then
            if callback then callback(false, "只有管理员可以发送奖励邮件") end
            return
        end
    end

    local mailId = tostring(myUid) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local mailItem = {
        id = mailId,
        to = targetUid,
        from = myUid,
        fromName = myName,
        subject = subject,
        body = body,
        rewards = rewards or {},
        time = os.time(),
    }

    -- 加入本地发件箱
    table.insert(CloudManager._mailOutbox, 1, mailItem)
    -- 裁剪过多 / 过期
    local now = os.time()
    local kept = {}
    for i, m in ipairs(CloudManager._mailOutbox) do
        if i <= MAIL_MAX_OUTBOX and (now - m.time) < MAIL_EXPIRE_DAYS * 86400 then
            kept[#kept + 1] = m
        end
    end
    CloudManager._mailOutbox = kept

    -- 上传到云端
    clientCloud:BatchSet()
        :SetInt(KEYS.mail_ts, os.time())
        :Set(KEYS.mail_outbox, CloudManager._mailOutbox)
        :Save("发送邮件", {
            ok = function()
                print("[邮件] 发送成功 → " .. tostring(targetUid) .. ": " .. subject)
                if callback then callback(true, "发送成功") end
            end,
            error = function(_, reason)
                print("[邮件] 发送失败: " .. tostring(reason))
                if callback then callback(false, tostring(reason)) end
            end,
        })
end

--- 广播邮件 (管理员向所有人发)
---@param subject string 标题
---@param body string 正文
---@param rewards? table 附件奖励
---@param callback? fun(ok:boolean, msg:string)
function CloudManager.BroadcastMail(subject, body, rewards, callback)
    if not CloudManager.IsAdmin() then
        if callback then callback(false, "仅管理员可广播") end
        return
    end
    -- to=0 表示广播给所有人
    CloudManager.SendMail(0, subject, body, rewards, callback)
end

--- 轮询收件箱 (扫描所有玩家的 outbox, 过滤发给自己的)
---@param callback? fun(mails:table)
function CloudManager.PollInbox(callback)
    if not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end
    local now = os.time()
    if now - CloudManager._mailLastPoll < MAIL_POLL_CD and #CloudManager._mailInbox > 0 then
        if callback then callback(CloudManager._mailInbox) end
        return
    end
    if CloudManager._mailLoading then
        if callback then callback(CloudManager._mailInbox) end
        return
    end
    CloudManager._mailLoading = true
    local myUid = clientCloud.userId

    clientCloud:GetRankList(KEYS.mail_ts, 0, 200, {
        ok = function(rankList)
            local inbox = {}
            local expireThreshold = now - MAIL_EXPIRE_DAYS * 86400
            for _, entry in ipairs(rankList) do
                local senderId = entry.player or entry.userId
                local outbox = entry.score and entry.score[KEYS.mail_outbox]
                if outbox and type(outbox) == "table" then
                    for _, m in ipairs(outbox) do
                        -- to==myUid 或 to==0(广播)
                        if (m.to == myUid or m.to == 0) and (m.time or 0) > expireThreshold then
                            -- 广播邮件不显示自己发给自己的
                            if not (m.to == 0 and m.from == myUid) then
                                inbox[#inbox + 1] = {
                                    id = m.id,
                                    from = m.from or senderId,
                                    fromName = m.fromName or ("玩家" .. tostring(senderId)),
                                    subject = m.subject or "",
                                    body = m.body or "",
                                    rewards = m.rewards or {},
                                    time = m.time or 0,
                                    isBroadcast = (m.to == 0),
                                }
                            end
                        end
                    end
                end
            end
            -- 按时间降序
            table.sort(inbox, function(a, b) return a.time > b.time end)
            CloudManager._mailInbox = inbox
            CloudManager._mailLastPoll = now
            CloudManager._mailLoading = false
            print("[邮件] 收件箱刷新: " .. #inbox .. " 封")
            if callback then callback(inbox) end
        end,
        error = function(_, reason)
            CloudManager._mailLoading = false
            print("[邮件] 收件箱刷新失败: " .. tostring(reason))
            if callback then callback(CloudManager._mailInbox) end
        end,
    }, KEYS.mail_outbox)
end

--- 强制刷新收件箱 (重置冷却)
function CloudManager.ForceRefreshInbox(callback)
    CloudManager._mailLastPoll = 0
    CloudManager.PollInbox(callback)
end

--- 判断当前玩家是否为管理员
---@return boolean
function CloudManager.IsAdmin()
    if not rawget(_G, "clientCloud") then return false end
    local ADMIN_UIDS = CloudManager.ADMIN_UIDS or {}
    local myUid = clientCloud.userId
    for _, uid in ipairs(ADMIN_UIDS) do
        if uid == myUid then return true end
    end
    return false
end

--- 标记邮件已领取
---@param mailId string
function CloudManager.ClaimMail(mailId)
    CloudManager._mailClaimed[mailId] = true
end

--- 检查邮件是否已领取
---@param mailId string
---@return boolean
function CloudManager.IsMailClaimed(mailId)
    return CloudManager._mailClaimed[mailId] == true
end

return CloudManager
