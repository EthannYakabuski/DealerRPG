# Campaign systems API

`Game` is the `scripts/game_state.gd` autoload. `game_data.gd` contains item definitions, supplier tiers and named meeting locations. Product quantities are abstract fictional game units.

## Clock and world integration

`minute` is absolute campaign minutes. Day one at 10:00 is `600`; day two at 09:00 is `1980`. `day_number()`, `time_text()`, `format_minute(value)`, `current_phase()` and `next_class_minute()` provide display helpers. The automatic clock runs at **3 game minutes per real second** after the tutorial. Set `paused = true` while an overlay is open; `advance_time()` still works for deliberate class/sleep/party actions.

Set `player_location_id` from world proximity before calling contextual actions. Named locations: `campus_quad`, `library`, `cafe`, `home`, `market`, `car_park`. World interactions should separately require proximity to the actual NPC for tutorial/client handoffs. Movement, line of sight, pursuit and catch radius are world responsibilities.

Signals:

- `changed()` — refresh displayed state; emitted every clock update, so avoid rebuilding focused input controls on every event.
- `notification(text: String)` — short user-facing feedback, including why a transaction failed.
- `ended(won: bool, reason: String)` — terminal campaign result.
- `crime_committed(severity: float)` — world witnesses decide whether to pursue. Minor handoff ~14, supplier setup 65, gunfire 65. Ordinary hidden crimes add small passive attention; this signal is **not** an automatic capture.

Call `set_heat(value)` for police attention, `take_damage(amount)` for injuries, and `caught_by_police()` for terminal arrest. `finish_game(won, reason)` is also available. An ended campaign rejects new transactions and persists its result; restarting resets everything.

## UI state

Public fields: `cash`, `tuition_remaining` (starts at $3,500), `health`, `hunger`, `energy`, `heat` (0–100), `reputation`, `minute`, `tutorial_step`, `inventory`, `contacts`, `inbox`, `meetings`, `status` (`playing`, `won`, `lost`), `ending_reason`, `missed_classes`, `vehicle_owned`, `flower_quality`, `dime_quality`, `total_sales`, `total_earned`, `classes_attended`, `parties_hosted`, `last_error`.

Inventory keys: `flower`, `dime_bag`, `sandwich`, `energy_drink`, `skateboard`, `pistol`, `ammo`. Counts are nonnegative integers. `inventory_weight()` and `capacity_remaining()` expose the 14-unit backpack. Initial inventory includes a skateboard, sandwich, drink, and one flower bundle.

`current_objective()` is the tutorial/campaign guidance text. Tutorial sequence is `split_flower()` → contextual `tutorial_sell()` → phone `add_tutorial_contact()`. It is safe and clock-frozen until all three steps complete.

Contacts contain `id`, `name`, `relationship` (0–100), `sales`, `last_sale_minute`. Inbox dictionaries contain `id`, `contact_id`, `contact_name`, `quantity`, `text`, `status` (`new`, `accepted`, `expired`), `created_minute`, `expires_minute`, `suggested_price`. Relationships improve with fair pricing, quality and punctuality; regular referrals unlock more contacts as reputation grows.

## Meetings and suppliers

`schedule_meeting(message_id, location_id, delay_minutes = 90, price = 22) -> bool` accepts one request. Delay is 30–240 minutes and price is $12–$40 per bag. `available_locations()` returns location dictionaries with `id`, `name`, `district`. The system rejects class conflicts, duplicate requests and overlapping meetings.

`active_meetings()` returns scheduled meetings sorted by due time. Every meeting includes:

| Key | Meaning |
| --- | --- |
| `id`, `type` | Unique ID; type is `client` or `supplier` |
| `contact_id`, `contact_name` | Person to spawn/display |
| `location_id`, `due_minute` | Physical place and absolute arrival time |
| `quantity`, `price`, `cost` | Bags and per-bag price for clients; bundles, per-bundle price and total cost for suppliers |
| `tier`, `quality`, `risk` | Supplier metadata; clients have tier -1, quality 0 and no risk field |
| `status`, `created_minute` | `scheduled`, `completed`, `missed` or `cancelled` |

`complete_meeting(meeting_id) -> bool` checks status, location, stock/cash/capacity, and arrival window. NPCs can trade **25 minutes before** due time, and wait **25–45 minutes after** based on relationship. `cancel_meeting(meeting_id)` applies a smaller relationship penalty than a no-show. Failed stock/location/time checks do not consume anything. Repeated handoffs cannot duplicate rewards.

`supplier_catalog()` returns three suppliers. `supplier_order(tier, bundles)` creates a meeting at `car_park` at least 60 minutes away. Cash is charged and bundles arrive only on handoff. Reputation gates are 0 / 8 / 22, prices are $46 / $40 / $33 per bundle, qualities are 0.72 / 0.87 / 0.98. Each bundle splits into six bags; quality averages when stocks mix. Supplier risk is exposed in the meeting; a rolled setup emits severity 65 with a warning, giving the world a chance to pursue rather than instantly ending the run.

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
- `host_party()` — home, reputation 5, at least two contacts, 17:00–22:59, 6+ bags, $25 setup, once per day. Sells up to 24 bags based on circle size, advances 90 minutes, increases relationships/reputation and police attention.
- `work_shift()` — classroom/campus/library, 11:00–19:00, heat ≤30; advances 120 minutes and earns $35. Recovery route if the player spent all seed money.

## Persistence and tests

`save_game()` writes version-2 JSON through a temporary file and rename. `load_game(show_message = true)` validates before applying; `restart_game(delete_save = true)` restores starting state. Save path is `user://deerfield_save_v2.json`. Browser `user://` uses the engine's persistent storage. Autosave runs every 20 active seconds; tutorial completion, sleep and endings also save. Set a different `save_path` before adding a standalone state instance to a scene tree when testing.

`world_state` is an optional, backward-compatible dictionary. The world captures `position: [x,y,z]`, `interior`, `vehicle_owned_pos`, `driving`, `stolen_vehicle`, `pursuit`, `skateboarding` and `car_rotation`. Positions must be finite and within the exterior or correct room bounds; invalid data falls back to the campus spawn. Indoor saves cannot restore driving/skateboarding. Capture this state before saving so physical location and police state stay consistent with the campaign clock.

Run the integration suite with Godot 4.5.1:

```powershell
& $Godot --headless --path . --log-file "$((Get-Location).Path.Replace('\','/'))/.godot/gameplay-tests.log" --script res://tests/test_game_state.gd
```

The suite checks tutorial ordering, scheduling, relationship penalties, inventory/quality, suppliers, hunger, classes, parties, cars, corrupted saves, irreversible loss, restart and a complete earned-money campaign. It uses a separate `.godot/gameplay-test-save.json`, never the player's save. For sandboxed desktop runs use an absolute forward-slash log path under the repository; Godot's default AppData log location may not be writable.

`tests/test_population.gd` instantiates the actual city, actors, collisions and navigation. It checks tutorial spawn spacing, animated models, day/night goals, building avoidance, first-sale witnesses, line-of-sight occlusion, patrol jurisdiction, persisted arrest, escape, reset, all five interiors, stamina, firearm visibility/ammunition, melee reactions, car theft/safe exits/ownership, timed NPC arrival and physical save positions. `CityPopulation.reset_population()` resets transient city simulation for a new or restored campaign; `StudentPlayer.reset_travel()` clears stale movement and vehicle state.
