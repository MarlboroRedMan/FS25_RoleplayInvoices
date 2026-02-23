# FS25 Roleplay Invoices

A Farming Simulator 25 mod that adds a roleplay phone UI for managing invoices between farms on multiplayer servers. Built for serious RP communities that want an in-game economy with real accountability.

 🎮 **PC Only** — This mod uses Lua scripts and cannot run on console versions of FS25 (PlayStation or Xbox). PC/Mac only.
---

## Features

- 📱 **Phone UI** — Press F7 to open/close a modern smartphone interface
- 🕐 **Live clock & date** — Displays current in-game time, day, and season on the home screen
- 📄 **Invoice System** — Create and manage invoices between farms for rent, leases, vehicle sales, services, and more
- 📥 **Inbox / Outbox** — Separate views for received and sent invoices
- 💰 **Payment System** — Recipients can pay invoices directly (deducts from farm account), or senders can manually mark as paid
- ✅ **Invoice Actions** — Accept, reject, or mark invoices as paid with full status tracking
- 📋 **23 Invoice Categories** — Houses, campers, shops, storage, land leases, vehicle transactions, services, and more
- 📇 **Contact Manager** — Save farm contacts by name, farm, phone number, and notes
- 🔔 **Ping System** — Send a ping notification to another farm
- 💾 **Persistent Storage** — Invoices and contacts save with your game and persist between sessions
- 🌐 **Multiplayer Ready** — Full server/client sync via network events

---

## Invoice Categories

| Category | Category |
|---|---|
| Rent - House (Small) | Rent - House (Large) |
| Rent - Camper / RV | Rent - Shop / Business |
| Rent - Storage Unit | Lease - Land |
| Lease - Crop Share | Lease - Equipment |
| Vehicle Sale | Vehicle Lease |
| Vehicle Rental (Daily) | Vehicle Rental (Weekly) |
| Service - Labor | Service - Delivery |
| Service - Snow / Mowing / Cleanup | Service - Custom Work |
| Loan Repayment | Fine / Penalty |
| Government Tax | Government Fee |
| Utility Bill | Insurance |
| Other | |

---

## Installation

1. Download `FS25_RoleplayInvoices.zip` from the [Releases](../../releases) page
2. Place the zip file directly into your FS25 mods folder:
   - **Windows:** `Documents\My Games\FarmingSimulator2025\mods\`
3. Enable the mod in the FS25 mod manager before loading your save
4. **Do not unzip** — FS25 reads mods directly from the zip file

> ⚠️ **Important:** Do not use the "Download ZIP" button from the main GitHub page — that version wraps the files in a subfolder and will not work. Always download from the Releases page.

---

## How to Use

### Opening the Phone
Press **F7** to toggle the phone open and closed from anywhere in-game.

### Sending an Invoice
1. Open the phone and tap **Invoices**
2. Tap **+ New Invoice**
3. Select the recipient farm, category, amount, and add a description and notes
4. Tap **Send** — the recipient will see it in their Inbox

### Paying an Invoice
1. Open your **Inbox**
2. Select the invoice
3. Tap **Pay** — the amount is deducted from your farm account and the invoice is marked PAID

### Managing Contacts
1. Open the phone and tap **Contacts**
2. Tap **+ Add** to create a new contact with name, farm, phone, and notes
3. Tap any contact to view or delete it

---

## Multiplayer Notes

- The **host** handles all invoice saving and loading
- Clients receive invoice updates in real time via network sync
- Clients do not need direct access to the savegame directory
- All invoice actions (pay, reject, mark paid) broadcast to all connected players

---

## Current Version

**v0.1.0** — Initial release

---

## Known Issues / Work in Progress

- Invoice IDs are randomly generated; no sequential numbering yet
- No in-game notification when a new invoice is received (coming soon)
- Phone UI is keyboard/mouse only; controller support not planned

---

## Credits

**Mod Author:** MarlboroRedMan  
**Development Assistance:** Claude (Anthropic AI)  

---

## License

This mod is for personal and multiplayer server use. Do not redistribute modified versions without permission.
