-- scripts/InvoiceSave.lua

InvoiceSave = {}

function InvoiceSave:saveToXML(xmlFile, key)
    local i = 0
    for _, invoice in pairs(InvoiceManager.invoices) do
        local invKey = string.format("%s.invoice(%d)", key, i)
        setXMLString(xmlFile, invKey .. "#category", invoice.category)
        setXMLInt(xmlFile, invKey .. "#fromFarm", invoice.fromFarmId)
        setXMLInt(xmlFile, invKey .. "#toFarm", invoice.toFarmId)
        setXMLFloat(xmlFile, invKey .. "#amount", invoice.amount)
        setXMLString(xmlFile, invKey .. "#description", invoice.description)
        setXMLString(xmlFile, invKey .. "#notes", invoice.notes)

        if invoice.status ~= nil then
            setXMLString(xmlFile, invKey .. "#status", invoice.status)
        end
        if invoice.dueDate ~= nil then
            setXMLString(xmlFile, invKey .. "#dueDate", tostring(invoice.dueDate))
        end

        i = i + 1
    end
end

function InvoiceSave:loadFromXML(xmlFile, key)
    local i = 0
    while true do
        local invKey = string.format("%s.invoice(%d)", key, i)
        if not hasXMLProperty(xmlFile, invKey) then
            break
        end

        local data = {
            id = i,
            category = getXMLString(xmlFile, invKey .. "#category"),
            fromFarmId = getXMLInt(xmlFile, invKey .. "#fromFarm"),
            toFarmId = getXMLInt(xmlFile, invKey .. "#toFarm"),
            amount = getXMLFloat(xmlFile, invKey .. "#amount"),
            description = getXMLString(xmlFile, invKey .. "#description"),
            notes = getXMLString(xmlFile, invKey .. "#notes"),
            status = getXMLString(xmlFile, invKey .. "#status"),
            dueDate = getXMLString(xmlFile, invKey .. "#dueDate")
        }

        InvoiceManager:addInvoice(Invoice.new(data))
        i = i + 1
    end
end
