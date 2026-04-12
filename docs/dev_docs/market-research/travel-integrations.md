# 10 Travel Integrations for VBWD Booking Plugin

**Date:** 2026-04-12
**Goal:** Extend the booking plugin to sync availability, rates, and reservations with major OTAs and travel platforms. HoReCa vendors manage everything in VBWD — OTA bookings flow in automatically.

---

## 1. Booking.com (Channel Manager API)

- **Type:** OTA — largest hotel booking platform globally
- **Coverage:** Global (28M+ listings, 230+ countries)
- **Integration:** Booking.com Connectivity API (XML/JSON), requires certified connectivity partner status
- **Plugin scope:**
  - Push room availability and rates from VBWD to Booking.com
  - Receive reservations, modifications, cancellations via webhook/pull
  - Sync guest data into VBWD user/booking model
  - Map VBWD resource types → Booking.com room types
- **Certification:** Required — Booking.com Connectivity Partner Program
- **Priority:** HIGH — #1 OTA globally, especially in EU

## 2. Agoda (YCS API)

- **Type:** OTA — dominant in Asia-Pacific
- **Coverage:** APAC focus (Thailand, Vietnam, Indonesia, Japan, Korea)
- **Integration:** Agoda YCS (Yield Control System) API, REST + XML
- **Plugin scope:**
  - ARI push (Availability, Rates, Inventory)
  - Reservation pull/webhook
  - Promotion sync (flash deals, member-only rates)
  - Multi-currency rate management
- **Priority:** HIGH — essential for ASEAN hospitality vendors

## 3. Trip.com (Ctrip)

- **Type:** OTA — largest Chinese travel platform
- **Coverage:** China + global (especially Asia)
- **Integration:** Trip.com Connectivity API (REST), requires partnership agreement
- **Plugin scope:**
  - Room/rate push
  - Reservation sync (Chinese guest data, passport info)
  - Alipay/WeChat Pay integration for Chinese travelers
  - Multi-language content sync (Simplified Chinese required)
- **Priority:** HIGH — essential for properties targeting Chinese tourists

## 4. Expedia Group (Rapid API)

- **Type:** OTA group (Expedia, Hotels.com, Vrbo, Orbitz)
- **Coverage:** Global (North America dominant, strong in EU)
- **Integration:** Expedia Rapid API (REST + GraphQL), EPC (Expedia Partner Central)
- **Plugin scope:**
  - Property content sync (photos, descriptions, amenities)
  - Rate plan management with restrictions (min stay, CTA/CTD)
  - Reservation delivery via webhook
  - Revenue management integration
- **Priority:** MEDIUM — strong in US/EU, less dominant in ASEAN

## 5. Airbnb (Professional Hosting API)

- **Type:** Short-term rental / vacation platform
- **Coverage:** Global (7M+ listings)
- **Integration:** Airbnb API (REST, OAuth2), Professional Hosting Tools
- **Plugin scope:**
  - Listing sync (property details, photos, pricing)
  - Calendar/availability sync (iCal or API)
  - Reservation and messaging sync
  - Cleaning schedule integration
  - Multi-unit management
- **Priority:** MEDIUM — important for vacation rentals and boutique hotels

## 6. Google Hotel Ads (Hotel Center API)

- **Type:** Meta-search / direct booking channel
- **Coverage:** Global (Google Search, Maps, Travel)
- **Integration:** Google Hotel Center API (REST), Hotel Ads Commission Program
- **Plugin scope:**
  - Price feed (ARI data push to Google)
  - Booking link that goes directly to VBWD checkout (bypass OTA commission)
  - Free booking links integration
  - Review aggregation
- **Priority:** HIGH — drives direct bookings, reduces OTA commission dependency

## 7. SiteMinder (Channel Manager)

- **Type:** Channel manager middleware
- **Coverage:** Global (35,000+ hotels, connects to 450+ OTAs)
- **Integration:** SiteMinder Platform API (REST)
- **Plugin scope:**
  - Single integration to distribute to all OTAs via SiteMinder
  - Centralized ARI management
  - Reservation delivery from all channels
  - Rate parity monitoring
- **Priority:** HIGH — one plugin gives access to 450+ channels
- **Alternative to:** Building individual OTA integrations

## 8. Cloudbeds (PMS Integration)

- **Type:** Property Management System
- **Coverage:** 20,000+ properties in 150+ countries
- **Integration:** Cloudbeds API (REST, OAuth2)
- **Plugin scope:**
  - Bi-directional sync: VBWD bookings ↔ Cloudbeds
  - Housekeeping task sync
  - Guest profile sync
  - Revenue/reporting data import
- **Priority:** MEDIUM — for properties already using Cloudbeds as PMS

## 9. Hostelworld (Affiliate / API)

- **Type:** OTA — hostel and budget accommodation
- **Coverage:** Global (17,000+ hostels/budget properties)
- **Integration:** Hostelworld Connectivity API (XML)
- **Plugin scope:**
  - Bed/dorm availability push
  - Shared room inventory management
  - Group booking handling
  - Reservation sync
- **Priority:** LOW — niche (hostels/budget), but relevant for backpacker market in ASEAN

## 10. TripAdvisor / Viator (Experiences API)

- **Type:** Review platform + experiences/tours booking
- **Coverage:** Global (experiences, tours, activities — not just hotels)
- **Integration:** Viator Partner API (REST), TripAdvisor Content API
- **Plugin scope:**
  - Tour/experience listing sync
  - Availability and pricing push
  - Booking delivery for tours/activities
  - Review widget integration (display TripAdvisor ratings)
  - Commission tracking
- **Priority:** MEDIUM — expands VBWD beyond rooms into experiences/tours

---

## Implementation Strategy

| Approach | Plugins | Effort | Coverage |
|----------|---------|--------|----------|
| **Channel Manager first** | SiteMinder or VBWD ↔ SiteMinder | 1 plugin | 450+ OTAs via one integration |
| **Direct OTA** | Booking.com, Agoda, Trip.com | 3 plugins | Top 3 OTAs for EU + ASEAN |
| **Meta-search** | Google Hotel Ads | 1 plugin | Direct bookings, reduce commission |
| **Full stack** | All 10 | 10 plugins | Complete distribution |

**Recommended path:** SiteMinder integration first (covers all OTAs), then Google Hotel Ads (direct bookings), then individual OTAs for deeper features.

## Plugin Architecture

Each travel integration follows the event-driven pattern:
```python
class BookingComPlugin(BasePlugin):
    def register_event_handlers(self, bus):
        bus.subscribe("booking.created", self._push_reservation)
        bus.subscribe("booking.cancelled", self._cancel_on_ota)
        bus.subscribe("resource.availability_changed", self._push_ari)
```

Admin UI: settings page for API credentials, channel mapping (VBWD resource → OTA room type), sync status dashboard.
