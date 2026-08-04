# ArkScale Interface System

Last updated: 2026-08-05

## Intent

- **Human:** a technically capable owner running a self-deployed HarmonyOS VPN client.
- **Primary task:** understand connection state immediately, then connect, sign in, or disconnect with one clear action.
- **Feel:** calm and precise like a network instrument, without turning the main screen into a terminal.

## Product World

- **Domain:** encrypted tunnel, tailnet node, direct/DERP path, network roaming, protected identity, peer probe.
- **Color world:** abyss navy, tunnel cyan, signal green, graphite, mist white, alert coral.
- **Signature:** the three-stage tunnel rail—device, tunnel, tailnet—changes tone with connection progress.
- **Rejected defaults:** card grid → single connection focal point; permanent debug console → collapsed diagnostics; bottom navigation → one task-focused page.

## Direction

Connection state leads. Connection facts support it. Diagnostics remain available but collapsed. Identity deletion is visually and spatially separated. Do not display settings that the backend cannot apply.

The ArkUI implementation and resource files are the source of truth:

- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/resources/base/element/color.json`
- `entry/src/main/resources/dark/element/color.json`
- `entry/src/main/resources/base/element/string.json`
- `entry/src/main/resources/zh_CN/element/string.json`

## Tokens

- **Canvas and surfaces:** `canvas` → `surface_primary` → inset `surface_inset`.
- **Text:** `text_primary`, `text_secondary`, `text_muted`; never use raw hex values in ArkTS.
- **Separation:** `border_standard` for cards and controls, `border_soft` for internal dividers.
- **Action:** `tunnel_accent` and `accent_surface` only for the primary tunnel action and related emphasis.
- **State:** `status_success`, `status_error`, `status_idle`; color supplements text and never replaces it.
- **Controls:** `control_secondary`, `control_disabled`, `on_accent` remain independent of surface tokens.

## Geometry

- **Depth:** borders only; no card shadows, gradients, glass, or decorative elevation.
- **Spacing base:** 4 vp.
- **Page:** 16 vp horizontal padding, 16 vp section gap, 680 vp maximum content width.
- **Cards:** 20 vp padding, 16 vp radius, 1 vp border.
- **Controls:** 10–12 vp radius; 44 vp secondary and 48 vp primary height.
- **Rows:** 12 vp vertical padding; use 8, 10, 12, 16, or 20 vp gaps.

## Typography

Use the HarmonyOS system typeface.

- App title: 28 vp bold.
- Connection state: 22 vp bold.
- Section title: 17 vp bold.
- Body and values: 14 vp regular/medium.
- Labels and helper text: 12–13 vp.
- Rail and metadata: 10–11 vp.

## Component Patterns

### Connection hero

- Shows one human-readable state and one next action.
- Priority: error → stopping/signing out → login required → connected → connecting → disconnected.
- Never show Connect and Disconnect simultaneously.
- Disable the primary action while an async transition is active.

### Tunnel rail

- Three markers: device, tunnel, tailnet.
- Idle uses `status_idle`; progress/login uses `tunnel_accent`; connected uses `status_success`; errors use `status_error`.
- Keep it structural and quiet—no animation unless reduced-motion behavior is also defined.

### Connection overview

- Compact label/value rows for backend, network, and VPN service.
- Values may truncate here; complete values remain available in raw diagnostics.

### Peer list

- Appears only as a secondary card below the connection overview.
- Sort online peers first; always pair the status color with Online, Offline, or Unknown text.
- A row exposes the peer name, preferred Tailscale address, OS, and one native 44 vp test action.
- The inline list is capped at 50 peers; add a dedicated virtualized page only when larger tailnets are in scope.

### Diagnostics

- Collapsed by default.
- Probe actions require a connected backend and valid input.
- Show progress by disabling the active action and changing its label.
- Keep peer, TCP, MagicDNS, resources, and raw status together.
- Raw status remains copyable and warns users to remove private endpoints before sharing.

### Identity

- Separate from routine connection controls.
- Use error semantics for logout-and-forget.
- Always require native confirmation before deleting identity.

## Content, Locale, and Accessibility

- Static user-facing copy lives in string resources; base English and `zh_CN` must remain aligned.
- Inputs have persistent nearby labels, meaningful examples, length limits, and `accessibilityText`.
- Errors must pair the problem with a recovery direction; raw platform codes belong in diagnostics.
- Preserve native Button and TextInput semantics, focus behavior, and touch feedback.

## Do Not Add Yet

- Taildrop, exit-node selection, subnet advertisement, per-app routing, or other controls without backend support.
- A component framework, navigation shell, icon dependency, or custom design abstraction for this single-page client.
- Permanent debug text above the primary connection action.

## Visual Reference

Codex image generation was used as a preview-only composition reference on 2026-08-05. Prompt summary: portrait HarmonyOS self-deployed VPN client; connection hero and tunnel rail first; compact network facts; collapsed developer diagnostics; separated destructive logout; borders-only depth; abyss navy, tunnel cyan, signal green, mist text, and alert coral; no dashboard grid, gradients, glassmorphism, or invented settings. The raster mockup is not tracked; the ArkUI implementation above is authoritative.
