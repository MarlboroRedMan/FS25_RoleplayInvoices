-- scripts/RoleplayPhone.lua
-- RP Phone UI - Draw-based, no XML GUI required
-- Pattern: Mission00 appended functions

-- Capture mod directory immediately at script load time
local modDirectory = g_currentModDirectory

RoleplayPhone = {}

-- ─── State constants ──────────────────────────────────────────────────────────
RoleplayPhone.STATE = {
    CLOSED          = 0,
    HOME            = 1,
    INVOICES_LIST  = 2,
    INVOICE_DETAIL = 3,
    INVOICE_CREATE = 4,
    CONTACTS       = 5,
    PING           = 6,
    CONTACT_DETAIL = 7,
    CONTACT_CREATE = 8,
}
