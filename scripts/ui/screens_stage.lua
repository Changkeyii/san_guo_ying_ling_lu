-- ui/screens_stage.lua - 三国武灵录 (从 screens.lua 拆分)
function DrawStageSelectScreen()
    if gameState.phase ~= "STAGE_SELECT" then return end
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local t = gameState.gameTime
    local page = stageState.currentPage

    -- 地图背景
    DrawBgImage(IMG.mapBg, W, H, 1143, 2048)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(8, 12, 20, 100)); nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- ========== 顶部栏 ==========
    local topY = 10
    local backW, backH = 100, 40
    nvgBeginPath(vg); nvgRoundedRect(vg, 10, topY, backW, backH, 6)
    nvgFillColor(vg, nvgRGBA(20, 25, 40, 200)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    nvgFontSize(vg, 28); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(10 + backW/2, topY + backH/2, "< 返回")
    stageBackBtnRect = { x = 10, y = topY, w = backW, h = backH }

    -- 标题 + 页名
    local titleCY = topY + backH / 2
    nvgFontSize(vg, 36); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, titleCY, "乱世征途")
    local pageName = STAGE_PAGE_NAMES[page] or ("第" .. page .. "章")
    nvgFontSize(vg, 20)
    DrawWhiteInkText(cx, titleCY + 22, "- " .. pageName .. " (" .. page .. "/" .. STAGE_TOTAL_PAGES .. ") -")

    -- ========== 星级宝箱进度条 ==========
    local barY = topY + backH + 50
    local pageStars = GetPageStars(page)
    local maxPageStars = STAGE_PAGE_SIZE * 3  -- 30
    local barW = W - 60
    local barH = 18
    local barX = 30

    -- 进度条背景
    nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 9)
    nvgFillColor(vg, nvgRGBA(20, 25, 35, 200)); nvgFill(vg)
    -- 进度条填充
    local fillW = math.max(0, math.min(barW, barW * pageStars / maxPageStars))
    if fillW > 0 then
        nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, fillW, barH, 9)
        local barGrad = nvgLinearGradient(vg, barX, barY, barX + fillW, barY,
            nvgRGBA(80, 180, 255, 200), nvgRGBA(220, 180, 80, 220))
        nvgFillPaint(vg, barGrad); nvgFill(vg)
    end
    -- 边框
    nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 9)
    nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 140)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    -- 星数文字
    nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, barY + barH / 2, pageStars .. "/" .. maxPageStars .. " ★")

    -- 宝箱图标 (3个: 10★, 20★, 30★)
    stageChestRects = {}
    local chestSize = 30
    for ci, threshold in ipairs(STAGE_CHEST_THRESHOLDS) do
        local chestX = barX + barW * (threshold / maxPageStars) - chestSize / 2
        local chestY = barY - chestSize / 2 + barH / 2
        local chestKey = tostring(page) .. "_" .. tostring(threshold)
        local claimed = stageChestClaimed[chestKey]
        local canClaim = (pageStars >= threshold) and not claimed

        -- 宝箱底盘
        nvgBeginPath(vg); nvgRoundedRect(vg, chestX, chestY, chestSize, chestSize, 4)
        if claimed then
            nvgFillColor(vg, nvgRGBA(40, 45, 35, 200))
        elseif canClaim then
            local cPulse = 0.6 + 0.4 * math.sin(t * 3 + ci)
            nvgFillColor(vg, nvgRGBA(60, 50, 20, math.floor(220 * cPulse)))
        else
            nvgFillColor(vg, nvgRGBA(30, 30, 40, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, claimed and nvgRGBA(60, 60, 50, 120) or nvgRGBA(220, 180, 60, 180))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 宝箱图案 (优先使用图片素材)
        if claimed then
            nvgFontSize(vg, 18); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 100, 80, 140))
            nvgText(vg, chestX + chestSize / 2, chestY + chestSize / 2, "✓", nil)
        elseif IsImageReady(IMG.treasureChest) then
            local alpha = canClaim and 1.0 or 0.45
            local pat = nvgImagePattern(vg, chestX + 2, chestY + 2, chestSize - 4, chestSize - 4, 0, IMG.treasureChest, alpha)
            nvgBeginPath(vg); nvgRoundedRect(vg, chestX + 2, chestY + 2, chestSize - 4, chestSize - 4, 3)
            nvgFillPaint(vg, pat); nvgFill(vg)
        else
            nvgFontSize(vg, 18); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, canClaim and nvgRGBA(255, 220, 80, 255) or nvgRGBA(160, 140, 80, 140))
            -- 绘制简约宝箱图案 (无emoji)
            nvgFillColor(vg, canClaim and nvgRGBA(255, 220, 80, 255) or nvgRGBA(160, 140, 80, 140))
            local bcx, bcy = chestX + chestSize / 2, chestY + chestSize / 2
            -- 箱体
            nvgBeginPath(vg); nvgRoundedRect(vg, bcx - 8, bcy - 4, 16, 10, 2)
            nvgFill(vg)
            -- 箱盖
            nvgBeginPath(vg); nvgRoundedRect(vg, bcx - 9, bcy - 7, 18, 5, 2)
            nvgFill(vg)
            -- 锁扣
            nvgBeginPath(vg); nvgCircle(vg, bcx, bcy, 2)
            nvgFillColor(vg, nvgRGBA(120, 80, 20, 200)); nvgFill(vg)
        end

        -- 阈值标记
        nvgFontSize(vg, 11); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 180, 120, 180))
        nvgText(vg, chestX + chestSize / 2, chestY + chestSize + 2, threshold .. "★", nil)

        stageChestRects[ci] = { x = chestX, y = chestY, w = chestSize, h = chestSize, threshold = threshold, page = page }
    end

    -- ========== 关卡网格 (2列5行 = 10关) ==========
    local gridStartY = barY + barH + 40
    local cols = 2
    local rows = 5
    local cellW = (W - 50) / cols
    local cellH = 80
    local gridX = 25
    local startIdx = (page - 1) * STAGE_PAGE_SIZE + 1
    stageNodeRects = {}

    for i = 0, STAGE_PAGE_SIZE - 1 do
        local stageIdx = startIdx + i
        if stageIdx > #STAGES then break end
        local stage = STAGES[stageIdx]
        local col = i % cols
        local row = math.floor(i / cols)
        local cellX = gridX + col * cellW + 5
        local cellY = gridStartY + row * cellH
        local cw = cellW - 10
        local ch = cellH - 8

        local isUnlocked = (stageIdx <= stageState.maxUnlocked)
        local isSelected = (stageIdx == stageState.currentStage)
        local stars = stageStars[tostring(stageIdx)] or 0
        local sc = stage.color

        -- 保存点击区域 (使用局部索引 i+1 对应全局 stageIdx)
        stageNodeRects[i + 1] = { x = cellX, y = cellY, w = cw, h = ch, stageIdx = stageIdx }

        -- 选中高亮
        if isSelected and isUnlocked then
            local pulse = 0.7 + 0.3 * math.sin(t * 3)
            nvgBeginPath(vg); nvgRoundedRect(vg, cellX - 2, cellY - 2, cw + 4, ch + 4, 8)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 100, math.floor(180 * pulse)))
            nvgStrokeWidth(vg, 2); nvgStroke(vg)
        end

        -- 卡片背景
        nvgBeginPath(vg); nvgRoundedRect(vg, cellX, cellY, cw, ch, 6)
        if isUnlocked then
            nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 25))
        else
            nvgFillColor(vg, nvgRGBA(20, 22, 28, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, isUnlocked and nvgRGBA(sc[1], sc[2], sc[3], 140) or nvgRGBA(50, 50, 55, 120))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 关卡编号
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, isUnlocked and nvgRGBA(sc[1], sc[2], sc[3], 180) or nvgRGBA(80, 80, 80, 160))
        nvgText(vg, cellX + 8, cellY + 6, tostring(stageIdx), nil)

        -- 关卡名称
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isUnlocked then
            nvgFontSize(vg, 19)
            nvgFillColor(vg, nvgRGBA(240, 230, 200, 240))
            nvgText(vg, cellX + cw / 2, cellY + ch / 2 - 10, stage.name, nil)
            -- 描述
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(180, 170, 140, 160))
            nvgText(vg, cellX + cw / 2, cellY + ch / 2 + 6, stage.desc, nil)
        else
            nvgFontSize(vg, 30)
            nvgFillColor(vg, nvgRGBA(60, 60, 60, 160))
            -- 绘制锁图案 (无emoji)
            local lkCx, lkCy = cellX + cw / 2, cellY + ch / 2 - 5
            nvgFillColor(vg, nvgRGBA(60, 60, 60, 160))
            -- 锁体
            nvgBeginPath(vg); nvgRoundedRect(vg, lkCx - 8, lkCy - 2, 16, 14, 3)
            nvgFill(vg)
            -- 锁环
            nvgBeginPath(vg); nvgArc(vg, lkCx, lkCy - 2, 6, math.pi, 0, 2)
            nvgStrokeColor(vg, nvgRGBA(60, 60, 60, 160)); nvgStrokeWidth(vg, 2.5); nvgStroke(vg)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(80, 80, 80, 140))
            nvgText(vg, cellX + cw / 2, cellY + ch / 2 + 12, "未解锁", nil)
        end

        -- 星级显示 (底部)
        if isUnlocked then
            local starY = cellY + ch - 16
            local starStartX = cellX + cw / 2 - 20
            for s = 1, 3 do
                nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if s <= stars then
                    nvgFillColor(vg, nvgRGBA(255, 220, 60, 240))
                else
                    nvgFillColor(vg, nvgRGBA(60, 55, 45, 140))
                end
                nvgText(vg, starStartX + (s - 1) * 16, starY, "★", nil)
            end
        end
    end

    -- ========== 翻页按钮 ==========
    local navY = gridStartY + rows * cellH + 8
    local arrowW, arrowH = 80, 36
    stagePagePrevRect = nil
    stagePageNextRect = nil

    if page > 1 then
        local prevX = 30
        nvgBeginPath(vg); nvgRoundedRect(vg, prevX, navY, arrowW, arrowH, 6)
        nvgFillColor(vg, nvgRGBA(25, 30, 42, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 140)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(prevX + arrowW / 2, navY + arrowH / 2, "< 上页")
        stagePagePrevRect = { x = prevX, y = navY, w = arrowW, h = arrowH }
    end

    if page < STAGE_TOTAL_PAGES then
        local nextX = W - 30 - arrowW
        nvgBeginPath(vg); nvgRoundedRect(vg, nextX, navY, arrowW, arrowH, 6)
        nvgFillColor(vg, nvgRGBA(25, 30, 42, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 140)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(nextX + arrowW / 2, navY + arrowH / 2, "下页 >")
        stagePageNextRect = { x = nextX, y = navY, w = arrowW, h = arrowH }
    end

    -- 页码指示器
    nvgFontSize(vg, 16); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, navY + arrowH / 2, page .. " / " .. STAGE_TOTAL_PAGES)

    -- ===========================
    -- 关卡预览弹窗
    -- ===========================
    if stageState.showPreview and not stageState.showDropPopup then
        local stage = STAGES[stageState.currentStage]
        if stage then
            local popW = W - 40
            local popH = 330
            local popX = 20
            local popY = H / 2 - popH / 2

            -- 遮罩
            nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(5, 5, 12, 120)); nvgFill(vg)

            -- 弹窗底板
            nvgBeginPath(vg); nvgRoundedRect(vg, popX, popY, popW, popH, 8)
            nvgFillColor(vg, nvgRGBA(18, 22, 35, 240)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

            local sc2 = stage.color
            local curStars = stageStars[tostring(stageState.currentStage)] or 0

            -- 关卡名
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 36)
            nvgFillColor(vg, nvgRGBA(sc2[1], sc2[2], sc2[3], 240))
            nvgText(vg, cx, popY + 28, stage.name, nil)

            nvgFontSize(vg, 20)
            DrawWhiteInkText(cx, popY + 50, stage.desc)

            -- 星级展示
            nvgFontSize(vg, 24); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local starDispY = popY + 72
            for s = 1, 3 do
                if s <= curStars then
                    nvgFillColor(vg, nvgRGBA(255, 220, 60, 240))
                else
                    nvgFillColor(vg, nvgRGBA(60, 55, 45, 140))
                end
                nvgText(vg, cx - 30 + (s - 1) * 28, starDispY, "★", nil)
            end
            -- 首次星级虎符奖励提示 (带虎符图标)
            nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local rewardHintY = starDispY + 18
            local ticketIconSize = 14
            local hasTicketIcon = IsImageReady(IMG.abyssTicket)
            for s = 1, 3 do
                local claimKey = tostring(stageState.currentStage) .. "_" .. s
                local claimed = stageStarClaimed[claimKey]
                if claimed then
                    nvgFillColor(vg, nvgRGBA(100, 100, 80, 140))
                elseif s <= curStars then
                    nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
                else
                    nvgFillColor(vg, nvgRGBA(160, 140, 100, 120))
                end
                local rewardCX = cx - 80 + (s - 1) * 80
                local jTxt = s .. "★:" .. STAGE_STAR_JADE[s]
                if claimed then jTxt = jTxt .. " ✓" end
                -- 先画文字
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgText(vg, rewardCX + 2, rewardHintY, jTxt, nil)
                -- 再画虎符图标 (文字右侧)
                if hasTicketIcon then
                    local alpha = claimed and 0.4 or 1.0
                    local tPat = nvgImagePattern(vg, rewardCX + 4, rewardHintY - ticketIconSize / 2, ticketIconSize, ticketIconSize, 0, IMG.abyssTicket, alpha)
                    nvgBeginPath(vg); nvgRect(vg, rewardCX + 4, rewardHintY - ticketIconSize / 2, ticketIconSize, ticketIconSize)
                    nvgFillPaint(vg, tPat); nvgFill(vg)
                else
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgText(vg, rewardCX + 4, rewardHintY, "虎符", nil)
                end
            end

            -- 可爆装备
            nvgFontSize(vg, 18)
            DrawWhiteInkText(cx, popY + 110, "- 可获得兵甲 -")

            local dropY = popY + 126
            local dropItemW = 52
            local dropGap = 6
            local dropSets = stage.dropSets
            local totalDropW = #dropSets * dropItemW + (#dropSets - 1) * dropGap
            local dropStartX = cx - totalDropW / 2

            for di, dSetIdx in ipairs(dropSets) do
                local dx = dropStartX + (di - 1) * (dropItemW + dropGap)
                local dSetData = EQUIPMENT_SETS[dSetIdx]
                local dsc = dSetData.color

                nvgBeginPath(vg); nvgRoundedRect(vg, dx, dropY, dropItemW, dropItemW + 16, 4)
                nvgFillColor(vg, nvgRGBA(25, 30, 42, 220)); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(dsc[1], dsc[2], dsc[3], 120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

                if IMG.equipmentSheet and IMG.equipmentSheet > 0 then
                    DrawCardImage(dx + 4, dropY + 4, dropItemW - 8, dropItemW - 8, IMG.equipmentSheet, 0, dSetIdx - 1, EQUIP_SHEET_COLS, EQUIP_SHEET_ROWS)
                end
                nvgFontSize(vg, 10.5); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(dsc[1], dsc[2], dsc[3], 200))
                nvgText(vg, dx + dropItemW / 2, dropY + dropItemW + 8, dSetData.name, nil)
            end

            -- 最高阶级
            local tierHintY = dropY + dropItemW + 26
            nvgFontSize(vg, 17); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local mtc = EQUIP_TIERS[stage.maxTier].color
            nvgFillColor(vg, nvgRGBA(mtc[1], mtc[2], mtc[3], 200))
            nvgText(vg, cx, tierHintY, "最高掉落: " .. EQUIP_TIERS[stage.maxTier].name, nil)

            -- 战力预估
            local powerY = tierHintY + 18
            local myPower = CalcPlayerTotalPower()
            local ePow, minReq, recReq = CalcStageRequiredPower(stage.enemyScale)
            local powerRatio = (ePow > 0) and (myPower / ePow) or 99.0
            local gradeTxt, gradeClr = GetPowerGrade(powerRatio)

            nvgFontSize(vg, 18); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            DrawWhiteInkText(cx, powerY, "我方战力 " .. FormatPower(myPower))
            nvgFontSize(vg, 16)
            local infoY = powerY + 16
            if myPower >= minReq then
                nvgFillColor(vg, nvgRGBA(140, 220, 140, 220))
            else
                nvgFillColor(vg, nvgRGBA(255, 100, 80, 240))
            end
            nvgText(vg, cx - 70, infoY, "最低 " .. FormatPower(minReq), nil)
            if myPower >= recReq then
                nvgFillColor(vg, nvgRGBA(140, 220, 140, 220))
            else
                nvgFillColor(vg, nvgRGBA(255, 180, 80, 220))
            end
            nvgText(vg, cx + 70, infoY, "推荐 " .. FormatPower(recReq), nil)
            nvgFillColor(vg, nvgRGBA(gradeClr[1], gradeClr[2], gradeClr[3], 240))
            nvgFontSize(vg, 17)
            nvgText(vg, cx, infoY + 15, "[ " .. gradeTxt .. " ]", nil)

            -- 出战按钮
            local startBtnW = 140
            local startBtnH = 38
            local startBtnX = cx - startBtnW / 2
            local startBtnY = popY + popH - 50
            local btnPulse = 0.7 + 0.3 * math.sin(t * 2.5)
            nvgBeginPath(vg); nvgRoundedRect(vg, startBtnX, startBtnY, startBtnW, startBtnH, 6)
            local sGrad = nvgLinearGradient(vg, startBtnX, startBtnY, startBtnX, startBtnY + startBtnH,
                nvgRGBA(40, 30, 55, 220), nvgRGBA(25, 18, 35, 240))
            nvgFillPaint(vg, sGrad); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(220, 180, 80, math.floor(200 * btnPulse)))
            nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            nvgFontSize(vg, 33); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            DrawWhiteInkText(cx, startBtnY + startBtnH / 2, "出  战")
            stageStartBtnRect = { x = startBtnX, y = startBtnY, w = startBtnW, h = startBtnH }

            -- 关闭按钮
            local closeBtnW = 26
            local closeBtnX = popX + popW - closeBtnW - 6
            local closeBtnY = popY + 6
            nvgBeginPath(vg); nvgCircle(vg, closeBtnX + closeBtnW/2, closeBtnY + closeBtnW/2, closeBtnW/2)
            nvgFillColor(vg, nvgRGBA(60, 50, 40, 200)); nvgFill(vg)
            nvgFontSize(vg, 30); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            DrawWhiteInkText(closeBtnX + closeBtnW/2, closeBtnY + closeBtnW/2, "×")
            stagePreviewCloseRect = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnW }
        end
    end

    -- ===========================
    -- 爆装获取弹窗
    -- ===========================
    if stageState.showDropPopup and stageState.lastDropReward then
        local reward = stageState.lastDropReward
        local rSet = EQUIPMENT_SETS[reward.setIdx]
        local rPiece = rSet.pieces[reward.slotIdx]
        local rTier = EQUIP_TIERS[reward.tier or 1]
        local rtc = rTier.color

        local popW = W - 60
        local popH = 200
        local popX = 30
        local popY = H / 2 - popH / 2

        -- 遮罩
        nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(5, 5, 12, 95)); nvgFill(vg)

        -- 弹窗
        nvgBeginPath(vg); nvgRoundedRect(vg, popX, popY, popW, popH, 8)
        nvgFillColor(vg, nvgRGBA(30, 35, 52, 235)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(rtc[1], rtc[2], rtc[3], 200)); nvgStrokeWidth(vg, 2); nvgStroke(vg)

        -- 光效
        local gPulse = 0.6 + 0.4 * math.sin(t * 3)
        local glow = nvgRadialGradient(vg, cx, popY + 80, 10, 60,
            nvgRGBA(rtc[1], rtc[2], rtc[3], math.floor(50 * gPulse)), nvgRGBA(rtc[1], rtc[2], rtc[3], 0))
        nvgBeginPath(vg); nvgCircle(vg, cx, popY + 80, 60)
        nvgFillPaint(vg, glow); nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 33)
        DrawWhiteInkText(cx, popY + 24, "获得兵甲!")

        -- 装备图标
        if IMG.equipmentSheet and IMG.equipmentSheet > 0 then
            local iconS = 56
            DrawEquipTierBg(cx - iconS/2, popY + 40, iconS, iconS, reward.tier, 5)
            DrawCardImage(cx - iconS/2, popY + 40, iconS, iconS, IMG.equipmentSheet, reward.slotIdx - 1, reward.setIdx - 1, EQUIP_SHEET_COLS, EQUIP_SHEET_ROWS)
        end

        -- 名称
        nvgFontSize(vg, 33)
        nvgFillColor(vg, nvgRGBA(rtc[1], rtc[2], rtc[3], 240))
        nvgText(vg, cx, popY + 110, rPiece.name, nil)

        -- 阶级 + 套装
        nvgFontSize(vg, 27)
        nvgFillColor(vg, nvgRGBA(rtc[1], rtc[2], rtc[3], 180))
        nvgText(vg, cx, popY + 130, "[" .. rTier.name .. "] " .. rSet.name .. " - " .. EQUIP_SLOT_NAMES[reward.slotIdx], nil)

        -- 属性
        local tierMul = rTier.multiplier
        nvgFontSize(vg, 19)
        nvgFillColor(vg, nvgRGBA(160, 220, 160, 200))
        nvgText(vg, cx, popY + 150, string.format("ATK+%d  DEF+%d  HP+%d",
            math.ceil(rPiece.atk * tierMul), math.ceil(rPiece.def * tierMul), math.ceil(rPiece.hp * tierMul)), nil)

        -- 关闭
        local closeBtnY2 = popY + popH - 40
        local closeBtnW2 = 120
        local closeBtnH2 = 32
        nvgBeginPath(vg); nvgRoundedRect(vg, cx - closeBtnW2/2, closeBtnY2, closeBtnW2, closeBtnH2, 5)
        nvgFillColor(vg, nvgRGBA(30, 35, 50, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 150, 80, 160)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 22)
        DrawWhiteInkText(cx, closeBtnY2 + closeBtnH2/2, "确认")
        stageDropCloseRect = { x = cx - closeBtnW2/2, y = closeBtnY2, w = closeBtnW2, h = closeBtnH2 }
    end
end


-- ============================================================================
-- 每日副本 选择界面 (重制版)
-- ============================================================================
function DrawDailyDungeonScreen()
    if gameState.phase ~= "DAILY_DUNGEON" then return end
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local t = gameState.gameTime

    -- 专属背景图 + 暗化叠加
    DrawBgImage(IMG.dailyDungeonBg, W, H, 572, 1025)
    -- 顶部暗化渐变
    local topGrad = nvgLinearGradient(vg, 0, 0, 0, H * 0.18,
        nvgRGBA(6, 12, 18, 200), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H * 0.18)
    nvgFillPaint(vg, topGrad); nvgFill(vg)
    -- 底部暗雾
    local botGrad = nvgLinearGradient(vg, 0, H * 0.72, 0, H,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(8, 14, 12, 180))
    nvgBeginPath(vg); nvgRect(vg, 0, H * 0.72, W, H * 0.28)
    nvgFillPaint(vg, botGrad); nvgFill(vg)
    -- 半透明暗板 (让卡片区域可读)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(8, 12, 16, 60)); nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 顶部返回按钮 (暗绿哥特风)
    local topY = 14
    local backW, backH = 100, 38
    nvgBeginPath(vg); nvgRoundedRect(vg, 14, topY, backW, backH, 6)
    nvgFillColor(vg, nvgRGBA(10, 20, 16, 210)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 140, 100, 130)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 26); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(5, 5, 12, 95))
    nvgText(vg, 14 + backW/2 + 1, topY + backH/2 + 1, "< 返回", nil)
    DrawWhiteInkText(14 + backW/2, topY + backH/2, "< 返回")
    dailyDungeonBackRect = { x = 14, y = topY, w = backW, h = backH }

    -- 标题 (多层投影, 与讨伐/爬塔一致)
    local titleCY = topY + backH / 2
    nvgFontSize(vg, 38); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(10, 40, 30, 130))
    nvgText(vg, cx + 2, titleCY + 2, "每日副本", nil)
    nvgFillColor(vg, nvgRGBA(40, 160, 110, 180))
    nvgText(vg, cx + 1, titleCY + 1, "每日副本", nil)
    DrawWhiteInkText(cx, titleCY, "每日副本")

    -- 副标题 (完成进度)
    local doneCount = 0
    for i = 1, 3 do if dailyDungeonState.completed[i] then doneCount = doneCount + 1 end end
    nvgFontSize(vg, 27)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgText(vg, cx + 1, titleCY + 23, "- 今日进度 " .. doneCount .. "/3 -", nil)
    DrawWhiteInkText(cx, titleCY + 22, "- 今日进度 " .. doneCount .. "/3 -")

    -- 装饰分隔线 (暗绿色, 中心菱形)
    local sepY = titleCY + 38
    local sepHW = 130
    local sepGradL = nvgLinearGradient(vg, cx - sepHW, sepY, cx - 8, sepY,
        nvgRGBA(40, 160, 100, 0), nvgRGBA(60, 180, 120, 160))
    nvgBeginPath(vg); nvgMoveTo(vg, cx - sepHW, sepY); nvgLineTo(vg, cx - 8, sepY)
    nvgStrokeWidth(vg, 1.2); nvgStrokePaint(vg, sepGradL); nvgStroke(vg)
    local sepGradR = nvgLinearGradient(vg, cx + 8, sepY, cx + sepHW, sepY,
        nvgRGBA(60, 180, 120, 160), nvgRGBA(40, 160, 100, 0))
    nvgBeginPath(vg); nvgMoveTo(vg, cx + 8, sepY); nvgLineTo(vg, cx + sepHW, sepY)
    nvgStrokeWidth(vg, 1.2); nvgStrokePaint(vg, sepGradR); nvgStroke(vg)
    -- 中心菱形
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, sepY - 4); nvgLineTo(vg, cx + 4, sepY)
    nvgLineTo(vg, cx, sepY + 4); nvgLineTo(vg, cx - 4, sepY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(80, 200, 140, 200)); nvgFill(vg)

    -- 入场提示
    nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 180, 140, 160))
    nvgText(vg, cx, sepY + 16, "消耗300虎符入场 | 必掉装备", nil)

    -- 副本卡片列表
    local cardW = W - 32
    local cardH = 130
    local cardGap = 14
    local listStartY = sepY + 38
    dailyDungeonCardRects = {}

    for i = 1, 3 do
        local dc = DAILY_DUNGEON_COLORS[i]
        local cy = listStartY + (i - 1) * (cardH + cardGap)
        local isDone = dailyDungeonState.completed[i]

        dailyDungeonCardRects[i] = { x = 16, y = cy, w = cardW, h = cardH }

        -- 卡片背景 (深色哥特渐变 + 双层)
        nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, cardW, cardH, 6)
        if isDone then
            nvgFillColor(vg, nvgRGBA(18, 22, 20, 220))
        else
            local cardBg = nvgLinearGradient(vg, 16, cy, 16 + cardW, cy,
                nvgRGBA(14, 20, 18, 220), nvgRGBA(22, 16, 28, 220))
            nvgFillPaint(vg, cardBg)
        end
        nvgFill(vg)

        -- 卡片内部底光 (颜色微漫)
        if not isDone then
            local glowGrad = nvgLinearGradient(vg, 16, cy, 16, cy + cardH,
                nvgRGBA(dc[1], dc[2], dc[3], 12), nvgRGBA(dc[1], dc[2], dc[3], 3))
            nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, cardW, cardH, 6)
            nvgFillPaint(vg, glowGrad); nvgFill(vg)
        end

        -- 左侧竖条装饰 (颜色标识)
        nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, 4, cardH, 2)
        if isDone then
            nvgFillColor(vg, nvgRGBA(50, 70, 55, 100))
        else
            local barPulse = 0.6 + 0.4 * math.sin(t * 2.0 + i * 1.2)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(220 * barPulse)))
        end
        nvgFill(vg)

        -- 外边框
        nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, cardW, cardH, 6)
        if isDone then
            nvgStrokeColor(vg, nvgRGBA(50, 60, 50, 70))
        else
            local bPulse = 0.5 + 0.5 * math.sin(t * 1.8 + i * 0.9)
            nvgStrokeColor(vg, nvgRGBA(
                math.floor(dc[1] * 0.5 + 60),
                math.floor(dc[2] * 0.3 + 40),
                math.floor(dc[3] * 0.3 + 40),
                math.floor(100 * bPulse)))
        end
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        -- 内边框 (微弱)
        if not isDone then
            nvgBeginPath(vg); nvgRoundedRect(vg, 18, cy + 2, cardW - 4, cardH - 4, 5)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 20)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)
        end

        -- 左侧图标区域 (大圆角方块)
        local iconSize = 60
        local iconX = 28
        local iconY = cy + (cardH - iconSize) / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 10)
        if isDone then
            nvgFillColor(vg, nvgRGBA(22, 28, 24, 210))
        else
            local iconBg = nvgLinearGradient(vg, iconX, iconY, iconX, iconY + iconSize,
                nvgRGBA(dc[1] * 0.18, dc[2] * 0.18, dc[3] * 0.18, 220),
                nvgRGBA(dc[1] * 0.06, dc[2] * 0.06, dc[3] * 0.06, 220))
            nvgFillPaint(vg, iconBg)
        end
        nvgFill(vg)
        -- 图标边框
        nvgBeginPath(vg); nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 10)
        if isDone then
            nvgStrokeColor(vg, nvgRGBA(45, 55, 48, 60))
        else
            local iPulse = 0.6 + 0.4 * math.sin(t * 1.5 + i * 2)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(120 * iPulse)))
        end
        nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 图标文字 (大号粗体)
        nvgFontSize(vg, 32); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isDone then
            nvgFillColor(vg, nvgRGBA(70, 80, 70, 100))
            nvgText(vg, iconX + iconSize / 2, iconY + iconSize / 2, DAILY_DUNGEON_ICONS[i], nil)
        else
            -- 投影 + 高亮
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
            nvgText(vg, iconX + iconSize / 2 + 1, iconY + iconSize / 2 + 1, DAILY_DUNGEON_ICONS[i], nil)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, iconX + iconSize / 2, iconY + iconSize / 2, DAILY_DUNGEON_ICONS[i], nil)
        end

        -- 右侧文字区域
        local textX = iconX + iconSize + 14
        local textCY2 = cy + cardH / 2
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        if isDone then
            -- 已完成 - 暗淡风格
            nvgFontSize(vg, 27)
            nvgFillColor(vg, nvgRGBA(90, 100, 95, 140))
            nvgText(vg, textX, textCY2 - 22, DAILY_DUNGEON_NAMES[i], nil)
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(70, 75, 72, 120))
            nvgText(vg, textX, textCY2 + 2, DAILY_DUNGEON_DESCS[i], nil)

            -- 右侧已完成标记 (带勾号底板)
            local badgeX = 16 + cardW - 90
            local badgeY = textCY2 - 16
            local badgeW = 78
            local badgeH = 32
            nvgBeginPath(vg); nvgRoundedRect(vg, badgeX, badgeY, badgeW, badgeH, 4)
            nvgFillColor(vg, nvgRGBA(25, 55, 35, 180)); nvgFill(vg)
            nvgBeginPath(vg); nvgRoundedRect(vg, badgeX, badgeY, badgeW, badgeH, 4)
            nvgStrokeColor(vg, nvgRGBA(60, 140, 80, 100)); nvgStrokeWidth(vg, 0.8); nvgStroke(vg)
            nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(80, 200, 110, 180))
            nvgText(vg, badgeX + badgeW / 2, badgeY + badgeH / 2, "已完成", nil)

            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(60, 65, 60, 90))
            nvgText(vg, textX, textCY2 + 26, "明日0点重置", nil)
        else
            -- 可用 - 高对比度
            nvgFontSize(vg, 27)
            -- 名称 (带色彩投影)
            nvgFillColor(vg, nvgRGBA(dc[1] * 0.3, dc[2] * 0.3, dc[3] * 0.3, 100))
            nvgText(vg, textX + 1, textCY2 - 25 + 1, DAILY_DUNGEON_NAMES[i], nil)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 250))
            nvgText(vg, textX, textCY2 - 25, DAILY_DUNGEON_NAMES[i], nil)

            -- 描述
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(180, 175, 165, 190))
            nvgText(vg, textX, textCY2 + 0, DAILY_DUNGEON_DESCS[i], nil)

            -- 副本特定信息 (突出显示)
            nvgFontSize(vg, 20)
            if i == 1 then
                local slotName = EQUIP_SLOT_NAMES[dailyDungeonState.todaySlot] or "?"
                nvgFillColor(vg, nvgRGBA(80, 220, 160, 220))
                nvgText(vg, textX, textCY2 + 24, "今日部位: " .. slotName, nil)
            elseif i == 2 then
                local setData = EQUIPMENT_SETS[dailyDungeonState.selectedSet]
                local setName = setData and setData.name or "?"
                nvgFillColor(vg, nvgRGBA(100, 170, 255, 220))
                nvgText(vg, textX, textCY2 + 24, "当前套装: " .. setName, nil)
            else
                nvgFillColor(vg, nvgRGBA(220, 130, 255, 220))
                nvgText(vg, textX, textCY2 + 24, "高品级爆率×10", nil)
            end

            -- 右侧进入箭头 (脉冲动画)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 30)
            local aPulse = 0.4 + 0.6 * math.sin(t * 3.0 + i * 1.1)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(180 * aPulse)))
            nvgText(vg, 16 + cardW - 12, textCY2, ">", nil)
        end
    end

    -- 底部提示条 (磨砂底板)
    local tipBarH = 36
    local tipBarY = H - tipBarH - 6
    nvgBeginPath(vg); nvgRoundedRect(vg, 12, tipBarY, W - 24, tipBarH, 5)
    nvgFillColor(vg, nvgRGBA(8, 14, 12, 180)); nvgFill(vg)
    nvgBeginPath(vg); nvgRoundedRect(vg, 12, tipBarY, W - 24, tipBarH, 5)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 70, 50)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)
    nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(130, 160, 140, 150))
    nvgText(vg, cx, tipBarY + tipBarH / 2, "每日0点重置  |  5×5探索地图  |  必掉装备", nil)

    -- ===========================
    -- 确认弹窗 (重制版)
    -- ===========================
    if dailyDungeonState.showConfirm then
        local di = dailyDungeonState.selectedDungeon
        if di and di >= 1 and di <= 3 then
            local dc = DAILY_DUNGEON_COLORS[di]
            local popW = W - 28
            local popH = (di == 2) and 320 or 230
            local popX = 14
            local popY = H / 2 - popH / 2

            -- 全屏遮罩
            nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 170)); nvgFill(vg)

            -- 弹窗底板 (暗色渐变 + 双层边框)
            nvgBeginPath(vg); nvgRoundedRect(vg, popX, popY, popW, popH, 8)
            local popBg = nvgLinearGradient(vg, popX, popY, popX, popY + popH,
                nvgRGBA(22, 32, 28, 250), nvgRGBA(12, 16, 14, 250))
            nvgFillPaint(vg, popBg); nvgFill(vg)
            -- 外边框
            nvgBeginPath(vg); nvgRoundedRect(vg, popX, popY, popW, popH, 8)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 120)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            -- 内边框 (更暗)
            nvgBeginPath(vg); nvgRoundedRect(vg, popX + 3, popY + 3, popW - 6, popH - 6, 6)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 30)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)

            -- 顶部彩色装饰横条
            nvgBeginPath(vg); nvgRoundedRect(vg, popX + 40, popY + 1, popW - 80, 2, 1)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 100)); nvgFill(vg)

            -- 标题 (带投影, 高品质)
            nvgFontSize(vg, 32); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(dc[1] * 0.3, dc[2] * 0.3, dc[3] * 0.3, 100))
            nvgText(vg, cx + 1, popY + 30 + 1, DAILY_DUNGEON_NAMES[di], nil)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 250))
            nvgText(vg, cx, popY + 30, DAILY_DUNGEON_NAMES[di], nil)

            -- 描述
            nvgFontSize(vg, 21); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 175, 165, 200))
            nvgText(vg, cx, popY + 58, DAILY_DUNGEON_DESCS[di], nil)

            -- 分隔细线
            nvgBeginPath(vg); nvgMoveTo(vg, popX + 20, popY + 72); nvgLineTo(vg, popX + popW - 20, popY + 72)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 40)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)

            -- 副本特定信息
            nvgFontSize(vg, 24)
            local infoY = popY + 92
            if di == 1 then
                local slotName = EQUIP_SLOT_NAMES[dailyDungeonState.todaySlot] or "?"
                nvgFillColor(vg, nvgRGBA(80, 220, 160, 230))
                nvgText(vg, cx, infoY, "今日锻造部位: " .. slotName, nil)
            elseif di == 2 then
                -- 套装选择区
                nvgFillColor(vg, nvgRGBA(140, 170, 210, 190))
                nvgText(vg, cx, infoY, "选择猎取套装:", nil)
                -- 7个套装选择按钮 (两行, 重制版)
                local setBtnW = (popW - 48) / 4
                local setBtnH = 36
                local setStartX = popX + 14
                local setStartY = infoY + 22
                dailyDungeonSetBtnRects = {}
                for si = 1, 7 do
                    local row = (si <= 4) and 0 or 1
                    local col = (si <= 4) and (si - 1) or (si - 5)
                    local sx = setStartX + col * (setBtnW + 5)
                    local sy = setStartY + row * (setBtnH + 7)
                    local isSelected = (dailyDungeonState.selectedSet == si)
                    local setData = EQUIPMENT_SETS[si]
                    local sc = setData and setData.color or {180,180,180}

                    dailyDungeonSetBtnRects[si] = { x = sx, y = sy, w = setBtnW, h = setBtnH }

                    -- 按钮背景
                    nvgBeginPath(vg); nvgRoundedRect(vg, sx, sy, setBtnW, setBtnH, 5)
                    if isSelected then
                        local selBg = nvgLinearGradient(vg, sx, sy, sx, sy + setBtnH,
                            nvgRGBA(sc[1] * 0.3, sc[2] * 0.3, sc[3] * 0.3, 230),
                            nvgRGBA(sc[1] * 0.15, sc[2] * 0.15, sc[3] * 0.15, 230))
                        nvgFillPaint(vg, selBg)
                    else
                        nvgFillColor(vg, nvgRGBA(20, 24, 22, 210))
                    end
                    nvgFill(vg)
                    -- 按钮边框
                    nvgBeginPath(vg); nvgRoundedRect(vg, sx, sy, setBtnW, setBtnH, 5)
                    if isSelected then
                        local sPulse = 0.6 + 0.4 * math.sin(t * 2.5 + si)
                        nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], math.floor(200 * sPulse)))
                        nvgStrokeWidth(vg, 1.5)
                    else
                        nvgStrokeColor(vg, nvgRGBA(60, 65, 60, 80))
                        nvgStrokeWidth(vg, 0.5)
                    end
                    nvgStroke(vg)

                    nvgFontSize(vg, 17); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    local sName = setData and setData.name or ("套装" .. si)
                    if #sName > 12 then sName = string.sub(sName, 1, 12) end
                    if isSelected then
                        nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 250))
                    else
                        nvgFillColor(vg, nvgRGBA(130, 135, 130, 160))
                    end
                    nvgText(vg, sx + setBtnW / 2, sy + setBtnH / 2, sName, nil)
                end
            else
                nvgFillColor(vg, nvgRGBA(220, 130, 255, 230))
                nvgText(vg, cx, infoY, "将品及以上爆率×10", nil)
            end

            -- 地图信息
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(110, 120, 110, 140))
            nvgText(vg, cx, popY + popH - 78, "5×5 探索地图", nil)

            -- 消耗虎符进入按钮 (渐变 + 脉冲边框)
            local confirmBtnW = 210
            local confirmBtnH = 44
            local confirmBtnX = cx - confirmBtnW / 2
            local confirmBtnY = popY + popH - 54
            local canAfford = (playerInfo.jade or 0) >= 300
            local btnPulse = 0.7 + 0.3 * math.sin(t * 2.5)
            nvgBeginPath(vg); nvgRoundedRect(vg, confirmBtnX, confirmBtnY, confirmBtnW, confirmBtnH, 6)
            if canAfford then
                local cBtnBg = nvgLinearGradient(vg, confirmBtnX, confirmBtnY, confirmBtnX, confirmBtnY + confirmBtnH,
                    nvgRGBA(dc[1] * 0.45, dc[2] * 0.45, dc[3] * 0.45, 240),
                    nvgRGBA(dc[1] * 0.2, dc[2] * 0.2, dc[3] * 0.2, 240))
                nvgFillPaint(vg, cBtnBg); nvgFill(vg)
            else
                nvgFillColor(vg, nvgRGBA(60, 60, 60, 200)); nvgFill(vg)
            end
            nvgBeginPath(vg); nvgRoundedRect(vg, confirmBtnX, confirmBtnY, confirmBtnW, confirmBtnH, 6)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], canAfford and math.floor(180 * btnPulse) or 60))
            nvgStrokeWidth(vg, 1.3); nvgStroke(vg)
            nvgFontSize(vg, 26); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local btnLabel = "300虎符进入"
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
            nvgText(vg, cx + 1, confirmBtnY + confirmBtnH / 2 + 1, btnLabel, nil)
            nvgFillColor(vg, canAfford and nvgRGBA(245, 245, 240, 245) or nvgRGBA(160, 160, 160, 180))
            nvgText(vg, cx, confirmBtnY + confirmBtnH / 2, btnLabel, nil)
            dailyDungeonConfirmBtnRect = { x = confirmBtnX, y = confirmBtnY, w = confirmBtnW, h = confirmBtnH }

            -- 关闭按钮 (暗色圆形)
            local closeBtnW = 30
            local closeBtnX = popX + popW - closeBtnW - 6
            local closeBtnY3 = popY + 6
            nvgBeginPath(vg); nvgCircle(vg, closeBtnX + closeBtnW/2, closeBtnY3 + closeBtnW/2, closeBtnW/2)
            nvgFillColor(vg, nvgRGBA(18, 24, 20, 210)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 80)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 24); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 210, 200, 200))
            nvgText(vg, closeBtnX + closeBtnW/2, closeBtnY3 + closeBtnW/2, "×", nil)
            dailyDungeonCloseRect = { x = closeBtnX, y = closeBtnY3, w = closeBtnW, h = closeBtnW }
        end
    end
end


-- ============================================================================
-- 探索资源副本 选择界面
-- ============================================================================
function DrawResourceDungeonScreen()
    if gameState.phase ~= "RESOURCE_DUNGEON" then return end
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local t = gameState.gameTime
    local rdCfg = GameConfig.RESOURCE_DUNGEON

    -- 背景 (复用每日副本背景 + 蓝绿色调叠加)
    DrawBgImage(IMG.dailyDungeonBg, W, H, 572, 1025)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 15, 20, 80)); nvgFill(vg)
    -- 顶部暗化渐变
    local topGrad = nvgLinearGradient(vg, 0, 0, 0, H * 0.18,
        nvgRGBA(4, 18, 22, 200), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H * 0.18)
    nvgFillPaint(vg, topGrad); nvgFill(vg)
    -- 底部暗雾
    local botGrad = nvgLinearGradient(vg, 0, H * 0.72, 0, H,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(4, 18, 16, 180))
    nvgBeginPath(vg); nvgRect(vg, 0, H * 0.72, W, H * 0.28)
    nvgFillPaint(vg, botGrad); nvgFill(vg)

    nvgFontFaceId(vg, GetMainFont())

    -- 顶部返回按钮
    local topY = 14
    local backW, backH = 100, 38
    nvgBeginPath(vg); nvgRoundedRect(vg, 14, topY, backW, backH, 6)
    nvgFillColor(vg, nvgRGBA(10, 22, 20, 210)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 180, 140, 130)); nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    nvgFontSize(vg, 26); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(5, 5, 12, 95))
    nvgText(vg, 14 + backW/2 + 1, topY + backH/2 + 1, "< 返回", nil)
    DrawWhiteInkText(14 + backW/2, topY + backH/2, "< 返回")
    resourceDungeonBackRect = { x = 14, y = topY, w = backW, h = backH }

    -- 标题
    local titleCY = topY + backH / 2
    nvgFontSize(vg, 38); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(10, 50, 40, 130))
    nvgText(vg, cx + 2, titleCY + 2, "探索资源副本", nil)
    nvgFillColor(vg, nvgRGBA(40, 200, 160, 180))
    nvgText(vg, cx + 1, titleCY + 1, "探索资源副本", nil)
    DrawWhiteInkText(cx, titleCY, "探索资源副本")

    -- 副标题 (完成进度)
    local doneCount = 0
    for i = 1, 3 do if resourceDungeonState.completed[i] then doneCount = doneCount + 1 end end
    nvgFontSize(vg, 27)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgText(vg, cx + 1, titleCY + 23, "- 今日探索 " .. doneCount .. "/3 -", nil)
    DrawWhiteInkText(cx, titleCY + 22, "- 今日探索 " .. doneCount .. "/3 -")

    -- 装饰分隔线
    local sepY = titleCY + 38
    local sepHW = 130
    local sepGradL = nvgLinearGradient(vg, cx - sepHW, sepY, cx - 8, sepY,
        nvgRGBA(40, 200, 160, 0), nvgRGBA(60, 220, 170, 160))
    nvgBeginPath(vg); nvgMoveTo(vg, cx - sepHW, sepY); nvgLineTo(vg, cx - 8, sepY)
    nvgStrokeWidth(vg, 1.2); nvgStrokePaint(vg, sepGradL); nvgStroke(vg)
    local sepGradR = nvgLinearGradient(vg, cx + 8, sepY, cx + sepHW, sepY,
        nvgRGBA(60, 220, 170, 160), nvgRGBA(40, 200, 160, 0))
    nvgBeginPath(vg); nvgMoveTo(vg, cx + 8, sepY); nvgLineTo(vg, cx + sepHW, sepY)
    nvgStrokeWidth(vg, 1.2); nvgStrokePaint(vg, sepGradR); nvgStroke(vg)
    -- 中心菱形
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, sepY - 4); nvgLineTo(vg, cx + 4, sepY)
    nvgLineTo(vg, cx, sepY + 4); nvgLineTo(vg, cx - 4, sepY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(80, 240, 180, 200)); nvgFill(vg)

    -- 入场提示
    nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 200, 170, 160))
    nvgText(vg, cx, sepY + 16, "门票 " .. rdCfg.entryCost .. " 虎符  |  7×7 遭遇战  |  通关记次", nil)

    -- 副本卡片列表
    local cardW = W - 32
    local cardH = 155
    local cardGap = 14
    local listStartY = sepY + 38
    resourceDungeonCardRects = {}

    local RD_ICONS = { "兵", "印", "残" }

    for i = 1, 3 do
        local typeInfo = rdCfg.types[i]
        local dc = typeInfo.color
        local cy = listStartY + (i - 1) * (cardH + cardGap)
        local isDone = resourceDungeonState.completed[i]

        resourceDungeonCardRects[i] = { x = 16, y = cy, w = cardW, h = cardH }

        -- 卡片背景
        nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, cardW, cardH, 6)
        if isDone then
            nvgFillColor(vg, nvgRGBA(18, 22, 20, 220))
        else
            local cardBg = nvgLinearGradient(vg, 16, cy, 16 + cardW, cy,
                nvgRGBA(14, 22, 20, 220), nvgRGBA(22, 16, 30, 220))
            nvgFillPaint(vg, cardBg)
        end
        nvgFill(vg)

        -- 卡片内部底光
        if not isDone then
            local glowGrad = nvgLinearGradient(vg, 16, cy, 16, cy + cardH,
                nvgRGBA(dc[1], dc[2], dc[3], 15), nvgRGBA(dc[1], dc[2], dc[3], 3))
            nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, cardW, cardH, 6)
            nvgFillPaint(vg, glowGrad); nvgFill(vg)
        end

        -- 左侧竖条装饰
        nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, 4, cardH, 2)
        if isDone then
            nvgFillColor(vg, nvgRGBA(50, 70, 55, 100))
        else
            local barPulse = 0.6 + 0.4 * math.sin(t * 2.0 + i * 1.2)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(220 * barPulse)))
        end
        nvgFill(vg)

        -- 外边框
        nvgBeginPath(vg); nvgRoundedRect(vg, 16, cy, cardW, cardH, 6)
        if isDone then
            nvgStrokeColor(vg, nvgRGBA(50, 60, 50, 70))
        else
            local bPulse = 0.5 + 0.5 * math.sin(t * 1.8 + i * 0.9)
            nvgStrokeColor(vg, nvgRGBA(
                math.floor(dc[1] * 0.5 + 60),
                math.floor(dc[2] * 0.3 + 40),
                math.floor(dc[3] * 0.3 + 40),
                math.floor(100 * bPulse)))
        end
        nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 左侧图标区域
        local iconSize = 60
        local iconX = 28
        local iconY = cy + (cardH - iconSize) / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 10)
        if isDone then
            nvgFillColor(vg, nvgRGBA(22, 28, 24, 210))
        else
            local iconBg = nvgLinearGradient(vg, iconX, iconY, iconX, iconY + iconSize,
                nvgRGBA(dc[1] * 0.18, dc[2] * 0.18, dc[3] * 0.18, 220),
                nvgRGBA(dc[1] * 0.06, dc[2] * 0.06, dc[3] * 0.06, 220))
            nvgFillPaint(vg, iconBg)
        end
        nvgFill(vg)
        nvgBeginPath(vg); nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 10)
        if isDone then
            nvgStrokeColor(vg, nvgRGBA(45, 55, 48, 60))
        else
            local iPulse = 0.6 + 0.4 * math.sin(t * 1.5 + i * 2)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(120 * iPulse)))
        end
        nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 图标文字
        nvgFontSize(vg, 32); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isDone then
            nvgFillColor(vg, nvgRGBA(70, 80, 70, 100))
            nvgText(vg, iconX + iconSize / 2, iconY + iconSize / 2, RD_ICONS[i], nil)
        else
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
            nvgText(vg, iconX + iconSize / 2 + 1, iconY + iconSize / 2 + 1, RD_ICONS[i], nil)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, iconX + iconSize / 2, iconY + iconSize / 2, RD_ICONS[i], nil)
        end

        -- 右侧文字区域
        local textX = iconX + iconSize + 14
        local textCY2 = cy + cardH / 2
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        if isDone then
            nvgFontSize(vg, 27)
            nvgFillColor(vg, nvgRGBA(90, 100, 95, 140))
            nvgText(vg, textX, textCY2 - 28, typeInfo.name, nil)
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(70, 75, 72, 120))
            nvgText(vg, textX, textCY2 - 4, typeInfo.desc, nil)

            -- 已完成标记
            local badgeX = 16 + cardW - 90
            local badgeY = textCY2 - 16
            local badgeW = 78
            local badgeH = 32
            nvgBeginPath(vg); nvgRoundedRect(vg, badgeX, badgeY, badgeW, badgeH, 4)
            nvgFillColor(vg, nvgRGBA(25, 55, 35, 180)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(60, 140, 80, 100)); nvgStrokeWidth(vg, 0.8); nvgStroke(vg)
            nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(80, 200, 110, 180))
            nvgText(vg, badgeX + badgeW / 2, badgeY + badgeH / 2, "已完成", nil)

            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(60, 65, 60, 90))
            nvgText(vg, textX, textCY2 + 20, "明日0点重置", nil)
        else
            -- 名称
            nvgFontSize(vg, 27)
            nvgFillColor(vg, nvgRGBA(dc[1] * 0.3, dc[2] * 0.3, dc[3] * 0.3, 100))
            nvgText(vg, textX + 1, textCY2 - 30 + 1, typeInfo.name, nil)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 250))
            nvgText(vg, textX, textCY2 - 30, typeInfo.name, nil)

            -- 描述
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(180, 175, 165, 190))
            nvgText(vg, textX, textCY2 - 6, typeInfo.desc, nil)

            -- 产出信息
            nvgFontSize(vg, 18)
            local prodInfo = ""
            if typeInfo.id == "equip" then
                prodInfo = "装备爆率+" .. math.floor(typeInfo.dropRateBonus * 100) .. "%  最高帝品"
            elseif typeInfo.id == "seal" then
                prodInfo = "碎片×" .. string.format("%.0f", typeInfo.fragMultiplier) .. "  最高王品"
            else
                prodInfo = "碎片×" .. string.format("%.0f", typeInfo.fragMultiplier) .. "  最高将品"
            end
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 200))
            nvgText(vg, textX, textCY2 + 16, prodInfo, nil)

            -- 门票费用
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 180))
            nvgText(vg, textX, textCY2 + 38, "门票: " .. rdCfg.entryCost .. " 虎符", nil)

            -- 右侧进入箭头
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 30)
            local aPulse = 0.4 + 0.6 * math.sin(t * 3.0 + i * 1.1)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(180 * aPulse)))
            nvgText(vg, 16 + cardW - 12, textCY2, ">", nil)
        end
    end

    -- 底部提示条
    local tipBarH = 36
    local tipBarY = H - tipBarH - 6
    nvgBeginPath(vg); nvgRoundedRect(vg, 12, tipBarY, W - 24, tipBarH, 5)
    nvgFillColor(vg, nvgRGBA(8, 14, 12, 180)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 130, 100, 50)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)
    nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(130, 180, 155, 150))
    nvgText(vg, cx, tipBarY + tipBarH / 2, "每日0点重置  |  7×7遭遇战  |  通关才算完成", nil)

    -- 当前虎符显示
    nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 200))
    nvgText(vg, W - 16, topY + backH / 2, "虎符: " .. FormatJade(playerInfo.jade), nil)

    -- ===========================
    -- 确认弹窗
    -- ===========================
    if resourceDungeonState.showConfirm then
        local ti = resourceDungeonState.selectedType
        if ti and ti >= 1 and ti <= 3 then
            local typeInfo = rdCfg.types[ti]
            local dc = typeInfo.color
            local popW = W - 28
            local popH = 260
            local popX = 14
            local popY = H / 2 - popH / 2

            -- 全屏遮罩
            nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 170)); nvgFill(vg)

            -- 弹窗底板
            nvgBeginPath(vg); nvgRoundedRect(vg, popX, popY, popW, popH, 8)
            local popBg = nvgLinearGradient(vg, popX, popY, popX, popY + popH,
                nvgRGBA(22, 36, 32, 250), nvgRGBA(12, 18, 16, 250))
            nvgFillPaint(vg, popBg); nvgFill(vg)
            nvgBeginPath(vg); nvgRoundedRect(vg, popX, popY, popW, popH, 8)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 120)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            nvgBeginPath(vg); nvgRoundedRect(vg, popX + 3, popY + 3, popW - 6, popH - 6, 6)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 30)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)

            -- 顶部彩色横条
            nvgBeginPath(vg); nvgRoundedRect(vg, popX + 40, popY + 1, popW - 80, 2, 1)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 100)); nvgFill(vg)

            -- 标题
            nvgFontSize(vg, 32); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(dc[1] * 0.3, dc[2] * 0.3, dc[3] * 0.3, 100))
            nvgText(vg, cx + 1, popY + 30 + 1, typeInfo.name, nil)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 250))
            nvgText(vg, cx, popY + 30, typeInfo.name, nil)

            -- 描述
            nvgFontSize(vg, 21); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 175, 165, 200))
            nvgText(vg, cx, popY + 58, typeInfo.desc, nil)

            -- 分隔细线
            nvgBeginPath(vg); nvgMoveTo(vg, popX + 20, popY + 72); nvgLineTo(vg, popX + popW - 20, popY + 72)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 40)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)

            -- 副本信息
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 220))
            local infoStr = ""
            if typeInfo.id == "equip" then
                infoStr = "装备爆率+" .. math.floor(typeInfo.dropRateBonus * 100) .. "% | 最高帝品"
            elseif typeInfo.id == "seal" then
                infoStr = "碎片产出×" .. string.format("%.0f", typeInfo.fragMultiplier) .. " | 最高王品"
            else
                infoStr = "碎片产出×" .. string.format("%.0f", typeInfo.fragMultiplier) .. " | 最高将品"
            end
            nvgText(vg, cx, popY + 92, infoStr, nil)

            -- 地图与模式信息
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(140, 180, 160, 170))
            nvgText(vg, cx, popY + 118, "7×7 遭遇战模式 | 难度动态匹配", nil)

            -- 门票费用
            nvgFontSize(vg, 24)
            local hasEnough = playerInfo.jade >= rdCfg.entryCost
            if hasEnough then
                nvgFillColor(vg, nvgRGBA(255, 220, 100, 240))
            else
                nvgFillColor(vg, nvgRGBA(255, 80, 80, 240))
            end
            nvgText(vg, cx, popY + 150, "门票: " .. rdCfg.entryCost .. " 虎符", nil)
            if not hasEnough then
                nvgFontSize(vg, 18)
                nvgFillColor(vg, nvgRGBA(255, 100, 80, 180))
                nvgText(vg, cx, popY + 172, "(虎符不足: 当前 " .. FormatJade(playerInfo.jade) .. ")", nil)
            end

            -- 进入按钮
            local confirmBtnW = 210
            local confirmBtnH = 44
            local confirmBtnX = cx - confirmBtnW / 2
            local confirmBtnY = popY + popH - 54
            local btnPulse = 0.7 + 0.3 * math.sin(t * 2.5)
            nvgBeginPath(vg); nvgRoundedRect(vg, confirmBtnX, confirmBtnY, confirmBtnW, confirmBtnH, 6)
            local cBtnBg = nvgLinearGradient(vg, confirmBtnX, confirmBtnY, confirmBtnX, confirmBtnY + confirmBtnH,
                nvgRGBA(dc[1] * 0.45, dc[2] * 0.45, dc[3] * 0.45, 240),
                nvgRGBA(dc[1] * 0.2, dc[2] * 0.2, dc[3] * 0.2, 240))
            nvgFillPaint(vg, cBtnBg); nvgFill(vg)
            nvgBeginPath(vg); nvgRoundedRect(vg, confirmBtnX, confirmBtnY, confirmBtnW, confirmBtnH, 6)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], math.floor(180 * btnPulse)))
            nvgStrokeWidth(vg, 1.3); nvgStroke(vg)
            nvgFontSize(vg, 26); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
            nvgText(vg, cx + 1, confirmBtnY + confirmBtnH / 2 + 1, "消耗虎符进入", nil)
            nvgFillColor(vg, nvgRGBA(245, 245, 240, 245))
            nvgText(vg, cx, confirmBtnY + confirmBtnH / 2, "消耗虎符进入", nil)

            resourceDungeonConfirmRect = {
                enter = { x = confirmBtnX, y = confirmBtnY, w = confirmBtnW, h = confirmBtnH },
            }

            -- 关闭按钮
            local closeBtnW = 30
            local closeBtnX = popX + popW - closeBtnW - 6
            local closeBtnY3 = popY + 6
            nvgBeginPath(vg); nvgCircle(vg, closeBtnX + closeBtnW/2, closeBtnY3 + closeBtnW/2, closeBtnW/2)
            nvgFillColor(vg, nvgRGBA(18, 24, 20, 210)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 80)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 24); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 210, 200, 200))
            nvgText(vg, closeBtnX + closeBtnW/2, closeBtnY3 + closeBtnW/2, "×", nil)
            resourceDungeonConfirmRect.close = { x = closeBtnX, y = closeBtnY3, w = closeBtnW, h = closeBtnW }
        end
    end
end


-- ============================================================================
-- 战令通行证 界面
-- ============================================================================
