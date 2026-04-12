-- exploration_core.lua - 三国武灵录 (从 exploration.lua 拆分)
-- 初始化 + 数据 + 地图生成 + 游戏逻辑
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
    -- 同步给 render 模块
    Exploration._.vg = vg
    Exploration._.fontId = fontId
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
-- 导出给 exploration_render.lua 使用的内部引用
-- ============================================================================
Exploration._ = {
    -- 模块级状态
    state      = state,
    playerData = playerData,
    GameConfig = GameConfig,
    -- NanoVG 上下文（Init 中赋值: vg, fontId）
    vg = nil, fontId = nil,
    -- 常量
    TILE_EMPTY = TILE_EMPTY, TILE_ENEMY = TILE_ENEMY, TILE_CHEST = TILE_CHEST,
    TILE_RETREAT = TILE_RETREAT, TILE_BLOCKED = TILE_BLOCKED, TILE_EVENT = TILE_EVENT,
    TILE_START = TILE_START, TILE_SCAMMER = TILE_SCAMMER,
    DIRS   = DIRS,
    COLORS = COLORS,
    SPRITE = SPRITE,
    -- 共享辅助函数
    HitRect        = HitRect,
    DeepCopySimple = DeepCopySimple,
    Shuffle        = Shuffle,
    CanMoveTo      = CanMoveTo,
    DoMove         = DoMove,
    AddLoot        = AddLoot,
    GenerateChestLoot = GenerateChestLoot,
}

return Exploration
