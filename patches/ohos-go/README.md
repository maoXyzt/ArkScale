# OpenHarmony-SIG Go patches

Patches apply to pinned commit
`2d8b23f6923100d8c90d8add9299da2c9d032a20`.

`0001-net-close-interface-resources.patch` closes the ioctl socket and frees the
`getifaddrs` list created by each OpenHarmony `net.Interfaces` query. Remove the
patch once the pinned toolchain contains an equivalent upstream fix.
