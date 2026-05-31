# Screener Builder UI

## Scope

This document describes the current Flutter screener authoring UI in `lib/features/screener/`.

It is intentionally product-facing:

1. how non-programmer users build strategies
2. what parts already map to the Rust DSL
3. what parts are already modeled in UI but still waiting for the future rule engine

This document does **not** redefine the backend architecture.

- Full engine direction: `SCREENER_RULE_ENGINE.md`
- Current Rust expression layer: `SCREENER_DSL.md`

## Product Goal

The screener entry should be builder-first, not DSL-first.

Most users will not write scripts. They should be able to:

1. define internal points / anchors
2. arrange rule groups by stage
3. add condition cards by combination
4. inspect a human summary and a generated execution preview

The text DSL remains available, but only as an advanced debugging and expert authoring surface.

## Current Authoring Modes

### 1. Builder Mode

This is the default mode in `ScreenerPage`.

It is designed for users who only know how to combine conditions, not program.

Current builder sections:

1. strategy basics
2. anchor definitions
3. staged rule groups
4. condition cards inside each group
5. preview panel

### 2. Advanced DSL Mode

This is a secondary mode.

It is intended for:

1. debugging the current Rust expression layer
2. checking what the builder can compile today
3. validating or explaining the current executable source

It is **not** the main product entry for ordinary users.

## Builder Information Architecture

### Strategy Basics

The builder currently lets users set:

1. strategy name
2. universe
3. timeframe
4. top-level group combination mode
5. sort metric
6. result limit

### Anchor Definitions

Anchors are now first-class builder objects.

Each anchor has:

1. `id`
2. display name
3. kind
4. resolver type
5. optional resolver parameter
6. note

Current anchor kinds:

1. point
2. group
3. window

Current resolver types include:

1. target day
2. previous day
3. previous 2 day
4. analysis window
5. first bullish bar in window
6. last bullish bar in window
7. first bearish group in window
8. nth bearish group in window

This is important because names like `A / A0 / Bm / Rn` should be represented as internal strategy anchors, not flattened into meaningless labels.

### Staged Rule Groups

Each group is attached to a stage.

Current stage model:

1. `baseFilter`
2. `dailyFilter`
3. `minuteVeto`
4. `minuteConfirm`

This aligns the UI with the intended execution funnel:

1. basic/static filtering
2. daily filtering
3. minute-level veto
4. minute-level confirmation

Each group also has its own combination mode:

1. all conditions must match
2. any condition may match

### Condition Cards

Current builder condition types:

1. compare
2. cross
3. candlestick
4. gap
5. minute window

The first four are expression-oriented daily conditions.

The fifth is a structured minute rule card for future lazy minute execution.

## Minute Window Conditions

Minute window conditions are already present in the builder UI.

Each minute card currently includes:

1. day reference
2. start time
3. end time
4. minute state
5. window mode
6. threshold when required

Current minute states include concepts such as:

1. price above average
2. price below average
3. price positive
4. average positive
5. both positive
6. both negative

Current minute window modes include:

1. duration at least
2. duration at most
3. all match
4. any match
5. segment count at least

These cards are important even before backend execution is wired up, because they let the product model the real rule grammar instead of pretending every strategy is just a daily boolean expression.

## Current Compilation Contract

This is the key reality to keep explicit.

### What already compiles into the Rust DSL

The builder currently compiles only:

1. groups in DSL-compatible stages
2. conditions that are themselves DSL-compatible

Today that means:

1. `baseFilter`
2. `dailyFilter`
3. compare / cross / candlestick / gap conditions

### What is structure-only for now

The builder already stores, previews, and explains these elements, but does not compile them into the current Rust executable DSL:

1. anchor definitions
2. `minuteVeto` groups
3. `minuteConfirm` groups
4. minute window conditions

The UI must keep this distinction visible.

The product should never silently pretend a structured rule is executing when it is only being modeled.

## Preview and Transparency Requirements

The current UI should expose four parallel views of the strategy:

1. human-readable summary
2. compile warnings
3. structured outline
4. generated DSL preview

This is intentional.

For a complex screener system, the builder is only trustworthy if the user can always see:

1. what they configured
2. what will actually execute today
3. what is only stored for the future engine

## Current UX Rules

### Builder is primary

Ordinary users should stay in builder mode.

### DSL is secondary

DSL mode is for debugging, expert comparison, and Rust validation.

### Unsupported execution must be explicit

If a rule is not yet executable in the current Rust layer, the UI should show a compile warning instead of hiding the limitation.

### Anchor-first authoring is valid

Users should be able to define point-commands first, then reference them in later minute or staged rules.

## Current File Mapping

Current main frontend files:

1. `lib/features/screener/screener_builder.dart`
   - builder-side data model
   - builder summary
   - structured outline
   - builder-to-DSL compilation
   - compile-warning collection
2. `lib/features/screener/screener_page.dart`
   - builder UI
   - advanced DSL UI
   - anchor editing
   - stage group editing
   - condition card editing
   - preview / validate / explain-plan interactions

## Next Frontend-Backend Integration Steps

### Near-term

1. keep builder UX stable and understandable
2. keep preview / warning behavior explicit
3. continue using Rust DSL validation for the executable subset

### Next backend milestone

1. add structured ruleset payloads on the Rust side
2. add anchor resolver execution
3. add minute-state operators and lazy minute loading
4. evaluate staged rules with short-circuit rejection / acceptance

### After that

1. compile the builder into structured rulesets instead of only expression DSL
2. return actual screener results, traces, and visual debugging data

## Summary

The current screener UI is no longer a raw script editor.

It is already a usable builder-first product surface with:

1. non-programmer-friendly combination authoring
2. first-class anchor definitions
3. staged rule grouping
4. minute rule cards
5. explicit visibility into what does and does not execute today

That is the correct V1 direction.
