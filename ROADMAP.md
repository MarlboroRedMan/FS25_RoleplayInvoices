# FS25 Roleplay Invoices — Development Roadmap

---

## ✅ v0.1.0 — Released
- Phone UI (F7) with home screen, live clock and date
- Invoice system with 23 categories
- Inbox / Outbox with pay, reject, and mark as paid
- Contact manager
- Ping system
- Full multiplayer sync via network events
- Persistent save/load

---

## 🔧 v0.2.0 — Planned

### Weather App
- Tap a weather icon on the home screen to open a dedicated app
- Show current conditions (temperature, weather, season)
- 7 day forecast with icons for sun/rain/snow/fog
- Pulls data from FS25's built-in weather and season API

### Market Prices App
- Tap a market icon to see current commodity prices
- List all sellable crops and products with current price per unit
- Color code green/red based on above/below average price
- Pulls from FS25's economy/market API

### Property Management App
- List properties you own and set them as available for rent
- Set rental price and assign a tenant farm
- Track active rentals and due dates
- Auto-generate an invoice when rent is due (ties into existing invoice system)

### Used Vehicle Marketplace App
- Two tabs in one app:
  - **Player Listings** — farms post their own owned vehicles for sale, price negotiated between players, invoice auto-generated on purchase, physical handoff via Transfer Ownership mod
  - **Broker Listings** — pulls current used equipment available in the in-game shop via g_currentMission.vehicleSaleSystem (compatible with BuyUsedEquipment mod)
- Vehicle details: name, hours, condition, asking price, seller farm
- Recommended companion mod: Transfer Ownership (for physical vehicle handoff after sale)
- Optional companion mod: BuyUsedEquipment (populates the Broker Listings tab)

### Phone Wallpapers
- Let players choose from a set of preset wallpapers for the home screen
- Farm/nature themed image options bundled with the mod
- Simple setting saved per player

### In-Game Messaging
- Send text messages between farms
- View conversation threads per farm
- New message notification
- Uses existing network event system as foundation
- *(Complex — likely needs its own development sprint)*

### Discord Webhook Integration
- Server admin configures a Discord webhook URL
- In-game events automatically post to a Discord channel:
  - New invoice sent → posts to Discord with details
  - Invoice paid/rejected → updates Discord
  - Ping sent → notifies in Discord
  - Message sent (if messaging is implemented)
- Each farm maps to a Discord role so the post @'s the right farm
- One-way only: game → Discord (Discord → game not feasible without a companion app)
- *(Complex — requires HTTP request workaround in FS25 Lua)*

---

## 🔮 Future Milestone — UsedPlus Integration

UsedPlus (github.com/XelaNull/FS25_UsedPlus) is a comprehensive finance and marketplace mod with a public API. Once it reaches a stable release, integrating with it would allow our phone to become the central hub for the entire RP economy.

**Planned apps powered by UsedPlus API:**

### Credit Score App
- Display farm's current FICO-style credit score (300-850)
- Show score history and what's affecting it
- Paying invoices through our mod reports payments to UsedPlus and builds credit
- Via UsedPlusAPI.getCreditScore(farmId)

### Finance Manager App
- View all active loans, leases, and financing deals
- See monthly payments, remaining balances, and terms
- Make payments directly from the phone
- Via UsedPlus Finance Manager API

### Cash Loans App
- Apply for cash loans against collateral
- View loan terms based on current credit score
- Via UsedPlus loan system

### Vehicle DNA App
- Inspect a vehicle's hidden DNA (lemon, workhorse, legendary)
- View reliability rating, hours, damage, wear
- Via UsedPlusAPI.getVehicleDNA(vehicle)

**The big picture:** Invoice payments through our mod feed into UsedPlus credit scores. Farms that pay rent on time, settle invoices, and honor leases build good credit and unlock better financing rates. Farms that dodge payments hurt their credit. The entire server economy becomes interconnected.

---

## 💭 Future / Maybe Someday

- Sequential invoice numbering
- In-game notification when a new invoice arrives
- Controller support
- Giants ModHub submission for console availability

---

*No timeline, no pressure — just a wishlist to work from!*
