-- scripts/RoleplayPhone.lua
-- RP Phone UI - Draw-based, no XML GUI required
-- Pattern: Mission00 appended functions (same as SurvivalNeeds)

-- Capture mod directory immediately at script load time
local modDirectory = g_currentModDirectory

RoleplayPhone = {}

-- ─── State constants ──────────────────────────────────────────────────────────
RoleplayPhone.STATE = {
    CLOSED         = 0,
    HOME           = 1,
    INVOICES_LIST  = 2,
    INVOICE_DETAIL = 3,
    INVOICE_CREATE = 4,
    CONTACTS       = 5,
    PING           = 6,
}

-- ─── Tab constants ────────────────────────────────────────────────────────────
RoleplayPhone.TAB = {
    INBOX  = 1,
    OUTBOX = 2,
}

-- ─── Runtime state ────────────────────────────────────────────────────────────
RoleplayPhone.state          = RoleplayPhone.STATE.CLOSED
RoleplayPhone.currentTab     = RoleplayPhone.TAB.INBOX
RoleplayPhone.mouseX         = 0
RoleplayPhone.mouseY         = 0
RoleplayPhone.whiteOverlay   = nil
RoleplayPhone.iconInvoices   = nil
RoleplayPhone.iconContacts   = nil
RoleplayPhone.iconPing       = nil
RoleplayPhone.hitboxes       = {}   -- rebuilt every draw frame

-- Create invoice form state
RoleplayPhone.form = {
    toFarmIndex   = 1,      -- index into available farms list
    categoryIndex = 1,      -- index into InvoiceManager.categories
    amount        = "",
    description   = "",
    notes         = "",
    dueDate       = "",
    activeField   = nil,    -- "amount" | "description" | "notes" | "dueDate"
}

-- ─── Layout: small phone (HOME screen) ───────────────────────────────────────
RoleplayPhone.PHONE = {
    x = 0.415, y = 0.06,
    w = 0.17,  h = 0.55,
}

-- ─── Layout: big screen (INVOICES, CONTACTS, PING) ───────────────────────────
RoleplayPhone.BIG = {
    x = 0.22, y = 0.03,
    w = 0.56, h = 0.90,
}

-- ─── Init ─────────────────────────────────────────────────────────────────────
function RoleplayPhone:init()
    local tex = modDirectory .. "textures/"
    self.whiteOverlay = createImageOverlay(tex .. "white.png")
    self.iconInvoices = createImageOverlay(tex .. "icon_invoices.png")
    self.iconContacts = createImageOverlay(tex .. "icon_contacts.png")
    self.iconPing     = createImageOverlay(tex .. "icon_ping.png")

    if self.whiteOverlay == nil or self.whiteOverlay == 0 then
        print("[RoleplayPhone] ERROR: failed to load white.png")
    else
        print("[RoleplayPhone] Initialized OK")
    end
end

-- ─── Open / Close ─────────────────────────────────────────────────────────────
function RoleplayPhone:toggle()
    if self.state == self.STATE.CLOSED then
        self.state = self.STATE.HOME
        g_inputBinding:setShowMouseCursor(true)
        g_currentMission.paused = true
        if g_currentMission.player then
            g_currentMission.player.inputInformation.ignoreInputAfterSelection = true
        end
        print("[RoleplayPhone] Opened")
    else
        self:close()
    end
end

function RoleplayPhone:close()
    self.state = self.STATE.CLOSED
    self.form.activeField = nil
    g_inputBinding:setShowMouseCursor(false)
    g_currentMission.paused = false
    print("[RoleplayPhone] Closed")
end

function RoleplayPhone:goHome()
    self.state = self.STATE.HOME
    self.form.activeField = nil
end

-- ─── Save invoices directly (no longer depends on g_roleplayInvoices) ────────
function RoleplayPhone:saveInvoices()
    if not g_currentMission or not g_currentMission.missionInfo then return end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if not dir then return end

    local filename = dir .. "/roleplayInvoices.xml"
    local xmlFile  = createXMLFile("roleplayInvoicesXML", filename, "roleplayInvoices")
    if xmlFile == 0 then return end

    InvoiceSave:saveToXML(xmlFile, "roleplayInvoices")
    saveXMLFile(xmlFile)
    delete(xmlFile)
    print("[RoleplayPhone] Invoices saved")
end

-- ─── Drawing helpers ──────────────────────────────────────────────────────────
function RoleplayPhone:drawRect(x, y, w, h, r, g, b, a)
    if not self.whiteOverlay or self.whiteOverlay == 0 then return end
    setOverlayColor(self.whiteOverlay, r, g, b, a or 1.0)
    renderOverlay(self.whiteOverlay, x, y, w, h)
end

function RoleplayPhone:hitTest(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function RoleplayPhone:addHitbox(id, x, y, w, h, data)
    table.insert(self.hitboxes, { id=id, x=x, y=y, w=w, h=h, data=data })
end

-- Draw a button and register its hitbox
function RoleplayPhone:drawButton(id, x, y, w, h, label, br, bg, bb, textSize)
    self:drawRect(x, y, w, h, br, bg, bb, 1.0)
    -- Top highlight
    self:drawRect(x, y + h - 0.002, w, 0.002, br+0.15, bg+0.15, bb+0.15, 0.3)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.95)
    renderText(x + w/2, y + h*0.32, textSize or 0.013, label)
    self:addHitbox(id, x, y, w, h, {})
end

-- Draw an input field box (highlights if active)
function RoleplayPhone:drawField(id, x, y, w, h, label, value, active)
    local br = active and 0.15 or 0.10
    local bg = active and 0.32 or 0.14
    local bb = active and 0.55 or 0.20
    -- Background
    self:drawRect(x, y, w, h, br, bg, bb, 1.0)
    -- Border (brighter if active)
    local alpha = active and 0.9 or 0.4
    self:drawRect(x,       y,       w,    0.002, 0.5, 0.6, 0.8, alpha)
    self:drawRect(x,       y+h-0.002, w,  0.002, 0.5, 0.6, 0.8, alpha)
    self:drawRect(x,       y,       0.002, h,    0.5, 0.6, 0.8, alpha)
    self:drawRect(x+w-0.002, y,     0.002, h,    0.5, 0.6, 0.8, alpha)
    -- Label
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.6, 0.7, 0.8, 0.9)
    renderText(x + 0.008, y + h - 0.016, 0.010, label)
    -- Value (with cursor if active)
    local display = value
    if active then display = value .. "|" end
    setTextColor(1, 1, 1, 1)
    renderText(x + 0.008, y + 0.008, 0.013, display)
    -- Register hitbox
    self:addHitbox(id, x, y, w, h, {})
end

-- ─── Status badge helper ──────────────────────────────────────────────────────
function RoleplayPhone:getStatusColor(status)
    if status == "PAID"    then return 0.10, 0.55, 0.20  end  -- green
    if status == "OVERDUE" then return 0.70, 0.15, 0.15  end  -- red
    if status == "DUE"     then return 0.70, 0.45, 0.05  end  -- orange
    return 0.30, 0.30, 0.38                                     -- gray (PENDING)
end

-- ─── Get farms helper ─────────────────────────────────────────────────────────
function RoleplayPhone:getAvailableFarms()
    local farms = {}
    if g_currentMission and g_currentMission.farmManager then
        for _, farm in pairs(g_currentMission.farmManager:getFarms()) do
            if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
                table.insert(farms, farm)
            end
        end
    end
    -- Fallback if no farms found
    if #farms == 0 then
        table.insert(farms, { farmId=1, name="Farm 1" })
    end
    return farms
end

-- ─── Main draw dispatcher ─────────────────────────────────────────────────────
function RoleplayPhone:draw()
    if self.state == self.STATE.CLOSED then return end
    self.hitboxes = {}  -- clear hitboxes each frame

    if self.state == self.STATE.HOME then
        self:drawPhoneHome()
    elseif self.state == self.STATE.INVOICES_LIST then
        self:drawBigScreen()
        self:drawInvoicesList()
    elseif self.state == self.STATE.INVOICE_CREATE then
        self:drawBigScreen()
        self:drawCreateInvoice()
    elseif self.state == self.STATE.INVOICE_DETAIL then
        self:drawBigScreen()
        self:drawInvoiceDetail()
    end
end

-- ─── Big screen shell (used by invoices, contacts, ping) ─────────────────────
function RoleplayPhone:drawBigScreen()
    local s = self.BIG
    -- Phone body border
    self:drawRect(s.x-0.007, s.y-0.007, s.w+0.014, s.h+0.014, 0.04, 0.04, 0.05, 1.0)
    -- Screen background
    self:drawRect(s.x, s.y, s.w, s.h, 0.02, 0.03, 0.05, 1.0)
    -- Notch
    local nw = s.w * 0.18
    self:drawRect(s.x + (s.w-nw)/2, s.y + s.h - 0.014, nw, 0.014, 0.01, 0.02, 0.03, 1.0)
    -- Status bar
    self:drawStatusBar(s.x, s.y, s.w, s.h)
end

-- ─── Status bar ───────────────────────────────────────────────────────────────
function RoleplayPhone:drawStatusBar(px, py, pw, ph)
    local barY     = py + ph - 0.038
    local textSize = 0.012

    local timeStr = "00:00"
    if g_currentMission and g_currentMission.environment then
        local dt   = g_currentMission.environment.dayTime / 3600000
        local hrs  = math.floor(dt) % 24
        local mins = math.floor((dt - math.floor(dt)) * 60)
        timeStr    = string.format("%02d:%02d", hrs, mins)
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(px + 0.014, barY, textSize, timeStr)

    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(px + pw - 0.044, barY, textSize, "|||")
    renderText(px + pw - 0.020, barY, textSize, "4G")

    -- Battery
    local bx = px + pw - 0.014
    self:drawRect(bx,       barY+0.001, 0.010, 0.010, 0.75, 0.75, 0.75, 1.0)
    self:drawRect(bx+0.001, barY+0.002, 0.008, 0.008, 1.00, 1.00, 1.00, 1.0)
    self:drawRect(bx+0.010, barY+0.003, 0.002, 0.004, 0.75, 0.75, 0.75, 1.0)

    -- Divider
    self:drawRect(px, barY - 0.004, pw, 0.001, 0.2, 0.22, 0.28, 0.6)
end

-- ─── HOME screen ─────────────────────────────────────────────────────────────
function RoleplayPhone:drawPhoneHome()
    local px = self.PHONE.x
    local py = self.PHONE.y
    local pw = self.PHONE.w
    local ph = self.PHONE.h
    local cx = px + pw / 2

    -- Phone body (near-black bezel)
    self:drawRect(px-0.009, py-0.009, pw+0.018, ph+0.018, 0.01, 0.01, 0.01, 1.0)
    -- Screen (pure black)
    self:drawRect(px, py, pw, ph, 0.0, 0.0, 0.0, 1.0)
    -- Notch
    local nw = pw * 0.20
    self:drawRect(cx - nw/2, py + ph - 0.010, nw, 0.010, 0.01, 0.01, 0.01, 1.0)

    -- Status bar
    self:drawStatusBar(px, py, pw, ph)

    -- Big clock
    local timeStr = "00:00"
    if g_currentMission and g_currentMission.environment then
        local dt   = g_currentMission.environment.dayTime / 3600000
        local hrs  = math.floor(dt) % 24
        local mins = math.floor((dt - math.floor(dt)) * 60)
        timeStr    = string.format("%02d:%02d", hrs, mins)
    end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(cx, py + ph * 0.66, 0.038, timeStr)

    -- Day and Season
    local dateStr = ""
    if g_currentMission and g_currentMission.environment then
        local env     = g_currentMission.environment
        local day     = env.currentDay or 0
        local seasons = { "Spring", "Summer", "Autumn", "Winter" }
        local season  = "Spring"
        if env.currentSeason ~= nil then
            season = seasons[(env.currentSeason % 4) + 1] or "Spring"
        end
        dateStr = string.format("Day %d  -  %s", day, season)
    end
    setTextBold(false)
    setTextColor(0.55, 0.60, 0.70, 0.9)
    renderText(cx, py + ph * 0.58, 0.013, dateStr)

    -- Dock background
    local dockH = 0.110
    local dockY = py + 0.004
    self:drawRect(px, dockY, pw, dockH, 0.02, 0.02, 0.03, 1.0)
    self:drawRect(px, dockY + dockH - 0.002, pw, 0.002, 0.08, 0.08, 0.10, 1.0)

    -- App icons
    self:drawAppIcons(px, py, pw, ph, dockY, dockH)

    -- Page dots above dock
    local dotSize   = 0.005
    local dotGap    = 0.016
    local dotY      = dockY + dockH + 0.009
    local dotStartX = cx - dotGap
    for i = 1, 3 do
        local alpha = (i == 1) and 0.85 or 0.22
        self:drawRect(dotStartX + (i-1)*dotGap - dotSize/2, dotY, dotSize, dotSize, 1, 1, 1, alpha)
    end

    -- Close hint
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    setTextColor(0.20, 0.20, 0.22, 0.9)
    renderText(cx, py + 0.003, 0.008, "Press F7 to close")
end

function RoleplayPhone:drawAppIcons(px, py, pw, ph, dockY, dockH)
    local colW      = pw / 3
    local iconSize  = colW * 0.80   -- always fits inside column with padding
    local labelSize = 0.009
    local iconY     = dockY + (dockH - iconSize) / 2
    local centerY   = iconY + iconSize * 0.38  -- image sits upper portion of square
    local labelY    = iconY + iconSize * 0.08  -- label near bottom inside square

    local apps = {
        { label="Invoices", br=0.28, bg=0.22, bb=0.01, state=self.STATE.INVOICES_LIST, icon=self.iconInvoices },
        { label="Contacts", br=0.24, bg=0.06, bb=0.32, state=self.STATE.CONTACTS,      icon=self.iconContacts },
        { label="Ping",     br=0.01, bg=0.26, bb=0.28, state=self.STATE.PING,          icon=self.iconPing     },
    }

    for i, app in ipairs(apps) do
        local iconX   = px + (i-1)*colW + (colW-iconSize)/2
        local centerX = iconX + iconSize/2

        -- Icon square (guaranteed to fit inside phone width)
        self:drawRect(iconX, iconY, iconSize, iconSize, app.br, app.bg, app.bb, 1.0)

        -- Icon image (upper ~65% of square)
        if app.icon and app.icon ~= 0 then
            local imgSize = iconSize * 0.55
            local imgX    = iconX + (iconSize - imgSize) / 2
            local imgY    = iconY + iconSize * 0.20
            setOverlayColor(app.icon, 1, 1, 1, 1)
            renderOverlay(app.icon, imgX, imgY, imgSize, imgSize)
        end

        -- Label inside square at the bottom
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(1, 1, 1, 0.95)
        renderText(centerX, labelY, labelSize, app.label)

        self:addHitbox("app_" .. app.label, iconX, iconY, iconSize, iconSize, { state=app.state })
    end
end

-- ─── INVOICES LIST screen ─────────────────────────────────────────────────────
function RoleplayPhone:drawInvoicesList()
    local s        = self.BIG
    local px       = s.x
    local py       = s.y
    local pw       = s.w
    local ph       = s.h
    local contentY = py + ph - 0.055  -- just below status bar

    -- ── Header ──
    local headerH  = 0.05
    local headerY  = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)

    -- Back button
    self:drawButton("btn_back", px+0.010, headerY+0.010, 0.055, 0.030,
                    "< Back", 0.18, 0.20, 0.28, 0.011)

    -- Title
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw/2, headerY + 0.016, 0.016, "INVOICES")

    -- ── Tabs ──
    local tabY = headerY - 0.038
    local tabH = 0.038
    local tabW = pw / 2

    -- Inbox tab
    local inboxActive  = self.currentTab == self.TAB.INBOX
    local outboxActive = self.currentTab == self.TAB.OUTBOX

    self:drawRect(px,      tabY, tabW, tabH,
                  inboxActive  and 0.13 or 0.09,
                  inboxActive  and 0.18 or 0.11,
                  inboxActive  and 0.28 or 0.15, 1.0)
    self:drawRect(px+tabW, tabY, tabW, tabH,
                  outboxActive and 0.13 or 0.09,
                  outboxActive and 0.18 or 0.11,
                  outboxActive and 0.28 or 0.15, 1.0)

    -- Active tab indicator line
    if inboxActive then
        self:drawRect(px, tabY, tabW, 0.003, 0.30, 0.55, 1.00, 1.0)
    else
        self:drawRect(px+tabW, tabY, tabW, 0.003, 0.30, 0.55, 1.00, 1.0)
    end

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(inboxActive)
    setTextColor(1, 1, 1, inboxActive and 1.0 or 0.5)
    renderText(px + tabW/2, tabY + 0.012, 0.013, "INBOX")

    setTextBold(outboxActive)
    setTextColor(1, 1, 1, outboxActive and 1.0 or 0.5)
    renderText(px + tabW + tabW/2, tabY + 0.012, 0.013, "OUTBOX")

    self:addHitbox("tab_inbox",  px,      tabY, tabW, tabH, {})
    self:addHitbox("tab_outbox", px+tabW, tabY, tabW, tabH, {})

    -- ── Invoice list area ──
    local listTopY    = tabY - 0.006
    local listBottomY = py + 0.015
    local listH       = listTopY - listBottomY

    -- Get invoices for current farm
    local myFarmId = (g_currentMission and g_currentMission.playerFarmId) or 1
    local inbox    = self.currentTab == self.TAB.INBOX
    local invoices = InvoiceManager:getInvoicesForFarm(myFarmId, inbox)

    -- Create Invoice button (Outbox only, at bottom)
    if not inbox then
        local btnH = 0.042
        local btnY = listBottomY
        listBottomY = listBottomY + btnH + 0.008
        listH       = listTopY - listBottomY

        self:drawButton("btn_create_invoice",
                        px + 0.015, btnY, pw - 0.030, btnH,
                        "+ Create Invoice", 0.10, 0.38, 0.18, 0.013)
    end

    -- Draw invoice rows
    if #invoices == 0 then
        -- Empty state
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(0.4, 0.45, 0.55, 0.8)
        local emptyMsg = inbox and "No invoices in your inbox" or "No invoices sent yet"
        renderText(px + pw/2, listBottomY + listH/2, 0.013, emptyMsg)
    else
        local rowH     = 0.072
        local rowPad   = 0.006
        local maxRows  = math.floor(listH / (rowH + rowPad))
        local shown    = math.min(#invoices, maxRows)

        for i = 1, shown do
            local inv  = invoices[i]
            local rowY = listTopY - (i * (rowH + rowPad))

            if rowY < listBottomY then break end

            self:drawInvoiceRow(inv, px + 0.010, rowY, pw - 0.020, rowH, i)
        end

        -- "X more" hint if list is longer than visible
        if #invoices > maxRows then
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(false)
            setTextColor(0.4, 0.45, 0.55, 0.7)
            renderText(px + pw/2, listBottomY - 0.001, 0.010,
                       string.format("+ %d more invoices", #invoices - maxRows))
        end
    end
end

-- Draw a single invoice row
function RoleplayPhone:drawInvoiceRow(inv, x, y, w, h, index)
    -- Row background (alternating slight shade)
    local shade = (index % 2 == 0) and 0.115 or 0.095
    self:drawRect(x, y, w, h, shade, shade+0.015, shade+0.030, 1.0)

    -- Status badge (right side)
    local badgeW = 0.075
    local badgeH = 0.022
    local badgeX = x + w - badgeW - 0.008
    local badgeY = y + h - badgeH - 0.008
    local sr, sg, sb = self:getStatusColor(inv.status)
    self:drawRect(badgeX, badgeY, badgeW, badgeH, sr, sg, sb, 1.0)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(badgeX + badgeW/2, badgeY + 0.004, 0.009, inv.status or "PENDING")

    -- Invoice # and date
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(0.75, 0.85, 1.0, 1.0)
    renderText(x + 0.010, y + h - 0.020, 0.011, string.format("INV #%04d", inv.id or 0))

    setTextBold(false)
    setTextColor(0.5, 0.55, 0.65, 0.8)
    renderText(x + 0.010, y + h - 0.034, 0.010,
               string.format("Day %s", tostring(inv.createdDate or "?")))

    -- Category
    setTextColor(0.85, 0.85, 0.95, 0.9)
    local cat = inv.category or "Uncategorized"
    if #cat > 28 then cat = cat:sub(1,26) .. ".." end
    renderText(x + 0.010, y + 0.030, 0.011, cat)

    -- Amount (right side, larger)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextBold(true)
    setTextColor(0.35, 0.95, 0.45, 1.0)
    renderText(x + w - 0.010, y + 0.028, 0.015,
               string.format("$%s", self:formatMoney(inv.amount or 0)))

    -- Register hitbox
    self:addHitbox("invoice_row", x, y, w, h, { invoice=inv })
end

-- ─── INVOICE DETAIL screen ───────────────────────────────────────────────────
function RoleplayPhone:drawInvoiceDetail()
    if not self.selectedInvoice then
        self.state = self.STATE.INVOICES_LIST
        return
    end

    local s   = self.BIG
    local px  = s.x
    local py  = s.y
    local pw  = s.w
    local ph  = s.h
    local inv = self.selectedInvoice

    -- Header
    local headerH = 0.05
    local headerY = py + ph - 0.055 - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)
    self:drawButton("btn_back", px+0.010, headerY+0.010, 0.055, 0.030,
                    "< Back", 0.18, 0.20, 0.28, 0.011)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw/2, headerY + 0.016, 0.015,
               string.format("INVOICE #%04d", inv.id or 0))

    -- Status banner
    local sr, sg, sb = self:getStatusColor(inv.status)
    local bannerY = headerY - 0.038
    self:drawRect(px, bannerY, pw, 0.038, sr, sg, sb, 0.85)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw/2, bannerY + 0.010, 0.016, inv.status or "PENDING")

    -- Detail fields
    local fieldX = px + 0.020
    local fieldW = pw - 0.040
    local curY   = bannerY - 0.020

    local function drawDetail(label, value)
        curY = curY - 0.038
        self:drawRect(fieldX, curY, fieldW, 0.036, 0.10, 0.13, 0.19, 1.0)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(false)
        setTextColor(0.55, 0.65, 0.80, 0.85)
        renderText(fieldX + 0.010, curY + 0.024, 0.009, label)
        setTextColor(1, 1, 1, 1)
        renderText(fieldX + 0.010, curY + 0.008, 0.013, tostring(value or "-"))
    end

    -- Get farm names
    local fromName = "Farm " .. tostring(inv.fromFarmId or "?")
    local toName   = "Farm " .. tostring(inv.toFarmId or "?")
    if g_currentMission and g_currentMission.farmManager then
        local ff = g_currentMission.farmManager:getFarmById(inv.fromFarmId)
        local tf = g_currentMission.farmManager:getFarmById(inv.toFarmId)
        if ff and ff.name then fromName = ff.name end
        if tf and tf.name then toName   = tf.name end
    end

    drawDetail("FROM",        fromName)
    drawDetail("TO",          toName)
    drawDetail("CATEGORY",    inv.category)
    drawDetail("AMOUNT",      "$" .. self:formatMoney(inv.amount or 0))
    drawDetail("DUE DATE",    inv.dueDate or "Not set")
    drawDetail("CREATED",     "Day " .. tostring(inv.createdDate or "?"))

    if inv.description and inv.description ~= "" then
        drawDetail("DESCRIPTION", inv.description)
    end
    if inv.notes and inv.notes ~= "" then
        drawDetail("NOTES", inv.notes)
    end

    -- Action buttons (bottom)
    local btnY = py + 0.015
    local myFarmId = (g_currentMission and g_currentMission.playerFarmId) or 1

    -- Pay button (shown to recipient if not already paid)
    if inv.toFarmId == myFarmId and inv.status ~= "PAID" then
        self:drawButton("btn_pay_invoice",
                        px + 0.015, btnY, pw*0.44, 0.045,
                        "Pay Invoice", 0.10, 0.40, 0.18, 0.013)
    end

    -- Mark Paid button (shown to sender)
    if inv.fromFarmId == myFarmId and inv.status ~= "PAID" then
        self:drawButton("btn_mark_paid",
                        px + pw*0.54, btnY, pw*0.42, 0.045,
                        "Mark as Paid", 0.28, 0.28, 0.10, 0.013)
    end
end

-- ─── CREATE INVOICE screen ───────────────────────────────────────────────────
function RoleplayPhone:drawCreateInvoice()
    local s   = self.BIG
    local px  = s.x
    local py  = s.y
    local pw  = s.w
    local ph  = s.h

    -- Header
    local headerH = 0.05
    local headerY = py + ph - 0.055 - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)
    self:drawButton("btn_back", px+0.010, headerY+0.010, 0.055, 0.030,
                    "< Back", 0.18, 0.20, 0.28, 0.011)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw/2, headerY + 0.016, 0.015, "CREATE INVOICE")

    local col1X = px + 0.015
    local colW  = pw - 0.030
    local curY  = headerY - 0.015
    local fldH  = 0.050

    -- ── To Farm selector ──
    curY = curY - fldH - 0.008
    local farms   = self:getAvailableFarms()
    local farm    = farms[self.form.toFarmIndex] or farms[1]
    local farmName = farm and farm.name or "Unknown"

    self:drawRect(col1X, curY, colW, fldH, 0.10, 0.14, 0.20, 1.0)
    self:drawRect(col1X, curY+fldH-0.002, colW, 0.002, 0.5, 0.6, 0.8, 0.4)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.55, 0.65, 0.80, 0.85)
    renderText(col1X + 0.010, curY + fldH - 0.016, 0.009, "SEND TO")
    setTextColor(1, 1, 1, 1)
    renderText(col1X + 0.010, curY + 0.010, 0.013, farmName)

    -- Arrow buttons
    local arrowW = 0.030
    self:drawButton("farm_prev", col1X + colW - arrowW*2 - 0.008, curY + 0.010,
                    arrowW, 0.028, "<", 0.20, 0.22, 0.32, 0.012)
    self:drawButton("farm_next", col1X + colW - arrowW - 0.004, curY + 0.010,
                    arrowW, 0.028, ">", 0.20, 0.22, 0.32, 0.012)

    -- ── Category selector ──
    curY = curY - fldH - 0.008
    local cats = InvoiceManager.categories
    local cat  = cats[self.form.categoryIndex] or "Other"
    local catDisplay = cat
    if #catDisplay > 30 then catDisplay = catDisplay:sub(1,28) .. ".." end

    self:drawRect(col1X, curY, colW, fldH, 0.10, 0.14, 0.20, 1.0)
    self:drawRect(col1X, curY+fldH-0.002, colW, 0.002, 0.5, 0.6, 0.8, 0.4)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.55, 0.65, 0.80, 0.85)
    renderText(col1X + 0.010, curY + fldH - 0.016, 0.009, "CATEGORY")
    setTextColor(1, 1, 1, 1)
    renderText(col1X + 0.010, curY + 0.010, 0.012, catDisplay)

    self:drawButton("cat_prev", col1X + colW - arrowW*2 - 0.008, curY + 0.010,
                    arrowW, 0.028, "<", 0.20, 0.22, 0.32, 0.012)
    self:drawButton("cat_next", col1X + colW - arrowW - 0.004, curY + 0.010,
                    arrowW, 0.028, ">", 0.20, 0.22, 0.32, 0.012)

    -- ── Amount field ──
    curY = curY - fldH - 0.008
    self:drawField("field_amount", col1X, curY, colW, fldH,
                   "AMOUNT ($)", self.form.amount,
                   self.form.activeField == "amount")

    -- ── Due Date field ──
    curY = curY - fldH - 0.008
    self:drawField("field_dueDate", col1X, curY, colW, fldH,
                   "DUE DATE (e.g. Day 45)", self.form.dueDate,
                   self.form.activeField == "dueDate")

    -- ── Description field ──
    curY = curY - fldH - 0.008
    self:drawField("field_description", col1X, curY, colW, fldH,
                   "DESCRIPTION", self.form.description,
                   self.form.activeField == "description")

    -- ── Notes field ──
    curY = curY - fldH - 0.008
    self:drawField("field_notes", col1X, curY, colW, fldH,
                   "NOTES (optional)", self.form.notes,
                   self.form.activeField == "notes")

    -- ── Send button ──
    local sendY = py + 0.015
    self:drawButton("btn_send_invoice",
                    col1X, sendY, colW, 0.048,
                    "SEND INVOICE", 0.10, 0.38, 0.18, 0.015)
end

-- ─── Mouse event ──────────────────────────────────────────────────────────────
function RoleplayPhone:mouseEvent(posX, posY, isDown, isUp, button)
    self.mouseX = posX
    self.mouseY = posY

    if self.state == self.STATE.CLOSED then return end
    if not isDown or button ~= Input.MOUSE_BUTTON_LEFT then return end

    -- Check hitboxes
    for _, hb in ipairs(self.hitboxes) do
        if self:hitTest(posX, posY, hb.x, hb.y, hb.w, hb.h) then
            self:onHitboxClicked(hb)
            return true
        end
    end

    -- Click outside phone body closes it (HOME state only)
    if self.state == self.STATE.HOME then
        local p = self.PHONE
        if not self:hitTest(posX, posY, p.x-0.006, p.y-0.006, p.w+0.012, p.h+0.012) then
            self:close()
            return true
        end
    end
end

function RoleplayPhone:onHitboxClicked(hb)
    -- App icons (home screen)
    if hb.id:sub(1,4) == "app_" and hb.data and hb.data.state then
        self.state = hb.data.state
        return
    end

    -- Back button
    if hb.id == "btn_back" then
        if self.state == self.STATE.INVOICE_CREATE then
            self.state = self.STATE.INVOICES_LIST
        elseif self.state == self.STATE.INVOICE_DETAIL then
            self.state = self.STATE.INVOICES_LIST
        else
            self:goHome()
        end
        return
    end

    -- Tabs
    if hb.id == "tab_inbox"  then self.currentTab = self.TAB.INBOX;  return end
    if hb.id == "tab_outbox" then self.currentTab = self.TAB.OUTBOX; return end

    -- Create invoice button
    if hb.id == "btn_create_invoice" then
        self:resetForm()
        self.state = self.STATE.INVOICE_CREATE
        return
    end

    -- Invoice row -> detail view
    if hb.id == "invoice_row" and hb.data and hb.data.invoice then
        self.selectedInvoice = hb.data.invoice
        self.state = self.STATE.INVOICE_DETAIL
        return
    end

    -- Farm selector arrows
    if hb.id == "farm_prev" then
        local farms = self:getAvailableFarms()
        self.form.toFarmIndex = ((self.form.toFarmIndex - 2) % #farms) + 1
        return
    end
    if hb.id == "farm_next" then
        local farms = self:getAvailableFarms()
        self.form.toFarmIndex = (self.form.toFarmIndex % #farms) + 1
        return
    end

    -- Category selector arrows
    if hb.id == "cat_prev" then
        local n = #InvoiceManager.categories
        self.form.categoryIndex = ((self.form.categoryIndex - 2) % n) + 1
        return
    end
    if hb.id == "cat_next" then
        local n = #InvoiceManager.categories
        self.form.categoryIndex = (self.form.categoryIndex % n) + 1
        return
    end

    -- Text fields - set active field
    if hb.id == "field_amount"      then self.form.activeField = "amount";      return end
    if hb.id == "field_description" then self.form.activeField = "description"; return end
    if hb.id == "field_notes"       then self.form.activeField = "notes";       return end
    if hb.id == "field_dueDate"     then self.form.activeField = "dueDate";     return end

    -- Send invoice
    if hb.id == "btn_send_invoice" then
        self:submitInvoice()
        return
    end

    -- Mark as paid (sender)
    if hb.id == "btn_mark_paid" and self.selectedInvoice then
        self.selectedInvoice.status = "PAID"
        RoleplayPhone:saveInvoices()
        print("[RoleplayPhone] Invoice marked as paid: #" .. tostring(self.selectedInvoice.id))
        return
    end

    -- Pay invoice (recipient - money transfer placeholder for now, MP in Step 4)
    if hb.id == "btn_pay_invoice" and self.selectedInvoice then
        local inv = self.selectedInvoice
        local amount = inv.amount or 0
        local myFarmId = (g_currentMission and g_currentMission.playerFarmId) or 1
        if g_currentMission and g_currentMission.economyManager and g_currentMission.farmManager then
            local farm = g_currentMission.farmManager:getFarmById(myFarmId)
            if farm and farm.money >= amount then
                g_currentMission.economyManager:updateFarmMoney(myFarmId, -amount,
                    EconomyManager.MONEY_TYPE_OTHER, nil, nil)
                inv.status = "PAID"
                RoleplayPhone:saveInvoices()
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format("Paid $%s to %s",
                        self:formatMoney(amount),
                        "Farm " .. tostring(inv.fromFarmId)))
                print("[RoleplayPhone] Invoice paid: #" .. tostring(inv.id))
            else
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                    "Insufficient funds to pay this invoice.")
            end
        end
        return
    end
end

-- ─── Submit invoice form ──────────────────────────────────────────────────────
function RoleplayPhone:submitInvoice()
    local amount = tonumber(self.form.amount)
    if not amount or amount <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Please enter a valid amount.")
        return
    end

    local farms   = self:getAvailableFarms()
    local toFarm  = farms[self.form.toFarmIndex]
    local myFarmId = (g_currentMission and g_currentMission.playerFarmId) or 1

    if not toFarm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "No recipient farm selected.")
        return
    end

    local cats = InvoiceManager.categories
    local cat  = cats[self.form.categoryIndex] or "Other"
    local day  = (g_currentMission and g_currentMission.environment and
                  g_currentMission.environment.currentDay) or 0

    -- Generate unique ID (time-based)
    local newId = math.floor((g_currentMission and g_currentMission.time) or os.time())

    local data = {
        id          = newId,
        fromFarmId  = myFarmId,
        toFarmId    = toFarm.farmId,
        category    = cat,
        amount      = amount,
        description = self.form.description,
        notes       = self.form.notes,
        dueDate     = self.form.dueDate,
        status      = "PENDING",
        createdDate = day,
    }

    local invoice = Invoice.new(data)
    InvoiceManager:addInvoice(invoice)
    RoleplayPhone:saveInvoices()

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Invoice sent to %s for $%s",
            toFarm.name, self:formatMoney(amount)))

    print("[RoleplayPhone] Invoice created: #" .. tostring(newId))

    self:resetForm()
    self.currentTab = self.TAB.OUTBOX
    self.state = self.STATE.INVOICES_LIST
end

function RoleplayPhone:resetForm()
    self.form.toFarmIndex   = 1
    self.form.categoryIndex = 1
    self.form.amount        = ""
    self.form.description   = ""
    self.form.notes         = ""
    self.form.dueDate       = ""
    self.form.activeField   = nil
end

-- ─── Key event ────────────────────────────────────────────────────────────────
function RoleplayPhone:keyEvent(unicode, sym, modifier, isDown)
    if not isDown then return false end

    -- F7 toggle
    local isF7 = (Input.KEY_F7 ~= nil and sym == Input.KEY_F7)
                 or (Input.KEY_f7 ~= nil and sym == Input.KEY_f7)
    if isF7 then
        self:toggle()
        return true
    end

    -- Text input (only when a field is active)
    if self.form.activeField and self.state == self.STATE.INVOICE_CREATE then
        local field = self.form.activeField
        local val   = self.form[field] or ""

        -- Backspace
        if sym == Input.KEY_BackSpace then
            if #val > 0 then
                self.form[field] = val:sub(1, #val - 1)
            end
            return true
        end

        -- Printable character (unicode > 31 and < 127 = basic ASCII printable)
        if unicode and unicode > 31 and unicode < 127 then
            local maxLen = (field == "amount") and 10 or 60
            if #val < maxLen then
                self.form[field] = val .. string.char(unicode)
            end
            return true
        end

        -- Tab / Enter = advance to next field
        if sym == Input.KEY_Tab or sym == Input.KEY_Return then
            local order = { "amount", "dueDate", "description", "notes" }
            for i, f in ipairs(order) do
                if f == field then
                    self.form.activeField = order[i+1] or nil
                    break
                end
            end
            return true
        end
    end

    return false
end

-- ─── Money formatter ──────────────────────────────────────────────────────────
function RoleplayPhone:formatMoney(n)
    n = math.floor(n or 0)
    local s = tostring(n)
    local result = ""
    local count  = 0
    for i = #s, 1, -1 do
        if count > 0 and count % 3 == 0 then
            result = "," .. result
        end
        result = s:sub(i,i) .. result
        count  = count + 1
    end
    return result
end

-- ─── Mission00 hooks (same pattern as SurvivalNeeds) ─────────────────────────
Mission00.draw = Utils.appendedFunction(Mission00.draw, function(mission)
    RoleplayPhone:draw()
end)

Mission00.mouseEvent = Utils.appendedFunction(Mission00.mouseEvent,
    function(mission, posX, posY, isDown, isUp, button)
        RoleplayPhone:mouseEvent(posX, posY, isDown, isUp, button)
    end)

local _phoneKeyListener = {}
function _phoneKeyListener:keyEvent(unicode, sym, modifier, isDown)
    RoleplayPhone:keyEvent(unicode, sym, modifier, isDown)
end
addModEventListener(_phoneKeyListener)

Mission00.loadMap = Utils.appendedFunction(Mission00.loadMap, function(mission, name)
    RoleplayPhone:init()
end)
