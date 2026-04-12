-- ============================================================================
-- systems/stage.lua - 三国武灵录
-- ============================================================================


--- 应用战斗布局: 重设石台位置 + 切换背景
function ApplyBattleLayout(layoutIdx)
    layoutIdx = layoutIdx or 1
    local layout = BATTLE_LAYOUTS[layoutIdx] or BATTLE_LAYOUTS[1]
    currentLayoutIdx = layoutIdx
    for i, pos in ipairs(layout.playerSlots) do
        if PLAYER_SLOTS[i] then
            PLAYER_SLOTS[i].cx = pos[1] * BG2D_X
            PLAYER_SLOTS[i].cy = pos[2] * BG2D_Y
        end
    end
    for i, pos in ipairs(layout.enemySlots) do
        if ENEMY_SLOTS[i] then
            ENEMY_SLOTS[i].cx = pos[1] * BG2D_X
            ENEMY_SLOTS[i].cy = pos[2] * BG2D_Y
        end
    end
end


--- 导出布局配置到文件 (JSON 格式, 调好后告诉AI读取即可)
function ExportBattleLayouts()
    -- 构建导出数据
    local data = {}
    for li, layout in ipairs(BATTLE_LAYOUTS) do
        local entry = {
            name = layout.name,
            bg = layout.bg,
            playerSlots = {},
            enemySlots = {},
        }
        for _, pos in ipairs(layout.playerSlots) do
            entry.playerSlots[#entry.playerSlots + 1] = { pos[1], pos[2] }
        end
        for _, pos in ipairs(layout.enemySlots) do
            entry.enemySlots[#entry.enemySlots + 1] = { pos[1], pos[2] }
        end
        data[#data + 1] = entry
    end
    ---@diagnostic disable-next-line: undefined-global
    local cj = cjson
    local jsonStr = cj.encode(data)
    -- 写入文件
    local file = File(FILE_LAYOUTS, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
        print("[布局编辑器] 已导出到 battle_layouts.json")
    else
        print("[布局编辑器] 导出失败: 无法写入文件")
    end
    -- 打印到控制台
    print("[布局数据] " .. jsonStr)
end


--- 从 JSON 文件加载布局配置 (启动时调用)
function LoadBattleLayouts()
    if not fileSystem:FileExists(FILE_LAYOUTS) then return false end
    local file = File(FILE_LAYOUTS, FILE_READ)
    if not file:IsOpen() then return false end
    ---@diagnostic disable-next-line: undefined-global
    local cj = cjson
    local ok, data = pcall(cj.decode, file:ReadString())
    file:Close()
    if not ok or type(data) ~= "table" then return false end
    for li, entry in ipairs(data) do
        if BATTLE_LAYOUTS[li] then
            -- 更新已有布局
            if entry.name then BATTLE_LAYOUTS[li].name = entry.name end
            if entry.bg then BATTLE_LAYOUTS[li].bg = entry.bg end
            if entry.playerSlots then
                for si, pos in ipairs(entry.playerSlots) do
                    if type(pos) == "table" and pos[1] and pos[2] then
                        BATTLE_LAYOUTS[li].playerSlots[si] = { math.floor(pos[1]), math.floor(pos[2]) }
                    end
                end
            end
            if entry.enemySlots then
                for si, pos in ipairs(entry.enemySlots) do
                    if type(pos) == "table" and pos[1] and pos[2] then
                        BATTLE_LAYOUTS[li].enemySlots[si] = { math.floor(pos[1]), math.floor(pos[2]) }
                    end
                end
            end
        else
            -- 新增布局
            local newLayout = {
                name = entry.name or ("布局" .. li),
                bg = entry.bg or "image/battle_bg_1.png",
                bgHandle = nil,
                playerSlots = {},
                enemySlots = {},
            }
            if entry.playerSlots then
                for _, pos in ipairs(entry.playerSlots) do
                    if type(pos) == "table" and pos[1] and pos[2] then
                        newLayout.playerSlots[#newLayout.playerSlots + 1] = { math.floor(pos[1]), math.floor(pos[2]) }
                    end
                end
            end
            if entry.enemySlots then
                for _, pos in ipairs(entry.enemySlots) do
                    if type(pos) == "table" and pos[1] and pos[2] then
                        newLayout.enemySlots[#newLayout.enemySlots + 1] = { math.floor(pos[1]), math.floor(pos[2]) }
                    end
                end
            end
            BATTLE_LAYOUTS[#BATTLE_LAYOUTS + 1] = newLayout
        end
    end
    print("[布局编辑器] 已从 battle_layouts.json 加载 " .. #data .. " 个布局")
    return true
end


--- 撤销上一步石台拖拽
--- 撤销一步 (支持批量: 栈顶元素可以是单条 {layoutIdx,...} 或批量 {{layoutIdx,...}, ...})
function UndoSlotEdit()
    if #slotUndoStack == 0 then return false end
    local snap = slotUndoStack[#slotUndoStack]
    slotUndoStack[#slotUndoStack] = nil
    -- 批量快照: 数组中的每条恢复
    local entries = snap.batch or { snap }
    for _, s in ipairs(entries) do
        local layout = BATTLE_LAYOUTS[s.layoutIdx]
        if layout then
            local slots = s.slotType == "player" and layout.playerSlots or layout.enemySlots
            if slots[s.slotIdx] then
                slots[s.slotIdx][1] = s.oldX
                slots[s.slotIdx][2] = s.oldY
            end
        end
    end
    return true
end


-- ============================================================================
-- 排位: 辅助函数
-- ============================================================================
function GetRankedTier(score)
    local tier = RANKED_TIERS[1]
    for i = #RANKED_TIERS, 1, -1 do
        if score >= RANKED_TIERS[i].minScore then
            tier = RANKED_TIERS[i]
            tier.index = i
            return tier
        end
    end
    tier.index = 1
    return tier
end


function CalcRankedScoreChange(isWin, currentStreak)
    if isWin then
        local s = math.max(0, currentStreak)
        return math.min(30, 20 + s * 2)
    else
        local s = math.max(0, -currentStreak)
        return -math.max(10, 15 - s)
    end
end


--- 生成排位AI对手 (只用武灵HERO_CARDS, 武灵战力匹配玩家+-5%)
function GenerateRankedOpponent()
    -- 对手只有武灵，所以只匹配玩家的武灵维度战力
    local playerPower = CalcPlayerTotalPower()
    local nonHeroPower = CalcRankPowerScore() + CalcEquipPowerScore() + CalcSkillPowerScore()
    local playerHeroPower = math.max(1, playerPower - nonHeroPower)
    local targetMin = playerHeroPower * 0.95
    local targetMax = playerHeroPower * 1.05

    -- 1) 随机选 3-5 个武灵
    local cardCount = math.random(3, 5)
    local usedIdx = {}
    local picked = {}
    for i = 1, cardCount do
        local idx
        repeat idx = math.random(1, #HERO_CARDS) until not usedIdx[idx]
        usedIdx[idx] = true
        local card = DeepCopy(HERO_CARDS[idx])
        card.cardIdx = idx
        card.level = 1
        card.constellation = 0
        table.insert(picked, card)
    end

    -- 计算阵容战力 (与 CalcHeroPowerScore 同口径)
    local function calcLinePower(cards)
        local total = 0
        for _, c in ipairs(cards) do
            local lm = 1 + ((c.level or 1) - 1) * GameConfig.LEVEL_GROWTH_RATE
            local cStats = ApplyConstellationStats(c)
            total = total + (cStats.atk * 2 + cStats.def + cStats.hp * 0.1) * lm
        end
        return math.floor(total)
    end

    -- 2) 迭代升级逼近目标战力
    for _ = 1, 200 do
        local cur = calcLinePower(picked)
        if cur >= targetMin and cur <= targetMax then break end
        if cur >= targetMax then break end
        local ci = math.random(1, #picked)
        local c = picked[ci]
        if c.level < 10 and (c.constellation >= GameConfig.MAX_CONSTELLATION or math.random() < 0.7) then
            c.level = c.level + 1
        elseif c.constellation < GameConfig.MAX_CONSTELLATION then
            c.constellation = c.constellation + 1
        elseif c.level < 10 then
            c.level = c.level + 1
        end
    end

    -- 3) 微调: 如果超标则降级
    for _ = 1, 50 do
        local cur = calcLinePower(picked)
        if cur <= targetMax then break end
        local ci = math.random(1, #picked)
        local c = picked[ci]
        if c.level > 1 then
            c.level = c.level - 1
        elseif c.constellation > 0 then c.constellation = c.constellation - 1 end
    end

    -- 4) 烘焙属性到 base stats (SpawnEnemyUnit 直接用 card.atk*ss)
    for _, c in ipairs(picked) do
        local lm = 1 + ((c.level or 1) - 1) * GameConfig.LEVEL_GROWTH_RATE
        local cStats = ApplyConstellationStats(c)
        c.atk = math.floor(cStats.atk * lm)
        c.def = math.floor(cStats.def * lm)
        c.hp  = math.floor(cStats.hp  * lm)
        c.level = 1
        c.constellation = 0
    end

    -- 5) 随机对手名字
    local surnames = {"烽火","铁骑","虎牢","武灵","破军","赤壁","青龙","白虎","玄武","朱雀","龙吟","凤鸣","天策","麒麟"}
    local titles   = {"猎手","先锋","守将","行者","游侠","壮士","校尉","军师","术士","勇士","义士","斥候","大将","护卫"}
    local opName = surnames[math.random(1,#surnames)] .. titles[math.random(1,#titles)]

    return {
        cards = picked,
        totalPower = calcLinePower(picked),
        name = opName,
    }
end
