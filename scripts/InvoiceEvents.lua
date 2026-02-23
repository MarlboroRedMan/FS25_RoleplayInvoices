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

function RI_SendInvoiceEvent.new(invoice)
    local self = RI_SendInvoiceEvent.emptyNew()
    self.invoice = invoice
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
    self.invoice = Invoice.new(data)
    self:run(connection)
end

function RI_SendInvoiceEvent:run(connection)
    if self.invoice == nil then return end

    -- Add invoice locally
    InvoiceManager:addInvoice(self.invoice)

    -- Save now that invoice is in manager (host only - clients don't have savegame)
    if g_server ~= nil then
        RoleplayPhone:saveInvoices()
    end

    -- Server forwards to all other clients (GIANTS pattern: check connection origin)
    if connection ~= nil and not connection:getIsServer() then
        g_server:broadcastEvent(RI_SendInvoiceEvent.new(self.invoice), false, connection)
    end

    -- Show notification to the recipient farm
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
