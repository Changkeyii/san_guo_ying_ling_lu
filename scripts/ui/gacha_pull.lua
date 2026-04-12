-- ============================================================================
-- ui/gacha_pull.lua - 三国武灵录 (抽卡动画 + 结果展示 + 残片商店)
-- ============================================================================
function DrawGachaPullAnimation(t)
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local cy = H * 0.40
    local progress = math.min(1, gachaState.pullTimer / 1.2)

    -- 扩大的光圈
    local maxR = 120
    local r = maxR * progress
    local glow = nvgRadialGradient(vg, cx, cy, r * 0.3, r,
        nvgRGBA(255, 230, 120, math.floor(120 * (1 - progress * 0.5))),
        nvgRGBA(180, 140, 60, 0))
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, r)
    nvgFillPaint(vg, glow); nvgFill(vg)

    -- 旋转光线
    local lineCount = gachaState.pullCount == 10 and 20 or 8
    for i = 1, lineCount do
        local angle = (i / lineCount) * math.pi * 2 + t * 4
        local len = 30 + 80 * progress
        local sx = cx + math.cos(angle) * 10
        local sy = cy + math.sin(angle) * 10
        local ex = cx + math.cos(angle) * len
        local ey = cy + math.sin(angle) * len
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy); nvgLineTo(vg, ex, ey)
        local la = math.floor(180 * (1 - progress * 0.3))
        nvgStrokeColor(vg, nvgRGBA(255, 220, 100, la))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    end

    -- 中心闪光
    local flashA = math.floor(255 * math.max(0, progress - 0.6) / 0.4)
    if flashA > 0 then
        nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(255, 245, 220, flashA)); nvgFill(vg)
    end

    -- 提示文字
    nvgFontFaceId(vg, GetMainFont())
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, H * 0.72, "点击跳过")
end


--- 抽卡结果展示
function DrawGachaResults()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local results = gachaState.results
    local count = #results

    -- 半透明全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 标题
    nvgFontSize(vg, 33)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, 65, count > 10 and ("召唤结果 ×" .. count) or "召唤结果")

    if count == 0 then return end

    -- 品质颜色
    local QCOLORS = {
        [1] = { 180, 180, 170 }, -- N
        [2] = { 100, 200, 120 }, -- R
        [3] = { 80, 160, 255 },  -- SR
        [4] = { 255, 200, 60 },  -- SSR
    }

    if count == 1 then
        -- 单抽: 大卡居中显示
        local cardW = 120
        local cardH = cardW / CARD_RATIO
        local cardX = cx - cardW / 2
        local cardY = H * 0.25
        local r = results[1]
        local card = HERO_CARDS[r.cardIdx]
        DrawInventoryCard(cardX, cardY, cardW, cardH, card, r.constellation or 0, false)

        local tagY = cardY + cardH + 12
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        if r.isFullCard then
            -- 整卡结果
            if r.isNew then
                nvgFillColor(vg, nvgRGBA(120, 255, 160, 240))
                nvgText(vg, cx, tagY, "新! " .. card.name, nil)
            elseif r.jadeRefund and r.jadeRefund > 0 then
                nvgFillColor(vg, nvgRGBA(255, 215, 0, 240))
                nvgText(vg, cx, tagY, card.name .. " 满命格", nil)
                nvgFontSize(vg, 27)
                nvgText(vg, cx, tagY + 24, "返还 " .. r.jadeRefund .. " 虎符", nil)
            else
                local cc = GameConfig.CONSTELLATION_COLORS[r.constellation] or { 180, 175, 165 }
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 240))
                nvgText(vg, cx, tagY, card.name .. " C" .. r.oldConst .. " >> C" .. r.constellation, nil)
            end
        else
            -- 残片结果
            local qc = QCOLORS[card.quality] or { 180, 180, 170 }
            nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 240))
            nvgText(vg, cx, tagY, card.name .. " 残片 ×" .. r.fragCount, nil)
            -- 进度
            local need = HERO_FRAG_EXCHANGE[card.quality] or 20
            local total = heroFragments[r.cardIdx] or 0
            nvgFontSize(vg, 24)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, cx, tagY + 28, "累计 " .. total .. "/" .. need, nil)
        end
    elseif count <= 10 then
        -- 按品质降序排序（高品质排前面）
        table.sort(results, function(a, b)
            local qa = HERO_CARDS[a.cardIdx] and HERO_CARDS[a.cardIdx].quality or 0
            local qb = HERO_CARDS[b.cardIdx] and HERO_CARDS[b.cardIdx].quality or 0
            return qa > qb
        end)
        -- 十连: 5列×2行 网格
        local cols = 5
        local cardW = 80
        local cardH = cardW / CARD_RATIO
        local gap = 8
        local gridW = cols * cardW + (cols - 1) * gap
        local startX = cx - gridW / 2
        local startY = 85

        for i, r in ipairs(results) do
            local col = ((i - 1) % cols)
            local row = math.floor((i - 1) / cols)
            local x = startX + col * (cardW + gap)
            local y = startY + row * (cardH + 28 + gap)
            local card = HERO_CARDS[r.cardIdx]

            DrawInventoryCard(x, y, cardW, cardH, card, r.constellation or 0, false)

            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

            if r.isFullCard then
                -- 整卡标记
                if r.isNew then
                    nvgFillColor(vg, nvgRGBA(120, 255, 160, 220))
                    nvgText(vg, x + cardW / 2, y + cardH + 2, "新!", nil)
                elseif r.jadeRefund and r.jadeRefund > 0 then
                    nvgFillColor(vg, nvgRGBA(255, 215, 0, 220))
                    nvgText(vg, x + cardW / 2, y + cardH + 2, "+" .. r.jadeRefund .. "玉", nil)
                else
                    local cc = GameConfig.CONSTELLATION_COLORS[r.constellation] or { 180, 175, 165 }
                    nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 200))
                    nvgText(vg, x + cardW / 2, y + cardH + 2, "C" .. r.oldConst .. ">>" .. r.constellation, nil)
                end
            else
                -- 残片标记
                local qc = QCOLORS[card.quality] or { 180, 180, 170 }
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 220))
                nvgText(vg, x + cardW / 2, y + cardH + 2, "残片×" .. r.fragCount, nil)
                -- 进度小字
                local need = HERO_FRAG_EXCHANGE[card.quality] or 20
                local total = heroFragments[r.cardIdx] or 0
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
                nvgText(vg, x + cardW / 2, y + cardH + 16, total .. "/" .. need, nil)
            end
        end
    else
        -- 按品质降序排序（高品质排前面）
        table.sort(results, function(a, b)
            local qa = HERO_CARDS[a.cardIdx] and HERO_CARDS[a.cardIdx].quality or 0
            local qb = HERO_CARDS[b.cardIdx] and HERO_CARDS[b.cardIdx].quality or 0
            return qa > qb
        end)
        -- 大量抽卡汇总展示 (50连/100连)
        -- 统计各品质数量
        local qualityCounts = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
        local notableResults = {}  -- SSR + 新获得的SR
        local totalRefund = 0
        local totalFragCount = 0
        for _, r in ipairs(results) do
            local card = HERO_CARDS[r.cardIdx]
            qualityCounts[card.quality] = (qualityCounts[card.quality] or 0) + 1
            if r.jadeRefund then totalRefund = totalRefund + r.jadeRefund end
            if r.fragCount then totalFragCount = totalFragCount + r.fragCount end
            -- 收集SSR和新获得的SR作为亮点
            if card.quality == 4 or (card.quality == 3 and r.isNew) then
                table.insert(notableResults, r)
            end
        end

        -- 品质汇总条
        local sumY = 95
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        local qLabels = {}
        if qualityCounts[4] > 0 then
            table.insert(qLabels, { text = "SSR ×" .. qualityCounts[4], color = { 255, 200, 60 } })
        end
        if qualityCounts[3] > 0 then
            table.insert(qLabels, { text = "SR ×" .. qualityCounts[3], color = { 80, 160, 255 } })
        end
        if qualityCounts[2] > 0 then
            table.insert(qLabels, { text = "R ×" .. qualityCounts[2], color = { 100, 200, 120 } })
        end
        if qualityCounts[1] > 0 then
            table.insert(qLabels, { text = "N ×" .. qualityCounts[1], color = { 180, 180, 170 } })
        end

        -- 居中绘制品质标签
        local totalLabelW = 0
        local labelGap = 16
        for _, ql in ipairs(qLabels) do
            totalLabelW = totalLabelW + nvgTextBounds(vg, 0, 0, ql.text, nil)
        end
        totalLabelW = totalLabelW + labelGap * math.max(0, #qLabels - 1)
        local labelX = cx - totalLabelW / 2
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        for _, ql in ipairs(qLabels) do
            nvgFillColor(vg, nvgRGBA(ql.color[1], ql.color[2], ql.color[3], 240))
            nvgText(vg, labelX, sumY, ql.text, nil)
            labelX = labelX + nvgTextBounds(vg, 0, 0, ql.text, nil) + labelGap
        end

        -- 残片/返还统计
        local statsY = 120
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local statsText = ""
        if totalFragCount > 0 then
            statsText = "残片 ×" .. totalFragCount
        end
        if totalRefund > 0 then
            if #statsText > 0 then statsText = statsText .. "  |  " end
            statsText = statsText .. "返还 " .. totalRefund .. " 虎符"
        end
        if #statsText > 0 then
            nvgFillColor(vg, nvgRGBA(200, 195, 180, 200))
            nvgText(vg, cx, statsY, statsText, nil)
        end

        -- 亮点武灵展示 (SSR + 新SR, 最多10张)
        local showResults = notableResults
        local showCount = #showResults
        local gridStartY = 145

        if showCount == 0 then
            -- 没有亮点: 显示所有结果的紧凑网格
            showResults = results
            showCount = math.min(#results, 20)  -- 最多显示20张
            nvgFontSize(vg, 15)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 195, 180, 160))
            nvgText(vg, cx, gridStartY, "本次未获得SSR/新SR", nil)
            gridStartY = 170
        else
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 200))
            nvgText(vg, cx, gridStartY, "亮点武灵", nil)
            gridStartY = 168
            showCount = math.min(showCount, 10)
        end

        -- 绘制亮点卡片网格 (自适应列数)
        if showCount > 0 then
            local cols = math.min(showCount, 5)
            local cardW = showCount <= 5 and 80 or 64
            local cardH = cardW / CARD_RATIO
            local gap = showCount <= 5 and 8 or 6
            local gridW = cols * cardW + (cols - 1) * gap
            local startX = cx - gridW / 2

            for i = 1, showCount do
                local r = showResults[i]
                local col = ((i - 1) % cols)
                local row = math.floor((i - 1) / cols)
                local x = startX + col * (cardW + gap)
                local y = gridStartY + row * (cardH + 28 + gap)
                local card = HERO_CARDS[r.cardIdx]

                DrawInventoryCard(x, y, cardW, cardH, card, r.constellation or 0, false)

                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

                if r.isFullCard then
                    if r.isNew then
                        nvgFillColor(vg, nvgRGBA(120, 255, 160, 220))
                        nvgText(vg, x + cardW / 2, y + cardH + 2, "新!", nil)
                    elseif r.jadeRefund and r.jadeRefund > 0 then
                        nvgFillColor(vg, nvgRGBA(255, 215, 0, 220))
                        nvgText(vg, x + cardW / 2, y + cardH + 2, "+" .. r.jadeRefund .. "玉", nil)
                    else
                        local cc = GameConfig.CONSTELLATION_COLORS[r.constellation] or { 180, 175, 165 }
                        nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 200))
                        nvgText(vg, x + cardW / 2, y + cardH + 2, "C" .. r.oldConst .. ">>" .. r.constellation, nil)
                    end
                else
                    local qc = QCOLORS[card.quality] or { 180, 180, 170 }
                    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 220))
                    nvgText(vg, x + cardW / 2, y + cardH + 2, "残片×" .. r.fragCount, nil)
                end
            end
        end
    end

    -- 确认按钮
    local confirmW = 140
    local confirmH = 38
    local confirmX = cx - confirmW / 2
    local confirmY = H * 0.88
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, confirmY, confirmW, confirmH, 5)
    nvgFillColor(vg, nvgRGBA(25, 30, 50, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 180)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, confirmY + confirmH / 2, "确 认")
    gachaConfirmBtnRect = { x = confirmX, y = confirmY, w = confirmW, h = confirmH }
end


-- ============================================================================
-- 武技召唤 - 待机界面
-- ============================================================================
function DrawSkillGachaIdle(t)
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local circleY = H * 0.42
    local circleR = 95

    -- 武技召唤阵 (紫色系, 与武灵金色区分)
    for i = 1, 10 do
        local angle = (i / 10) * math.pi * 2 + t * 0.8
        local arcLen = math.pi / 7
        local r = circleR + 6 + 3 * math.sin(t * 2 + i)
        nvgBeginPath(vg)
        nvgArc(vg, cx, circleY, r, angle, angle + arcLen, NVG_CW)
        local pulse = 0.4 + 0.6 * math.sin(t * 1.5 + i * 0.6)
        nvgStrokeColor(vg, nvgRGBA(160, 100, 220, math.floor(100 * pulse)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    end
    for i = 1, 6 do
        local angle = -(i / 6) * math.pi * 2 + t * 1.2
        local arcLen = math.pi / 5
        nvgBeginPath(vg)
        nvgArc(vg, cx, circleY, circleR - 5, angle, angle + arcLen, NVG_CW)
        local pulse = 0.3 + 0.7 * math.sin(t * 2.5 + i * 0.9)
        nvgStrokeColor(vg, nvgRGBA(180, 130, 255, math.floor(80 * pulse)))
        nvgStrokeWidth(vg, 1.0); nvgStroke(vg)
    end

    -- 中心光晕 (紫色)
    local glowPulse = 0.6 + 0.4 * math.sin(t * 2)
    local glow = nvgRadialGradient(vg, cx, circleY, 5, circleR * 0.8,
        nvgRGBA(140, 80, 200, math.floor(40 * glowPulse)),
        nvgRGBA(100, 60, 180, 0))
    nvgBeginPath(vg); nvgCircle(vg, cx, circleY, circleR * 0.8)
    nvgFillPaint(vg, glow); nvgFill(vg)

    -- 中心文字
    nvgFontFaceId(vg, GetMainFont())
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local textPulse = 0.6 + 0.4 * math.sin(t * 1.8)
    nvgFillColor(vg, nvgRGBA(200, 160, 255, math.floor(180 * textPulse)))
    nvgText(vg, cx, circleY, "功 法 感 悟", nil)

    nvgFontSize(vg, 14)
    DrawWhiteInkText(cx, circleY + 32, "消耗虎符, 感悟武技残片")

    -- 抽卡按钮
    local bigPull = playerInfo.jadeUnlockedBigPull
    gachaHundredBtnRect = nil

    if bigPull then
        -- 增强模式: 3个按钮 (10连/50连/100连) 紫色调
        local btnW = 160
        local btnH = 46
        local btnGap = 8
        local btnY1 = H * 0.62
        local btnY2 = btnY1 + btnH + btnGap
        local btnY3 = btnY2 + btnH + btnGap
        local unitCost = GameConfig.GACHA_COST_SINGLE
        local fragPer = SKILL_FRAG_PER_PULL  -- 单抽5个残片

        -- 10连 (出50残片)
        local b1x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b1x, btnY1, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(30, 20, 50, 200)); nvgFill(vg)
        local bp1 = 0.7 + 0.3 * math.sin(t * 2)
        nvgStrokeColor(vg, nvgRGBA(160, 100, 220, math.floor(180 * bp1)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 - 7, "十连感悟 ×" .. (fragPer * 10))
        nvgFontSize(vg, 14)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 + 12, math.floor(unitCost * 10 * 0.9) .. " 虎符 (9折)")
        gachaSingleBtnRect = { x = b1x, y = btnY1, w = btnW, h = btnH }

        -- 50连 (出250残片)
        local b2x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        local g50 = nvgLinearGradient(vg, b2x, btnY2, b2x + btnW, btnY2 + btnH,
            nvgRGBA(40, 20, 60, 220), nvgRGBA(55, 25, 80, 220))
        nvgFillPaint(vg, g50); nvgFill(vg)
        local bp2 = 0.6 + 0.4 * math.sin(t * 2.5)
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(200, 140, 255, math.floor(200 * bp2)))
        nvgStrokeWidth(vg, 1.8); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 - 7, "五十连 ×" .. (fragPer * 50))
        nvgFontSize(vg, 14)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 + 12, math.floor(unitCost * 50 * 0.9) .. " 虎符 (9折)")
        gachaTenBtnRect = { x = b2x, y = btnY2, w = btnW, h = btnH }

        -- 100连 (出500残片)
        local b3x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b3x, btnY3, btnW, btnH, 6)
        local g100 = nvgLinearGradient(vg, b3x, btnY3, b3x + btnW, btnY3 + btnH,
            nvgRGBA(50, 15, 75, 230), nvgRGBA(65, 10, 90, 230))
        nvgFillPaint(vg, g100); nvgFill(vg)
        local bp3 = 0.5 + 0.5 * math.sin(t * 3)
        nvgBeginPath(vg); nvgRoundedRect(vg, b3x, btnY3, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(240, 180, 255, math.floor(220 * bp3)))
        nvgStrokeWidth(vg, 2.0); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY3 + btnH / 2 - 7, "百连感悟 ×" .. (fragPer * 100))
        nvgFontSize(vg, 14)
        DrawWhiteInkText(cx, btnY3 + btnH / 2 + 12, math.floor(unitCost * 100 * 0.9) .. " 虎符 (9折)")
        gachaHundredBtnRect = { x = b3x, y = btnY3, w = btnW, h = btnH }
    else
        -- 原始模式: 2个按钮 (单抽/十连)
        local btnW = 160
        local btnH = 56
        local btnGap = 16
        local btnY1 = H * 0.66
        local btnY2 = btnY1 + btnH + btnGap

        -- 单抽按钮 (出5残片)
        local b1x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b1x, btnY1, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(30, 20, 50, 200)); nvgFill(vg)
        local bp1 = 0.7 + 0.3 * math.sin(t * 2)
        nvgStrokeColor(vg, nvgRGBA(160, 100, 220, math.floor(180 * bp1)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 - 10, "感悟 ×5")
        nvgFontSize(vg, 16)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 + 20, GameConfig.GACHA_COST_SINGLE .. " 虎符")
        gachaSingleBtnRect = { x = b1x, y = btnY1, w = btnW, h = btnH }

        -- 十连按钮 (出50残片)
        local b2x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        local tenGrad = nvgLinearGradient(vg, b2x, btnY2, b2x + btnW, btnY2 + btnH,
            nvgRGBA(40, 20, 60, 220), nvgRGBA(55, 25, 80, 220))
        nvgFillPaint(vg, tenGrad); nvgFill(vg)
        local bp2 = 0.6 + 0.4 * math.sin(t * 2.5)
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(200, 140, 255, math.floor(200 * bp2)))
        nvgStrokeWidth(vg, 1.8); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 - 10, "十连感悟 ×50")
        nvgFontSize(vg, 16)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 + 20, GameConfig.GACHA_COST_TEN .. " 虎符 (9折)")
        gachaTenBtnRect = { x = b2x, y = btnY2, w = btnW, h = btnH }
    end

    -- 计算最后一个按钮底部Y (兼容增强模式3按钮)
    local lastBtnBottom = gachaHundredBtnRect and (gachaHundredBtnRect.y + gachaHundredBtnRect.h) or (gachaTenBtnRect.y + gachaTenBtnRect.h)

    -- 残片兑换提示
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, lastBtnBottom + 20, "集齐49个同名残片可兑换完整武技")

    -- 已收集残片统计
    local fragTotal = 0
    local fragTypes = 0
    for _, cnt in pairs(skillFragments) do
        fragTotal = fragTotal + cnt
        fragTypes = fragTypes + 1
    end
    nvgFontSize(vg, 14)
    DrawWhiteInkText(cx, lastBtnBottom + 52, "已收集 " .. fragTotal .. " 残片 (" .. fragTypes .. " 种)")

    -- (万能残片已移除，不再显示)

    -- 可兑换列表预览（最多显示3个最接近兑换的）
    local exchangeable = {}
    for skillIdx, cnt in pairs(skillFragments) do
        if cnt >= SKILL_FRAG_EXCHANGE then
            table.insert(exchangeable, { idx = skillIdx, cnt = cnt })
        end
    end
    if #exchangeable > 0 then
        nvgFontSize(vg, 14)
        DrawWhiteInkText(cx, lastBtnBottom + 84, "有 " .. #exchangeable .. " 个武技可兑换! 前往武技")
    end

    -- 底部按钮行：概率规则(?) + 残片仓库
    local bottomBtnY = lastBtnBottom + 8

    -- 残片仓库按钮（左侧）
    local shopBtnW = 90
    local shopBtnH = 30
    local shopBtnX = 12
    nvgBeginPath(vg); nvgRoundedRect(vg, shopBtnX, bottomBtnY, shopBtnW, shopBtnH, 6)
    nvgFillColor(vg, nvgRGBA(35, 25, 55, 210)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 130, 220, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(shopBtnX + shopBtnW / 2, bottomBtnY + shopBtnH / 2, "残片仓库")
    -- 可合成红点提示（含武灵+武技）
    local canComposeCount = 0
    for cardIdx, cnt in pairs(heroFragments) do
        local card = HERO_CARDS[cardIdx]
        if card and cnt >= (HERO_FRAG_EXCHANGE[card.quality] or 20) then canComposeCount = canComposeCount + 1 end
    end
    for _, cnt in pairs(skillFragments) do
        if cnt >= SKILL_FRAG_EXCHANGE then canComposeCount = canComposeCount + 1 end
    end
    if canComposeCount > 0 then
        local dotR = 7
        local dotX = shopBtnX + shopBtnW - 4
        local dotY = bottomBtnY + 4
        nvgBeginPath(vg); nvgCircle(vg, dotX, dotY, dotR)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 230)); nvgFill(vg)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(dotX, dotY, tostring(canComposeCount))
    end
    gachaFragShopBtnRect = { x = shopBtnX, y = bottomBtnY, w = shopBtnW, h = shopBtnH }

    -- 概率规则按钮（右侧）
    local qBtnSize = 30
    local qBtnX = W - qBtnSize - 12
    local qBtnY = bottomBtnY
    nvgBeginPath(vg); nvgCircle(vg, qBtnX + qBtnSize / 2, qBtnY + qBtnSize / 2, qBtnSize / 2)
    nvgFillColor(vg, nvgRGBA(40, 30, 65, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 100, 200, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(qBtnX + qBtnSize / 2, qBtnY + qBtnSize / 2, "?")
    gachaRulesBtnRect = { x = qBtnX, y = qBtnY, w = qBtnSize, h = qBtnSize }
end


-- ============================================================================
-- 武技召唤 - 结果展示
-- ============================================================================
function DrawSkillGachaResults()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local results = gachaState.skillResults
    local count = #results

    -- 半透明全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 标题
    nvgFontSize(vg, 33)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, 65, "感悟结果")

    if count == 0 then return end

    -- 武技残片tier对应颜色 (7阶, 与 SKILL_TIERS 对齐)
    local TIER_COLORS = {
        { 180, 175, 165 },  -- 凡品 灰
        { 100, 210, 120 },  -- 良品 绿
        { 80, 160, 255 },   -- 优品 蓝
        { 180, 100, 255 },  -- 将品 紫
        { 255, 140, 0 },    -- 侯品 橙
        { 255, 180, 50 },   -- 王品 金
        { 255, 80, 80 },    -- 帝品 红
    }

    -- 按等阶降序排序（高品质排前面）
    if count > 1 then
        table.sort(results, function(a, b)
            local ta = SKILL_TECHNIQUES[a.skillIdx] and SKILL_TECHNIQUES[a.skillIdx].tier or 0
            local tb = SKILL_TECHNIQUES[b.skillIdx] and SKILL_TECHNIQUES[b.skillIdx].tier or 0
            return ta > tb
        end)
    end

    -- 网格展示残片（带武技图标）
    local cols = math.min(count, 4)
    local cardW = 90
    local cardH = 130
    local gap = 8
    local gridW = cols * cardW + (cols - 1) * gap
    local startX = cx - gridW / 2
    local startY = 85

    for i, r in ipairs(results) do
        local col = ((i - 1) % cols)
        local row = math.floor((i - 1) / cols)
        local x = startX + col * (cardW + gap)
        local y = startY + row * (cardH + gap)
        local tech = SKILL_TECHNIQUES[r.skillIdx]
        local tier = tech.tier
        local tc = TIER_COLORS[tier] or { 180, 180, 170 }

        -- 残片卡片背景
        nvgBeginPath(vg); nvgRoundedRect(vg, x, y, cardW, cardH, 8)
        nvgFillColor(vg, nvgRGBA(20, 15, 35, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 180)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

        -- 武技图标（居中显示）
        local iconSize = 52
        local iconX = x + (cardW - iconSize) / 2
        local iconY = y + 6
        drawSkillIcon(tech.iconIdx, iconX, iconY, iconSize, 6)

        -- 残片数量标签（图标右下角叠加）
        local badgeX = iconX + iconSize - 8
        local badgeY = iconY + iconSize - 10
        nvgBeginPath(vg); nvgRoundedRect(vg, badgeX - 10, badgeY - 6, 26, 16, 4)
        nvgFillColor(vg, nvgRGBA(30, 20, 50, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(badgeX + 3, badgeY + 2, "×" .. r.fragCount)

        -- 武技名（图标下方）
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 240))
        nvgText(vg, x + cardW / 2, y + 68, tech.name, nil)

        -- 等阶标签
        local tierInfo = SKILL_TIERS[tier]
        local tierLabel = tierInfo and tierInfo.name or ("T" .. tier)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 160))
        nvgText(vg, x + cardW / 2, y + 82, tierLabel, nil)

        -- 累计进度条
        local barW = cardW - 16
        local barH = 8
        local barX = x + 8
        local barY = y + 92
        local total = r.totalFrags
        local progress = math.min(total / SKILL_FRAG_EXCHANGE, 1.0)

        nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(40, 30, 60, 200)); nvgFill(vg)

        if progress > 0 then
            local fillColor = total >= SKILL_FRAG_EXCHANGE
                and nvgRGBA(255, 200, 60, 240)
                or nvgRGBA(tc[1], tc[2], tc[3], 200)
            nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3)
            nvgFillColor(vg, fillColor); nvgFill(vg)
        end

        -- 进度文字 x/49
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if total >= SKILL_FRAG_EXCHANGE then
            DrawWhiteInkText(x + cardW / 2, y + 112, "可合成!")
        else
            DrawWhiteInkText(x + cardW / 2, y + 112, total .. "/" .. SKILL_FRAG_EXCHANGE)
        end
    end

    -- 确认按钮
    local confirmW = 140
    local confirmH = 38
    local confirmX = cx - confirmW / 2
    local confirmY = H * 0.88
    nvgBeginPath(vg); nvgRoundedRect(vg, confirmX, confirmY, confirmW, confirmH, 5)
    nvgFillColor(vg, nvgRGBA(25, 20, 50, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 100, 200, 180)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, confirmY + confirmH / 2, "确 认")
    gachaConfirmBtnRect = { x = confirmX, y = confirmY, w = confirmW, h = confirmH }
end


-- ============================================================================
-- 残片商店 (召唤Tab 3) — 重做版
-- ============================================================================
function DrawFragmentShop(t)
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2

    -- 半透明黑色遮罩 (0.6 不透明度)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 153))  -- 255 * 0.6 = 153
    nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())
    fragShopComposeBtnRects = {}
    heroFragShopComposeBtnRects = {}

    -- 收集武灵残片
    local heroFragList = {}
    for cardIdx, cnt in pairs(heroFragments) do
        if cnt > 0 and HERO_CARDS[cardIdx] then
            table.insert(heroFragList, { cardIdx = cardIdx, count = cnt, quality = HERO_CARDS[cardIdx].quality })
        end
    end
    table.sort(heroFragList, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.count > b.count
    end)

    -- 收集武技残片
    local fragList = {}
    for skillIdx, cnt in pairs(skillFragments) do
        if cnt > 0 then
            local tech = SKILL_TECHNIQUES[skillIdx]
            if tech then
                table.insert(fragList, { skillIdx = skillIdx, count = cnt, tier = tech.tier })
            end
        end
    end
    table.sort(fragList, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        if a.count ~= b.count then return a.count > b.count end
        return a.skillIdx < b.skillIdx
    end)

    -- 统计可合成数量
    local heroCanCompose = 0
    for _, f in ipairs(heroFragList) do
        local need = HERO_FRAG_EXCHANGE[f.quality] or 20
        if f.count >= need then heroCanCompose = heroCanCompose + 1 end
    end
    local skillCanCompose = 0
    for _, f in ipairs(fragList) do
        if f.count >= SKILL_FRAG_EXCHANGE then skillCanCompose = skillCanCompose + 1 end
    end
    local totalCanCompose = heroCanCompose + skillCanCompose

    -- ======== 标题区域 ========
    local titleY = 55
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, titleY, "残片仓库")

    -- 副标题统计
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(200, 190, 180, 160))
    nvgText(vg, cx, titleY + 20, "武灵 " .. #heroFragList .. " 种  ·  武技 " .. #fragList .. " 种", nil)
    if totalCanCompose > 0 then
        -- "✦ N 个可合成" 左侧 + "一键合成"按钮右侧，同一行
        local rowY = titleY + 38
        local composeLabel = "✦ " .. totalCanCompose .. " 个可合成"
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
        nvgText(vg, cx - 4, rowY, composeLabel, nil)

        -- 一键合成按钮
        local okBtnW, okBtnH = 72, 22
        local okBtnX = cx + 4
        local okBtnY = rowY - okBtnH / 2
        local pulse = 0.75 + 0.25 * math.sin(t * 3.5)
        local bgP = nvgLinearGradient(vg, okBtnX, okBtnY, okBtnX, okBtnY + okBtnH,
            nvgRGBA(220, 170, 40, math.floor(240 * pulse)),
            nvgRGBA(180, 120, 20, math.floor(210 * pulse)))
        nvgBeginPath(vg); nvgRoundedRect(vg, okBtnX, okBtnY, okBtnW, okBtnH, 5)
        nvgFillPaint(vg, bgP); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 240, 140, math.floor(200 * pulse)))
        nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(okBtnX + okBtnW / 2, okBtnY + okBtnH / 2, "一键合成")
        fragShopOneKeyBtnRect = { x = okBtnX, y = okBtnY, w = okBtnW, h = okBtnH }
    else
        fragShopOneKeyBtnRect = nil
    end

    -- ======== 空状态 ========
    if #heroFragList == 0 and #fragList == 0 then
        nvgFontSize(vg, 22)
        DrawWhiteInkText(cx, H * 0.44, "暂无残片")
        nvgFontSize(vg, 15)
        nvgFillColor(vg, nvgRGBA(180, 170, 160, 140))
        nvgText(vg, cx, H * 0.44 + 30, "召唤武灵或感悟武技获取残片", nil)
        return
    end

    -- ======== 滚动区域 ========
    local clipTop = titleY + 50
    local clipBottom = H - 10
    local clipH = clipBottom - clipTop

    -- 网格布局 — 3列更宽敞
    local cols = 3
    local cellW = 110
    local cellH = 140
    local gapX = 10
    local gapY = 10

    -- 武技残片 tier 颜色 (7阶, 与 SKILL_TIERS 对齐)
    local TIER_COLORS = {
        { 180, 175, 165 },  -- 凡品 灰
        { 100, 210, 120 },  -- 良品 绿
        { 80, 160, 255 },   -- 优品 蓝
        { 180, 100, 255 },  -- 将品 紫
        { 255, 140, 0 },    -- 侯品 橙
        { 255, 180, 50 },   -- 王品 金
        { 255, 80, 80 },    -- 帝品 红
    }
    local tierNames = { "凡", "良", "优", "将", "侯", "王", "帝" }

    -- 计算各区域高度
    local sectionTitleH = 32
    local heroSectionH = 0
    local heroRows = math.ceil(#heroFragList / cols)
    if #heroFragList > 0 then
        heroSectionH = sectionTitleH + heroRows * (cellH + gapY)
    end
    local skillSectionH = 0
    local skillRows = math.ceil(#fragList / cols)
    if #fragList > 0 then
        skillSectionH = sectionTitleH + skillRows * (cellH + gapY)
    end
    local sectionGap = (#heroFragList > 0 and #fragList > 0) and 12 or 0
    local contentH = heroSectionH + sectionGap + skillSectionH
    local gridW = cols * cellW + (cols - 1) * gapX
    local gridStartX = cx - gridW / 2

    -- 限制滚动范围
    local maxScroll = 0
    local minScroll = math.min(0, clipH - contentH - 10)
    fragShopScroll.offset = math.max(minScroll, math.min(maxScroll, fragShopScroll.offset))

    nvgSave(vg)
    nvgScissor(vg, 0, clipTop, W, clipH)

    local cursorY = clipTop + fragShopScroll.offset

    -- ======== 区域分隔标题绘制辅助 ========
    local function drawSectionHeader(label, labelColor, count, yPos)
        local lineY = yPos + sectionTitleH / 2
        -- 左侧装饰线
        local labelW = 80
        local lineLeft = gridStartX
        local lineRight = gridStartX + gridW
        nvgBeginPath(vg)
        nvgMoveTo(vg, lineLeft, lineY)
        nvgLineTo(vg, cx - labelW / 2 - 8, lineY)
        nvgStrokeColor(vg, nvgRGBA(labelColor[1], labelColor[2], labelColor[3], 60))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        -- 右侧装饰线
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + labelW / 2 + 8, lineY)
        nvgLineTo(vg, lineRight, lineY)
        nvgStrokeColor(vg, nvgRGBA(labelColor[1], labelColor[2], labelColor[3], 60))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        -- 标签
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(labelColor[1], labelColor[2], labelColor[3], 200))
        nvgText(vg, cx, lineY, label .. " (" .. count .. ")", nil)
    end

    -- ======== 通用合成按钮绘制 ========
    local function drawComposeBtn(bx, by, bw, bh, pulse)
        -- 按钮底色渐变
        local bgPaint = nvgLinearGradient(vg, bx, by, bx, by + bh,
            nvgRGBA(200, 150, 40, math.floor(230 * pulse)),
            nvgRGBA(160, 100, 20, math.floor(200 * pulse)))
        nvgBeginPath(vg); nvgRoundedRect(vg, bx, by, bw, bh, 5)
        nvgFillPaint(vg, bgPaint); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 230, 120, math.floor(180 * pulse)))
        nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(bx + bw / 2, by + bh / 2, "合 成")
    end

    -- ========== 武灵残片区域 ==========
    if #heroFragList > 0 then
        drawSectionHeader("武灵残片", { 255, 200, 80 }, #heroFragList, cursorY)
        cursorY = cursorY + sectionTitleH

        for i, f in ipairs(heroFragList) do
            local col = ((i - 1) % cols)
            local row = math.floor((i - 1) / cols)
            local x = gridStartX + col * (cellW + gapX)
            local y = cursorY + row * (cellH + gapY)

            if y + cellH >= clipTop and y <= clipBottom then
                local card = HERO_CARDS[f.cardIdx]
                local qc = QUALITY_COLORS[f.quality] or { 180, 180, 170 }
                local need = HERO_FRAG_EXCHANGE[f.quality] or 20
                local canExchange = f.count >= need

                -- 卡片背景 — 渐变底色
                nvgBeginPath(vg); nvgRoundedRect(vg, x, y, cellW, cellH, 10)
                if canExchange then
                    local glowPulse = 0.6 + 0.4 * math.sin(t * 3 + f.cardIdx)
                    local bgP = nvgLinearGradient(vg, x, y, x, y + cellH,
                        nvgRGBA(50, 45, 15, math.floor(230 * glowPulse)),
                        nvgRGBA(30, 25, 10, math.floor(210 * glowPulse)))
                    nvgFillPaint(vg, bgP); nvgFill(vg)
                    -- 金色发光边框
                    nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(200 * glowPulse)))
                    nvgStrokeWidth(vg, 2); nvgStroke(vg)
                else
                    local bgP = nvgLinearGradient(vg, x, y, x, y + cellH,
                        nvgRGBA(30, 28, 45, 230), nvgRGBA(18, 16, 30, 240))
                    nvgFillPaint(vg, bgP); nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 100))
                    nvgStrokeWidth(vg, 1); nvgStroke(vg)
                end

                -- 品质色顶部装饰条
                nvgBeginPath(vg); nvgRoundedRect(vg, x + 2, y + 2, cellW - 4, 3, 1.5)
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 160)); nvgFill(vg)

                -- 武灵头像（卡牌缩略图）
                local thumbW = 60
                local thumbH = thumbW / CARD_RATIO
                local thumbX = x + (cellW - thumbW) / 2
                local thumbY = y + 8
                DrawInventoryCard(thumbX, thumbY, thumbW, thumbH, card, 0, false)

                -- 进度条
                local barW = cellW - 16
                local barH = 6
                local barX = x + 8
                local barY = y + 95
                local progress = math.min(f.count / need, 1.0)

                nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 3)
                nvgFillColor(vg, nvgRGBA(40, 30, 50, 200)); nvgFill(vg)
                if progress > 0 then
                    local fillCol = canExchange
                        and nvgRGBA(255, 210, 60, 240)
                        or nvgRGBA(qc[1], qc[2], qc[3], 180)
                    nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3)
                    nvgFillColor(vg, fillCol); nvgFill(vg)
                end

                -- 残片数文字
                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if canExchange then
                    nvgFillColor(vg, nvgRGBA(255, 220, 80, 240))
                else
                    nvgFillColor(vg, nvgRGBA(200, 195, 185, 200))
                end
                nvgText(vg, x + cellW / 2, barY + barH + 10, f.count .. " / " .. need, nil)

                -- 合成按钮
                if canExchange then
                    local btnW = 64
                    local btnH = 22
                    local btnX = x + (cellW - btnW) / 2
                    local btnY = y + cellH - btnH - 4
                    local pulse = 0.7 + 0.3 * math.sin(t * 4 + f.cardIdx * 0.7)
                    drawComposeBtn(btnX, btnY, btnW, btnH, pulse)
                    heroFragShopComposeBtnRects[f.cardIdx] = { x = btnX, y = btnY, w = btnW, h = btnH }
                end
            end
        end
        cursorY = cursorY + heroRows * (cellH + gapY)
    end

    -- 区域间距
    if #heroFragList > 0 and #fragList > 0 then
        cursorY = cursorY + sectionGap
    end

    -- ========== 武技残片区域 ==========
    if #fragList > 0 then
        drawSectionHeader("武技残片", { 180, 140, 255 }, #fragList, cursorY)
        cursorY = cursorY + sectionTitleH
    end

    for i, f in ipairs(fragList) do
        local col = ((i - 1) % cols)
        local row = math.floor((i - 1) / cols)
        local x = gridStartX + col * (cellW + gapX)
        local y = cursorY + row * (cellH + gapY)

        if y + cellH >= clipTop and y <= clipBottom then
            local tech = SKILL_TECHNIQUES[f.skillIdx]
            local tc = TIER_COLORS[tech.tier] or { 180, 180, 170 }
            local canExchange = f.count >= SKILL_FRAG_EXCHANGE

            -- 卡片背景 — 渐变
            nvgBeginPath(vg); nvgRoundedRect(vg, x, y, cellW, cellH, 10)
            if canExchange then
                local glowPulse = 0.6 + 0.4 * math.sin(t * 3 + f.skillIdx)
                local bgP = nvgLinearGradient(vg, x, y, x, y + cellH,
                    nvgRGBA(50, 45, 15, math.floor(230 * glowPulse)),
                    nvgRGBA(30, 25, 10, math.floor(210 * glowPulse)))
                nvgFillPaint(vg, bgP); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(200 * glowPulse)))
                nvgStrokeWidth(vg, 2); nvgStroke(vg)
            else
                local bgP = nvgLinearGradient(vg, x, y, x, y + cellH,
                    nvgRGBA(25, 20, 40, 230), nvgRGBA(15, 12, 28, 240))
                nvgFillPaint(vg, bgP); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 100))
                nvgStrokeWidth(vg, 1); nvgStroke(vg)
            end

            -- 品质色顶部装饰条
            nvgBeginPath(vg); nvgRoundedRect(vg, x + 2, y + 2, cellW - 4, 3, 1.5)
            nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 160)); nvgFill(vg)

            -- 武技图标 — 更大
            local iconSize = 54
            local iconX = x + (cellW - iconSize) / 2
            local iconY = y + 8
            drawSkillIcon(tech.iconIdx, iconX, iconY, iconSize, 6)

            -- 阶级标签（右上角小徽章）
            local badgeX = x + cellW - 24
            local badgeY = y + 6
            nvgBeginPath(vg); nvgRoundedRect(vg, badgeX, badgeY, 20, 16, 4)
            nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 140)); nvgFill(vg)
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, badgeX + 10, badgeY + 8, tierNames[tech.tier] or "?", nil)

            -- 武技名
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 240))
            nvgText(vg, x + cellW / 2, y + 70, tech.name, nil)

            -- 进度条
            local barW = cellW - 16
            local barH = 6
            local barX = x + 8
            local barY = y + 82
            local progress = math.min(f.count / SKILL_FRAG_EXCHANGE, 1.0)

            nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 3)
            nvgFillColor(vg, nvgRGBA(40, 30, 60, 200)); nvgFill(vg)

            if progress > 0 then
                local fillColor = canExchange
                    and nvgRGBA(255, 210, 60, 240)
                    or nvgRGBA(tc[1], tc[2], tc[3], 180)
                nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3)
                nvgFillColor(vg, fillColor); nvgFill(vg)
            end

            -- 残片数 x/49
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if canExchange then
                nvgFillColor(vg, nvgRGBA(255, 220, 80, 240))
            else
                nvgFillColor(vg, nvgRGBA(200, 195, 185, 200))
            end
            nvgText(vg, x + cellW / 2, barY + barH + 10, f.count .. " / " .. SKILL_FRAG_EXCHANGE, nil)

            -- 合成按钮
            if canExchange then
                local btnW = 64
                local btnH = 22
                local btnX = x + (cellW - btnW) / 2
                local btnY = y + cellH - btnH - 4
                local pulse = 0.7 + 0.3 * math.sin(t * 4 + f.skillIdx * 0.7)
                drawComposeBtn(btnX, btnY, btnW, btnH, pulse)
                fragShopComposeBtnRects[f.skillIdx] = { x = btnX, y = btnY, w = btnW, h = btnH }
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条指示器
    if contentH > clipH then
        local scrollRange = contentH - clipH
        local scrollRatio = (scrollRange > 0) and (-fragShopScroll.offset / scrollRange) or 0
        local barVisH = math.max(24, clipH * clipH / contentH)
        local barPosY = clipTop + scrollRatio * (clipH - barVisH)
        nvgBeginPath(vg); nvgRoundedRect(vg, W - 5, barPosY, 3, barVisH, 1.5)
        nvgFillColor(vg, nvgRGBA(180, 160, 220, 70)); nvgFill(vg)
    end
end
