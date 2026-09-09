---
stepsCompleted: ['step-01', 'step-02', 'step-03', 'step-04']
inputDocuments:
  - '_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md'
  - '_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/addendum.md'
  - '_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md'
---

# GlycemicGPT iOS + watchOS - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for GlycemicGPT iOS + watchOS, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

**FR-1**: Reaching pairing from Settings
**FR-2**: Driver-determined pairing shape and Driver-supplied copy
**FR-3**: Bluetooth pre-explanation, the system prompt, and denial recovery
**FR-4**: Scanning and the discovered-Pump list
**FR-5**: Pairing-code entry
**FR-6**: Advertise-and-wait pairing
**FR-7**: One-phone-at-a-time warning
**FR-8**: The connection state model
**FR-9**: Cancelling a connection attempt
**FR-10**: Distinct pairing-failure categories
**FR-11**: The broken-pairing wall
**FR-12**: Restraint before declaring a pairing broken
**FR-13**: Indefinite reconnection
**FR-14**: Reconnection while backgrounded, locked, evicted and after reboot
**FR-15**: Force-quit disclosure and detection
**FR-16**: Foreground-only discoverability for advertise-and-wait Drivers
**FR-17**: One canonical unpair, always confirmed
**FR-18**: Per-Driver credential isolation
**FR-19**: Pump identity is a name and a model, never a raw identifier
**FR-20**: Connection status outside the pairing flow
**FR-21**: Driver Catalog as the sole registration path
**FR-22**: Viewing the Drivers this build contains
**FR-23**: Activating a Driver and swapping a single-instance Capability
**FR-24**: Multi-instance Capabilities
**FR-25**: Deactivating a Driver
**FR-26**: Selection surviving relaunch, restart, upgrade and background launch
**FR-27**: Compile-time kill switch making a Driver wholly absent
**FR-28**: A failing Driver is skipped without affecting the others
**FR-29**: Per-Driver namespaced settings that survive deactivation
**FR-30**: The closed Capability set and its cardinality rules
**FR-31**: Read-only by construction — no therapeutic write exists
**FR-32**: Safety Limits read fresh at every validation pass, narrowing only
**FR-33**: No active Driver is a distinguishable error, never an empty result
**FR-34**: Best-effort bounded event delivery
**FR-35**: The Simulated Driver as a shipped first-class Driver
**FR-36**: The Trace-Replay Driver as a shipped first-class Driver
**FR-37**: Driver-contributed dashboard cards and detail screens
**FR-38**: The Backend-mediated Nightscout data source as a Driver-shaped Capability
**FR-39**: Home dashboard composition and fixed card order
**FR-40**: Pull-to-refresh forced read
**FR-41**: Foreground re-read on activation
**FR-42**: Refresh failures preserve cached values
**FR-43**: Pump-link indicator
**FR-44**: Sync and Backend reachability indicators
**FR-45**: Driver brand marks
**FR-46**: Glucose hero
**FR-47**: Severity colour from stored mg/dL alone
**FR-48**: Too Stale de-emphasis of the hero
**FR-49**: Freshness Tier classification
**FR-50**: Wall-clock freshness re-evaluation
**FR-51**: Staleness badge
**FR-52**: Trend chart base rendering
**FR-53**: Chart draw order, overlays and legend
**FR-54**: Chart time-axis labels and tick counts
**FR-55**: Chart detail interaction
**FR-56**: Chart detail landscape presentation
**FR-57**: Five independent period selections
**FR-58**: Time in Range
**FR-59**: CGM statistics
**FR-60**: Display-boundary unit rendering and numeric formatting
**FR-61**: Single injectable time source
**FR-62**: Theme selection
**FR-63**: Navigation, capability-driven tab bar and session banner
**FR-64**: Dashboard legibility under Dynamic Type
**FR-65**: Alert type vocabulary and delivery tiering
**FR-66**: Interruption level and the audibility honesty statement
**FR-67**: Per-severity alert sound selection
**FR-68**: Foreground presentation
**FR-69**: Alert content, title format, and caregiver rendering
**FR-70**: Notification slot identity and duplicate suppression
**FR-71**: The Alert Floor — on-device alarming with no Backend
**FR-72**: Freshness and clock-trust gate
**FR-73**: Never alarm from unconfirmed Alert Thresholds
**FR-74**: Re-alarm cooldown and episode semantics
**FR-75**: Episode guard against Backend alert history
**FR-76**: Bounded finite re-alarm ladder
**FR-77**: Acknowledge from the notification
**FR-78**: Offline acknowledgement durability and reconciliation
**FR-79**: On-device Alert Threshold editor (Backend-optional mode)
**FR-80**: Backend-supplied Alert Thresholds are read-only and adopted within the hour
**FR-81**: Invalid Backend threshold responses are discarded whole
**FR-82**: Alert Threshold provenance across sign-out
**FR-83**: The Coverage Claim
**FR-84**: Coverage Claim expiry and decay
**FR-85**: Proactive coverage-lapse notification, force-quit and reboot warnings
**FR-86**: Automatic resume after background termination
**FR-87**: Backend alert history
**FR-88**: Developer fault-injection surface
**FR-89**: Insulin Summary
**FR-90**: Delivered-insulin honesty
**FR-91**: Recent Boluses and Bolus History
**FR-92**: Glucose-Reading-at-event and IOB-at-event cross-referencing
**FR-93**: Meal availability gate, Home glance and entry point
**FR-94**: Meal photo capture and preparation
**FR-95**: Upload lifecycle and the non-sticking estimate indicator
**FR-96**: The never-dose qualifier on every carb-estimate surface
**FR-97**: Carb range and confidence presentation
**FR-98**: Multi-read disagreement disclosure
**FR-99**: Food identity confirmation
**FR-100**: Carb range correction — reject, never clamp
**FR-101**: Estimate provenance — "How was this estimated?"
**FR-102**: Backend-authored nutrition, rendered verbatim
**FR-103**: Meal history and record deletion
**FR-104**: Common foods — save, edit, read-only re-log, delete
**FR-105**: AI Chat tab availability
**FR-106**: One-time AI provider probe and its three landing states
**FR-107**: Sending a message and the 2000-character limit
**FR-108**: Ephemeral in-memory transcript
**FR-109**: Curated failure copy for every failure class
**FR-110**: Honest disclosure of an interrupted request
**FR-111**: Starter suggestions and the standing safety disclaimers
**FR-112**: Assistant markdown sanitization
**FR-113**: Spoken responses, voice choice and audio ducking
**FR-114**: AI Chat on the Watch
**FR-115**: Single-bundle Watch app delivery and read-only wrist posture
**FR-116**: One shared safety module behind every wrist surface, demonstrable in the Simulator
**FR-117**: The wrist complication set, and the absence of custom watch faces
**FR-118**: Guided complication setup and active-face detection
**FR-119**: Glanceable surfaces on the iPhone Lock Screen, Dynamic Island and Watch Smart Stack
**FR-120**: Glucose Reading on the wrist with the Freshness Tier treatment
**FR-121**: IOB on the wrist with the Freshness Tier treatment
**FR-122**: Wrist decay on the Watch's own clock, within the OS refresh budget
**FR-123**: Backward clock-jump guard
**FR-124**: Display-only mmol/L conversion and glucose banding on the wrist
**FR-125**: Alert Threshold sanitization on the wrist
**FR-126**: The wrist Coverage Claim — rendered and decayed, never derived
**FR-127**: Not-Watching Reason copy on the wrist
**FR-128**: Watch-scheduled wrist alert delivery
**FR-129**: Locally scheduled 30-minute wrist re-alarm ladder
**FR-130**: Live-alert refresh, and never retracting on data we cannot vouch for
**FR-131**: Wrist alert dismissal
**FR-132**: Six-hour basal, Bolus and IOB history on the Watch
**FR-133**: Full-screen Watch glucose graph and the shared Y-axis rule
**FR-134**: iPhone Settings > Watch — preference sync and the true wrist-link state
**FR-135**: Encrypted local store for all monitoring data
**FR-136**: Database key generated once, device-only, never inherited
**FR-137**: Write-time deduplication and cross-source collision resolution
**FR-138**: Canonical mg/dL storage and rejection of invariant-violating rows
**FR-139**: Retention window bounding every table
**FR-140**: Durable local record before any upload, surviving suspension
**FR-141**: Upload failure classification and the retry budget
**FR-142**: Bounded outbound queue and its user-visible state
**FR-143**: Backend-optional transitions
**FR-144**: Opportunity-driven background work
**FR-145**: Capture-time freshness and detected collection gaps
**FR-146**: Resumable, cancellable initial history download
**FR-147**: Staying signed in with proactive token refresh
**FR-148**: Exactly one serialized refresh per 401, and sign-out always wins
**FR-149**: Offline session expiry without data loss
**FR-150**: Cleartext transport policy
**FR-151**: Local network reachability — permission, denial copy, and the insecure-HTTP opt-in
**FR-152**: Three connectivity states
**FR-153**: Backend-mediated Nightscout source
**FR-154**: Nightscout sync execution — cursor, paging and clean abort
**FR-155**: Tolerant reader with loud failure on missing consumed fields
**FR-156**: Device registration as an iOS device
**FR-157**: Backend-alert transport posture — SSE while alive, APNs reserved
**FR-158**: Scrubbed diagnostic log export
**FR-159**: First-run onboarding flow and stage gating
**FR-160**: Unskippable safety acknowledgement
**FR-161**: Optional Backend setup, connection test and sign-in
**FR-162**: Local-network-blocked state and Settings deep link
**FR-163**: Insecure LAN HTTP opt-in and the persistent insecure-transport banner
**FR-164**: Finishing onboarding without a Backend
**FR-165**: Notification and Bluetooth authorization on both completion paths
**FR-166**: Settings composition, ordering and mode-dependent visibility
**FR-167**: Account section and sign-out
**FR-168**: Alert Thresholds are read-only whenever a Backend is configured
**FR-169**: Alert Thresholds are editable in Backend-optional mode with dependent validation
**FR-170**: Per-severity alert sound picker
**FR-171**: Notification status card reporting every suppressing condition
**FR-172**: Watch section — pairing state, what the Watch surfaces show, and telemetry
**FR-173**: About — versions, build mismatch, TestFlight, and the licenses entry
**FR-174**: Settings entry point to the offline license viewer
**FR-175**: Appearance, Units, Meal Intelligence and Retention
**FR-176**: Developer section and debug console
**FR-177**: Accessibility identifier parity as the acceptance substrate
**FR-178**: VoiceOver, non-colour encoding and Dynamic Type
**FR-179**: Fork-and-build with no project-held signing material
**FR-180**: The documented fixed secret set and isolated credential validation
**FR-181**: Identifiers derived from the Builder Team ID
**FR-182**: One-time identifier and capability registration
**FR-183**: Building, signing and uploading from the Builder's own fork
**FR-184**: Distribution-signing assertion, hard fail
**FR-185**: Custody of signing material within a run
**FR-186**: On-demand and scheduled rebuild so an installed build never lapses
**FR-187**: In-app build provenance, channel and expiry
**FR-188**: Upstream release notice and TestFlight deep link
**FR-189**: Build-time composition of what ships
**FR-190**: One version source of truth
**FR-191**: Monotonic build numbers
**FR-192**: develop-to-main promotion
**FR-193**: Pinned build inputs
**FR-194**: Bot dependency pull requests and the auto-merge scope guard
**FR-195**: Syncing a fork with upstream
**FR-196**: The pipeline as a supported surface, and the Builder boundary
**FR-197**: Fixed Required Check roster and branch protection
**FR-198**: Always-reporting gate shape and fail-closed aggregation
**FR-199**: Every Required Check passes on a fork pull request
**FR-200**: Swift static security analysis with a pinned query set, failing closed
**FR-201**: Dependency vulnerability scanning over the committed resolved graph
**FR-202**: Workflow lint, SHA-pin enforcement and the composite-action secrets guard
**FR-203**: Workflow security auditing at medium-or-higher, with a fork-reachable-checkout backstop
**FR-204**: Entitlements, Plist, signing-material and build-script guard
**FR-205**: Driver protocol public-interface snapshot gate
**FR-206**: Per-Driver protocol tests over recorded frames
**FR-207**: Buildability and full behavioral exercise against the Simulated Driver
**FR-208**: iOS Gate — build and unit test of phone, Watch and widget extension
**FR-209**: UI tests on both Simulator destinations with a published result bundle
**FR-210**: Platform-independent code testable without Xcode
**FR-211**: License Header Gate and dependency license allowlist
**FR-212**: Project-lead review required on trust-boundary files
**FR-213**: Local reproduction of every gate from one committed script
**FR-214**: Contract Pin guards — version agreement, endpoint presence, field presence
**FR-215**: One shared decoder configuration and tolerant-reader guards in both directions
**FR-216**: Contract-version signalling and older-Backend behavior
**FR-217**: Safety Constant drift guard — exactly one definition, and no reintroduced literal
**FR-218**: AI-attribution and sign-off enforcement
**FR-219**: Section directory contract and the page publication gate
**FR-220**: The published documentation set for the iPhone and Apple Watch apps
**FR-221**: Public repository — rendered is not the same as private
**FR-222**: Docs publication dispatch to the website repository
**FR-223**: Fork-to-working-app install runbook and the 90-day rebuild
**FR-224**: Apple Watch setup page
**FR-225**: Contributor documentation, the Driver contribution guide, and the code of conduct
**FR-226**: Security disclosure policy and the pre-declined report class
**FR-227**: In-app license viewer
**FR-228**: License assets generated from the resolved dependency graph on every build
**FR-229**: Fail-closed license policy gate with version-pinned exceptions
**FR-230**: License asset drift test and license-document build inputs
**FR-231**: SPDX headers, never-stamp trees, and the EC-JPAKE notice
**FR-232**: Acknowledgments page — studied versus ported, per upstream project
**FR-233**: Repo-internal, unpublished provenance record
**FR-234**: Medical disclaimer, the alert-delivery conditions, and the per-device verification table
**FR-235**: Prohibition on guaranteed-alert claims on any surface
**FR-236**: Privacy document and the crash-reporting posture under fork-and-build
**FR-237**: The troubleshooting and status-icon pages, and the forced-loss disclosures they carry

### NonFunctional Requirements

**NFR-1**: One deployment floor — iOS 17.0 and watchOS 10.0
**NFR-2**: Supported device classes, and what the Simulator can never prove
**NFR-3**: Pinned toolchain, and a floor-runtime test job
**NFR-4**: One shared safety module, linked by every target (SI-4)
**NFR-5**: Interaction responsiveness
**NFR-6**: Cold start is honest before it is fast
**NFR-7**: Data-volume ceilings the UI must hold
**NFR-8**: Main-thread and background-wake work rules
**NFR-9**: Deterministic behaviour under interruption
**NFR-10**: No published battery figure without a project measurement
**NFR-11**: Background cost is budgeted as work, not as a percentage
**NFR-12**: Low Power Mode and thermal state degrade honestly
**NFR-13**: Persist before derive
**NFR-14**: No trap on any ingest, decode, background-wake or render path
**NFR-15**: Migrations never destroy data as a fallback
**NFR-16**: Bounded growth everywhere
**NFR-17**: Degradation is always announced
**NFR-18**: Credential custody (SI-10)
**NFR-19**: At-rest encryption and file protection
**NFR-20**: Transport security — no cleartext to a non-private host, enforced in the app
**NFR-21**: No therapeutic write surface exists anywhere (SI-1)
**NFR-22**: Minimal, declared attack surface
**NFR-23**: No project telemetry, and network silence with one named exception
**NFR-24**: Log scrubbing is a system-wide invariant (SI-9)
**NFR-25**: Diagnostic export is scrubbed, bounded and user-initiated
**NFR-26**: VoiceOver
**NFR-27**: Dynamic Type
**NFR-28**: Non-colour encoding, and legibility in flattened rendering modes
**NFR-29**: Motion, contrast, and input
**NFR-30**: The accessibility parity rule, and the identifier contract as the UI-test substrate
**NFR-31**: Deliberate English-only v1, with the discipline that makes i18n later mechanical
**NFR-32**: The project can never see a crash, and the design accepts it
**NFR-33**: The on-device diagnostic surface is the only diagnostic channel
**NFR-34**: Every device-only NFR has a named owner before v1 ships

### Additional Requirements

### Architecture spine — 23 binding decisions (AD-n)

Every story inherits these. A story that violates one is a defect, not a variation.

- **AD-1** — Hexagonal paradigm with an actor-guarded device edge
- **AD-2** — Module topology, with `SafetyCore` linked by every rendering target
- **AD-3** — One-way dependency direction, CI-enforced
- **AD-4** — Swift 6 strict concurrency; the device edge is an actor
- **AD-5** — `Glucose` is a value type that cannot hold an invalid number
- **AD-6** — GRDB unforked, at-rest protection from iOS Data Protection
- **AD-7** — One decoder, explicit tolerant reading
- **AD-8** — EC-JPAKE runs on a pinned fork of `swift-crypto`
- **AD-9** — One App Group, exactly one database writer
- **AD-10** — The Coverage Claim has one implementation and one owner
- **AD-11** — Core Bluetooth restoration is the only load-bearing relaunch path
- **AD-12** — No therapeutic write exists to call
- **AD-13** — Typed errors; no silent defaults on a safety path
- **AD-14** — One injectable clock
- **AD-15** — Cleartext is decided in code, not delegated to ATS
- **AD-16** — One Driver lifecycle, owned by the platform
- **AD-17** — Build configuration is a closed dimension, and composition is subtractive only
- **AD-18** — The Watch app is an independently-built unit, not a renderer
- **AD-19** — History cursors are durable and monotonic-by-decode
- **AD-20** — Every safety invariant names its enforcing mechanism
- **AD-21** — AccessorySetupKit where available, and the claim knows which relaunch rules apply
- **AD-22** — Decode failure and domain rejection are different outcomes
- **AD-23** — Acknowledgement is owned by the phone; the Watch sends intent, never state

### Safety invariants the spine binds (SI-n, from the PRD)

- **SI-1** — No therapeutic write exists anywhere.
- **SI-2** — Glucose outside 20–500 mg/dL is rejected, never clamped.
- **SI-3** — mg/dL is canonical everywhere.
- **SI-4** — One definition of each Safety Constant, shared by phone and Watch.
- **SI-5** — The Alert Floor never fires from stale data or from unconfirmed thresholds.
- **SI-6** — The Coverage Claim never overstates.
- **SI-7** — Only completed insulin deliveries are reported as delivered.
- **SI-8** — History cursors never advance past a record that was not successfully decoded.
- **SI-9** — No health value, raw device payload, or credential appears in any log at or above debug level.
- **SI-10** — Credentials and pairing secrets live in the Keychain
- **SI-11** — Backend-supplied Safety Limits may only narrow, never widen,
- **SI-12** — Unknown fields in a Backend response are tolerated; a missing consumed field fails loudly.

### Prerequisite spikes — both block work that depends on them

- **SPK-1 — AccessorySetupKit / relaunch spike.** Apple TN3115: from iOS 26 only apps using AccessorySetupKit are relaunched after force-quit or a Bluetooth toggle. The floor is iOS 17.0, so the Coverage Claim is OS-version-dependent. Device-verified. Gates AD-11, AD-21 and the reliability story.
- **SPK-2 — EC-JPAKE known-answer vector generation.** `JpakeAuthenticatorTest.kt` has zero KATs. Vectors must be generated from the Kotlin implementation under fixed seeds and committed before any Swift conformance test can exist. Gates all Tandem pairing work (AD-8).
- **SPK-3 — Medtronic transport spike, part (a).** Can Core Bluetooth return a `CBPeripheral` for a central that connected to our `CBPeripheralManager`? Answerable **without** a pump. A negative answer invalidates the Medtronic driver architecture, so it runs before that work is committed.

### Infrastructure and setup requirements

- No starter template. Greenfield SPM package; the module topology is fixed by AD-2 and its dependency direction by AD-3.
- Stack pinned: Swift 6.x, iOS 17.0 / watchOS 10.0, GRDB 7.11.1 (unforked), a pinned fork of swift-crypto 4.5.1 exporting `CryptoBoringWrapper`.
- Distribution is fork-and-build: no project-published binary, no project-held signing key; each Builder signs into their own TestFlight.
- Five Required Checks on `develop`, fixed by name in the PRD; branch protection keys on those exact strings.


### UX Design Requirements

> **No UX design contract exists, and this is a deliberate decision — not a gap left open.**
>
> **Decision (confirmed 2026-08-09):** proceed without `bmad-ux`. This is a port, and the Android UI *is* the specification. The PRD already fixes literal copy, card and draw order, the six connection-state indicators with their colours, severity banding, the Not-Watching Reason vocabulary, non-colour encoding, and the accessibility-identifier parity rule. A design pass against a parity mandate would produce divergence from Android, which is the opposite of the requirement.
>
> **Where design decisions genuinely remain:** the 18 additive substitutes in the PRD's Parity Ledger have no Android counterpart. Six carry real user-facing design:
>
> - **PA-1** Live Activity on the Lock Screen and Dynamic Island
> - **PA-2** WidgetKit accessory complications on watchOS
> - **PA-3** iPhone Lock Screen and Home Screen widgets
> - **PA-4** Pre-baked decay timelines
> - **PA-5** Proactive coverage-lapse notification
> - **PA-13** Guided complication setup
>
> Each is heavily constrained already — WidgetKit fixes the accessory families, complications render in a system-controlled tint, and the PRD fixes what each surface must say, that it must be unambiguous in monochrome, and that it may never overstate coverage. **Those decisions are made in the stories that build them,** where the constraints and the coverage vocabulary sit in the acceptance criteria.
>
> **Known thin area:** the first-run onboarding sequence is less specified than the rest. The pairing *recovery* flow is well covered (the broken-pairing wall has verbatim copy); first-run is not. Flagged in the affected stories. A scoped UX pass on onboarding alone remains a reasonable later addition.

### FR Coverage Map

| FR | Epic | Requirement |
| --- | --- | --- |
| FR-1 | Epic 1 | Reaching pairing from Settings |
| FR-2 | Epic 1 | Driver-determined pairing shape and Driver-supplied copy |
| FR-3 | Epic 1 | Bluetooth pre-explanation, the system prompt, and denial recovery |
| FR-4 | Epic 1 | Scanning and the discovered-Pump list |
| FR-5 | Epic 1 | Pairing-code entry |
| FR-6 | Epic 1 | Advertise-and-wait pairing |
| FR-7 | Epic 1 | One-phone-at-a-time warning |
| FR-8 | Epic 1 | The connection state model |
| FR-9 | Epic 1 | Cancelling a connection attempt |
| FR-10 | Epic 1 | Distinct pairing-failure categories |
| FR-11 | Epic 1 | The broken-pairing wall |
| FR-12 | Epic 1 | Restraint before declaring a pairing broken |
| FR-13 | Epic 1 | Indefinite reconnection |
| FR-14 | Epic 1 | Reconnection while backgrounded, locked, evicted and after reboot |
| FR-15 | Epic 1 | Force-quit disclosure and detection |
| FR-16 | Epic 7 | Foreground-only discoverability for advertise-and-wait Drivers |
| FR-17 | Epic 1 | One canonical unpair, always confirmed |
| FR-18 | Epic 1 | Per-Driver credential isolation |
| FR-19 | Epic 1 | Pump identity is a name and a model, never a raw identifier |
| FR-20 | Epic 1 | Connection status outside the pairing flow |
| FR-21 | Epic 1 | Driver Catalog as the sole registration path |
| FR-22 | Epic 1 | Viewing the Drivers this build contains |
| FR-23 | Epic 1 | Activating a Driver and swapping a single-instance Capability |
| FR-24 | Epic 1 | Multi-instance Capabilities |
| FR-25 | Epic 1 | Deactivating a Driver |
| FR-26 | Epic 1 | Selection surviving relaunch, restart, upgrade and background launch |
| FR-27 | Epic 1 | Compile-time kill switch making a Driver wholly absent |
| FR-28 | Epic 1 | A failing Driver is skipped without affecting the others |
| FR-29 | Epic 1 | Per-Driver namespaced settings that survive deactivation |
| FR-30 | Epic 1 | The closed Capability set and its cardinality rules |
| FR-31 | Epic 1 | Read-only by construction — no therapeutic write exists |
| FR-32 | Epic 1 | Safety Limits read fresh at every validation pass, narrowing only |
| FR-33 | Epic 1 | No active Driver is a distinguishable error, never an empty result |
| FR-34 | Epic 1 | Best-effort bounded event delivery |
| FR-35 | Epic 1 | The Simulated Driver as a shipped first-class Driver |
| FR-36 | Epic 1 | The Trace-Replay Driver as a shipped first-class Driver |
| FR-37 | Epic 1 | Driver-contributed dashboard cards and detail screens |
| FR-38 | Epic 1 | The Backend-mediated Nightscout data source as a Driver-shaped Capability |
| FR-39 | Epic 1 | Home dashboard composition and fixed card order |
| FR-40 | Epic 1 | Pull-to-refresh forced read |
| FR-41 | Epic 1 | Foreground re-read on activation |
| FR-42 | Epic 1 | Refresh failures preserve cached values |
| FR-43 | Epic 1 | Pump-link indicator |
| FR-44 | Epic 1 | Sync and Backend reachability indicators |
| FR-45 | Epic 1 | Driver brand marks |
| FR-46 | Epic 1 | Glucose hero |
| FR-47 | Epic 1 | Severity colour from stored mg/dL alone |
| FR-48 | Epic 1 | Too Stale de-emphasis of the hero |
| FR-49 | Epic 1 | Freshness Tier classification |
| FR-50 | Epic 1 | Wall-clock freshness re-evaluation |
| FR-51 | Epic 1 | Staleness badge |
| FR-52 | Epic 4 | Trend chart base rendering |
| FR-53 | Epic 4 | Chart draw order, overlays and legend |
| FR-54 | Epic 4 | Chart time-axis labels and tick counts |
| FR-55 | Epic 4 | Chart detail interaction |
| FR-56 | Epic 4 | Chart detail landscape presentation |
| FR-57 | Epic 4 | Five independent period selections |
| FR-58 | Epic 4 | Time in Range |
| FR-59 | Epic 4 | CGM statistics |
| FR-60 | Epic 4 | Display-boundary unit rendering and numeric formatting |
| FR-61 | Epic 1 | Single injectable time source |
| FR-62 | Epic 6 | Theme selection |
| FR-63 | Epic 1 | Navigation, capability-driven tab bar and session banner |
| FR-64 | Epic 6 | Dashboard legibility under Dynamic Type |
| FR-65 | Epic 2 | Alert type vocabulary and delivery tiering |
| FR-66 | Epic 2 | Interruption level and the audibility honesty statement |
| FR-67 | Epic 2 | Per-severity alert sound selection |
| FR-68 | Epic 2 | Foreground presentation |
| FR-69 | Epic 2 | Alert content, title format, and caregiver rendering |
| FR-70 | Epic 2 | Notification slot identity and duplicate suppression |
| FR-71 | Epic 2 | The Alert Floor — on-device alarming with no Backend |
| FR-72 | Epic 2 | Freshness and clock-trust gate |
| FR-73 | Epic 2 | Never alarm from unconfirmed Alert Thresholds |
| FR-74 | Epic 2 | Re-alarm cooldown and episode semantics |
| FR-75 | Epic 2 | Episode guard against Backend alert history |
| FR-76 | Epic 2 | Bounded finite re-alarm ladder |
| FR-77 | Epic 2 | Acknowledge from the notification |
| FR-78 | Epic 2 | Offline acknowledgement durability and reconciliation |
| FR-79 | Epic 2 | On-device Alert Threshold editor (Backend-optional mode) |
| FR-80 | Epic 2 | Backend-supplied Alert Thresholds are read-only and adopted within the hour |
| FR-81 | Epic 2 | Invalid Backend threshold responses are discarded whole |
| FR-82 | Epic 2 | Alert Threshold provenance across sign-out |
| FR-83 | Epic 2 | The Coverage Claim |
| FR-84 | Epic 2 | Coverage Claim expiry and decay |
| FR-85 | Epic 2 | Proactive coverage-lapse notification, force-quit and reboot warnings |
| FR-86 | Epic 2 | Automatic resume after background termination |
| FR-87 | Epic 2 | Backend alert history |
| FR-88 | Epic 2 | Developer fault-injection surface |
| FR-89 | Epic 4 | Insulin Summary |
| FR-90 | Epic 4 | Delivered-insulin honesty |
| FR-91 | Epic 4 | Recent Boluses and Bolus History |
| FR-92 | Epic 4 | Glucose-Reading-at-event and IOB-at-event cross-referencing |
| FR-93 | Epic 5 | Meal availability gate, Home glance and entry point |
| FR-94 | Epic 5 | Meal photo capture and preparation |
| FR-95 | Epic 5 | Upload lifecycle and the non-sticking estimate indicator |
| FR-96 | Epic 5 | The never-dose qualifier on every carb-estimate surface |
| FR-97 | Epic 5 | Carb range and confidence presentation |
| FR-98 | Epic 5 | Multi-read disagreement disclosure |
| FR-99 | Epic 5 | Food identity confirmation |
| FR-100 | Epic 5 | Carb range correction — reject, never clamp |
| FR-101 | Epic 5 | Estimate provenance — "How was this estimated?" |
| FR-102 | Epic 5 | Backend-authored nutrition, rendered verbatim |
| FR-103 | Epic 5 | Meal history and record deletion |
| FR-104 | Epic 5 | Common foods — save, edit, read-only re-log, delete |
| FR-105 | Epic 5 | AI Chat tab availability |
| FR-106 | Epic 5 | One-time AI provider probe and its three landing states |
| FR-107 | Epic 5 | Sending a message and the 2000-character limit |
| FR-108 | Epic 5 | Ephemeral in-memory transcript |
| FR-109 | Epic 5 | Curated failure copy for every failure class |
| FR-110 | Epic 5 | Honest disclosure of an interrupted request |
| FR-111 | Epic 5 | Starter suggestions and the standing safety disclaimers |
| FR-112 | Epic 5 | Assistant markdown sanitization |
| FR-113 | Epic 5 | Spoken responses, voice choice and audio ducking |
| FR-114 | Epic 5 | AI Chat on the Watch |
| FR-115 | Epic 3 | Single-bundle Watch app delivery and read-only wrist posture |
| FR-116 | Epic 3 | One shared safety module behind every wrist surface, demonstrable in the Simulator |
| FR-117 | Epic 3 | The wrist complication set, and the absence of custom watch faces |
| FR-118 | Epic 3 | Guided complication setup and active-face detection |
| FR-119 | Epic 3 | Glanceable surfaces on the iPhone Lock Screen, Dynamic Island and Watch Smart Stack |
| FR-120 | Epic 3 | Glucose Reading on the wrist with the Freshness Tier treatment |
| FR-121 | Epic 3 | IOB on the wrist with the Freshness Tier treatment |
| FR-122 | Epic 3 | Wrist decay on the Watch's own clock, within the OS refresh budget |
| FR-123 | Epic 3 | Backward clock-jump guard |
| FR-124 | Epic 3 | Display-only mmol/L conversion and glucose banding on the wrist |
| FR-125 | Epic 3 | Alert Threshold sanitization on the wrist |
| FR-126 | Epic 3 | The wrist Coverage Claim — rendered and decayed, never derived |
| FR-127 | Epic 3 | Not-Watching Reason copy on the wrist |
| FR-128 | Epic 3 | Watch-scheduled wrist alert delivery |
| FR-129 | Epic 3 | Locally scheduled 30-minute wrist re-alarm ladder |
| FR-130 | Epic 3 | Live-alert refresh, and never retracting on data we cannot vouch for |
| FR-131 | Epic 3 | Wrist alert dismissal |
| FR-132 | Epic 3 | Six-hour basal, Bolus and IOB history on the Watch |
| FR-133 | Epic 3 | Full-screen Watch glucose graph and the shared Y-axis rule |
| FR-134 | Epic 3 | iPhone Settings > Watch — preference sync and the true wrist-link state |
| FR-135 | Epic 1 | Encrypted local store for all monitoring data |
| FR-136 | Epic 1 | Database key generated once, device-only, never inherited |
| FR-137 | Epic 1 | Write-time deduplication and cross-source collision resolution |
| FR-138 | Epic 1 | Canonical mg/dL storage and rejection of invariant-violating rows |
| FR-139 | Epic 1 | Retention window bounding every table |
| FR-140 | Epic 5 | Durable local record before any upload, surviving suspension |
| FR-141 | Epic 5 | Upload failure classification and the retry budget |
| FR-142 | Epic 5 | Bounded outbound queue and its user-visible state |
| FR-143 | Epic 5 | Backend-optional transitions |
| FR-144 | Epic 5 | Opportunity-driven background work |
| FR-145 | Epic 1 | Capture-time freshness and detected collection gaps |
| FR-146 | Epic 5 | Resumable, cancellable initial history download |
| FR-147 | Epic 5 | Staying signed in with proactive token refresh |
| FR-148 | Epic 5 | Exactly one serialized refresh per 401, and sign-out always wins |
| FR-149 | Epic 5 | Offline session expiry without data loss |
| FR-150 | Epic 5 | Cleartext transport policy |
| FR-151 | Epic 5 | Local network reachability — permission, denial copy, and the insecure-HTTP opt-in |
| FR-152 | Epic 5 | Three connectivity states |
| FR-153 | Epic 5 | Backend-mediated Nightscout source |
| FR-154 | Epic 5 | Nightscout sync execution — cursor, paging and clean abort |
| FR-155 | Epic 5 | Tolerant reader with loud failure on missing consumed fields |
| FR-156 | Epic 5 | Device registration as an iOS device |
| FR-157 | Epic 5 | Backend-alert transport posture — SSE while alive, APNs reserved |
| FR-158 | Epic 5 | Scrubbed diagnostic log export |
| FR-159 | Epic 1 | First-run onboarding flow and stage gating |
| FR-160 | Epic 1 | Unskippable safety acknowledgement |
| FR-161 | Epic 5 | Optional Backend setup, connection test and sign-in |
| FR-162 | Epic 5 | Local-network-blocked state and Settings deep link |
| FR-163 | Epic 5 | Insecure LAN HTTP opt-in and the persistent insecure-transport banner |
| FR-164 | Epic 1 | Finishing onboarding without a Backend |
| FR-165 | Epic 1 | Notification and Bluetooth authorization on both completion paths |
| FR-166 | Epic 6 | Settings composition, ordering and mode-dependent visibility |
| FR-167 | Epic 5 | Account section and sign-out |
| FR-168 | Epic 5 | Alert Thresholds are read-only whenever a Backend is configured |
| FR-169 | Epic 6 | Alert Thresholds are editable in Backend-optional mode with dependent validation |
| FR-170 | Epic 6 | Per-severity alert sound picker |
| FR-171 | Epic 2 | Notification status card reporting every suppressing condition |
| FR-172 | Epic 6 | Watch section — pairing state, what the Watch surfaces show, and telemetry |
| FR-173 | Epic 6 | About — versions, build mismatch, TestFlight, and the licenses entry |
| FR-174 | Epic 6 | Settings entry point to the offline license viewer |
| FR-175 | Epic 6 | Appearance, Units, Meal Intelligence and Retention |
| FR-176 | Epic 6 | Developer section and debug console |
| FR-177 | Epic 6 | Accessibility identifier parity as the acceptance substrate |
| FR-178 | Epic 6 | VoiceOver, non-colour encoding and Dynamic Type |
| FR-179 | Epic 8 | Fork-and-build with no project-held signing material |
| FR-180 | Epic 8 | The documented fixed secret set and isolated credential validation |
| FR-181 | Epic 8 | Identifiers derived from the Builder Team ID |
| FR-182 | Epic 8 | One-time identifier and capability registration |
| FR-183 | Epic 8 | Building, signing and uploading from the Builder's own fork |
| FR-184 | Epic 8 | Distribution-signing assertion, hard fail |
| FR-185 | Epic 8 | Custody of signing material within a run |
| FR-186 | Epic 8 | On-demand and scheduled rebuild so an installed build never lapses |
| FR-187 | Epic 8 | In-app build provenance, channel and expiry |
| FR-188 | Epic 8 | Upstream release notice and TestFlight deep link |
| FR-189 | Epic 8 | Build-time composition of what ships |
| FR-190 | Epic 8 | One version source of truth |
| FR-191 | Epic 8 | Monotonic build numbers |
| FR-192 | Epic 8 | develop-to-main promotion |
| FR-193 | Epic 8 | Pinned build inputs |
| FR-194 | Epic 8 | Bot dependency pull requests and the auto-merge scope guard |
| FR-195 | Epic 8 | Syncing a fork with upstream |
| FR-196 | Epic 8 | The pipeline as a supported surface, and the Builder boundary |
| FR-197 | Epic 8 | Fixed Required Check roster and branch protection |
| FR-198 | Epic 8 | Always-reporting gate shape and fail-closed aggregation |
| FR-199 | Epic 8 | Every Required Check passes on a fork pull request |
| FR-200 | Epic 8 | Swift static security analysis with a pinned query set, failing closed |
| FR-201 | Epic 8 | Dependency vulnerability scanning over the committed resolved graph |
| FR-202 | Epic 8 | Workflow lint, SHA-pin enforcement and the composite-action secrets guard |
| FR-203 | Epic 8 | Workflow security auditing at medium-or-higher, with a fork-reachable-checkout backstop |
| FR-204 | Epic 8 | Entitlements, Plist, signing-material and build-script guard |
| FR-205 | Epic 8 | Driver protocol public-interface snapshot gate |
| FR-206 | Epic 8 | Per-Driver protocol tests over recorded frames |
| FR-207 | Epic 8 | Buildability and full behavioral exercise against the Simulated Driver |
| FR-208 | Epic 8 | iOS Gate — build and unit test of phone, Watch and widget extension |
| FR-209 | Epic 8 | UI tests on both Simulator destinations with a published result bundle |
| FR-210 | Epic 8 | Platform-independent code testable without Xcode |
| FR-211 | Epic 8 | License Header Gate and dependency license allowlist |
| FR-212 | Epic 8 | Project-lead review required on trust-boundary files |
| FR-213 | Epic 8 | Local reproduction of every gate from one committed script |
| FR-214 | Epic 8 | Contract Pin guards — version agreement, endpoint presence, field presence |
| FR-215 | Epic 8 | One shared decoder configuration and tolerant-reader guards in both directions |
| FR-216 | Epic 8 | Contract-version signalling and older-Backend behavior |
| FR-217 | Epic 8 | Safety Constant drift guard — exactly one definition, and no reintroduced literal |
| FR-218 | Epic 8 | AI-attribution and sign-off enforcement |
| FR-219 | Epic 8 | Section directory contract and the page publication gate |
| FR-220 | Epic 8 | The published documentation set for the iPhone and Apple Watch apps |
| FR-221 | Epic 8 | Public repository — rendered is not the same as private |
| FR-222 | Epic 8 | Docs publication dispatch to the website repository |
| FR-223 | Epic 8 | Fork-to-working-app install runbook and the 90-day rebuild |
| FR-224 | Epic 8 | Apple Watch setup page |
| FR-225 | Epic 8 | Contributor documentation, the Driver contribution guide, and the code of conduct |
| FR-226 | Epic 8 | Security disclosure policy and the pre-declined report class |
| FR-227 | Epic 8 | In-app license viewer |
| FR-228 | Epic 8 | License assets generated from the resolved dependency graph on every build |
| FR-229 | Epic 8 | Fail-closed license policy gate with version-pinned exceptions |
| FR-230 | Epic 8 | License asset drift test and license-document build inputs |
| FR-231 | Epic 8 | SPDX headers, never-stamp trees, and the EC-JPAKE notice |
| FR-232 | Epic 8 | Acknowledgments page — studied versus ported, per upstream project |
| FR-233 | Epic 8 | Repo-internal, unpublished provenance record |
| FR-234 | Epic 8 | Medical disclaimer, the alert-delivery conditions, and the per-device verification table |
| FR-235 | Epic 8 | Prohibition on guaranteed-alert claims on any surface |
| FR-236 | Epic 8 | Privacy document and the crash-reporting posture under fork-and-build |
| FR-237 | Epic 8 | The troubleshooting and status-icon pages, and the forced-loss disclosures they carry |

## Epic List

### Epic 1: Pair a pump and see my glucose

A person with a Tandem t:slim X2 installs the app, pairs their pump over Bluetooth, and sees their current glucose with a trend arrow and an honest freshness marker — with no Backend, no account, and nothing in the cloud. This is the walking skeleton: it stands up SafetyCore, the Driver Catalog, the encrypted store and the dashboard, and it is the first point at which the product is worth having.

**FRs covered (62):** FR-1–FR-15, FR-17–FR-51, FR-61, FR-63, FR-135–FR-139, FR-145, FR-159–FR-160, FR-164–FR-165

### Epic 2: Know when I'm low

The app alarms for urgent low, low, high and urgent high from readings on the device alone, and tells the user at all times whether anything is actually watching — with a specific, actionable reason whenever it is not. Delivers the product's irreducible safety net and the honesty contract that surrounds it.

**FRs covered (25):** FR-65–FR-88, FR-171

### Epic 3: Glance without opening the app

Glucose, trend and coverage reach the wrist, the Lock Screen and the Dynamic Island, decaying honestly on the Watch's own clock and never showing a value the phone could not vouch for. Delivers the at-a-glance product that is most of the daily experience.

**FRs covered (20):** FR-115–FR-134

### Epic 4: Understand my patterns

Charts, Time in Range, CGM statistics, insulin summary and bolus history let a user work out what happened — from data already on the device, with no export and no upload.

**FRs covered (13):** FR-52–FR-60, FR-89–FR-92

### Epic 5: Run it against my own server

A user connects the app to their own self-hosted Backend and gains sync, Nightscout-sourced data, meal carb estimation and AI chat — while the app stays fully functional without one. Delivers everything the Backend adds, and proves Backend-optional mode is a first-class mode rather than a degraded one.

**FRs covered (45):** FR-93–FR-114, FR-140–FR-144, FR-146–FR-158, FR-161–FR-163, FR-167–FR-168

### Epic 6: Make it mine, and make it usable by everyone

Settings, appearance, units, retention, per-severity sounds, the Watch section, and the accessibility contract — VoiceOver descriptions, non-colour encoding, Dynamic Type, and identifier parity with the Android client, which is also the acceptance substrate for every Simulator-runnable gate.

**FRs covered (12):** FR-62, FR-64, FR-166, FR-169–FR-170, FR-172–FR-178

### Epic 7: Support my Medtronic pump

A Medtronic MiniMed 680G/770G/780G user pairs by making the phone discoverable to the pump and sees the same monitoring surfaces as a Tandem user. Ships gated at Beta with its transport assumption named, because nobody on the team has the hardware.

**FRs covered (1):** FR-16

### Epic 8: Build it, install it, and keep it working

A Builder forks the repository, adds their own Apple credentials, and produces a signed build on their own iPhone through their own TestFlight — then keeps it alive past the 90-day expiry. Includes the gates that make the pipeline trustworthy and the documentation that makes it followable, because under fork-and-build the docs are the delivery mechanism.

**FRs covered (59):** FR-179–FR-237

---

## Epic 1: Pair a pump and see my glucose

A person with a Tandem t:slim X2 installs the app, pairs their pump over Bluetooth, and sees their current glucose with a trend arrow and an honest freshness marker — with no Backend, no account, and nothing in the cloud. This is the walking skeleton: it stands up `SafetyCore`, the Driver Catalog, the encrypted store and the dashboard, and it is the first point at which the product is worth having.

**Inherits:** AD-1 – AD-23. **Upholds:** SI-1, SI-2, SI-3, SI-4, SI-8, SI-9, SI-10.

### Story 1.1: Generate EC-JPAKE known-answer vectors (SPK-2)

As a maintainer,
I want known-answer vectors captured from the Android EC-JPAKE implementation,
So that the Swift handshake can be proven byte-identical instead of merely self-consistent.

**Acceptance Criteria:**

**Given** the Kotlin `EcJpake` implementation and a fixed, injected seed
**When** the round-1, round-2 and derived-secret payloads are captured
**Then** they are committed as fixture files with the seed and curve parameters recorded alongside
**And** the fixtures cover at least one full client-role handshake and one malformed-input rejection
**And** the task records that `JpakeAuthenticatorTest.kt` contained zero known-answer vectors before this story, so nothing downstream assumes vectors that never existed (AD-8)

### Story 1.2: SafetyCore — canonical glucose, safety constants and one clock

As a developer building any surface that shows a number,
I want a glucose type that cannot hold an invalid value and a single source for every safety constant,
So that no two targets can disagree about the same reading.

**Acceptance Criteria:**

**Given** a greenfield SPM package (there is **no** starter template) whose target topology and one-way dependency direction follow AD-2 and AD-3
**When** `SafetyCore` is created with zero dependencies
**And** a `Glucose` constructed from a value outside 20–500 mg/dL
**Then** the initializer **throws** — it does not clamp, substitute or `precondition` (AD-5, SI-2)
**And** the Conversion Factor 18.0156, the 20–500 bound and the Tandem epoch offset are each defined exactly once, and a second definition anywhere fails the build (AD-2, SI-4)
**And** every current time comes from an injectable `Clock`; a direct `Date()` in `SafetyCore` fails lint (AD-14)
**And** that clock is the single time source behind freshness, chart windows, day-boundary alignment and decay — no surface reads the wall clock directly (FR-61)
**And** mmol/L exists only as a formatting output, converted once and rounded last (SI-3)

### Story 1.3: Freshness Tier classification and independent decay

As a user glancing at a number,
I want the app to know how old that reading is on its own schedule,
So that a stale value is never presented as current.

**Acceptance Criteria:**

**Given** a Glucose Reading carrying its own sensor timestamp
**When** its age is classified
**Then** it resolves to Fresh, Stale or Too Stale using half-open boundaries, pinned by test at each boundary value (FR-49)
**And** re-evaluation runs on a wall-clock timer at one quarter of the boundary, independent of new data arriving (FR-50)
**And** a negative age classifies as Fresh **for display only** and never arms the Alert Floor (AD-14, SI-5)
**And** the staleness badge renders nothing when Fresh, "Stale" in amber, and "Too old" in the error colour (FR-51)

### Story 1.4: The Driver Catalog and the closed Capability set

As a Builder,
I want every Driver in my build listed explicitly with what it provides,
So that nothing can be loaded at runtime and nothing can go missing silently.

**Acceptance Criteria:**

**Given** the Driver Catalog is the sole registration path
**When** a Driver target builds but is absent from the Catalog
**Then** the `iOS Gate` Required Check fails (FR-21, AD-12)
**And** the Capability set is exactly six and closed — glucose source, insulin source, pump status, BGM source, data sync, bolus-category provider — with **no calibration member** (FR-30, SI-1)
**And** no protocol in `DriverAPI` declares a write, command or set member, and a CI symbol scan over Driver targets fails on a delivery verb or pump-write characteristic (AD-12, SI-1)
**And** a Driver may depend only on `DriverAPI` and `SafetyCore`, asserted from the resolved package manifest (AD-3)
**And** the Drivers screen lists every Driver this build contains with name, protocol and version, active state, and its Verification Status (FR-22)
**And** the read-only posture is structural: no Capability protocol declares a therapeutic write, so there is nothing for a Driver to call (FR-31, SI-1)
**And** Safety Limits are read fresh at every validation pass and may only narrow the absolute bound, never widen it (FR-32, SI-11)

### Story 1.5: The Simulated Driver as a shipped target

As the lead developer working without an iPhone,
I want a shipped Driver that produces realistic data with no Bluetooth,
So that every surface above the driver boundary is buildable and demonstrable in the Simulator.

**Acceptance Criteria:**

**Given** Core Bluetooth does not exist in the iOS Simulator
**When** the Simulated Driver is activated
**Then** it produces Glucose Readings, IOB, basal and bolus events that pass every Safety Limit validation, through the same Capability protocols as a real Driver (FR-35)
**And** it ships in every configuration under the same compile-time exclusion as any other Driver, not behind `#if DEBUG` (AD-17)
**And** it can drive the dashboard, freshness decay and connection states end to end without hardware
**And** this is recorded as net-new work with no Android counterpart — `plugins/example` is not a built module there

### Story 1.6: Encrypted local store with write-time invariants

As a user,
I want my pump data stored on my device and unreadable to anything else,
So that my health data never leaves my control.

**Acceptance Criteria:**

**Given** GRDB unforked on plain SQLite
**When** the store is created
**Then** the file carries iOS Data Protection at `CompleteUntilFirstUserAuthentication` — never `NSFileProtectionComplete`, which would fail background writes while locked (AD-6, FR-135, FR-136)
**And** this story creates **only** the tables Epic 1 needs — glucose readings, pump status and raw history; alert history arrives with Epic 2, the outbound queue with Epic 5, meals with Epic 5 (FR-135)
**And** at most one CGM reading exists per timestamp, one basal per timestamp, and cross-source collisions resolve deterministically (FR-137)
**And** a row violating the **absolute** 20–500 bound is rejected at write; narrowable Safety Limits are never a parameter to the glucose initializer (FR-138, AD-5)
**And** retention is user-set between 1 and 30 days defaulting to 7, and bounds every table including alert history and raw pump history (FR-139)
**And** migrations are numbered, forward-only, starting at v1 with no Android inheritance (AD-6)

### Story 1.7: The Trace-Replay Driver

As a maintainer,
I want recorded pump frames replayed through the real parsers,
So that protocol correctness is testable without hardware and without a live pump.

**Acceptance Criteria:**

**Given** committed frame traces
**When** the Trace-Replay Driver runs
**Then** frames pass through the same parsing path a live Driver uses, with no test-only branch (FR-36)
**And** traces are de-identified before commit — glucose values, doses and serial numbers synthesized or offset — because the repository is public
**And** a decode failure in a trace surfaces as a decode failure, not a domain rejection (AD-22)

### Story 1.8: Discover a Tandem pump by scanning

As a user pairing for the first time,
I want to see nearby pumps identified by name and model,
So that I can pick mine with confidence.

**Acceptance Criteria:**

**Given** Bluetooth is authorized and powered on
**When** the user starts a scan from the pairing flow
**Then** discovered pumps appear in a live-updating list showing name and detected model, never a raw device identifier (FR-6, FR-19)
**And** the scan stops automatically after a bounded period of no interaction so the radio is not left running (FR-7)
**And** when a scan cannot start, the specific blocking condition is named — Bluetooth off, unauthorized, or already connected — rather than a generic failure (FR-8)
**And** the discovered-Pump list updates live and ages out entries that stop advertising (FR-4)

### Story 1.9: Complete first-time Tandem pairing

As a user,
I want to pair my pump by entering its pairing code,
So that the app can read my glucose.

**Acceptance Criteria:**

**Given** a pump selected from the scan list
**When** the user enters a pairing code of 6 to 16 characters
**Then** the EC-JPAKE handshake runs against the vectors committed in Story 1.1 and reproduces them byte-for-byte (AD-8)
**And** the user is told why Bluetooth is needed **before** the system prompt appears (FR-3)
**And** the user can cancel during connecting or authenticating and return to the previous state (FR-10)
**And** the pairing-code field accepts 6 to 16 characters with no character-class restriction (FR-5)
**And** cancelling a connection attempt leaves no live subscription behind, so the next attempt starts clean (FR-9)
**And** a rejection names its category — wrong or expired code, pump busy, or trust failure — rather than collapsing them into one string (FR-12)
**And** no pairing path issues any device command (SI-1)

### Story 1.10: Reconnect indefinitely, and survive backgrounding

As a user,
I want the app to reconnect to my pump on its own,
So that I do not have to think about it.

**Acceptance Criteria:**

**Given** a pairing exists
**When** the connection drops for any reason short of an explicit unpair
**Then** the app retries indefinitely — **no attempt cap, no give-up condition**; bounded backoff intervals are permitted, a terminal state is not (FR-13, AD-13)
**And** `CBCentralManager` is configured with a restoration identifier and reconnection continues while backgrounded and while the device is locked (FR-14, AD-11)
**And** the user is told plainly that force-quitting from the App Switcher stops monitoring (FR-15)
**And** pairing secrets are stored in the Keychain, device-only and after-first-unlock, so overnight reconnection works while locked (SI-10)

### Story 1.11: Recover from a broken pairing

As a user whose pump has forgotten this phone,
I want to be told what actually happened and what to do,
So that I am not left staring at a generic disconnect.

**Acceptance Criteria:**

**Given** a trust failure the app can detect
**When** the condition is recognised
**Then** the app presents the broken-pairing wall — not an ordinary "not paired" state — with verbatim copy (FR-11)
**And** the wall states that iOS gives the app no way to clear a Bluetooth bond, and walks the user through Settings → Bluetooth → ⓘ → Forget This Device, then Retry Pairing (PL-1)
**And** the app never presents that instruction for an ordinary disconnection (FR-11)
**And** unpairing requires explicit confirmation, clears credentials, and tells the user to forget the device in iOS Settings too (FR-17, FR-18)

### Story 1.12: Activate, deactivate and persist Driver selection

As a Builder,
I want my Driver choice to survive relaunch and upgrade,
So that a background wake reconnects without me opening the app.

**Acceptance Criteria:**

**Given** a Driver claiming a single-instance Capability is activated
**When** another Driver already holds that slot
**Then** the incoming Driver's activation runs first, the active set is updated, then the conflicting Driver is deactivated — the derived slot is never empty (FR-23, AD-2)
**And** what persists is the **set of active Driver ids**; slots are derived from it by a total deterministic function with a stable id tiebreak, and no slot table exists (AD-2, AD-3)
**And** restoration works on a background relaunch with no UI, no scene and no network, and does not depend on an authenticated Backend (FR-26)
**And** deactivation requires confirmation naming what stops, and preserves credentials and per-Driver settings (FR-25)
**And** a Driver excluded at compile time leaves its persisted selection untouched; a Driver whose activation throws has its selection cleared (FR-27, FR-28)
**And** multi-instance Capabilities — BGM source and data sync — allow several active Drivers at once without eviction (FR-24)
**And** each Driver has private, namespaced settings storage that survives deactivation and reactivation (FR-29)
**And** a read attempted with no active Driver returns a distinguishable error, never an empty result that reads as "no data" (FR-33)
**And** event delivery between Drivers and the platform is explicitly best-effort with bounded buffering (FR-34)

### Story 1.13: Home dashboard and the glucose hero

As a user opening the app,
I want my current glucose at a glance,
So that one look answers the question I opened it for.

**Acceptance Criteria:**

**Given** a paired pump producing readings
**When** Home renders
**Then** the card order is fixed and identical to the Android client, and every card renders with its own empty state — no card is hidden for lack of data (FR-39)
**And** the hero shows the value at hero scale with its trend glyph in the same colour, banded from the **Target Range** — never from Alert Thresholds (FR-46, FR-47)
**And** at Too Stale the hero loses its severity colour and de-emphasises (FR-48)
**And** the trend glyph carries its own timestamp and renders at the **worse** of the two Freshness Tiers, degrading to "?" when its own source is Too Stale (FR-46)

### Story 1.14: The status row — pump link, and what it does not claim

As a user,
I want to see whether the app is connected to my pump,
So that I know whether the number is live.

**Acceptance Criteria:**

**Given** the status row is present in every mode
**When** the connection state changes
**Then** the pump-link indicator shows six distinct states with text and colour as well as a glyph, so no state depends on glyph recognition (FR-43)
**And** the sync and Backend-reachability indicators are hidden entirely when no Backend is configured (FR-44)
**And** each active Driver with a bundled brand mark shows it untinted, in a deterministic order (FR-45)
**And** the crossed-out Bluetooth state is the resting state when nothing is paired, not an error

### Story 1.15: Refresh without losing what I already had

As a user,
I want to pull to refresh and have the app re-read on return,
So that I can force a check without risking the data already on screen.

**Acceptance Criteria:**

**Given** cached values are on screen
**When** the user pulls to refresh, or the app returns to the foreground
**Then** the pump read sequence runs immediately (FR-40, FR-41)
**And** any refresh or reconciliation failure leaves the previously cached values intact and is logged (FR-42)
**And** no failure path substitutes a default, a zero or a clamp (AD-13)

### Story 1.16: Navigation and the capability-driven tab bar

As a user,
I want the app to show only what my configuration supports,
So that I am not offered a tab that cannot work.

**Acceptance Criteria:**

**Given** the app's mode and active Capabilities
**When** the tab bar renders
**Then** Home, Alerts and Settings are always present, and AI Chat appears only when a Backend base URL is configured (FR-63)
**And** the start destination depends only on onboarding completion, never on session validity (FR-63)
**And** detail screens hide the tab bar and provide a back affordance

### Story 1.17: First run — welcome, safety, and getting to a working monitor

As a new user,
I want to get from install to a paired pump without being forced through a server setup I do not want,
So that Backend-optional mode is genuinely reachable.

**Acceptance Criteria:**

**Given** a first launch
**When** the user moves through onboarding
**Then** the safety acknowledgement cannot be skipped or swiped past and requires an explicit action (FR-160)
**And** the Backend stage carries an always-available **"Use without a server"** control that completes onboarding into Backend-optional mode, present regardless of whether a connection test has run or failed (FR-159, FR-164)
**And** notification and Bluetooth authorization are requested on **both** completion paths (FR-165)
**And** the user is told during onboarding that restarting the phone or force-quitting the app stops monitoring
**And** `[ASSUMPTION]` first-run visual design is the least-specified area of the PRD; this story implements the stated sequence and copy, and flags anything it had to invent

### Story 1.18: Driver-contributed cards, deterministically ordered

As a Builder,
I want Driver-supplied cards to appear in a stable position,
So that the dashboard does not reshuffle between refreshes.

**Acceptance Criteria:**

**Given** one or more active Drivers contributing dashboard cards
**When** Home renders repeatedly
**Then** platform cards occupy priority 0–50 and Driver cards 100+, lower sorting higher, ties broken by Driver id (FR-37)
**And** the order is identical across repeated renders — Android needed an explicit sort because map iteration order shuffled badges (FR-38)
**And** a Driver contributes UI as declarative data, never as views (AD-1)

### Story 1.19: Reach pairing from Settings, with Driver-supplied copy

As a user,
I want the pairing flow to explain my specific pump,
So that the instructions match the device in my hand.

**Acceptance Criteria:**

**Given** the Settings pump card showing current status
**When** the user enters the pairing flow
**Then** the flow presented is determined by the active Driver, supporting both phone-scans-and-connects and phone-advertises-and-waits shapes (FR-1, FR-2)
**And** all pairing copy, blurbs and code-entry instructions come from the active Driver, not from the platform (FR-2)
**And** the user is warned before pairing that a pump connects to one phone at a time

### Story 1.20: See connection status without opening the app

As a user,
I want to know my pump is connected from the Lock Screen,
So that I do not have to open the app to check.

**Acceptance Criteria:**

**Given** a paired pump
**When** the app is not in the foreground
**Then** connection status is visible on the Lock Screen and in the Dynamic Island while a pairing exists (FR-20)
**And** the surface never claims coverage the phone cannot deliver (SI-6)
**And** this story **defines** the shared snapshot record in `SafetyCore` and writes it: one record, written atomically (write-temp-then-rename), carrying its schema version and the instant it was produced, with the app as the sole writer (AD-2, AD-9)
**And** a reader that cannot parse it, or finds an unknown version, renders *unknown* — never a partial record, because a stale value shown as Fresh is SI-6's worst failure
**And** Epic 3's wrist and widget surfaces consume this record; nothing in this story depends on them existing

---

## Epic 2: Know when I'm low

The app alarms for urgent low, low, high and urgent high from readings on the device alone, and tells the user at all times whether anything is actually watching — with a specific, actionable reason whenever it is not. Delivers the product's irreducible safety net and the honesty contract around it.

**Inherits:** AD-10, AD-11, AD-13, AD-14, AD-21. **Upholds:** SI-5, SI-6.

### Story 2.1: AccessorySetupKit and relaunch-rules spike (SPK-1)

As a maintainer,
I want to know which relaunch rules apply on each supported OS version,
So that the Coverage Claim never assumes a relaunch the OS will not perform.

**Acceptance Criteria:**

**Given** Apple TN3115 states that from iOS 26 only apps using AccessorySetupKit are relaunched after a force-quit or a Control Center Bluetooth toggle
**When** the spike runs on hardware across the supported range
**Then** the effective relaunch behaviour is recorded per OS version, with evidence
**And** the AccessorySetupKit adoption surface and its interaction with the existing pairing flows is determined (AD-21)
**And** the result becomes a runtime input to the Coverage Claim, not a footnote
**And** the PRD is flagged for update, because its research predates this behaviour change

### Story 2.2: The Alert Floor — alarming with no Backend

As a user with no server configured,
I want my phone to alarm for a low from the reading it already has,
So that the app is useful and safe on its own.

**Acceptance Criteria:**

**Given** Backend-optional mode, where Backend alerting is permanently degraded
**When** a fresh Glucose Reading crosses a configured Alert Threshold
**Then** the Alert Floor classifies urgent bands first — value ≤ urgent low → `low_urgent`, ≥ urgent high → `high_urgent`, ≤ low → `low_warning`, ≥ high → `high_warning`, inclusive at both edges (FR-71)
**And** the gate order is fixed and tested: clock rewind, episode re-arm, no classification, Backend-not-degraded, data-trust bound, notification capability (FR-71)
**And** the Alert Floor performs no prediction, no trajectory projection and no IOB escalation, and never produces a caregiver alert (FR-71)
**And** the alert type vocabulary and its delivery tiering are defined once and shared by every surface that raises or renders an alert (FR-65)
**And** no Alert Floor path issues any device command (SI-1)

### Story 2.3: Never alarm from stale data or thresholds nobody set

As a user,
I want the app to stay silent rather than alarm from a reading it cannot trust,
So that I never learn to ignore my alarms.

**Acceptance Criteria:**

**Given** a Glucose Reading whose own sensor timestamp is not Fresh
**When** the Alert Floor evaluates
**Then** it does not alarm, at any value (FR-72, SI-5)
**And** the built-in defaults 55/70/180/250 are **never** used to arm an alarm on any surface; only thresholds the user or their Backend actually set can (FR-73, SI-5)
**And** the monotonic clock high-water mark is process-local, never persisted, resets on a forward correction larger than 60,000 ms, and suppression is hard-bounded at 300,000 ms (FR-72)
**And** clock-distrust suppression reports `CLOCK_UNTRUSTED` — never `NO_FRESH_READING`, because the readings are fine and the clock is not

### Story 2.4: Deliver the alert, and be honest about what can silence it

As a user asleep at 3 a.m.,
I want the alarm to reach me,
So that I wake up.

**Acceptance Criteria:**

**Given** an urgent low
**When** the notification is delivered
**Then** it uses `.timeSensitive`, upgrading to `.critical` automatically if the entitlement is ever present (FR-66, decision 4)
**And** the app sets no volume and never reads or infers the silent-switch position (FR-66)
**And** the product states plainly — in onboarding, in Settings and in the docs — that the ring/silent switch can silence the alarm and the app cannot detect it (FR-66, PL-23)
**And** a foreground app still presents the alert; it never swallows one (FR-68)
**And** the alert body names the value, the unit and that it was computed on-device from the last sensor reading (FR-69)

### Story 2.5: Alert sounds, slots and duplicate suppression

As a user,
I want to tell my alerts apart by ear,
So that I know whether to get up.

**Acceptance Criteria:**

**Given** the bundled sound set
**When** the user chooses a sound per severity tier
**Then** the choice applies to low, high and informational tiers, with "Silent" available for informational (FR-67)
**And** sounds come from a **bundled curated set only** — user-imported audio is deferred, because Android's mechanism is the system ringtone picker, which iOS has no equivalent for (FR-67, PL-24)
**And** notification slot identity prevents the same condition producing two visible alerts (FR-70)

### Story 2.6: Re-alarm, cooldown and episode semantics

As a user who has not treated yet,
I want the alarm to come back,
So that a single missed notification is not the end of it.

**Acceptance Criteria:**

**Given** an unacknowledged urgent alert
**When** the condition persists
**Then** it re-alarms on a bounded, finite ladder that terminates when the reading ages past Too Stale (FR-76)
**And** the same alert type does not re-alarm more than once per 30 minutes while it remains active (FR-74)
**And** an episode already announced by the Backend and acknowledged by the user does not re-alarm on-device (FR-75)

### Story 2.7: Acknowledge, offline and everywhere

As a user,
I want acknowledging once to be enough,
So that my wrist stops buzzing after I dealt with it on my phone.

**Acceptance Criteria:**

**Given** an alert delivered to phone and wrist
**When** the user acknowledges on either surface
**Then** acknowledgement state has exactly one owner — `DomainCore` on the phone — and this story delivers the phone path complete on its own (AD-23)
**And** the intent-handling entry point is defined here so the Watch can call it in Epic 3; the Watch sends an idempotent **intent**, never authoritative state, and nothing in this story requires the Watch to exist
**And** an acknowledgement made offline sticks locally and is reconciled on reconnect (FR-78)
**And** a later Backend delivery of the same alert never reverses it (FR-78)
**And** tapping the notification opens the Alerts screen (FR-77)

### Story 2.8: Alert Thresholds — editable locally, read-only with a Backend

As a user,
I want to set my own thresholds when I have no server, and see my server's when I do,
So that there is never ambiguity about which values are in force.

**Acceptance Criteria:**

**Given** Backend-optional mode
**When** the user edits thresholds
**Then** all four are editable in the chosen unit with dependent validation enforcing 20 ≤ urgent low ≤ low < high ≤ urgent high ≤ 500, rejecting rather than clamping (FR-79)
**And** with a Backend configured they are read-only, with the four current values, their sync age and a pointer to the web app (FR-80)
**And** a Backend response failing validation is discarded **whole**, leaving last-known-good in force (FR-81)
**And** sign-out clears Backend-provenance thresholds and preserves locally set ones (FR-82)

### Story 2.9: The Coverage Claim

As a user,
I want to know whether anything is watching for a low right now,
So that I am never falsely reassured.

**Acceptance Criteria:**

**Given** one pure selector in `SafetyCore` (AD-10)
**When** the claim is computed
**Then** it evaluates in this order: **notification capability first**, then clock trust, then Backend alerting, then thresholds, then accept window, then pump connection, then freshness (FR-83)
**And** "Backend alerting is not degraded" requires **positive evidence of a Backend-side Glucose Reading newer than the Fresh boundary** — a connected stream alone is not evidence, because the app never uploads Glucose Readings (FR-83)
**And** the Not-Watching Reason set is open at eight, and a new failure mode gets a new reason rather than collapsing into a true-sounding wrong one (FR-83)
**And** exactly one pipeline produces the claim for every consumer; forking it per surface fails a test (FR-83)

### Story 2.10: Coverage expiry, decay, and the dead-man's switch

As a user,
I want the app to tell me when it has stopped watching,
So that silence is never mistaken for safety.

**Acceptance Criteria:**

**Given** a coverage claim with an explicit expiry
**When** no new data arrives
**Then** the claim decays on its own schedule and degrades to *not watching* with a reason, rather than going quiet (FR-84, SI-6)
**And** the app proactively notifies the user when coverage has lapsed longer than the window (FR-85)
**And** the user is warned during onboarding and in Settings that force-quitting or restarting the phone stops monitoring (FR-85)
**And** monitoring resumes automatically after a background termination when the pump reconnects (FR-86)

### Story 2.11: Alert history and the notification status card

As a user,
I want to see what fired and why nothing might fire,
So that I can diagnose my own setup.

**Acceptance Criteria:**

**Given** a configured Backend
**When** the Alerts screen opens
**Then** it shows the most recent 100 Backend alerts with pull-to-refresh (FR-87)
**And** history follows the user's retention window, pruned on a schedule rather than only when the screen opens (FR-87)
**And** the notification status card reports **every** condition that would prevent an alert reaching the user (FR-171)
**And** a caregiver data-gap alert never shows a glucose value in its title (FR-69)

### Story 2.12: Developer fault-injection, off in every shipped build

As a maintainer,
I want to force degraded states on demand,
So that I can validate the honesty paths in the Simulator.

**Acceptance Criteria:**

**Given** a local Xcode build with the fault-injection flag enabled
**When** the developer console is used
**Then** it can force Backend-unreachable, compress the Freshness policy, and inject fresh and stale readings (FR-88)
**And** the surface is gated on a **dedicated compile-time flag that is off in every configuration the pipeline produces**, in both channels (AD-17)
**And** a test asserts the Developer section is absent from a pipeline-produced build of either channel

---

## Epic 3: Glance without opening the app

Glucose, trend and coverage reach the wrist, the Lock Screen and the Dynamic Island, decaying honestly on the Watch's own clock and never showing a value the phone could not vouch for.

**Inherits:** AD-2, AD-9, AD-10, AD-18. **Upholds:** SI-4, SI-6.

### Story 3.1: One bundle, one shared safety module, read-only wrist

As a user,
I want the Watch app to arrive with the phone app,
So that there is no second thing to install.

**Acceptance Criteria:**

**Given** a single distributable bundle
**When** the phone app installs or updates
**Then** the Watch app installs or updates with it; there is no second downloadable artifact (FR-115)
**And** the Watch app links the **same** `SafetyCore` module as the phone, so both produce byte-identical glucose strings for the same stored value (FR-116, SI-4)
**And** the Watch hosts no Driver, performs no pairing, and exposes no scanning, code entry or unpairing (FR-115)
**And** the whole wrist surface is demonstrable in the watchOS Simulator paired to the iOS Simulator (FR-116)

### Story 3.2: Complications, widgets, and the absence of a watch face

As a user,
I want glucose on my watch face,
So that I see it by turning my wrist.

**Acceptance Criteria:**

**Given** watchOS supports no third-party watch faces
**When** the complication set ships
**Then** it provides WidgetKit accessory complications the user places on their own face, plus Smart Stack and Lock Screen widgets (FR-117, PA-2, PA-3)
**And** the product states plainly that a custom watch face is not possible on watchOS — the Android watch face has no equivalent (PL-31)
**And** guided in-app setup tells the user exactly which complications exist and where to put them (FR-118, PA-13)
**And** each surface is unambiguous in monochrome and under accented/tinted rendering, never relying on hue alone (FR-117)

### Story 3.3: Glucose and IOB on the wrist, with freshness

As a user glancing down,
I want to know instantly whether the number is current,
So that I never act on a stale reading.

**Acceptance Criteria:**

**Given** a reading relayed from the phone
**When** the wrist renders it
**Then** the value shows plain when Fresh and carries an explicit treatment when Stale or Too Stale (FR-120)
**And** IOB gets the same three-tier treatment (FR-121)
**And** the trend glyph follows FR-46's provenance rule — rendered at the worse of the two tiers, degrading independently of the value
**And** no value outside 20–500 mg/dL is ever shown, at any tier (FR-124)
**And** mmol/L conversion is display-only, dividing once by 18.0156 and rounding last (FR-124, SI-3)
**And** thresholds arriving on the wrist are sanitized in a dependent order guaranteeing 20 ≤ urgent low ≤ low < high ≤ urgent high ≤ 500, discarding the set rather than repairing it (FR-125)

### Story 3.4: Decay on the Watch's own clock

As a user whose phone is in another room,
I want my watch to stop claiming a number is current,
So that distance from my phone does not become a false reassurance.

**Acceptance Criteria:**

**Given** no new data from the phone
**When** time passes on the Watch
**Then** freshness decays on the **Watch's own clock**, without requiring a phone message (FR-122)
**And** decay respects the OS complication refresh budget, read at runtime and never hardcoded (FR-122)
**And** a backward clock jump greater than 60 seconds marks the clock untrusted (FR-123)
**And** coverage does not persist across a Watch app restart — after a restart, coverage is unknown until the phone says otherwise (FR-126)

### Story 3.5: The wrist Coverage Claim — rendered, never derived

As a user,
I want my watch to tell me the truth about whether I am being watched,
So that the wrist is never more confident than the phone.

**Acceptance Criteria:**

**Given** the phone computes the claim (AD-10)
**When** the Watch renders it
**Then** the Watch **renders and decays** the phone's claim and never derives one of its own (FR-126, SI-6)
**And** the envelope carries a schema version **and the Not-Watching Reason vocabulary is versioned with it**; an unrecognised reason renders as its literal identifier plus generic text, never as a different reason (AD-10)
**And** the five wrist reason strings are distinct and actionable (FR-127)
**And** the complication changes to a not-watching state visible on the face itself (FR-117)

### Story 3.6: Wrist alerts, scheduled on the Watch

As a user with my phone unlocked and in my hand,
I want my wrist to buzz for a low,
So that I am not relying on mirroring that will not fire.

**Acceptance Criteria:**

**Given** an alert condition
**When** it is delivered to the wrist
**Then** the notification is **scheduled on the Watch** — iPhone mirroring is the fallback, never the mechanism, because mirroring does not fire when the phone is unlocked and in use (FR-128, AD-12)
**And** a single fresh low produces **one** wrist experience, not several (FR-128)
**And** a sustained alert re-alarms every 30 minutes on a locally scheduled ladder that terminates when the reading ages past Too Stale (FR-129, PA-6)
**And** a live alert refreshes at least every 5 minutes so an ongoing condition does not look resolved (FR-130)
**And** the app never retracts a shown alert on the basis of data it cannot vouch for (FR-130)

### Story 3.7: Dismiss from the wrist

As a user,
I want to dismiss from my watch and have it stick,
So that I do not have to find my phone.

**Acceptance Criteria:**

**Given** an alert on the wrist
**When** the user dismisses from the alert screen or the notification
**Then** the dismissal is acknowledged locally **before** any server call, so it is never lost to a network failure (FR-131)
**And** it is sent to the phone as an intent, per AD-23, and the phone owns the resulting state
**And** turning wrist alerts off states plainly what the user gives up (FR-131)

### Story 3.8: History and the full-screen graph on the wrist

As a user,
I want to see the last few hours on my watch,
So that I can read the trend without my phone.

**Acceptance Criteria:**

**Given** six hours of basal, bolus and IOB history forwarded from the phone
**When** the Watch graph renders
**Then** it supports pan-back-in-time and tap-for-value (FR-132, FR-133)
**And** it uses the **same Y-axis rule as the phone** — default 40–300 mg/dL, expanding to include any out-of-range reading, never pinning (FR-133)
**And** a truncated or malformed history payload renders no overlay rather than a wrong one (FR-132)

### Story 3.9: iPhone Settings → Watch, and the true wrist-link state

As a user,
I want to know whether my watch is actually receiving data,
So that a silent wrist is diagnosable.

**Acceptance Criteria:**

**Given** the Watch section in iPhone Settings
**When** it renders
**Then** it shows whether a Watch is paired, whether the app is installed, and whether it is currently reachable (FR-134)
**And** the user can configure what the Watch surfaces show, with the preference set defined once in FR-134 and mirrored — never restated — by Settings (AD-18)
**And** a build mismatch between phone and Watch is flagged with the remedy (FR-134)
**And** there is **no** watch-face theme control, because complications render in a system-controlled tint the app cannot override

### Story 3.10: Live Activity on the Lock Screen and Dynamic Island

As a user,
I want glucose on my Lock Screen during an active session,
So that I see it without unlocking.

**Acceptance Criteria:**

**Given** an active monitoring session
**When** the Live Activity is presented
**Then** it shows glucose, trend and coverage state with the same freshness treatment as every other surface (FR-119, PA-1)
**And** it is fed by the atomically written snapshot record, with the app as sole writer (AD-9)
**And** an unparseable or unknown-version snapshot renders *unknown* — never a partial record, because a stale value rendered Fresh is SI-6's worst failure
**And** it never presents a value older than its Freshness Tier permits

---

## Epic 4: Understand my patterns

Charts, Time in Range, CGM statistics, insulin summary and bolus history let a user work out what happened — from data already on the device, with no export and no upload.

**Inherits:** AD-5, AD-13, AD-14. **Upholds:** SI-3, SI-7.

### Story 4.1: The trend chart

As a user,
I want to see my glucose over time,
So that I can read the shape rather than a single number.

**Acceptance Criteria:**

**Given** readings in the selected period
**When** the chart renders
**Then** the Y axis **defaults to 40–300 mg/dL and expands** to include any out-of-range reading — a reading is never pinned to a boundary, which would draw a valid value at a false position (FR-52)
**And** draw order is target band, threshold grid lines, Y-axis labels, X-axis labels, then series (FR-53)
**And** grid lines and labels sit at the **Target Range** values, not Alert Thresholds (FR-53)
**And** the legend lists only series actually present in the loaded data (FR-53)
**And** time-axis label format and tick count follow the visible span (FR-54)

### Story 4.2: Chart detail — zoom, landscape, and shared period state

As a user,
I want to open the chart and explore it,
So that I can look closely at a specific window.

**Acceptance Criteria:**

**Given** the Home chart card
**When** the user taps it
**Then** a detail view opens supporting pinch-zoom (FR-55)
**And** it presents in landscape and restores the previous orientation posture on exit (FR-56)
**And** period selection is shared between the Home card and the detail view (FR-57)
**And** the dashboard maintains five independent period selections — chart, Time in Range, CGM stats, insulin summary, bolus history — each filtered by the retention setting, with an out-of-range selection corrected rather than left dangling (FR-57)

### Story 4.3: Time in Range and CGM statistics

As a user,
I want the numbers I take to my care team,
So that I can have a useful conversation about my control.

**Acceptance Criteria:**

**Given** readings in the selected period
**When** Time in Range is computed
**Then** it buckets on the **Target Range**, not Alert Thresholds — a test configures the two sets differently and asserts TIR follows the Target Range (FR-58)
**And** it aggregates over readings between 20 and 500 mg/dL in the database (FR-58)
**And** CGM statistics report mean, sample standard deviation using the n−1 denominator, CV%, GMI and CGM-active percentage (FR-59)
**And** every number uses a dot decimal separator and half-up rounding regardless of locale (FR-60)

### Story 4.4: Insulin summary and delivered-insulin honesty

As a user,
I want to see how much insulin I actually received,
So that I am not misled about what is on board.

**Acceptance Criteria:**

**Given** insulin events from the pump
**When** the insulin summary renders
**Then** it reports total daily dose, the basal/bolus split as a stacked bar with legend, and the food/correction breakdown (FR-89)
**And** only **completed** deliveries count — started, cancelled and in-progress boluses are excluded, and SmartGuard auto-basal micro-boluses stay out of bolus totals (FR-90, SI-7)
**And** a bolus's requested meal and correction portions are **never** laid out as though they sum to what was delivered; no layout reads as an equation (FR-90)
**And** the Backend-supplied bolus-category label map is used when present, falls back to the app's own vocabulary when absent, and is cleared on sign-out (FR-89)

### Story 4.5: Recent boluses and event cross-referencing

As a user,
I want to see what my glucose was when I bolused,
So that I can work out what a correction actually did.

**Acceptance Criteria:**

**Given** recorded bolus events
**When** Recent Boluses renders
**Then** it shows the five most recent in descending time order with time, units and a type badge (FR-91)
**And** glucose-at-event and IOB-at-event are cross-referenced to the nearest reading within ± 5 minutes, and are absent rather than approximated when none exists (FR-92)
**And** a bolus outside 0–25 units is rejected, never clamped (FR-92, SI-2)

---

## Epic 5: Run it against my own server

A user connects the app to their own self-hosted Backend and gains sync, Nightscout-sourced data, meal carb estimation and AI chat — while the app stays fully functional without one.

**Inherits:** AD-7, AD-9, AD-13, AD-15. **Upholds:** SI-11, SI-12.

### Story 5.1: Configure a Backend, safely

As a user with a self-hosted server,
I want to point the app at it and know the connection is sound,
So that I am not guessing why sync is not working.

**Acceptance Criteria:**

**Given** the Backend setup stage
**When** the user enters a URL and tests it
**Then** success and failure are reported distinctly, and a URL carrying a path, query or fragment is rejected at save time with a specific message (FR-161)
**And** if iOS blocks a local-network host, the app says exactly that and links to Settings, rather than reporting a generic Backend fault (FR-162)
**And** plaintext HTTP is refused for any host that is not a literal loopback, private, carrier-NAT or link-local address or a `.local` name, classified by literal address parsing and **never** by DNS (FR-150, AD-15)
**And** insecure LAN HTTP requires an explicit per-device opt-in, and while in use a persistent banner appears above every screen (FR-163)
**And** the ATS plist configuration is treated as architecture-to-verify; no code or copy asserts a posture before a device-verified baseline exists (AD-15)
**And** Local Network access is requested when reaching a LAN host, and a denial is surfaced as its own state with recovery copy — never as a generic unreachable Backend (FR-151)

### Story 5.2: Stay signed in, and sign out cleanly

As a user,
I want to stay signed in across restarts,
So that I do not re-authenticate to see my own data.

**Acceptance Criteria:**

**Given** a valid session
**When** the access token nears expiry
**Then** it refreshes proactively; a 401 triggers exactly one serialized refresh-and-retry shared across all concurrent requests (FR-147, FR-148)
**And** sign-out always wins over an in-flight refresh; a refresh completing after sign-out is discarded (FR-148)
**And** a session expiring while offline shows "sign in again" without erasing local data (FR-149)
**And** credentials live in the Keychain, device-only and after-first-unlock (SI-10)
**And** sign-out clears Backend-provenance thresholds and the bolus-label map, and preserves the queue and the Backend URL (FR-167)

### Story 5.3: Upload durably, and never lose an event

As a user,
I want my pump data to reach my server even over a bad connection,
So that gaps are the network's fault and not the app's.

**Acceptance Criteria:**

**Given** an uploadable pump event
**When** it is produced
**Then** the local write happens first and unconditionally; enqueueing is a separate second step whose failure never blocks the local write (FR-140)
**And** an upload begun in the foreground completes after backgrounding, via a batch serialized to a file first (FR-140)
**And** transport failures and HTTP 408, 429, 502, 503 and 504 never discard an event (FR-141)
**And** the outbound queue is bounded at 20,000 rows, evicting oldest-first, sized so a full day without a successful upload discards nothing (FR-142)
**And** the user can see how many events are waiting and when the last successful upload happened (FR-142)
**And** Glucose Readings are never enqueued — the wire quirks are preserved exactly (FR-140)
**And** the app registers itself with the Backend as an iOS device under a stable per-installation identifier (FR-156)

### Story 5.4: Backend-optional transitions

As a user,
I want to add or remove my server without losing anything,
So that trying a Backend is not a one-way door.

**Acceptance Criteria:**

**Given** a configured Backend
**When** the user removes the server URL
**Then** a fully functional local-only monitor remains; no undelivered rows are dropped (FR-143)
**And** adding a URL resumes syncing without an app restart (FR-143)
**And** in Backend-optional mode the app makes **no** network request to any host carrying or receiving health data; the user-toggleable, default-off upstream release check is the single named exception (FR-143, NFR-23)
**And** three connectivity states are reported distinctly — device offline, Backend unreachable, reachable (FR-152)
**And** the Backend alert transport is SSE while the process is alive, with the APNs device-token path reserved but unwired for v1 (FR-157, decision 7)
**And** a user-initiated diagnostic log export is available, scrubbed of tokens, addresses and health values, and states its own gaps (FR-158, SI-9)

### Story 5.5: Tolerant reading and the Contract Pin

As a maintainer,
I want an older client to survive a newer server, and a broken contract to fail loudly,
So that a silent mismatch never corrupts what the user sees.

**Acceptance Criteria:**

**Given** exactly one shared `JSONDecoder` configuration (AD-7)
**When** a Backend response is decoded
**Then** unknown fields — including unknown nested objects — are ignored, and a **missing consumed field throws** (FR-155, SI-12)
**And** no Backend-supplied enumerated value is a strict enum; unrecognised members decode to an explicit unknown case (FR-155)
**And** synthesized `Codable` is prohibited on Backend DTOs, because its default behaviour is the inverse of this rule (AD-7)
**And** a response carrying Alert Thresholds, a target range or Safety Limits that fails validation is dropped whole, leaving last-known-good in force (FR-155, SI-11)
**And** Safety Limits are additionally rejected when narrower than 100 mg/dL or when they exclude any configured Alert Threshold (SI-11)

### Story 5.6: Opportunity-driven background work and the initial history download

As a user,
I want the app to catch up whenever it gets the chance,
So that a period offline does not leave a permanent hole.

**Acceptance Criteria:**

**Given** any opportunity to run
**When** the app wakes
**Then** it attempts queue drain, retention, threshold refresh and cloud-source sync (FR-144)
**And** the initial multi-month history download is user-visible, cancellable and resumable (FR-146)
**And** capture-time freshness and detected collection gaps are recorded rather than smoothed over (FR-145)
**And** the app never claims background coverage it cannot deliver (SI-6)

### Story 5.7: The Backend-mediated Nightscout source

As a user with Nightscout data on my server,
I want it in the app alongside my pump data,
So that I have one view.

**Acceptance Criteria:**

**Given** the Nightscout source is off by default
**When** the user enables it
**Then** the app reads Nightscout-sourced data **from the Backend** — it holds no Nightscout URL and no API secret anywhere (FR-153)
**And** disabling it retains already-synced data (FR-153)
**And** the last successful sync time is shown, with a distinct state for each outcome, and an on-demand sync is available (FR-153)
**And** the cursor is persisted and a background run aborts cleanly rather than losing its place (FR-154, AD-19)
**And** records colliding on the same timestamp with a pump source collapse deterministically (FR-137)

### Story 5.8: AI Chat

As a user with a question about my own data at 11 p.m.,
I want to ask it,
So that I get a read without waiting for an appointment.

**Acceptance Criteria:**

**Given** a Backend base URL is configured
**When** the AI Chat tab is opened
**Then** the tab exists **only** when a Backend is configured, and the provider is probed exactly once, landing in one of three states (FR-105, FR-106)
**And** a message of up to 2000 characters inclusive can be sent; longer is refused (FR-107)
**And** the transcript is in-memory only, capped at 100 messages, and lost on relaunch — and the app does not pretend otherwise (FR-108)
**And** every failure class shows curated copy, never a raw error (FR-109)
**And** an interrupted request is disclosed honestly rather than dropped silently (FR-110)
**And** assistant markdown is sanitized — image markdown and HTML image tags stripped — before rendering (FR-112)
**And** four starter suggestions appear when the transcript is empty, and no answer is ever a dose (FR-111)

### Story 5.9: Spoken responses and AI Chat on the wrist

As a user with my hands busy,
I want to ask and hear an answer,
So that I do not have to read.

**Acceptance Criteria:**

**Given** spoken responses are enabled
**When** an answer arrives
**Then** speech **ducks** other audio rather than interrupting it, and stops when the user turns speech off (FR-113)
**And** the user can choose a voice (FR-113)
**And** from the Watch the user can ask by dictation, scribble, keyboard or three one-tap prompts (FR-114)
**And** with no Backend the Watch returns the terminal message rather than a loading state (FR-114)
**And** one shared request timeout applies to the Watch and the Backend call, so a late answer cannot outlive its own deadline (FR-114)

### Story 5.10: Log a meal by photo

As a user,
I want to photograph my plate and get a carb estimate,
So that I have a starting point rather than a guess.

**Acceptance Criteria:**

**Given** a Backend with meal intelligence enabled
**When** the user captures or selects a photo
**Then** it is downscaled to a 1280px longest edge, oriented upright and re-encoded as JPEG (FR-94)
**And** temporary capture files are deleted after upload, on cancellation, and when superseded (FR-94)
**And** the "Estimating carbs…" indicator can never stick — every failure path clears it (FR-95)
**And** meal logging is unavailable, not degraded, when the Backend is unreachable, and says so (FR-93)

### Story 5.11: Carb estimates that never read as a dose

As a user,
I want the uncertainty attached to the number,
So that I never mistake an AI guess for a prescription.

**Acceptance Criteria:**

**Given** a returned estimate
**When** it is displayed on any surface
**Then** "Rough estimate — an AI guess. Never dose from this." appears on the **same screen** as the number, every time (FR-96)
**And** carbs are always a low-to-high range with a confidence signal, never a bare number (FR-97)
**And** confidence is conveyed by bar length as well as colour, and medium and low remain distinguishable without hue (FR-97)
**And** VoiceOver announces the value, the confidence, the never-dose qualifier and any uncertainty (FR-97)
**And** multi-read disagreement or uncertain food identity is disclosed rather than averaged away (FR-98)

### Story 5.12: Correct, explain and reuse a meal

As a user,
I want to fix a wrong estimate and save what I eat often,
So that the app gets more useful rather than more wrong.

**Acceptance Criteria:**

**Given** a carb estimate on screen
**When** the user corrects the range
**Then** out-of-bounds values are **rejected, never silently clamped** (FR-100, SI-2)
**And** confirming or correcting the food identity is a separate action from correcting the range (FR-99)
**And** "How was this estimated?" shows how many times the photo was read and what was seen (FR-101)
**And** Backend-authored nutrition text renders verbatim in the server's own words (FR-102)
**And** a meal can be saved as a named common food, re-logged read-only, and deleted with immediate effect (FR-103, FR-104)

---

## Epic 6: Make it mine, and make it usable by everyone

Settings, appearance, units, retention, per-severity sounds, the Watch section — and the accessibility contract that is also the acceptance substrate for every Simulator-runnable gate.

**Inherits:** AD-13, AD-18. **Upholds:** SI-3.

### Story 6.1: Settings composition and mode-dependent visibility

As a user,
I want Settings to show only what applies to my setup,
So that I am not offered controls that cannot do anything.

**Acceptance Criteria:**

**Given** the app's current mode
**When** Settings renders
**Then** sections appear in a fixed order — Account, Network, Drivers, Sync, Meal Intelligence, Notifications, Watch, Appearance, Units, Retention, Licenses, About (FR-166)
**And** in Backend-optional mode the Backend sync control, meal intelligence and account sections are hidden entirely (FR-166)
**And** the Developer section appears only in a build with the fault-injection flag set (FR-176, AD-17)
**And** a tappable session banner appears for an expired session (FR-166)
**And** Settings is where the threshold controls live: read-only whenever a Backend supplies them (FR-168), editable with dependent validation in Backend-optional mode (FR-169), and the per-severity sound picker (FR-170) — each deferring to Epic 2 for alerting semantics
**And** the Watch section shows pairing state, what the wrist surfaces display, and the true link state (FR-172), mirroring FR-134 rather than restating it

### Story 6.2: Appearance, units, retention and meal intelligence

As a user,
I want the app to match how I read numbers,
So that I am not converting in my head.

**Acceptance Criteria:**

**Given** the Appearance and Units controls
**When** the user changes a setting
**Then** System / Dark / Light applies live without restart, per device (FR-62, FR-175)
**And** switching between mg/dL and mmol/L re-renders every displayed value immediately, while storage, transport, thresholds and alerting stay mg/dL (FR-175, SI-3)
**And** when the unit was picked automatically from region or a data source, the app says so once (FR-175)
**And** retention is settable between 1 and 30 days, defaulting to 7 (FR-175)

### Story 6.3: About, versions and the offline license viewer

As a user,
I want to know exactly what I am running,
So that I can report a problem accurately.

**Acceptance Criteria:**

**Given** the About section
**When** it renders
**Then** it shows the app and Watch versions, flags a mismatch with the remedy, and shows the source commit, build date and days until expiry (FR-173)
**And** the license viewer opens with no connectivity, with distinct Loading, Loaded and Error states (FR-174)
**And** license text is selectable and rendered as plain text, never markdown (FR-174)

### Story 6.4: Accessibility identifier parity

As a maintainer with no iPhone,
I want every element to carry a stable identifier,
So that the Simulator tier can actually verify the app.

**Acceptance Criteria:**

**Given** the Android client's `testTag` set
**When** the iOS surfaces are built
**Then** every element carrying a `testTag` in the Android phone and Wear main source sets has a **byte-identical** accessibility identifier on the corresponding iOS or watchOS surface (FR-177, NFR-30)
**And** the parity target is a **generated registry diffed by CI** — not a pinned count, because a count was never verifiable and drifts with every Android change (NFR-30)
**And** the registry is committed and its diff is the gate
**And** identifiers appear on states, not only on containers (FR-177)

### Story 6.5: VoiceOver, non-colour encoding and Dynamic Type

As a user who relies on VoiceOver or larger text,
I want the app to work for me,
So that a glucose monitor is not sighted-only.

**Acceptance Criteria:**

**Given** any card carrying meaning
**When** VoiceOver reads it
**Then** it exposes a single combined description matching the Android content description (FR-178)
**And** everywhere colour carries meaning, a non-colour encoding carries it too — including in monochrome and tinted complication rendering (FR-178)
**And** hero numerals remain legible and non-truncating across Dynamic Type sizes (FR-64, FR-178)

---

## Epic 7: Support my Medtronic pump

A Medtronic MiniMed 680G/770G/780G user pairs by making the phone discoverable to the pump and sees the same monitoring surfaces as a Tandem user. Ships gated at Beta with its transport assumption named.

**Inherits:** AD-16, AD-19, AD-22. **Upholds:** SI-2, SI-7, SI-8.

### Story 7.1: Medtronic transport spike, part (a) — no pump required (SPK-3)

As a maintainer,
I want to know whether iOS can support the Medtronic pairing shape at all,
So that we do not build a driver on an assumption that turns out false.

**Acceptance Criteria:**

**Given** two iOS devices, or a Mac acting as peripheral
**When** the spike runs
**Then** it establishes whether Core Bluetooth can return a `CBPeripheral` for a central that connected to our `CBPeripheralManager`
**And** the result is recorded with evidence, because a negative answer invalidates the Medtronic driver architecture before it is built
**And** part (b) — whether a 780G's discovery filter accepts an iOS advertisement — is left explicitly open, needing hardware nobody on the team has
**And** if part (a) fails, Epic 7 is cut with evidence rather than unpicked later

### Story 7.2: Advertise-and-wait pairing

As a Medtronic user,
I want to pair by selecting my phone from the pump's own menu,
So that I can connect the way my pump expects.

**Acceptance Criteria:**

**Given** the Medtronic Driver is active
**When** the user opens the pairing screen
**Then** the app advertises and waits, telling the user the app must stay open and in the foreground for pairing (FR-16)
**And** the screen states, before the user starts, that the pump must first be removed from MiniMed Mobile
**And** each distinct pairing failure has its own message and a Try Again action
**And** a terminal handshake rejection latches: advertising stops, no auto-reconnect, and the user is told what to do

### Story 7.3: Medtronic decode gates and history

As a user,
I want the app to discard readings my pump marked invalid,
So that a sensor warm-up value is never shown as real glucose.

**Acceptance Criteria:**

**Given** decoded Medtronic frames
**When** values are extracted
**Then** `SG_SENTINELS` `{0x0301, 0x0303, 0x030D}` are dropped in the history path, and IEEE-11073 reserved codes are rejected via `isFinite()` in the live path — including on insulin totals and basal rates (AD-22)
**And** the annunciation byte remains a named TODO, as it is in the Android source — named, not silently omitted
**And** history timestamps resolve relative offsets against the naive local wall-clock reference record, verified by a test under a non-UTC timezone (AD-22)
**And** the E2E-CRC requirement is read from the per-pump feature bit, never hardcoded to a model
**And** SmartGuard auto-basal micro-boluses stay excluded from bolus totals (SI-7)

### Story 7.4: Ship Medtronic gated at Beta

As a user,
I want to know exactly how much this driver has been proven,
So that I can decide whether to rely on it.

**Acceptance Criteria:**

**Given** no team member owns a Medtronic pump
**When** the driver ships
**Then** it is present but gated, labelled **Beta** with its unproven transport assumption named, matching Android's own posture
**And** the device matrix records that no status may be raised except by evidence recorded in the table
**And** the in-app gate carries a warning before activation
**And** a community validator with hardware can close part (b) and raise the status

---

## Epic 8: Build it, install it, and keep it working

A Builder forks the repository, adds their own Apple credentials, and produces a signed build on their own iPhone through their own TestFlight — then keeps it alive past the 90-day expiry. Includes the gates that make the pipeline trustworthy and the documentation that makes it followable.

**Inherits:** AD-3, AD-12, AD-17. **Upholds:** SI-1, SI-4, SI-9, SI-12.

### Story 8.1: Fork, add six secrets, and get a signed build

As a Builder who has never opened App Store Connect,
I want to follow one page and end up with the app on my phone,
So that I can actually use this.

**Acceptance Criteria:**

**Given** a fork of the repository
**When** the Builder adds the documented secret set — `TEAMID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, `GH_PAT` — and runs the build workflow
**Then** a signed build reaches their own TestFlight, with **no project-held signing material at any point** (FR-179, FR-183)
**And** `GH_PAT` carries the `workflow` scope, without which the scheduled rebuild cannot fire (FR-180)
**And** signing material is managed by `fastlane match` against a private `Match-Secrets` repository in the Builder's own account (FR-180)
**And** credentials can be validated in isolation without exposing any secret value (FR-180)
**And** the build hard-fails — never warns — if the archive is not signed by an Apple Distribution certificate (FR-184)
**And** any credential materialized during a run is created with restrictive permissions and destroyed with the run (FR-185)
**And** the pipeline is a **supported product surface** — CODEOWNERS-gated, SHA-pinned, inside the security-response scope — while key custody, Apple account state, certificate lifecycle and the 90-day rebuild remain the Builder's (FR-196, decision 6)

### Story 8.2: Register identifiers once, and choose a channel

As a Builder,
I want my identifiers set up once,
So that subsequent builds just work.

**Acceptance Criteria:**

**Given** a one-time registration workflow
**When** it runs
**Then** it registers one App ID set — app, Watch app and every extension — with exactly the capabilities used (FR-182)
**And** bundle identifiers, App Group containers and Keychain access groups derive from the Builder's Team ID, because App IDs are globally unique across all Apple accounts (FR-181)
**And** the channel is a build-time branch choice — `develop` for a development build, `main` for production — and a new build **replaces** the installed one rather than sitting beside it (FR-182)
**And** side-by-side installation is documented as an advanced path requiring a second identifier set, not the default

### Story 8.3: Never let an installed build lapse

As a Builder,
I want my app to keep working,
So that my glucose monitor does not silently die at 90 days.

**Acceptance Criteria:**

**Given** Apple expires TestFlight builds after 90 days
**When** the scheduled rebuild workflow runs
**Then** it performs a **weekly change-triggered build plus a monthly unconditional build**, so a quiet upstream cannot let a build lapse (FR-186)
**And** the workflow ships enabled by default in every fork (FR-186)
**And** the app shows its build date, source commit, channel and days until expiry (FR-187)
**And** the documentation names the monthly unconditional build as the thing not to disable
**And** the app can report that a newer upstream release exists and deep-link to it, off by default and user-toggleable (FR-188)

### Story 8.4: Promotion, versioning and pinned inputs

As a maintainer,
I want one promotion to produce a version, a changelog and a sync-back,
So that releases are not hand-assembled.

**Acceptance Criteria:**

**Given** a `develop` → `main` promotion
**When** it merges
**Then** it fans out to a version bump, a changelog and a sync-back to `develop` (FR-192)
**And** there is exactly one version source of truth, bumped from conventional commits (FR-190)
**And** every uploaded build carries a build number strictly greater than any previous (FR-191)
**And** every direct and transitive Swift package is pinned to an exact version and revision, with resolution drift a hard failure (FR-193)
**And** bot dependency PRs regenerate lockfiles automatically and cannot auto-merge outside their scope (FR-194)
**And** a fork can pull upstream and rebuild without manual merge work (FR-195)

### Story 8.5: The five Required Checks

As a maintainer,
I want a fixed, named gate roster,
So that branch protection has stable strings to key on.

**Acceptance Criteria:**

**Given** branch protection on `develop`
**When** the roster is defined
**Then** it is exactly five named checks, and every other job is explicitly non-required (FR-197)
**And** each either runs unconditionally or reports through an always-running aggregation gate that fails closed (FR-198)
**And** every check passes on a fork pull request with a read-only token and no privileged context (FR-199)
**And** the documented roster is verified against the actual branch-protection configuration (FR-197)
**And** every gate is reproducible locally from one committed script (FR-213)

### Story 8.6: Swift static analysis that actually analyses Swift

As a maintainer,
I want a security gate that finds real defects,
So that a green check means something.

**Acceptance Criteria:**

**Given** Semgrep's `p/kotlin` and `p/java` packs produce **zero** findings on Swift
**When** the static analysis gate runs
**Then** it uses CodeQL `swift` with `security-extended`, pinned to an exact query-pack version (FR-200)
**And** it **fails closed** if the scanner errors, and **fails if it reports zero analyzed files** — a name-only port of the Android gate would be permanently green and test nothing (FR-200)
**And** dependency vulnerability scanning runs over the committed resolved graph, with suppressions in one reviewed file each carrying a written reason (FR-201)
**And** workflow lint enforces SHA-pinning and the composite-action secrets guard, and workflow security fails at medium-or-higher (FR-202, FR-203)

### Story 8.7: Guards that keep the invariants true

As a maintainer,
I want the safety invariants enforced mechanically,
So that they survive contributors who have not read the PRD.

**Acceptance Criteria:**

**Given** the guard suite
**When** a pull request runs
**Then** the Entitlements and Plist Guard fails any ATS broadening beyond the recorded baseline, any committed signing material, any credential stored outside the Keychain, and any Run Script or SPM plugin introduction (FR-204)
**And** the Safety Constant drift guard asserts exactly one definition of each constant and fails any reintroduced literal (FR-217, SI-4)
**And** the Driver protocol public interface is snapshotted and diffed (FR-205)
**And** per-Driver protocol tests run over recorded frames (FR-206)
**And** the app is buildable and fully exercisable against the Simulated Driver (FR-207)
**And** the Contract Pin guards check version agreement, endpoint presence, safety-critical field presence, one shared decoder, and tolerant reading in both directions (FR-214, FR-215, FR-216)
**And** project-lead review is required on workflows, signing configuration, the security allowlist and the safety-constant guard (FR-212)

### Story 8.8: Build, test and UI-test every target

As a maintainer,
I want every target built and tested on every change,
So that a break is caught before a Builder finds it.

**Acceptance Criteria:**

**Given** the `iOS Gate`
**When** it runs
**Then** it builds and unit-tests the phone app, the Watch app and the widget extension (FR-208)
**And** it builds a configuration with **every Driver enabled**, so compile-time-excluded code stays compiled and covered (AD-17)
**And** UI tests run on both iOS and watchOS Simulator destinations with the result bundle published, as a non-required job (FR-209)
**And** platform-independent driver, domain and unit-conversion code is testable via `swift test` without Xcode or a Simulator (FR-210)
**And** what ships in each configuration is a build-time composition, subtractive only — a configuration may remove a Driver or a diagnostic surface, never add a capability (FR-189, AD-17)

### Story 8.9: Licensing, attribution and the SPDX contract

As a maintainer of a GPL-3.0-only project,
I want licensing enforced by the build,
So that compliance is not a memory exercise.

**Acceptance Criteria:**

**Given** the resolved dependency graph
**When** license assets are generated on every build
**Then** the build **fails — not warns —** on an empty component list, a missing SPDX identifier, or a license not on the checked-in allowlist (FR-228, FR-229)
**And** per-package exceptions are pinned to exact versions with written reasons (FR-229)
**And** a drift test asserts byte-for-byte equality between each shipped asset and its on-disk source (FR-230)
**And** every in-scope Swift, shell and workflow file carries the `GPL-3.0-only` SPDX header, with never-stamp trees named (FR-231)
**And** AI-attribution and sign-off enforcement blocks a PR carrying attribution in trailers, added lines or the description (FR-218)
**And** the License Header Gate and the dependency license allowlist both fail the build rather than warning (FR-211)
**And** the in-app license viewer reads generated assets, renders them as plain text, and works with no connectivity (FR-227)

### Story 8.10: The install runbook and the published docs set

As a Builder,
I want documentation written for someone in my position,
So that I can get from a fork to a working app.

**Acceptance Criteria:**

**Given** `docs/` is empty today and every page is authored fresh
**When** the documentation set ships
**Then** it carries index, install, daily-use, apple-watch, troubleshooting, reference, concepts and dev sections, each with its `_meta.json` (FR-219, FR-220)
**And** the install runbook takes a Builder from a fresh fork to a working app, states the 90-day expiry in the body, and names the macOS runner-minutes cost as a prerequisite (FR-223)
**And** it is validated end to end by someone who did not write it, from a clean GitHub account and a clean Apple Developer account, before the repository is announced (FR-223)
**And** pages are written for a reader on the website, not a reader browsing GitHub; every link leaving `docs/` is absolute (FR-219, FR-220)
**And** CI fails a docs PR on missing frontmatter, a page absent from its `pages` array, a `pages` entry with no file, or a dead link (FR-219)
**And** a push to `main` touching `docs/**` dispatches the rebuild event (FR-222)
**And** the Apple Watch setup page states that the Watch app installs automatically with the phone app and how to place complications (FR-224)
**And** the documentation states that this repository is **public**, so "not rendered on the website" never means "not visible" — genuinely internal material does not belong here at all (FR-221)

### Story 8.11: The disclosure surfaces that forced losses depend on

As a user hitting a problem iOS caused,
I want a page that explains it,
So that I am not left thinking my equipment is broken.

**Acceptance Criteria:**

**Given** five forced parity losses name a published page as their only disclosure surface
**When** those pages ship
**Then** the pairing-troubleshooting page, the iOS status-icons page and the iOS security-testing page all exist and render (FR-237)
**And** the troubleshooting page states that iOS exposes no API to clear a Bluetooth bond, and walks through the forget-and-re-pair procedure with wording matching the in-app wall (FR-237, PL-1)
**And** it states the stale-service-cache symptom, the unstable pairing identity after reinstall, and the reliability conditions a user can actually control (FR-237, PL-2, PL-8, PL-52)
**And** the security-testing page states that Semgrep's Kotlin and Java packs find nothing in Swift, that Xcode has no wrapper-checksum equivalent, and that artifact-level scanning is unreachable upstream (FR-237, PL-57, PL-64, PL-66)
**And** the medical disclaimer enumerates every iOS-specific condition under which alert delivery can fail (FR-234)
**And** **no** surface anywhere claims alerts are guaranteed, undismissable, or able to override the silent switch (FR-235)

### Story 8.12: Policy, privacy and the contributor path

As a prospective contributor,
I want to know how to contribute a Driver and how to report a vulnerability,
So that I can participate without guessing.

**Acceptance Criteria:**

**Given** the contributor documentation
**When** it ships
**Then** the Driver contribution guide describes one SwiftPM target, explicit Driver Catalog registration, and the read-only Capability set of **six** — with no calibration member (FR-225)
**And** it states that runtime plugin loading is not possible on iOS, with the trade-off named
**And** the security policy has two private channels and no public issue path, and **pre-declines in writing** any report proposing that the absent therapeutic-write surface be added (FR-226)
**And** the privacy document enumerates every outbound connection by name and states the crash-reporting posture: no pipeline-produced build carries a telemetry credential (FR-236)
**And** the acknowledgments page states, per upstream project, whether code was studied or ported — Tandem studied, Medtronic ported under explicit permission (FR-232)
**And** a repo-internal, unpublished provenance record maps each Swift module to its Android origin (FR-233)

---

## Validation Record

Run at Step 4. Every check below was executed; findings were fixed in place rather than waived.

### 1. Requirements coverage — PASS

- **237 / 237 FRs** appear in the FR Coverage Map **and** are cited in at least one story's acceptance criteria. Verified mechanically, not by inspection.
- A gap was found and closed here: 27 FRs were mapped to an epic but cited in no story body. They would have passed a coverage-map check while having no implementation home. Most were covered but uncited; two were genuinely thin — **FR-33** (no active Driver must be a *distinguishable error*, never an empty result reading as "no data") and **FR-157** (SSE-while-alive with the APNs token path reserved) — and now carry their own criteria.
- **34 NFRs**, **23 ADs** and **12 SIs** are carried in the Requirements Inventory and referenced from the stories they bind.

### 2. Architecture implementation — PASS, with one fix

- **No starter template exists.** The spine specifies a greenfield SPM package, so the "Epic 1 Story 1 sets up the starter" rule does not apply. Story 1.1 is instead the EC-JPAKE vector spike, which is the true blocking prerequisite.
- **Fixed:** the SPM package skeleton had no explicit home — Story 1.2 presupposed it. Story 1.2 now establishes the package and its AD-2 / AD-3 topology as its opening condition.
- **Entity creation is incremental.** Story 1.6 creates **only** the tables Epic 1 needs; alert history arrives with Epic 2, the outbound queue and meals with Epic 5.

### 3. Story quality — PASS, with three fixes

- 80 stories, each sized for a single dev session, each citing the FRs it implements and the invariants it upholds.
- **Fixed — forward dependency, Story 1.20 → Epic 3:** the Lock Screen surface consumed "the same snapshot record the widgets read", but widgets ship in Epic 3. Story 1.20 now **defines** the snapshot record and its atomic write; Epic 3 consumes it.
- **Fixed — forward dependency, Story 2.7 → Epic 3:** acknowledgement required the Watch to exist. The phone path is now complete on its own, with the intent entry point defined for Epic 3 to call.
- **Accepted — Story 8.5 → 8.6 / 8.7:** the Required Check roster names five checks whose contents later stories fill. This is a naming contract, not a functional dependency: 8.5 is completable and its gate is meaningful with the checks stubbed. Branch protection keys on the names, so fixing them first is correct.

### 4. Epic structure — PASS

- Every epic is framed by what a user can do afterwards, not by a technical layer. No "set up the database" or "build the API" epic exists.
- **File churn assessed.** Settings surfaces are touched by Epics 1, 2, 5 and 6, and the dashboard by 1 and 4. Examined and **consolidation deliberately rejected**: these are distinct sections and cards rather than one file end-to-end, and a settings-only epic would carry no user value until the features it configures exist. The split follows the feature, not the file.
- **Epic 1 is deliberately front-loaded** at 20 stories. Anything smaller is not a product — a foundation epic with no visible glucose cannot be validated. A natural split at Story 1.7 ("see a number from the Simulated Driver" / "see a number from a real Tandem") remains available if earlier delivery is wanted.

### 5. Dependency flow — PASS

- **Epic independence:** 2 builds on 1; 3 builds on 1 and 2; 4 on 1; 5 on 1; 6 on 1; 7 on 1 and 2; 8 stands alone. No epic requires a *later* epic to function.
- **Within-epic:** each story is completable using only earlier stories in its epic, after the two fixes above.
- **Sequencing note that is not a defect but matters:** Epic 8 is independently valuable and correctly numbered last, but the lead developer has no iPhone — so **no hardware validation of any epic can happen until Epic 8 exists.** Recommend pulling Epic 8 earlier in the schedule than its number implies.

### 6. Known open items carried into development

- **SPK-1** (Story 2.1) AccessorySetupKit and relaunch rules — device-verified; the Coverage Claim's OS-dependence rests on it.
- **SPK-2** (Story 1.1) EC-JPAKE known-answer vectors — blocks all Tandem pairing work.
- **SPK-3** (Story 7.1) Medtronic transport part (a) — answerable without a pump; a negative answer cuts Epic 7 rather than unpicking it later.
- **OQ-45** ATS `Info.plist` configuration — assigned to architecture, device-verified before binding.
- **No UX design contract.** Deliberate (see Requirements Inventory). First-run onboarding is the thinnest area; Story 1.17 flags what it had to infer.
