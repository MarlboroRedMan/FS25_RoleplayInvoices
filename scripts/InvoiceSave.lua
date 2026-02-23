-- scripts/InvoiceSave.lua

InvoiceSave = {}

function InvoiceSave:saveToXML(xmlFile, key)
    local i = 0
    for _, invoice in pairs(InvoiceManager.invoices) do
        local invKey = string.format("%s.invoice(%d)", key, i)
        setXMLString(xmlFile, invKey .. "#category",    invoice.category    or "")
        setXMLInt   (xmlFile, invKey .. "#fromFarm",    invoice.fromFarmId  or 0)
        setXMLInt   (xmlFile, invKey .. "#toFarm",      invoice.toFarmId    or 0)
        setXMLFloat (xmlFile, invKey .. "#amount",      invoice.amount      or 0)
        setXMLString(xmlFile, invKey .. "#description", invoice.description or "")
        setXMLString(xmlFile, invKey .. "#notes",       invoice.notes       or "")
        setXMLString(xmlFile, invKey .. "#status",      invoice.status      or "PENDING")
        setXMLString(xmlFile, invKey .. "#dueDate",     tostring(invoice.dueDate or ""))
        if invoice.id ~= nil then
            setXMLInt(xmlFile, invKey .. "#id", invoice.id)
        end
        i = i + 1
    end

    -- Save contacts
    ContactManager:saveToXML(xmlFile, key .. ".contacts")
end

function InvoiceSave:loadFromXML(xmlFile, key)
    local i = 0
    while true do
        local invKey = string.format("%s.invoice(%d)", key, i)
        if not hasXMLProperty(xmlFile, invKey) then
            break
        end

        local data = {
            id          = getXMLInt   (xmlFile, invKey .. "#id")          or i,
            category    = getXMLString(xmlFile, invKey .. "#category")    or "",
            fromFarmId  = getXMLInt   (xmlFile, invKey .. "#fromFarm")    or 0,
            toFarmId    = getXMLInt   (xmlFile, invKey .. "#toFarm")      or 0,
            amount      = getXMLFloat (xmlFile, invKey .. "#amount")      or 0,
            description = getXMLString(xmlFile, invKey .. "#description") or "",
            notes       = getXMLString(xmlFile, invKey .. "#notes")       or "",
            status      = getXMLString(xmlFile, invKey .. "#status")      or "PENDING",
            dueDate     = getXMLString(xmlFile, invKey .. "#dueDate")     or "",
        }

        InvoiceManager:addInvoice(Invoice.new(data))
        i = i + 1
    end

    -- Load contacts
    ContactManager:loadFromXML(xmlFile, key .. ".contacts")
end


