-- exploration_render.lua - 三国武灵录 (从 exploration.lua 拆分)
-- 撤离结算 + NanoVG 渲染 + 输入处理
-- ============================================================================

local Exploration = require "exploration_core"
local S = Exploration._

-- 解构共享状态和常量为 local（保持原代码不变）
local state      = S.state
local playerData = S.playerData
local GameConfig = S.GameConfig
local TILE_EMPTY   = S.TILE_EMPTY
local TILE_ENEMY   = S.TILE_ENEMY
local TILE_CHEST   = S.TILE_CHEST
local TILE_RETREAT = S.TILE_RETREAT
local TILE_BLOCKED = S.TILE_BLOCKED
local TILE_EVENT   = S.TILE_EVENT
local TILE_START   = S.TILE_START
local TILE_SCAMMER = S.TILE_SCAMMER
local DIRS   = S.DIRS
local COLORS = S.COLORS
local SPRITE = S.SPRITE
local HitRect        = S.HitRect
local DeepCopySimple = S.DeepCopySimple
local Shuffle        = S.Shuffle
local CanMoveTo      = S.CanMoveTo
local DoMove         = S.DoMove
local AddLoot        = S.AddLoot
local GenerateChestLoot = S.GenerateChestLoot

-- vg/fontId 在 Init 后才赋值，由入口函数 Draw/HandlePress 延迟同步
local vg, fontId
local function _syncCtx()
    vg = S.vg
    fontId = S.fontId
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
    _syncCtx()
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
    _syncCtx()
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

