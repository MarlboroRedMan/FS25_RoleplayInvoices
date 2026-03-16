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
    CALLS          = 6,
    CONTACT_DETAIL = 7,
    CONTACT_CREATE = 8,
    CALL_OUTGOING  = 9,
    CALL_INCOMING  = 10,
    CALL_ACTIVE    = 11,
    SETTINGS       = 12,
    MESSAGE_THREAD = 13,
}

-- ─── Tab constants ────────────────────────────────────────────────────────────
RoleplayPhone.TAB = {
    INBOX  = 1,
    OUTBOX = 2,
}

-- ─── Runtime state ────────────────────────────────────────────────────────────
RoleplayPhone.state          = RoleplayPhone.STATE.CLOSED
RoleplayPhone.isOpen         = false   -- true while phone UI is visible (context pushed)
RoleplayPhone.phoneContextEventId = nil  -- eventId of close action registered in RI_PHONE_UI context
RoleplayPhone.currentTab     = RoleplayPhone.TAB.INBOX
RoleplayPhone.mouseX         = 0
RoleplayPhone.mouseY         = 0
RoleplayPhone.whiteOverlay   = nil
RoleplayPhone.wallpaper      = nil  -- home screen wallpaper texture
RoleplayPhone.iconInvoices   = nil
RoleplayPhone.iconContacts   = nil
RoleplayPhone.iconCalls      = nil
RoleplayPhone.iconSettings              = nil
RoleplayPhone.callActionEventId         = nil
RoleplayPhone.incomingCallActionEventId = nil
RoleplayPhone.backspaceEventId          = nil
RoleplayPhone.callHistory               = {}  -- current session only, cleared on game restart
RoleplayPhone.hitboxes       = {}   -- rebuilt every draw frame

-- ─── Home screen page system ──────────────────────────────────────────────────
RoleplayPhone.homePage       = 1    -- current page (1 = home with clock/weather)
RoleplayPhone.homePageCount  = 2    -- total pages (grows as we add apps)

-- ─── App grid definition (page 2+) ───────────────────────────────────────────
-- Each entry: { id, label, color {r,g,b}, icon (optional overlay ref) }
RoleplayPhone.GRID_APPS = {
    -- Page 2
    { id="weather",  label="Weather",  page=2, color={0.15, 0.45, 0.75} },
    { id="market",   label="Market",   page=2, color={0.20, 0.60, 0.30} },
}

-- ─── Dock apps (always visible, bottom) ──────────────────────────────────────
-- These are the 3 core apps pinned to the dock on every page
RoleplayPhone.DOCK_APPS = {
    { id="invoices", label="Invoices", color={0.25, 0.25, 0.30} },
    { id="contacts", label="Contacts", color={0.10, 0.50, 0.30} },
    { id="calls",    label="Calls",    color={0.10, 0.30, 0.65} },
    { id="settings", label="Settings", color={0.35, 0.25, 0.45} },
}

-- ─── Player settings (cosmetic, per-player, saved to modSettings XML) ─────────
RoleplayPhone.settings = {
    timeFormat     = "12",   -- "12" or "24"
    tempUnit       = "F",    -- "F" or "C"
    wallpaperIndex = 1,      -- 1-6 colour swatch
    batteryVisible = true,   -- show battery widget in status bar
}

-- ─── Battery widget (cosmetic, purely visual) ─────────────────────────────────
RoleplayPhone.battery = {
    level      = 100.0,   -- 0-100
    drainRate  = 0.04,    -- % per second while open (~40 min to drain)
    callRate   = 0.08,    -- % per second during active call (~20 min to drain)
    chargeRate = 0.20,    -- % per second while closed (~8 min to full)
}

-- ─── Wallpaper colour palettes ────────────────────────────────────────────────
-- Index 1 = Countryside (uses wallpaper.dds texture if present)
-- Index 2+ = solid colour swatches
RoleplayPhone.WALLPAPERS = {
    { name="Countryside", texture=true,  r=0.08, g=0.12, b=0.06 },  -- 1 fallback tint if no .dds
    { name="Midnight",    texture=false, r=0.07, g=0.07, b=0.14 },  -- 2
    { name="Forest",      texture=false, r=0.04, g=0.14, b=0.07 },  -- 3
    { name="Slate",       texture=false, r=0.10, g=0.10, b=0.10 },  -- 4
    { name="Ember",       texture=false, r=0.16, g=0.07, b=0.04 },  -- 5
    { name="Dusk",        texture=false, r=0.14, g=0.05, b=0.18 },  -- 6
    { name="Ocean",       texture=false, r=0.04, g=0.12, b=0.20 },  -- 7
}

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

-- ─── Message storage & compose ────────────────────────────────────────────────
-- messages[contactIndex] = { { fromFarmId, senderName, text, gameDay, sent }, ... }
RoleplayPhone.messages       = {}
RoleplayPhone.messageCompose = { text = "", active = false }
RoleplayPhone.unreadMessages = {}  -- unreadMessages[contactIndex] = count

-- ─── Call state ───────────────────────────────────────────────────────────────
RoleplayPhone.call = {
    contactName  = "",    -- display name of the other party
    contactNum   = "",    -- their phone number
    toFarmId     = 0,     -- farmId of the other party
    fromFarmId   = 0,     -- farmId of caller (for incoming)
    startTime    = 0,     -- g_currentMission.time when call connected
    ringSample   = nil,   -- sound handle
    prevState    = 7,     -- STATE to return to after call (default CONTACT_DETAIL)
}

RoleplayPhone.contactForm = {
    name        = "",
    farmName    = "",
    phone       = "",
    notes       = "",
    activeField = nil,  -- "name" | "farmName" | "phone" | "notes"
}


-- ─── Layout: small phone (HOME screen) ───────────────────────────────────────
RoleplayPhone.PHONE = {
    x = 0.390, y = 0.05,
    w = 0.220, h = 0.65,
}

-- ─── Layout: big screen (INVOICES, CONTACTS, PING) ───────────────────────────
RoleplayPhone.BIG = {
    x = 0.390, y = 0.05,
    w = 0.220, h = 0.65,
}

-- ─── Init ─────────────────────────────────────────────────────────────────────
function RoleplayPhone:init()
    local tex = modDirectory .. "textures/"
    self.whiteOverlay = createImageOverlay(tex .. "white.dds")
    self.wallpaper    = createImageOverlay(tex .. "wallpaper.dds")
    self.iconInvoices = createImageOverlay(tex .. "icon_invoices.dds")
    self.iconContacts = createImageOverlay(tex .. "icon_contacts.dds")
    self.iconCalls    = createImageOverlay(tex .. "recent_call.dds")
    self.iconSettings = createImageOverlay(tex .. "icon_settings.dds")

    if self.whiteOverlay == nil or self.whiteOverlay == 0 then
        print("[RoleplayPhone] ERROR: failed to load white.dds")
    else
        print("[RoleplayPhone] Initialized OK")
    end
    if self.wallpaper == nil or self.wallpaper == 0 then
        print("[RoleplayPhone] WARN: wallpaper.dds not found - using solid background")
        self.wallpaper = nil
    end

    -- Load ring tone (optional — won't error if missing)
    local soundFile = modDirectory .. "sounds/ringtone.ogg"
    self.ringSample = createSample("RP_ringtone")
    if self.ringSample and self.ringSample ~= 0 then
        loadSample(self.ringSample, soundFile, false)  -- false = not 3D positional
        print("[RoleplayPhone] Ringtone loaded OK")
    else
        self.ringSample = nil
        print("[RoleplayPhone] WARN: ringtone.ogg not found - calls will be silent")
    end

    -- Init notification system — shares our white overlay for drawing
    NotificationManager:init(self.whiteOverlay, modDirectory)

    -- Load per-player cosmetic settings (time format, temp, wallpaper, battery)
    self:loadSettings()
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

    -- Sync host's own contacts into farmContacts so they're available for connect sync
    local hostFarmId = self:getMyFarmId()
    if hostFarmId and hostFarmId > 0 then
        ContactManager.farmContacts[hostFarmId] = ContactManager.contacts
        print(string.format("[RoleplayPhone] Bootstrapped farmContacts[%d] with %d contacts",
            hostFarmId, #ContactManager.contacts))
    end
end

-- ─── Open / Close ─────────────────────────────────────────────────────────────
function RoleplayPhone:toggle()
    print("[RoleplayPhone] toggle() called — state=" .. tostring(self.state))
    -- Debounce: axisType=HALF fires on both key press AND release (~100ms apart).
    -- Use getTimeSec() (real clock) not g_currentMission.time — the latter can
    -- return 0 or not advance on MP clients, causing debounce to never expire.
    local now = getTimeSec()
    if self.lastToggleTime and (now - self.lastToggleTime) < 0.4 then return end
    self.lastToggleTime = now

    if self.state == self.STATE.CLOSED then
        self.state = self.STATE.HOME
        self.isOpen = true
        self:clearFarmCache()  -- refresh farm list on each open

        -- Show cursor and freeze player input (purely client-local, MP-safe)
        -- setContext pushes an empty context so ALL game input is blocked.
        -- We then re-register only RI_OPEN_PHONE in that context so F6 can close.
        g_inputBinding:setShowMouseCursor(true)
        g_inputBinding:setContext("RI_PHONE_UI", true, false)
        local _, evId = g_inputBinding:registerActionEvent(
            "RI_OPEN_PHONE", self, self.close,
            false,  -- triggerUp:     don't fire on key release
            true,   -- triggerDown:   fire on key press
            false,  -- triggerAlways: don't fire every frame
            true    -- startActive:   enabled immediately
        )
        if evId then
            g_inputBinding:setActionEventTextVisibility(evId, false)
            self.phoneContextEventId = evId
        end

        -- Register backspace in RI_PHONE_UI context so it works while phone is open
        local _, bsId = g_inputBinding:registerActionEvent(
            "RI_BACKSPACE", self, self.handleBackspace,
            false, true, false, true)
        if bsId then
            g_inputBinding:setActionEventTextVisibility(bsId, false)
            self.backspaceEventId = bsId
            print("[RoleplayPhone] RI_BACKSPACE registered OK: " .. tostring(bsId))
        else
            print("[RoleplayPhone] WARNING: RI_BACKSPACE registration FAILED")
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
                    and "You have 1 unpaid invoice."
                    or  string.format("You have %d unpaid invoices.", unpaid)
                NotificationManager:push("info", msg)
            end
        end

        -- Clear badge when phone opens
        NotificationManager:clearBadge()
        print("[RoleplayPhone] Opened")
    else
        self:close()
    end
end

function RoleplayPhone:close()
    if not self.isOpen then return end  -- prevent double-close
    self.isOpen = false
    self.state = self.STATE.CLOSED
    self.form.activeField = nil

    -- Hide cursor and restore full player input
    g_inputBinding:setShowMouseCursor(false)
    if self.phoneContextEventId then
        g_inputBinding:removeActionEvent(self.phoneContextEventId)
        self.phoneContextEventId = nil
    end
    if self.backspaceEventId then
        g_inputBinding:removeActionEvent(self.backspaceEventId)
        self.backspaceEventId = nil
    end
    g_inputBinding:revertContext(true)

    print("[RoleplayPhone] Closed")
end

function RoleplayPhone:goHome()
    self.state = self.STATE.HOME
    self.form.activeField = nil
end

-- ─── Store an incoming message in the right thread ────────────────────────────
function RoleplayPhone:receiveMessage(contactKey, fromFarmId, senderName, text, gameDay, sent)
    if not self.messages[contactKey] then
        self.messages[contactKey] = {}
    end
    table.insert(self.messages[contactKey], {
        fromFarmId  = fromFarmId,
        senderName  = senderName,
        text        = text,
        gameDay     = gameDay or 0,
        sent        = sent or false,
    })
    -- Notify if not currently viewing this thread
    if sent then return end  -- we sent it, no notification needed
    local viewing = ((self.state == self.STATE.CONTACT_DETAIL or self.state == self.STATE.MESSAGE_THREAD)
                     and self.selectedContact == contactKey)
    if not viewing then
        -- Look up contact name for friendlier notification
        local displayName = senderName
        for _, c in ipairs(ContactManager.contacts) do
            if c.farmName and string.lower(c.farmName) == string.lower(senderName) then
                displayName = c.name or senderName
                break
            end
        end
        self.unreadMessages[contactKey] = (self.unreadMessages[contactKey] or 0) + 1
        NotificationManager:push("ping",
            string.format("MSG from %s: %s", displayName, text))
    end
end

-- ─── Send a message from the current contact thread ──────────────────────────
function RoleplayPhone:sendMessage()
    local text = self.messageCompose.text
    if not text or text == "" then return end
    if not self.selectedContact then return end

    local c = ContactManager:getContact(self.selectedContact)
    if not c then return end

    -- Resolve recipient farmId
    local toFarmId = self:resolveFarmId(c.farmName)
    if toFarmId == 0 then
        NotificationManager:push("rejected",
            string.format("Can't find farm '%s' online.", c.farmName or "?"))
        return
    end

    local myFarmId = self:getMyFarmId()
    local myName   = self:getFarmName(myFarmId)
    local gameDay   = (g_currentMission and g_currentMission.environment
                       and g_currentMission.environment.currentDay) or 0

    -- Store locally as a sent message
    self:receiveMessage(self.selectedContact, myFarmId, myName, text, gameDay, true)

    -- Broadcast over network
    local evt = RI_MessageEvent.new(myFarmId, toFarmId, myName, text, gameDay)
    if g_server ~= nil then
        g_server:broadcastEvent(evt)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(evt)
    end

    -- Clear compose
    self.messageCompose.text = ""
    print(string.format("[RoleplayPhone] Message sent to Farm %d (%s): %s",
        toFarmId, c.farmName, text))
end

-- ─── Farm lookup helpers (use g_farmManager directly — reliable on host AND client) ──

-- ─── CALL: initiate outgoing call from contact thread ─────────────────────────
function RoleplayPhone:startCall()
    if not self.selectedContact then return end
    local c = ContactManager:getContact(self.selectedContact)
    if not c then return end

    local toFarmId = self:resolveFarmId(c.farmName)
    if toFarmId == 0 then
        NotificationManager:push("rejected",
            string.format("Can't reach '%s' - are they online?", c.farmName or "?"))
        return
    end

    local myFarmId = self:getMyFarmId()
    local myName   = self:getFarmName(myFarmId)

    self.call.contactName = c.name or c.farmName
    self.call.contactNum  = c.phone or ""
    self.call.toFarmId    = toFarmId
    self.call.fromFarmId  = myFarmId
    self.call.startTime   = 0
    self.call.prevState   = self.STATE.CLOSED
    self.state = self.STATE.CALL_OUTGOING
    self.callRingTimer    = 0
    -- Record outgoing call
    table.insert(self.callHistory, 1, { direction="outgoing", name=self.call.contactName, gameTime=g_currentMission and g_currentMission.time or 0 })

    -- Close the phone UI context so player keeps full movement during call
    -- The call popup draws independently above the CLOSED guard in draw()
    self.isOpen = false
    g_inputBinding:setShowMouseCursor(false)
    if self.phoneContextEventId then
        g_inputBinding:removeActionEvent(self.phoneContextEventId)
        self.phoneContextEventId = nil
    end
    g_inputBinding:revertContext(true)

    local evt = RI_CallEvent.new("ring", myFarmId, toFarmId, myName, "")
    if g_server ~= nil then g_server:broadcastEvent(evt)
    elseif g_client ~= nil then g_client:getServerConnection():sendEvent(evt) end
    print(string.format("[RoleplayPhone] Calling Farm %d (%s)...", toFarmId, c.farmName))
end

-- ─── CALL: incoming ──────────────────────────────────────────────────────────
function RoleplayPhone:onIncomingCall(fromFarmId, callerName, callerNum)
    if self.state == self.STATE.CALL_OUTGOING
    or self.state == self.STATE.CALL_INCOMING
    or self.state == self.STATE.CALL_ACTIVE then
        local myFarmId = self:getMyFarmId()
        local evt = RI_CallEvent.new("decline", myFarmId, fromFarmId, "", "")
        if g_server ~= nil then g_server:broadcastEvent(evt)
        elseif g_client ~= nil then g_client:getServerConnection():sendEvent(evt) end
        return
    end
    -- Try to find caller in our contacts by farm name for a friendlier display name
    local displayName = callerName
    for _, c in ipairs(ContactManager.contacts) do
        if c.farmName and string.lower(c.farmName) == string.lower(callerName) then
            displayName = c.name or callerName
            break
        end
    end
    self.call.contactName = displayName
    self.call.contactNum  = callerNum
    self.call.fromFarmId  = fromFarmId
    self.call.toFarmId    = self:getMyFarmId()
    self.call.startTime   = 0
    self.call.prevState   = self.state
    self.state = self.STATE.CALL_INCOMING
    self.callRingTimer    = 0
    -- Record incoming call
    table.insert(self.callHistory, 1, { direction="incoming", name=self.call.contactName, gameTime=g_currentMission and g_currentMission.time or 0 })

    -- Popup draws independently, no context push needed — player keeps full movement
    -- Don't set isOpen so _restoreAfterCall won't try to revertContext
    if self.ringSample and self.ringSample ~= 0 then
        playSample(self.ringSample, 0, 1.0, 0, 0, 0)
    end
    print(string.format("[RoleplayPhone] Incoming call from %s", callerName))
end

function RoleplayPhone:onCallAnswered()
    self:stopRingtone()
    self.call.startTime = g_currentMission and g_currentMission.time or 0
    self.state = self.STATE.CALL_ACTIVE
end

function RoleplayPhone:onCallDeclined()
    self:stopRingtone()
    NotificationManager:push("rejected", "Call declined.")
    self:_restoreAfterCall()
end

function RoleplayPhone:onCallEnded()
    self:stopRingtone()
    -- If we were still ringing when the other side ended it, that's a missed call
    if self.state == self.STATE.CALL_INCOMING then
        local name = self.call.contactName or "Unknown"
        NotificationManager:push("info", string.format("Missed call from %s", name))
        -- Record missed call
        table.insert(self.callHistory, 1, { direction="missed", name=name, gameTime=g_currentMission and g_currentMission.time or 0 })
    end
    self:_restoreAfterCall()
end

-- Shared cleanup: called by endCall, onCallEnded, onCallDeclined
function RoleplayPhone:_restoreAfterCall()
    local prevState = self.call.prevState or self.STATE.HOME
    self:stopRingtone()
    self.call = { prevState = self.STATE.HOME, startTime = 0, fromFarmId = 0, toFarmId = 0, contactName = "", contactNum = "" }
    if prevState == self.STATE.CLOSED or not self.isOpen then
        -- If isOpen is already false, context was cleaned up by startCall — don't revert again
        if self.isOpen then
            g_inputBinding:setShowMouseCursor(false)
            if self.phoneContextEventId then
                g_inputBinding:removeActionEvent(self.phoneContextEventId)
                self.phoneContextEventId = nil
            end
            if self.incomingCallActionEventId then
                g_inputBinding:removeActionEvent(self.incomingCallActionEventId)
                self.incomingCallActionEventId = nil
            end
            g_inputBinding:revertContext(true)
        end
        self.state  = self.STATE.CLOSED
        self.isOpen = false
    else
        self.state = prevState
    end
end

function RoleplayPhone:answerCall()
    self:stopRingtone()
    self.call.startTime = g_currentMission and g_currentMission.time or 0
    self.state = self.STATE.CALL_ACTIVE
    local myFarmId = self:getMyFarmId()
    local evt = RI_CallEvent.new("answer", myFarmId, self.call.fromFarmId, "", "")
    if g_server ~= nil then g_server:broadcastEvent(evt)
    elseif g_client ~= nil then g_client:getServerConnection():sendEvent(evt) end
end

function RoleplayPhone:endCall()
    self:stopRingtone()
    local myFarmId = self:getMyFarmId()
    local remoteFarm = (self.call.fromFarmId == myFarmId)
                       and self.call.toFarmId or self.call.fromFarmId
    -- Send "decline" if still ringing, "end" if call was active
    local evtType = (self.state == self.STATE.CALL_INCOMING) and "decline" or "end"
    local evt = RI_CallEvent.new(evtType, myFarmId, remoteFarm, "", "")
    if g_server ~= nil then g_server:broadcastEvent(evt)
    elseif g_client ~= nil then g_client:getServerConnection():sendEvent(evt) end
    self:_restoreAfterCall()
end

function RoleplayPhone:stopRingtone()
    if self.ringSample and self.ringSample ~= 0 then
        stopSample(self.ringSample, 0, 0)
    end
end

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

-- ─── Time formatter (respects 12/24hr player setting) ────────────────────────
function RoleplayPhone:formatTime(hrs, mins)
    if self.settings.timeFormat == "24" then
        return string.format("%02d:%02d", hrs, mins)
    else
        local suffix = hrs >= 12 and "PM" or "AM"
        local h12    = hrs % 12
        if h12 == 0 then h12 = 12 end
        return string.format("%d:%02d %s", h12, mins, suffix)
    end
end

-- ─── Battery update (call from Mission00.update) ──────────────────────────────
function RoleplayPhone:updateBattery(dt)
    local bat = self.battery
    if self.state ~= self.STATE.CLOSED then
        -- drain faster during active call
        local rate = (self.state == self.STATE.CALL_ACTIVE)
            and bat.callRate or bat.drainRate
        bat.level = math.max(0, bat.level - rate * dt)
    else
        bat.level = math.min(100, bat.level + bat.chargeRate * dt)
    end
end

-- Auto-timeout unanswered calls after 30 seconds
function RoleplayPhone:updateCallTimeout(dt)
    if self.state ~= self.STATE.CALL_OUTGOING
    and self.state ~= self.STATE.CALL_INCOMING then return end

    self.callRingTimer = (self.callRingTimer or 0) + dt
    if self.callRingTimer >= 30000 then  -- 30 seconds in ms
        self.callRingTimer = 0
        local myFarmId = self:getMyFarmId()
        -- Send end event to the other side
        local evt = RI_CallEvent.new("end", myFarmId, self.call.toFarmId or self.call.fromFarmId, "", "")
        if g_server ~= nil then g_server:broadcastEvent(evt)
        elseif g_client ~= nil then g_client:getServerConnection():sendEvent(evt) end
        -- Show missed call notification for incoming side
        if self.state == self.STATE.CALL_INCOMING then
            local name = self.call.contactName or "Unknown"
            NotificationManager:push("info", string.format("Missed call from %s", name))
        end
        self:_restoreAfterCall()
    end
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
-- ─── Resolve a farm name to a farmId ─────────────────────────────────────────
-- Checks g_farmManager (works on both host AND client in FS25),
-- then falls back to knownFarms (sent by host on connect).
function RoleplayPhone:resolveFarmId(farmName)
    if not farmName or farmName == "" then return 0 end
    local lower = string.lower(farmName)
    -- g_farmManager is the correct global — g_currentMission.farmManager is often nil
    if g_farmManager then
        for _, farm in pairs(g_farmManager:getFarms()) do
            if farm.name and string.lower(farm.name) == lower then
                return farm.farmId
            end
        end
    end
    if self.knownFarms then
        for _, farm in ipairs(self.knownFarms) do
            if farm.name and string.lower(farm.name) == lower then
                return farm.farmId
            end
        end
    end
    return 0
end

function RoleplayPhone:getAvailableFarms()
    -- Return cached list if available - cache is cleared every time phone opens
    -- so this only persists during a single open session, not across opens
    if self._farmCache and #self._farmCache > 0 then
        return self._farmCache
    end

    local result  = {}
    local seenIds = {}

    -- Primary: g_farmManager is the correct global (g_currentMission.farmManager is often nil)
    if g_farmManager then
        for _, farm in pairs(g_farmManager:getFarms()) do
            if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
                table.insert(result, {
                    farmId = farm.farmId,
                    name   = (farm.name and farm.name ~= "") and farm.name
                                or ("Farm " .. tostring(farm.farmId))
                })
                seenIds[farm.farmId] = true
            end
        end
    end

    -- Client fallback: knownFarms sent by host (includes offline farms)
    if self.knownFarms then
        for _, farm in ipairs(self.knownFarms) do
            if not seenIds[farm.farmId] then
                table.insert(result, farm)
                seenIds[farm.farmId] = true
            end
        end
    end

    -- Host supplement: farms.xml picks up any OFFLINE farms not in farmManager
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
                    if farmId and farmId ~= FarmManager.SPECTATOR_FARM_ID
                    and not seenIds[farmId] then
                        table.insert(result, {
                            farmId = farmId,
                            name   = (name and name ~= "") and name
                                        or ("Farm " .. tostring(farmId))
                        })
                        seenIds[farmId] = true
                    end
                    i = i + 1
                end
                delete(xmlFile)
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
    if g_farmManager then
        local f = g_farmManager:getFarmById(farmId)
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
    -- HUD icon and popups always draw, even when phone is closed
    NotificationManager:draw()

    -- Call popup draws regardless of phone open state — player keeps full movement
    if self.state == self.STATE.CALL_OUTGOING
    or self.state == self.STATE.CALL_INCOMING
    or self.state == self.STATE.CALL_ACTIVE then
        self:drawCallScreen()
        return
    end

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
    elseif self.state == self.STATE.MESSAGE_THREAD then
        self:drawMessageThread()
    elseif self.state == self.STATE.CONTACT_CREATE then
        self:drawContactCreate()
    elseif self.state == self.STATE.CALLS then
        self:drawCallsList()
    elseif self.state == self.STATE.SETTINGS then
        self:drawSettings()
    end
end

-- ─── Big screen shell (used by invoices, contacts, ping) ─────────────────────
function RoleplayPhone:drawBigScreen()
    local s = self.BIG
    -- Phone body border
    self:drawRect(s.x-0.007, s.y-0.007, s.w+0.014, s.h+0.014, 0.04, 0.04, 0.05, 1.0)

    -- Wallpaper background: use player's selected wallpaper (texture or colour swatch)
    local wp = self.WALLPAPERS[self.settings.wallpaperIndex] or self.WALLPAPERS[1]
    if wp.texture and self.wallpaper and self.wallpaper ~= 0 then
        setOverlayColor(self.wallpaper, 1, 1, 1, 1)
        renderOverlay(self.wallpaper, s.x, s.y, s.w, s.h)
        self:drawRect(s.x, s.y, s.w, s.h, 0.0, 0.0, 0.0, 0.45)
    else
        self:drawRect(s.x, s.y, s.w, s.h, wp.r, wp.g, wp.b, 1.0)
    end

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
        timeStr    = self:formatTime(hrs, mins)
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(px + 0.014, barY, textSize, timeStr)

    -- Right side: 4G, signal bars, battery — tight group from right edge
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(px + pw - 0.042, barY, textSize, "4G")
    renderText(px + pw - 0.060, barY, textSize, "|||")

    -- Battery widget: sits at far right, next to signal bars
    if self.settings.batteryVisible then
        local bat     = self.battery
        local pct     = bat.level / 100
        local bw      = 0.013
        local bh      = 0.007
        local bx      = px + pw - 0.037
        local by      = barY + 0.003
        -- Outer shell
        self:drawRect(bx, by, bw, bh, 0.55, 0.55, 0.55, 1.0)
        -- Fill colour: green >30%, yellow >15%, red <=15%
        local fr, fg, fb
        if pct > 0.30 then
            fr, fg, fb = 0.15, 0.80, 0.20
        elseif pct > 0.15 then
            fr, fg, fb = 0.90, 0.75, 0.05
        else
            fr, fg, fb = 0.90, 0.10, 0.10
        end
        local fillW = math.max(0.001, (bw - 0.002) * pct)
        self:drawRect(bx + 0.001, by + 0.001, fillW, bh - 0.002, fr, fg, fb, 1.0)
        -- Nub on right
        self:drawRect(bx + bw, by + 0.001, 0.002, bh - 0.002, 0.55, 0.55, 0.55, 1.0)
        -- LOW BATTERY flash at <=15%
        if pct <= 0.15 then
            local flash = math.floor(getTimeSec() * 2) % 2 == 0
            if flash then
                setTextAlignment(RenderText.ALIGN_RIGHT)
                setTextBold(false)
                setTextColor(0.95, 0.15, 0.15, 1.0)
                renderText(bx - 0.003, barY, 0.009, "LOW")
            end
        end
    end

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

    -- Dock dimensions (shared by all pages)
    local dockH = 0.115
    local dockY = py + 0.006

    -- Phone body (near-black bezel)
    self:drawRect(px-0.009, py-0.009, pw+0.018, ph+0.018, 0.01, 0.01, 0.01, 1.0)

    -- ── Screen background ────────────────────────────────────────────────────
    if self.homePage == 1 then
        -- Page 1: wallpaper from picker — texture (Countryside) or colour swatch
        local wp = self.WALLPAPERS[self.settings.wallpaperIndex] or self.WALLPAPERS[1]
        if wp.texture and self.wallpaper and self.wallpaper ~= 0 then
            setOverlayColor(self.wallpaper, 1, 1, 1, 1)
            renderOverlay(self.wallpaper, px, py, pw, ph)
            self:drawRect(px, py, pw, ph, 0.0, 0.0, 0.0, 0.38)
        else
            self:drawRect(px, py, pw, ph, wp.r, wp.g, wp.b, 1.0)
        end
    else
        -- Page 2+: same wallpaper as page 1
        local wp = self.WALLPAPERS[self.settings.wallpaperIndex] or self.WALLPAPERS[1]
        if wp.texture and self.wallpaper and self.wallpaper ~= 0 then
            setOverlayColor(self.wallpaper, 1, 1, 1, 1)
            renderOverlay(self.wallpaper, px, py, pw, ph)
            self:drawRect(px, py, pw, ph, 0.0, 0.0, 0.0, 0.55)
        else
            self:drawRect(px, py, pw, ph, wp.r, wp.g, wp.b, 1.0)
        end
    end

    -- Notch
    local nw = pw * 0.20
    self:drawRect(cx - nw/2, py + ph - 0.010, nw, 0.010, 0.01, 0.01, 0.01, 1.0)

    -- Status bar (always)
    self:drawStatusBar(px, py, pw, ph)

    -- ── Page 1 content: clock + weather widget ───────────────────────────────
    if self.homePage == 1 then
        -- Big clock
        local timeStr = "00:00"
        if g_currentMission and g_currentMission.environment then
            local dt   = g_currentMission.environment.dayTime / 3600000
            local hrs  = math.floor(dt) % 24
            local mins = math.floor((dt - math.floor(dt)) * 60)
            timeStr    = self:formatTime(hrs, mins)
        end
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(1, 1, 1, 1)
        renderText(cx, py + ph * 0.70, 0.038, timeStr)

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
        setTextColor(0.90, 0.93, 1.0, 0.92)
        renderText(cx, py + ph * 0.63, 0.013, dateStr)

        -- Weather widget
        self:drawWeatherWidget(px, py, pw, ph)

    -- ── Page 2+ content: app grid ────────────────────────────────────────────
    else
        self:drawAppGrid(px, py, pw, ph, dockY, dockH)
    end

    -- ── Dock (always visible on all pages) ───────────────────────────────────
    -- Frosted glass effect: semi-transparent dark strip
    self:drawRect(px, dockY, pw, dockH, 0.03, 0.03, 0.04, 0.88)
    self:drawRect(px, dockY + dockH, pw, 0.002, 0.12, 0.12, 0.15, 0.5)
    self:drawDockIcons(px, py, pw, ph, dockY, dockH)

    -- ── Page dots ─────────────────────────────────────────────────────────────
    local dotSize   = 0.005
    local dotGap    = 0.016
    local dotY      = dockY + dockH + 0.008
    local totalDots = self.homePageCount
    local dotStartX = cx - ((totalDots - 1) * dotGap) / 2
    for i = 1, totalDots do
        local alpha = (i == self.homePage) and 0.90 or 0.25
        self:drawRect(dotStartX + (i-1)*dotGap - dotSize/2, dotY, dotSize, dotSize, 1, 1, 1, alpha)
        -- Dot hitboxes for page switching
        self:addHitbox("page_dot_" .. i, dotStartX + (i-1)*dotGap - 0.012, dotY - 0.006, 0.024, 0.018, { page=i })
    end

    -- ── Page swipe arrows (subtle, only when more than 1 page) ───────────────
    if self.homePageCount > 1 then
        if self.homePage > 1 then
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextBold(false)
            setTextColor(1, 1, 1, 0.75)
            renderText(px + 0.004, dotY - 0.001, 0.014, "<")
            self:addHitbox("page_prev", px, dotY - 0.015, 0.025, 0.030, {})
        end
        if self.homePage < self.homePageCount then
            setTextAlignment(RenderText.ALIGN_RIGHT)
            setTextColor(1, 1, 1, 0.75)
            renderText(px + pw - 0.004, dotY - 0.001, 0.014, ">")
            self:addHitbox("page_next", px + pw - 0.025, dotY - 0.015, 0.025, 0.030, {})
        end
    end

    -- Close hint and swipe hint — both in the grey dock area
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    -- Swipe hint at top of dock (only when more than 1 page)
    if self.homePageCount > 1 then
        setTextColor(0.65, 0.70, 0.80, 0.70)
        renderText(cx, dockY + dockH - 0.008, 0.009, "< > or tap arrows to switch pages")
    end
    -- Close hint just above the icons
    setTextColor(0.85, 0.87, 0.90, 0.75)
    renderText(cx, dockY + 0.094, 0.008, "Click outside to close")
end

-- ─── Weather widget (page 1 center) ──────────────────────────────────────────
function RoleplayPhone:drawWeatherWidget(px, py, pw, ph)
    local cx = px + pw / 2

    -- Widget sits between date and dock, roughly in the center vertical area
    local widgetY = py + ph * 0.43

    -- Get weather data
    local tempStr    = "--°C"
    local condStr    = "Clear"
    local condColor  = { 1.0, 0.85, 0.30 }  -- default: sunny yellow

    if g_currentMission and g_currentMission.environment then
        local weather = g_currentMission.environment.weather

        if weather then
            local isRaining  = weather.getIsRaining  and weather:getIsRaining()  or false
            local isSnowing  = weather.getIsSnowing  and weather:getIsSnowing()  or false
            local isHailing  = weather.getIsHailing  and weather:getIsHailing()  or false

            if isHailing then
                condStr   = "Hail"
                condColor = { 0.60, 0.80, 0.95 }
            elseif isSnowing then
                condStr   = "Snow"
                condColor = { 0.85, 0.92, 1.00 }
            elseif isRaining then
                local intensity = weather.getRainFallScale and weather:getRainFallScale() or 1
                condStr   = intensity > 0.6 and "Heavy Rain" or "Rain"
                condColor = { 0.45, 0.65, 0.90 }
            else
                condStr   = "Clear"
                condColor = { 1.0, 0.85, 0.30 }
            end

            -- Temperature
            if weather.temperatureUpdater then
                local env  = g_currentMission.environment
                local temp = weather.temperatureUpdater:getTemperatureAtTime(env.dayTime)
                if temp then
                    if self.settings.tempUnit == "F" then
                        local f = math.floor(temp * 9 / 5 + 32 + 0.5)
                        tempStr = string.format("%d°F", f)
                    else
                        tempStr = string.format("%d°C", math.floor(temp + 0.5))
                    end
                end
            end
        end
    end

    -- Condition label (e.g. "Clear", "Rain")
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    setTextColor(condColor[1], condColor[2], condColor[3], 0.95)
    renderText(cx, widgetY + 0.020, 0.014, condStr)

    -- Temperature (big-ish, white)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(cx, widgetY, 0.022, tempStr)
    setTextBold(false)
end

-- ─── App grid (page 2+) ───────────────────────────────────────────────────────
function RoleplayPhone:drawAppGrid(px, py, pw, ph, dockY, dockH)
    local cx      = px + pw / 2
    local cols    = 3
    local iconSz  = 0.038
    local iconGap = (pw - cols * iconSz) / (cols + 1)
    local startY  = dockY + dockH + 0.035  -- start just above dock area, working upward

    -- Collect apps for this page
    local pageApps = {}
    for _, app in ipairs(self.GRID_APPS) do
        if app.page == self.homePage then
            table.insert(pageApps, app)
        end
    end

    -- Draw in rows of `cols`
    local row = 0
    local col = 0
    local rowH = iconSz + 0.028  -- icon + label space
    -- Start from top of screen content area, below status bar
    local gridStartY = py + ph - 0.060 - rowH  -- just below status bar

    for idx, app in ipairs(pageApps) do
        col = (idx - 1) % cols
        row = math.floor((idx - 1) / cols)

        local ix = px + iconGap + col * (iconSz + iconGap)
        local iy = gridStartY - row * (rowH + 0.008)

        -- Rounded square background
        local c = app.color
        self:drawRect(ix, iy, iconSz, iconSz, c[1], c[2], c[3], 1.0)
        -- Subtle highlight top edge
        self:drawRect(ix, iy + iconSz - 0.003, iconSz, 0.003, c[1]+0.2, c[2]+0.2, c[3]+0.2, 0.3)

        -- Label below
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(1, 1, 1, 0.90)
        renderText(ix + iconSz/2, iy - 0.014, 0.009, app.label)

        -- Hitbox
        self:addHitbox("grid_app_" .. app.id, ix, iy - 0.016, iconSz, iconSz + 0.016, { appId = app.id })
    end
end

-- ─── Dock icons (always visible) ─────────────────────────────────────────────
function RoleplayPhone:drawDockIcons(px, py, pw, ph, dockY, dockH)
    local cx     = px + pw / 2
    local nApps  = #self.DOCK_APPS
    -- Shrink icon + gap so all 4 fit inside the phone width with small margins
    local margin = 0.010
    local gap    = 0.008
    local iconSz = (pw - margin * 2 - gap * (nApps - 1)) / nApps  -- width in screen coords
    local iconH  = iconSz * (16 / 9)  -- compensate for 16:9 aspect ratio so boxes look square
    local totalW = nApps * iconSz + (nApps - 1) * gap
    local startX = cx - totalW / 2
    local iconY  = dockY + (dockH - iconH) / 2

    for i, app in ipairs(self.DOCK_APPS) do
        local ix = startX + (i-1) * (iconSz + gap)
        local c  = app.color

        -- Icon background (visually square)
        self:drawRect(ix, iconY, iconSz, iconH, c[1], c[2], c[3], 1.0)
        -- Highlight strip at top of icon
        self:drawRect(ix, iconY + iconH - 0.003, iconSz, 0.003, c[1]+0.2, c[2]+0.2, c[3]+0.2, 0.3)

        -- Icon image overlays for dock
        local overlay = nil
        if app.id == "invoices" then overlay = self.iconInvoices
        elseif app.id == "contacts" then overlay = self.iconContacts
        elseif app.id == "calls" then overlay = self.iconCalls
        end
        if overlay and overlay ~= 0 then
            setOverlayColor(overlay, 1, 1, 1, 0.9)
            renderOverlay(overlay, ix + iconSz*0.15, iconY + iconH*0.15, iconSz*0.70, iconH*0.70)
        end

        -- Settings icon overlay
        if app.id == "settings" then
            local sm = iconSz * 0.1
            local hm = iconH  * 0.1
            setOverlayColor(self.iconSettings, 1, 1, 1, 0.9)
            renderOverlay(self.iconSettings, ix + sm, iconY + hm, iconSz - sm*2, iconH - hm*2)
        end

        -- Label below icon (inside dock)
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(0.85, 0.87, 0.90, 0.85)
        renderText(ix + iconSz/2, dockY + 0.004, 0.008, app.label)

        -- Hitbox
        self:addHitbox("dock_" .. app.id, ix, dockY, iconSz, dockH, { appId = app.id })
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
                   "Notes (job details / agreement)", self.form.notes,
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

    -- When phone is closed, let NotificationManager handle HUD icon dragging
    if self.state == self.STATE.CLOSED then
        NotificationManager:mouseEvent(posX, posY, isDown, isUp, button)
        return
    end

    -- Also forward to NotificationManager from HOME screen — cursor IS visible
    -- here, so the player can click-hold-drag the HUD icon while the phone is open.
    -- Must be before the isDown guard so isUp (drag-end / save) is forwarded too.
    if self.state == self.STATE.HOME then
        local handled = NotificationManager:mouseEvent(posX, posY, isDown, isUp, button)
        if handled then return end
    end

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
    -- Page dot navigation
    if hb.id:sub(1,9) == "page_dot_" and hb.data and hb.data.page then
        self.homePage = hb.data.page
        return
    end
    if hb.id == "page_prev" then
        self.homePage = math.max(1, self.homePage - 1)
        return
    end
    if hb.id == "page_next" then
        self.homePage = math.min(self.homePageCount, self.homePage + 1)
        return
    end

    -- Dock app clicks
    if hb.id:sub(1,5) == "dock_" and hb.data and hb.data.appId then
        local appId = hb.data.appId
        if appId == "invoices" then self.state = self.STATE.INVOICES_LIST; return end
        if appId == "contacts" then self.state = self.STATE.CONTACTS;      return end
        if appId == "calls"    then self.state = self.STATE.CALLS;          return end
        if appId == "settings" then self.state = self.STATE.SETTINGS;      return end
        return
    end

    -- Grid app clicks (page 2+)
    if hb.id:sub(1,9) == "grid_app_" and hb.data and hb.data.appId then
        local appId = hb.data.appId
        -- Weather and market apps coming soon
        if appId == "weather" then
            -- TODO: self.state = self.STATE.WEATHER
            return
        end
        if appId == "market" then
            -- TODO: self.state = self.STATE.MARKET
            return
        end
        return
    end

    -- Legacy: App icons (home screen) - keep for any old hitboxes
    if hb.id:sub(1,4) == "app_" and hb.data and hb.data.state then
        self.state = hb.data.state
        return
    end

    -- Message compose field (focus/unfocus)
    if hb.id == "msg_field" then
        self.messageCompose.active = true
        return
    end

    -- Send message button
    if hb.id == "btn_send_message" then
        self:sendMessage()
        return
    end

    -- Message button (from contact detail — opens message thread)
    if hb.id == "btn_message_contact" then
        self.state = self.STATE.MESSAGE_THREAD
        return
    end

    -- Call button (from contact thread)
    if hb.id == "btn_call" then
        self:startCall()
        return
    end

    -- Answer incoming call
    if hb.id == "btn_answer" then
        self:answerCall()
        return
    end

    -- End / decline call
    if hb.id == "btn_end_call" then
        self:endCall()
        return
    end

    -- Back button
    if hb.id == "btn_back" then
        if self.state == self.STATE.MESSAGE_THREAD then
            self.messageCompose.active = false
            self.messageCompose.text   = ""
            self.state = self.STATE.CONTACT_DETAIL
            return
        end
        if self.state == self.STATE.CONTACT_DETAIL then
            self.state = self.STATE.CONTACTS
            return
        end
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
        UsedPlusCompat:onInvoiceMarkedPaid(self.selectedInvoice)
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
            UsedPlusCompat:onInvoiceRejected(inv)
            NotificationManager:push("rejected", "Invoice #" .. string.format("%04d", inv.id) .. " rejected.")
            print("[RoleplayPhone] Invoice rejected: #" .. tostring(inv.id))
        end
        return
    end

    -- Pay invoice (recipient)
    if hb.id == "btn_pay_invoice" and self.selectedInvoice then
        local inv = self.selectedInvoice
        local amount = inv.amount or 0
        local myFarmId = self:getMyFarmId()
        local farmManager = g_farmManager or (g_currentMission and g_currentMission.farmManager)
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
                UsedPlusCompat:onInvoicePaid(inv)
                NotificationManager:push("paid",
                    string.format("Paid $%s to %s",
                        self:formatMoney(amount),
                        self:getFarmName(inv.fromFarmId)))
                print("[RoleplayPhone] Invoice paid: #" .. tostring(inv.id))
            else
                NotificationManager:push("rejected", "Insufficient funds to pay this invoice.")
            end
        end
        return
    end

    -- ── Contacts list ──────────────────────────────────────────────────────
    if hb.id == "contact_row" and hb.data and hb.data.index then
        self.selectedContact = hb.data.index
        self.unreadMessages[hb.data.index] = 0  -- clear badge on open
        self.messageCompose.text   = ""
        self.messageCompose.active = false
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
            local idx = self.selectedContact
            -- If client, notify host to persist the deletion
            if g_server == nil then
                local myFarmId = self:getMyFarmId()
                g_client:getServerConnection():sendEvent(
                    RI_ContactEvent.new("delete", myFarmId, idx, {}))
            end
            ContactManager:removeContact(idx)
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

    -- ── Contact create: clear buttons ──────────────────────────────────────
    if hb.id == "cclear_name"     then self.contactForm.name     = ""; self.contactForm.activeField = "name";     return end
    if hb.id == "cclear_farmName" then self.contactForm.farmName = ""; self.contactForm.activeField = "farmName"; return end
    if hb.id == "cclear_phone"    then self.contactForm.phone    = ""; self.contactForm.activeField = "phone";    return end
    if hb.id == "cclear_notes"    then self.contactForm.notes    = ""; self.contactForm.activeField = "notes";    return end

    -- ── Contact create: save ───────────────────────────────────────────────
    if hb.id == "btn_save_contact" then
        local f = self.contactForm
        if f.name and f.name ~= "" then
            local data = {
                name     = f.name,
                farmName = f.farmName,
                phone    = f.phone,
                notes    = f.notes,
            }
            ContactManager:addContact(data)
            -- If client, notify host to persist the new contact
            if g_server == nil then
                local myFarmId = self:getMyFarmId()
                g_client:getServerConnection():sendEvent(
                    RI_ContactEvent.new("add", myFarmId, 0, data))
            end
            RoleplayPhone:saveInvoices()
        end
        self.contactForm.activeField = nil
        self.state = self.STATE.CONTACTS
        return
    end

    -- ── Settings screen ────────────────────────────────────────────────────
    if hb.id == "setting_timeformat_12" then
        self.settings.timeFormat = "12"
        RoleplayPhone:saveSettings()
        return
    end
    if hb.id == "setting_timeformat_24" then
        self.settings.timeFormat = "24"
        RoleplayPhone:saveSettings()
        return
    end
    if hb.id == "setting_temp_F" then
        self.settings.tempUnit = "F"
        RoleplayPhone:saveSettings()
        return
    end
    if hb.id == "setting_temp_C" then
        self.settings.tempUnit = "C"
        RoleplayPhone:saveSettings()
        return
    end
    if hb.id == "setting_battery_toggle" then
        self.settings.batteryVisible = not self.settings.batteryVisible
        RoleplayPhone:saveSettings()
        return
    end
    if hb.id:sub(1, 14) == "setting_wallp_" then
        local idx = tonumber(hb.id:sub(15))
        if idx and self.WALLPAPERS[idx] then
            self.settings.wallpaperIndex = idx
            RoleplayPhone:saveSettings()
        end
        return
    end
end

-- ─── Submit invoice form ──────────────────────────────────────────────────────
function RoleplayPhone:submitInvoice()
    local amount = tonumber(self.form.amount)
    if not amount or amount <= 0 then
        NotificationManager:push("rejected", "Enter a valid amount.")
        return
    end

    local farms   = self:getAvailableFarms()
    local toFarm  = farms[self.form.toFarmIndex]
    local myFarmId = self:getMyFarmId()

    if not toFarm then
        NotificationManager:push("rejected", "No recipient farm selected.")
        return
    end

    if toFarm.farmId == myFarmId then
        NotificationManager:push("rejected", "Can't invoice your own farm.")
        return
    end

    local cats = InvoiceManager.categories
    local cat  = cats[self.form.categoryIndex] or "Other"
    local day  = (g_currentMission and g_currentMission.environment and
                  g_currentMission.environment.currentDay) or 0

    if g_client ~= nil then
        -- MP: send with id=0 — server assigns the canonical sequential ID and
        -- broadcasts back to ALL clients (including the sender) so everyone
        -- gets the invoice with the same real ID.  Do NOT add locally here;
        -- the incoming broadcast from the server will add it.
        local mpData = {
            id          = 0,  -- placeholder; server will assign
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
        g_client:getServerConnection():sendEvent(
            InvoiceEvents.SendInvoiceEvent.new(Invoice.new(mpData)))
        print("[RoleplayPhone] Invoice submitted to server (id=0, awaiting assignment)")
    else
        -- Singleplayer: assign ID locally, add directly, and save
        local newId = InvoiceManager.nextInvoiceId
        InvoiceManager.nextInvoiceId = InvoiceManager.nextInvoiceId + 1
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
        UsedPlusCompat:onInvoiceCreated(invoice)
        print("[RoleplayPhone] Invoice created: #" .. tostring(newId))
    end

    NotificationManager:push("info",
        string.format("Invoice for $%s sent to %s", self:formatMoney(amount), toFarm.name))

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

    -- Helper: is this a backspace keypress?
    -- FS25 may or may not expose Input.KEY_BackSpace correctly so we check both:
    --   unicode == 8  (ASCII backspace, always reliable)
    --   sym check as fallback
    local isBackspace = (unicode == 8)
        or (Input.KEY_BackSpace ~= nil and sym == Input.KEY_BackSpace)

    -- Text input (only when a field is active)
    if self.form.activeField and self.state == self.STATE.INVOICE_CREATE then
        local field = self.form.activeField
        local val   = self.form[field] or ""

        -- Backspace
        if isBackspace then
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
        if isBackspace then
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

    -- Message compose text input (contact thread)
    if self.messageCompose.active and self.state == self.STATE.MESSAGE_THREAD then
        local val = self.messageCompose.text or ""

        if isBackspace then
            if #val > 0 then
                self.messageCompose.text = val:sub(1, #val - 1)
            end
            return true
        end

        -- Enter sends the message
        if sym == Input.KEY_Return then
            self:sendMessage()
            return true
        end

        -- Printable character
        if unicode and unicode > 31 and unicode < 127 then
            if #val < 120 then
                self.messageCompose.text = val .. string.char(unicode)
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

-- ─── CALL SCREEN (compact popup — no freeze, F8 to answer/hang up) ───────────
function RoleplayPhone:drawCallScreen()
    local call = self.call

    -- Popup dimensions — left side, between minimap and keybinding list
    local pw  = 0.165
    local ph  = 0.140
    local px  = 0.01            -- left edge with small margin
    local py  = 0.38            -- vertically between minimap (bottom) and keybindings (top)
    local cx  = px + pw / 2

    -- Background card
    self:drawRect(px - 0.004, py - 0.004, pw + 0.008, ph + 0.008, 0.08, 0.12, 0.22, 0.85)
    self:drawRect(px, py, pw, ph, 0.04, 0.07, 0.14, 0.97)
    -- Top accent line
    self:drawRect(px, py + ph - 0.003, pw, 0.003, 0.25, 0.50, 1.0, 0.9)

    -- Status label
    local statusStr = "Calling..."
    if self.state == self.STATE.CALL_INCOMING then statusStr = "Incoming Call"
    elseif self.state == self.STATE.CALL_ACTIVE then statusStr = "On Call" end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    setTextColor(0.55, 0.70, 1.0, 0.9)
    renderText(cx, py + ph - 0.022, 0.012, statusStr)

    -- Contact name
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(cx, py + ph * 0.62, 0.018, call.contactName or "Unknown")

    -- Timer / ringing dots
    setTextBold(false)
    if self.state == self.STATE.CALL_ACTIVE and call.startTime and call.startTime > 0 then
        local now     = (g_currentMission and g_currentMission.time) or call.startTime
        local elapsed = math.max(0, math.floor((now - call.startTime) / 1000))
        local mins    = math.floor(elapsed / 60)
        local secs    = elapsed % 60
        setTextColor(0.70, 0.95, 0.70, 1.0)
        renderText(cx, py + ph * 0.44, 0.014, string.format("%d:%02d", mins, secs))
    elseif self.state == self.STATE.CALL_OUTGOING then
        local dots = string.rep(".", (math.floor(getTimeSec() * 2) % 4))
        setTextColor(0.60, 0.70, 0.85, 0.8)
        renderText(cx, py + ph * 0.44, 0.012, "Ringing" .. dots)
    end

    -- Decorative buttons (visual only — F8 does the actual action)
    local btnW = 0.075
    local btnH = 0.032
    local btnY = py + 0.018
    if self.state == self.STATE.CALL_INCOMING then
        local gap = 0.020
        local bx1 = cx - btnW - gap / 2
        local bx2 = cx + gap / 2
        self:drawRect(bx1, btnY, btnW, btnH, 0.08, 0.45, 0.18, 0.85)
        setTextBold(false)
        setTextColor(1, 1, 1, 0.9)
        renderText(bx1 + btnW/2, btnY + 0.008, 0.010, "Answer")
        self:drawRect(bx2, btnY, btnW, btnH, 0.50, 0.10, 0.10, 0.85)
        renderText(bx2 + btnW/2, btnY + 0.008, 0.010, "Decline")
    else
        self:drawRect(cx - btnW/2, btnY, btnW, btnH, 0.50, 0.10, 0.10, 0.85)
        setTextBold(false)
        setTextColor(1, 1, 1, 0.9)
        renderText(cx, btnY + 0.008, 0.010, "End Call")
    end

    -- F8 hint
    setTextBold(false)
    setTextColor(0.50, 0.60, 0.75, 0.70)
    renderText(cx, btnY - 0.014, 0.009, "Press F8 to answer / hang up")
end

-- ─── CONTACTS LIST screen ─────────────────────────────────────────────────────
function RoleplayPhone:drawContacts()
    local s  = self.PHONE
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    -- Phone shell background
    self:drawRect(px, py, pw, ph, 0.06, 0.07, 0.10, 0.97)

    local contentY = py + ph - 0.012

    -- Header bar
    local headerH = 0.042
    local headerY = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)

    -- Back button
    self:drawButton("btn_back", px + 0.006, headerY + 0.008, 0.045, 0.026,
        "< Back", 0.18, 0.20, 0.28, 0.010)

    -- Title
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.28, 0.013, "Contacts")

    -- Add button (top-right)
    self:drawButton("btn_add_contact", px + pw - 0.068, headerY + 0.008, 0.062, 0.026,
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

        -- Unread message badge (green dot + count)
        local unread = self.unreadMessages[i] or 0
        if unread > 0 then
            local dotR  = 0.012
            local dotX  = px + pw - 0.038
            local dotY  = rowY - rowH + (rowH / 2) - dotR
            -- Green filled circle (drawn as small square for now)
            self:drawRect(dotX, dotY, dotR * 2, dotR * 2, 0.15, 0.75, 0.30, 1.0)
            -- Count number inside
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setTextColor(1, 1, 1, 1)
            local countStr = unread > 9 and "9+" or tostring(unread)
            renderText(dotX + dotR, dotY + dotR * 0.25, 0.010, countStr)
        end

        -- Hitbox for the whole row
        self:addHitbox("contact_row", px, rowY - rowH, pw, rowH, { index = i })
    end
end


-- ─── CONTACT DETAIL screen ────────────────────────────────────────────────────
-- ─── CONTACT DETAIL screen (small phone screen) ──────────────────────────────
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

    local s  = self.PHONE
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    self:drawRect(px, py, pw, ph, 0.06, 0.07, 0.10, 0.97)

    -- Header
    local headerH = 0.042
    local headerY = py + ph - 0.012 - headerH
    self:drawRect(px, headerY, pw, headerH, 0.08, 0.11, 0.18, 1.0)
    self:drawButton("btn_back", px + 0.006, headerY + 0.008, 0.045, 0.026,
        "< Back", 0.12, 0.15, 0.22, 0.010)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.28, 0.013, "Contact")

    -- Avatar
    local avSz = pw * 0.25
    local avH  = avSz * (16/9)
    local avX  = px + pw/2 - avSz/2
    local avY  = headerY - avH - 0.018
    self:drawRect(avX, avY, avSz, avH, 0.15, 0.32, 0.60, 1.0)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(avX + avSz/2, avY + avH * 0.25, 0.028,
        string.upper(string.sub(c.name or "?", 1, 1)))

    -- Name
    setTextBold(true)
    setTextColor(0.92, 0.95, 1.0, 1.0)
    renderText(px + pw/2, avY - 0.018, 0.014, c.name or "Unknown")

    -- Info rows
    local infoY = avY - 0.040
    local infoX = px + 0.012
    local rowH  = 0.030
    local gap   = 0.006

    local function infoRow(label, value)
        if not value or value == "" then return end
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(false)
        setTextColor(0.50, 0.62, 0.78, 0.85)
        renderText(infoX, infoY, 0.009, label)
        setTextColor(0.92, 0.95, 1.0, 1.0)
        renderText(infoX, infoY - 0.014, 0.011, value)
        infoY = infoY - rowH - gap
    end

    infoRow("FARM", c.farmName)
    infoRow("PHONE", c.phone)
    infoRow("NOTES", c.notes)

    -- Message and Delete buttons
    local btnW = pw - 0.020
    local btnH = 0.032
    local btnX = px + 0.010

    self:drawButton("btn_call",           btnX, py + 0.092, btnW, btnH,
        "Call",           0.10, 0.48, 0.22, 0.011)
    self:drawButton("btn_message_contact", btnX, py + 0.052, btnW, btnH,
        "Message",        0.10, 0.35, 0.55, 0.011)
    self:drawButton("btn_delete_contact",  btnX, py + 0.012, btnW, btnH,
        "Delete Contact", 0.50, 0.10, 0.10, 0.010)
end

-- ─── MESSAGE THREAD screen (big screen) ──────────────────────────────────────
function RoleplayPhone:drawMessageThread()
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

    -- ── Header bar ────────────────────────────────────────────────────────────
    local headerH = 0.062
    local headerY = py + ph - 0.055 - headerH
    self:drawRect(px, headerY, pw, headerH, 0.07, 0.10, 0.16, 1.0)

    self:drawButton("btn_back", px + 0.010, headerY + 0.016, 0.055, 0.030,
        "< Back", 0.15, 0.18, 0.26, 0.011)

    -- Call button (top right of header)
    self:drawButton("btn_call", px + pw - 0.080, headerY + 0.016, 0.068, 0.030,
        "Call", 0.10, 0.48, 0.22, 0.011)

    -- Avatar (small, in header)
    local avSz = 0.036
    local avX  = px + pw/2 - avSz/2
    local avY  = headerY + (headerH - avSz) / 2
    self:drawRect(avX, avY, avSz, avSz, 0.15, 0.32, 0.60, 1.0)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(avX + avSz/2, avY + avSz * 0.18, 0.018,
        string.upper(string.sub(c.name or "?", 1, 1)))

    -- Name + farm below avatar in header
    setTextBold(true)
    setTextColor(0.92, 0.95, 1.0, 1.0)
    renderText(px + pw/2, headerY + 0.006, 0.013, c.name or "Unknown")
    setTextBold(false)
    setTextColor(0.50, 0.62, 0.78, 0.85)
    renderText(px + pw/2, headerY - 0.006, 0.009,
        (c.farmName ~= "" and c.farmName) or "")

    -- ── Compose bar (bottom) ──────────────────────────────────────────────────
    local composeH  = 0.052
    local composeY  = py + 0.006
    local sendBtnW  = 0.060
    local fieldX    = px + 0.010
    local fieldW    = pw - sendBtnW - 0.022
    local compose   = self.messageCompose

    -- Compose background
    self:drawRect(px, composeY, pw, composeH, 0.07, 0.09, 0.13, 1.0)
    self:drawRect(px, composeY + composeH - 0.002, pw, 0.002, 0.15, 0.18, 0.26, 0.6)

    -- Text input pill
    local pillH = 0.032
    local pillY = composeY + (composeH - pillH) / 2
    local active = compose.active
    local pillBg = active and 0.16 or 0.10
    self:drawRect(fieldX, pillY, fieldW, pillH, pillBg, pillBg + 0.03, pillBg + 0.08, 1.0)
    self:drawRect(fieldX, pillY + pillH - 0.002, fieldW, 0.002, 0.3, 0.4, 0.6,
        active and 0.8 or 0.3)

    local displayText = (compose.text == "" and not active) and "Message..." or compose.text
    local displayCol  = (compose.text == "" and not active) and 0.40 or 1.0
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(displayCol, displayCol, displayCol, 0.85)
    renderText(fieldX + 0.008, pillY + pillH * 0.25, 0.012,
        displayText .. (active and "|" or ""))
    self:addHitbox("msg_field", fieldX, pillY, fieldW, pillH, {})

    -- Send button
    local canSend = compose.text ~= ""
    local sbX = fieldX + fieldW + 0.006
    local sbR = canSend and 0.10 or 0.15
    local sbG = canSend and 0.42 or 0.18
    local sbB = canSend and 0.22 or 0.20
    self:drawButton("btn_send_message", sbX, pillY, sendBtnW - 0.004, pillH,
        "Send", sbR, sbG, sbB, 0.010)

    -- ── Message thread (between header and compose bar) ───────────────────────
    local threadTop = headerY - 0.008
    local threadBot = composeY + composeH + 0.006
    local threadH   = threadTop - threadBot

    -- Clip region visual (subtle inner border)
    self:drawRect(px, threadBot, pw, 0.001, 0.12, 0.14, 0.20, 0.4)

    local msgs = self.messages[self.selectedContact] or {}

    if #msgs == 0 then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(0.35, 0.40, 0.50, 0.8)
        renderText(px + pw/2, threadBot + threadH/2, 0.012,
            "No messages yet.")
        renderText(px + pw/2, threadBot + threadH/2 - 0.018, 0.010,
            "Say something!")
    else
        -- Show most recent messages that fit, newest at bottom
        -- Calculate how many we can fit
        local bubblePad  = 0.008
        local bubbleH    = 0.038   -- height per message row (wrapping is TODO)
        local bubbleGap  = 0.006
        local maxVisible = math.floor(threadH / (bubbleH + bubbleGap))
        local startIdx   = math.max(1, #msgs - maxVisible + 1)

        local curY = threadBot + bubblePad
        for i = startIdx, #msgs do
            local msg      = msgs[i]
            local isSent   = msg.sent
            local bubbleW  = pw * 0.68
            local bx       = isSent and (px + pw - bubbleW - 0.012) or (px + 0.012)

            -- Bubble background
            local br = isSent and 0.10 or 0.14
            local bg = isSent and 0.40 or 0.18
            local bb = isSent and 0.20 or 0.42
            self:drawRect(bx, curY, bubbleW, bubbleH, br, bg, bb, 1.0)

            -- Message text
            setTextAlignment(isSent and RenderText.ALIGN_RIGHT or RenderText.ALIGN_LEFT)
            setTextBold(false)
            setTextColor(1, 1, 1, 0.95)
            local textX = isSent and (bx + bubbleW - 0.008) or (bx + 0.008)
            renderText(textX, curY + bubbleH * 0.35, 0.011, msg.text or "")

            -- Day label (small, muted)
            setTextAlignment(isSent and RenderText.ALIGN_RIGHT or RenderText.ALIGN_LEFT)
            setTextColor(0.55, 0.65, 0.75, 0.7)
            renderText(textX, curY + bubbleH * 0.68, 0.008,
                string.format("Day %d", msg.gameDay or 0))

            curY = curY + bubbleH + bubbleGap
        end
    end
end


-- ─── CONTACT CREATE screen ────────────────────────────────────────────────────
function RoleplayPhone:drawContactCreate()
    local s  = self.PHONE
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    self:drawRect(px, py, pw, ph, 0.06, 0.07, 0.10, 0.97)

    local contentY = py + ph - 0.012

    -- Header bar
    local headerH = 0.042
    local headerY = contentY - headerH
    self:drawRect(px, headerY, pw, headerH, 0.10, 0.13, 0.20, 1.0)

    self:drawButton("btn_back", px + 0.010, headerY + 0.010, 0.055, 0.030,
        "< Back", 0.18, 0.20, 0.28, 0.011)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.30, 0.016, "New Contact")

    -- Fields (no X buttons — use Backspace to delete)
    local f    = self.contactForm
    local fX   = px + 0.012
    local fW   = pw - 0.024
    local fH   = 0.044
    local fGap = 0.008
    local fY   = headerY - 0.014

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


-- ─── SETTINGS screen ──────────────────────────────────────────────────────────
function RoleplayPhone:drawSettings()
    local s  = self.BIG
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h
    local cx = px + pw / 2

    self:drawBigScreen()

    local contentY = py + ph - 0.055
    local headerH  = 0.05
    local headerY  = contentY - headerH

    -- Semi-transparent dark tint over wallpaper so text is readable (wallpaper still visible)
    self:drawRect(px, py, pw, ph, 0.0, 0.0, 0.0, 0.55)

    -- Header
    self:drawRect(px, headerY, pw, headerH, 0.12, 0.08, 0.20, 1.0)
    self:drawButton("btn_back", px + 0.010, headerY + 0.010, 0.055, 0.030,
        "< Back", 0.16, 0.10, 0.24, 0.011)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(cx, headerY + headerH * 0.30, 0.016, "Settings")

    local cy     = headerY - 0.018
    local rowH   = 0.040
    local optW   = 0.090
    local optGap = 0.008
    local indent = px + 0.018
    local labelW = pw * 0.45

    -- ── Section: Clock Format ─────────────────────────────────────────────────
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(0.55, 0.45, 0.75, 0.85)
    renderText(indent, cy, 0.009, "CLOCK FORMAT")
    cy = cy - 0.028

    local is12 = self.settings.timeFormat == "12"
    self:drawButton("setting_timeformat_12",
        indent, cy - rowH, optW, rowH,
        "12 hr", is12 and 0.28 or 0.12, is12 and 0.18 or 0.10, is12 and 0.45 or 0.22, 0.012)
    if is12 then
        self:drawRect(indent, cy - rowH, 0.004, rowH, 0.70, 0.50, 1.0, 1.0)
    end
    self:drawButton("setting_timeformat_24",
        indent + optW + optGap, cy - rowH, optW, rowH,
        "24 hr", not is12 and 0.28 or 0.12, not is12 and 0.18 or 0.10,
        not is12 and 0.45 or 0.22, 0.012)
    if not is12 then
        self:drawRect(indent + optW + optGap, cy - rowH, 0.004, rowH, 0.70, 0.50, 1.0, 1.0)
    end
    cy = cy - rowH - 0.022

    -- ── Section: Temperature Unit ─────────────────────────────────────────────
    setTextBold(false)
    setTextColor(0.55, 0.45, 0.75, 0.85)
    renderText(indent, cy, 0.009, "TEMPERATURE")
    cy = cy - 0.028

    local isF = self.settings.tempUnit == "F"
    self:drawButton("setting_temp_F",
        indent, cy - rowH, optW, rowH,
        "°F", isF and 0.28 or 0.12, isF and 0.18 or 0.10, isF and 0.45 or 0.22, 0.013)
    if isF then
        self:drawRect(indent, cy - rowH, 0.004, rowH, 0.70, 0.50, 1.0, 1.0)
    end
    self:drawButton("setting_temp_C",
        indent + optW + optGap, cy - rowH, optW, rowH,
        "°C", not isF and 0.28 or 0.12, not isF and 0.18 or 0.10,
        not isF and 0.45 or 0.22, 0.013)
    if not isF then
        self:drawRect(indent + optW + optGap, cy - rowH, 0.004, rowH, 0.70, 0.50, 1.0, 1.0)
    end
    cy = cy - rowH - 0.022

    -- ── Section: Battery Widget ───────────────────────────────────────────────
    setTextBold(false)
    setTextColor(0.55, 0.45, 0.75, 0.85)
    renderText(indent, cy, 0.009, "BATTERY WIDGET")
    cy = cy - 0.028

    local batOn = self.settings.batteryVisible
    local batLbl = batOn and "ON" or "OFF"
    local batR = batOn and 0.08 or 0.22
    local batG = batOn and 0.42 or 0.14
    local batB = batOn and 0.18 or 0.14
    self:drawButton("setting_battery_toggle",
        indent, cy - rowH, optW, rowH,
        batLbl, batR, batG, batB, 0.013)
    if batOn then
        self:drawRect(indent, cy - rowH, 0.004, rowH, 0.20, 0.85, 0.35, 1.0)
    end
    cy = cy - rowH - 0.022

    -- ── Section: Wallpaper ────────────────────────────────────────────────────
    setTextBold(false)
    setTextColor(0.55, 0.45, 0.75, 0.85)
    renderText(indent, cy, 0.009, "WALLPAPER")
    cy = cy - 0.028

    -- Calculate swatch size to fit all 7 within phone width
    local numSwatches = #self.WALLPAPERS
    local swatchGap = 0.006
    local totalGaps = (numSwatches - 1) * swatchGap
    local swatchSz  = (pw - (indent - px) * 2 - totalGaps) / numSwatches
    local swatchX   = indent

    for i, wp in ipairs(self.WALLPAPERS) do
        local isSelected = (self.settings.wallpaperIndex == i)
        -- Swatch square
        self:drawRect(swatchX, cy - swatchSz, swatchSz, swatchSz, wp.r, wp.g, wp.b, 1.0)
        -- Selection ring
        if isSelected then
            self:drawRect(swatchX - 0.003, cy - swatchSz - 0.003,
                swatchSz + 0.006, swatchSz + 0.006,
                0.80, 0.60, 1.0, 0.0)
            self:drawRect(swatchX - 0.003, cy - swatchSz - 0.003,
                swatchSz + 0.006, 0.002, 0.80, 0.60, 1.0, 1.0)
            self:drawRect(swatchX - 0.003, cy - 0.003,
                swatchSz + 0.006, 0.002, 0.80, 0.60, 1.0, 1.0)
            self:drawRect(swatchX - 0.003, cy - swatchSz - 0.003,
                0.002, swatchSz + 0.006, 0.80, 0.60, 1.0, 1.0)
            self:drawRect(swatchX + swatchSz + 0.001, cy - swatchSz - 0.003,
                0.002, swatchSz + 0.006, 0.80, 0.60, 1.0, 1.0)
        end
        -- Name label
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(isSelected)
        setTextColor(isSelected and 0.90 or 0.55,
                     isSelected and 0.80 or 0.50,
                     isSelected and 1.00 or 0.70, 1.0)
        renderText(swatchX + swatchSz / 2, cy - swatchSz - 0.014, 0.009, wp.name)

        self:addHitbox("setting_wallp_" .. i,
            swatchX - 0.004, cy - swatchSz - 0.018, swatchSz + 0.008, swatchSz + 0.022, {})

        swatchX = swatchX + swatchSz + swatchGap
    end
end

-- ─── Settings save / load (modSettings XML, per-player, cosmetic) ─────────────
function RoleplayPhone:saveSettings()
    local xmlPath = getUserProfileAppPath()
        .. "modSettings/FS25_RoleplayInvoices_settings.xml"
    local xmlFile = createXMLFile("RP_Settings", xmlPath, "phoneSettings")
    if not xmlFile or xmlFile == 0 then return end

    setXMLString(xmlFile, "phoneSettings#timeFormat",    self.settings.timeFormat    or "12")
    setXMLString(xmlFile, "phoneSettings#tempUnit",      self.settings.tempUnit      or "F")
    setXMLInt(xmlFile,    "phoneSettings#wallpaperIndex",self.settings.wallpaperIndex or 1)
    setXMLBool(xmlFile,   "phoneSettings#batteryVisible",self.settings.batteryVisible)

    saveXMLFile(xmlFile)
    delete(xmlFile)
    print("[RoleplayPhone] Settings saved")
end

function RoleplayPhone:loadSettings()
    local xmlPath = getUserProfileAppPath()
        .. "modSettings/FS25_RoleplayInvoices_settings.xml"
    local xmlFile = loadXMLFile("RP_Settings", xmlPath)
    if not xmlFile or xmlFile == 0 then
        print("[RoleplayPhone] No settings file found, using defaults")
        return
    end

    local tf = getXMLString(xmlFile, "phoneSettings#timeFormat")
    if tf == "12" or tf == "24" then self.settings.timeFormat = tf end

    local tu = getXMLString(xmlFile, "phoneSettings#tempUnit")
    if tu == "F" or tu == "C" then self.settings.tempUnit = tu end

    local wi = getXMLInt(xmlFile, "phoneSettings#wallpaperIndex")
    if wi and wi >= 1 and wi <= #self.WALLPAPERS then
        self.settings.wallpaperIndex = wi
    end

    local bv = getXMLBool(xmlFile, "phoneSettings#batteryVisible")
    if bv ~= nil then self.settings.batteryVisible = bv end

    delete(xmlFile)
    print(string.format("[RoleplayPhone] Settings loaded: %s, %s, wallpaper=%d, battery=%s",
        self.settings.timeFormat, self.settings.tempUnit,
        self.settings.wallpaperIndex, tostring(self.settings.batteryVisible)))
end

-- ─── RECENT CALLS screen (small phone screen) ────────────────────────────────
function RoleplayPhone:drawCallsList()
    local s  = self.PHONE
    local px = s.x
    local py = s.y
    local pw = s.w
    local ph = s.h

    -- Phone shell background
    self:drawRect(px, py, pw, ph, 0.06, 0.07, 0.10, 0.97)

    -- Header
    local headerH = 0.042
    local headerY = py + ph - 0.012 - headerH
    self:drawRect(px, headerY, pw, headerH, 0.08, 0.11, 0.18, 1.0)
    self:drawButton("btn_back", px + 0.006, headerY + 0.008, 0.045, 0.026,
        "< Back", 0.12, 0.15, 0.22, 0.010)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(px + pw / 2, headerY + headerH * 0.28, 0.013, "Recent Calls")

    -- List
    local history = self.callHistory
    if #history == 0 then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(false)
        setTextColor(0.45, 0.50, 0.60, 0.8)
        renderText(px + pw / 2, py + ph / 2, 0.011, "No recent calls.")
        return
    end

    local rowH   = 0.048
    local rowGap = 0.003
    local listY  = headerY - 0.008

    for i, entry in ipairs(history) do
        local rowY = listY - (i - 1) * (rowH + rowGap)
        if rowY - rowH < py then break end

        local shade = (i % 2 == 0) and 0.10 or 0.085
        self:drawRect(px, rowY - rowH, pw, rowH, shade, shade + 0.01, shade + 0.025, 1.0)

        -- Direction icon color and symbol
        local dirColor = {1, 1, 1}
        local dirSymbol = "→"
        if entry.direction == "incoming" then
            dirColor = {0.20, 0.80, 0.40}
            dirSymbol = "↙"
        elseif entry.direction == "missed" then
            dirColor = {0.90, 0.25, 0.25}
            dirSymbol = "↙"
        elseif entry.direction == "outgoing" then
            dirColor = {0.40, 0.65, 1.0}
            dirSymbol = "↗"
        end

        -- Direction arrow
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(true)
        setTextColor(dirColor[1], dirColor[2], dirColor[3], 1.0)
        renderText(px + 0.008, rowY - rowH + rowH * 0.28, 0.014, dirSymbol)

        -- Contact name
        setTextBold(true)
        setTextColor(0.92, 0.95, 1.0, 1.0)
        renderText(px + 0.026, rowY - rowH + rowH * 0.28, 0.012, entry.name or "Unknown")

        -- Direction label
        setTextBold(false)
        setTextColor(dirColor[1], dirColor[2], dirColor[3], 0.75)
        local label = entry.direction == "missed" and "Missed" 
            or entry.direction == "incoming" and "Incoming"
            or "Outgoing"
        renderText(px + 0.026, rowY - rowH + rowH * 0.62, 0.009, label)
    end
end


-- ─── Mission00 hooks ─────────────────────────────────────────────────────────
Mission00.update = Utils.appendedFunction(Mission00.update, function(mission, dt)
    RoleplayPhone:updateBattery(dt / 1000)
    RoleplayPhone:updateCallTimeout(dt)
    RoleplayPhone:updateCallKeyPoll()
end)

Mission00.draw = Utils.appendedFunction(Mission00.draw, function(mission)
    if not RoleplayPhone.inputRegistered then return end
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

-- FS25 calls these on every registered mod event listener during game save/load.
-- Without them the engine fails the entire save with Error 7.
function _phoneKeyListener:saveToXMLFile(xmlFilename, key, usedModNames)
    RoleplayPhone:saveInvoices()
end

function _phoneKeyListener:loadFromXMLFile(xmlFilename, key)
    -- Loading is handled in Mission00.loadMap hook via RoleplayPhone:loadSavedData()
end

addModEventListener(_phoneKeyListener)

Mission00.loadMap = Utils.appendedFunction(Mission00.loadMap, function(mission, name)
    RoleplayPhone:init()
    RoleplayPhone:loadSavedData()
end)

-- Register the phone keybinding after gameplay fully starts.
-- The correct hook is MessageType.CURRENT_MISSION_LOADED via g_messageCenter --
-- that is the exact same event the built-in Player class uses to register its
-- own input actions (see Player:initialise). It fires AFTER "Entered Gameplay"
-- on both host and MP clients, so registration always lands at the right time.
RoleplayPhone.inputRegistered = false

g_messageCenter:subscribe(MessageType.CURRENT_MISSION_LOADED, function()
    if RoleplayPhone.inputRegistered then return end
    print("[RoleplayPhone] CURRENT_MISSION_LOADED fired, registering keybind")
    RoleplayPhone:registerKeybind()

    -- Login notification: fires after "Entered Gameplay" so farmId is reliable
    local myFarmId = RoleplayPhone:getMyFarmId()
    local unpaid = 0
    for _, inv in pairs(InvoiceManager.invoices) do
        if inv.toFarmId == myFarmId and inv.status == "PENDING" then
            unpaid = unpaid + 1
        end
    end
    if unpaid > 0 then
        local msg = unpaid == 1
            and "You have 1 unpaid invoice."
            or  string.format("You have %d unpaid invoices.", unpaid)
        NotificationManager:push("info", msg)
    end

    -- Client-pull contact sync: ask host for our saved contacts
    -- Host replies with RI_ContactSyncEvent containing this farm's contacts
    if g_server == nil and myFarmId and myFarmId > 0 then
        g_client:getServerConnection():sendEvent(
            RI_ContactEvent.new("request", myFarmId, 0, {}))
        print(string.format("[RoleplayPhone] Requested contact sync for farm %d", myFarmId))
    end
end, RoleplayPhone)

function RoleplayPhone:registerKeybind()
    if self.inputRegistered then return end

    -- Register F7 in PLAYER context (on foot)
    g_inputBinding:beginActionEventsModification("PLAYER")
    local _, eventId = g_inputBinding:registerActionEvent(
        "RI_OPEN_PHONE", RoleplayPhone, RoleplayPhone.toggle,
        false, true, false, true)
    self.actionEventId = eventId
    if eventId then
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_RI_OPEN_PHONE"))
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL or 0)
        print("[RoleplayPhone] RI_OPEN_PHONE registered OK: " .. tostring(eventId))
    else
        print("[RoleplayPhone] WARNING: RI_OPEN_PHONE registration failed")
    end
    g_inputBinding:endActionEventsModification()

    -- Register F8 outside any context so it fires on foot AND in vehicles
    local _, callEventId = g_inputBinding:registerActionEvent(
        "RI_CALL_ACTION", RoleplayPhone, RoleplayPhone.callAction,
        false, true, false, true)
    self.callActionEventId = callEventId
    if callEventId then
        g_inputBinding:setActionEventText(callEventId, g_i18n:getText("input_RI_CALL_ACTION"))
        g_inputBinding:setActionEventTextPriority(callEventId, GS_PRIO_NORMAL or 0)
        g_inputBinding:setActionEventTextVisibility(callEventId, false)
        print("[RoleplayPhone] RI_CALL_ACTION registered OK: " .. tostring(callEventId))
    else
        print("[RoleplayPhone] WARNING: RI_CALL_ACTION registration failed")
    end

    self.inputRegistered = true
end

-- F8 handler: answer if incoming, hang up if outgoing or active
function RoleplayPhone:callAction()
    if self.state == self.STATE.CALL_INCOMING then
        self:answerCall()
    elseif self.state == self.STATE.CALL_OUTGOING
        or self.state == self.STATE.CALL_ACTIVE then
        self:endCall()
    end
end

-- Backspace handler: removes last character from whatever field is active
function RoleplayPhone:handleBackspace()
    print("[RoleplayPhone] handleBackspace called, state=" .. tostring(self.state))
    if self.state == self.STATE.INVOICE_CREATE and self.form.activeField then
        local f = self.form.activeField
        local v = self.form[f] or ""
        if #v > 0 then self.form[f] = v:sub(1, #v - 1) end

    elseif self.state == self.STATE.CONTACT_CREATE and self.contactForm.activeField then
        local f = self.contactForm.activeField
        local v = self.contactForm[f] or ""
        if #v > 0 then self.contactForm[f] = v:sub(1, #v - 1) end

    elseif self.state == self.STATE.MESSAGE_THREAD and self.messageCompose.active then
        local v = self.messageCompose.text or ""
        if #v > 0 then self.messageCompose.text = v:sub(1, #v - 1) end
    end
end

-- Poll F8 key state every frame — works in vehicles where keyboardEvent doesn't fire
function RoleplayPhone:updateCallKeyPoll()
    local isInCall = self.state == self.STATE.CALL_INCOMING
                  or self.state == self.STATE.CALL_OUTGOING
                  or self.state == self.STATE.CALL_ACTIVE
    if not isInCall then
        self._f8WasDown = false
        return
    end

    local isDown = Input.isKeyPressed ~= nil and Input.isKeyPressed(Input.KEY_f8)

    -- Edge trigger: only fire on press, not hold
    if isDown and not self._f8WasDown then
        print("[RoleplayPhone] F8 polled — triggering callAction")
        self:callAction()
    end
    self._f8WasDown = isDown
end
-- FS25 calls Mission00.keyboardEvent(unicode, sym, modifier, isDown) every frame
-- a key is pressed. We forward to RoleplayPhone:keyEvent which handles all field input.
Mission00.keyboardEvent = Utils.appendedFunction(Mission00.keyboardEvent,
    function(mission, unicode, sym, modifier, isDown)
        -- F8 for call answer/hangup — detected at mission level so it works in vehicles too
        if isDown and Input.KEY_f8 ~= nil and sym == Input.KEY_f8 then
            print("[RoleplayPhone] F8 detected in keyboardEvent, state=" .. tostring(RoleplayPhone.state))
            RoleplayPhone:callAction()
        end
        if RoleplayPhone.state ~= RoleplayPhone.STATE.CLOSED then
            RoleplayPhone:keyEvent(unicode, sym, modifier, isDown)
        end
    end
)

Mission00.deleteMap = Utils.appendedFunction(Mission00.deleteMap, function(mission)
    -- Safety net: if phone was open when map unloads, restore cursor and input context
    if RoleplayPhone.isOpen then
        g_inputBinding:setShowMouseCursor(false)
        if RoleplayPhone.phoneContextEventId then
            g_inputBinding:removeActionEvent(RoleplayPhone.phoneContextEventId)
            RoleplayPhone.phoneContextEventId = nil
        end
        g_inputBinding:revertContext(true)
        RoleplayPhone.isOpen = false
    end
    if RoleplayPhone.actionEventId then
        g_inputBinding:removeActionEvent(RoleplayPhone.actionEventId)
        RoleplayPhone.actionEventId = nil
    end
    if RoleplayPhone.callActionEventId then
        g_inputBinding:removeActionEvent(RoleplayPhone.callActionEventId)
        RoleplayPhone.callActionEventId = nil
    end
    g_messageCenter:unsubscribeAll(RoleplayPhone)
    RoleplayPhone.inputRegistered = false
    -- Clean up texture overlays
    if RoleplayPhone.whiteOverlay   and RoleplayPhone.whiteOverlay   ~= 0 then delete(RoleplayPhone.whiteOverlay)   end
    if RoleplayPhone.wallpaper      and RoleplayPhone.wallpaper      ~= 0 then delete(RoleplayPhone.wallpaper)      end
    if RoleplayPhone.iconInvoices   and RoleplayPhone.iconInvoices   ~= 0 then delete(RoleplayPhone.iconInvoices)   end
    if RoleplayPhone.iconContacts   and RoleplayPhone.iconContacts   ~= 0 then delete(RoleplayPhone.iconContacts)   end
    if RoleplayPhone.iconCalls      and RoleplayPhone.iconCalls      ~= 0 then delete(RoleplayPhone.iconCalls)      end
    if RoleplayPhone.iconSettings   and RoleplayPhone.iconSettings   ~= 0 then delete(RoleplayPhone.iconSettings)   end
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
            -- Host also stores knownFarms locally so resolveFarmId works on host too
            RoleplayPhone.knownFarms = farms
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
        -- Contacts use client-pull: client sends RI_ContactEvent("request") after
        -- CURRENT_MISSION_LOADED so we know their farmId. No push needed here.
    end
)
