# Tryzub Reservations — Documentation Index

**Start here.** Humans and agents use this file to find current source-of-truth documentation.

Do not implement from stale index or diagram files listed under [Stale / archive warning](#stale--archive-warning) unless explicitly instructed.

---

## Master docs

| Doc | Purpose |
|-----|---------|
| [SECOND_ENGINEER_CONTEXT.md](./SECOND_ENGINEER_CONTEXT.md) | ChatGPT / second-engineer alignment: priorities, repo state, V1 rules, verification |
| [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) | Non-negotiable architecture and workflow rules |
| [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) | V1 order: stabilization → guest person-map 3D; Slices 1/2/3A/3B/3R/3M-B/3M + Manual Intake input polish + Host polish done |
| [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md) | Active handoff: stabilization open; guest person-map through 3M-B/3M + Manual Intake input polish shipped |
| [OPEN_WORK.md](./OPEN_WORK.md) | V1 stabilization backlog with acceptance tests |
| [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md) | Roles, invariants, test checklists |

**Deploy note:** `Backend/*.zip` is not tracked in git. Build plugin zip locally from submodule `HEAD` when deploying to WordPress.

**Current root HEAD:** `75dce15` on `audit-current-state` (latest iOS `ad5d274`).

---

## Backend docs

All backend API, schema, email, and guest-token contracts live in the plugin folder — **not** in `Docs/`.

| Doc | Purpose |
|-----|---------|
| [../Backend/tryzub-reservations-api/README.md](../Backend/tryzub-reservations-api/README.md) | REST routes, tables, email types, iOS handoff, test checklists |
| [../Backend/tryzub-reservations-api/INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md) | Guest intelligence, business intelligence, system status, pipeline diagnostics |

---

## iOS docs

| Doc | Purpose |
|-----|---------|
| [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md) | App structure, session, SwiftData cache rule |
| [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md) | Staff confirm, reminders, mutations |
| [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md) | Startup, refresh, TTL, sync guards |
| [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md) | Floor plan and table assignment |
| [ACTIVITY_HISTORY.md](./ACTIVITY_HISTORY.md) | Read-only activity display |

---

## Host docs

| Doc | Purpose |
|-----|---------|
| [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md) | Host tab file map and ownership |
| [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) | selectedDate, snapshot, pressure, seated duration |
| [HOST_TAB_UI_DESIGN_SYSTEM.md](./HOST_TAB_UI_DESIGN_SYSTEM.md) | Host visual system |
| [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md) | Deterministic briefing pipeline |
| [LOCAL_MODEL_INTELLIGENCE.md](./LOCAL_MODEL_INTELLIGENCE.md) | On-device wording assistant only |

---

## Stale / archive warning

These files are **not** implementation source of truth. They may contain outdated confirm flows, endpoint inventories, or missing cross-references.

| Doc | Note |
|-----|------|
| [PROJECT_MAP.md](./PROJECT_MAP.md) | Large reference index only |
| [PROJECT_METHOD_MAP.md](./PROJECT_METHOD_MAP.md) | Method map; update-required sections |
| [ARCHITECTURE_DIAGRAMS.md](./ARCHITECTURE_DIAGRAMS.md) | Diagram reference; verify against current docs/code |
| [IOS_ADMIN_TESTING.md](./IOS_ADMIN_TESTING.md) | Superseded redirect → DIAGNOSTICS_AND_TESTING |
| [TABLE_CONFIGURATION.md](./TABLE_CONFIGURATION.md) | Superseded redirect → FLOOR_PLAN_AND_TABLES |

**Agents:** Do not use the files above for implementation unless the user explicitly asks to consult them.
