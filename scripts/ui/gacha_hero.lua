-- ============================================================================
-- ui/gacha_hero.lua - 三国武灵录 (主抽卡界面 + 武灵召唤)
-- ============================================================================
-- ============================================================================
-- ui/gacha_screen.lua - 三国武灵录
-- ============================================================================


-- ============================================================================
-- 召唤武灵 (抽卡界面) - 设计坐标
-- ============================================================================
function DrawGachaScreen()
    if gameState.phase ~= "GACHA" then return end

    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local t = gachaState.animTimer

    -- 1. 背景 (复用首页背景图 + 深色调)
    DrawBgImage(IMG.menuBg, W, H, 1143, 2048)

    -- 深色遮罩 (比首页更暗, 突出抽卡区域)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(5, 8, 18, 160)); nvgFill(vg)

    -- 底部渐变
    local botGrad = nvgLinearGradient(vg, 0, H * 0.65, 0, H,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(5, 8, 15, 180))
    nvgBeginPath(vg); nvgRect(vg, 0, H * 0.65, W, H * 0.35)
    nvgFillPaint(vg, botGrad); nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- ===========================
    -- 2. 顶部返回按钮 + 标题 + 虎符显示
    -- ===========================
    local topBarY = 10
    local backW, backH = 100, 40
    local backX = 10

    -- 返回按钮
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, topBarY, backW, backH, 6)
    nvgFillColor(vg, nvgRGBA(20, 25, 40, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(backX + backW / 2, topBarY + backH / 2, "< 返回")
    gachaBackBtnRect = { x = backX, y = topBarY, w = backW, h = backH }

    -- Tab 切换按钮 (武灵 / 武技 / 兵符 / 限定) — grid 排列，避免与虎符重叠
    local hasSealUnlock = HasMaxConstellationHero()
    local tabW = 65
    local tabH = 32
    local tabGap = 5
    local tabLabels, tabCount
    if hasSealUnlock then
        tabLabels = { "武灵", "武技", "兵符", "限定" }
        tabCount = 4
    else
        tabLabels = { "武灵", "武技", "限定" }
        tabCount = 3
    end
    local tabTotalW = tabW * tabCount + tabGap * (tabCount - 1)
    local tabStartX = math.floor((W - tabTotalW) / 2)
    local tabY = topBarY + backH + 6
    gachaTabRects = {}
    for ti = 1, tabCount do
        local tx = tabStartX + (ti - 1) * (tabW + tabGap)
        nvgBeginPath(vg); nvgRoundedRect(vg, tx, tabY, tabW, tabH, 5)
        if gachaState.currentTab == ti then
            local tabGrad = nvgLinearGradient(vg, tx, tabY, tx, tabY + tabH,
                nvgRGBA(180, 150, 70, 220), nvgRGBA(140, 100, 40, 220))
            nvgFillPaint(vg, tabGrad); nvgFill(vg)
        else
            nvgFillColor(vg, nvgRGBA(25, 30, 50, 180)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        end
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if gachaState.currentTab == ti then
            nvgFillColor(vg, nvgRGBA(40, 20, 5, 250))
            nvgText(vg, tx + tabW / 2, tabY + tabH / 2, tabLabels[ti], nil)
        else
            DrawWhiteInkText(tx + tabW / 2, tabY + tabH / 2, tabLabels[ti])
        end
        gachaTabRects[ti] = { x = tx, y = tabY, w = tabW, h = tabH }
    end

    -- 虎符显示 (右上角) + 广告按钮
    local jadeBoxW = 185
    local jadeBoxH = 30
    local jadeBoxX = W - jadeBoxW - 10
    local jadeBoxY = topBarY + (backH - jadeBoxH) / 2

    nvgBeginPath(vg); nvgRoundedRect(vg, jadeBoxX, jadeBoxY, jadeBoxW, jadeBoxH, 4)
    nvgFillColor(vg, nvgRGBA(15, 20, 35, 140)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(120, 200, 160, 80)); nvgStrokeWidth(vg, 0.8); nvgStroke(vg)

    nvgFontSize(vg, 19)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(jadeBoxX + 8, jadeBoxY + jadeBoxH / 2, "虎符")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(jadeBoxX + jadeBoxW - 36, jadeBoxY + jadeBoxH / 2, FormatJade(playerInfo.jade))

    -- 广告 + 按钮
    local gadBtnW = 36
    local gadBtnH = 28
    local gadBtnX = jadeBoxX + jadeBoxW - gadBtnW - 3
    local gadBtnY = jadeBoxY + (jadeBoxH - gadBtnH) / 2
    local gadPulse = 0.7 + 0.3 * math.sin(t * 3)
    nvgBeginPath(vg); nvgRoundedRect(vg, gadBtnX, gadBtnY, gadBtnW, gadBtnH, 4)
    nvgFillColor(vg, nvgRGBA(60, 160, 100, math.floor(170 * gadPulse))); nvgFill(vg)
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(gadBtnX + gadBtnW / 2, gadBtnY + gadBtnH / 2, "+")
    -- 点击区域覆盖整个虎符框+下方提示文字，防止误触Tab切换
    local jadeTouchPad = 4
    adRects.jade = { x = jadeBoxX - jadeTouchPad, y = jadeBoxY - jadeTouchPad, w = jadeBoxW + jadeTouchPad * 2, h = jadeBoxH + 22 + jadeTouchPad }
    -- 广告规则提示
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(160, 220, 180, math.floor(140 * gadPulse)))
    nvgText(vg, jadeBoxX + jadeBoxW / 2, jadeBoxY + jadeBoxH + 1, "+40虎符", nil)

    -- ===========================
    -- 3. 主内容区域
    -- ===========================

    local curTabType = GetGachaTabType()
    if gachaState.showFragShop then
        -- === 残片仓库 ===
        DrawFragmentShop(t)
    elseif curTabType == "seal" then
        -- === 兵符召唤 Tab ===
        if sealGachaState.pulling then
            DrawSealGachaPullAnimation(t)
        elseif sealGachaState.showResults then
            DrawSealGachaResults()
        else
            DrawSealGachaIdle(t)
        end
    elseif gachaState.pulling then
        -- === 召唤动画 (武灵/武技/限定共用) ===
        DrawGachaPullAnimation(t)
    elseif gachaState.showResults then
        -- === 显示抽卡结果 ===
        if curTabType == "limited" then
            DrawLimitedGachaResults()
        elseif curTabType == "skill" then
            DrawSkillGachaResults()
        else
            DrawGachaResults()
        end
    else
        -- === 待机界面 ===
        if curTabType == "limited" then
            DrawLimitedGachaIdle(t)
        elseif curTabType == "skill" then
            DrawSkillGachaIdle(t)
        else
            DrawGachaIdle(t)
        end
    end

    -- 漂浮粒子 (幽冥气)
    for i = 1, 6 do
        local px = W * (0.1 + 0.8 * ((i * 137 + math.floor(t * 18)) % 100) / 100)
        local py = H * (0.1 + 0.2 * math.sin(t * 0.4 + i * 1.5))
        local pr = 1.2 + math.sin(t * 2 + i) * 0.6
        local pa = math.floor(30 + 20 * math.sin(t * 1.3 + i * 0.8))
        nvgBeginPath(vg); nvgCircle(vg, px, py, pr)
        nvgFillColor(vg, nvgRGBA(180, 200, 255, pa)); nvgFill(vg)
    end

    -- ===========================
    -- 概率规则弹窗 (最顶层)
    -- ===========================
    if gachaState.showRules then
        if curTabType == "seal" then
            DrawSealGachaRulesPopup()
        elseif curTabType == "limited" then
            DrawLimitedGachaRulesPopup()
        elseif curTabType == "skill" then
            DrawSkillGachaRulesPopup()
        else
            DrawGachaRulesPopup()
        end
    end
end


--- 概率规则弹窗
function DrawGachaRulesPopup()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2

    -- 半透明遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(5, 5, 12, 110)); nvgFill(vg)

    -- 弹窗面板
    local panelW = W * 0.82
    local panelH = 750
    local panelX = cx - panelW / 2
    local panelY = H / 2 - panelH / 2 - 20

    -- 面板背景
    local panelGrad = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH,
        nvgRGBA(42, 38, 58, 240), nvgRGBA(30, 26, 44, 245))
    nvgBeginPath(vg); nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillPaint(vg, panelGrad); nvgFill(vg)

    -- 面板边框
    nvgBeginPath(vg); nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 标题
    local titleY = panelY + 28
    nvgFontSize(vg, 35)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, titleY, "召唤规则")

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, titleY + 18)
    nvgLineTo(vg, panelX + panelW - 20, titleY + 18)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 70, 80)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    -- 概率表
    local lineH = 30
    local startY = titleY + 36
    local leftX = panelX + 28
    local rightX = panelX + panelW - 28

    -- 小标题: 出率
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "各品质出率")
    startY = startY + lineH * 0.8

    -- 概率行
    local qualities = {
        { tag = "N",   name = "凡品", pct = GameConfig.DRAW_QUALITY_WEIGHTS[1], color = QUALITY_COLORS[1] },
        { tag = "R",   name = "王品", pct = GameConfig.DRAW_QUALITY_WEIGHTS[2], color = QUALITY_COLORS[2] },
        { tag = "SR",  name = "帝品", pct = GameConfig.DRAW_QUALITY_WEIGHTS[3], color = QUALITY_COLORS[3] },
        { tag = "SSR", name = "将品", pct = GameConfig.DRAW_QUALITY_WEIGHTS[4], color = QUALITY_COLORS[4] },
    }

    for _, q in ipairs(qualities) do
        local qc = q.color
        -- 标签色块
        local tagW = #q.tag > 2 and 36 or (#q.tag > 1 and 28 or 20)
        nvgBeginPath(vg); nvgRoundedRect(vg, leftX, startY - 9, tagW, 18, 3)
        nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 200)); nvgFill(vg)
        nvgFontSize(vg, 27)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(leftX + tagW / 2, startY, q.tag)

        -- 品质名
        nvgFontSize(vg, 27)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 220))
        nvgText(vg, leftX + tagW + 8, startY, q.name, nil)

        -- 概率百分比
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(rightX, startY, q.pct .. "%")

        startY = startY + lineH * 0.85
    end

    -- 分隔线
    startY = startY + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 70, 50)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 保底规则
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "保底机制")
    startY = startY + lineH * 0.8

    nvgFontSize(vg, 24)
    DrawWhiteInkText(leftX, startY, "每" .. GameConfig.PITY_SSR_COUNT .. "抽保底:必出整卡")
    startY = startY + lineH * 0.7

    nvgFontSize(vg, 24)
    DrawWhiteInkText(leftX, startY, "十连大保底:必出SSR整卡")
    startY = startY + lineH * 0.7

    local remaining = GameConfig.PITY_SSR_COUNT - gachaState.pityCounter
    DrawWhiteInkText(leftX, startY, "当前距保底: " .. remaining .. " 抽")
    startY = startY + lineH

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 70, 50)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 残片/整卡出率
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "召唤产出形式")
    startY = startY + lineH * 0.8

    nvgFontSize(vg, 14.5)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "整卡直出")
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(rightX, startY, HERO_FULL_CARD_RATE .. "%")
    startY = startY + lineH * 0.7

    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "武灵残片 (1~5个)")
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(rightX, startY, (100 - HERO_FULL_CARD_RATE) .. "%")
    startY = startY + lineH * 0.7

    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 170, 150, 180))
    nvgText(vg, leftX, startY, "* 保底SSR必定为整卡", nil)
    startY = startY + lineH * 0.7

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 70, 50)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 残片合成阶梯
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "残片合成所需")
    startY = startY + lineH * 0.8

    nvgFontSize(vg, 14.5)
    local fragInfo = {
        { tag = "N",   cnt = HERO_FRAG_EXCHANGE[1], color = QUALITY_COLORS[1] },
        { tag = "R",   cnt = HERO_FRAG_EXCHANGE[2], color = QUALITY_COLORS[2] },
        { tag = "SR",  cnt = HERO_FRAG_EXCHANGE[3], color = QUALITY_COLORS[3] },
        { tag = "SSR", cnt = HERO_FRAG_EXCHANGE[4], color = QUALITY_COLORS[4] },
        { tag = "限定SSR", cnt = HERO_FRAG_EXCHANGE[5], color = QUALITY_COLORS[5] },
    }
    for _, fi in ipairs(fragInfo) do
        local fic = fi.color
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(fic[1], fic[2], fic[3], 200))
        nvgText(vg, leftX + 4, startY, fi.tag .. " 品质", nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(rightX, startY, fi.cnt .. " 残片")
        startY = startY + lineH * 0.7
    end

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 70, 50)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 重复角色规则
    nvgFontSize(vg, 27)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "满命格重复转化")
    startY = startY + lineH * 0.8

    nvgFontSize(vg, 14.5)
    local refundInfo = {
        { tag = "N",   jade = GameConfig.DUPLICATE_JADE_REWARD[1], color = QUALITY_COLORS[1] },
        { tag = "R",   jade = GameConfig.DUPLICATE_JADE_REWARD[2], color = QUALITY_COLORS[2] },
        { tag = "SR",  jade = GameConfig.DUPLICATE_JADE_REWARD[3], color = QUALITY_COLORS[3] },
        { tag = "SSR", jade = GameConfig.DUPLICATE_JADE_REWARD[4], color = QUALITY_COLORS[4] },
    }

    for _, ri in ipairs(refundInfo) do
        local ric = ri.color
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(ric[1], ric[2], ric[3], 200))
        nvgText(vg, leftX + 4, startY, ri.tag .. "  满命格重复", nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(rightX, startY, ">> " .. ri.jade .. " 虎符")
        startY = startY + lineH * 0.7
    end

    -- 关闭按钮
    local closeBtnW = 120
    local closeBtnH = 36
    local closeBtnX = cx - closeBtnW / 2
    local closeBtnY = panelY + panelH - closeBtnH - 14
    nvgBeginPath(vg); nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6)
    nvgFillColor(vg, nvgRGBA(40, 45, 65, 220)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 80, 150)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, closeBtnY + closeBtnH / 2, "知道了")
    gachaRulesCloseBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH }
end


function DrawSkillGachaRulesPopup()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2

    -- 半透明遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(5, 5, 12, 110)); nvgFill(vg)

    -- 弹窗面板
    local panelW = W * 0.84
    local panelH = 570
    local panelX = cx - panelW / 2
    local panelY = H / 2 - panelH / 2 - 10

    -- 面板背景（紫色调，与武技主题一致）
    local panelGrad = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH,
        nvgRGBA(45, 35, 60, 240), nvgRGBA(32, 25, 48, 245))
    nvgBeginPath(vg); nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillPaint(vg, panelGrad); nvgFill(vg)

    -- 面板边框
    nvgBeginPath(vg); nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeColor(vg, nvgRGBA(160, 100, 200, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 标题
    local titleY = panelY + 28
    nvgFontSize(vg, 35)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, titleY, "武技感悟规则")

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, titleY + 18)
    nvgLineTo(vg, panelX + panelW - 20, titleY + 18)
    nvgStrokeColor(vg, nvgRGBA(140, 100, 180, 80)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    -- 各阶级出率
    local lineH = 28
    local startY = titleY + 36
    local leftX = panelX + 24
    local rightX = panelX + panelW - 24

    -- 小标题: 残片出率
    nvgFontSize(vg, 25)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "各阶级残片出率")
    startY = startY + lineH

    -- 7个等阶概率行 (与 SKILL_TIERS 7阶对齐)
    local totalWeight = 0
    for t = 1, 7 do totalWeight = totalWeight + (SKILL_FRAG_WEIGHTS[t] or 0) end
    local tierData = {}
    for t = 1, 7 do
        local st = SKILL_TIERS[t]
        local pct = (SKILL_FRAG_WEIGHTS[t] or 0) / totalWeight * 100
        table.insert(tierData, { name = st.name, pct = pct, color = st.color })
    end

    for _, td in ipairs(tierData) do
        local tc = td.color

        -- 等阶色块标签
        local tagW = 44
        nvgBeginPath(vg); nvgRoundedRect(vg, leftX, startY - 9, tagW, 18, 3)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 180)); nvgFill(vg)
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(leftX + tagW / 2, startY, td.name)

        -- 概率百分比
        local pctStr = string.format("%.1f%%", td.pct)
        nvgFontSize(vg, 23)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 220))
        nvgText(vg, rightX, startY, pctStr, nil)

        -- 概率条形图（直观展示）
        local barMaxW = rightX - leftX - tagW - 60
        local barH = 6
        local barX = leftX + tagW + 10
        local barW = barMaxW * (td.pct / 55)  -- 以最大55%为满
        nvgBeginPath(vg); nvgRoundedRect(vg, barX, startY - barH / 2, barMaxW, barH, 2)
        nvgFillColor(vg, nvgRGBA(40, 30, 60, 150)); nvgFill(vg)
        nvgBeginPath(vg); nvgRoundedRect(vg, barX, startY - barH / 2, barW, barH, 2)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 160)); nvgFill(vg)

        startY = startY + lineH * 0.85
    end

    -- 分隔线
    startY = startY + 6
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, startY)
    nvgLineTo(vg, panelX + panelW - 20, startY)
    nvgStrokeColor(vg, nvgRGBA(140, 100, 180, 50)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    startY = startY + 14

    -- 兑换说明
    nvgFontSize(vg, 25)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(leftX, startY, "残片兑换")
    startY = startY + lineH * 0.85

    nvgFontSize(vg, 19)
    DrawWhiteInkText(leftX + 10, startY, "· 集齐 " .. SKILL_FRAG_EXCHANGE .. " 个同武技残片可兑换完整武技")
    startY = startY + lineH * 0.7
    nvgText(vg, leftX + 10, startY, "· 探索/战斗/任务可获得特定武技残片", nil)
    startY = startY + lineH * 0.7
    nvgText(vg, leftX + 10, startY, "· 每次感悟获得 " .. SKILL_FRAG_PER_PULL .. " 个随机残片", nil)

    -- 关闭按钮
    local closeBtnW = 120
    local closeBtnH = 36
    local closeBtnX = cx - closeBtnW / 2
    local closeBtnY = panelY + panelH - closeBtnH - 14
    nvgBeginPath(vg); nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6)
    nvgFillColor(vg, nvgRGBA(40, 30, 60, 220)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 130, 220, 150)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, closeBtnY + closeBtnH / 2, "知道了")
    gachaRulesCloseBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH }
end


--- 抽卡待机界面: 旋转召唤阵 + 按钮
function DrawGachaIdle(t)
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local circleY = H * 0.42
    local circleR = 95

    -- 召唤阵外圈: 旋转虚线光弧
    for i = 1, 12 do
        local angle = (i / 12) * math.pi * 2 + t * 0.6
        local arcLen = math.pi / 8
        local r = circleR + 8 + 3 * math.sin(t * 2 + i)
        nvgBeginPath(vg)
        nvgArc(vg, cx, circleY, r, angle, angle + arcLen, NVG_CW)
        local pulse = 0.4 + 0.6 * math.sin(t * 1.5 + i * 0.5)
        nvgStrokeColor(vg, nvgRGBA(160, 130, 80, math.floor(100 * pulse)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    end

    -- 内圈
    for i = 1, 8 do
        local angle = -(i / 8) * math.pi * 2 + t * 1.0
        local arcLen = math.pi / 6
        nvgBeginPath(vg)
        nvgArc(vg, cx, circleY, circleR - 5, angle, angle + arcLen, NVG_CW)
        local pulse = 0.3 + 0.7 * math.sin(t * 2.5 + i * 0.8)
        nvgStrokeColor(vg, nvgRGBA(120, 180, 220, math.floor(80 * pulse)))
        nvgStrokeWidth(vg, 1.0); nvgStroke(vg)
    end

    -- 中心光晕
    local glowPulse = 0.6 + 0.4 * math.sin(t * 2)
    local glow = nvgRadialGradient(vg, cx, circleY, 5, circleR * 0.8,
        nvgRGBA(180, 160, 100, math.floor(40 * glowPulse)),
        nvgRGBA(100, 120, 180, 0))
    nvgBeginPath(vg); nvgCircle(vg, cx, circleY, circleR * 0.8)
    nvgFillPaint(vg, glow); nvgFill(vg)

    -- 中心文字
    nvgFontFaceId(vg, GetMainFont())
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local textPulse = 0.6 + 0.4 * math.sin(t * 1.8)
    nvgFillColor(vg, nvgRGBA(220, 200, 140, math.floor(180 * textPulse)))
    nvgText(vg, cx, circleY, "灵 将 召 唤", nil)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(190, 180, 155, 160))
    nvgText(vg, cx, circleY + 26, "消耗虎符, 召唤武灵", nil)

    -- ===========================
    -- 抽卡按钮
    -- ===========================
    local bigPull = playerInfo.jadeUnlockedBigPull
    gachaHundredBtnRect = nil  -- 每帧重置

    if bigPull then
        -- 增强模式: 3个按钮 (10连/50连/100连)
        local btnW = 160
        local btnH = 46
        local btnGap = 8
        local btnY1 = H * 0.62
        local btnY2 = btnY1 + btnH + btnGap
        local btnY3 = btnY2 + btnH + btnGap
        local unitCost = GameConfig.GACHA_COST_SINGLE

        -- 10连按钮
        local b1x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b1x, btnY1, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(25, 32, 50, 200)); nvgFill(vg)
        local bp1 = 0.7 + 0.3 * math.sin(t * 2)
        nvgStrokeColor(vg, nvgRGBA(180, 145, 75, math.floor(180 * bp1)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 - 7, "十 连 召 唤")
        nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(220, 200, 150, 200))
        nvgText(vg, cx, btnY1 + btnH / 2 + 12, math.floor(unitCost * 10 * 0.9) .. " 虎符 (9折)", nil)
        gachaSingleBtnRect = { x = b1x, y = btnY1, w = btnW, h = btnH }

        -- 50连按钮
        local b2x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        local g50 = nvgLinearGradient(vg, b2x, btnY2, b2x + btnW, btnY2 + btnH,
            nvgRGBA(30, 28, 55, 220), nvgRGBA(45, 25, 60, 220))
        nvgFillPaint(vg, g50); nvgFill(vg)
        local bp2 = 0.6 + 0.4 * math.sin(t * 2.5)
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(220, 180, 80, math.floor(200 * bp2)))
        nvgStrokeWidth(vg, 1.8); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 - 7, "五十连召唤")
        nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(255, 220, 130, 210))
        nvgText(vg, cx, btnY2 + btnH / 2 + 12, math.floor(unitCost * 50 * 0.9) .. " 虎符 (9折)", nil)
        gachaTenBtnRect = { x = b2x, y = btnY2, w = btnW, h = btnH }

        -- 100连按钮 (最突出)
        local b3x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b3x, btnY3, btnW, btnH, 6)
        local g100 = nvgLinearGradient(vg, b3x, btnY3, b3x + btnW, btnY3 + btnH,
            nvgRGBA(50, 20, 30, 230), nvgRGBA(60, 15, 45, 230))
        nvgFillPaint(vg, g100); nvgFill(vg)
        local bp3 = 0.5 + 0.5 * math.sin(t * 3)
        nvgBeginPath(vg); nvgRoundedRect(vg, b3x, btnY3, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(255, 180, 60, math.floor(220 * bp3)))
        nvgStrokeWidth(vg, 2.0); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY3 + btnH / 2 - 7, "百 连 召 唤")
        nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(255, 200, 80, 230))
        nvgText(vg, cx, btnY3 + btnH / 2 + 12, math.floor(unitCost * 100 * 0.9) .. " 虎符 (9折)", nil)
        gachaHundredBtnRect = { x = b3x, y = btnY3, w = btnW, h = btnH }
    else
        -- 原始模式: 2个按钮 (单抽/十连)
        local btnW = 160
        local btnH = 56
        local btnGap = 16
        local btnY1 = H * 0.66
        local btnY2 = btnY1 + btnH + btnGap

        -- 单抽按钮
        local b1x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b1x, btnY1, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(25, 32, 50, 200)); nvgFill(vg)
        local borderPulse1 = 0.7 + 0.3 * math.sin(t * 2)
        nvgStrokeColor(vg, nvgRGBA(180, 145, 75, math.floor(180 * borderPulse1)))
        nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY1 + btnH / 2 - 8, "单 抽")
        nvgFontSize(vg, 16); nvgFillColor(vg, nvgRGBA(220, 200, 150, 200))
        nvgText(vg, cx, btnY1 + btnH / 2 + 14, GameConfig.GACHA_COST_SINGLE .. " 虎符", nil)
        gachaSingleBtnRect = { x = b1x, y = btnY1, w = btnW, h = btnH }

        -- 十连按钮 (更突出)
        local b2x = cx - btnW / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        local tenGrad = nvgLinearGradient(vg, b2x, btnY2, b2x + btnW, btnY2 + btnH,
            nvgRGBA(30, 28, 55, 220), nvgRGBA(45, 25, 60, 220))
        nvgFillPaint(vg, tenGrad); nvgFill(vg)
        local borderPulse2 = 0.6 + 0.4 * math.sin(t * 2.5)
        nvgBeginPath(vg); nvgRoundedRect(vg, b2x, btnY2, btnW, btnH, 6)
        nvgStrokeColor(vg, nvgRGBA(220, 180, 80, math.floor(200 * borderPulse2)))
        nvgStrokeWidth(vg, 1.8); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, btnY2 + btnH / 2 - 8, "十 连 召 唤")
        nvgFontSize(vg, 16); nvgFillColor(vg, nvgRGBA(255, 220, 130, 210))
        nvgText(vg, cx, btnY2 + btnH / 2 + 14, GameConfig.GACHA_COST_TEN .. " 虎符 (9折)", nil)
        gachaTenBtnRect = { x = b2x, y = btnY2, w = btnW, h = btnH }
    end

    -- 计算最后一个按钮底部Y (兼容增强模式3按钮)
    local lastBtnBottom = gachaHundredBtnRect and (gachaHundredBtnRect.y + gachaHundredBtnRect.h) or (gachaTenBtnRect.y + gachaTenBtnRect.h)

    -- 拥有武灵提示
    local ownedCount = 0
    for _, h in pairs(playerHeroes) do
        if h.owned then ownedCount = ownedCount + 1 end
    end
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 195, 180, 180))
    nvgText(vg, cx, lastBtnBottom + 18, "已拥有 " .. ownedCount .. "/" .. #HERO_CARDS .. " 位武灵", nil)

    -- 保底进度
    local pityRemain = GameConfig.PITY_SSR_COUNT - gachaState.pityCounter
    local pityText = "距保底: " .. pityRemain .. " 抽 | 保底必出整卡"
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 170, 140, 160))
    nvgText(vg, cx, lastBtnBottom + 38, pityText, nil)

    -- 残片仓库按钮（左下角）
    local bottomBtnY = lastBtnBottom + 8
    local shopBtnW = 90
    local shopBtnH = 30
    local shopBtnX = 12
    nvgBeginPath(vg); nvgRoundedRect(vg, shopBtnX, bottomBtnY, shopBtnW, shopBtnH, 6)
    nvgFillColor(vg, nvgRGBA(35, 30, 50, 210)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 145, 75, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(shopBtnX + shopBtnW / 2, bottomBtnY + shopBtnH / 2, "残片仓库")
    -- 可合成红点
    local heroComposeN = 0
    for ci, cnt in pairs(heroFragments) do
        local cd = HERO_CARDS[ci]
        if cd and cnt >= (HERO_FRAG_EXCHANGE[cd.quality] or 20) then heroComposeN = heroComposeN + 1 end
    end
    local skillComposeN = 0
    for _, cnt in pairs(skillFragments) do
        if cnt >= SKILL_FRAG_EXCHANGE then skillComposeN = skillComposeN + 1 end
    end
    local totalCompN = heroComposeN + skillComposeN
    if totalCompN > 0 then
        local dotR = 7
        local dotX = shopBtnX + shopBtnW - 4
        local dotY = bottomBtnY + 4
        nvgBeginPath(vg); nvgCircle(vg, dotX, dotY, dotR)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 230)); nvgFill(vg)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(dotX, dotY, tostring(totalCompN))
    end
    gachaFragShopBtnRect = { x = shopBtnX, y = bottomBtnY, w = shopBtnW, h = shopBtnH }

    -- "?" 概率规则按钮 (右下角)
    local qBtnSize = 30
    local qBtnX = W - qBtnSize - 12
    local qBtnY = bottomBtnY
    nvgBeginPath(vg); nvgCircle(vg, qBtnX + qBtnSize / 2, qBtnY + qBtnSize / 2, qBtnSize / 2)
    nvgFillColor(vg, nvgRGBA(40, 45, 65, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 160, 100, 160)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(qBtnX + qBtnSize / 2, qBtnY + qBtnSize / 2, "?")
    gachaRulesBtnRect = { x = qBtnX, y = qBtnY, w = qBtnSize, h = qBtnSize }
end


-- ============================================================================
-- 限定池 UI
-- ============================================================================

--- 限定池待机界面
