#!/usr/bin/env python3
"""Parse raw APRS packets for LZ1CCM and display human-readable output."""

import re, sys

packets = """2026-03-08 15:29:56 EET: LZ1CCM-9>APBM1D,LZ1CCM,DMR*,qAR,LZ1CCM:@132939h4239.16N/02321.88E[273/000Miroslav Tzonkov
2026-03-08 18:47:03 EET: LZ1CCM-9>APBM1D,LZ1CCM,DMR*,qAR,LZ1CCM:@164658h4239.17N/@0[326/251Miroslav Tzonkov
2026-03-08 22:14:40 EET: LZ1CCM-9>APBM1D,LZ1CCM,DMR*,qAR,LZ1CCM:@201435h4239.19N/02321.85E[342/000Miroslav Tzonkov
2026-03-09 00:57:17 EET: LZ1CCM-9>APBM1D,LZ1CCM,DMR*,qAR,LZ1CCM:@225703h4239.16N/02321.88E[090/000Miroslav Tzonkov
2026-03-09 07:17:15 EET: LZ1CCM-9>APBM1D,LZ0ATV,DMR*,qAR,LZ0ATV:@051712h4239.17N/02321.88E[292/000Miroslav Tzonkov
2026-03-09 07:28:43 EET: LZ1CCM-9>APDMRP,LZ0DDA,TCPIP*,qAU,FOURTH:!4238.98N/02322.05E>109/000 Miroslav via DMR+ LZ0DDA
2026-03-09 22:25:19 EET: LZ1CCM-9>APDMRP,LZ0DDA,TCPIP*,qAU,FOURTH:!4239.26N/02321.74E>272/002 Miroslav via DMR+ LZ0DDA
2026-03-10 07:16:16 EET: LZ1CCM-9>APDMRP,LZ0DDA,TCPIP*,qAU,FOURTH:!4239.17N/02321.89E>302/000 Miroslav via DMR+ LZ0DDA"""

def dm2dd(dm_str, direction):
    """Convert DDMM.MM to decimal degrees."""
    m = re.match(r'(\d{2,3})(\d{2}\.\d+)', dm_str)
    if not m:
        return None
    deg = int(m.group(1)) + float(m.group(2)) / 60.0
    if direction in ('S', 'W'):
        deg = -deg
    return deg

print(f"{'Time EET':>20s}  {'Lat':>9s}  {'Lon':>9s}  {'Crs':>3s}  {'Spd':>3s}  {'Via':>12s}  Comment")
print("-" * 90)

for line in packets.strip().split('\n'):
    # Extract timestamp
    ts_match = re.match(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) EET:', line)
    ts = ts_match.group(1) if ts_match else '?'

    # Determine path/via
    if 'APBM1D' in line:
        via = 'Brandmeister'
    elif 'APDMRP' in line:
        via_match = re.search(r'via DMR\+ (\S+)', line)
        via = f"DMR+ {via_match.group(1)}" if via_match else 'DMR+'
    else:
        via = '?'

    # Parse position: DDMM.MMN/DDDMM.MME
    pos = re.search(r'(\d{4}\.\d{2})([NS])[/@](\d{5}\.\d{2})([EW])', line)
    if pos:
        lat = dm2dd(pos.group(1), pos.group(2))
        lon = dm2dd(pos.group(3), pos.group(4))
    else:
        lat = lon = None

    # Parse course/speed
    cs = re.search(r'[>\[[](\d{3})/(\d{3})', line)
    crs = cs.group(1) if cs else '?'
    spd = cs.group(2) if cs else '?'

    # Comment
    comment_match = re.search(r'\d{3}/\d{3}\s*(.*?)$', line)
    comment = comment_match.group(1) if comment_match else ''

    if lat and lon:
        print(f"{ts:>20s}  {lat:9.5f}  {lon:9.5f}  {crs:>3s}  {spd:>3s}  {via:>12s}  {comment}")
    else:
        print(f"{ts:>20s}  {'INVALID':>9s}  {'':>9s}  {crs:>3s}  {spd:>3s}  {via:>12s}  {comment} [bad pos]")
