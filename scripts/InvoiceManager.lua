-- scripts/InvoiceManager.lua

InvoiceManager = {}
InvoiceManager.invoices = {}

-- Category list for the dropdown (v1)
InvoiceManager.categories = {
    "Rent - House (Small)",
    "Rent - House (Medium)",
    "Rent - House (Large)",
    "Rent - House (Luxury)",
    "Rent - Camper (Full Hookup)",
    "Rent - Camper (Water & Power)",
    "Rent - Camper (Electric Only)",
    "Rent - Camper (Land Use Only)",
    "Rent - Shop (Full Use)",
    "Rent - Shop (Single Bay)",
    "Rent - Storage (Indoor)",
    "Rent - Storage (Covered)",
    "Rent - Storage (Yard)",
    "Lease - Agricultural Land",
    "Lease - Yard / Equipment Staging",
    "Lease - Industrial / Mining Land",
    "Vehicle - Sale (Paid in Full)",
    "Vehicle - Sale (Installment Payment)",
    "Vehicle - Lease / Rental",
    "Service - Labor",
    "Service - Hauling",
    "Service - Equipment Operation",
    "Service - Snow / Mowing / Cleanup"
}

function InvoiceManager:addInvoice(invoice)
    self.invoices[invoice.id] = invoice
end

-- inbox=true -> invoices sent TO farmId
-- inbox=false -> invoices sent FROM farmId
function InvoiceManager:getInvoicesForFarm(farmId, inbox)
    local list = {}
    for _, invoice in pairs(self.invoices) do
        if inbox and invoice.toFarmId == farmId then
            table.insert(list, invoice)
        elseif (not inbox) and invoice.fromFarmId == farmId then
            table.insert(list, invoice)
        end
    end
    return list
end

function InvoiceManager:copyInvoice(invoice)
    local newData = {
        id = g_currentMission.time,
        fromFarmId = invoice.fromFarmId,
        toFarmId = invoice.toFarmId,
        category = invoice.category,
        amount = invoice.amount,
        description = invoice.description,
        notes = invoice.notes,
        dueDate = invoice.dueDate,
        status = "PENDING",
        createdDate = g_currentMission.environment.currentDay
    }
    return Invoice.new(newData)
end