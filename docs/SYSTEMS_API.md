# Campaign systems API

`Game` is the `scripts/game_state.gd` autoload. `game_data.gd` contains item definitions, supplier tiers and named meeting locations. Product quantities are abstract fictional game units.

## Clock and world integration

`minute` is absolute campaign minutes. Day one at 10:00 is `600`; day two at 09:00 is `1980`. `day_number()`, `time_text()`, `format_minute(value)`, `current_phase()` and `next_class_minute()` provide display helpers. The automatic clock runs at **3 game minutes per real second** after the tutorial. Set `paused = true` while an overlay is open; `advance_time()` still works for deliberate class/sleep actions. Live parties follow the ordinary clock.

Set `player_location_id` from world proximity before calling contextual actions. Named locations: `campus_quad`, `library`, `cafe`, `home`, `market`, `car_park`. World interactions should separately require proximity to the actual NPC for tutorial/client handoffs. Movement, line of sight, pursuit and catch radius are world responsibilities.

Signals:

- `changed()` — refresh displayed state; emitted every clock update, so avoid rebuilding focused input controls on every event.
- `notification(text: String)` — short user-facing feedback, including why a transaction failed.
- `ended(won: bool, reason: String)` — terminal campaign result.
- `crime_committed(severity: float)` — world witnesses decide whether to pursue. Minor handoff ~14, supplier setup 65, gunfire 65. Ordinary hidden crimes add small passive attention; this signal is **not** an automatic capture.
- `feedback_event(kind: String, value: float)` — success-only sound and visual cues. Kinds: `pack`, `purchase`, `sale`, `text`, `caught`, `consume`, `tuition`, `class`, `party`. Transaction values are signed cash changes: party supplies emit `purchase, -25`; each chosen guest sale emits `party, 24`. Other values are zero. Loading a save and failed transactions never replay these cues.
- `civilian_reaction(npc_id: String, reaction: String)` — a pedestrian's `report` reaction asks the world to start their physical walk toward an officer. This signal does not increase heat or cause an arrest.
- `police_tip(location_id: String, severity: float)` — a supplier setup or informant handoff provides a meeting location for an actual patrol response. The state warns the player and leaves pursuit, arrival and capture to the world.
- `street_reaction(npc_id: String, kind: String)`, `meeting_reaction(meeting_id: int, kind: String)`, `party_reaction(contact_id: String, kind: String)` — semantic cosmetic reactions such as `wave`, `question`, `happy`, `sad`, or `angry`; they never trigger police behavior themselves.
- `meeting_missed(meeting_id: int, contact_id: String)` — emitted once when a scheduled meeting expires, so the world can show an upset contact leaving.
- `police_pressure_changed()` — local reinforcement changes; population can refresh its bounded temporary patrol roster.

Call `set_heat(value)` for police attention, `take_damage(amount)` for injuries, and `caught_by_police()` for terminal arrest. `finish_game(won, reason)` is also available. An ended campaign rejects new transactions and persists its result; restarting resets everything.

## UI state

Public fields: `cash`, `tuition_remaining` (starts at $3,500), `health`, `hunger`, `energy`, `heat` (0–100), `reputation`, `minute`, `tutorial_step`, `inventory`, `contacts`, `inbox`, `meetings`, `status` (`playing`, `won`, `lost`), `ending_reason`, `missed_classes`, `vehicle_owned`, `flower_quality`, `dime_quality`, `total_sales`, `total_earned`, `classes_attended`, `parties_hosted`, `last_error`.

Inventory keys: `flower`, `dime_bag`, `sandwich`, `energy_drink`, `skateboard`, `pistol`, `ammo`. Counts are nonnegative integers. `inventory_weight()` and `capacity_remaining()` expose the 14-unit backpack. Initial inventory includes a skateboard, sandwich, drink, and one flower bundle.

`current_objective()` is the tutorial/campaign guidance text. Tutorial sequence is `split_flower()` → contextual `tutorial_sell()` → phone `add_tutorial_contact()`. It is safe and clock-frozen until all three steps complete.

Contacts contain `id`, `name`, `relationship` (0–100), `sales`, `last_sale_minute`, `last_order_quantity`, `next_request_minute`. Inbox dictionaries contain `id`, `contact_id`, `contact_name`, `quantity`, `text`, `status` (`new`, `accepted`, `expired`), `created_minute`, `expires_minute`, `suggested_price`. Relationships improve with fair pricing, quality and punctuality; regular referrals unlock more contacts as reputation grows.

Milo's first follow-up arrives 90 game minutes after the tutorial purchase. Subsequent purchases impose a persisted per-contact cooldown of 6–8 hours plus 30 minutes for each extra bag. Customers only text between 07:00 and 23:00 and cannot have duplicate pending requests or scheduled meetings. Cancellation/no-shows allow at least four hours before retrying. Party guests also receive a purchase cooldown. Existing version-2 saves derive the new timing from sale history while retaining accepted appointments.

## Meetings and suppliers

`schedule_meeting(message_id, location_id, delay_minutes = 90, price = 22) -> bool` accepts one request. Delay is 30–480 minutes and price is $12–$40 per bag, capped at `message.max_price` for discounted offers. `available_locations()` returns location dictionaries with `id`, `name`, `district`. The system rejects class conflicts across midnight, duplicate requests and overlapping meetings.

`active_meetings()` returns scheduled meetings sorted by due time. Every meeting includes:

| Key | Meaning |
| --- | --- |
| `id`, `type` | Unique ID; type is `client` or `supplier` |
| `contact_id`, `contact_name` | Person to spawn/display |
| `location_id`, `due_minute` | Physical place and absolute arrival time |
| `quantity`, `price`, `cost` | Bags and per-bag price for clients; bundles, per-bundle price and total cost for suppliers |
| `tier`, `quality`, `risk` | Supplier metadata; clients have tier -1, quality 0 and no risk field |
| `status`, `created_minute` | `scheduled`, `completed`, `missed`, `postponed` or `cancelled` |

`complete_meeting(meeting_id) -> bool` checks status, location, stock/cash/capacity, and arrival window. NPCs can trade **12 minutes before** due time (`MEETING_ARRIVAL_MINUTES`), and wait **25–45 minutes after** based on relationship (`MEETING_WINDOW` plus relationship grace). `cancel_meeting(meeting_id)` applies a smaller relationship penalty than a no-show. Failed stock/location/time checks do not consume anything. Repeated handoffs cannot duplicate rewards.

`supplier_catalog()` returns three suppliers. `next_supplier_minute(earliest = -1)` previews the next free night slot at least 60 minutes away, between 22:00 inclusive and 02:00 exclusive. `supplier_order(tier, bundles)` creates that meeting at `car_park`, preserving 35-minute gaps and the absolute day across midnight. Cash is charged and bundles arrive only on a handoff during the night window. Reputation gates are 0 / 8 / 22, prices are $46 / $40 / $33 per bundle, qualities are 0.72 / 0.87 / 0.98. Each bundle splits into six bags; quality averages when stocks mix. A supplier setup emits a warning and a severity-65 physical police tip rather than ending the run.

`postpone_meeting(id, delay_minutes = 120)` is for a conversation at the real meeting: main must first verify NPC proximity. State also checks the meeting location and arrival window. It removes the accepted obligation without a relationship penalty and queues a callback after at least two hours. A client callback stays within 07:00–23:00; a supplier callback moves to an appropriate night window. `request_tomorrow(message_id)` defers an incoming client opportunity until at least 09:00 the next day. Both persist, prevent duplicates, and produce a new opportunity requiring explicit scheduling, never an automatic appointment. Supplier callback messages retain normal inbox fields plus `type: supplier_callback`, `tier` and `bundles`; `accept_supplier_callback(message_id)` atomically schedules a fresh night pickup and consumes the callback.

## Conversations and introductions

`street_conversation(npc_id, npc_name)` creates or reads a stable pedestrian record and returns only public fields: `npc_id`, `name`, `text`, `can_offer`, `can_add_contact`, `sold`, `price`, `contact_id`. Root/world owns the physical conversation range. `offer_street_sale(npc_id)` can sell one bag for $22, receive a refusal, or emit a reporting reaction. Outcomes persist and cannot be rerolled by reopening the dialog. Successful sales apply a purchase cooldown; refusals impose four hours before another offer. `add_street_contact(npc_id)` works once after a successful sale and carries that sale's cooldown into the phone contact.

`street_smalltalk(npc_id, goal = "") -> String` cycles through ordinary conversations and retains the latest reply. Dialogue voice is drawn independently from the hidden purchase outcome; a study-related line or an NPC's daily activity never reveals whether they will buy. Purchase, refusal and report replies also vary. Older records derive a stable voice from their ID.

`pending_civilian_reports()` lists pedestrians still looking for an officer. Restore their physical journeys when continuing a game. When one reaches a living officer, the world calls `civilian_report_arrived(npc_id)` once and handles the ensuing pursuit itself. State only records completion, so there is no duplicate crime alert or immediate arrest.

Referrals first appear in `pending_introductions()`, a public array containing `id`, `name`, `text`, `referrer_id`, `referrer_name`, `who_answer`, `connection_answer` and `status`. `ask_introduction(id, "referrer")` asks who gave out the number; `ask_introduction(id, "connection")` asks how they know that person. Compare the saved answers to `contact_profile(contact_id)`, which provides known `course`, `hangout` and `bio`. `resolve_introduction(id, "accept" | "decline" | "block")` makes the player's decision explicit. Acceptance adds a contact and an incoming opportunity; it does not schedule anything. Some informants have inconsistent cover and some have accurate cover, so questions provide clues rather than an infallible identity check. Hidden identity fields are omitted from public introduction/profile views. A hidden informant only sends a police tip after an actual chosen handoff.

`text_contact(contact_id)` proactively asks an existing contact about interest, limited to one outreach every four hours and no duplicate pending business. A customer needs at least three hours since purchase plus thirty minutes per extra bag before considering another offer. Eligible customers have 20–30% interest depending on relationship; some ask for one bag at a discounted $20 maximum. A declined offer leaves the automatic 6–8-hour request cooldown untouched. `contact.last_reply` / `last_text_minute` persist for conversation display; `contact_profile` includes them too.

## Other actions

All transaction methods return a success bool. Failed actions emit a notification and set `last_error`.

- `buy_item(item, quantity = 1)` — market/cafe for food and board; `supplier` service yard (or parking lot) plus reputation 8 for handgun/ammo.
- `consume_item(item)` — sandwiches restore 48 hunger and 8 health, drinks restore 65 energy and 8 hunger.
- `discard_item(item, quantity = 1)` — free backpack space.
- `use_ammo()` — verify firearm/ammo, consume one round and report gunfire. World code handles aiming and hits.
- `use_energy(amount)` — subtracts energy only if sufficient, rejects invalid values.
- `purchase_vehicle()` — `auto_dealer` (or parking lot), reputation 22, $900; sets `vehicle_owned`.
- `pay_tuition(amount = -1)` — phone payment; default pays as much as affordable. Paying the full $3,500 wins.
- `attend_class()` — `classroom` lecture hall, campus quad or library, 08:40–09:59; advances to 11:00. Day-one class is already complete. Three missed days cause eviction.
- `sleep_at_home()` — home and heat ≤35; advances to next 08:10, restores energy and some health if fed. Obligations still advance.
- `host_party()` — home, reputation 5, at least two contacts, 17:00–02:00, $25 supplies, once per night. Opens a live party without changing stock or advancing time; see the party APIs below.
- `work_shift()` — classroom/campus/library, 11:00–19:00, heat ≤30; advances 120 minutes and earns $35. Recovery route if the player spent all seed money.

## Live parties

`party_summary()` returns `{active, id, start_minute, end_minute, ends_minute, guest_count, guests, can_invite}`; `ends_minute` aliases `end_minute`. Parties last up to 180 campaign minutes, always close by 02:00, and cannot start with less than 20 minutes remaining. Midnight belongs to the previous party night. Guests remain in the summary after closing so their world actors can depart.

`invite_party_contact(contact_id)` invites up to eight known, unblocked contacts, with staggered `arrival_minute` values. Each guest has `contact_id`, `name`, `status` (`invited`, `inside`, `left`), `arrived`, `chatted` and `purchased`. An accepted meeting before party closing plus a 15-minute departure buffer prevents an invitation; answering an older text cannot create that conflict in the opposite order either. Later appointments remain available. Invited guests do not generate new sales errands or accept proactive outreach while the party is running. Invitations are social visits and do not sell inventory.

Main's party actor helper owns physical movement, arrival and conversation distance. Once a guest has reached home after their arrival time, call `mark_party_guest_arrived(contact_id)` (alias `party_guest_arrived`) for the once-only +2 relationship award. `party_guest_view(contact_id)` exposes name, conversational text, `can_chat`, `can_offer`, `price` ($24) and `sold`. `chat_party_guest` (alias `party_chat`) gives +3 relationship once. `sell_party_guest` (alias `party_sell`) explicitly sells one bag once to that guest, awards revenue/reputation and applies the normal purchase cooldown. State requires the player at home; main also checks actual actor proximity. Guests never buy automatically when time advances or the party ends.

## Local police pressure

Completed appointments update `last_meeting_location` and `consecutive_location_meetings`. Two consecutive meetings at one place create watch level 1; three create heavy watch level 2. Changing locations resets the consecutive count but does not erase existing watch. Failed, cancelled, missed, duplicate and postponed handoffs do not increase it.

Population calls `register_pursuit(location_id)` exactly once when a new pursuit begins. Each incident increases that area's reinforcement and the persisted global `pursuit_incidents` count. `escape_duration_seconds()` returns 10, 10, 15, 20, 25, 30 seconds for incidents 1–6, then 40, 50, 60 and another 10 seconds per incident. Quiet areas lose their extra patrols after 1,440 campaign minutes without a new bust; permanent escape escalation remains. Ordinary meetings do not extend that quiet-day deadline.

`police_pressure_locations()` returns active `{location_id, expires_minute, strength, watch_level, incident_count}` records sorted by strength. Strength is watch level plus incident count, capped at `MAX_EXTRA_OFFICERS_PER_AREA` (4), and population limits the combined temporary roster to `MAX_VISIBLE_EXTRA_OFFICERS` (8). Incident counts and escape requirements keep increasing beyond the visible roster cap. Temporary patrols are rebuilt from this saved state; only the base roster is stored in pursuit actor snapshots.

## Persistence and tests

`save_game()` writes version-2 JSON through a temporary file and rename. `load_game(show_message = true)` validates before applying; `restart_game(delete_save = true)` restores starting state. Save path is `user://deerfield_save_v2.json`. Browser `user://` uses the engine's persistent storage. Autosave runs every 20 active seconds; tutorial completion, sleep and endings also save. Set a different `save_path` before adding a standalone state instance to a scene tree when testing.

`world_state` is an optional, backward-compatible dictionary. The world captures `position: [x,y,z]`, `interior`, `vehicle_owned_pos`, `driving`, `stolen_vehicle`, `pursuit`, `skateboarding` and `car_rotation`. Positions must be finite and within the exterior or correct room bounds; invalid data falls back to the campus spawn. Indoor saves cannot restore driving/skateboarding. Capture this state before saving so physical location and police state stay consistent with the campaign clock.

Optional `world_state.meeting_walks` validates up to ten client/supplier actor records. The world captures approaching and waiting actors for active appointments; completed departures are cosmetic and are not restored. Each record contains numeric `id`, exterior `position` and `target` arrays, `state`, and absolute `start_minute` / `due` times. Invalid entries and duplicate IDs are skipped independently; oversized or malformed containers are ignored. Missing data remains compatible with earlier saves.

Optional `world_state.informant_runs` retains up to 57 reporting pedestrians as `{id, position, report_position, campus}`. IDs must be `citizen_00` through `citizen_56`; both positions must be finite and inside the exterior. Malformed or duplicate entries are skipped. Optional `world_state.party_walks` retains up to eight `{contact_id, state, position, slot}` records: `inside` requires the home room, `approaching` requires exterior bounds, and `leaving` permits either. Pursuit snapshots accept both legacy seven-officer and current ten-officer base rosters.

Optional top-level `introductions`, `callbacks`, `street_npcs`, `active_party`, `police_pressure`, `pursuit_incidents`, `last_meeting_location` and `consecutive_location_meetings` are validated before a save is applied; older version-2 saves without them remain compatible. Live party guest awards and purchases persist to prevent duplicate transactions after reload. Already-expired parties and local patrol deadlines resolve quietly on load without replaying feedback.

Existing daytime supplier appointments that are still live migrate to the next legal night slot without changing cash or stock. Only that supplier's obsolete saved walking record is removed; unrelated actors remain intact. Already-overdue appointments retain ordinary expiry behavior, and the load notification points the player to the updated agenda.

Run the integration suite with Godot 4.5.1:

```powershell
& $Godot --headless --path . --log-file "$((Get-Location).Path.Replace('\','/'))/.godot/gameplay-tests.log" --script res://tests/test_game_state.gd
```

The suite checks tutorial ordering, scheduling, relationship penalties, inventory/quality, suppliers, hunger, classes, parties, cars, corrupted saves, irreversible loss, restart and a complete earned-money campaign. It uses a separate `.godot/gameplay-test-save.json`, never the player's save. For sandboxed desktop runs use an absolute forward-slash log path under the repository; Godot's default AppData log location may not be writable.

`tests/test_social_state.gd` covers pedestrian sale/refusal/report branches, persistent reports, referral vetting and informant handoffs, proactive discounted opportunities, night-only suppliers, client/supplier/tomorrow callbacks, eight-hour scheduling, duplicate prevention and optional-save compatibility. Its isolated save is `.godot/social-test-save.json`.

`tests/test_party_pressure.gd` covers live-party windows, invitations, arrival/chat/manual sale exclusivity, midnight limits, persistent guest outcomes, consecutive completed-meeting pressure, the escalation ladder, local expiry, missed-contact reactions, ambiguous dialogue, expanded patrol/report snapshots, malformed saves and optional-field migration.

`tests/test_population.gd` instantiates the actual city, actors, collisions and navigation. It checks tutorial spawn spacing, animated models, day/night goals, building avoidance, first-sale witnesses, line-of-sight occlusion, patrol jurisdiction, persisted arrest, escape, reset, all five interiors, stamina, firearm visibility/ammunition, melee reactions, car theft/safe exits/ownership, timed NPC arrival and physical save positions. `CityPopulation.reset_population()` resets transient city simulation for a new or restored campaign; `StudentPlayer.reset_travel()` clears stale movement and vehicle state.
