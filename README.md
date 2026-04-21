# CTL

`CTL` is a Debian/Ubuntu deployment and management script for a sing-box based multi-protocol server.

It installs:

- `AnyTLS`
- `Hysteria2`
- `VLESS + WS + TLS`
- `VMess + WS + TLS`
- `Shadowsocks`
- `TUIC`
- `Trojan + WS + TLS`
- `Trojan + gRPC + TLS`

It also manages:

- `sing-box`
- `nginx`
- `acme.sh`
- HTTPS subscription outputs
- certificate renewal
- update / restart / uninstall actions
- an interactive menu opened by the `ctl` command

## Supported OS

- `Debian`
- `Ubuntu`

## Quick Start

Run directly from GitHub Raw:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/cimile/kimi/main/ctl.sh)
```

After installation:

```bash
ctl
```

## Recommended Install With Variables

```bash
CTL_DOMAIN=your.domain.com \
CTL_EMAIL=you@example.com \
CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/kimi/main/ctl.sh \
bash <(wget -qO- https://raw.githubusercontent.com/cimile/kimi/main/ctl.sh)
```

## Main Commands

```bash
ctl
ctl install
ctl show
ctl sub
ctl renew
ctl update
ctl restart
ctl uninstall
ctl site-check
ctl tune-network
ctl set-update-url https://raw.githubusercontent.com/cimile/kimi/main/ctl.sh
```

## Environment Variables

```bash
CTL_DOMAIN=your.domain.com
CTL_EMAIL=you@example.com
CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/kimi/main/ctl.sh
CTL_VLESS_WS_PATH=/ctl-vless
CTL_VMESS_WS_PATH=/ctl-vmess
CTL_TROJAN_WS_PATH=/ctl-trojan-ws
CTL_TROJAN_GRPC_SERVICE=ctl-trojan-grpc
CTL_RESET_SECRETS=1
```

## Generated Subscription Outputs

After installation, `ctl sub` will show:

- `universal`
- `clash.yaml`
- `v2rayn.txt`
- `shadowrocket.txt`
- `karing.txt`
- `sub.txt`
- `raw.txt`
- `client-info.txt`

## Client Import Mapping

- `Clash / Clash Party`: `clash.yaml`
- `v2rayN`: `v2rayn.txt`
- `Shadowrocket`: `shadowrocket.txt`
- `Karing`: `karing.txt`
- `Not sure`: `universal`

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
- `clash.yaml` excludes `AnyTLS` on purpose to reduce import errors in stricter clients.
- `karing.txt` keeps `AnyTLS` because Karing handles it better.
- `nginx` fronts the subscription site, WS routes, and the gRPC endpoint.
- `acme.sh` handles certificate issuance and renewal.

## Credits / References

- `sing-box`: [https://sing-box.sagernet.org](https://sing-box.sagernet.org)
- `acme.sh`: [https://github.com/acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh)
- `nginx`: [https://nginx.org](https://nginx.org)
- `Project X WebSocket transport docs`: [https://xtls.github.io/en/config/transports/websocket](https://xtls.github.io/en/config/transports/websocket)
- `Project X gRPC transport docs`: [https://xtls.github.io/en/config/transports/grpc.html](https://xtls.github.io/en/config/transports/grpc.html)
- `Mihomo docs`: [https://wiki.metacubex.one/en/](https://wiki.metacubex.one/en/)
- `v2rayN`: [https://github.com/2dust/v2rayN](https://github.com/2dust/v2rayN)
