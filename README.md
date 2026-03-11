# APRS.fi Tracker

Real-time APRS position tracker via direct APRS-IS TCP stream.

## Quick Start

```bash
cp track_aprs_is.sh.example track_aprs_is.sh
# Edit track_aprs_is.sh with your callsign and passcode
./track_aprs_is.sh
```

## Files

| File               | Description                                    |
|--------------------|------------------------------------------------|
| `track_aprs_is.pl`       | Main tracker — APRS-IS TCP stream, parser, log |
| `callsigns.conf`         | Tracked callsigns (one per line, `*` wildcard) |
| `parse_raw.py`           | Parse raw APRS packets (offline/debug)         |
| `track_aprs_is.sh`       | Your credentials (gitignored)                  |

## Configuration

Edit `callsigns.conf` to add/remove tracked stations:

```
LZ1CCM*
LZ3SP*
```

## Environment Variables

| Variable         | Description                                |
|------------------|--------------------------------------------|
| `APRS_CALL`      | Your callsign (without SSID)               |
| `APRS_PASSCODE`  | APRS-IS passcode (computed from call)      |
| `APRS_FI_KEY`    | aprs.fi API key — optional, fetches history|

## Station Info

- **Callsign**: LZ1CCM-9 (SSID -9 = mobile)
- **Operator**: Miroslav Tzonkov
- **QTH**: Sofia, 42°39'N 23°21'E
- **Radio**: Baofeng DM-32UV (GPS + DMR)
- **APRS paths**:
  - Brandmeister: `LZ1CCM,DMR*,qAR,LZ1CCM` (tocall APBM1D)
  - DMR+: `LZ0DDA,TCPIP*,qAU,FOURTH` (tocall APDMRP, repeater LZ0DDA)

## aprs.fi HTTP API (legacy, slower)

- **Base URL**: `https://api.aprs.fi/api/get`
- **Docs**: https://aprs.fi/page/api
- Note: API caches data — introduces delay vs APRS-IS TCP stream
- Note: Wildcard `*` does NOT work in API — use exact SSID
