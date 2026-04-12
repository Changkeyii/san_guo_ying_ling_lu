-- ============================================================================
-- ui/gacha_limited.lua - 三国武灵录 (限定池系统)
-- ============================================================================
function DrawLimitedGachaIdle(t)
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local circleY = H * 0.42
    local circleR = 95

    -- 召唤阵外圈: 红色旋转弧线 (区别于普通池的金色)
    for i = 1, 12 do
        local angle = (i / 12) * math.pi * 2 + t * 0.8
        local arcLen = math.pi / 8
        local r = circleR + 8 + 3 * math.sin(t * 2 + i)
        nvgBeginPath(vg)
        nvgArc(vg, cx, circleY, r, angle, angle + arcLen, NVG_CW)
        local pulse = 0.4 + 0.6 * math.sin(t * 1.5 + i * 0.5)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 120, math.floor(100 * pulse)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    end

    -- 内圈: 暗红光弧
    for i = 1, 8 do
        local angle = -(i / 8) * math.pi * 2 + t * 1.2
        local arcLen = math.pi / 6
        nvgBeginPath(vg)
        nvgArc(vg, cx, circleY, circleR - 5, angle, angle + arcLen, NVG_CW)
        local pulse = 0.3 + 0.7 * math.sin(t * 2.5 + i * 0.8)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 140, math.floor(80 * pulse)))
        nvgStrokeWidth(vg, 1.0); nvgStroke(vg)
    end

    -- 中心光晕 (红粉色)
    local glowPulse = 0.6 + 0.4 * math.sin(t * 2)
    local glow = nvgRadialGradient(vg, cx, circleY, 5, circleR * 0.8,
        nvgRGBA(255, 80, 120, math.floor(40 * glowPulse)),
        nvgRGBA(180, 60, 100, 0))
    nvgBeginPath(vg); nvgCircle(vg, cx, circleY, circleR * 0.8)
    nvgFillPaint(vg, glow); nvgFill(vg)

    -- 中心文字
    nvgFontFaceId(vg, GetMainFont())
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local textPulse = 0.6 + 0.4 * math.sin(t * 1.8)
    nvgFillColor(vg, nvgRGBA(255, 120, 150, math.floor(200 * textPulse)))
    nvgText(vg, cx, circleY - 5, "限 定 召 唤", nil)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(255, 180, 200, 160))
    nvgText(vg, cx, circleY + 28, "仅出碎片 · 限定SSR唯一来源", nil)

    -- 限定武灵展示 (小图标)
    local limitedPool = {}
    for idx, card in ipairs(HERO_CARDS) do
        if card.quality == QUALITY.LIMITED then
            table.insert(limitedPool, { idx = idx, card = card })
        end
    end
    if #limitedPool > 0 then
        local iconSize = 32
        local iconGap = 8
        local totalIconW = #limitedPool * iconSize + (#limitedPool - 1) * iconGap
        local iconStartX = cx - totalIconW / 2
        local iconY = circleY + 50
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        for li, lh in ipairs(limitedPool) do
            local ix = iconStartX + (li - 1) * (iconSize + iconGap)
            -- 红粉边框小卡
            nvgBeginPath(vg); nvgRoundedRect(vg, ix, iconY, iconSize, iconSize, 4)
            nvgFillColor(vg, nvgRGBA(40, 20, 30, 200)); nvgFill(vg)
            local bPulse = 0.6 + 0.4 * math.sin(t * 2 + li)
            nvgStrokeColor(vg, nvgRGBA(255, 80, 120, math.floor(180 * bPulse)))
            nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            -- 名字首字
            nvgFillColor(vg, nvgRGBA(255, 200, 210, 220))
            local firstName = string.sub(lh.card.name, 1, 3)  -- UTF-8 首字
            nvgText(vg, ix + iconSize / 2, iconY + iconSize / 2 - 7, firstName, nil)
        end
    end

    -- 抽卡按钮
    local bigPull = playerInfo.jadeUnlockedBigPull
    gachaHundredBtnRect = nil

    if bigPull then
        -- 增强模式: 3个按钮 (10连/50连/100连) 红粉色调
        local btnW = 160
        local btnH = 46
        local btnGap = 8
        local btnY1 = H * 0.62
        local btnY2 = btnY1 + btnH + btnGap
        local btnY3 = btnY2 + btnH + btnGap
        local unitCost = LIMITED_GACHA_COST

        -- 10连
        local b1x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b1x, btnY1, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(35, 18, 28, 200)); nvgFill(vg)
        local bp1 = 0.7 + 0.3 * math.sin(t * 2)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 120, math.floor(180 * bp1)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 - 7, "十 连 召 唤")
        nvgFontSize(vg, 14)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 + 12, math.floor(unitCost * 10 * 0.9) .. " 虎符 (9折)")
        gachaSingleBtnRect = { x = b1x, y = btnY1, w = btnW, h = btnH }

        -- 50连
        local b2x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        local g50 = nvgLinearGradient(vg, b2x, btnY2, b2x + btnW, btnY2 + btnH,
            nvgRGBA(55, 20, 35, 220), nvgRGBA(60, 18, 50, 220))
        nvgFillPaint(vg, g50); nvgFill(vg)
        local bp2 = 0.6 + 0.4 * math.sin(t * 2.5)
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 140, math.floor(200 * bp2)))
        nvgStrokeWidth(vg, 1.8); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 - 7, "五十连召唤")
        nvgFontSize(vg, 14)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 + 12, math.floor(unitCost * 50 * 0.9) .. " 虎符 (9折)")
        gachaTenBtnRect = { x = b2x, y = btnY2, w = btnW, h = btnH }

        -- 100连 (最突出)
        local b3x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b3x, btnY3, btnW, btnH, 6)
        local g100 = nvgLinearGradient(vg, b3x, btnY3, b3x + btnW, btnY3 + btnH,
            nvgRGBA(70, 15, 30, 230), nvgRGBA(80, 10, 50, 230))
        nvgFillPaint(vg, g100); nvgFill(vg)
        local bp3 = 0.5 + 0.5 * math.sin(t * 3)
        nvgBeginPath(vg); nvgRoundedRect(vg, b3x, btnY3, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(255, 140, 100, math.floor(220 * bp3)))
        nvgStrokeWidth(vg, 2.0); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY3 + btnH / 2 - 7, "百 连 召 唤")
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

        -- 单抽按钮 (红粉色调)
        local b1x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b1x, btnY1, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(35, 18, 28, 200)); nvgFill(vg)
        local borderPulse1 = 0.7 + 0.3 * math.sin(t * 2)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 120, math.floor(180 * borderPulse1)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 - 10, "单 抽")
        nvgFontSize(vg, 16)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 + 20, LIMITED_GACHA_COST .. " 虎符")
        gachaSingleBtnRect = { x = b1x, y = btnY1, w = btnW, h = btnH }

        -- 十连按钮 (更突出, 红紫渐变)
        local b2x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        local tenGrad = nvgLinearGradient(vg, b2x, btnY2, b2x + btnW, btnY2 + btnH,
            nvgRGBA(55, 20, 35, 220), nvgRGBA(60, 18, 50, 220))
        nvgFillPaint(vg, tenGrad); nvgFill(vg)
        local borderPulse2 = 0.6 + 0.4 * math.sin(t * 2.5)
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 140, math.floor(200 * borderPulse2)))
        nvgStrokeWidth(vg, 1.8); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 - 10, "十 连 召 唤")
        nvgFontSize(vg, 16)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 + 20, LIMITED_GACHA_TEN_COST .. " 虎符 (9折)")
        gachaTenBtnRect = { x = b2x, y = btnY2, w = btnW, h = btnH }
    end

    -- 计算最后一个按钮底部Y (兼容增强模式3按钮)
    local lastBtnBottom = gachaHundredBtnRect and (gachaHundredBtnRect.y + gachaHundredBtnRect.h) or (gachaTenBtnRect.y + gachaTenBtnRect.h)

    -- 保底进度
    local pityRemain = LIMITED_PITY_FRAG_COUNT - gachaState.limitedPityCounter
    local pityText = "距碎片保底: " .. pityRemain .. " 抽 | " .. LIMITED_FRAG_GUARANTEE_MIN .. "~" .. LIMITED_FRAG_GUARANTEE_MAX .. "碎片"
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, lastBtnBottom + 20, pityText)

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(255, 150, 170, 120))
    nvgText(vg, cx, lastBtnBottom + 46, "无整卡保底 · 仅产出碎片", nil)

    -- 残片仓库按钮（左下角）
    local bottomBtnY = lastBtnBottom + 8
    local shopBtnW = 90
    local shopBtnH = 30
    local shopBtnX = 12
    nvgBeginPath(vg); nvgRoundedRect(vg, shopBtnX, bottomBtnY, shopBtnW, shopBtnH, 6)
    nvgFillColor(vg, nvgRGBA(35, 30, 50, 210)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 120, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(shopBtnX + shopBtnW / 2, bottomBtnY + shopBtnH / 2, "残片仓库")
    gachaFragShopBtnRect = { x = shopBtnX, y = bottomBtnY, w = shopBtnW, h = shopBtnH }

    -- "?" 概率规则按钮 (右下角)
    local qBtnSize = 30
    local qBtnX = W - qBtnSize - 12
    local qBtnY = bottomBtnY
    nvgBeginPath(vg); nvgCircle(vg, qBtnX + qBtnSize / 2, qBtnY + qBtnSize / 2, qBtnSize / 2)
    nvgFillColor(vg, nvgRGBA(40, 20, 30, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 100, 120, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(qBtnX + qBtnSize / 2, qBtnY + qBtnSize / 2, "?")
    gachaRulesBtnRect = { x = qBtnX, y = qBtnY, w = qBtnSize, h = qBtnSize }
end


--- 限定池抽取结果展示
function DrawLimitedGachaResults()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local results = gachaState.limitedResults
    if not results or #results == 0 then return end
    local count = #results
    local t = gachaState.animTimer or 0

    -- 检查是否有限定SSR
    local hasLimitedSSR = false
    for _, r in ipairs(results) do
        local c = HERO_CARDS[r.cardIdx]
        if c and c.quality == QUALITY.LIMITED then hasLimitedSSR = true; break end
    end

    -- === 全屏遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- === 限定SSR出货特效: 全屏闪光 + 粒子 ===
    if hasLimitedSSR then
        -- 全屏红金色脉冲光
        local flashA = math.max(0, 80 * math.sin(t * 4))
        nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
        local flashGrad = nvgRadialGradient(vg, cx, H * 0.4, 10, W * 0.9,
            nvgRGBA(255, 100, 60, math.floor(flashA)),
            nvgRGBA(255, 40, 80, 0))
        nvgFillPaint(vg, flashGrad); nvgFill(vg)

        -- 旋转光线
        for i = 1, 12 do
            local angle = (i / 12) * math.pi * 2 + t * 0.6
            local len = 260 + 40 * math.sin(t * 3 + i)
            local ex = cx + math.cos(angle) * len
            local ey = H * 0.4 + math.sin(angle) * len
            local rayA = 0.3 + 0.7 * math.sin(t * 2.5 + i * 0.5)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, H * 0.4)
            nvgLineTo(vg, ex, ey)
            nvgStrokeColor(vg, nvgRGBA(255, 180, 80, math.floor(40 * rayA)))
            nvgStrokeWidth(vg, 2); nvgStroke(vg)
        end

        -- 上升粒子
        for i = 1, 20 do
            local px = cx + math.sin(t * 1.3 + i * 1.7) * W * 0.4
            local py = H - ((t * 60 + i * 47) % (H + 40))
            local pSize = 2 + math.sin(t * 3 + i) * 1.5
            local pA = 0.4 + 0.6 * math.sin(t * 2 + i * 0.8)
            nvgBeginPath(vg); nvgCircle(vg, px, py, pSize)
            if i % 3 == 0 then
                nvgFillColor(vg, nvgRGBA(255, 80, 120, math.floor(180 * pA)))
            else
                nvgFillColor(vg, nvgRGBA(255, 200, 80, math.floor(160 * pA)))
            end
            nvgFill(vg)
        end
    end

    nvgFontFaceId(vg, GetMainFont())

    -- === 标题 ===
    nvgFontSize(vg, 33)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if hasLimitedSSR then
        -- 限定SSR: 金色闪烁标题
        local titlePulse = 0.7 + 0.3 * math.sin(t * 3)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, math.floor(255 * titlePulse)))
        nvgText(vg, cx, 65, "限定召唤结果", nil)
        -- 标题光晕
        nvgFillColor(vg, nvgRGBA(255, 120, 60, math.floor(60 * titlePulse)))
        nvgText(vg, cx, 65, "限定召唤结果", nil)
    else
        DrawWhiteInkText(cx, 65, "限定召唤结果")
    end

    -- === 卡牌展示 (与武灵召唤一致) ===
    if count == 1 then
        -- 单抽: 大卡居中
        local cardW = 120
        local cardH = cardW / CARD_RATIO
        local cardX = cx - cardW / 2
        local cardY = H * 0.25
        local r = results[1]
        local card = HERO_CARDS[r.cardIdx]

        -- 限定SSR出货: 额外大光晕
        if card and card.quality == QUALITY.LIMITED then
            local bigGlow = nvgRadialGradient(vg, cx, cardY + cardH / 2, 10, cardW * 1.8,
                nvgRGBA(255, 80, 120, math.floor(100 * (0.5 + 0.5 * math.sin(t * 2.5)))),
                nvgRGBA(255, 40, 80, 0))
            nvgBeginPath(vg); nvgCircle(vg, cx, cardY + cardH / 2, cardW * 1.8)
            nvgFillPaint(vg, bigGlow); nvgFill(vg)
        end

        DrawInventoryCard(cardX, cardY, cardW, cardH, card, 0, false)

        local tagY = cardY + cardH + 12
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 碎片信息
        local isLimited = card and card.quality == QUALITY.LIMITED
        local qc = QUALITY_COLORS[card.quality] or { 200, 200, 200 }
        if isLimited then
            nvgFillColor(vg, nvgRGBA(255, 120, 150, 240))
        else
            nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 240))
        end
        nvgText(vg, cx, tagY, card.name .. " 碎片 x" .. r.fragCount, nil)

        -- 进度
        local need = HERO_FRAG_EXCHANGE[card.quality] or 20
        local total = r.totalFrags or 0
        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
        nvgText(vg, cx, tagY + 28, "累计 " .. total .. "/" .. need, nil)

        -- 保底标记
        if r.isPity then
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(255, 80, 120, 220))
            nvgText(vg, cx, tagY + 56, "保底出货!", nil)
        end
    else
        -- 按品质降序排序（高品质排前面，限定SSR最优先）
        table.sort(results, function(a, b)
            local qa = HERO_CARDS[a.cardIdx] and HERO_CARDS[a.cardIdx].quality or 0
            local qb = HERO_CARDS[b.cardIdx] and HERO_CARDS[b.cardIdx].quality or 0
            return qa > qb
        end)
        -- 十连: 5列×2行 卡牌网格
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

            -- 限定SSR: 卡牌额外光晕
            if card and card.quality == QUALITY.LIMITED then
                local gPulse = 0.5 + 0.5 * math.sin(t * 3 + i)
                local glow = nvgRadialGradient(vg, x + cardW / 2, y + cardH / 2, 5, cardW * 0.9,
                    nvgRGBA(255, 80, 120, math.floor(80 * gPulse)),
                    nvgRGBA(255, 40, 80, 0))
                nvgBeginPath(vg); nvgCircle(vg, x + cardW / 2, y + cardH / 2, cardW * 0.9)
                nvgFillPaint(vg, glow); nvgFill(vg)
            end

            DrawInventoryCard(x, y, cardW, cardH, card, 0, false)

            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

            -- 碎片数量
            local isLimited = card and card.quality == QUALITY.LIMITED
            if isLimited then
                nvgFillColor(vg, nvgRGBA(255, 120, 150, 240))
                nvgText(vg, x + cardW / 2, y + cardH + 2, "碎片x" .. r.fragCount, nil)
            else
                local qc = QUALITY_COLORS[card.quality] or { 200, 200, 200 }
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 220))
                nvgText(vg, x + cardW / 2, y + cardH + 2, "碎片x" .. r.fragCount, nil)
            end

            -- 累计碎片小字
            local need = HERO_FRAG_EXCHANGE[card.quality] or 20
            local total = r.totalFrags or 0
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
            nvgText(vg, x + cardW / 2, y + cardH + 16, total .. "/" .. need, nil)

            -- 保底标记
            if r.isPity then
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(255, 80, 120, 220))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgText(vg, x + cardW - 2, y + 2, "保底", nil)
            end
        end
    end

    -- === 确认按钮 ===
    local confirmW = 140
    local confirmH = 44
    local confirmX = cx - confirmW / 2
    local confirmY = H * 0.88
    nvgBeginPath(vg); nvgRoundedRect(vg, confirmX, confirmY, confirmW, confirmH, 6)
    nvgFillColor(vg, nvgRGBA(255, 60, 100, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 160, 180, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, confirmY + confirmH / 2, "确 认")
    gachaConfirmBtnRect = { x = confirmX, y = confirmY, w = confirmW, h = confirmH }
end


--- 限定池规则弹窗
function DrawLimitedGachaRulesPopup()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2

    -- 半透明遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(5, 5, 12, 110)); nvgFill(vg)

    -- 弹窗面板
    local panelW = W * 0.82
    local panelH = 680
    local panelX = cx - panelW / 2
    local panelY = H / 2 - panelH / 2 - 20

    local panelGrad = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH,
        nvgRGBA(50, 28, 38, 240), nvgRGBA(35, 20, 30, 245))
    nvgBeginPath(vg); nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillPaint(vg, panelGrad); nvgFill(vg)

    nvgBeginPath(vg); nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 120, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 标题
    local titleY = panelY + 28
    nvgFontSize(vg, 35)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 120, 150, 240))
    nvgText(vg, cx, titleY, "限定召唤规则", nil)

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, titleY + 18)
    nvgLineTo(vg, panelX + panelW - 20, titleY + 18)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 120, 60)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    local leftX = panelX + 20
    local rightX = panelX + panelW - 20
    local lineH = 30
    local startY = titleY + 36

    -- 核心规则
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "核心规则")
    startY = startY + lineH * 0.8

    local function DrawRuleLine(text)
        nvgFontSize(vg, 14.5)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(leftX + 10, startY, text)
        startY = startY + lineH * 0.7
    end

    DrawRuleLine("· 限定池仅产出碎片, 无整卡产出")
    DrawRuleLine("· 限定SSR武灵碎片唯一来源")
    DrawRuleLine("· 每 " .. LIMITED_PITY_FRAG_COUNT .. " 抽保底: 必出限定SSR碎片x" .. LIMITED_FRAG_GUARANTEE_MIN .. "~" .. LIMITED_FRAG_GUARANTEE_MAX)
    DrawRuleLine("· 单抽 " .. LIMITED_GACHA_COST .. " 虎符 / 十连 " .. LIMITED_GACHA_TEN_COST .. " 虎符(9折)")

    -- 分隔线
    startY = startY + 6
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 120, 40)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 概率表
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "碎片品质概率")
    startY = startY + lineH * 0.8

    local probInfo = {
        { tag = "R",   name = "地品碎片", pct = LIMITED_DRAW_WEIGHTS[2], color = QUALITY_COLORS[2] },
        { tag = "SR",  name = "天品碎片", pct = LIMITED_DRAW_WEIGHTS[3], color = QUALITY_COLORS[3] },
        { tag = "SSR", name = "神品碎片", pct = LIMITED_DRAW_WEIGHTS[4], color = QUALITY_COLORS[4] },
        { tag = "限定", name = "限定碎片", pct = LIMITED_DRAW_WEIGHTS[5], color = QUALITY_COLORS[5] },
    }
    local totalProb = 0
    for _, p in ipairs(probInfo) do totalProb = totalProb + p.pct end

    for _, pi in ipairs(probInfo) do
        local pic = pi.color
        nvgFontSize(vg, 14.5)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(pic[1], pic[2], pic[3], 200))
        nvgText(vg, leftX + 4, startY, pi.tag .. " " .. pi.name, nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        local pctText = string.format("%.0f%%", pi.pct / totalProb * 100)
        DrawWhiteInkText(rightX, startY, pctText)
        startY = startY + lineH * 0.7
    end

    -- 分隔线
    startY = startY + 6
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 120, 40)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 保底进度
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "保底进度")
    startY = startY + lineH * 0.8

    local remaining = LIMITED_PITY_FRAG_COUNT - gachaState.limitedPityCounter
    nvgFontSize(vg, 14.5)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX + 4, startY, "距离保底还需")
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 120, 150, 240))
    nvgText(vg, rightX, startY, remaining .. " 抽", nil)
    startY = startY + lineH * 0.7

    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX + 4, startY, "已累计抽取")
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(rightX, startY, gachaState.limitedPityCounter .. " 抽")
    startY = startY + lineH * 0.7

    -- 残片合成所需
    startY = startY + 8
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "限定武灵合成所需")
    startY = startY + lineH * 0.8

    nvgFontSize(vg, 14.5)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local lc = QUALITY_COLORS[5]
    nvgFillColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 200))
    nvgText(vg, leftX + 4, startY, "限定SSR 品质", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(rightX, startY, HERO_FRAG_EXCHANGE[5] .. " 残片")

    -- 关闭按钮
    local closeBtnW = 100
    local closeBtnH = 36
    local closeBtnX = cx - closeBtnW / 2
    local closeBtnY = panelY + panelH - closeBtnH - 14
    nvgBeginPath(vg); nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6)
    nvgFillColor(vg, nvgRGBA(255, 60, 100, 180)); nvgFill(vg)
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, closeBtnY + closeBtnH / 2, "关 闭")
    gachaRulesCloseBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH }
end


--- 抽卡召唤动画
