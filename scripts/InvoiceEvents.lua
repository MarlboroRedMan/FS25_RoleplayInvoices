-- scripts/InvoiceEvents.lua

InvoiceEvents = {}

-- Placeholder event for MP sync. (We'll implement readStream/writeStream later.)
InvoiceEvents.SendInvoiceEvent = {}
InvoiceEvents.SendInvoiceEvent_mt = Class(InvoiceEvents.SendInvoiceEvent, Event)
InitEventClass(InvoiceEvents.SendInvoiceEvent, "RoleplayInvoices_SendInvoiceEvent")

function InvoiceEvents.SendInvoiceEvent.emptyNew()
    return Event.new(InvoiceEvents.SendInvoiceEvent_mt)
end

function InvoiceEvents.SendInvoiceEvent.new(invoice)
    local self = InvoiceEvents.SendInvoiceEvent.emptyNew()
    self.invoice = invoice
    return self
end

function InvoiceEvents.SendInvoiceEvent:readStream(streamId, connection)
    -- TODO: implement MP serialization (invoice fields) later
end

function InvoiceEvents.SendInvoiceEvent:writeStream(streamId, connection)
    -- TODO: implement MP serialization (invoice fields) later
end

function InvoiceEvents.SendInvoiceEvent:run(connection)
    if self.invoice ~= nil then
        InvoiceManager:addInvoice(self.invoice)
    end
end