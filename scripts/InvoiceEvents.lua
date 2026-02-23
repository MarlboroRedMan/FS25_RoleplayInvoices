-- scripts/InvoiceEvents.lua
-- Network events for MP sync.
-- IMPORTANT: FS25 requires event classes to be top-level globals, not nested in tables.

InvoiceEvents = {}


-- ─────────────────────────────────────────────────────────────────────────────
-- EVENT 1: Send a new invoice to all clients
-- ─────────────────────────────────────────────────────────────────────────────

if RI_SendInvoiceEvent == nil then
    RI_SendInvoiceEvent    = {}
    RI_SendInvoiceEvent_mt = Class(RI_SendInvoiceEvent, Event)
    InitEventClass(RI_SendInvoiceEvent, "RI_SendInvoiceEvent")
end

function RI_SendInvoiceEvent.emptyNew()
    return Event.new(RI_SendInvoiceEvent_mt)
end

function RI_SendInvoiceEvent.new(invoice, showNotification)
    local self = RI_SendInvoiceEvent.emptyNew()
    self.invoice          = invoice
    self.showNotification = (showNotification ~= false)  -- default true
    return self
end

function RI_SendInvoiceEvent:writeStream(streamId, connection)
    local inv = self.invoice
    streamWriteInt32(streamId,   inv.id          or 0)
    streamWriteInt32(streamId,   inv.fromFarmId  or 0)
    streamWriteInt32(streamId,   inv.toFarmId    or 0)
    streamWriteFloat32(streamId, inv.amount      or 0)
    streamWriteInt32(streamId,   inv.createdDate or 0)
    streamWriteString(streamId,  inv.category    or "")
    streamWriteString(streamId,  inv.description or "")
    streamWriteString(streamId,  inv.notes       or "")
    streamWriteString(streamId,  inv.dueDate     or "")
    streamWriteString(streamId,  inv.status      or "PENDING")
    streamWriteBool(streamId,    self.showNotification)
end

function RI_SendInvoiceEvent:readStream(streamId, connection)
    local data = {
        id          = streamReadInt32(streamId),
        fromFarmId  = streamReadInt32(streamId),
        toFarmId    = streamReadInt32(streamId),
        amount      = streamReadFloat32(streamId),
        createdDate = streamReadInt32(streamId),
        category    = streamReadString(streamId),
        description = streamReadString(streamId),
        notes       = streamReadString(streamId),
        dueDate     = streamReadString(streamId),
        status      = streamReadString(streamId),
    }
    self.invoice          = Invoice.new(data)
    self.showNotification = streamReadBool(streamId)
    self:run(connection)
end

function RI_SendInvoiceEvent:run(connection)
    if self.invoice == nil then return end

    -- Avoid duplicates: client already added the invoice locally when sending
    -- so skip adding if we already have it
    local alreadyExists = false
    for _, inv in pairs(InvoiceManager.invoices) do
        if inv.id == self.invoice.id then
            alreadyExists = true
            break
        end
    end

    if not alreadyExists then
        InvoiceManager:addInvoice(self.invoice)
    end

    -- Save now that invoice is in manager (host only - clients don't have savegame)
    if g_server ~= nil then
        RoleplayPhone:saveInvoices()
    end

    -- Server forwards to all other clients (GIANTS pattern: check connection origin)
    if connection ~= nil and not connection:getIsServer() then
        g_server:broadcastEvent(RI_SendInvoiceEvent.new(self.invoice, true), false, connection)
    end

    -- Show notification to the recipient farm (skip during initial sync on connect)
    if self.showNotification and not alreadyExists then
        local myFarmId = RoleplayPhone:getMyFarmId()
        print(string.format("[InvoiceEvents] Invoice check: myFarmId=%d toFarmId=%d",
            myFarmId, self.invoice.toFarmId or -1))
        if self.invoice.toFarmId == myFarmId then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                string.format("New invoice from Farm %d  -  $%s",
                    self.invoice.fromFarmId,
                    tostring(math.floor(self.invoice.amount or 0))))
        end
    end

    print(string.format("[InvoiceEvents] Invoice #%d synced", self.invoice.id or 0))
end

-- Keep old name accessible so RoleplayPhone.lua references still work
InvoiceEvents.SendInvoiceEvent = RI_SendInvoiceEvent


-- ─────────────────────────────────────────────────────────────────────────────
-- EVENT 2: Update invoice status (PAID / REJECTED) across all clients
-- ─────────────────────────────────────────────────────────────────────────────

if RI_UpdateInvoiceEvent == nil then
    RI_UpdateInvoiceEvent    = {}
    RI_UpdateInvoiceEvent_mt = Class(RI_UpdateInvoiceEvent, Event)
    InitEventClass(RI_UpdateInvoiceEvent, "RI_UpdateInvoiceEvent")
end

function RI_UpdateInvoiceEvent.emptyNew()
    return Event.new(RI_UpdateInvoiceEvent_mt)
end

function RI_UpdateInvoiceEvent.new(invoiceId, status)
    local self = RI_UpdateInvoiceEvent.emptyNew()
    self.invoiceId = invoiceId
    self.status    = status
    return self
end

function RI_UpdateInvoiceEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,  self.invoiceId or 0)
    streamWriteString(streamId, self.status    or "PAID")
end

function RI_UpdateInvoiceEvent:readStream(streamId, connection)
    self.invoiceId = streamReadInt32(streamId)
    self.status    = streamReadString(streamId)
    self:run(connection)
end

function RI_UpdateInvoiceEvent:run(connection)
    -- Update locally by matching invoice id
    for _, inv in pairs(InvoiceManager.invoices) do
        if inv.id == self.invoiceId then
            inv.status = self.status
            print(string.format("[InvoiceEvents] Invoice #%d updated to %s",
                self.invoiceId, self.status))
            break
        end
    end

    -- Server forwards to all other clients (GIANTS pattern)
    if connection ~= nil and not connection:getIsServer() then
        g_server:broadcastEvent(
            RI_UpdateInvoiceEvent.new(self.invoiceId, self.status), false, connection)
    end
end

InvoiceEvents.UpdateInvoiceEvent = RI_UpdateInvoiceEvent


-- ─────────────────────────────────────────────────────────────────────────────
-- EVENT 3: Ping — send a message to a specific farm
-- ─────────────────────────────────────────────────────────────────────────────

if RI_PingEvent == nil then
    RI_PingEvent    = {}
    RI_PingEvent_mt = Class(RI_PingEvent, Event)
    InitEventClass(RI_PingEvent, "RI_PingEvent")
end

function RI_PingEvent.emptyNew()
    return Event.new(RI_PingEvent_mt)
end

function RI_PingEvent.new(fromFarmId, toFarmId, message)
    local self = RI_PingEvent.emptyNew()
    self.fromFarmId = fromFarmId
    self.toFarmId   = toFarmId
    self.message    = message
    return self
end

function RI_PingEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,  self.fromFarmId or 0)
    streamWriteInt32(streamId,  self.toFarmId   or 0)
    streamWriteString(streamId, self.message    or "")
end

function RI_PingEvent:readStream(streamId, connection)
    self.fromFarmId = streamReadInt32(streamId)
    self.toFarmId   = streamReadInt32(streamId)
    self.message    = streamReadString(streamId)
    self:run(connection)
end

function RI_PingEvent:run(connection)
    -- Server forwards to all other clients (GIANTS pattern)
    if connection ~= nil and not connection:getIsServer() then
        g_server:broadcastEvent(
            RI_PingEvent.new(self.fromFarmId, self.toFarmId, self.message),
            false, connection)
    end

    -- Show notification to the target farm
    local myFarmId = RoleplayPhone:getMyFarmId()
    print(string.format("[InvoiceEvents] Ping check: myFarmId=%d toFarmId=%d",
        myFarmId, self.toFarmId or -1))
    if self.toFarmId == 0 or self.toFarmId == myFarmId then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("PING from Farm %d: %s", self.fromFarmId, self.message))
    end

    print(string.format("[InvoiceEvents] Ping Farm %d -> Farm %d: %s",
        self.fromFarmId, self.toFarmId, self.message))
end

InvoiceEvents.PingEvent = RI_PingEvent


-- ─────────────────────────────────────────────────────────────────────────────
-- EVENT 4: Farm List — host sends full farm list to a connecting client
-- ─────────────────────────────────────────────────────────────────────────────

if RI_FarmListEvent == nil then
    RI_FarmListEvent    = {}
    RI_FarmListEvent_mt = Class(RI_FarmListEvent, Event)
    InitEventClass(RI_FarmListEvent, "RI_FarmListEvent")
end

function RI_FarmListEvent.emptyNew()
    return Event.new(RI_FarmListEvent_mt)
end

function RI_FarmListEvent.new(farms)
    local self = RI_FarmListEvent.emptyNew()
    self.farms = farms  -- array of {farmId, name}
    return self
end

function RI_FarmListEvent:writeStream(streamId, connection)
    local farms = self.farms or {}
    streamWriteInt32(streamId, #farms)
    for _, farm in ipairs(farms) do
        streamWriteInt32(streamId,  farm.farmId or 0)
        streamWriteString(streamId, farm.name   or ("Farm " .. tostring(farm.farmId)))
    end
end

function RI_FarmListEvent:readStream(streamId, connection)
    local count = streamReadInt32(streamId)
    self.farms = {}
    for i = 1, count do
        local farmId = streamReadInt32(streamId)
        local name   = streamReadString(streamId)
        table.insert(self.farms, { farmId = farmId, name = name })
    end
    self:run(connection)
end

function RI_FarmListEvent:run(connection)
    -- Store the received farm list on the phone so getAvailableFarms() can use it
    if self.farms and #self.farms > 0 then
        RoleplayPhone.knownFarms = self.farms
        RoleplayPhone:clearFarmCache()
        print(string.format("[InvoiceEvents] Received farm list: %d farms", #self.farms))
        for _, f in ipairs(self.farms) do
            print(string.format("[InvoiceEvents]   Farm %d: %s", f.farmId, f.name))
        end
    end

    -- Flag that we need to show a pending invoice notification on next phone open
    -- Can't do it now because playerUserId isn't resolved yet at connect time
    RoleplayPhone.pendingInboxCheck = true
end

InvoiceEvents.FarmListEvent = RI_FarmListEvent


-- ─────────────────────────────────────────────────────────────────────────────
-- EVENT 5: Pay Invoice — client requests server to transfer money and mark paid
-- ─────────────────────────────────────────────────────────────────────────────

if RI_PayInvoiceEvent == nil then
    RI_PayInvoiceEvent    = {}
    RI_PayInvoiceEvent_mt = Class(RI_PayInvoiceEvent, Event)
    InitEventClass(RI_PayInvoiceEvent, "RI_PayInvoiceEvent")
end

function RI_PayInvoiceEvent.emptyNew()
    return Event.new(RI_PayInvoiceEvent_mt)
end

function RI_PayInvoiceEvent.new(invoiceId, fromFarmId, toFarmId, amount)
    local self = RI_PayInvoiceEvent.emptyNew()
    self.invoiceId  = invoiceId
    self.fromFarmId = fromFarmId  -- who sent the invoice (receives money)
    self.toFarmId   = toFarmId    -- who is paying (loses money)
    self.amount     = amount
    return self
end

function RI_PayInvoiceEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,   self.invoiceId  or 0)
    streamWriteInt32(streamId,   self.fromFarmId or 0)
    streamWriteInt32(streamId,   self.toFarmId   or 0)
    streamWriteFloat32(streamId, self.amount     or 0)
end

function RI_PayInvoiceEvent:readStream(streamId, connection)
    self.invoiceId  = streamReadInt32(streamId)
    self.fromFarmId = streamReadInt32(streamId)
    self.toFarmId   = streamReadInt32(streamId)
    self.amount     = streamReadFloat32(streamId)
    self:run(connection)
end

function RI_PayInvoiceEvent:run(connection)
    -- Only server does the actual money transfer
    if g_server ~= nil then
        local em = (g_currentMission and g_currentMission.economyManager) or g_economyManager
        local fm = (g_currentMission and g_currentMission.farmManager) or g_farmManager
        if em and fm then
            local payingFarm = fm:getFarmById(self.toFarmId)
            if payingFarm and payingFarm.money >= self.amount then
                -- Deduct from payer
                g_currentMission:addMoney(-self.amount, self.toFarmId, MoneyType.OTHER, true, true)
                -- Add to recipient
                g_currentMission:addMoney(self.amount, self.fromFarmId, MoneyType.OTHER, true, true)
                -- Mark invoice paid and broadcast status to all clients
                g_server:broadcastEvent(
                    RI_UpdateInvoiceEvent.new(self.invoiceId, "PAID"))
                -- Update server's local copy too
                for _, inv in pairs(InvoiceManager.invoices) do
                    if inv.id == self.invoiceId then
                        inv.status = "PAID"
                        break
                    end
                end
                RoleplayPhone:saveInvoices()
                print(string.format("[InvoiceEvents] Invoice #%d paid: $%.0f from Farm %d to Farm %d",
                    self.invoiceId, self.amount, self.toFarmId, self.fromFarmId))
            else
                print(string.format("[InvoiceEvents] Invoice #%d payment failed: insufficient funds",
                    self.invoiceId))
            end
        end
    end
end

InvoiceEvents.PayInvoiceEvent = RI_PayInvoiceEvent
