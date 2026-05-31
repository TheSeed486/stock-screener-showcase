# Stock App Target Architecture

## Goal

This repository should converge to a strict, explicit split:

1. Flutter pages are thin: layout, focus handling, gestures, and dispatching typed intents.
2. Flutter ViewModels own screen state, route state, async serials, and mutation state machines.
3. Flutter application services own feature orchestration and reusable refresh flows.
4. Flutter repositories and clients own data-source boundaries and DTO adaptation.
5. Rust host owns persistence, network access, batching, caching, and cross-feature business logic.
6. `tdx_api` stays focused on low-level TDX transport, parsing, and protocol validation.

The final shape is not "move code around". The final shape is:

- one source of truth for route state
- one source of truth for feature screen state
- one source of truth for quote/minute shared cache
- one thin FRB facade on top of Rust domain modules

## Canonical Layering

### Flutter

- `lib/app/`
  - app bootstrap
  - dependency wiring
  - shell composition
  - app-wide activation and lifecycle hooks
- `lib/application/`
  - `NavigationViewModel`
  - `MarketViewModel`
  - `StockViewModel`
  - `WatchlistViewModel`
  - `MarketDataService`
  - `StockDataService`
  - `WatchlistDataService`
  - `WatchlistGroupLoader`
  - `SharedQuoteCache`
  - startup bootstrap helpers
- `lib/features/<feature>/presentation/`
  - thin pages
  - feature-local widgets
  - painters and render helpers
- `lib/data/`
  - repositories
  - `TdxApiClient`
  - Rust/mock adapters

### Rust host

- `rust/src/api/`
  - FRB facade only
  - no business logic beyond parameter mapping and result adaptation
- `rust/src/catalog/`
  - security catalog warmup
  - segmented loading
  - metadata cache
- `rust/src/quotes/`
  - market quotes
  - security quotes
  - batching/chunking
  - shared quote orchestration
- `rust/src/charts/`
  - kline
  - realtime minute
  - historical minute
  - tick
- `rust/src/watchlist/`
  - watchlist groups
  - entries
  - reorder and persistence orchestration
- `rust/src/storage/`
  - DuckDB schema
  - migration
  - storage IO

### Protocol core

- `tdx_api/`
  - TCP binary transport
  - request builders
  - response parsers
  - connection pool
  - server probe
  - protocol-level tests

## Target Runtime Topology

The intended runtime graph is:

- Flutter pages
  - `MarketPage`
  - `StockPage`
  - `WatchlistPage`
- Flutter ViewModels
  - `MarketViewModel`
  - `StockViewModel`
  - `WatchlistViewModel`
  - `NavigationViewModel`
- Flutter application services
  - `MarketDataService`
  - `StockDataService`
  - `WatchlistDataService`
  - `WatchlistGroupLoader`
  - `SharedQuoteCache`
- Flutter data boundary
  - `TdxApiClient`
  - repositories
- FRB
- Rust services
  - `QuoteSvc`
  - `CatalogSvc`
  - `WatchlistSvc`
  - `ChartSvc`
- `tdx_api`
- `storage.rs`

## Navigation Model

`NavigationViewModel` is the only owner of app route state and history.

History must be semantic, not page-index-only.

Target route model:

- `MarketRoute`
  - segment
  - sort spec
  - page window
  - selected row
- `StockRoute`
  - selected security
  - originating segment
  - originating watch group
  - preferred absolute index
  - chart mode
  - timeframe
  - historical minute date when relevant
- `WatchlistRoute`
  - active group
  - edit mode when meaningful
  - selected row
- `ScreenerRoute`
- `BacktestingRoute`

This is required so Back/Forward can restore real user state instead of only restoring the visible page.

## Feature Ownership

### Market

`MarketPage` should only own:

- focus nodes
- scroll controllers
- viewport measurement
- pointer/keyboard dispatch
- opening stock detail

`MarketViewModel` should own:

- active segment
- sort state
- page start/page size
- selected row
- request serials
- loading/error state
- page cache keys and page snapshots

`MarketDataService` should own:

- page loading
- index page adaptation
- display name resolution
- row-kind resolution
- mini-trend loading through `SharedQuoteCache`

### Stock Detail

`StockPage` should only own:

- chart viewport UI mechanics
- scroll controllers
- crosshair and visual focus glue
- drag handle geometry
- transient render-only affordances

`StockViewModel` should own:

- list segment
- active watchlist group
- selected security key
- selected quote
- chart mode
- kline timeframe
- historical minute date
- market page window
- loaded bars/minute bars identity
- screen-level error state

`StockDataService` should own:

- list refresh orchestration
- chart loading
- selected quote loading
- tick source selection
- request shaping for market/index/watchlist modes

Important semantic rule:

- watchlist mode is a first-class list segment, not a disguised market code

### Watchlist

`WatchlistPage` should only own:

- layout
- drag handles
- text field focus wiring
- dialogs and overlays

`WatchlistViewModel` should own:

- loaded groups
- active group
- group drawer state
- table edit state
- active row
- selected rows
- inline note edit state
- reorder buffers
- quote refresh state
- mini-trend queue state
- optimistic mutation rollback state

`WatchlistDataService` should own:

- bulk quote loading
- meta lookup helpers
- display name/exchange helpers
- mini-trend loading through `SharedQuoteCache`

`WatchlistGroupLoader` should remain the boundary for:

- persisted watchlist state
- catalog join
- dedupe and fallback-to-meta behavior

## Shared State And Cache Rules

The following ownership rules are mandatory:

- `SharedQuoteCache` is the only shared owner of reusable mini-trend cache and in-flight mini-trend futures.
- feature pages do not own long-lived quote caches
- inactive pages do not keep polling
- ViewModels do not talk directly to Rust or FRB
- pages do not talk directly to repositories for business mutations
- widget tests should inject mocks and should not hit FRB by default

Pages may keep ephemeral state only:

- focus
- hover
- local drag geometry
- animation toggles
- render-only derived values

Pages must not own:

- feature data source truth
- refresh serials
- watchlist mutation workflow
- route history

## Rust Target Split

`rust/src/api/tdx.rs` is currently a transitional monolith. The target shape is:

- `rust/src/api/mod.rs`
  - exports FRB functions
- `rust/src/api/catalog.rs`
  - thin FRB wrappers into `catalog/`
- `rust/src/api/quotes.rs`
  - thin FRB wrappers into `quotes/`
- `rust/src/api/charts.rs`
  - thin FRB wrappers into `charts/`
- `rust/src/api/watchlist.rs`
  - thin FRB wrappers into `watchlist/`

The facade layer may:

- parse FRB arguments
- map Rust domain structs to FRB structs
- assemble small response DTOs

The facade layer must not:

- own caches
- own retry loops beyond thin delegation
- own storage workflows
- own business orchestration

## Storage And Protocol Rules

Keep these stable:

- `tdx_api` stays protocol-only
- `storage.rs` remains the low-level persistence boundary
- storage schema stays centered on:
  - `security_catalog`
  - `watchlist_group`
  - `watchlist_entry`

Allowed evolution:

- add migration discipline
- add more tables later for low-frequency persisted reference data
- add DuckDB-backed analytical tables later

Not allowed:

- duplicate protocol parsing in Flutter
- move quote batching logic up into Dart UI

## Source Of Truth Boundaries

Canonical truth by concern:

- navigation/history: `NavigationViewModel`
- market screen state: `MarketViewModel`
- stock screen state: `StockViewModel`
- watchlist screen state: `WatchlistViewModel`
- shared mini-trend cache: `SharedQuoteCache`
- watchlist persistence: `WatchlistRepository` -> Rust `WatchlistSvc`
- reference metadata: `ReferenceDataRepository` backed by Rust catalog warmup + catalog loads
- quote/minute/tick transport: Rust services + `tdx_api`

## Migration Plan

### Phase 1

- establish explicit VM layer
- establish shared quote cache
- move shell route/history state into `NavigationViewModel`
- bind market/stock pages to explicit ViewModels

### Phase 2

- extract `WatchlistViewModel`
- move watchlist edit/group/reorder state out of `WatchlistPage`
- finish semantic route model in `NavigationViewModel`

### Phase 3

- continue reducing `StockPage`
- move remaining page-level screen state into `StockViewModel`
- reduce page file size by moving sections into presentation widgets

### Phase 4

- split `rust/src/api/tdx.rs`
- introduce `QuoteSvc`, `CatalogSvc`, `ChartSvc`, `WatchlistSvc`
- keep FRB API surface stable where possible

### Phase 5

- add stricter CI gates
- add architecture checks through tests and conventions
- optionally introduce `Screener` and `Backtesting` using the same VM/Svc split

## Current Status

Already landed:

- `NavigationViewModel`
- `MarketViewModel`
- `StockViewModel`
- `SharedQuoteCache`
- explicit wiring from `AppShell`
- shared mini-trend cache integration in market/watchlist services

Still pending:

- `WatchlistViewModel`
- deeper stock-page state extraction
- semantic history restoration beyond the current partial route payload
- Rust facade split out of `rust/src/api/tdx.rs`

## Acceptance Criteria

The architecture can be considered implemented when:

1. `MarketPage`, `StockPage`, and `WatchlistPage` are primarily presentation code.
2. Route Back/Forward restores semantic screen state rather than only page index.
3. `WatchlistPage` mutations are driven through a dedicated `WatchlistViewModel`.
4. Shared mini-trend cache is not duplicated anywhere else.
5. `rust/src/api/tdx.rs` has been replaced by domain facade modules.
6. Flutter tests and Rust checks pass without relying on hidden side effects from giant stateful pages.
