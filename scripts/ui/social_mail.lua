-- ui/social_mail.lua - 三国武灵录 (从 social.lua 拆分)

-- ============================================================================
-- 贡献榜详情独立界面（与战力排行榜同款样式，显示次数）
-- ============================================================================

function DrawContribRankScreen()
    local W = DESIGN_W
    local H = DESIGN_H
    local cx = W / 2
    local t = menuAnimTimer or 0

    -- 1. 统一菜单背景
    DrawMenuBg(W, H)
    nvgFontFaceId(vg, GetMainFont())

    -- 2. 返回按钮
    local backW, backH = 100, 44
    local backX, backY = 10, 10
    nvgBeginPath(vg); nvgRoundedRect(vg, backX, backY, backW, backH, 6)
    nvgFillColor(vg, nvgRGBA(30, 35, 50, 220)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(backX + backW / 2, backY + backH / 2, "< 返回")
    menuBtnRects.contribRankBack = { x = backX, y = backY, w = backW, h = backH }

    -- 3. 标题
    nvgFontSize(vg, 39)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, 32, "贡献排行榜")

    nvgFontSize(vg, 25)
    DrawWhiteInkText(cx, 56, "感谢每一次支持")

    -- 4. 排行列表区域
    local listTop = 76
    local listBottom = H - 12
    local listH = listBottom - listTop
    local secPad = 16
    local secW = W - secPad * 2

    local contribData = welfareState.contribRank
    local contribCount = contribData and #contribData or 0
    local rowH = 56
    local headerH = 44
    local contentH = math.max(listH, headerH + contribCount * rowH + 20)

    -- 滚动偏移
    local scrollOff = welfareState.contribDetailScroll.offset
    local minScroll = math.min(0, listH - contentH)
    scrollOff = math.max(minScroll, math.min(0, scrollOff))
    welfareState.contribDetailScroll.offset = scrollOff

    nvgSave(vg)
    nvgScissor(vg, 0, listTop, W, listH)

    local baseY = listTop + scrollOff

    -- 底板（暖色半透明，暗黑地牢风格）
    nvgBeginPath(vg); nvgRoundedRect(vg, secPad, baseY, secW, contentH, 10)
    nvgFillColor(vg, nvgRGBA(15, 12, 8, 190)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 80)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

    -- 表头
    local hy = baseY + 8
    nvgBeginPath(vg); nvgRoundedRect(vg, secPad + 6, hy, secW - 12, headerH - 4, 6)
    local headerGrad = nvgLinearGradient(vg, secPad, hy, secPad + secW, hy,
        nvgRGBA(80, 60, 30, 100), nvgRGBA(60, 45, 20, 60))
    nvgFillPaint(vg, headerGrad); nvgFill(vg)
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 140, 200))
    nvgText(vg, secPad + 30, hy + headerH / 2 - 2, "排名", nil)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, secPad + 60, hy + headerH / 2 - 2, "道号", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, secPad + secW - 16, hy + headerH / 2 - 2, "次数", nil)

    -- 表头分隔线
    nvgBeginPath(vg); nvgMoveTo(vg, secPad + 10, hy + headerH - 2); nvgLineTo(vg, secPad + secW - 10, hy + headerH - 2)
    nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 60)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    if welfareState.contribLoading and not welfareState.contribLoaded then
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, baseY + listH / 2, "加载中...")
    elseif contribCount == 0 then
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, baseY + listH / 2, "暂无数据，快去看广告上榜吧！")
    else
        local medals = {"[1]", "[2]", "[3]"}
        local rankColors = {
            nvgRGBA(255, 215, 80, 35),   -- 第1名 金
            nvgRGBA(210, 210, 220, 25),  -- 第2名 银
            nvgRGBA(200, 160, 90, 20),   -- 第3名 铜
        }
        for i, entry in ipairs(contribData) do
            local ry = baseY + headerH + 8 + (i - 1) * rowH
            -- 前3名暖金高亮底色
            if i <= 3 then
                nvgBeginPath(vg); nvgRoundedRect(vg, secPad + 6, ry + 2, secW - 12, rowH - 4, 6)
                nvgFillColor(vg, rankColors[i]); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(180, 145, 60, 40)); nvgStrokeWidth(vg, 0.5); nvgStroke(vg)
            elseif i % 2 == 0 then
                nvgBeginPath(vg); nvgRoundedRect(vg, secPad + 6, ry + 2, secW - 12, rowH - 4, 4)
                nvgFillColor(vg, nvgRGBA(255, 240, 200, 6)); nvgFill(vg)
            end

            -- 排名
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if i <= 3 then
                nvgFontSize(vg, 28)
                nvgText(vg, secPad + 30, ry + rowH / 2, medals[i], nil)
            else
                nvgFontSize(vg, 22)
                nvgFillColor(vg, nvgRGBA(180, 165, 130, 200))
                nvgText(vg, secPad + 30, ry + rowH / 2, "#" .. i, nil)
            end

            -- 道号
            nvgFontSize(vg, 24)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            if i <= 3 then
                nvgFillColor(vg, nvgRGBA(255, 235, 175, 240))
            else
                nvgFillColor(vg, nvgRGBA(220, 210, 190, 220))
            end
            nvgText(vg, secPad + 60, ry + rowH / 2, entry.name, nil)

            -- 次数（暖金色）
            nvgFontSize(vg, 24)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if i <= 3 then
                nvgFillColor(vg, nvgRGBA(255, 200, 80, 240))
            else
                nvgFillColor(vg, nvgRGBA(220, 180, 100, 210))
            end
            nvgText(vg, secPad + secW - 16, ry + rowH / 2, tostring(entry.count) .. " 次", nil)

            -- 行间分隔线
            if i < contribCount then
                nvgBeginPath(vg)
                nvgMoveTo(vg, secPad + 20, ry + rowH)
                nvgLineTo(vg, secPad + secW - 20, ry + rowH)
                nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 25))
                nvgStrokeWidth(vg, 0.5); nvgStroke(vg)
            end
        end
    end

    nvgRestore(vg)

    -- 幽冥粒子
    for i = 1, 6 do
        local px = W * (0.1 + 0.8 * ((i * 131 + math.floor(t * 16)) % 100) / 100)
        local py = H * (0.04 + 0.12 * math.sin(t * 0.5 + i * 1.5))
        local pr = 1 + math.sin(t * 1.8 + i) * 0.5
        local pa = math.floor(22 + 16 * math.sin(t * 1.3 + i * 0.9))
        nvgBeginPath(vg); nvgCircle(vg, px, py, pr)
        nvgFillColor(vg, nvgRGBA(220, 195, 140, pa)); nvgFill(vg)
    end
end


-- ============================================================================
-- 战力排行榜独立界面
-- ============================================================================

function DrawMailBoxScreen()
    local W, H = DESIGN_W, DESIGN_H
    local cx = W / 2
    local t = menuAnimTimer or 0
    local ms = welfareState.mail

    -- 1. 背景
    DrawMenuBg(W, H)
    nvgFontFaceId(vg, GetMainFont())

    -- 2. 返回按钮
    local backW, backH = 100, 44
    local backX, backY = 10, 10
    nvgBeginPath(vg); nvgRoundedRect(vg, backX, backY, backW, backH, 6)
    nvgFillColor(vg, nvgRGBA(30, 35, 50, 220)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 45, 55, 160)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
    nvgFontSize(vg, 29)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(backX + backW / 2, backY + backH / 2, "< 返回")
    menuBtnRects.mailBack = { x = backX, y = backY, w = backW, h = backH }

    -- 3. 标题 + UID显示
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawWhiteInkText(cx, 32, "邮件")

    -- 右上角显示玩家UID (方便管理员确认身份)
    local myUid = rawget(_G, "clientCloud") and clientCloud.userId or 0
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 100, 110, 140))
    nvgText(vg, W - 10, 6, "UID:" .. tostring(myUid), nil)
    -- 管理员标识
    if CloudManager.IsAdmin() then
        nvgFillColor(vg, nvgRGBA(255, 200, 60, 200))
        nvgText(vg, W - 10, 20, "[管理员]", nil)
    end
    -- 免广告状态
    if playerInfo.ad_free then
        nvgFillColor(vg, nvgRGBA(100, 255, 150, 180))
        nvgText(vg, W - 10, CloudManager.IsAdmin() and 34 or 20, "[免广告]", nil)
    end

    -- 4. Tab 栏: 系统邮件 / 玩家邮件 (非管理员只显示系统邮件)
    local pad = 14
    local tabY = 56
    local tabH = 36
    local isMailAdmin = CloudManager.IsAdmin()
    local tabs
    if isMailAdmin then
        tabs = { { id = "system", label = "系统邮件" }, { id = "cloud", label = "玩家邮件" } }
    else
        tabs = { { id = "system", label = "邮件" } }
        -- 非管理员强制切到 system tab
        if ms.tab == "cloud" then ms.tab = "system" end
    end
    -- 云邮件未读数
    local cloudUnread = 0
    for _, cm in ipairs(CloudManager._mailInbox or {}) do
        if not CloudManager.IsMailClaimed(cm.id) and #(cm.rewards or {}) > 0 then
            cloudUnread = cloudUnread + 1
        end
    end
    local tabW = (W - pad * 2) / #tabs
    for i, tb in ipairs(tabs) do
        local tx = pad + (i - 1) * tabW
        local sel = (ms.tab == tb.id)
        nvgBeginPath(vg); nvgRoundedRect(vg, tx + 2, tabY, tabW - 4, tabH, 6)
        nvgFillColor(vg, sel and nvgRGBA(90, 60, 30, 220) or nvgRGBA(30, 30, 40, 180)); nvgFill(vg)
        if sel then nvgStrokeColor(vg, nvgRGBA(255, 180, 60, 180)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg) end
        nvgFontSize(vg, 18); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, sel and nvgRGBA(255, 220, 100, 255) or nvgRGBA(180, 180, 180, 200))
        local lbl = tb.label
        if tb.id == "cloud" and cloudUnread > 0 then lbl = lbl .. "(" .. cloudUnread .. ")" end
        -- 非管理员在邮件Tab上显示未读云邮件数
        if not isMailAdmin and tb.id == "system" and cloudUnread > 0 then lbl = lbl .. "(" .. cloudUnread .. ")" end
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, lbl, nil)
        menuBtnRects["mailTab_" .. tb.id] = { x = tx + 2, y = tabY, w = tabW - 4, h = tabH }
    end

    local listTop = tabY + tabH + 8
    local listBottom = H - 12
    local listH = listBottom - listTop
    local cardGap = 10

    -- =============== 系统邮件 Tab ===============
    if ms.tab == "system" then
        local mailCardH = 220
        local cloudCardH = 130  -- 云邮件卡片高度
        ms.btnRects = {}
        if not isMailAdmin then ms.cloudBtnRects = {} end  -- 非管理员也需要云邮件领取按钮

        nvgSave(vg)
        nvgScissor(vg, 0, listTop, W, listH)

        local scrollOff = ms.scroll and ms.scroll.offset or 0
        local mailCount = #welfareState.mailDefs
        local inbox = not isMailAdmin and (CloudManager._mailInbox or {}) or {}
        local contentH = mailCount * (mailCardH + cardGap) - cardGap
        -- 非管理员: 系统邮件底部追加云邮件
        if #inbox > 0 then
            contentH = contentH + (mailCount > 0 and cardGap or 0) + #inbox * (cloudCardH + cardGap) - cardGap
        end
        local maxScroll = math.max(0, contentH - listH)
        if ms.scroll then
            if ms.scroll.offset > maxScroll then ms.scroll.offset = maxScroll; ms.scroll.vel = 0 end
            if ms.scroll.offset < 0 then ms.scroll.offset = 0; ms.scroll.vel = 0 end
            scrollOff = ms.scroll.offset
        end

        for i, mail in ipairs(welfareState.mailDefs) do
            local isClaimed = ms.claimed[mail.id] == true
            local cardY = listTop + (i - 1) * (mailCardH + cardGap) - scrollOff
            local cardX = pad
            local cardW = W - pad * 2

            nvgBeginPath(vg); nvgRoundedRect(vg, cardX, cardY, cardW, mailCardH, 10)
            if isClaimed then
                nvgFillColor(vg, nvgRGBA(20, 20, 25, 180)); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(60, 60, 70, 100)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            else
                local glow = 0.8 + 0.2 * math.sin(t * 2.5)
                nvgFillColor(vg, nvgRGBA(30, 18, 10, math.floor(210 * glow))); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(255, 180, 80, math.floor(140 * glow))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            end

            nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(140, 130, 110, isClaimed and 120 or 200))
            nvgText(vg, cardX + 12, cardY + 8, "来自: " .. mail.sender, nil)

            nvgFontSize(vg, 24); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if isClaimed then
                nvgFillColor(vg, nvgRGBA(120, 120, 120, 160))
                nvgText(vg, cardX + 12, cardY + 26, mail.title, nil)
            else
                DrawWhiteInkText(cardX + 12, cardY + 26, mail.title)
            end

            nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(190, 180, 170, isClaimed and 100 or 210))
            local contentLines = {}
            local lineLen = 22
            local txt = mail.content
            while #txt > 0 do
                local seg, count, pos = "", 0, 1
                while pos <= #txt and count < lineLen do
                    local b = string.byte(txt, pos)
                    if b >= 0xE0 then
                        seg = seg .. txt:sub(pos, pos + 2); pos = pos + 3
                    elseif b >= 0xC0 then
                        seg = seg .. txt:sub(pos, pos + 1); pos = pos + 2
                    else seg = seg .. txt:sub(pos, pos); pos = pos + 1 end
                    count = count + 1
                end
                contentLines[#contentLines + 1] = seg
                txt = txt:sub(pos)
                if #contentLines >= 5 then break end
            end
            for li, line in ipairs(contentLines) do
                nvgText(vg, cardX + 12, cardY + 54 + (li - 1) * 22, line, nil)
            end

            local rwY = cardY + 54 + #contentLines * 22 + 8
            for ri, rw in ipairs(mail.rewards) do
                local rwX = cardX + 12 + (ri - 1) * 160
                nvgFontSize(vg, 16); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(rw.type == "jade" and 255 or 200, rw.type == "jade" and 220 or 160, rw.type == "jade" and 100 or 255, isClaimed and 100 or 230))
                nvgText(vg, rwX, rwY, rw.label, nil)
            end

            local btnW2, btnH2 = 100, 36
            local btnX2 = cardX + cardW - btnW2 - 12
            local btnY2 = cardY + mailCardH - btnH2 - 10
            if isClaimed then
                nvgFontSize(vg, 18); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(100, 100, 100, 140))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "已领取", nil)
            else
                local bp = 0.85 + 0.15 * math.sin(t * 3.5 + i)
                nvgBeginPath(vg); nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 8)
                nvgFillColor(vg, nvgRGBA(180, 80, 30, math.floor(220 * bp))); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(255, 200, 100, math.floor(180 * bp))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
                nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                DrawWhiteInkText(btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "领取")
                ms.btnRects[i] = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
            end

            if not isClaimed then
                local sparkle = math.sin(t * 4.0 + i * 2.0)
                if sparkle > 0.7 then
                    local sa = math.floor((sparkle - 0.7) / 0.3 * 80)
                    nvgBeginPath(vg); nvgRoundedRect(vg, cardX - 1, cardY - 1, cardW + 2, mailCardH + 2, 11)
                    nvgStrokeColor(vg, nvgRGBA(255, 220, 120, sa)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
                end
            end
        end

        -- 非管理员: 系统邮件底部追加云邮件
        if not isMailAdmin and #inbox > 0 then
            local cloudStartY = listTop + mailCount * (mailCardH + cardGap)
            for i, cm in ipairs(inbox) do
                local isClaimed = CloudManager.IsMailClaimed(cm.id)
                local hasRewards = #(cm.rewards or {}) > 0
                local cardY = cloudStartY + (i - 1) * (cloudCardH + cardGap) - scrollOff
                local cardX = pad
                local cardW = W - pad * 2

                nvgBeginPath(vg); nvgRoundedRect(vg, cardX, cardY, cardW, cloudCardH, 10)
                if isClaimed or not hasRewards then
                    nvgFillColor(vg, nvgRGBA(20, 20, 25, 180)); nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(60, 60, 70, 100)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
                else
                    local glow = 0.8 + 0.2 * math.sin(t * 2.5)
                    nvgFillColor(vg, nvgRGBA(20, 25, 40, math.floor(210 * glow))); nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(100, 160, 255, math.floor(140 * glow))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
                end

                -- 广播标识
                if cm.isBroadcast then
                    nvgFontSize(vg, 11); nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(255, 180, 60, 180))
                    nvgText(vg, cardX + cardW - 8, cardY + 4, "[全服]", nil)
                end

                -- 发件人 + 时间
                nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
                nvgText(vg, cardX + 10, cardY + 6, "来自: " .. (cm.fromName or "系统"), nil)
                local timeStr = ""
                if cm.time and cm.time > 0 then
                    local dt2 = os.time() - cm.time
                    if dt2 < 60 then
                        timeStr = "刚刚"
                    elseif dt2 < 3600 then
                        timeStr = math.floor(dt2 / 60) .. "分钟前"
                    elseif dt2 < 86400 then
                        timeStr = math.floor(dt2 / 3600) .. "小时前"
                    else timeStr = math.floor(dt2 / 86400) .. "天前" end
                end
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgText(vg, cardX + cardW - 10, cardY + 6 + (cm.isBroadcast and 14 or 0), timeStr, nil)

                -- 标题
                nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                if isClaimed or not hasRewards then
                    nvgFillColor(vg, nvgRGBA(160, 160, 170, 180))
                else
                    nvgFillColor(vg, nvgRGBA(220, 230, 255, 240))
                end
                nvgText(vg, cardX + 10, cardY + 24, cm.subject or "(无主题)", nil)

                -- 正文预览
                nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(160, 160, 170, isClaimed and 100 or 180))
                local bodyPreview = (cm.body or "")
                if #bodyPreview > 60 then bodyPreview = bodyPreview:sub(1, 60) .. "..." end
                nvgText(vg, cardX + 10, cardY + 48, bodyPreview, nil)

                -- 奖励预览
                if hasRewards then
                    local rwY2 = cardY + 70
                    for ri, rw in ipairs(cm.rewards) do
                        local rwX = cardX + 10 + (ri - 1) * 140
                        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                        if rw.type == "jade" then
                            nvgFillColor(vg, nvgRGBA(255, 220, 100, isClaimed and 80 or 220))
                        elseif rw.type == "ad_free" then
                            nvgFillColor(vg, nvgRGBA(100, 255, 150, isClaimed and 80 or 220))
                        else
                            nvgFillColor(vg, nvgRGBA(200, 160, 255, isClaimed and 80 or 220))
                        end
                        nvgText(vg, rwX, rwY2, rw.label or "", nil)
                    end
                end

                -- 领取按钮 / 已读标签
                local btnW2, btnH2 = 80, 30
                local btnX2 = cardX + cardW - btnW2 - 10
                local btnY2 = cardY + cloudCardH - btnH2 - 8
                if hasRewards then
                    if isClaimed then
                        nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(100, 100, 100, 140))
                        nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "已领取", nil)
                    else
                        local bp = 0.85 + 0.15 * math.sin(t * 3.5 + i)
                        nvgBeginPath(vg); nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 8)
                        nvgFillColor(vg, nvgRGBA(50, 90, 160, math.floor(220 * bp))); nvgFill(vg)
                        nvgStrokeColor(vg, nvgRGBA(100, 180, 255, math.floor(180 * bp))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
                        nvgFontSize(vg, 17); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(220, 240, 255, 240))
                        nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "领取", nil)
                        ms.cloudBtnRects[i] = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
                    end
                end
            end
        end

        if #welfareState.mailDefs == 0 and #inbox == 0 then
            nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 110, 100, 160))
            nvgText(vg, cx, listTop + listH / 2, "暂无邮件", nil)
        end

        nvgRestore(vg)

    -- =============== 玩家邮件 Tab ===============
    elseif ms.tab == "cloud" then
        local mailCardH = 130
        ms.cloudBtnRects = {}
        local inbox = CloudManager._mailInbox or {}

        -- 写信按钮位置 (其他按钮也依赖这些坐标)
        local compBtnW, compBtnH = 90, 32
        local compBtnX = W - pad - compBtnW
        local compBtnY = listTop

        -- 写信按钮 (暂时隐藏, 仅管理员可见)
        menuBtnRects.mailCompose = nil
        if CloudManager.IsAdmin() then
            nvgBeginPath(vg); nvgRoundedRect(vg, compBtnX, compBtnY, compBtnW, compBtnH, 6)
            nvgFillColor(vg, nvgRGBA(50, 90, 140, 220)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 160, 220, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 16); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 230, 255, 240))
            nvgText(vg, compBtnX + compBtnW / 2, compBtnY + compBtnH / 2, "写信", nil)
            menuBtnRects.mailCompose = { x = compBtnX, y = compBtnY, w = compBtnW, h = compBtnH }
        end

        -- 管理员专属: 发奖励邮件按钮 + 玩家管理按钮
        if CloudManager.IsAdmin() then
            local admBtnW, admBtnH = 110, 32
            local admBtnX = compBtnX - admBtnW - 8
            nvgBeginPath(vg); nvgRoundedRect(vg, admBtnX, compBtnY, admBtnW, admBtnH, 6)
            nvgFillColor(vg, nvgRGBA(140, 70, 20, 220)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 180, 60, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 240))
            nvgText(vg, admBtnX + admBtnW / 2, compBtnY + admBtnH / 2, "发奖励邮件", nil)
            menuBtnRects.mailAdminReward = { x = admBtnX, y = compBtnY, w = admBtnW, h = admBtnH }
            -- 玩家管理按钮
            local mgBtnW, mgBtnH = 90, 32
            local mgBtnX = admBtnX - mgBtnW - 8
            nvgBeginPath(vg); nvgRoundedRect(vg, mgBtnX, compBtnY, mgBtnW, mgBtnH, 6)
            nvgFillColor(vg, nvgRGBA(100, 30, 30, 220)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(220, 80, 80, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 180, 180, 240))
            nvgText(vg, mgBtnX + mgBtnW / 2, compBtnY + mgBtnH / 2, "玩家管理", nil)
            menuBtnRects.mailAdminManage = { x = mgBtnX, y = compBtnY, w = mgBtnW, h = mgBtnH }
        end

        -- 刷新按钮
        local refBtnW, refBtnH = 60, 32
        local refBtnX = pad
        nvgBeginPath(vg); nvgRoundedRect(vg, refBtnX, compBtnY, refBtnW, refBtnH, 6)
        nvgFillColor(vg, nvgRGBA(40, 60, 50, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 120, 160)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 220, 180, 220))
        nvgText(vg, refBtnX + refBtnW / 2, compBtnY + refBtnH / 2, "刷新", nil)
        menuBtnRects.mailRefresh = { x = refBtnX, y = compBtnY, w = refBtnW, h = refBtnH }

        local cloudListTop = compBtnY + compBtnH + 8
        local cloudListH = listBottom - cloudListTop

        nvgSave(vg)
        nvgScissor(vg, 0, cloudListTop, W, cloudListH)

        local scrollOff = ms.scroll and ms.scroll.offset or 0
        local contentH = #inbox * (mailCardH + cardGap) - cardGap
        local maxScroll = math.max(0, contentH - cloudListH)
        if ms.scroll then
            if ms.scroll.offset > maxScroll then ms.scroll.offset = maxScroll; ms.scroll.vel = 0 end
            if ms.scroll.offset < 0 then ms.scroll.offset = 0; ms.scroll.vel = 0 end
            scrollOff = ms.scroll.offset
        end

        for i, cm in ipairs(inbox) do
            local isClaimed = CloudManager.IsMailClaimed(cm.id)
            local hasRewards = #(cm.rewards or {}) > 0
            local cardY = cloudListTop + (i - 1) * (mailCardH + cardGap) - scrollOff
            local cardX = pad
            local cardW = W - pad * 2

            nvgBeginPath(vg); nvgRoundedRect(vg, cardX, cardY, cardW, mailCardH, 10)
            if isClaimed or not hasRewards then
                nvgFillColor(vg, nvgRGBA(20, 20, 25, 180)); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(60, 60, 70, 100)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            else
                local glow = 0.8 + 0.2 * math.sin(t * 2.5)
                nvgFillColor(vg, nvgRGBA(20, 25, 40, math.floor(210 * glow))); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(100, 160, 255, math.floor(140 * glow))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            end

            -- 广播标识
            if cm.isBroadcast then
                nvgFontSize(vg, 11); nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(255, 180, 60, 180))
                nvgText(vg, cardX + cardW - 8, cardY + 4, "[全服]", nil)
            end

            -- 发件人 + 时间
            nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
            nvgText(vg, cardX + 10, cardY + 6, "来自: " .. (cm.fromName or "未知"), nil)
            -- 时间
            local timeStr = ""
            if cm.time and cm.time > 0 then
                local dt2 = os.time() - cm.time
                if dt2 < 60 then
                    timeStr = "刚刚"
                elseif dt2 < 3600 then
                    timeStr = math.floor(dt2 / 60) .. "分钟前"
                elseif dt2 < 86400 then
                    timeStr = math.floor(dt2 / 3600) .. "小时前"
                else
                    timeStr = math.floor(dt2 / 86400) .. "天前"
                end
            end
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgText(vg, cardX + cardW - 10, cardY + 6 + (cm.isBroadcast and 14 or 0), timeStr, nil)

            -- 标题
            nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if isClaimed or not hasRewards then
                nvgFillColor(vg, nvgRGBA(160, 160, 170, 180))
            else
                nvgFillColor(vg, nvgRGBA(220, 230, 255, 240))
            end
            nvgText(vg, cardX + 10, cardY + 24, cm.subject or "(无主题)", nil)

            -- 正文预览 (最多2行)
            nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(160, 160, 170, isClaimed and 100 or 180))
            local bodyPreview = (cm.body or "")
            if #bodyPreview > 60 then bodyPreview = bodyPreview:sub(1, 60) .. "..." end
            nvgText(vg, cardX + 10, cardY + 48, bodyPreview, nil)

            -- 奖励预览
            if hasRewards then
                local rwY2 = cardY + 70
                for ri, rw in ipairs(cm.rewards) do
                    local rwX = cardX + 10 + (ri - 1) * 140
                    nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    if rw.type == "jade" then
                        nvgFillColor(vg, nvgRGBA(255, 220, 100, isClaimed and 80 or 220))
                    elseif rw.type == "ad_free" then
                        nvgFillColor(vg, nvgRGBA(100, 255, 150, isClaimed and 80 or 220))
                    else
                        nvgFillColor(vg, nvgRGBA(200, 160, 255, isClaimed and 80 or 220))
                    end
                    nvgText(vg, rwX, rwY2, rw.label or "", nil)
                end
            end

            -- 领取按钮 / 已读标签
            local btnW2, btnH2 = 80, 30
            local btnX2 = cardX + cardW - btnW2 - 10
            local btnY2 = cardY + mailCardH - btnH2 - 8
            if hasRewards then
                if isClaimed then
                    nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(100, 100, 100, 140))
                    nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "已领取", nil)
                else
                    local bp = 0.85 + 0.15 * math.sin(t * 3.5 + i)
                    nvgBeginPath(vg); nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 8)
                    nvgFillColor(vg, nvgRGBA(50, 90, 160, math.floor(220 * bp))); nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(100, 180, 255, math.floor(180 * bp))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
                    nvgFontSize(vg, 17); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(220, 240, 255, 240))
                    nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "领取", nil)
                    ms.cloudBtnRects[i] = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
                end
            end
        end

        if #inbox == 0 then
            nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 120, 140, 160))
            nvgText(vg, cx, cloudListTop + cloudListH / 2, CloudManager._mailLoading and "加载中..." or "暂无玩家邮件", nil)
        end

        nvgRestore(vg)
    end

    -- =============== 写信弹窗 / 管理面板弹窗 ===============
    if ms.composing and ms.composeData then
        local cd = ms.composeData
        nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180)); nvgFill(vg)

      if cd.isManage then
        -- =============== 玩家管理面板（支持标签切换） ===============
        if not cd.banTab then cd.banTab = "operate" end
        local pw, ph = 420, 440
        local px, py = cx - pw / 2, H / 2 - ph / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, px, py, pw, ph, 14)
        nvgFillColor(vg, nvgRGBA(30, 18, 18, 245)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 80, 80, 160)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
        cd.bgRect = { x = px, y = py, w = pw, h = ph }

        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 180, 180, 240))
        nvgText(vg, cx, py + 24, "玩家管理(管理员)", nil)

        -- 标签按钮
        local fieldX, fieldW = px + 16, pw - 32
        local mTabY = py + 44
        local mTabNames = { { id = "operate", name = "操作" }, { id = "tempList", name = "暂时封禁" }, { id = "permList", name = "永久封禁" } }
        local mTabW = math.floor((fieldW - 8) / 3)
        local mTabH = 28
        cd.tabBtnRects = {}
        for ti, tab in ipairs(mTabNames) do
            local tx = fieldX + (ti - 1) * (mTabW + 4)
            local isSel = (cd.banTab == tab.id)
            nvgBeginPath(vg); nvgRoundedRect(vg, tx, mTabY, mTabW, mTabH, 5)
            if isSel then
                nvgFillColor(vg, nvgRGBA(160, 60, 60, 240)); nvgFill(vg)
            else
                nvgFillColor(vg, nvgRGBA(60, 30, 30, 200)); nvgFill(vg)
            end
            nvgStrokeColor(vg, nvgRGBA(180, 80, 80, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, isSel and nvgRGBA(255, 240, 240, 255) or nvgRGBA(180, 140, 140, 200))
            nvgText(vg, tx + mTabW / 2, mTabY + mTabH / 2, tab.name, nil)
            cd.tabBtnRects[tab.id] = { x = tx, y = mTabY, w = mTabW, h = mTabH }
        end

        local contentY = mTabY + mTabH + 10
        local contentH = py + ph - contentY - 50  -- 底部留空给结果提示

      if cd.banTab == "operate" then
        -- =============== 操作标签（原有功能） ===============
        local fy = contentY
        -- UID输入
        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 180, 180, 200))
        nvgText(vg, fieldX, fy, "目标玩家UID:", nil)
        fy = fy + 18
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, fieldW, 28, 4)
        nvgFillColor(vg, nvgRGBA(15, 15, 20, 200)); nvgFill(vg)
        nvgStrokeColor(vg, cd.inputFocus == "uid" and nvgRGBA(255, 120, 120, 200) or nvgRGBA(80, 50, 50, 150))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        local uidPasteW = 50
        nvgFillColor(vg, nvgRGBA(240, 220, 220, 230)); nvgFontSize(vg, 15)
        nvgText(vg, fieldX + 8, fy + 5, cd.targetUid .. (cd.inputFocus == "uid" and "|" or ""), nil)
        cd.uidRect = { x = fieldX, y = fy, w = fieldW - uidPasteW - 6, h = 28 }
        local upX = fieldX + fieldW - uidPasteW
        nvgBeginPath(vg); nvgRoundedRect(vg, upX, fy, uidPasteW, 28, 4)
        nvgFillColor(vg, nvgRGBA(100, 60, 60, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 120, 120, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 200, 230))
        nvgText(vg, upX + uidPasteW / 2, fy + 14, "粘贴", nil)
        cd.uidPasteRect = { x = upX, y = fy, w = uidPasteW, h = 28 }

        -- 登录管理
        fy = fy + 42
        nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 180, 180, 180))
        nvgText(vg, fieldX, fy, "登录管理:", nil)
        fy = fy + 18
        local btnW, btnH = (fieldW - 12) / 2, 32
        -- 暂时封禁
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(140, 90, 20, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(220, 160, 60, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 140, 240))
        nvgText(vg, fieldX + btnW / 2, fy + btnH / 2, "暂时封禁", nil)
        cd.banBtnRect = { x = fieldX, y = fy, w = btnW, h = btnH }
        -- 解禁
        local ubX = fieldX + btnW + 12
        nvgBeginPath(vg); nvgRoundedRect(vg, ubX, fy, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(30, 100, 50, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 120, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, 240))
        nvgText(vg, ubX + btnW / 2, fy + btnH / 2, "解禁", nil)
        cd.unbanBtnRect = { x = ubX, y = fy, w = btnW, h = btnH }

        -- 排行榜管理
        fy = fy + btnH + 14
        nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 180, 180, 180))
        nvgText(vg, fieldX, fy, "排行榜管理:", nil)
        fy = fy + 18
        -- 隐藏排行榜
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(120, 80, 20, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(220, 160, 60, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 140, 240))
        nvgText(vg, fieldX + btnW / 2, fy + btnH / 2, "隐藏排行榜", nil)
        cd.hideRankBtnRect = { x = fieldX, y = fy, w = btnW, h = btnH }
        -- 恢复排行榜
        nvgBeginPath(vg); nvgRoundedRect(vg, ubX, fy, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(30, 80, 120, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 220, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 240))
        nvgText(vg, ubX + btnW / 2, fy + btnH / 2, "恢复排行榜", nil)
        cd.unhideRankBtnRect = { x = ubX, y = fy, w = btnW, h = btnH }

        -- 永久封禁按钮
        fy = fy + btnH + 14
        nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 180, 180, 180))
        nvgText(vg, fieldX, fy, "永久封禁(不可恢复):", nil)
        fy = fy + 18
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, fieldW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(120, 10, 10, 220)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 40, 40, 200)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 160, 160, 255))
        nvgText(vg, fieldX + fieldW / 2, fy + btnH / 2, "永久封禁(删除数据)", nil)
        cd.permBanBtnRect = { x = fieldX, y = fy, w = fieldW, h = btnH }

      elseif cd.banTab == "tempList" or cd.banTab == "permList" then
        -- =============== 封禁名单标签 ===============
        local isTemp = (cd.banTab == "tempList")
        -- 自动加载
        if not cd.banListLoaded and not cd.banListLoading then
            cd.banListLoading = true
            CloudManager.AdminGetBanListSummary(function(tempList, permList, err)
                cd.banTempList = tempList or {}
                cd.banPermList = permList or {}
                cd.banListLoaded = true
                cd.banListLoading = false
            end)
        end

        local listData = isTemp and cd.banTempList or cd.banPermList
        local fy = contentY

        if cd.banListLoading then
            nvgFontSize(vg, 16); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 180, 180, 200))
            nvgText(vg, cx, fy + contentH / 2, "加载中...", nil)
        elseif #listData == 0 then
            nvgFontSize(vg, 16); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 140, 140, 180))
            nvgText(vg, cx, fy + contentH / 2, isTemp and "暂无暂时封禁玩家" or "暂无永久封禁玩家", nil)
        else
            -- 刷新按钮
            local refBtnW, refBtnH = 60, 24
            local refBtnX = fieldX + fieldW - refBtnW
            nvgBeginPath(vg); nvgRoundedRect(vg, refBtnX, fy, refBtnW, refBtnH, 4)
            nvgFillColor(vg, nvgRGBA(60, 80, 100, 200)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 150, 200, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 12); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 220, 255, 230))
            nvgText(vg, refBtnX + refBtnW / 2, fy + refBtnH / 2, "刷新", nil)
            cd.banRefreshBtnRect = { x = refBtnX, y = fy, w = refBtnW, h = refBtnH }

            nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 160, 160, 180))
            nvgText(vg, fieldX, fy + refBtnH / 2, "共 " .. #listData .. " 人", nil)
            fy = fy + refBtnH + 6

            -- 列表区域（带滚动）
            local banListH = contentH - (refBtnH + 6)
            local itemH = 44
            local totalH = #listData * itemH
            local scroll = cd.banListScroll
            if not scroll then scroll = { offset = 0, vel = 0 }; cd.banListScroll = scroll end
            local maxScroll = math.max(0, totalH - banListH)
            if scroll.offset < 0 then scroll.offset = 0 end
            if scroll.offset > maxScroll then scroll.offset = maxScroll end

            nvgSave(vg)
            nvgScissor(vg, fieldX, fy, fieldW, banListH)
            cd.banListItemRects = {}

            for i, item in ipairs(listData) do
                local iy = fy + (i - 1) * itemH - scroll.offset
                if iy + itemH > fy and iy < fy + banListH then
                    -- 行背景
                    local bgAlpha = (i % 2 == 0) and 40 or 25
                    nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, iy, fieldW, itemH - 2, 4)
                    nvgFillColor(vg, nvgRGBA(80, 40, 40, bgAlpha)); nvgFill(vg)

                    -- UID 和状态
                    nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(240, 210, 210, 230))
                    nvgText(vg, fieldX + 8, iy + itemH / 2 - 8, "UID: " .. item.uid, nil)
                    nvgFontSize(vg, 11); nvgFillColor(vg, nvgRGBA(180, 150, 150, 180))
                    local statusTxt = ""
                    if item.permanent then
                        statusTxt = "永久封禁"
                    else
                        if item.level >= 3 then
                            statusTxt = "全面封禁"
                        elseif item.level >= 2 then
                            statusTxt = "核心封禁"
                        elseif item.level >= 1 then
                            statusTxt = "社交封禁"
                        end
                        if item.rankHidden then statusTxt = statusTxt .. "+排行隐藏" end
                    end
                    nvgText(vg, fieldX + 8, iy + itemH / 2 + 8, statusTxt, nil)

                    -- 操作按钮
                    local actBtnW, actBtnH = 72, 26
                    local actBtnX = fieldX + fieldW - actBtnW - 8
                    local actBtnY = iy + (itemH - actBtnH) / 2

                    if isTemp then
                        -- 暂时封禁名单 → 显示"永久封禁"按钮
                        nvgBeginPath(vg); nvgRoundedRect(vg, actBtnX, actBtnY, actBtnW, actBtnH, 4)
                        nvgFillColor(vg, nvgRGBA(140, 20, 20, 220)); nvgFill(vg)
                        nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
                        nvgFontSize(vg, 12); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(255, 180, 180, 240))
                        nvgText(vg, actBtnX + actBtnW / 2, actBtnY + actBtnH / 2, "永久删除", nil)

                        -- 解禁按钮
                        local unBtnX = actBtnX - actBtnW - 6
                        nvgBeginPath(vg); nvgRoundedRect(vg, unBtnX, actBtnY, actBtnW, actBtnH, 4)
                        nvgFillColor(vg, nvgRGBA(30, 90, 50, 220)); nvgFill(vg)
                        nvgStrokeColor(vg, nvgRGBA(80, 200, 120, 160)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
                        nvgFillColor(vg, nvgRGBA(180, 255, 200, 240))
                        nvgText(vg, unBtnX + actBtnW / 2, actBtnY + actBtnH / 2, "解禁", nil)
                        cd.banListItemRects[i] = {
                            permBtn = { x = actBtnX, y = actBtnY, w = actBtnW, h = actBtnH },
                            unbanBtn = { x = unBtnX, y = actBtnY, w = actBtnW, h = actBtnH },
                            uid = item.uid,
                        }
                    else
                        -- 永久封禁名单 → 仅显示"已删除"标记
                        nvgFontSize(vg, 12); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(255, 80, 80, 160))
                        nvgText(vg, actBtnX + actBtnW / 2, actBtnY + actBtnH / 2, "已删除", nil)
                    end
                end
            end
            nvgRestore(vg)
        end
      end -- banTab

        -- 操作结果提示（所有标签共享）
        if cd.resultMsg and cd.resultTimer and cd.resultTimer > 0 then
            local msgY = py + ph - 36
            local alpha = math.min(255, math.floor(cd.resultTimer / 3.0 * 255))
            local rc = cd.resultOk and nvgRGBA(100, 255, 150, alpha) or nvgRGBA(255, 120, 120, alpha)
            nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, rc)
            nvgText(vg, cx, msgY, cd.resultMsg, nil)
            cd.resultTimer = cd.resultTimer - 0.016
        end

        -- 确认删除弹窗
        if cd.confirmDeleteUid then
            nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 150)); nvgFill(vg)
            local dw, dh = 300, 140
            local dx, dy = cx - dw / 2, H / 2 - dh / 2
            nvgBeginPath(vg); nvgRoundedRect(vg, dx, dy, dw, dh, 10)
            nvgFillColor(vg, nvgRGBA(40, 20, 20, 250)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 200)); nvgStrokeWidth(vg, 2); nvgStroke(vg)

            nvgFontSize(vg, 16); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 200, 200, 240))
            nvgText(vg, cx, dy + 30, "确认永久封禁(删除)?", nil)
            nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(200, 160, 160, 200))
            nvgText(vg, cx, dy + 54, "UID: " .. tostring(cd.confirmDeleteUid), nil)
            nvgFontSize(vg, 12); nvgFillColor(vg, nvgRGBA(255, 120, 120, 180))
            nvgText(vg, cx, dy + 72, "此操作不可恢复!", nil)

            local cbW, cbH = 100, 32
            local cfmX = cx - cbW - 8
            local cfmY = dy + dh - cbH - 16
            -- 确认按钮
            nvgBeginPath(vg); nvgRoundedRect(vg, cfmX, cfmY, cbW, cbH, 6)
            nvgFillColor(vg, nvgRGBA(160, 20, 20, 230)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 200)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 15); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 200, 200, 250))
            nvgText(vg, cfmX + cbW / 2, cfmY + cbH / 2, "确认删除", nil)
            cd.confirmYesRect = { x = cfmX, y = cfmY, w = cbW, h = cbH }
            -- 取消按钮
            local cnlX = cx + 8
            nvgBeginPath(vg); nvgRoundedRect(vg, cnlX, cfmY, cbW, cbH, 6)
            nvgFillColor(vg, nvgRGBA(60, 60, 70, 230)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 140, 160, 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFillColor(vg, nvgRGBA(200, 200, 210, 240))
            nvgText(vg, cnlX + cbW / 2, cfmY + cbH / 2, "取消", nil)
            cd.confirmNoRect = { x = cnlX, y = cfmY, w = cbW, h = cbH }
        end

        -- 关闭按钮
        local clR = 16
        local clX = px + pw - 25
        local clY = py + 20
        nvgBeginPath(vg); nvgCircle(vg, clX, clY, clR)
        nvgFillColor(vg, nvgRGBA(60, 40, 40, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 100, 100, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 180, 180, 220))
        nvgText(vg, clX, clY, "X", nil)
        cd.closeBtnRect = { x = clX - clR, y = clY - clR, w = clR * 2, h = clR * 2 }

      else
        -- =============== 写信 / 发奖励邮件面板 ===============
        local sealSectionH = (cd.isAdmin and cd.sealHeroIdx) and 180 or (cd.isAdmin and 30 or 0)
        local pw, ph = 420, 340 + sealSectionH
        local px, py = cx - pw / 2, H / 2 - ph / 2
        nvgBeginPath(vg); nvgRoundedRect(vg, px, py, pw, ph, 14)
        nvgFillColor(vg, nvgRGBA(25, 28, 40, 245)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 160, 220, 160)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
        cd.bgRect = { x = px, y = py, w = pw, h = ph }

        nvgFontSize(vg, 24); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(cx, py + 28, cd.isAdmin and "发奖励邮件(管理员)" or "写信")

        -- 收件人UID (0=全服广播)
        local fieldX, fieldW = px + 20, pw - 40
        local fy = py + 56
        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
        nvgText(vg, fieldX, fy, cd.isAdmin and "收件人UID (0=全服广播):" or "收件人UID:", nil)
        fy = fy + 20
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, fieldW, 30, 4)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 200)); nvgFill(vg)
        nvgStrokeColor(vg, cd.inputFocus == "uid" and nvgRGBA(100, 180, 255, 200) or nvgRGBA(60, 60, 80, 150))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        local uidPasteW = 50
        nvgFillColor(vg, nvgRGBA(220, 220, 240, 230)); nvgFontSize(vg, 16)
        nvgText(vg, fieldX + 8, fy + 6, cd.targetUid .. (cd.inputFocus == "uid" and "|" or ""), nil)
        cd.uidRect = { x = fieldX, y = fy, w = fieldW - uidPasteW - 6, h = 30 }
        -- UID粘贴按钮
        local upX = fieldX + fieldW - uidPasteW
        nvgBeginPath(vg); nvgRoundedRect(vg, upX, fy, uidPasteW, 30, 4)
        nvgFillColor(vg, nvgRGBA(60, 100, 160, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 160, 255, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawWhiteInkText(upX + uidPasteW / 2, fy + 15, "粘贴")
        cd.uidPasteRect = { x = upX, y = fy, w = uidPasteW, h = 30 }
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        -- 主题
        fy = fy + 38
        nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
        nvgText(vg, fieldX, fy, "主题:", nil)
        fy = fy + 20
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, fieldW, 30, 4)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 200)); nvgFill(vg)
        nvgStrokeColor(vg, cd.inputFocus == "subject" and nvgRGBA(100, 180, 255, 200) or nvgRGBA(60, 60, 80, 150))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 240, 230)); nvgFontSize(vg, 16)
        nvgText(vg, fieldX + 8, fy + 6, cd.subject .. (cd.inputFocus == "subject" and "|" or ""), nil)
        cd.subjectRect = { x = fieldX, y = fy, w = fieldW, h = 30 }

        -- 正文
        fy = fy + 38
        nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
        nvgText(vg, fieldX, fy, "正文:", nil)
        fy = fy + 20
        nvgBeginPath(vg); nvgRoundedRect(vg, fieldX, fy, fieldW, 50, 4)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 200)); nvgFill(vg)
        nvgStrokeColor(vg, cd.inputFocus == "body" and nvgRGBA(100, 180, 255, 200) or nvgRGBA(60, 60, 80, 150))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 240, 230)); nvgFontSize(vg, 14)
        nvgText(vg, fieldX + 8, fy + 6, cd.body .. (cd.inputFocus == "body" and "|" or ""), nil)
        cd.bodyRect = { x = fieldX, y = fy, w = fieldW, h = 50 }

        -- 管理员: 奖励选项
        if cd.isAdmin then
            fy = fy + 58
            nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(255, 200, 80, 200))
            nvgText(vg, fieldX, fy, "附件奖励:", nil)
            fy = fy + 18
            -- 虎符: 标签
            nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
            nvgText(vg, fieldX, fy, "虎符:", nil)
            -- 虎符: 输入框 (可直接输入数字)
            local jInputX, jInputW, jbH = fieldX + 42, 80, 22
            nvgBeginPath(vg); nvgRoundedRect(vg, jInputX, fy - 2, jInputW, jbH, 4)
            nvgFillColor(vg, nvgRGBA(15, 15, 25, 200)); nvgFill(vg)
            nvgStrokeColor(vg, cd.inputFocus == "jade" and nvgRGBA(255, 200, 80, 200) or nvgRGBA(80, 70, 40, 150))
            nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFillColor(vg, nvgRGBA(255, 230, 130, 240)); nvgFontSize(vg, 15)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local jadeDisplayStr = cd.inputFocus == "jade" and ((cd.jadeInputText or "0") .. "|") or tostring(cd.rewardJade or 0)
            nvgText(vg, jInputX + jInputW / 2, fy + jbH / 2 - 2, jadeDisplayStr, nil)
            cd.jadeInputRect = { x = jInputX, y = fy - 2, w = jInputW, h = jbH }
            -- -500 按钮
            local jbW = 36
            local jMinusX = jInputX + jInputW + 6
            nvgBeginPath(vg); nvgRoundedRect(vg, jMinusX, fy - 2, jbW, jbH, 4)
            nvgFillColor(vg, nvgRGBA(80, 40, 40, 200)); nvgFill(vg)
            nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 200, 200, 220))
            nvgText(vg, jMinusX + jbW / 2, fy + jbH / 2 - 2, "-500", nil)
            cd.jadeMinus = { x = jMinusX, y = fy - 2, w = jbW, h = jbH }
            -- +500 按钮
            local jPlusX = jMinusX + jbW + 6
            nvgBeginPath(vg); nvgRoundedRect(vg, jPlusX, fy - 2, jbW, jbH, 4)
            nvgFillColor(vg, nvgRGBA(40, 80, 40, 200)); nvgFill(vg)
            nvgFillColor(vg, nvgRGBA(200, 255, 200, 220))
            nvgText(vg, jPlusX + jbW / 2, fy + jbH / 2 - 2, "+500", nil)
            cd.jadePlus = { x = jPlusX, y = fy - 2, w = jbW, h = jbH }

            -- 免广告特权开关
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local adFreeX = jPlusX + jbW + 14
            nvgFontSize(vg, 14)
            nvgFillColor(vg, cd.adFree and nvgRGBA(100, 255, 150, 230) or nvgRGBA(160, 160, 170, 180))
            nvgText(vg, adFreeX, fy, cd.adFree and "[v] 免广告" or "[ ] 免广告", nil)
            cd.adFreeRect = { x = adFreeX, y = fy - 2, w = 90, h = jbH }

            -- ========== 兵符派发 ==========
            fy = fy + 28
            nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(180, 140, 255, 220))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgText(vg, fieldX, fy, "兵符派发:", nil)

            -- 武灵选择按钮
            local heroSelX = fieldX + 68
            local heroSelW, heroSelH = 140, 22
            local heroName = "未选择"
            if cd.sealHeroIdx and HERO_CARDS[cd.sealHeroIdx] then
                heroName = cd.sealHeroIdx .. "." .. HERO_CARDS[cd.sealHeroIdx].name
            end
            nvgBeginPath(vg); nvgRoundedRect(vg, heroSelX, fy - 2, heroSelW, heroSelH, 4)
            nvgFillColor(vg, nvgRGBA(30, 20, 50, 200)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 100, 200, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 200, 255, 230))
            nvgText(vg, heroSelX + heroSelW / 2, fy + heroSelH / 2 - 2, heroName, nil)
            cd.sealHeroSelRect = { x = heroSelX, y = fy - 2, w = heroSelW, h = heroSelH }

            -- 左右翻页按钮
            local arrW = 22
            local arrLX = heroSelX - arrW - 4
            nvgBeginPath(vg); nvgRoundedRect(vg, arrLX, fy - 2, arrW, heroSelH, 4)
            nvgFillColor(vg, nvgRGBA(60, 40, 80, 200)); nvgFill(vg)
            nvgFontSize(vg, 14); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 180, 255, 220))
            nvgText(vg, arrLX + arrW / 2, fy + heroSelH / 2 - 2, "<", nil)
            cd.sealHeroPrev = { x = arrLX, y = fy - 2, w = arrW, h = heroSelH }

            local arrRX = heroSelX + heroSelW + 4
            nvgBeginPath(vg); nvgRoundedRect(vg, arrRX, fy - 2, arrW, heroSelH, 4)
            nvgFillColor(vg, nvgRGBA(60, 40, 80, 200)); nvgFill(vg)
            nvgFillColor(vg, nvgRGBA(200, 180, 255, 220))
            nvgText(vg, arrRX + arrW / 2, fy + heroSelH / 2 - 2, ">", nil)
            cd.sealHeroNext = { x = arrRX, y = fy - 2, w = arrW, h = heroSelH }

            -- 清除武灵选择
            local clrX = arrRX + arrW + 6
            local clrW = 36
            nvgBeginPath(vg); nvgRoundedRect(vg, clrX, fy - 2, clrW, heroSelH, 4)
            nvgFillColor(vg, nvgRGBA(80, 40, 40, 200)); nvgFill(vg)
            nvgFontSize(vg, 12); nvgFillColor(vg, nvgRGBA(255, 180, 180, 220))
            nvgText(vg, clrX + clrW / 2, fy + heroSelH / 2 - 2, "清除", nil)
            cd.sealHeroClear = { x = clrX, y = fy - 2, w = clrW, h = heroSelH }

            -- 如果已选武灵，显示6个孔位选择
            if cd.sealHeroIdx then
                if not cd.sealSlots then cd.sealSlots = {} end
                cd.sealSlotRects = {}
                fy = fy + 26

                -- 快捷操作行: 全随机 / 全不选
                local qkBtnW, qkBtnH = 64, 20
                local qkX1 = fieldX
                nvgBeginPath(vg); nvgRoundedRect(vg, qkX1, fy - 1, qkBtnW, qkBtnH, 4)
                nvgFillColor(vg, nvgRGBA(50, 50, 20, 200)); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(200, 200, 100, 120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
                nvgFontSize(vg, 12); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(220, 220, 120, 230))
                nvgText(vg, qkX1 + qkBtnW / 2, fy + qkBtnH / 2 - 1, "全随机", nil)
                cd.sealAllRandom = { x = qkX1, y = fy - 1, w = qkBtnW, h = qkBtnH }

                local qkX2 = qkX1 + qkBtnW + 8
                nvgBeginPath(vg); nvgRoundedRect(vg, qkX2, fy - 1, qkBtnW, qkBtnH, 4)
                nvgFillColor(vg, nvgRGBA(50, 20, 20, 200)); nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(200, 100, 100, 120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
                nvgFillColor(vg, nvgRGBA(220, 150, 150, 230))
                nvgText(vg, qkX2 + qkBtnW / 2, fy + qkBtnH / 2 - 1, "全不选", nil)
                cd.sealAllClear = { x = qkX2, y = fy - 1, w = qkBtnW, h = qkBtnH }

                -- 已选计数提示
                local selCount = 0
                for s = 1, SEAL_MAX_SLOTS do if cd.sealSlots[s] ~= nil then selCount = selCount + 1 end end
                nvgFontSize(vg, 11); nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(160, 140, 200, 160))
                nvgText(vg, fieldX + fieldW, fy + qkBtnH / 2 - 1, selCount .. "/6 已选", nil)

                fy = fy + qkBtnH + 6
                local colW = (fieldW) / 3
                for s = 1, SEAL_MAX_SLOTS do
                    local col = (s - 1) % 3
                    local row = (s - 1) < 3 and 0 or 1
                    local sx = fieldX + col * colW
                    local sy = fy + row * 50
                    local slotVal = cd.sealSlots[s] -- nil=不选, 0=随机, 1~7=指定品阶

                    -- 孔位名称
                    local tc = SEAL_SLOT_THEME_COLORS[s] or {180,180,180}
                    nvgFontSize(vg, 12); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 220))
                    nvgText(vg, sx, sy, SEAL_SLOT_NAMES[s], nil)

                    -- 品阶选择按钮
                    local btnX = sx + 36
                    local btnW, btnH = 80, 20
                    local label = "跳过"
                    local lblClr = nvgRGBA(100, 100, 110, 150)
                    local bgAlpha = 180
                    if slotVal == 0 then
                        label = "随机"
                        lblClr = nvgRGBA(220, 220, 100, 240)
                        bgAlpha = 220
                    elseif slotVal and slotVal >= 1 then
                        label = SEAL_TIER_NAMES[slotVal] or ("Lv" .. slotVal)
                        local qc = SEAL_QUALITY_COLORS[slotVal] or {200,200,200}
                        lblClr = nvgRGBA(qc[1], qc[2], qc[3], 250)
                        bgAlpha = 230
                    end
                    nvgBeginPath(vg); nvgRoundedRect(vg, btnX, sy - 1, btnW, btnH, 4)
                    nvgFillColor(vg, nvgRGBA(20, 15, 30, bgAlpha)); nvgFill(vg)
                    nvgStrokeColor(vg, slotVal ~= nil and nvgRGBA(tc[1], tc[2], tc[3], 140) or nvgRGBA(tc[1], tc[2], tc[3], 50))
                    nvgStrokeWidth(vg, slotVal ~= nil and 1.5 or 0.8); nvgStroke(vg)
                    nvgFontSize(vg, 13); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, lblClr)
                    nvgText(vg, btnX + btnW / 2, sy + btnH / 2 - 1, label, nil)
                    cd.sealSlotRects[s] = { x = btnX, y = sy - 1, w = btnW, h = btnH }
                end
                fy = fy + 100
            end
        end

        -- 发送按钮
        local sendBtnW, sendBtnH = 120, 40
        local sendBtnX = cx - sendBtnW / 2
        local sendBtnY = py + ph - sendBtnH - 16
        local sp = 0.85 + 0.15 * math.sin(t * 3.0)
        nvgBeginPath(vg); nvgRoundedRect(vg, sendBtnX, sendBtnY, sendBtnW, sendBtnH, 8)
        nvgFillColor(vg, nvgRGBA(50, 100, 170, math.floor(230 * sp))); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 180, 255, math.floor(180 * sp))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 240, 255, 240))
        nvgText(vg, sendBtnX + sendBtnW / 2, sendBtnY + sendBtnH / 2, "发送", nil)
        cd.sendBtnRect = { x = sendBtnX, y = sendBtnY, w = sendBtnW, h = sendBtnH }

        -- 关闭按钮
        local clR = 16
        local clX = px + pw - 25
        local clY = py + 20
        nvgBeginPath(vg); nvgCircle(vg, clX, clY, clR)
        nvgFillColor(vg, nvgRGBA(60, 50, 40, 200)); nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(160, 140, 110, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 190, 170, 220))
        nvgText(vg, clX, clY, "X", nil)
        cd.closeBtnRect = { x = clX - clR, y = clY - clR, w = clR * 2, h = clR * 2 }
      end -- isManage branch
    end

    -- =============== 系统邮件确认弹窗 ===============
    if ms.confirmPopup and not ms.composing then
        local popup = ms.confirmPopup
        local mail = popup.cloudMail or welfareState.mailDefs[popup.mailIdx]
        if mail then
            nvgBeginPath(vg); nvgRect(vg, 0, 0, W, H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 160)); nvgFill(vg)

            local pw, ph = 380, 280
            local px, py = cx - pw / 2, H / 2 - ph / 2
            nvgBeginPath(vg); nvgRoundedRect(vg, px, py, pw, ph, 14)
            nvgFillColor(vg, nvgRGBA(25, 20, 15, 240)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(200, 160, 80, 160)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
            popup.bgRect = { x = px, y = py, w = pw, h = ph }

            local popTitle = popup.cloudMail and (mail.subject or "领取") or mail.title
            nvgFontSize(vg, 26); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            DrawWhiteInkText(cx, py + 30, "领取: " .. popTitle)

            local rewards = popup.cloudMail and (mail.rewards or {}) or (mail.rewards or {})
            nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local ry0 = py + 60
            for ri, rw in ipairs(rewards) do
                if rw.type == "jade" then
                    nvgFillColor(vg, nvgRGBA(255, 220, 100, 240))
                elseif rw.type == "ad_free" then
                    nvgFillColor(vg, nvgRGBA(100, 255, 150, 240))
                else
                    nvgFillColor(vg, nvgRGBA(200, 160, 255, 240))
                end
                nvgText(vg, cx, ry0 + (ri - 1) * 30, rw.label or "", nil)
            end

            if not popup.cloudMail then
                nvgFontSize(vg, 14); nvgFillColor(vg, nvgRGBA(160, 150, 130, 180))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgText(vg, cx, ry0 + #rewards * 30 + 16, "武技残片将分配给每个已开放的武技", nil)
            end

            local cbW, cbH = 140, 42
            local cbX = cx - cbW / 2
            local cbY = py + ph - cbH - 20
            local cbP = 0.85 + 0.15 * math.sin(t * 3.0)
            nvgBeginPath(vg); nvgRoundedRect(vg, cbX, cbY, cbW, cbH, 8)
            nvgFillColor(vg, nvgRGBA(180, 80, 30, math.floor(230 * cbP))); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 100, math.floor(180 * cbP))); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            nvgFontSize(vg, 22); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            DrawWhiteInkText(cbX + cbW / 2, cbY + cbH / 2, "确认领取")
            popup.confirmBtnRect = { x = cbX, y = cbY, w = cbW, h = cbH }

            local clR = 16
            local clX = px + pw - 25
            local clY = py + 20
            nvgBeginPath(vg); nvgCircle(vg, clX, clY, clR)
            nvgFillColor(vg, nvgRGBA(60, 50, 40, 200)); nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(160, 140, 110, 150)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
            nvgFontSize(vg, 20); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 190, 170, 220))
            nvgText(vg, clX, clY, "X", nil)
            popup.closeBtnRect = { x = clX - clR, y = clY - clR, w = clR * 2, h = clR * 2 }
        end
    end
end


