-- scripts/RoleplayPhone.lua
-- RP Phone UI - Draw-based, no XML GUI required
-- Pattern: Mission00 appended functions

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
    CONTACT_DETAIL = 7,
    CONTACT_CREATE = 8,
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

RoleplayPhone.selectedContact = nil   -- index into ContactManager.contacts

RoleplayPhone.contactForm = {
    name        = "",
    farmName    = "",
    phone       = "",
    notes       = "",
    activeField = nil,  -- "name" | "farmName" | "phone" | "notes"
}

RoleplayPhone.pingForm = {
    selectedFarmIndex = 1,      -- which farm to ping
    selectedPreset    = 1,      -- which quick message preset
    customMessage     = "",     -- optional typed message
    activeField       = nil,    -- "customMessage" if typing
    sentMessage       = nil,    -- set after ping is sent, triggers confirmation
    sentTimer         = 0,      -- counts down to clear sentMessage
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
    self.whiteOverlay = createImageOverlay(tex .. "white.dds")
    self.iconInvoices = createImageOverlay(tex .. "icon_invoices.dds")
    self.iconContacts = createImageOverlay(tex .. "icon_contacts.dds")
    self.iconPing     = createImageOverlay(tex .. "icon_ping.dds")

    if self.whiteOverlay == nil or self.whiteOverlay == 0 then
        print("[RoleplayPhone] ERROR: failed to load white.dds")
    else
        print("[RoleplayPhone] Initialized OK")
    end
end

function RoleplayPhone:loadSavedData()
    if g_server == nil then return end
    if not g_currentMission or not g_currentMission.missionInfo then return end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if not dir then return end

    local filename = dir .. "/roleplayInvoices.xml"
    local xmlFile  = loadXMLFile("roleplayInvoicesXML", filename)
    if xmlFile and xmlFile ~= 0 then
        InvoiceSave:loadFromXML(xmlFile, "roleplayInvoices")
        delete(xmlFile)
        local count = 0
        for _ in pairs(InvoiceManager.invoices) do count = count + 1 end
        print(string.format("[RoleplayPhone] Loaded %d invoices from disk", count))
    else
        print("[RoleplayPhone] No saved invoices found (new save or first run)")
    end
end

-- ─── Open / Close ─────────────────────────────────────────────────────────────
function RoleplayPhone:toggle()
    if self.state == self.STATE.CLOSED then
        self.state = self.STATE.HOME
        self:clearFarmCache()  -- refresh farm list on each open
        g_inputBinding:setShowMouseCursor(true)
        g_currentMission.paused = true
        if g_currentMission.player then
            g_currentMission.player:setMovementEnabled(false)
        end

        -- On first open after connecting, check for pending invoices and notify
        if self.pendingInboxCheck then
            self.pendingInboxCheck = false
            local myFarmId = self:getMyFarmId()
            local unpaid = 0
            for _, inv in pairs(InvoiceManager.invoices) do
                if inv.toFarmId == myFarmId and inv.status == "PENDING" then
                    unpaid = unpaid + 1
                end
            end
            if unpaid > 0 then
                local msg = unpaid == 1
                    and "You have 1 unpaid invoice in your inbox."
                    or  string.format("You have %d unpaid invoices in your inbox.", unpaid)
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK, msg)
            end
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
    if g_currentMission.player then
        g_currentMission.player:setMovementEnabled(true)
    end
    print("[RoleplayPhone] Closed")
end

function RoleplayPhone:goHome()
    self.state = self.STATE.HOME
    self.form.activeField = nil
end

-- ─── Get local player's farmId reliably on host and client ──────────────────
-- Pattern from working FS25 mods: g_farmManager:getFarmByUserId(playerUserId)
-- playerUserId is always set on both host and client
function RoleplayPhone:getMyFarmId()
    -- Return cached value if it's still fresh (re-check every 5 seconds)
    local now = getTimeSec()
    if self.cachedFarmId and self.cachedFarmIdTime and (now - self.cachedFarmIdTime) < 30 then
        return self.cachedFarmId
    end

    local farmId = nil

    -- Primary: the correct FS25 pattern used in LeaseToOwn and other working mods
    if g_farmManager and g_currentMission and g_currentMission.playerUserId then
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
        if farm and farm.farmId and farm.farmId > 0 then
            farmId = farm.farmId
        end
    end
    -- Fallback 1: playerFarmId (works on host, may be nil on client)
    if not farmId and g_currentMission and g_currentMission.playerFarmId
    and g_currentMission.playerFarmId > 0 then
        farmId = g_currentMission.playerFarmId
    end
    -- Fallback 2: player object farmId
    if not farmId and g_currentMission and g_currentMission.player
    and g_currentMission.player.farmId
    and g_currentMission.player.farmId > 0 then
        farmId = g_currentMission.player.farmId
    end

    if not farmId then
        farmId = 1
    end

    -- Cache the result
    self.cachedFarmId = farmId
    self.cachedFarmIdTime = now
    return farmId
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
    if status == "PAID"     then return 0.10, 0.55, 0.20  end  -- green
    if status == "OVERDUE"  then return 0.70, 0.15, 0.15  end  -- red
    if status == "DUE"      then return 0.70, 0.45, 0.05  end  -- orange
    if status == "REJECTED" then return 0.55, 0.10, 0.10  end  -- dark red
    return 0.30, 0.30, 0.38                                     -- gray (PENDING)
end

-- ─── Get farms helper ─────────────────────────────────────────────────────────
function RoleplayPhone:getAvailableFarms()
    -- Return cached list if available - cache is cleared every time phone opens
    -- so this only persists during a single open session, not across opens
    if self._farmCache and #self._farmCache > 0 then
        return self._farmCache
    end

    local result = {}

    -- Host: read from farms.xml so ALL farms (even offline) are included
    if g_server ~= nil and g_currentMission and g_currentMission.missionInfo then
        local dir = g_currentMission.missionInfo.savegameDirectory
        if dir then
            local xmlFile = loadXMLFile("farmsXML", dir .. "/farms.xml")
            if xmlFile and xmlFile ~= 0 then
                local i = 0
                while true do
                    local key = string.format("farms.farm(%d)", i)
                    if not hasXMLProperty(xmlFile, key) then break end
                    local farmId = getXMLInt(xmlFile, key .. "#farmId")
                    local name   = getXMLString(xmlFile, key .. "#name")
                    if farmId and farmId ~= FarmManager.SPECTATOR_FARM_ID then
                        table.insert(result, {
                            farmId = farmId,
                            name   = (name and name ~= "") and name or ("Farm " .. tostring(farmId))
                        })
                    end
                    i = i + 1
                end
                delete(xmlFile)
            end
        end
    end

    -- Client: use knownFarms sent by host on connect (includes offline farms)
    if #result == 0 and self.knownFarms and #self.knownFarms > 0 then
        for _, farm in ipairs(self.knownFarms) do
            table.insert(result, farm)
        end
    end

    -- Last resort fallback: farmManager (only online farms)
    if #result == 0 and g_currentMission and g_currentMission.farmManager then
        for _, farm in pairs(g_currentMission.farmManager:getFarms()) do
            if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
                table.insert(result, {
                    farmId = farm.farmId,
                    name   = farm.name or ("Farm " .. tostring(farm.farmId))
                })
            end
        end
    end

    if #result == 0 then
        table.insert(result, { farmId=1, name="Farm 1" })
    end
    table.sort(result, function(a, b) return a.farmId < b.farmId end)

    -- Cache the result for this open session (cleared when phone opens)
    self._farmCache = result
    return result
end

function RoleplayPhone:clearFarmCache()
    self._farmCache = nil
end

function RoleplayPhone:getFarmName(farmId)
    if not farmId then return "Unknown" end
    -- Try farmManager first (online farms)
    if g_currentMission and g_currentMission.farmManager then
        local f = g_currentMission.farmManager:getFarmById(farmId)
        if f and f.name and f.name ~= "" then return f.name end
    end
    -- Fall back to knownFarms (sent by host on connect, includes offline farms)
    if self.knownFarms then
        for _, f in ipairs(self.knownFarms) do
            if f.farmId == farmId then return f.name end
        end
    end
    return "Farm " .. tostring(farmId)
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
     elseif self.state == self.STATE.CONTACTS then
        self:drawContacts()
    elseif self.state == self.STATE.CONTACT_DETAIL then
        self:drawContactDetail()
    elseif self.state == self.STATE.CONTACT_CREATE then
        self:drawContactCreate()
    elseif self.state == self.STATE.PING then
        self:drawPing()
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
    local myFarmId = self:getMyFarmId()
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

    -- Get farm names - check farmManager first, then knownFarms for offline farms
    local fromName = self:getFarmName(inv.fromFarmId)
    local toName   = self:getFarmName(inv.toFarmId)

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
    local myFarmId = self:getMyFarmId()

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

    -- Reject button (shown to recipient if still PENDING)
    if inv.toFarmId == myFarmId and inv.status == "PENDING" then
        self:drawButton("btn_reject_invoice",
                        px + pw*0.54, btnY, pw*0.42, 0.045,
                        "Reject", 0.42, 0.10, 0.10, 0.013)
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
    local clrW = 0.028
    local clrGap = 0.005
    self:drawField("field_amount", col1X, curY, colW - clrW - clrGap, fldH,
                   "AMOUNT ($)", self.form.amount,
                   self.form.activeField == "amount")
    self:drawButton("clear_amount", col1X + colW - clrW, curY + (fldH-0.026)/2, clrW, 0.026,
                    "X", 0.45, 0.12, 0.12, 0.011)

    -- ── Due Date field ──
    curY = curY - fldH - 0.008
    self:drawField("field_dueDate", col1X, curY, colW - clrW - clrGap, fldH,
                   "DUE DATE (e.g. Day 45)", self.form.dueDate,
                   self.form.activeField == "dueDate")
    self:drawButton("clear_dueDate", col1X + colW - clrW, curY + (fldH-0.026)/2, clrW, 0.026,
                    "X", 0.45, 0.12, 0.12, 0.011)

    -- ── Description field ──
    curY = curY - fldH - 0.008
    self:drawField("field_description", col1X, curY, colW - clrW - clrGap, fldH,
                   "DESCRIPTION", self.form.description,
                   self.form.activeField == "description")
    self:drawButton("clear_description", col1X + colW - clrW, curY + (fldH-0.026)/2, clrW, 0.026,
                    "X", 0.45, 0.12, 0.12, 0.011)

    -- ── Notes field ──
    curY = curY - fldH - 0.008
    self:drawField("field_notes", col1X, curY, colW - clrW - clrGap, fldH,
                   "Notes (job details / agreement)", self.form.notes,
                   self.form.activeField == "notes")
    self:drawButton("clear_notes", col1X + colW - clrW, curY + (fldH-0.026)/2, clrW, 0.026,
                    "X", 0.45, 0.12, 0.12, 0.011)

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

    if hb.id == "clear_amount"      then self.form.amount      = ""; self.form.activeField = "amount";      return end
    if hb.id == "clear_dueDate"     then self.form.dueDate     = ""; self.form.activeField = "dueDate";     return end
    if hb.id == "clear_description" then self.form.description = ""; self.form.activeField = "description"; return end
    if hb.id == "clear_notes"       then self.form.notes       = ""; self.form.activeField = "notes";       return end

    -- Send invoice
    if hb.id == "btn_send_invoice" then
        self:submitInvoice()
        return
    end

    -- Mark as paid (sender)
    if hb.id == "btn_mark_paid" and self.selectedInvoice then
        self.selectedInvoice.status = "PAID"
        local invId = self.selectedInvoice.id
        if g_server ~= nil then
            g_server:broadcastEvent(
                InvoiceEvents.UpdateInvoiceEvent.new(invId, "PAID"))
        elseif g_client ~= nil then
            g_client:getServerConnection():sendEvent(
                InvoiceEvents.UpdateInvoiceEvent.new(invId, "PAID"))
        end
        RoleplayPhone:saveInvoices()
        print("[RoleplayPhone] Invoice marked as paid: #" .. tostring(invId))
        return
    end

    -- Reject invoice (recipient)
    if hb.id == "btn_reject_invoice" and self.selectedInvoice then
        local inv = self.selectedInvoice
        if inv.status == "PENDING" then
            inv.status = "REJECTED"
            if g_server ~= nil then
                g_server:broadcastEvent(
                    InvoiceEvents.UpdateInvoiceEvent.new(inv.id, "REJECTED"))
            elseif g_client ~= nil then
                g_client:getServerConnection():sendEvent(
                    InvoiceEvents.UpdateInvoiceEvent.new(inv.id, "REJECTED"))
            end
            RoleplayPhone:saveInvoices()
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                "Invoice rejected.")
            print("[RoleplayPhone] Invoice rejected: #" .. tostring(inv.id))
        end
        return
    end

    -- Pay invoice (recipient)
    if hb.id == "btn_pay_invoice" and self.selectedInvoice then
        local inv = self.selectedInvoice
        local amount = inv.amount or 0
        local myFarmId = self:getMyFarmId()
        local farmManager = g_currentMission and g_currentMission.farmManager or g_farmManager
        if farmManager then
            local farm = farmManager:getFarmById(myFarmId)
            if farm and farm.money >= amount then
                -- Route through server event so money transfer happens authoritatively
                if g_server ~= nil then
                    -- Host paying: run directly
                    g_currentMission:addMoney(-amount, myFarmId, MoneyType.OTHER, true, true)
                    g_currentMission:addMoney(amount, inv.fromFarmId, MoneyType.OTHER, true, true)
                    inv.status = "PAID"
                    g_server:broadcastEvent(
                        InvoiceEvents.UpdateInvoiceEvent.new(inv.id, "PAID"))
                    RoleplayPhone:saveInvoices()
                elseif g_client ~= nil then
                    -- Client paying: ask server to do the transfer
                    inv.status = "PAID"  -- optimistic local update
                    g_client:getServerConnection():sendEvent(
                        RI_PayInvoiceEvent.new(inv.id, inv.fromFarmId, myFarmId, amount))
                end
                RoleplayPhone:saveInvoices()
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format("Paid $%s to %s",
                        self:formatMoney(amount),
                        self:getFarmName(inv.fromFarmId)))
                print("[RoleplayPhone] Invoice paid: #" .. tostring(inv.id))
            else
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                    "Insufficient funds to pay this invoice.")
            end
        end
        return
    end

    -- ── Contacts list ──────────────────────────────────────────────────────
    if hb.id == "contact_row" and hb.data and hb.data.index then
        self.selectedContact = hb.data.index
        self.state = self.STATE.CONTACT_DETAIL
        return
    end

    if hb.id == "btn_add_contact" then
        self:resetContactForm()
        self.state = self.STATE.CONTACT_CREATE
        return
    end

    -- ── Contact detail ─────────────────────────────────────────────────────
    if hb.id == "btn_delete_contact" then
        if self.selectedContact then
            ContactManager:removeContact(self.selectedContact)
            self.selectedContact = nil
            RoleplayPhone:saveInvoices()
        end
        self.state = self.STATE.CONTACTS
        return
    end

    -- ── Contact create fields (focus) ──────────────────────────────────────
    if hb.id == "cf_name"     then self.contactForm.activeField = "name";     return end
    if hb.id == "cf_farmName" then self.contactForm.activeField = "farmName"; return end
    if hb.id == "cf_phone"    then self.contactForm.activeField = "phone";    return end
    if hb.id == "cf_notes"    then self.contactForm.activeField = "notes";    return end

    -- ── Contact create: save ───────────────────────────────────────────────
    if hb.id == "btn_save_contact" then
        local f = self.contactForm
        if f.name and f.name ~= "" then
            ContactManager:addContact({
                name     = f.name,
                farmName = f.farmName,
                phone    = f.phone,
                notes    = f.notes,
            })
            RoleplayPhone:saveInvoices()
        end
        self.contactForm.activeField = nil
        self.state = self.STATE.CONTACTS
        return
    end

    -- ── Ping screen ────────────────────────────────────────────────────────
    if hb.id == "ping_farm_prev" then
        local farms = self:getPingableFarms()
        local n = #farms
        if n > 0 then
            self.pingForm.selectedFarmIndex =
                ((self.pingForm.selectedFarmIndex - 2) % n) + 1
        end
        return
    end

    if hb.id == "ping_farm_next" then
        local farms = self:getPingableFarms()
        local n = #farms
        if n > 0 then
            self.pingForm.selectedFarmIndex =
                (self.pingForm.selectedFarmIndex % n) + 1
        end
        return
    end

    if hb.id:sub(1, 12) == "ping_preset_" then
        local idx = tonumber(hb.id:sub(13))
        if idx then
            self.pingForm.selectedPreset = idx
            self.pingForm.activeField    = nil
        end
        return
    end

    if hb.id == "ping_custom_field" then
        self.pingForm.activeField = "customMessage"
        return
    end

    if hb.id == "clear_ping_message" then
        self.pingForm.customMessage = ""
        self.pingForm.activeField = "customMessage"
        return
    end

    if hb.id == "btn_send_ping" then
        self:submitPing()
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
    local myFarmId = self:getMyFarmId()

    if not toFarm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "No recipient farm selected.")
        return
    end

    if toFarm.farmId == myFarmId then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "You cannot send an invoice to your own farm.")
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

    -- Route through sendEvent in all cases so server run() fires correctly
    if g_client ~= nil then
        -- MP: add locally first so sender's outbox is populated immediately
        -- then send to server so it saves and broadcasts to other clients
        InvoiceManager:addInvoice(invoice)
        g_client:getServerConnection():sendEvent(
            InvoiceEvents.SendInvoiceEvent.new(invoice))
    else
        -- Singleplayer: no network, add directly and save
        InvoiceManager:addInvoice(invoice)
        RoleplayPhone:saveInvoices()
    end

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

    -- Contact create text input
    if self.contactForm.activeField and self.state == self.STATE.CONTACT_CREATE then
        local field = self.contactForm.activeField
        local val   = self.contactForm[field] or ""

        -- Backspace
        if sym == Input.KEY_BackSpace then
            if #val > 0 then
                self.contactForm[field] = val:sub(1, #val - 1)
            end
            return true
        end

        -- Printable character
        if unicode and unicode > 31 and unicode < 127 then
            if #val < 60 then
                self.contactForm[field] = val .. string.char(unicode)
            end
            return true
        end
    end

    -- Ping custom message text input
    if self.pingForm.activeField and self.state == self.STATE.PING then
        local val = self.pingForm.customMessage or ""

        -- Backspace
        if sym == Input.KEY_BackSpace then
            if #val > 0 then
                self.pingForm.customMessage = val:sub(1, #val - 1)
            end
            return true
        end

        -- Printable character
        if unicode and unicode > 31 and unicode < 127 then
            if #val < 80 then
                self.pingForm.customMessage = val .. string.char(unicode)
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

-- ─── CONTACTS LIST screen ─────────────────────────────────────────────────────
function RoleplayPhone:drawContacts()
    local s  = self.BIG
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    self:drawBigScreen()

    local contentY = py + ph - 0.055

    -- Header bar
    local headerH = 0.05
    local headerY = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)

    -- Back button
    self:drawButton("btn_back", px + 0.010, headerY + 0.010, 0.055, 0.030,
        "< Back", 0.18, 0.20, 0.28, 0.011)

    -- Title
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.30, 0.016, "Contacts")

    -- Add button (top-right)
    self:drawButton("btn_add_contact", px + pw - 0.092, headerY + 0.010, 0.080, 0.030,
        "+ Add", 0.10, 0.38, 0.18, 0.012)

    -- ── Contact list ──────────────────────────────────────────────────────────
    local listY    = headerY - 0.008
    local rowH     = 0.056
    local rowGap   = 0.003
    local contacts = ContactManager.contacts

    if #contacts == 0 then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(0.50, 0.52, 0.60, 0.8)
        renderText(px + pw / 2, py + ph / 2, 0.013,
            "No contacts yet.  Tap  + Add  to save one.")
        return
    end

    for i, c in ipairs(contacts) do
        local rowY = listY - (i - 1) * (rowH + rowGap)
        if rowY - rowH < py then break end   -- clip below screen

        -- Alternating row shade
        local shade = (i % 2 == 0) and 0.115 or 0.095
        self:drawRect(px, rowY - rowH, pw, rowH, shade, shade + 0.015, shade + 0.030, 1.0)

        -- Avatar square (first initial)
        local avSize = 0.034
        local avX    = px + 0.012
        local avY    = rowY - rowH + (rowH - avSize) / 2
        self:drawRect(avX, avY, avSize, avSize, 0.15, 0.32, 0.60, 1.0)
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(1, 1, 1, 1)
        renderText(avX + avSize / 2, avY + avSize * 0.20, 0.018,
            string.upper(string.sub(c.name or "?", 1, 1)))

        -- Name
        local textX = avX + avSize + 0.012
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(true)
        setTextColor(0.90, 0.92, 1.0, 1.0)
        renderText(textX, rowY - rowH + rowH * 0.52, 0.013, c.name or "Unknown")

        -- Farm name (sub-line)
        setTextBold(false)
        setTextColor(0.52, 0.62, 0.78, 0.9)
        renderText(textX, rowY - rowH + rowH * 0.18, 0.011,
            (c.farmName ~= "" and c.farmName) or "No farm")

        -- Phone (right side, green tint)
        if c.phone and c.phone ~= "" then
            setTextAlignment(RenderText.ALIGN_RIGHT)
            setTextColor(0.38, 0.72, 0.38, 0.9)
            renderText(px + pw - 0.014, rowY - rowH + rowH * 0.38, 0.011, c.phone)
        end

        -- Chevron hint
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(0.40, 0.42, 0.55, 0.6)
        renderText(px + pw - 0.008, rowY - rowH + rowH * 0.38, 0.013, ">")

        -- Hitbox for the whole row
        self:addHitbox("contact_row", px, rowY - rowH, pw, rowH, { index = i })
    end
end


-- ─── CONTACT DETAIL screen ────────────────────────────────────────────────────
function RoleplayPhone:drawContactDetail()
    if not self.selectedContact then
        self.state = self.STATE.CONTACTS
        return
    end

    local c = ContactManager:getContact(self.selectedContact)
    if not c then
        self.state = self.STATE.CONTACTS
        return
    end

    local s  = self.BIG
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    self:drawBigScreen()

    local contentY = py + ph - 0.055

    -- Header bar
    local headerH = 0.05
    local headerY = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)

    self:drawButton("btn_back", px + 0.010, headerY + 0.010, 0.055, 0.030,
        "< Back", 0.18, 0.20, 0.28, 0.011)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.30, 0.016, "Contact")

    -- Large avatar
    local avSize = 0.065
    local avX    = px + pw / 2 - avSize / 2
    local avY    = headerY - 0.020 - avSize
    self:drawRect(avX, avY, avSize, avSize, 0.15, 0.32, 0.60, 1.0)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(avX + avSize / 2, avY + avSize * 0.22, 0.032,
        string.upper(string.sub(c.name or "?", 1, 1)))

    -- Name + farm
    local nameY = avY - 0.018
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(0.90, 0.93, 1.0, 1.0)
    renderText(px + pw / 2, nameY, 0.018, c.name or "Unknown")

    setTextBold(false)
    setTextColor(0.52, 0.62, 0.78, 0.9)
    renderText(px + pw / 2, nameY - 0.022, 0.013,
        (c.farmName ~= "" and c.farmName) or "No farm set")

    -- Divider
    local divY = nameY - 0.045
    self:drawRect(px + 0.030, divY, pw - 0.060, 0.001, 0.28, 0.32, 0.50, 0.4)

    -- Info rows
    local iX    = px + 0.035
    local iW    = pw - 0.070
    local lineH = 0.042
    local iY    = divY - 0.012

    -- Phone row
    iY = iY - lineH
    self:drawRect(iX, iY, iW, lineH, 0.10, 0.13, 0.20, 1.0)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.48, 0.58, 0.72, 0.8)
    renderText(iX + 0.010, iY + lineH * 0.64, 0.009, "PHONE")
    setTextColor(0.90, 0.95, 1.0, 1.0)
    renderText(iX + 0.010, iY + lineH * 0.20, 0.013,
        (c.phone ~= "" and c.phone) or "—")

    -- Notes row
    local notesH = 0.060
    iY = iY - notesH - 0.006
    self:drawRect(iX, iY, iW, notesH, 0.10, 0.13, 0.20, 1.0)
    setTextColor(0.48, 0.58, 0.72, 0.8)
    renderText(iX + 0.010, iY + notesH * 0.82, 0.009, "NOTES")
    setTextColor(0.88, 0.92, 1.0, 1.0)
    renderText(iX + 0.010, iY + notesH * 0.35, 0.012,
        (c.notes ~= "" and c.notes) or "—")

    -- Delete button (bottom, red)
    iY = iY - 0.038 - 0.018
    self:drawButton("btn_delete_contact", iX, iY, iW, 0.036,
        "Delete Contact", 0.48, 0.10, 0.10, 0.013)
end


-- ─── CONTACT CREATE screen ────────────────────────────────────────────────────
function RoleplayPhone:drawContactCreate()
    local s  = self.BIG
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    self:drawBigScreen()

    local contentY = py + ph - 0.055

    -- Header bar
    local headerH = 0.05
    local headerY = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)

    self:drawButton("btn_back", px + 0.010, headerY + 0.010, 0.055, 0.030,
        "< Back", 0.18, 0.20, 0.28, 0.011)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.30, 0.016, "New Contact")

    -- Fields
    local f    = self.contactForm
    local fX   = px + 0.030
    local fW   = pw - 0.060
    local fH   = 0.044
    local fGap = 0.010
    local fY   = headerY - 0.018

    fY = fY - fH
    self:drawField("cf_name",     fX, fY, fW, fH, "Name",         f.name,     f.activeField == "name")
    fY = fY - fH - fGap
    self:drawField("cf_farmName", fX, fY, fW, fH, "Farm Name",    f.farmName, f.activeField == "farmName")
    fY = fY - fH - fGap
    self:drawField("cf_phone",    fX, fY, fW, fH, "Phone (RP #)", f.phone,    f.activeField == "phone")
    fY = fY - fH - fGap
    self:drawField("cf_notes",    fX, fY, fW, fH, "Notes",        f.notes,    f.activeField == "notes")

    -- Validation hint
    if f.name == "" then
        fY = fY - 0.020
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(0.80, 0.55, 0.20, 0.85)
        renderText(px + pw / 2, fY + 0.006, 0.010, "Name is required")
    end

    -- Save button
    fY = fY - fH - 0.012
    local canSave = f.name and f.name ~= ""
    local btnR = canSave and 0.10 or 0.20
    local btnG = canSave and 0.38 or 0.22
    local btnB = canSave and 0.18 or 0.22
    self:drawButton("btn_save_contact", fX, fY, fW, fH,
        "Save Contact", btnR, btnG, btnB, 0.013)
end


-- ─── resetContactForm helper ──────────────────────────────────────────────────
function RoleplayPhone:resetContactForm()
    self.contactForm = {
        name        = "",
        farmName    = "",
        phone       = "",
        notes       = "",
        activeField = nil,
    }
end


-- ─── Quick message presets ────────────────────────────────────────────────────
RoleplayPhone.PING_PRESETS = {
    "Come to my location",
    "Job available for you",
    "Invoice ready to pay",
    "Need help ASAP",
    "Delivery ready for pickup",
    "All done here",
    "Custom message...",
}


-- ─── Helper: farms you can ping (everyone except yourself) ────────────────────
function RoleplayPhone:getPingableFarms()
    local myFarmId = self:getMyFarmId()
    local all    = self:getAvailableFarms()
    local result = {}
    for _, farm in ipairs(all) do
        if farm.farmId ~= myFarmId then
            table.insert(result, farm)
        end
    end
    -- Fallback: if still empty, try farmManager directly for connected farms
    if #result == 0 and g_currentMission and g_currentMission.farmManager then
        for _, farm in pairs(g_currentMission.farmManager:getFarms()) do
            if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID
            and farm.farmId ~= myFarmId then
                table.insert(result, {
                    farmId = farm.farmId,
                    name   = farm.name or ("Farm " .. tostring(farm.farmId))
                })
            end
        end
        table.sort(result, function(a, b) return a.farmId < b.farmId end)
    end
    return result
end


-- ─── Submit ping ──────────────────────────────────────────────────────────────
function RoleplayPhone:submitPing()
    local farms = self:getPingableFarms()
    local farm  = farms[self.pingForm.selectedFarmIndex]
    if not farm then return end

    local presets  = RoleplayPhone.PING_PRESETS
    local isCustom = (self.pingForm.selectedPreset == #presets)

    local message
    if isCustom then
        message = self.pingForm.customMessage
        if not message or message == "" then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                "Please type a message before sending.")
            return
        end
    else
        message = presets[self.pingForm.selectedPreset] or presets[1]
    end

    local myFarmId = self:getMyFarmId()

    -- Broadcast ping over the network so all clients receive it
    if g_server ~= nil then
        g_server:broadcastEvent(
            InvoiceEvents.PingEvent.new(myFarmId, farm.farmId, message))
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(
            InvoiceEvents.PingEvent.new(myFarmId, farm.farmId, message))
    else
        -- Single player fallback
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("PING >> %s: %s", farm.name, message))
    end

    print(string.format("[RoleplayPhone] Ping sent to %s: %s", farm.name, message))

    -- Show confirmation on screen for ~3 seconds
    self.pingForm.sentMessage   = string.format("Pinged %s!", farm.name)
    self.pingForm.sentTimer     = 180
    self.pingForm.customMessage = ""
    self.pingForm.activeField   = nil
end


-- ─── PING screen ─────────────────────────────────────────────────────────────
function RoleplayPhone:drawPing()
    local s  = self.BIG
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    self:drawBigScreen()

    local contentY = py + ph - 0.055

    -- Header bar
    local headerH = 0.05
    local headerY = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.08, 0.20, 0.22, 1.0)

    self:drawButton("btn_back", px + 0.010, headerY + 0.010, 0.055, 0.030,
        "< Back", 0.10, 0.22, 0.24, 0.011)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.30, 0.016, "Ping")

    local cy = headerY - 0.018

    -- ── Farm selector ─────────────────────────────────────────────────────────
    local farms     = self:getPingableFarms()
    local farmCount = #farms
    local selFarm   = farms[self.pingForm.selectedFarmIndex]
    local farmName  = selFarm and selFarm.name or "No farms"

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.45, 0.65, 0.70, 0.85)
    renderText(px + 0.018, cy, 0.010, "SEND TO")
    cy = cy - 0.030

    local rowH = 0.046
    self:drawRect(px + 0.018, cy - rowH, pw - 0.036, rowH, 0.08, 0.18, 0.20, 1.0)

    self:drawButton("ping_farm_prev",
        px + 0.018, cy - rowH, 0.038, rowH,
        "<", 0.10, 0.22, 0.24, 0.016)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(0.80, 0.96, 1.0, 1.0)
    renderText(px + pw / 2, cy - rowH + rowH * 0.30, 0.015, farmName)

    setTextBold(false)
    setTextColor(0.40, 0.55, 0.58, 0.7)
    renderText(px + pw / 2, cy - rowH + rowH * 0.68, 0.009,
        string.format("%d / %d", self.pingForm.selectedFarmIndex, farmCount))

    self:drawButton("ping_farm_next",
        px + pw - 0.056, cy - rowH, 0.038, rowH,
        ">", 0.10, 0.22, 0.24, 0.016)

    cy = cy - rowH - 0.022

    -- ── Quick message presets ─────────────────────────────────────────────────
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.45, 0.65, 0.70, 0.85)
    renderText(px + 0.018, cy, 0.010, "MESSAGE")
    cy = cy - 0.010

    local presets        = RoleplayPhone.PING_PRESETS
    local presetH        = 0.038
    local presetGap      = 0.004
    local isCustomSelected = (self.pingForm.selectedPreset == #presets)

    for i, preset in ipairs(presets) do
        cy = cy - presetH

        local isSelected = (self.pingForm.selectedPreset == i)

        local br = isSelected and 0.08 or 0.06
        local bg = isSelected and 0.26 or 0.14
        local bb = isSelected and 0.28 or 0.16
        self:drawRect(px + 0.018, cy, pw - 0.036, presetH, br, bg, bb, 1.0)

        -- Selected indicator bar on left edge
        if isSelected then
            self:drawRect(px + 0.018, cy, 0.004, presetH, 0.20, 0.80, 0.85, 1.0)
        end

        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(isSelected)
        setTextColor(0.85, 0.95, 1.0, isSelected and 1.0 or 0.65)
        renderText(px + 0.030, cy + presetH * 0.28, 0.012, preset)

        self:addHitbox("ping_preset_" .. i, px + 0.018, cy, pw - 0.036, presetH, {})
        cy = cy - presetGap
    end

    -- Custom message input (only when last preset selected)
    if isCustomSelected then
        cy = cy - 0.008
        local clrW = 0.028
        local clrGap = 0.005
        local fldW = pw - 0.036
        self:drawField("ping_custom_field",
            px + 0.018, cy - 0.044, fldW - clrW - clrGap, 0.044,
            "Type your message",
            self.pingForm.customMessage,
            self.pingForm.activeField == "customMessage")
        self:drawButton("clear_ping_message",
            px + 0.018 + fldW - clrW, cy - 0.044 + (0.044 - 0.026)/2, clrW, 0.026,
            "X", 0.45, 0.12, 0.12, 0.011)
        cy = cy - 0.044 - 0.008
    end

    cy = cy - 0.012

    -- ── Send button ───────────────────────────────────────────────────────────
    local canSend = farmCount > 0
    self:drawButton("btn_send_ping",
        px + 0.018, cy - 0.046, pw - 0.036, 0.046,
        "Send Ping",
        canSend and 0.06 or 0.18,
        canSend and 0.32 or 0.20,
        canSend and 0.34 or 0.20,
        0.014)
    cy = cy - 0.046

    -- ── Sent confirmation flash ───────────────────────────────────────────────
    if self.pingForm.sentMessage and self.pingForm.sentTimer > 0 then
        self.pingForm.sentTimer = self.pingForm.sentTimer - 1

        local alpha = math.min(1.0, self.pingForm.sentTimer / 30)
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(0.90, 0.15, 0.15, alpha)
        renderText(px + pw / 2, cy - 0.024, 0.021,
            "Sent: " .. self.pingForm.sentMessage)

        if self.pingForm.sentTimer <= 0 then
            self.pingForm.sentMessage = nil
        end
    end
end


-- ─── Mission00 hooks ─────────────────────────────────────────────────────────
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
    RoleplayPhone:loadSavedData()

    -- Login notification: count unpaid invoices for this farm
    local myFarmId = RoleplayPhone:getMyFarmId()
    local unpaid = 0
    for _, inv in pairs(InvoiceManager.invoices) do
        if inv.toFarmId == myFarmId and inv.status == "PENDING" then
            unpaid = unpaid + 1
        end
    end
    if unpaid > 0 then
        local msg = unpaid == 1
            and "You have 1 unpaid invoice in your inbox."
            or  string.format("You have %d unpaid invoices in your inbox.", unpaid)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK, msg)
    end
end)

-- Hook into FS25's save system so our file is written as part of normal game save
-- This prevents the game from deleting our file on exit
Mission00.saveSavegame = Utils.appendedFunction(Mission00.saveSavegame,
    function(mission)
        if g_server ~= nil then
            RoleplayPhone:saveInvoices()
        end
    end
)

-- When a client finishes loading, host sends them the full farm list
-- and all existing invoices so they're fully in sync
Mission00.onConnectionFinishedLoading = Utils.appendedFunction(
    Mission00.onConnectionFinishedLoading,
    function(mission, connection)
        if g_server == nil then return end  -- only host does this

        -- Send full farm list
        local farms = RoleplayPhone:getAvailableFarms()
        if farms and #farms > 0 then
            connection:sendEvent(RI_FarmListEvent.new(farms))
            print(string.format("[RoleplayPhone] Sent farm list (%d farms) to new client", #farms))
        end

        -- Send all existing invoices so client inbox is populated
        -- showNotification=false because farmId isn't resolved yet at connect time
        -- We send a summary notification via RI_FarmListEvent instead
        local count = 0
        for _, inv in pairs(InvoiceManager.invoices) do
            connection:sendEvent(RI_SendInvoiceEvent.new(inv, false))
            count = count + 1
        end
        if count > 0 then
            print(string.format("[RoleplayPhone] Sent %d existing invoices to new client", count))
        end
    end
)
