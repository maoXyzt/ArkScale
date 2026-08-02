# Tailscale patches

Patches apply to pinned Tailscale commit
`e4d64c6faf827a308ec20b39651225178e6743c0` (v1.82.5). `fetch-deps.sh`
applies them idempotently; `audit-openharmony-platform.sh` verifies the actual
files selected by the OpenHarmony-SIG Go toolchain.

## 0001: OpenHarmony platform seams

OpenHarmony-SIG Go intentionally exposes Linux compatibility to the standard
library and build system. Tailscale must not treat that as permission to manage
Linux host networking.

| Area | Linux path excluded | OpenHarmony choice |
| --- | --- | --- |
| `netns` | `SO_MARK`, `SO_BINDTODEVICE` | no-op socket control; Harmony VPN protects the process |
| `netmon` | rtnetlink and `/proc/net/route` | polling monitor plus `Monitor.InjectEvent()` |
| `router` | policy routing and netfilter | explicit `CallbackRouter`; accidental `router.New` fails |
| `magicsock` | raw AF_PACKET/BPF, UDP batching, PMTU sockopts | existing portable/default implementations |
| `tstun` | Linux link attributes, GRO/GSO probes, TUN diagnostics | external Harmony TUN fd plus existing no-op wrappers |

The patch only changes build selection and adds the missing no-op
`UseSocketMark` result. It does not change Tailscale protocol behavior.
