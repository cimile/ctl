# CTL

`CTL` is a Debian/Ubuntu deployment and management script for a multi-protocol access stack.

It installs:

- `Hysteria2`
- `TUIC v5`
- `Shadowsocks 2022 Blake3`
- `VLESS + XHTTP + Reality`
- `Trojan + Reality`

It also manages:

- `sing-box`
- `Xray`
- `nginx`
- `acme.sh`
- HTTPS subscription outputs
- certificate renewal
- update / repair / restart / uninstall actions
- an interactive menu opened by the `ctl` command

## Supported OS

- `Debian`
- `Ubuntu`

## Quick Start

```bash
bash <(wget -qO- https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh)
```

After installation:

```bash
ctl
```

## Recommended Install With Variables

```bash
CTL_DOMAIN=your.domain.com \
CTL_EMAIL=you@example.com \
CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh \
bash <(wget -qO- https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh)
```

## Main Commands

```bash
ctl
ctl install
ctl show
ctl sub
ctl renew
ctl update
ctl repair
ctl restart
ctl uninstall
ctl site-check
ctl tune-network
ctl set-update-url https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
```

## Environment Variables

```bash
CTL_DOMAIN=your.domain.com
CTL_EMAIL=you@example.com
CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
CTL_XHTTP_PATH=/ctl-xhttp
CTL_TROJAN_REALITY_PORT=9443
CTL_RESET_SECRETS=1
```

## Generated Subscription Outputs

After installation, `ctl sub` shows:

- `universal`
- `clash.yaml`
- `v2rayn.txt`
- `shadowrocket.txt`
- `karing.txt`
- `sub.txt`
- `raw.txt`
- `sub.json`
- `client-info.txt`

## Client Import Mapping

- `Mihomo / Clash Party`: `clash.yaml`
- `v2rayN`: `v2rayn.txt`
- `Shadowrocket`: `shadowrocket.txt`
- `Karing`: `karing.txt`
- `Not sure`: `universal`

## Client Filtering Policy

- `clash.yaml` keeps all five protocols.
- `v2rayn.txt` keeps all five protocols.
- `shadowrocket.txt`, `karing.txt`, and the generic `sub.txt` intentionally exclude `VLESS + XHTTP + Reality` to avoid import failures on clients that still lag behind the latest XHTTP handling.
- `raw.txt` keeps the full set for manual import.
- `sub.json` exposes the subscription mapping in a machine-readable form.

## Service Checks

Run:

```bash
ctl site-check
```

This checks the current VPS egress IP against:

- `Netflix`
- `TikTok`
- `Facebook`
- `X`
- `ChatGPT Web`
- `OpenAI API`
- `Claude`
- `Gemini`
- `Perplexity`

## Notes

- `BBR / network tuning` is optional and is not enabled automatically.
- `Protocol` does not equal `unlock`. Netflix, TikTok, ChatGPT, Claude, Gemini, and similar services mostly depend on the VPS egress IP, ASN type, region, and reputation.
- `nginx` serves only the subscription hub and HTTPS redirect layer. Reality nodes are exposed on their own TCP ports.
- `acme.sh` handles certificate issuance and renewal.
- `ctl uninstall` removes CTL-managed configs, certificates, binaries, and legacy `kimi` leftovers, while keeping the `nginx` and `acme.sh` packages installed.

## Credits / References

- `sing-box`: [https://sing-box.sagernet.org](https://sing-box.sagernet.org)
- `Xray-core`: [https://github.com/XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- `acme.sh`: [https://github.com/acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh)
- `nginx`: [https://nginx.org](https://nginx.org)
- `Project X REALITY docs`: [https://xtls.github.io/en/config/transport.html](https://xtls.github.io/en/config/transport.html)
- `Project X XHTTP docs`: [https://xtls.github.io/en/config/transports/xhttp.html](https://xtls.github.io/en/config/transports/xhttp.html)
- `Mihomo docs`: [https://wiki.metacubex.one/en/](https://wiki.metacubex.one/en/)
- `v2rayN`: [https://github.com/2dust/v2rayN](https://github.com/2dust/v2rayN)
