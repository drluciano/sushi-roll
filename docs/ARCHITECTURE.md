# Architecture

```
lib/
  core/            pure Dart, no Flutter: protocol, server, client, discovery
  app/             AppController (state), Settings (persistence)
  ui/              screens, sheets and animated widgets
```

## Protocol v1

Every device runs an HTTP server on TCP **47100**. If that port is busy, it tries the next nine. JSON bodies are used everywhere except uploads.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/sushi/v1/info` | `{id, name, platform, port, version, pinRequired}` |
| POST | `/sushi/v1/hello` | Body: caller's info. Registers the caller (using the address it came from) and returns ours. |
| GET | `/sushi/v1/peers` | Peers we've recently reached: `[{host, port, info}]` |
| POST | `/sushi/v1/offer` | `{sender, files:[{id,name,size}], pin?}`. Held open until the user answers (2 min max). 200 `{session}`, 401 wrong PIN, 403 declined. |
| POST | `/sushi/v1/upload?session=&file=` | Raw bytes with exact `Content-Length`. Written to `name.part`, then renamed. |
| POST | `/sushi/v1/cancel?session=` | Either side stops the session. |

LAN discovery is a JSON announce `{sushi:1, info}` to multicast group `239.255.71.100:47101`. It's best-effort only.

## Why it works over Tailscale

- Discovery never relies on multicast alone (see the README for the four routes).
- A device can have several addresses (LAN IP, tailnet IP, MagicDNS name). Each peer keeps them all, ordered by last success. Sending tries them in order.
- Incoming `hello`/`offer` requests register the sender, so a device that can only be found by others (iOS) still ends up with a full list.

## Security

Transfers are plain HTTP. Over Tailscale they're already end-to-end encrypted by WireGuard. Nothing is written without the receiver tapping Accept, and an optional 4-digit PIN stops strangers on a shared network from even asking. File names are sanitized so they can't escape the receive folder or use Windows reserved names.

## iOS notes

- iOS suspends sockets in the background. The app restarts its server and rediscovers when it comes back to the foreground, so keep it open during a transfer.
- Multicast on iOS needs Apple's multicast entitlement. Without it, LAN discovery quietly does nothing and the other routes cover it.
