-- ============================================================================
-- 搜打撤 探索系统 (Search-Fight-Retreat Grid Exploration)
-- 独立模块: 地图生成、移动、迷雾、战斗对接、NanoVG渲染
-- ============================================================================

local GameConfig = require "game_config"

local Exploration = {}

-- ============================================================================
-- 常量
-- ============================================================================
local TILE_EMPTY   = "empty"
local TILE_ENEMY   = "enemy"
local TILE_CHEST   = "chest"
local TILE_RETREAT = "retreat"
local TILE_BLOCKED = "blocked"
local TILE_EVENT   = "event"
local TILE_START   = "start"
local TILE_SCAMMER = "scammer"  -- 骗子追击点 (被骗后随机出现)

local DIRS = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }  -- 上下左右

-- 颜色定义 (哥特暗黑风格)
local COLORS = {
    fog       = { 10,  8,  15, 240 },
    empty     = { 35, 30, 45, 200 },
    visited   = { 25, 22, 35, 180 },
    enemy     = { 80, 20, 20, 200 },
    chest     = { 60, 50, 10, 200 },
    chestGuard= { 80, 40, 10, 200 },
    retreat   = { 20, 60, 40, 200 },
    blocked   = { 15, 12, 10, 240 },
    event     = { 40, 30, 60, 200 },
    scammer   = { 120, 60, 20, 200 },
    start     = { 30, 50, 30, 200 },
    player    = { 200, 180, 100, 255 },
    gridLine  = { 60, 50, 70, 120 },
    hudBg     = { 12, 10, 18, 220 },
    popupBg   = { 18, 15, 25, 240 },
    textWhite = { 220, 210, 200, 255 },
    textGold  = { 255, 220, 80, 255 },
    textRed   = { 255, 80, 80, 255 },
    textGreen = { 80, 255, 80, 255 },
    textPurple= { 180, 120, 255, 255 },
    btnPrimary= { 100, 50, 140, 255 },
    btnDanger = { 140, 40, 40, 255 },
}

-- ============================================================================
-- 精灵图资源
-- ============================================================================
local SPRITE = {
    enemy      = { path = "image/explore_enemy_sanguo_20260408070142.png",        handle = -1 },
    chest      = { path = "image/explore_chest_sanguo_20260408070139.png",        handle = -1 },
    chestLocked= { path = "image/explore_chest_locked_sanguo_20260408070147.png", handle = -1 },
    retreat    = { path = "image/explore_retreat_sanguo_20260408070206.png",       handle = -1 },
    event      = { path = "image/explore_event_sanguo_20260408070140.png",        handle = -1 },
    blocked    = { path = "image/explore_blocked_sanguo_20260408070155.png",      handle = -1 },
    start      = { path = "image/explore_start_sanguo_20260408070141.png",        handle = -1 },
    player     = { path = "image/explore_player_sanguo_20260408070135.png",       handle = -1 },
    jade       = { path = "image/explore_jade_sanguo_20260408070157.png",         handle = -1 },
    fragment   = { path = "image/explore_fragment_sanguo_20260408070138.png",     handle = -1 },
}

-- ============================================================================
-- 模块状态
-- ============================================================================
---@type any
local vg = nil
local fontId = -1
---@type table
local IMG = nil

local state = {
    active = false,
    config = nil,
    grid = {},
    gridSize = 4,
    playerPos = { row = 1, col = 1 },
    startPos  = { row = 1, col = 1 },
    retreatPos= { row = 4, col = 4 },
    tempLoot = {},
    moveCount = 0,
    killCount = 0,
    chestsOpened = 0,
    chestsTotal = 0,
    pendingBattleTile = nil,
    -- 战斗增益/减益
    nextBattleBuff = nil,   -- { type = "hp_bonus"|"atk_bonus"|"def_bonus"|"enemy_buff", value = N }
    ambushBonusLoot = false, -- 伏兵战胜利后双倍掉落
    -- UI 弹窗
    showEventPopup  = false,
    showChestPopup  = false,
    showRetreatConfirm = false,
    showAbandonConfirm = false,
    showResultPopup = false,
    eventPopupData  = nil,
    chestPopupData  = nil,
    resultData      = nil,
    -- 动画
    animTimer  = 0,
    moveAnim   = nil,  -- { fromRow, fromCol, toRow, toCol, progress }
    -- 宝箱搜索动画
    chestSearching     = false,
    chestSearchTimer   = 0,
    chestSearchDuration= 0,
    chestSearchLoot    = nil,
    chestRevealTimer   = 0,     -- 奖励揭示特效计时
    chestRevealActive  = false, -- 正在播放揭示特效
    -- 骗子追击
    scammerActive = false,      -- 是否有骗子在地图上
    scammerStolenLoot = nil,    -- 骗子偷走的战利品列表
    showScammerPopup = false,   -- 骗子追击结果弹窗
    scammerPopupData = nil,
    -- 按钮区域 (触摸检测)
    btnRects   = {},
    tileRects  = {},
}

-- 外部回调 (由 main.lua 设置)
Exploration.onComplete = nil     -- function(result)
Exploration.onStartBattle = nil  -- function(enemyScale, maxTier, dropSets)
Exploration.onWatchAdForDouble = nil  -- function(callback) 看广告翻倍虎符
Exploration.canWatchAd = nil         -- function() -> bool 是否可看广告
Exploration.isBattleAdFree = nil     -- function() -> bool 免广告卡是否生效

-- 玩家数据 (由 main.lua 通过 SetPlayerData 传入)
local playerData = {
    avatarSheet = -1,       -- 头像精灵图 handle
    avatarIdx = 1,          -- 当前头像索引
    avatarData = nil,       -- AVATAR_DATA 表
    avatarCols = 2,         -- 头像精灵图列数
    avatarRows = 3,         -- 头像精灵图行数
    avatarImgW = 858,       -- 头像精灵图宽
    avatarImgH = 1280,      -- 头像精灵图高
    equipSheet = -1,        -- 装备精灵图 handle
    equipCols = 7,          -- 装备精灵图列数
    equipRows = 7,          -- 装备精灵图行数
    equipTierNames = {},    -- 品阶名称列表
    equipTierColors = {},   -- 品阶颜色列表
    equipSetNames = {},     -- 套装名称列表
    equipSlotNames = {},    -- 部位名称列表
    equipPieceNames = {},   -- equipPieceNames[setIdx][slotIdx] = name
}

function Exploration.SetPlayerData(data)
    for k, v in pairs(data) do
        playerData[k] = v
    end
end

-- ============================================================================
-- 工具函数
-- ============================================================================

local function ShallowCopy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function DeepCopySimple(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopySimple(v) end
    return c
end

local function Shuffle(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

local function HitRect(r, x, y)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function RollWeighted(items, weightKey)
    local total = 0
    for _, item in ipairs(items) do total = total + item[weightKey] end
    local roll = math.random() * total
    local acc = 0
    for _, item in ipairs(items) do
        acc = acc + item[weightKey]
        if roll <= acc then return item end
    end
    return items[#items]
end

-- ============================================================================
-- BFS 路径验证
-- ============================================================================

local function HasPath(grid, fromR, fromC, toR, toC, gridSize)
    local visited = {}
    local queue = { { fromR, fromC } }
    visited[fromR * 100 + fromC] = true
    local head = 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        if cur[1] == toR and cur[2] == toC then return true end
        for _, d in ipairs(DIRS) do
            local nr, nc = cur[1] + d[1], cur[2] + d[2]
            local key = nr * 100 + nc
            if nr >= 1 and nr <= gridSize and nc >= 1 and nc <= gridSize
               and not visited[key] then
                local tile = grid[nr][nc]
                if tile.type ~= TILE_BLOCKED then
                    visited[key] = true
                    queue[#queue + 1] = { nr, nc }
                end
            end
        end
    end
    return false
end

-- ============================================================================
-- 地图生成
-- ============================================================================

local function CreateTile(tileType)
    return {
        type = tileType,
        revealed = false,
        visited = false,
        enemyScale = 1.0,
        loot = nil,
        eventType = nil,
        guarded = false,
        guardCleared = false,
    }
end

local function GetEmptyTiles(grid, gridSize, excludeStart, excludeRetreat)
    local tiles = {}
    for r = 1, gridSize do
        for c = 1, gridSize do
            if grid[r][c].type == TILE_EMPTY then
                local skip = false
                if excludeStart and r == 1 and c == 1 then skip = true end
                if excludeRetreat and r == gridSize and c == gridSize then skip = true end
                if not skip then tiles[#tiles + 1] = { r, c } end
            end
        end
    end
    return Shuffle(tiles)
end

local function GetAdjacentEmpty(grid, r, c, gridSize)
    local adj = {}
    for _, d in ipairs(DIRS) do
        local nr, nc = r + d[1], c + d[2]
        if nr >= 1 and nr <= gridSize and nc >= 1 and nc <= gridSize then
            if grid[nr][nc].type == TILE_EMPTY then
                adj[#adj + 1] = { nr, nc }
            end
        end
    end
    return adj
end

local function RevealAdjacent(grid, r, c, gridSize)
    grid[r][c].revealed = true
    for _, d in ipairs(DIRS) do
        local nr, nc = r + d[1], c + d[2]
        if nr >= 1 and nr <= gridSize and nc >= 1 and nc <= gridSize then
            grid[nr][nc].revealed = true
        end
    end
end

local function GenerateChestLoot(gridSize, config)
    local rates = GameConfig.EXPLORATION_DROP_RATES[gridSize]
    if not rates then rates = GameConfig.EXPLORATION_DROP_RATES[4] end
    local effectiveRate = rates.equipment + (config.dropRateBonus or 0)
    local loot = {}

    -- 虎符 (必出)
    local jadeMul = config.jadeMultiplier or 1.0
    loot.jade = math.floor(math.random(rates.jade_min, rates.jade_max) * jadeMul)

    -- 武技残页 (随机分配到一个具体武技)
    local fragMul = config.fragMultiplier or 1.0
    local fragCount = math.floor((rates.frag + (math.random() < 0.3 and 1 or 0)) * fragMul)
    if fragCount > 0 then
        local totalSkills = GameConfig.TOTAL_SKILL_COUNT or 36
        loot.fragSkillIdx = math.random(1, totalSkills)
        loot.frag = fragCount
    else
        loot.frag = 0
    end

    -- 装备
    if math.random() < effectiveRate then
        loot.hasEquipment = true
        -- 使用与 GrantRandomEquipment 一致的概率表计算品级
        local mxT = config.maxTier or 1
        local htm = config.highTierMultiplier or 1  -- 将品(4)及以上概率倍率
        local eqRoll = math.random(1, 1000)
        local eqTier = 1
        -- 基础概率: 帝品0.5% 王品2% 侯品5% 优品15% 良品25% 凡品52.5%
        -- highTierMultiplier 仅作用于 tier4+
        local t6 = math.min(10, math.floor(5 * htm))    -- 0.5% * htm, 帝品上限1%
        local t5 = math.floor(25 * htm)   -- 2.5% * htm (累计)
        local t4 = math.floor(75 * htm)   -- 7.5% * htm (累计)
        if mxT >= 6 and eqRoll <= t6 then eqTier = 6
        elseif mxT >= 5 and eqRoll <= t5 then eqTier = 5
        elseif mxT >= 4 and eqRoll <= t4 then eqTier = 4
        elseif mxT >= 3 and eqRoll <= 225 then eqTier = 3  -- 15%
        elseif mxT >= 2 and eqRoll <= 475 then eqTier = 2  -- 25%
        else eqTier = 1
        end
        loot.equipTier = eqTier
        loot.equipSet = config.dropSets and config.dropSets[math.random(1, #config.dropSets)] or 1
        loot.equipSlotIdx = math.random(1, 7)  -- 随机部位 (用于弹窗显示)
        -- 品质下限: 高难度区域保底更高品质 (maxTier*8 作为品质下限)
        local minQ = math.min(50, (mxT - 1) * 8)  -- tier1=0, tier2=8, tier3=16, tier4=24, tier5=32, tier6=40
        loot.equipMinQuality = minQ
    end

    return loot
end

function Exploration.GenerateMap(config)
    local gs = config.gridSize
    local grid = {}
    local isEncounter = config.encounterMode  -- 遭遇战模式

    -- 1. 初始化全空
    for r = 1, gs do
        grid[r] = {}
        for c = 1, gs do
            grid[r][c] = CreateTile(TILE_EMPTY)
        end
    end

    -- 2. 起点和撤离点
    grid[1][1] = CreateTile(TILE_START)
    grid[1][1].revealed = true
    grid[1][1].visited = true

    grid[gs][gs] = CreateTile(TILE_RETREAT)

    -- 3. 放置敌人
    local enemyDensity = isEncounter and (config.enemyDensityOverride or 0.10) or (GameConfig.ENEMY_DENSITY[gs] or 0.18)
    local enemyCount = math.floor(gs * gs * enemyDensity)
    local emptyTiles = GetEmptyTiles(grid, gs, true, true)
    for i = 1, math.min(enemyCount, #emptyTiles) do
        local pos = emptyTiles[i]
        grid[pos[1]][pos[2]] = CreateTile(TILE_ENEMY)
        grid[pos[1]][pos[2]].enemyScale = config.enemyScale * (0.85 + math.random() * 0.30)
    end

    -- 3.5 遭遇战模式: 标记敌人为隐藏 (不在地图上显示)
    if isEncounter then
        for r = 1, gs do
            for c = 1, gs do
                if grid[r][c].type == TILE_ENEMY then
                    grid[r][c].hidden = true  -- 隐藏敌人图标
                end
            end
        end
    end

    -- 4. 放置宝箱 (分散到不同区域)
    local chestCount = isEncounter and (config.chestCountOverride or 5) or math.min(GameConfig.MAX_CHESTS, math.floor(gs / 2))
    local quadrants = {}
    for q = 1, 4 do quadrants[q] = {} end
    local halfR = math.ceil(gs / 2)
    local halfC = math.ceil(gs / 2)
    emptyTiles = GetEmptyTiles(grid, gs, true, true)
    for _, pos in ipairs(emptyTiles) do
        local qr = pos[1] <= halfR and 1 or 2
        local qc = pos[2] <= halfC and 1 or 2
        local qi = (qr - 1) * 2 + qc
        quadrants[qi][#quadrants[qi] + 1] = pos
    end

    local chestsPlaced = 0
    local quadOrder = Shuffle({1, 2, 3, 4})
    for _, qi in ipairs(quadOrder) do
        if chestsPlaced >= chestCount then break end
        if #quadrants[qi] > 0 then
            local pos = quadrants[qi][1]
            grid[pos[1]][pos[2]] = CreateTile(TILE_CHEST)
            -- 宝箱内容
            grid[pos[1]][pos[2]].loot = GenerateChestLoot(gs, config)
            -- 看守敌人
            local guardChance = isEncounter and (config.chestGuardOverride or 0.4) or GameConfig.CHEST_GUARD_CHANCE
            if math.random() < guardChance then
                grid[pos[1]][pos[2]].guarded = true
                -- 在相邻格放置看守敌人
                local adj = GetAdjacentEmpty(grid, pos[1], pos[2], gs)
                if #adj > 0 then
                    local gp = adj[1]
                    grid[gp[1]][gp[2]] = CreateTile(TILE_ENEMY)
                    grid[gp[1]][gp[2]].enemyScale = config.enemyScale * 1.1  -- 看守敌人稍强
                end
            end
            chestsPlaced = chestsPlaced + 1
        end
    end

    -- 5. 放置阻挡格
    local blockedRatio = isEncounter and (config.blockedRatioOverride or 0.06) or GameConfig.BLOCKED_RATIO
    local blockedCount = math.floor(gs * gs * blockedRatio)
    emptyTiles = GetEmptyTiles(grid, gs, true, true)
    local blockedPlaced = 0
    for _, pos in ipairs(emptyTiles) do
        if blockedPlaced >= blockedCount then break end
        grid[pos[1]][pos[2]] = CreateTile(TILE_BLOCKED)
        -- 验证路径可达
        if not HasPath(grid, 1, 1, gs, gs, gs) then
            -- 撤销
            grid[pos[1]][pos[2]] = CreateTile(TILE_EMPTY)
        else
            blockedPlaced = blockedPlaced + 1
        end
    end

    -- 6. 放置事件格
    local eventRatio = isEncounter and (config.eventRatioOverride or 0.18) or GameConfig.EVENT_RATIO
    local eventCount = math.floor(gs * gs * eventRatio)
    emptyTiles = GetEmptyTiles(grid, gs, true, true)
    for i = 1, math.min(eventCount, #emptyTiles) do
        local pos = emptyTiles[i]
        grid[pos[1]][pos[2]] = CreateTile(TILE_EVENT)
        local evt = RollWeighted(GameConfig.EXPLORATION_EVENTS, "weight")
        grid[pos[1]][pos[2]].eventType = evt.type
    end

    -- 7. 揭示起点相邻格
    RevealAdjacent(grid, 1, 1, gs)

    return grid, chestsPlaced
end

-- ============================================================================
-- 生命周期 API
-- ============================================================================

function Exploration.Init(vgCtx, font, imgTable)
    vg = vgCtx
    fontId = font
    IMG = imgTable
    -- 加载探索精灵图
    for _, sp in pairs(SPRITE) do
        if sp.handle < 0 then
            sp.handle = nvgCreateImage(vg, sp.path, 0)
        end
    end
end

function Exploration.StartMap(config)
    state.active = true
    state.config = config
    state.gridSize = config.gridSize
    state.playerPos = { row = 1, col = 1 }
    state.startPos = { row = 1, col = 1 }
    state.retreatPos = { row = config.gridSize, col = config.gridSize }
    state.tempLoot = {}
    state.moveCount = 0
    state.killCount = 0
    state.chestsOpened = 0
    state.pendingBattleTile = nil
    state.nextBattleBuff = nil
    state.showEventPopup = false
    state.showChestPopup = false
    state.showRetreatConfirm = false
    state.showAbandonConfirm = false
    state.showResultPopup = false
    state.eventPopupData = nil
    state.chestPopupData = nil
    state.resultData = nil
    state.animTimer = 0
    state.moveAnim = nil
    state.chestSearching = false
    state.chestSearchTimer = 0
    state.chestSearchDuration = 0
    state.chestSearchLoot = nil
    state.chestRevealTimer = 0
    state.chestRevealActive = false
    state.adDoubledJade = false
    state.btnRects = {}
    state.tileRects = {}

    local grid, chestCount = Exploration.GenerateMap(config)
    state.grid = grid
    state.chestsTotal = chestCount
end

function Exploration.IsActive()
    return state.active
end

function Exploration.Update(dt)
    if not state.active then return end
    state.animTimer = state.animTimer + dt

    -- 移动动画
    if state.moveAnim then
        state.moveAnim.progress = state.moveAnim.progress + dt * 5.0
        if state.moveAnim.progress >= 1.0 then
            state.moveAnim = nil
        end
    end
end

-- ============================================================================
-- 移动与交互
-- ============================================================================

local function CanMoveTo(r, c)
    if r < 1 or r > state.gridSize or c < 1 or c > state.gridSize then return false end
    local tile = state.grid[r][c]
    if tile.type == TILE_BLOCKED then return false end
    -- 被看守的宝箱: 检查看守是否已清除
    if tile.type == TILE_CHEST and tile.guarded and not tile.guardCleared then
        -- 检查是否相邻还有敌人
        for _, d in ipairs(DIRS) do
            local nr, nc = r + d[1], c + d[2]
            if nr >= 1 and nr <= state.gridSize and nc >= 1 and nc <= state.gridSize then
                if state.grid[nr][nc].type == TILE_ENEMY then
                    return false  -- 仍有看守敌人
                end
            end
        end
        -- 所有相邻敌人已清除
        tile.guardCleared = true
    end
    return true
end

local function AddLoot(lootItem)
    state.tempLoot[#state.tempLoot + 1] = DeepCopySimple(lootItem)
end

local function OnTileEnter(r, c)
    local tile = state.grid[r][c]
    tile.visited = true
    RevealAdjacent(state.grid, r, c, state.gridSize)

    if tile.type == TILE_ENEMY then
        -- 进入战斗
        state.pendingBattleTile = { row = r, col = c }
        if Exploration.onStartBattle then
            Exploration.onStartBattle(
                tile.enemyScale,
                state.config.maxTier or 1,
                state.config.dropSets
            )
        end
        return

    elseif tile.type == TILE_CHEST then
        -- 开启宝箱 → 先播放搜索动画
        state.chestsOpened = state.chestsOpened + 1
        -- 计算搜索时长: 奖励越好时间越长 (1~5秒)
        local loot = tile.loot
        local duration = 1.5  -- 基础: 只有虎符
        if loot.hasEquipment then
            duration = 4.0 + math.random() * 1.0  -- 装备: 4~5秒
        elseif loot.frag and loot.frag > 0 then
            duration = 2.5 + math.random() * 1.0  -- 残片: 2.5~3.5秒
        else
            duration = 1.2 + math.random() * 0.8  -- 虎符: 1.2~2秒
        end
        state.chestSearching = true
        state.chestSearchTimer = 0
        state.chestSearchDuration = duration
        state.chestSearchLoot = loot
        AddLoot(loot)
        tile.type = TILE_EMPTY  -- 宝箱消失
        return

    elseif tile.type == TILE_RETREAT then
        -- 到达撤离点
        state.showRetreatConfirm = true
        return

    elseif tile.type == TILE_EVENT then
        -- 触发事件
        local evtType = tile.eventType
        state.showEventPopup = true
        local evtDesc = ""
        for _, e in ipairs(GameConfig.EXPLORATION_EVENTS) do
            if e.type == evtType then evtDesc = e.desc; break end
        end

        if evtType == "heal" then
            state.nextBattleBuff = { type = "hp_bonus", value = 100 }
            state.eventPopupData = { title = "治愈泉水", desc = evtDesc, detail = "下次战斗基地HP+100", color = COLORS.textGreen }
        elseif evtType == "buff" then
            state.nextBattleBuff = { type = "atk_bonus", value = 0.2 }
            state.eventPopupData = { title = "神秘祝福", desc = evtDesc, detail = "下次战斗攻击力+20%", color = COLORS.textGold }
        elseif evtType == "trap" then
            -- 随机丢失一个战利品
            if #state.tempLoot > 0 then
                local idx = math.random(1, #state.tempLoot)
                table.remove(state.tempLoot, idx)
                state.eventPopupData = { title = "陷阱!", desc = evtDesc, detail = "丢失了一个战利品!", color = COLORS.textRed }
            else
                state.eventPopupData = { title = "陷阱!", desc = evtDesc, detail = "幸好没有携带物品", color = COLORS.textRed }
            end
        elseif evtType == "debuff" then
            state.nextBattleBuff = { type = "enemy_buff", value = 0.2 }
            state.eventPopupData = { title = "敌军诡计", desc = evtDesc, detail = "下次战斗敌人增强20%", color = COLORS.textPurple }
        elseif evtType == "shop" then
            local shopCost = GameConfig.EXPLORE_SHOP_COST or 40
            state.eventPopupData = { title = "行商旅人", desc = evtDesc, detail = "花费" .. shopCost .. "虎符购买补给", color = COLORS.textGold, isShop = true, shopCost = shopCost }
        elseif evtType == "blacksmith" then
            -- 铁匠铺: 花费20虎符, 下次战斗防御+30%
            state.eventPopupData = { title = "铁匠铺", desc = evtDesc, detail = "花费20虎符锻造护甲\n下次战斗防御+30%", color = COLORS.textBlue or COLORS.textGold,
                isShop = true, shopCost = 20, shopEffect = "def_bonus" }
        elseif evtType == "gamble" then
            -- 赌坊: 50%概率获得双倍当前虎符，50%概率丢失一半虎符战利品
            local jadeCount = 0
            for _, l in ipairs(state.tempLoot) do jadeCount = jadeCount + (l.jade or 0) end
            if math.random() < 0.5 then
                -- 赢了: 获得额外虎符 (当前虎符战利品的30%，至少5)
                local winJade = math.max(5, math.floor(jadeCount * 0.3))
                AddLoot({ jade = winJade })
                state.eventPopupData = { title = "赌坊·大胜!", desc = "手气不错!", detail = "赢得 " .. winJade .. " 虎符!", color = COLORS.textGold }
            else
                -- 输了: 丢失一个战利品
                if #state.tempLoot > 0 then
                    table.remove(state.tempLoot, math.random(1, #state.tempLoot))
                    state.eventPopupData = { title = "赌坊·惨败!", desc = "运气太差...", detail = "输掉了一个战利品!", color = COLORS.textRed }
                else
                    state.eventPopupData = { title = "赌坊·平手", desc = "空手而来", detail = "没有可输的东西，侥幸脱身", color = COLORS.textGold }
                end
            end
        elseif evtType == "ambush" then
            -- 精锐伏兵: 强制进入一场强化战斗(+50%敌人)，但胜利奖励翻倍
            state.nextBattleBuff = { type = "enemy_buff", value = 0.5 }
            state.eventPopupData = { title = "精锐伏兵!", desc = evtDesc, detail = "遭遇精锐敌军(+50%强度)\n击败后双倍掉落!", color = COLORS.textRed,
                isAmbush = true }
        elseif evtType == "relic" then
            -- 古战场遗迹: 获得1-2个碎片(小额固定奖励)
            local relicFrag = math.random(1, 2)
            AddLoot({ frag = relicFrag })
            state.eventPopupData = { title = "古战场遗迹", desc = evtDesc, detail = "搜寻残骸，发现 " .. relicFrag .. " 个武技残片", color = COLORS.textPurple }
        elseif evtType == "supply" then
            -- 军粮辎重: 获得少量虎符(8-15)
            local supplyJade = math.random(8, 15)
            AddLoot({ jade = supplyJade })
            state.eventPopupData = { title = "截获辎重", desc = evtDesc, detail = "获得 " .. supplyJade .. " 虎符!", color = COLORS.textGreen }
        elseif evtType == "adventure" then
            -- 奇遇·仙人指路: 随机2选1选项
            local roll = math.random(1, 3)
            if roll == 1 then
                -- 指路: 揭示大范围迷雾
                local revealed = 0
                for dr = -2, 2 do
                    for dc = -2, 2 do
                        local nr = state.playerPos.row + dr
                        local nc = state.playerPos.col + dc
                        if nr >= 1 and nr <= state.gridSize and nc >= 1 and nc <= state.gridSize then
                            if not state.grid[nr][nc].revealed then
                                state.grid[nr][nc].revealed = true
                                revealed = revealed + 1
                            end
                        end
                    end
                end
                state.eventPopupData = { title = "仙人指路", desc = evtDesc, detail = "揭示了周围 " .. revealed .. " 个格子!", color = COLORS.textGold }
            elseif roll == 2 then
                -- 赠送武技残片
                local advFrag = math.random(2, 4)
                local totalSkills = GameConfig.TOTAL_SKILL_COUNT or 36
                AddLoot({ frag = advFrag, fragSkillIdx = math.random(1, totalSkills) })
                state.eventPopupData = { title = "奇遇·传功", desc = "遇到隐世高人", detail = "获得 " .. advFrag .. " 个武技残片!", color = COLORS.textPurple }
            else
                -- 全属性增益
                state.nextBattleBuff = { type = "atk_bonus", value = 0.3 }
                state.eventPopupData = { title = "奇遇·点化", desc = "高人点拨武学要义", detail = "下次战斗攻击力+30%!", color = COLORS.textGold }
            end
        elseif evtType == "gift" then
            -- 路遇贵人相助: 直接获得虎符+碎片
            local giftJade = math.random(12, 25)
            local giftFrag = math.random(1, 2)
            local totalSkills = GameConfig.TOTAL_SKILL_COUNT or 36
            AddLoot({ jade = giftJade })
            AddLoot({ frag = giftFrag, fragSkillIdx = math.random(1, totalSkills) })
            state.eventPopupData = { title = "贵人相助", desc = evtDesc, detail = "获得 " .. giftJade .. " 虎符 + " .. giftFrag .. " 残片!", color = COLORS.textGreen }
        elseif evtType == "scam" then
            -- 遭遇江湖骗子: 偷走2-3个战利品，骗子逃到地图随机空格
            local stolenCount = math.min(math.random(2, 3), #state.tempLoot)
            local stolenItems = {}
            for si = 1, stolenCount do
                if #state.tempLoot > 0 then
                    local idx = math.random(1, #state.tempLoot)
                    stolenItems[#stolenItems + 1] = table.remove(state.tempLoot, idx)
                end
            end
            if #stolenItems > 0 then
                state.scammerStolenLoot = stolenItems
                -- 将骗子放到地图上随机空格
                local emptyList = {}
                for er = 1, state.gridSize do
                    for ec = 1, state.gridSize do
                        local et = state.grid[er][ec]
                        if et.type == TILE_EMPTY and not (er == state.playerPos.row and ec == state.playerPos.col) then
                            emptyList[#emptyList + 1] = { er, ec }
                        end
                    end
                end
                if #emptyList > 0 then
                    Shuffle(emptyList)
                    local sp = emptyList[1]
                    state.grid[sp[1]][sp[2]].type = TILE_SCAMMER
                    state.grid[sp[1]][sp[2]].revealed = true  -- 骗子位置可见
                    state.scammerActive = true
                end
                state.eventPopupData = { title = "江湖骗子!", desc = evtDesc,
                    detail = "被骗走了 " .. #stolenItems .. " 个战利品!\n骗子已标记在地图上，追上去夺回!",
                    color = COLORS.textRed }
            else
                state.eventPopupData = { title = "江湖骗子!", desc = evtDesc,
                    detail = "骗子想行骗，但你身无长物\n骗子灰溜溜地跑了", color = COLORS.textGold }
            end
        elseif evtType == "mystery" then
            -- 神秘宝匣: 高风险高回报，可能大奖或陷阱
            local mRoll = math.random(1, 100)
            if mRoll <= 30 then
                -- 大奖: 获得装备
                local mysteryLoot = GenerateChestLoot(state.gridSize, state.config)
                mysteryLoot.hasEquipment = true
                mysteryLoot.equipTier = math.random(3, math.min(state.config.maxTier or 4, 5))
                AddLoot(mysteryLoot)
                state.eventPopupData = { title = "神秘宝匣·珍宝!", desc = "打开了神秘宝匣",
                    detail = "发现珍贵装备和物资!", color = COLORS.textGold }
            elseif mRoll <= 60 then
                -- 中奖: 大量虎符
                local mJade = math.random(20, 40)
                AddLoot({ jade = mJade })
                state.eventPopupData = { title = "神秘宝匣·惊喜", desc = "打开了神秘宝匣",
                    detail = "获得 " .. mJade .. " 虎符!", color = COLORS.textGreen }
            else
                -- 陷阱: 损失战利品
                if #state.tempLoot > 0 then
                    local lostIdx = math.random(1, #state.tempLoot)
                    table.remove(state.tempLoot, lostIdx)
                    state.eventPopupData = { title = "神秘宝匣·诅咒!", desc = "宝匣中释放出诅咒",
                        detail = "丢失了一个战利品!", color = COLORS.textRed }
                else
                    state.eventPopupData = { title = "神秘宝匣·空", desc = "宝匣中空无一物",
                        detail = "虚惊一场", color = COLORS.textGold }
                end
            end
        end

        tile.type = TILE_EMPTY  -- 事件消失
        return
    end
    -- TILE_SCAMMER: 追上骗子，夺回战利品 + 触发战斗
    if tile.type == TILE_SCAMMER then
        state.showScammerPopup = true
        -- 归还被骗走的战利品
        local returnedCount = 0
        if state.scammerStolenLoot then
            for _, sl in ipairs(state.scammerStolenLoot) do
                AddLoot(sl)
                returnedCount = returnedCount + 1
            end
        end
        -- 额外奖励: 骗子身上搜出虎符
        local bonusJade = math.random(10, 20)
        AddLoot({ jade = bonusJade })
        state.scammerPopupData = {
            title = "追回赃物!",
            desc = "抓住了江湖骗子",
            detail = "夺回 " .. returnedCount .. " 个战利品!\n额外获得 " .. bonusJade .. " 虎符!",
            color = COLORS.textGreen,
        }
        state.scammerActive = false
        state.scammerStolenLoot = nil
        tile.type = TILE_EMPTY
        return
    end

    -- TILE_START: 无事发生
    if tile.type == TILE_START then return end

    -- 遭遇战模式: 空格有概率触发遭遇战
    if state.config.encounterMode and tile.type == TILE_EMPTY then
        local encounterRate = state.config.encounterRate or 0.30
        if math.random() < encounterRate then
            -- 触发遭遇战
            local encounterEvents = GameConfig.RESOURCE_DUNGEON and GameConfig.RESOURCE_DUNGEON.encounterEvents
            if encounterEvents then
                local evt = RollWeighted(encounterEvents, "weight")
                if evt.type == "battle" or evt.type == "ambush" then
                    -- 遭遇敌军: 触发战斗
                    local isAmbush = (evt.type == "ambush")
                    if isAmbush then
                        state.nextBattleBuff = { type = "enemy_buff", value = 0.5 }
                        state.ambushBonusLoot = true
                    end
                    state.showEventPopup = true
                    local detail = isAmbush and "精锐伏兵(+50%强度)\n击败后双倍掉落!" or "即将进入战斗!"
                    local titleStr = isAmbush and "精锐伏兵!" or "遭遇敌军!"
                    state.eventPopupData = {
                        title = titleStr, desc = evt.desc, detail = detail,
                        color = COLORS.textRed, isEncounterBattle = true,
                        encounterRow = r, encounterCol = c,
                    }
                elseif evt.type == "treasure" then
                    -- 隐藏宝物: 获得少量奖励
                    local tJade = math.random(5, 12)
                    local tFrag = math.random() < 0.4 and 1 or 0
                    AddLoot({ jade = tJade, frag = tFrag > 0 and tFrag or nil })
                    state.showEventPopup = true
                    local detailStr = "获得 " .. tJade .. " 虎符"
                    if tFrag > 0 then detailStr = detailStr .. " + " .. tFrag .. " 武技残片" end
                    state.eventPopupData = { title = "隐藏宝物!", desc = evt.desc, detail = detailStr, color = COLORS.textGold }
                end
                -- "nothing" → 不做任何事
            end
        end
    end
end

local function DoMove(toRow, toCol)
    if not CanMoveTo(toRow, toCol) then return end

    -- 启动移动动画
    state.moveAnim = {
        fromRow = state.playerPos.row, fromCol = state.playerPos.col,
        toRow = toRow, toCol = toCol, progress = 0,
    }

    state.playerPos.row = toRow
    state.playerPos.col = toCol
    state.moveCount = state.moveCount + 1

    OnTileEnter(toRow, toCol)
end

-- ============================================================================
-- 战斗回调
-- ============================================================================

function Exploration.OnBattleReturn(victory)
    if not state.pendingBattleTile then return end
    local tr = state.pendingBattleTile.row
    local tc = state.pendingBattleTile.col

    if victory then
        -- 清除敌人
        state.grid[tr][tc] = CreateTile(TILE_EMPTY)
        state.grid[tr][tc].revealed = true
        state.grid[tr][tc].visited = true
        state.killCount = state.killCount + 1

        -- 战斗掉落
        local battleLoot = {
            jade = math.random(GameConfig.EXPLORE_BATTLE_JADE_MIN, GameConfig.EXPLORE_BATTLE_JADE_MAX),
        }
        if math.random() < GameConfig.EXPLORE_BATTLE_FRAG_CHANCE then
            battleLoot.frag = 1
        end
        -- 精锐伏兵双倍掉落
        if state.ambushBonusLoot then
            battleLoot.jade = (battleLoot.jade or 0) * 2
            if battleLoot.frag then battleLoot.frag = battleLoot.frag * 2 end
            state.ambushBonusLoot = false
        end
        AddLoot(battleLoot)

        -- 检查看守宝箱解锁
        for _, d in ipairs(DIRS) do
            local nr, nc = tr + d[1], tc + d[2]
            if nr >= 1 and nr <= state.gridSize and nc >= 1 and nc <= state.gridSize then
                local adjTile = state.grid[nr][nc]
                if adjTile.type == TILE_CHEST and adjTile.guarded then
                    -- 检查是否还有其他看守
                    local hasGuard = false
                    for _, d2 in ipairs(DIRS) do
                        local gr, gc = nr + d2[1], nc + d2[2]
                        if gr >= 1 and gr <= state.gridSize and gc >= 1 and gc <= state.gridSize then
                            if state.grid[gr][gc].type == TILE_ENEMY then
                                hasGuard = true
                                break
                            end
                        end
                    end
                    if not hasGuard then
                        adjTile.guardCleared = true
                    end
                end
            end
        end

        -- 揭示周围
        RevealAdjacent(state.grid, tr, tc, state.gridSize)
    else
        -- 战败/退出: 玩家停留原位, 敌人不清除, 随机丢失10%-30%已有战利品
        if #state.tempLoot > 0 then
            local lossPct = 0.1 + math.random() * 0.2  -- 10% ~ 30%
            local lossCount = math.max(1, math.floor(#state.tempLoot * lossPct))
            for i = 1, lossCount do
                if #state.tempLoot > 0 then
                    table.remove(state.tempLoot, math.random(1, #state.tempLoot))
                end
            end
            state.lastBattleLostCount = lossCount
        else
            state.lastBattleLostCount = 0
        end
    end

    state.pendingBattleTile = nil
    state.nextBattleBuff = nil  -- 消耗增益
end

-- ============================================================================
-- 撤离与结算
-- ============================================================================

local function CalculateRetainedLoot(retainPct)
    if retainPct >= 1.0 or #state.tempLoot == 0 then
        return state.tempLoot
    end
    -- 0% 保留 = 全部丢失, 不保留任何物品
    if retainPct <= 0 then
        return {}
    end
    local count = math.max(1, math.floor(#state.tempLoot * retainPct))
    local shuffled = {}
    for i, v in ipairs(state.tempLoot) do shuffled[i] = v end
    Shuffle(shuffled)
    local retained = {}
    for i = 1, math.min(count, #shuffled) do
        retained[i] = shuffled[i]
    end
    return retained
end

local function FinishExploration(success)
    local retainPct = success and GameConfig.LOOT_RETAIN_RETREAT or GameConfig.LOOT_RETAIN_ABANDON
    local finalLoot = CalculateRetainedLoot(retainPct)

    -- 统计奖励总和
    local totalJade = 0
    local equipCount = 0
    -- 按武技索引汇总残页: { [skillIdx] = count }
    local fragMap = {}
    local totalFrag = 0
    for _, loot in ipairs(finalLoot) do
        totalJade = totalJade + (loot.jade or 0)
        if (loot.frag or 0) > 0 and loot.fragSkillIdx then
            local si = loot.fragSkillIdx
            fragMap[si] = (fragMap[si] or 0) + loot.frag
            totalFrag = totalFrag + loot.frag
        end
        if loot.hasEquipment then equipCount = equipCount + 1 end
    end
    -- 转为列表方便遍历
    local fragList = {}
    for si, cnt in pairs(fragMap) do
        fragList[#fragList + 1] = { skillIdx = si, count = cnt }
    end

    state.resultData = {
        success = success,
        loot = finalLoot,
        totalJade = totalJade,
        totalFrag = totalFrag,
        fragList = fragList,
        equipCount = equipCount,
        retainPct = retainPct,
        mode = state.config.mode,
        stageIdx = state.config.stageIdx,
        abyssFloor = state.config.abyssFloor,
        moveCount = state.moveCount,
        killCount = state.killCount,
        chestsOpened = state.chestsOpened,
        chestsTotal = state.chestsTotal,
    }
    state.showResultPopup = true
end

local function CloseAndExit()
    state.active = false
    state.showResultPopup = false
    if Exploration.onComplete and state.resultData then
        Exploration.onComplete(state.resultData)
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

local function DrawText(x, y, text, size, color, align)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size or 18)
    nvgTextAlign(vg, align or (NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE))
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgText(vg, x, y, text, nil)
end

--- 在 (cx, cy) 为中心绘制精灵图，size 为正方形边长，alpha 为透明度 0~255
local function DrawSprite(handle, cx, cy, size, alpha)
    if handle < 0 then return false end
    alpha = alpha or 255
    local half = size / 2
    local pat = nvgImagePattern(vg, cx - half, cy - half, size, size, 0, handle, alpha / 255)
    nvgBeginPath(vg)
    nvgRect(vg, cx - half, cy - half, size, size)
    nvgFillPaint(vg, pat)
    nvgFill(vg)
    return true
end

-- 绘制玩家头像 (圆角矩形, 从精灵图裁切)
-- cx, cy = 中心点坐标 (与 DrawSprite 一致)
local function DrawPlayerAvatar(cx, cy, size, radius)
    local half = size / 2
    local lx, ly = cx - half, cy - half  -- 左上角
    if playerData.avatarSheet < 0 or not playerData.avatarData then
        -- 降级: 画一个圆形占位符
        nvgBeginPath(vg); nvgRoundedRect(vg, lx, ly, size, size, radius or 4)
        nvgFillColor(vg, nvgRGBA(200, 180, 100, 200)); nvgFill(vg)
        nvgFontSize(vg, size * 0.6)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(40, 30, 20, 255))
        nvgText(vg, cx, cy, "P", nil)
        return
    end
    local avData = playerData.avatarData[playerData.avatarIdx] or playerData.avatarData[1]
    local cellW = playerData.avatarImgW / playerData.avatarCols
    local cellH = playerData.avatarImgH / playerData.avatarRows
    local sx = avData.col * cellW
    local sy = avData.row * cellH
    local pat = nvgImagePattern(vg,
        lx - sx * (size / cellW), ly - sy * (size / cellH),
        playerData.avatarImgW * (size / cellW),
        playerData.avatarImgH * (size / cellH),
        0, playerData.avatarSheet, 1.0)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, lx, ly, size, size, radius or 4)
    nvgFillPaint(vg, pat); nvgFill(vg)
end

-- 绘制装备图标 (从精灵图裁切)
local function DrawEquipIcon(x, y, size, slotIdx, setIdx)
    if playerData.equipSheet < 0 then return end
    local cols = playerData.equipCols
    local rows = playerData.equipRows
    local eqRow = (slotIdx or 1) - 1
    local eqCol = (setIdx or 1) - 1
    -- 使用与 main.lua DrawCardImage 相同的逻辑
    local cellW = 1.0 / cols
    local cellH = 1.0 / rows
    -- nvgImagePattern 需要绝对坐标
    local totalW = size * cols
    local totalH = size * rows
    local pat = nvgImagePattern(vg,
        x - eqCol * size, y - eqRow * size,
        totalW, totalH, 0, playerData.equipSheet, 1.0)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, size, size, 4)
    nvgFillPaint(vg, pat); nvgFill(vg)
end

local function DrawRoundedPanel(x, y, w, h, radius, bgColor)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius or 8)
    nvgFillColor(vg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(vg)
    -- 边框
    nvgStrokeColor(vg, nvgRGBA(80, 60, 100, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

local function DrawButton(x, y, w, h, text, color, key)
    DrawRoundedPanel(x, y, w, h, 6, color)
    DrawText(x + w / 2, y + h / 2, text, 16, COLORS.textWhite)
    state.btnRects[key] = { x = x, y = y, w = w, h = h }
end

local function DrawGrid(W, H)
    local gs = state.gridSize
    local maxGridArea = math.min(W - 40, H * 0.50)
    local cellSize = math.floor(maxGridArea / gs)
    local gridW = cellSize * gs
    local gridX = math.floor((W - gridW) / 2)
    local gridY = 80

    state.tileRects = {}

    -- 格子背景
    for r = 1, gs do
        for c = 1, gs do
            local tile = state.grid[r][c]
            local cx = gridX + (c - 1) * cellSize
            local cy = gridY + (r - 1) * cellSize
            local innerMargin = 2
            local ix = cx + innerMargin
            local iy = cy + innerMargin
            local iw = cellSize - innerMargin * 2
            local ih = cellSize - innerMargin * 2

            -- 保存点击区域
            state.tileRects[r * 100 + c] = { x = cx, y = cy, w = cellSize, h = cellSize, row = r, col = c }

            -- 绘制格子
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, iw, ih, 4)

            if not tile.revealed then
                -- 迷雾
                nvgFillColor(vg, nvgRGBA(COLORS.fog[1], COLORS.fog[2], COLORS.fog[3], COLORS.fog[4]))
                nvgFill(vg)
                DrawText(ix + iw / 2, iy + ih / 2, "?", math.max(14, cellSize * 0.35), { 60, 50, 80, 150 })
            else
                -- 已揭示: 按类型着色
                local col
                local isHiddenEnemy = (tile.type == TILE_ENEMY and tile.hidden)  -- 遭遇战隐藏敌人
                if tile.type == TILE_EMPTY or tile.type == TILE_START or isHiddenEnemy then
                    col = tile.visited and COLORS.visited or COLORS.empty
                elseif tile.type == TILE_ENEMY then
                    col = COLORS.enemy
                elseif tile.type == TILE_CHEST then
                    col = tile.guarded and not tile.guardCleared and COLORS.chestGuard or COLORS.chest
                elseif tile.type == TILE_RETREAT then
                    col = COLORS.retreat
                elseif tile.type == TILE_BLOCKED then
                    col = COLORS.blocked
                elseif tile.type == TILE_EVENT then
                    col = COLORS.event
                elseif tile.type == TILE_SCAMMER then
                    col = COLORS.scammer
                else
                    col = COLORS.empty
                end
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], col[4]))
                nvgFill(vg)

                -- 图标 (精灵图)
                local iconSize = math.max(16, cellSize * 0.55)
                local iconAlpha = tile.visited and 255 or 180
                local midX, midY = ix + iw / 2, iy + ih / 2

                if tile.type == TILE_ENEMY and not tile.hidden then
                    DrawSprite(SPRITE.enemy.handle, midX, midY, iconSize, iconAlpha)
                elseif tile.type == TILE_ENEMY and tile.hidden then
                    -- 遭遇战隐藏敌人: 不显示图标 (显示为普通空格)
                elseif tile.type == TILE_CHEST then
                    if tile.guarded and not tile.guardCleared then
                        DrawSprite(SPRITE.chestLocked.handle, midX, midY, iconSize, iconAlpha)
                        -- 锁定宝箱提示标签
                        local lblSz = math.max(7, cellSize * 0.14)
                        nvgFontSize(vg, lblSz)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                        local lockPulse = math.floor(150 + 80 * math.sin(state.animTimer * 2.5))
                        nvgFillColor(vg, nvgRGBA(255, 120, 80, lockPulse))
                        nvgText(vg, midX, midY + iconSize * 0.35, "击败周围敌人", nil)
                        nvgText(vg, midX, midY + iconSize * 0.35 + lblSz + 1, "可解锁宝箱", nil)
                    else
                        DrawSprite(SPRITE.chest.handle, midX, midY, iconSize, iconAlpha)
                    end
                elseif tile.type == TILE_RETREAT then
                    -- 撤离点脉冲
                    local pulse = 0.7 + 0.3 * math.sin(state.animTimer * 3.0)
                    local glowAlpha = math.floor(pulse * 200)
                    nvgBeginPath(vg)
                    nvgCircle(vg, midX, midY, iw * 0.35)
                    nvgFillColor(vg, nvgRGBA(40, 200, 80, glowAlpha))
                    nvgFill(vg)
                    DrawSprite(SPRITE.retreat.handle, midX, midY, iconSize, 255)
                elseif tile.type == TILE_EVENT then
                    DrawSprite(SPRITE.event.handle, midX, midY, iconSize, iconAlpha)
                elseif tile.type == TILE_BLOCKED then
                    DrawSprite(SPRITE.blocked.handle, midX, midY, iconSize * 0.9, iconAlpha)
                elseif tile.type == TILE_START then
                    DrawSprite(SPRITE.start.handle, midX, midY, iconSize, iconAlpha)
                elseif tile.type == TILE_SCAMMER then
                    -- 骗子图标: 脉冲闪烁的感叹号
                    local scamPulse = 0.6 + 0.4 * math.sin(state.animTimer * 5.0)
                    local scamAlpha = math.floor(255 * scamPulse)
                    DrawText(midX, midY, "!", math.max(16, cellSize * 0.5), { 255, 100, 30, scamAlpha })
                    -- 小标签
                    local scamLblSz = math.max(7, cellSize * 0.13)
                    nvgFontSize(vg, scamLblSz)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(255, 180, 60, scamAlpha))
                    nvgText(vg, midX, midY + iconSize * 0.3, "骗子", nil)
                end

                -- 已访问标记
                if tile.visited and tile.type ~= TILE_START and tile.type ~= TILE_RETREAT then
                    nvgBeginPath(vg)
                    nvgCircle(vg, ix + iw - 6, iy + ih - 6, 3)
                    nvgFillColor(vg, nvgRGBA(100, 100, 100, 100))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 玩家标记
    local pr, pc = state.playerPos.row, state.playerPos.col
    -- 动画偏移
    local drawR, drawC = pr, pc
    if state.moveAnim then
        local p = math.min(1.0, state.moveAnim.progress)
        local ease = p * p * (3 - 2 * p)  -- smoothstep
        drawR = state.moveAnim.fromRow + (state.moveAnim.toRow - state.moveAnim.fromRow) * ease
        drawC = state.moveAnim.fromCol + (state.moveAnim.toCol - state.moveAnim.fromCol) * ease
    end
    local px = gridX + (drawC - 1) * cellSize + cellSize / 2
    local py = gridY + (drawR - 1) * cellSize + cellSize / 2
    local pulseR = cellSize * 0.28 + cellSize * 0.05 * math.sin(state.animTimer * 4.0)

    -- 外圈发光
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, pulseR + 4)
    nvgFillColor(vg, nvgRGBA(200, 180, 100, 80))
    nvgFill(vg)
    -- 内圈
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, pulseR)
    nvgFillColor(vg, nvgRGBA(COLORS.player[1], COLORS.player[2], COLORS.player[3], COLORS.player[4]))
    nvgFill(vg)
    -- 玩家头像
    local avatarSz = math.max(18, cellSize * 0.5)
    DrawPlayerAvatar(px, py, avatarSz, avatarSz * 0.25)

    return gridY + gs * cellSize  -- 返回网格底部Y
end

local function DrawHUD(W, H, gridBottom)
    local gs = state.gridSize
    local cfg = state.config

    -- === 顶栏 ===
    DrawRoundedPanel(0, 0, W, 70, 0, COLORS.hudBg)

    -- 返回按钮
    DrawButton(10, 15, 90, 40, "< 撤退", COLORS.btnDanger, "abandon")

    -- 关卡名
    local title = ""
    if cfg.mode == "stage" then
        title = "探索 · " .. (cfg.stageName or ("战场 " .. gs .. "×" .. gs))
    elseif cfg.mode == "abyss" then
        title = "讨伐 · " .. gs .. "×" .. gs
        if cfg.highTierMultiplier and cfg.highTierMultiplier > 1 then
            title = title .. " 高品×" .. cfg.highTierMultiplier
        elseif cfg.dropRateBonus and cfg.dropRateBonus > 0 then
            title = title .. " +" .. math.floor(cfg.dropRateBonus * 100) .. "%"
        end
    end
    DrawText(W / 2, 35, title, 20, COLORS.textGold)

    -- 步数
    DrawText(W - 50, 35, "步:" .. state.moveCount, 16, COLORS.textWhite, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)

    -- === 底栏信息 ===
    local infoY = gridBottom + 15
    local barH = 140
    DrawRoundedPanel(10, infoY, W - 20, barH, 8, COLORS.hudBg)

    local leftX = 25
    local lineH = 22
    local curY = infoY + 14

    -- 击杀
    DrawText(leftX, curY, "击杀: " .. state.killCount, 16, COLORS.textWhite, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 宝箱
    DrawText(leftX + 120, curY, "宝箱: " .. state.chestsOpened .. "/" .. state.chestsTotal, 16, COLORS.textGold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    curY = curY + lineH

    -- 战利品预览
    DrawText(leftX, curY, "战利品:", 16, COLORS.textWhite, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    if #state.tempLoot == 0 then
        DrawText(leftX + 70, curY, "暂无", 14, { 120, 110, 100, 180 }, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    else
        -- 统计总量
        local tj, tf, te = 0, 0, 0
        for _, l in ipairs(state.tempLoot) do
            tj = tj + (l.jade or 0)
            tf = tf + (l.frag or 0)
            if l.hasEquipment then te = te + 1 end
        end
        -- 用精灵图+文字逐项绘制战利品
        local lootX = leftX + 70
        local iconSz = 16
        if tj > 0 then
            DrawSprite(SPRITE.jade.handle, lootX + iconSz / 2, curY, iconSz, 255)
            lootX = lootX + iconSz + 2
            DrawText(lootX, curY, tostring(tj), 14, COLORS.textGold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            lootX = lootX + 24
        end
        if tf > 0 then
            DrawSprite(SPRITE.fragment.handle, lootX + iconSz / 2, curY, iconSz, 255)
            lootX = lootX + iconSz + 2
            DrawText(lootX, curY, tostring(tf), 14, COLORS.textPurple, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            lootX = lootX + 24
        end
        if te > 0 then
            DrawPlayerAvatar(lootX + iconSz / 2, curY, iconSz, 3)
            lootX = lootX + iconSz + 2
            DrawText(lootX, curY, te .. "件", 14, COLORS.textWhite, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        end
    end
    curY = curY + lineH

    -- 指南针 (指向最近宝箱)
    local nearestChestDist = 9999
    local nearestChestDir = nil
    for r = 1, gs do
        for c = 1, gs do
            if state.grid[r][c].type == TILE_CHEST then
                local dist = math.abs(r - state.playerPos.row) + math.abs(c - state.playerPos.col)
                if dist < nearestChestDist then
                    nearestChestDist = dist
                    nearestChestDir = { r - state.playerPos.row, c - state.playerPos.col }
                end
            end
        end
    end

    if nearestChestDir then
        DrawSprite(SPRITE.chest.handle, leftX + 7, curY, 14, 255)
        DrawText(leftX + 18, curY, "宝箱方向:", 14, COLORS.textGold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        -- 箭头方向
        local angle = math.atan(nearestChestDir[2], nearestChestDir[1])
        local arrowX = leftX + 130
        local arrowY = curY
        nvgSave(vg)
        nvgTranslate(vg, arrowX, arrowY)
        nvgRotate(vg, angle - math.pi / 2)  -- 调整使上方为0度
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, -8)
        nvgLineTo(vg, 5, 4)
        nvgLineTo(vg, -5, 4)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
        nvgFill(vg)
        nvgRestore(vg)
        DrawText(arrowX + 20, curY, "~" .. nearestChestDist .. "格", 14, { 180, 160, 120, 200 }, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    else
        DrawText(leftX, curY, "所有宝箱已收集!", 14, COLORS.textGreen, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
    curY = curY + lineH

    -- 增益状态
    if state.nextBattleBuff then
        local buffText = ""
        if state.nextBattleBuff.type == "hp_bonus" then
            buffText = "增益: 基地HP+" .. state.nextBattleBuff.value
        elseif state.nextBattleBuff.type == "atk_bonus" then
            buffText = "增益: 攻击力+" .. math.floor(state.nextBattleBuff.value * 100) .. "%"
        elseif state.nextBattleBuff.type == "def_bonus" then
            buffText = "增益: 防御力+" .. math.floor(state.nextBattleBuff.value * 100) .. "%"
        elseif state.nextBattleBuff.type == "enemy_buff" then
            buffText = "敌袭: 敌人增强" .. math.floor(state.nextBattleBuff.value * 100) .. "%"
        end
        local bColor = state.nextBattleBuff.type == "enemy_buff" and COLORS.textRed or COLORS.textGreen
        DrawText(leftX, curY, buffText, 14, bColor, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        curY = curY + lineH
    end

    -- 骗子追踪提示
    if state.scammerActive then
        local scamFlash = math.floor(180 + 75 * math.sin(state.animTimer * 4.0))
        DrawText(leftX, curY, "!! 骗子在逃 - 追上去夺回战利品!", 14, { 255, 120, 40, scamFlash }, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
end

local function DrawPopup(W, H, title, lines, buttons, titleColor)
    -- 暗幕
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗面板
    local pw, ph = 380, 60 + #lines * 28 + #buttons * 50 + 20
    local px = (W - pw) / 2
    local py = (H - ph) / 2
    DrawRoundedPanel(px, py, pw, ph, 12, COLORS.popupBg)

    -- 标题
    DrawText(px + pw / 2, py + 28, title, 22, titleColor or COLORS.textGold)

    -- 内容行
    local curY = py + 55
    for _, line in ipairs(lines) do
        local color = line.color or COLORS.textWhite
        DrawText(px + pw / 2, curY, line.text, line.size or 16, color)
        curY = curY + 28
    end

    -- 按钮
    curY = curY + 10
    for _, btn in ipairs(buttons) do
        DrawButton(px + (pw - 200) / 2, curY, 200, 38, btn.text, btn.color or COLORS.btnPrimary, btn.key)
        curY = curY + 50
    end
end

local function DrawEventPopup(W, H)
    if not state.eventPopupData then return end
    local d = state.eventPopupData
    local lines = {
        { text = d.desc, color = d.color, size = 18 },
        { text = d.detail, color = COLORS.textWhite, size = 15 },
    }
    local buttons = {
        { text = "确认", key = "event_ok", color = COLORS.btnPrimary },
    }
    if d.isShop then
        local cost = d.shopCost or (GameConfig.EXPLORE_SHOP_COST or 40)
        buttons = {
            { text = "购买 (-" .. cost .. "石)", key = "event_buy", color = COLORS.btnPrimary },
            { text = "离开", key = "event_ok", color = COLORS.btnDanger },
        }
    end
    if d.isAmbush then
        buttons = {
            { text = "迎战!", key = "event_ambush_fight", color = COLORS.btnDanger },
        }
    end
    if d.isEncounterBattle then
        buttons = {
            { text = "迎战!", key = "event_encounter_fight", color = COLORS.btnDanger },
        }
    end
    DrawPopup(W, H, d.title, lines, buttons)
end

-- ============================================================================
-- 宝箱搜索动画
-- ============================================================================
local function DrawChestSearchAnimation(W, H, dt)
    if not state.chestSearching then return end

    state.chestSearchTimer = state.chestSearchTimer + dt
    local t = state.chestSearchTimer
    local dur = state.chestSearchDuration
    local progress = math.min(t / dur, 1.0)

    -- 暗幕
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180)); nvgFill(vg)

    local cx, cy = W / 2, H / 2 - 30

    -- 中央宝箱图标 (呼吸效果)
    local breathScale = 1.0 + 0.08 * math.sin(t * 3.0)
    local chestSz = 72 * breathScale
    DrawSprite(SPRITE.chest.handle, cx, cy - 40, chestSz, 255)

    -- 旋转光圈
    local ringR = 60
    local ringAlpha = 160 + 60 * math.sin(t * 4.0)
    local arcSpeed = 3.0 + progress * 4.0  -- 越接近结束转越快
    local arcStart = t * arcSpeed
    local arcLen = 1.2 + 0.8 * math.sin(t * 2.0)

    -- 外圈暗光环
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy + 30, ringR + 4, 0, math.pi * 2, NVG_CW)
    nvgStrokeColor(vg, nvgRGBA(80, 40, 120, 40))
    nvgStrokeWidth(vg, 8)
    nvgStroke(vg)

    -- 主旋转弧线
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy + 30, ringR, arcStart, arcStart + arcLen, NVG_CW)
    local arcR, arcG, arcB = 180, 130, 255
    if progress > 0.7 then
        -- 接近完成时变金色
        local blend = (progress - 0.7) / 0.3
        arcR = math.floor(180 + (255 - 180) * blend)
        arcG = math.floor(130 + (220 - 130) * blend)
        arcB = math.floor(255 + (80 - 255) * blend)
    end
    nvgStrokeColor(vg, nvgRGBA(arcR, arcG, arcB, math.floor(ringAlpha)))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    -- 第二条弧线 (对向)
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy + 30, ringR, arcStart + math.pi, arcStart + math.pi + arcLen * 0.7, NVG_CW)
    nvgStrokeColor(vg, nvgRGBA(arcR, arcG, arcB, math.floor(ringAlpha * 0.5)))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 粒子散点 (围绕光圈旋转的小点)
    for i = 1, 6 do
        local angle = arcStart * 0.8 + (i / 6) * math.pi * 2
        local pr = ringR + 8 + 6 * math.sin(t * 5 + i)
        local px = cx + math.cos(angle) * pr
        local py = (cy + 30) + math.sin(angle) * pr
        local psz = 2 + 1.5 * math.sin(t * 6 + i * 1.5)
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, psz)
        nvgFillColor(vg, nvgRGBA(arcR, arcG, arcB, math.floor(100 + 80 * math.sin(t * 4 + i))))
        nvgFill(vg)
    end

    -- 进度条
    local barW, barH = 200, 6
    local barX = cx - barW / 2
    local barY = cy + 30 + ringR + 24
    -- 背景
    nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(40, 30, 60, 180)); nvgFill(vg)
    -- 填充
    nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3)
    local barGrad = nvgLinearGradient(vg, barX, barY, barX + barW * progress, barY,
        nvgRGBA(120, 60, 200, 240), nvgRGBA(arcR, arcG, arcB, 240))
    nvgFillPaint(vg, barGrad); nvgFill(vg)

    -- 搜索文字
    local dots = string.rep(".", math.floor(t * 2) % 4)
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 255, 200 + math.floor(55 * math.sin(t * 3))))
    nvgText(vg, cx, barY + 28, "搜索中" .. dots, nil)

    -- 奖励等级提示 (搜索快结束时闪现)
    if progress > 0.85 then
        local loot = state.chestSearchLoot
        local hintAlpha = math.floor(255 * ((progress - 0.85) / 0.15))
        local hint = "发现了什么..."
        local hc = { 200, 200, 200 }
        if loot and loot.hasEquipment then
            hint = "发现珍贵兵甲!"
            hc = { 255, 200, 80 }
        elseif loot and loot.frag and loot.frag > 0 then
            hint = "发现武技残页!"
            hc = { 180, 130, 255 }
        end
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(hc[1], hc[2], hc[3], hintAlpha))
        nvgText(vg, cx, barY + 54, hint, nil)
    end

    -- 搜索完成 → 转入奖励展示
    if progress >= 1.0 then
        state.chestSearching = false
        state.chestSearchTimer = 0
        state.showChestPopup = true
        state.chestPopupData = state.chestSearchLoot
        state.chestSearchLoot = nil
        -- 启动揭示特效
        state.chestRevealActive = true
        state.chestRevealTimer = 0
    end
end

local function DrawChestRevealEffect(W, H, dt)
    if not state.chestRevealActive then return end
    state.chestRevealTimer = state.chestRevealTimer + dt
    local t = state.chestRevealTimer
    local maxT = 1.0  -- 特效持续1秒

    if t > maxT then
        state.chestRevealActive = false
        return
    end

    local progress = t / maxT
    local cx, cy = W / 2, H / 2

    -- 中央闪光爆发
    local flashAlpha = math.floor(200 * (1 - progress))
    local flashR = 50 + 250 * progress
    local flashGrad = nvgRadialGradient(vg, cx, cy, 0, flashR,
        nvgRGBA(255, 240, 180, flashAlpha), nvgRGBA(255, 200, 100, 0))
    nvgBeginPath(vg); nvgRect(vg, cx - flashR, cy - flashR, flashR * 2, flashR * 2)
    nvgFillPaint(vg, flashGrad); nvgFill(vg)

    -- 向外飞散的光点
    local numParticles = 12
    for i = 1, numParticles do
        local angle = (i / numParticles) * math.pi * 2 + 0.3
        local dist = 30 + 180 * progress * (0.8 + 0.4 * math.sin(i * 2.1))
        local px = cx + math.cos(angle) * dist
        local py = cy + math.sin(angle) * dist
        local pAlpha = math.floor(220 * (1 - progress * progress))
        local pSize = (3 + 2 * math.sin(i)) * (1 - progress * 0.5)
        nvgBeginPath(vg); nvgCircle(vg, px, py, pSize)
        -- 交替金色和紫色粒子
        if i % 2 == 0 then
            nvgFillColor(vg, nvgRGBA(255, 220, 100, pAlpha))
        else
            nvgFillColor(vg, nvgRGBA(180, 130, 255, pAlpha))
        end
        nvgFill(vg)
    end

    -- 星形光芒
    if progress < 0.6 then
        local starAlpha = math.floor(180 * (1 - progress / 0.6))
        local starLen = 80 + 120 * progress
        nvgStrokeColor(vg, nvgRGBA(255, 240, 200, starAlpha))
        nvgStrokeWidth(vg, 2)
        for i = 0, 3 do
            local a = (i / 4) * math.pi + progress * 0.5
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx + math.cos(a) * 10, cy + math.sin(a) * 10)
            nvgLineTo(vg, cx + math.cos(a) * starLen, cy + math.sin(a) * starLen)
            nvgStroke(vg)
        end
    end
end

local function DrawChestPopup(W, H)
    if not state.chestPopupData then return end
    local loot = state.chestPopupData

    -- 计算奖励项数
    local itemCount = 0
    if loot.jade and loot.jade > 0 then itemCount = itemCount + 1 end
    if loot.frag and loot.frag > 0 then itemCount = itemCount + 1 end
    if loot.hasEquipment then itemCount = itemCount + 1 end
    if itemCount == 0 then itemCount = 1 end

    -- 暗幕
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 170)); nvgFill(vg)

    -- 弹窗面板
    local rowH = 64
    local pw = math.min(400, W - 40)
    local ph = 70 + itemCount * rowH + 70
    local px = (W - pw) / 2
    local py = (H - ph) / 2

    -- 面板背景 (深色渐变)
    local panelBg = nvgLinearGradient(vg, px, py, px, py + ph,
        nvgRGBA(28, 22, 38, 248), nvgRGBA(15, 12, 22, 248))
    nvgBeginPath(vg); nvgRoundedRect(vg, px, py, pw, ph, 12)
    nvgFillPaint(vg, panelBg); nvgFill(vg)
    -- 金色边框
    nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 180)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
    -- 顶部高光
    local topGlow = nvgLinearGradient(vg, px, py, px, py + 40,
        nvgRGBA(255, 220, 100, 30), nvgRGBA(255, 220, 100, 0))
    nvgBeginPath(vg); nvgRoundedRect(vg, px, py, pw, 40, 12)
    nvgFillPaint(vg, topGlow); nvgFill(vg)

    -- 标题: 玩家头像 + "获得战利品"
    local titleY = py + 18
    local avSize = 36
    local titleTextX = px + pw / 2
    -- 头像在标题左侧
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 24)
    local titleW = nvgTextBounds(vg, 0, 0, "获得战利品", nil)
    local totalTitleW = avSize + 8 + titleW
    local avX = px + (pw - totalTitleW) / 2
    local avCx, avCy = avX + avSize / 2, titleY + avSize / 2
    DrawPlayerAvatar(avCx, avCy, avSize, 6)
    -- 头像边框
    nvgBeginPath(vg); nvgRoundedRect(vg, avX, titleY, avSize, avSize, 6)
    nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 150)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    -- 标题文字
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, avX + avSize + 8, titleY + avSize / 2, "获得战利品", nil)

    -- 分隔线
    local sepY = titleY + avSize + 10
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 16, sepY)
    nvgLineTo(vg, px + pw - 16, sepY)
    nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 60)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    -- 奖励列表
    local curY = sepY + 10
    local iconSz = 44
    local contentX = px + 20
    local contentW = pw - 40

    -- 暗影石
    if loot.jade and loot.jade > 0 then
        -- 行背景
        nvgBeginPath(vg); nvgRoundedRect(vg, contentX, curY, contentW, rowH - 6, 8)
        nvgFillColor(vg, nvgRGBA(35, 25, 55, 180)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 130, 255, 60)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        -- 菱形图标
        nvgSave(vg)
        nvgTranslate(vg, contentX + 30, curY + (rowH - 6) / 2)
        nvgRotate(vg, math.rad(45))
        nvgBeginPath(vg); nvgRoundedRect(vg, -12, -12, 24, 24, 3)
        nvgFillColor(vg, nvgRGBA(160, 100, 255, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(210, 170, 255, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgRestore(vg)
        -- 名称
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(210, 180, 255, 240))
        nvgText(vg, contentX + 56, curY + (rowH - 6) / 2, "虎符", nil)
        -- 数量
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(230, 200, 255, 255))
        nvgText(vg, contentX + contentW - 12, curY + (rowH - 6) / 2, "×" .. loot.jade, nil)
        curY = curY + rowH
    end

    -- 碎片
    if loot.frag and loot.frag > 0 then
        nvgBeginPath(vg); nvgRoundedRect(vg, contentX, curY, contentW, rowH - 6, 8)
        nvgFillColor(vg, nvgRGBA(30, 20, 45, 180)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 120, 255, 60)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        -- 碎片图标
        DrawSprite(SPRITE.fragment.handle, contentX + 30, curY + (rowH - 6) / 2, 28, 255)
        -- 名称
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(180, 130, 255, 240))
        nvgText(vg, contentX + 56, curY + (rowH - 6) / 2, (GetSkillTechniqueName and loot.fragSkillIdx) and (GetSkillTechniqueName(loot.fragSkillIdx) .. "残页") or "武技残页", nil)
        -- 数量
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(200, 170, 255, 255))
        nvgText(vg, contentX + contentW - 12, curY + (rowH - 6) / 2, "×" .. loot.frag, nil)
        curY = curY + rowH
    end

    -- 装备
    if loot.hasEquipment then
        local tier = loot.equipTier or 1
        local setIdx = loot.equipSet or 1
        local slotIdx = loot.equipSlotIdx or 1
        local tc = playerData.equipTierColors[tier] or { 180, 175, 165 }
        local tierName = playerData.equipTierNames[tier] or "兵甲"
        local pieceName = ""
        if playerData.equipPieceNames[setIdx] and playerData.equipPieceNames[setIdx][slotIdx] then
            pieceName = playerData.equipPieceNames[setIdx][slotIdx]
        else
            pieceName = (playerData.equipSlotNames[slotIdx] or "兵甲")
        end

        -- 行背景 (品阶色调)
        nvgBeginPath(vg); nvgRoundedRect(vg, contentX, curY, contentW, rowH - 6, 8)
        nvgFillColor(vg, nvgRGBA(25, 20, 15, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 100)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        -- 品阶光晕
        local eqGlow = nvgBoxGradient(vg, contentX, curY, contentW, rowH - 6, 8, 10,
            nvgRGBA(tc[1], tc[2], tc[3], 20), nvgRGBA(tc[1], tc[2], tc[3], 0))
        nvgBeginPath(vg); nvgRoundedRect(vg, contentX - 1, curY - 1, contentW + 2, rowH - 4, 9)
        nvgFillPaint(vg, eqGlow); nvgFill(vg)
        -- 装备图标
        local eqIconSz = 40
        local eqIconX = contentX + 8
        local eqIconY = curY + ((rowH - 6) - eqIconSz) / 2
        DrawEquipIcon(eqIconX, eqIconY, eqIconSz, slotIdx, setIdx)
        -- 品阶小标签
        local badgeW, badgeH = 24, 12
        nvgBeginPath(vg); nvgRoundedRect(vg, eqIconX, eqIconY, badgeW, badgeH, 2)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 200)); nvgFill(vg)
        nvgFontSize(vg, 11); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, eqIconX + badgeW / 2, eqIconY + badgeH / 2, tierName, nil)
        -- 装备名称
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 240))
        nvgText(vg, contentX + 56, curY + (rowH - 6) / 2, pieceName, nil)
        -- 数量
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 255))
        nvgText(vg, contentX + contentW - 12, curY + (rowH - 6) / 2, "×1", nil)
        curY = curY + rowH
    end

    -- 收下按钮
    local btnW, btnH = 160, 42
    local btnX = px + (pw - btnW) / 2
    local btnY = curY + 10
    local btnBg = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
        nvgRGBA(100, 50, 140, 240), nvgRGBA(70, 30, 100, 240))
    nvgBeginPath(vg); nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
    nvgFillPaint(vg, btnBg); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 130, 255, 100)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(255, 240, 220, 255))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "收下", nil)
    -- 注册按钮
    state.btnRects["chest_ok"] = { x = btnX, y = btnY, w = btnW, h = btnH }
end

local function DrawRetreatPopup(W, H)
    DrawPopup(W, H, "到达撤离点!", {
        { text = "安全撤离，保留全部战利品!", color = COLORS.textGreen, size = 18 },
        { text = "战利品: " .. #state.tempLoot .. " 件", color = COLORS.textGold, size = 16 },
    }, {
        { text = "撤离 (100%保留)", key = "retreat_yes", color = COLORS.btnPrimary },
        { text = "继续探索", key = "retreat_no", color = COLORS.btnDanger },
    })
end

local function DrawAbandonPopup(W, H)
    DrawPopup(W, H, "!! 放弃探索", {
        { text = "未到达撤离点，所有战利品将丢失!", color = COLORS.textRed, size = 16 },
        { text = "当前战利品: " .. #state.tempLoot .. " 件 → 全部丢失", color = COLORS.textGold, size = 16 },
        { text = "必须到达撤离点才能保留收益!", color = COLORS.textWhite, size = 16 },
        { text = "退出不算完成，可再次进入(需门票)", color = { 180, 160, 120, 200 }, size = 14 },
    }, {
        { text = "放弃 (0收益)", key = "abandon_yes", color = COLORS.btnDanger },
        { text = "继续探索", key = "abandon_no", color = COLORS.btnPrimary },
    })
end

local function DrawResultPopup(W, H)
    if not state.resultData then return end
    local d = state.resultData
    local titleText = d.success and "探索完成!" or "紧急撤退"
    local titleColor = d.success and COLORS.textGreen or COLORS.textRed

    -- 免广告卡自动翻倍虎符
    if not state.adDoubledJade and d.totalJade > 0
        and Exploration.isBattleAdFree and Exploration.isBattleAdFree() then
        state.adDoubledJade = true
        d.totalJade = d.totalJade * 2
    end

    local lines = {
        { text = "步数: " .. d.moveCount .. "  击杀: " .. d.killCount, color = COLORS.textWhite, size = 16 },
        { text = "宝箱: " .. d.chestsOpened .. "/" .. d.chestsTotal, color = COLORS.textGold, size = 16 },
        { text = "保留比例: " .. math.floor(d.retainPct * 100) .. "%", color = d.success and COLORS.textGreen or COLORS.textRed, size = 16 },
    }
    if d.totalJade > 0 then
        local jadeText = "虎符 +" .. d.totalJade
        if state.adDoubledJade then jadeText = jadeText .. " (免广告卡已自动翻倍)" end
        lines[#lines + 1] = { text = jadeText, color = COLORS.textGold, size = 18 }
    end
    if d.fragList and #d.fragList > 0 then
        for _, fi in ipairs(d.fragList) do
            local skName = GetSkillTechniqueName and GetSkillTechniqueName(fi.skillIdx) or ("武技#" .. fi.skillIdx)
            lines[#lines + 1] = { text = skName .. "残页 +" .. fi.count, color = COLORS.textPurple, size = 18 }
        end
    elseif d.totalFrag and d.totalFrag > 0 then
        lines[#lines + 1] = { text = "武技残页 +" .. d.totalFrag, color = COLORS.textPurple, size = 18 }
    end
    if d.equipCount > 0 then
        lines[#lines + 1] = { text = "装备 x" .. d.equipCount, color = COLORS.textGreen, size = 18 }
    end

    -- 判断是否显示广告翻倍按钮
    local showAdBtn = not state.adDoubledJade
        and d.totalJade > 0
        and Exploration.canWatchAd
        and Exploration.canWatchAd()

    -- 计算面板高度: 标题 + 内容行 + 广告按钮(可选) + 返回按钮
    local adBtnSpace = showAdBtn and 70 or 0
    local doubledSpace = state.adDoubledJade and 28 or 0
    local ph = 60 + #lines * 28 + adBtnSpace + doubledSpace + 50 + 20
    local pw = 380
    local px = (W - pw) / 2
    local py = (H - ph) / 2

    -- 暗幕
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160)); nvgFill(vg)

    -- 面板
    DrawRoundedPanel(px, py, pw, ph, 12, COLORS.popupBg)

    -- 标题
    DrawText(px + pw / 2, py + 28, titleText, 22, titleColor)

    -- 内容行
    local curY = py + 55
    for _, line in ipairs(lines) do
        DrawText(px + pw / 2, curY, line.text, line.size or 16, line.color or COLORS.textWhite)
        curY = curY + 28
    end

    -- 广告翻倍按钮 或 已翻倍提示
    curY = curY + 10
    if showAdBtn then
        local abw, abh = 220, 38
        local abx = px + (pw - abw) / 2
        local aby = curY
        -- 绿色渐变按钮
        local adBg = nvgLinearGradient(vg, abx, aby, abx, aby + abh,
            nvgRGBA(40, 160, 80, 240), nvgRGBA(30, 120, 60, 240))
        nvgBeginPath(vg); nvgRoundedRect(vg, abx, aby, abw, abh, 8)
        nvgFillPaint(vg, adBg); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 255, 150, 120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 255, 220, 255))
        nvgText(vg, abx + abw / 2, aby + abh / 2, "看广告 虎符x2", nil)
        state.btnRects["result_ad_double"] = { x = abx, y = aby, w = abw, h = abh }
        curY = curY + 44
        -- 免广告卡提示
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(200, 200, 180, 160))
        nvgText(vg, px + pw / 2, curY, "设置中有当日免广告卡，3次即可获取", nil)
        curY = curY + 26
    elseif state.adDoubledJade then
        DrawText(px + pw / 2, curY, "虎符已翻倍!", 16, { 120, 255, 160 })
        state.btnRects["result_ad_double"] = nil
        curY = curY + 28
    else
        state.btnRects["result_ad_double"] = nil
    end

    -- 返回按钮
    DrawButton(px + (pw - 200) / 2, curY, 200, 38, "返回", COLORS.btnPrimary, "result_ok")
end

function Exploration.Draw(W, H, t)
    if not state.active then return end
    local prevT = state.animTimer
    state.animTimer = t or state.animTimer
    local dt = (prevT > 0) and (state.animTimer - prevT) or (1 / 60)
    if dt <= 0 then dt = 1 / 60 end
    if dt > 0.1 then dt = 0.1 end  -- 防止大跳帧

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(8, 6, 14, 255))
    nvgFill(vg)

    -- 网格
    local gridBottom = DrawGrid(W, H)

    -- HUD
    DrawHUD(W, H, gridBottom)

    -- 宝箱搜索动画 (优先级最高，覆盖所有弹窗)
    if state.chestSearching then
        DrawChestSearchAnimation(W, H, dt)
        return
    end

    -- 弹窗 (互斥)
    if state.showResultPopup then
        DrawResultPopup(W, H)
    elseif state.showRetreatConfirm then
        DrawRetreatPopup(W, H)
    elseif state.showAbandonConfirm then
        DrawAbandonPopup(W, H)
    elseif state.showChestPopup then
        DrawChestPopup(W, H)
        -- 揭示特效叠加在宝箱弹窗上方
        DrawChestRevealEffect(W, H, dt)
    elseif state.showScammerPopup then
        -- 骗子追击结果弹窗
        local sd = state.scammerPopupData or {}
        local sLines = {
            { text = sd.desc or "", color = sd.color or COLORS.textGreen, size = 18 },
            { text = sd.detail or "", color = COLORS.textWhite, size = 15 },
        }
        DrawPopup(W, H, sd.title or "追击", sLines, {
            { text = "确认", key = "scammer_ok", color = COLORS.btnPrimary },
        })
    elseif state.showEventPopup then
        DrawEventPopup(W, H)
    end
end

-- ============================================================================
-- 触摸输入
-- ============================================================================

function Exploration.HandlePress(dx, dy)
    if not state.active then return end

    -- 搜索动画中不接受点击
    if state.chestSearching then return end

    -- 弹窗优先处理
    if state.showResultPopup then
        -- 广告翻倍按钮
        if state.btnRects["result_ad_double"] and HitRect(state.btnRects["result_ad_double"], dx, dy) then
            if not state.adDoubledJade and Exploration.onWatchAdForDouble then
                Exploration.onWatchAdForDouble(function(success)
                    if success and state.resultData then
                        state.adDoubledJade = true
                        state.resultData.totalJade = (state.resultData.totalJade or 0) * 2
                    end
                end)
            end
            return
        end
        if state.btnRects["result_ok"] and HitRect(state.btnRects["result_ok"], dx, dy) then
            CloseAndExit()
        end
        return
    end

    if state.showRetreatConfirm then
        if state.btnRects["retreat_yes"] and HitRect(state.btnRects["retreat_yes"], dx, dy) then
            state.showRetreatConfirm = false
            FinishExploration(true)
        elseif state.btnRects["retreat_no"] and HitRect(state.btnRects["retreat_no"], dx, dy) then
            state.showRetreatConfirm = false
        end
        return
    end

    if state.showAbandonConfirm then
        if state.btnRects["abandon_yes"] and HitRect(state.btnRects["abandon_yes"], dx, dy) then
            state.showAbandonConfirm = false
            FinishExploration(false)
        elseif state.btnRects["abandon_no"] and HitRect(state.btnRects["abandon_no"], dx, dy) then
            state.showAbandonConfirm = false
        end
        return
    end

    if state.showScammerPopup then
        if state.btnRects["scammer_ok"] and HitRect(state.btnRects["scammer_ok"], dx, dy) then
            state.showScammerPopup = false
            state.scammerPopupData = nil
        end
        return
    end

    if state.showChestPopup then
        if state.btnRects["chest_ok"] and HitRect(state.btnRects["chest_ok"], dx, dy) then
            state.showChestPopup = false
            state.chestPopupData = nil
        end
        return
    end

    if state.showEventPopup then
        if state.btnRects["event_ok"] and HitRect(state.btnRects["event_ok"], dx, dy) then
            state.showEventPopup = false
            state.eventPopupData = nil
        elseif state.btnRects["event_buy"] and HitRect(state.btnRects["event_buy"], dx, dy) then
            local d = state.eventPopupData or {}
            local cost = d.shopCost or (GameConfig.EXPLORE_SHOP_COST or 40)
            state.showEventPopup = false
            state.eventPopupData = nil
            if d.shopEffect == "def_bonus" then
                -- 铁匠铺: 扣虎符 + 下次战斗防御加成
                state.nextBattleBuff = { type = "def_bonus", value = 0.3 }
                if Exploration.onShopPurchase then
                    Exploration.onShopPurchase(cost)
                end
            else
                -- 商人购买: 生成商品宝箱 → 搜索动画
                local shopLoot = GenerateChestLoot(state.gridSize, state.config)
                AddLoot(shopLoot)
                local duration = 1.5
                if shopLoot.hasEquipment then
                    duration = 4.0 + math.random() * 1.0
                elseif shopLoot.frag and shopLoot.frag > 0 then
                    duration = 2.5 + math.random() * 1.0
                else
                    duration = 1.2 + math.random() * 0.8
                end
                state.chestSearching = true
                state.chestSearchTimer = 0
                state.chestSearchDuration = duration
                state.chestSearchLoot = shopLoot
                if Exploration.onShopPurchase then
                    Exploration.onShopPurchase(cost)
                end
            end
        elseif state.btnRects["event_ambush_fight"] and HitRect(state.btnRects["event_ambush_fight"], dx, dy) then
            -- 精锐伏兵: 强制战斗, 战斗后双倍掉落
            state.showEventPopup = false
            state.eventPopupData = nil
            state.ambushBonusLoot = true  -- 标记下次战斗胜利双倍掉落
            -- 在当前位置生成一个临时敌人格子触发战斗
            local pr, pc = state.playerPos.row, state.playerPos.col
            state.grid[pr][pc].type = TILE_ENEMY
            state.grid[pr][pc].visited = false
            state.pendingBattleTile = state.grid[pr][pc]
            state.pendingBattleTile.row = pr
            state.pendingBattleTile.col = pc
            if Exploration.onStartBattle then
                Exploration.onStartBattle()
            end
        elseif state.btnRects["event_encounter_fight"] and HitRect(state.btnRects["event_encounter_fight"], dx, dy) then
            -- 遭遇战: 触发战斗
            local d = state.eventPopupData or {}
            state.showEventPopup = false
            state.eventPopupData = nil
            local pr = d.encounterRow or state.playerPos.row
            local pc = d.encounterCol or state.playerPos.col
            state.grid[pr][pc].type = TILE_ENEMY
            state.grid[pr][pc].visited = false
            state.pendingBattleTile = { row = pr, col = pc }
            if Exploration.onStartBattle then
                Exploration.onStartBattle(
                    (state.config.enemyScale or 1.0) * (0.85 + math.random() * 0.30),
                    state.config.maxTier or 1,
                    state.config.dropSets
                )
            end
        end
        return
    end

    -- 撤退按钮
    if state.btnRects["abandon"] and HitRect(state.btnRects["abandon"], dx, dy) then
        state.showAbandonConfirm = true
        return
    end

    -- 正在移动动画中不接受输入
    if state.moveAnim then return end

    -- 格子点击
    for key, rect in pairs(state.tileRects) do
        if HitRect(rect, dx, dy) then
            local r, c = rect.row, rect.col
            -- 判断是否相邻
            local dr = math.abs(r - state.playerPos.row)
            local dc = math.abs(c - state.playerPos.col)
            if (dr == 1 and dc == 0) or (dr == 0 and dc == 1) then
                -- 检查是否为被看守宝箱且无法移动
                local tile = state.grid[r][c]
                if tile.type == TILE_CHEST and tile.guarded and not tile.guardCleared and not CanMoveTo(r, c) then
                    if Exploration.onShowToast then
                        Exploration.onShowToast("宝箱被看守!需先击败周围敌人")
                    end
                else
                    DoMove(r, c)
                end
            end
            return
        end
    end
end

-- ============================================================================
-- 存档
-- ============================================================================

function Exploration.GetState()
    if not state.active then return nil end
    return DeepCopySimple(state)
end

function Exploration.RestoreState(saved)
    if not saved then return end
    -- 恢复所有状态
    for k, v in pairs(saved) do
        state[k] = v
    end
    -- 重建 btnRects/tileRects (渲染时自动填充)
    state.btnRects = {}
    state.tileRects = {}
end

function Exploration.GetBuff()
    return state.nextBattleBuff
end

function Exploration.ClearBuff()
    state.nextBattleBuff = nil
end

--- 强制放弃探索 (从战斗中直接退出时调用)
--- 以 LOOT_RETAIN_ABANDON (0%) 保留率结算战利品并触发 onComplete 回调
function Exploration.ForceAbandon()
    if not state.active then return end
    FinishExploration(false)
    -- 直接触发回调并关闭
    state.active = false
    state.showResultPopup = false
    if Exploration.onComplete and state.resultData then
        Exploration.onComplete(state.resultData)
    end
end

--- 强制撤退并指定保留比例 (讨伐战中途退出用: 保留30%)
---@param retainPct number 保留比例 (0.0 ~ 1.0)
function Exploration.ForceAbandonWithRetain(retainPct)
    if not state.active then return end
    retainPct = retainPct or 0.0
    local finalLoot = CalculateRetainedLoot(retainPct)
    -- 统计奖励总和
    local totalJade = 0
    local equipCount = 0
    local fragMap = {}
    local totalFrag = 0
    for _, loot in ipairs(finalLoot) do
        totalJade = totalJade + (loot.jade or 0)
        if (loot.frag or 0) > 0 and loot.fragSkillIdx then
            local si = loot.fragSkillIdx
            fragMap[si] = (fragMap[si] or 0) + loot.frag
            totalFrag = totalFrag + loot.frag
        end
        if loot.hasEquipment then equipCount = equipCount + 1 end
    end
    local fragList = {}
    for si, cnt in pairs(fragMap) do
        fragList[#fragList + 1] = { skillIdx = si, count = cnt }
    end
    state.resultData = {
        success = false,
        loot = finalLoot,
        totalJade = totalJade,
        totalFrag = totalFrag,
        fragList = fragList,
        equipCount = equipCount,
        retainPct = retainPct,
        mode = state.config.mode,
        stageIdx = state.config.stageIdx,
        abyssFloor = state.config.abyssFloor,
        moveCount = state.moveCount,
        killCount = state.killCount,
        chestsOpened = state.chestsOpened,
        chestsTotal = state.chestsTotal,
    }
    -- 直接触发回调并关闭
    state.active = false
    state.showResultPopup = false
    if Exploration.onComplete and state.resultData then
        Exploration.onComplete(state.resultData)
    end
end

return Exploration
