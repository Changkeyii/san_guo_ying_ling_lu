-- ============================================================================
-- systems/gacha.lua - 三国武灵录
-- ============================================================================


--- 检查是否有至少1个满命武灵 (解锁兵符召唤的条件)
function HasMaxConstellationHero()
    for idx, hero in pairs(playerHeroes) do
        if hero and (hero.constellation or 0) >= GameConfig.MAX_CONSTELLATION then
            return true
        end
    end
    return false
end


--- 获取当前抽卡Tab对应的功能类型
--- @return string "hero"|"skill"|"seal"|"limited"
function GetGachaTabType()
    local tab = gachaState.currentTab
    local hasSeal = HasMaxConstellationHero()
    if tab == 1 then return "hero" end
    if tab == 2 then return "skill" end
    if hasSeal then
        if tab == 3 then return "seal" end
        if tab == 4 then return "limited" end
    else
        if tab == 3 then return "limited" end
    end
    return "hero"
end


--- 获取限定Tab的索引值 (用于Tab高亮判定)
function GetLimitedTabIndex()
    return HasMaxConstellationHero() and 4 or 3
end


--- 获取所有满命武灵列表 (用于兵符管理)
function GetMaxConstellationHeroes()
    local list = {}
    if not HERO_CARDS then return list end
    for idx, hero in pairs(playerHeroes) do
        if hero and (hero.constellation or 0) >= GameConfig.MAX_CONSTELLATION then
            local card = HERO_CARDS[idx]
            if card then
                table.insert(list, { cardIdx = idx, name = card.name, quality = card.quality })
            end
        end
    end
    table.sort(list, function(a, b) return a.cardIdx < b.cardIdx end)
    return list
end


-- ============================================================================
-- 抽卡系统 (广告驱动)
-- ============================================================================

--- 按权重随机选一张卡的 cardIdx
function RandomDrawCard()
    -- 1. 按品质概率表决定本次抽到哪个品质
    local weights = GameConfig.DRAW_QUALITY_WEIGHTS
    local totalW = 0
    for q = 1, 4 do totalW = totalW + (weights[q] or 0) end

    local r = math.random() * totalW
    local cumW = 0
    local targetQuality = 1
    for q = 1, 4 do
        cumW = cumW + (weights[q] or 0)
        if r <= cumW then
            targetQuality = q
            break
        end
    end

    -- 2. 从该品质的武灵中随机选一个
    -- 教程期间排除初始武灵 (确保抽到新角色)
    local excludeSet = nil
    if tutorialState.active then
        excludeSet = {}
        for _, id in ipairs(GameConfig.INITIAL_HEROES) do
            excludeSet[id] = true
        end
    end

    local pool = {}
    for idx, card in ipairs(HERO_CARDS) do
        if card.quality == targetQuality then
            if not excludeSet or not excludeSet[idx] then
                table.insert(pool, idx)
            end
        end
    end

    -- 安全回退: 若该品质无武灵，从全池中选(排除初始武灵和限定SSR)
    if #pool == 0 then
        for idx, card in ipairs(HERO_CARDS) do
            if card.quality ~= QUALITY.LIMITED then
                if not excludeSet or not excludeSet[idx] then
                    table.insert(pool, idx)
                end
            end
        end
    end

    if #pool == 0 then
        -- 极端回退: 从非限定池中随机
        local safePool = {}
        for idx, card in ipairs(HERO_CARDS) do
            if card.quality ~= QUALITY.LIMITED then table.insert(safePool, idx) end
        end
        if #safePool > 0 then return safePool[math.random(1, #safePool)] end
        return math.random(1, #HERO_CARDS)
    end

    return pool[math.random(1, #pool)]
end


--- 执行抽卡 (count 次, 消耗虎符, 残片/整卡混合产出)
--- 大概率出残片(1~5个), 极小概率出整卡
--- @param count number 抽卡次数 (1 或 10)
--- @param forceCardIdx number|nil 强制指定出整卡(新手引导用)
function ExecuteGachaPull(count, forceCardIdx)
    local cost
    if count >= 10 then
        cost = math.floor(GameConfig.GACHA_COST_SINGLE * count * 0.9)  -- 10连及以上享9折
    else
        cost = GameConfig.GACHA_COST_SINGLE * count
    end
    if playerInfo.jade < cost then
        AddFloatText(DESIGN_W / 2, DESIGN_H * 0.45, "虎符不足!", 1.2, { 255, 100, 100 }, 14)
        return false
    end

    playerInfo.jade = playerInfo.jade - cost
    gachaState.results = {}

    local totalJadeRefund = 0

    for pullI = 1, count do
        gachaState.pityCounter = gachaState.pityCounter + 1

        -- 决定本次抽取的武灵
        local cardIdx
        local isPityTriggered = false  -- 75抽保底是否触发
        local isFullCardForced = false -- 保底强制整卡标记
        if forceCardIdx and pullI == 1 then
            -- 新手引导强制指定
            cardIdx = forceCardIdx
            isFullCardForced = true
        elseif gachaState.pityCounter >= GameConfig.PITY_SSR_COUNT then
            -- ★ 75抽保底: 必出整卡, 普通:SSR = 7:3 (排除限定SSR)
            isPityTriggered = true
            local roll = math.random(1, 10)
            if roll <= 3 then
                -- 30% SSR整卡 (仅普通SSR, 排除限定)
                local ssrCards = {}
                for ci, c in ipairs(HERO_CARDS) do
                    if c.quality == QUALITY.LEGENDARY then table.insert(ssrCards, ci) end
                end
                cardIdx = ssrCards[math.random(1, #ssrCards)]
            else
                -- 70% 普通整卡(非SSR, 排除限定SSR)
                local normalCards = {}
                for ci, c in ipairs(HERO_CARDS) do
                    if c.quality ~= QUALITY.LEGENDARY and c.quality ~= QUALITY.LIMITED then
                        table.insert(normalCards, ci)
                    end
                end
                cardIdx = normalCards[math.random(1, #normalCards)]
            end
            isFullCardForced = true
            gachaState.pityCounter = 0  -- 保底触发立即重置
            print("[抽卡] 75抽保底触发! 强制出整卡(普通:SSR=7:3, roll=" .. roll .. ")")
        else
            cardIdx = RandomDrawCard()
        end

        local card = HERO_CARDS[cardIdx]

        -- 判断是出整卡还是残片
        local isFullCard = false
        if isFullCardForced then
            -- 保底/新手引导: 强制整卡
            isFullCard = true
        else
            -- 正常抽取: HERO_FULL_CARD_RATE% 概率整卡
            isFullCard = (math.random(1, 100) <= HERO_FULL_CARD_RATE)
        end

        if isFullCard then
            -- ★ 整卡产出
            local hero = playerHeroes[cardIdx]
            local result = {
                cardIdx = cardIdx, isFullCard = true, fragCount = 0,
                isNew = false, oldConst = 0, constellation = 0, jadeRefund = 0,
            }
            if hero and hero.owned then
                result.oldConst = hero.constellation
                if hero.constellation >= GameConfig.MAX_CONSTELLATION then
                    local refund = GameConfig.DUPLICATE_JADE_REWARD[card.quality] or 1
                    result.jadeRefund = refund
                    totalJadeRefund = totalJadeRefund + refund
                    result.constellation = hero.constellation
                else
                    hero.constellation = hero.constellation + 1
                    result.constellation = hero.constellation
                end
            else
                playerHeroes[cardIdx] = { owned = true, constellation = 0 }
                result.isNew = true
                result.constellation = 0
            end
            table.insert(gachaState.results, result)

            -- 保底重置已在触发时处理; 非保底情况下不额外重置
        else
            -- ★ 残片产出: 1~5个残片
            local fragCount = math.random(1, 5)
            heroFragments[cardIdx] = (heroFragments[cardIdx] or 0) + fragCount
            local result = {
                cardIdx = cardIdx, isFullCard = false, fragCount = fragCount,
                totalFrags = heroFragments[cardIdx],
                isNew = false, oldConst = 0, constellation = 0, jadeRefund = 0,
            }
            table.insert(gachaState.results, result)
        end
    end

    -- 返还满命格重复角色的虎符
    if totalJadeRefund > 0 then
        playerInfo.jade = playerInfo.jade + totalJadeRefund
        AddFloatText(DESIGN_W / 2, DESIGN_H * 0.38, "满命格返还 " .. totalJadeRefund .. " 虎符!", 1.5, { 255, 215, 0 }, 16)
    end

    -- 启动召唤动画
    gachaState.pulling = true
    gachaState.pullTimer = 0
    gachaState.pullCount = count
    gachaState.showResults = false

    -- 任务追踪
    playerInfo.totalGachas = playerInfo.totalGachas + count
    TrackDailyTask("gacha1", count)
    TrackWeeklyTask("wgacha5", count)
    TrackBattlePassTask("bp_gacha1", count)
    TrackBattlePassTask("bp_wgacha5", count)
    TrackBattlePassTask("bp_sgacha30", count)

    print("[抽卡] 消耗 " .. cost .. " 虎符, 抽取 " .. count .. " 次")
    return true
end


-- ============================================================================
-- 限定池抽取 (只出碎片, 无整卡, 限定SSR碎片唯一来源)
-- ============================================================================

--- 限定池随机抽取: 按 LIMITED_DRAW_WEIGHTS 决定品质, 然后随机该品质武灵
function RandomDrawLimitedCard()
    local weights = LIMITED_DRAW_WEIGHTS
    local totalW = 0
    for q = 1, 5 do totalW = totalW + (weights[q] or 0) end

    local r = math.random() * totalW
    local cumW = 0
    local targetQuality = 2  -- 默认R
    for q = 1, 5 do
        cumW = cumW + (weights[q] or 0)
        if r <= cumW then
            targetQuality = q
            break
        end
    end

    local pool = {}
    for idx, card in ipairs(HERO_CARDS) do
        if card.quality == targetQuality then
            table.insert(pool, idx)
        end
    end

    -- 安全回退
    if #pool == 0 then
        for idx, card in ipairs(HERO_CARDS) do
            if card.quality >= QUALITY.RARE then
                table.insert(pool, idx)
            end
        end
    end
    if #pool == 0 then return math.random(1, #HERO_CARDS) end
    return pool[math.random(1, #pool)]
end


--- 执行限定池抽取 (全碎片产出, 30抽保底限定碎片)
--- @param count number 抽取次数 (1 或 10)
function ExecuteLimitedGachaPull(count)
    local cost
    if count >= 10 then
        cost = math.floor(LIMITED_GACHA_COST * count * 0.9)  -- 10连及以上享9折
    else
        cost = LIMITED_GACHA_COST * count
    end
    if playerInfo.jade < cost then
        AddFloatText(DESIGN_W / 2, DESIGN_H * 0.45, "虎符不足!", 1.2, { 255, 100, 100 }, 14)
        return false
    end

    playerInfo.jade = playerInfo.jade - cost
    gachaState.limitedResults = {}

    local totalJadeRefund = 0

    for pullI = 1, count do
        gachaState.limitedPityCounter = gachaState.limitedPityCounter + 1

        local cardIdx
        local isPityTriggered = false

        -- 30抽保底: 必出限定SSR碎片
        if gachaState.limitedPityCounter >= LIMITED_PITY_FRAG_COUNT then
            isPityTriggered = true
            -- 从限定SSR池中随机
            local limitedPool = {}
            for idx, card in ipairs(HERO_CARDS) do
                if card.quality == QUALITY.LIMITED then
                    table.insert(limitedPool, idx)
                end
            end
            cardIdx = #limitedPool > 0 and limitedPool[math.random(1, #limitedPool)] or RandomDrawLimitedCard()
            print("[限定池] 保底触发! 必出限定SSR碎片")
        else
            cardIdx = RandomDrawLimitedCard()
        end

        local card = HERO_CARDS[cardIdx]

        -- 限定池只出碎片, 无整卡
        local fragCount
        if isPityTriggered then
            fragCount = math.random(LIMITED_FRAG_GUARANTEE_MIN, LIMITED_FRAG_GUARANTEE_MAX)  -- 保底给6~8碎片
        elseif card.quality == QUALITY.LIMITED then
            fragCount = math.random(3, 6)  -- 限定SSR碎片多给
        elseif card.quality == QUALITY.LEGENDARY then
            fragCount = math.random(2, 5)  -- SSR碎片
        else
            fragCount = math.random(1, 4)  -- 普通碎片
        end

        heroFragments[cardIdx] = (heroFragments[cardIdx] or 0) + fragCount

        local result = {
            cardIdx = cardIdx, isFullCard = false, fragCount = fragCount,
            totalFrags = heroFragments[cardIdx],
            isNew = false, oldConst = 0, constellation = 0, jadeRefund = 0,
            isPity = isPityTriggered,
        }
        table.insert(gachaState.limitedResults, result)

        -- 保底重置
        if isPityTriggered or card.quality == QUALITY.LIMITED then
            gachaState.limitedPityCounter = 0
        end
    end

    -- 启动召唤动画 (复用武灵池动画)
    gachaState.pulling = true
    gachaState.pullTimer = 0
    gachaState.pullCount = count
    gachaState.showResults = false

    -- 任务追踪
    playerInfo.totalGachas = playerInfo.totalGachas + count
    TrackDailyTask("gacha1", count)
    TrackWeeklyTask("wgacha5", count)
    TrackBattlePassTask("bp_gacha1", count)
    TrackBattlePassTask("bp_wgacha5", count)
    TrackBattlePassTask("bp_sgacha30", count)

    print("[限定池] 消耗 " .. cost .. " 虎符, 抽取 " .. count .. " 次")
    return true
end


--- 战斗胜利掉落武技残片 (按关卡maxTier影响掉落品质)
--- @param maxTier number 关卡最高掉落阶级(1-6)
--- @return table[] fragDrops 掉落列表 { {skillIdx, skillName, tierName, tierColor} ... }
function GenerateBattleSkillFragDrop(maxTier)
    local fragDrops = {}
    -- 掉落数量: 1-3个残片, 高关卡倾向更多
    local dropCount = 1
    local roll = math.random(1, 100)
    if maxTier >= 4 then
        dropCount = roll <= 40 and 3 or (roll <= 75 and 2 or 1)
    elseif maxTier >= 2 then
        dropCount = roll <= 30 and 2 or 1
    end
    for _ = 1, dropCount do
        -- 构建受maxTier影响的权重池: 关卡越高, 高阶残片权重略增
        local pool = {}
        local totalW = 0
        for idx, tech in ipairs(SKILL_TECHNIQUES) do
            local baseW = SKILL_FRAG_WEIGHTS[tech.tier] or 10
            -- maxTier以下的阶级保持原权重, 以上的轻微提升
            if tech.tier <= maxTier then
                baseW = baseW + math.floor(maxTier * 0.5)
            end
            totalW = totalW + baseW
            table.insert(pool, { idx = idx, weight = baseW, cumWeight = totalW })
        end
        local r = math.random() * totalW
        local chosen = pool[1].idx
        for _, p in ipairs(pool) do
            if r <= p.cumWeight then chosen = p.idx; break end
        end
        skillFragments[chosen] = (skillFragments[chosen] or 0) + 1
        local tech = SKILL_TECHNIQUES[chosen]
        local tier = SKILL_TIERS[tech.tier]
        table.insert(fragDrops, {
            skillIdx = chosen,
            skillName = tech.name,
            tierName = tier.name,
            tierColor = tier.color,
        })
    end
    return fragDrops
end


--- 按权重随机选一个武技
function RandomDrawSkillFragment()
    -- 构建权重池
    local pool = {}
    local totalWeight = 0
    for idx, tech in ipairs(SKILL_TECHNIQUES) do
        local w = SKILL_FRAG_WEIGHTS[tech.tier] or 10
        totalWeight = totalWeight + w
        table.insert(pool, { idx = idx, weight = w, cumWeight = totalWeight })
    end
    local roll = math.random() * totalWeight
    for _, entry in ipairs(pool) do
        if roll <= entry.cumWeight then
            return entry.idx
        end
    end
    return 1
end


--- 执行武技残片抽取 (count=1单抽出5个残片, count=10十连出50个残片)
function ExecuteSkillGachaPull(count)
    local cost
    if count >= 10 then
        cost = math.floor(GameConfig.GACHA_COST_SINGLE * count * 0.9)  -- 10连及以上享9折
    else
        cost = GameConfig.GACHA_COST_SINGLE * count
    end
    if playerInfo.jade < cost then
        AddFloatText(DESIGN_W / 2, DESIGN_H * 0.45, "虎符不足!", 1.2, { 255, 100, 100 }, 14)
        return false
    end

    playerInfo.jade = playerInfo.jade - cost
    gachaState.skillResults = {}

    local totalFrags = SKILL_FRAG_PER_PULL * count  -- 单抽5个, 十连50个
    -- 随机抽出所有残片, 合并同类 (无保底, 纯概率)
    local fragMap = {}
    for _ = 1, totalFrags do
        local skillIdx = RandomDrawSkillFragment()
        fragMap[skillIdx] = (fragMap[skillIdx] or 0) + 1
    end

    -- 转为结果列表
    for skillIdx, fragCount in pairs(fragMap) do
        -- 累加到玩家残片库
        skillFragments[skillIdx] = (skillFragments[skillIdx] or 0) + fragCount
        table.insert(gachaState.skillResults, {
            skillIdx = skillIdx,
            fragCount = fragCount,
            totalFrags = skillFragments[skillIdx],
            isPity = false,
        })
    end
    -- 按tier从高到低排序（稀有的在前面）
    table.sort(gachaState.skillResults, function(a, b)
        local ta = SKILL_TECHNIQUES[a.skillIdx].tier
        local tb = SKILL_TECHNIQUES[b.skillIdx].tier
        if ta ~= tb then return ta > tb end
        return a.skillIdx < b.skillIdx
    end)

    -- 启动召唤动画
    gachaState.pulling = true
    gachaState.pullTimer = 0
    gachaState.pullCount = count
    gachaState.showResults = false

    -- 任务追踪
    playerInfo.totalGachas = playerInfo.totalGachas + count
    TrackDailyTask("gacha1", count)
    TrackWeeklyTask("wgacha5", count)
    TrackBattlePassTask("bp_gacha1", count)
    TrackBattlePassTask("bp_wgacha5", count)
    TrackBattlePassTask("bp_sgacha30", count)

    print("[武技抽取] 消耗 " .. cost .. " 虎符, 获得 " .. totalFrags .. " 个残片")
    return true
end


-- ============================================================================
-- 合成系统
-- ============================================================================

--- 在背包中查找可合成的配对 (同角色同命格, 且命格 < MAX)
function FindMergeableIndex(targetInvIdx)
    local item = inventory[targetInvIdx]
    if not item then return nil end
    if item.constellation >= GameConfig.MAX_CONSTELLATION then return nil end
    for i, other in ipairs(inventory) do
        if i ~= targetInvIdx and
           other.cardIdx == item.cardIdx and
           other.constellation == item.constellation then
            return i
        end
    end
    return nil
end


--- 检测某张背包卡是否可合成
function IsMergeable(invIdx)
    return FindMergeableIndex(invIdx) ~= nil
end


--- 执行合成: 两张同角色同命格 >> 一张更高命格
function TryMergeCard(invIdx)
    local pairIdx = FindMergeableIndex(invIdx)
    if not pairIdx then
        AddFloatText(DESIGN_W / 2, DESIGN_H * 0.85, "无法合成", 1.0, { 255, 120, 80 }, 13)
        return false
    end
    local item = inventory[invIdx]
    local newConst = item.constellation + 1
    local cardName = HERO_CARDS[item.cardIdx].name

    -- 移除配对 (先移除较大索引, 避免索引偏移)
    local removeFirst = math.max(invIdx, pairIdx)
    local removeSecond = math.min(invIdx, pairIdx)
    table.remove(inventory, removeFirst)
    table.remove(inventory, removeSecond)

    -- 添加新卡
    table.insert(inventory, { cardIdx = item.cardIdx, constellation = newConst })

    AddFloatText(DESIGN_W / 2, DESIGN_H * 0.85,
        cardName .. " >> C" .. newConst .. " !", 1.5, { 200, 160, 255 }, 15)
    print("[合成] " .. cardName .. " C" .. (newConst - 1) .. " >> C" .. newConst)
    return true
end
