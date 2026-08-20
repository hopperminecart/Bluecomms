# BlueComms

Nearby Mac chat and files over Bonjour + AWDL. No internet. Wi-Fi just needs to be on.

## Run with a friend

On **each** Mac, after this fix is on `main`:

```bash
cd Bluecomms
git pull
cd BlueCommsCLI
swift run BlueCommsApp
```

1. Wi-Fi on (same network not required).
2. Allow **Local Network** for Terminal.
3. Click the other Mac → **Connect** → type, Attach, Screenshot, or drop a file.

Incoming files: `~/Downloads/BlueComms`.

Terminal instead:

```bash
cd Bluecomms/BlueCommsCLI
swift run BlueCommsCLI
```

Then `list`, `connect 0`, type, `quit`.

Needs macOS 14+ and Swift 6.1.

If AirDrop also cannot see the other Mac, fix AirDrop first (same radio). Quit Tailscale and try with the firewall off.

## Tests

```bash
cd BlueCommsCLI
swift run BlueCommsSelfTest
```
