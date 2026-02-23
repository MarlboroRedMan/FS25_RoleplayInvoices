-- scripts/ContactManager.lua
-- Manages the player contact list (name, farm, phone, notes)
-- Save/load mirrors InvoiceSave XML pattern

ContactManager = {}
ContactManager.contacts = {}   -- ordered array of contact tables


-- ─── CRUD ─────────────────────────────────────────────────────────────────────

function ContactManager:addContact(data)
    table.insert(self.contacts, {
        name     = data.name     or "",
        farmName = data.farmName or "",
        phone    = data.phone    or "",
        notes    = data.notes    or "",
    })
end

function ContactManager:removeContact(index)
    table.remove(self.contacts, index)
end

function ContactManager:getContact(index)
    return self.contacts[index]
end

function ContactManager:count()
    return #self.contacts
end


-- ─── XML SAVE ─────────────────────────────────────────────────────────────────

function ContactManager:saveToXML(xmlFile, key)
    for i, c in ipairs(self.contacts) do
        local cKey = string.format("%s.contact(%d)", key, i - 1)
        setXMLString(xmlFile, cKey .. "#name",     c.name     or "")
        setXMLString(xmlFile, cKey .. "#farmName", c.farmName or "")
        setXMLString(xmlFile, cKey .. "#phone",    c.phone    or "")
        setXMLString(xmlFile, cKey .. "#notes",    c.notes    or "")
    end
end


-- ─── XML LOAD ─────────────────────────────────────────────────────────────────

function ContactManager:loadFromXML(xmlFile, key)
    self.contacts = {}
    local i = 0
    while true do
        local cKey = string.format("%s.contact(%d)", key, i)
        local name = getXMLString(xmlFile, cKey .. "#name")
        if name == nil then break end
        table.insert(self.contacts, {
            name     = name,
            farmName = getXMLString(xmlFile, cKey .. "#farmName") or "",
            phone    = getXMLString(xmlFile, cKey .. "#phone")    or "",
            notes    = getXMLString(xmlFile, cKey .. "#notes")    or "",
        })
        i = i + 1
    end
    print(string.format("[ContactManager] Loaded %d contacts", #self.contacts))
end
