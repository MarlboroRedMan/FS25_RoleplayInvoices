-- scripts/Invoice.lua

Invoice = {}
Invoice.__index = Invoice

function Invoice.new(data)
    local self = setmetatable({}, Invoice)
    self.id = data.id
    self.fromFarmId = data.fromFarmId
    self.toFarmId = data.toFarmId
    self.category = data.category
    self.amount = data.amount
    self.description = data.description or ""
    self.notes = data.notes or ""
    self.dueDate = data.dueDate
    self.status = data.status or "PENDING"
    self.createdDate = data.createdDate
    return self
end