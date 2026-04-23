#!/bin/bash
# Read last valid positions for tracked stations from APRS log and write JSON.
# Log file stores UTC (ZULU) timestamps; this script converts to system local
# time automatically via `date +%z`.

LOG="/home/claude/work/track_aprs/lz1ccm.log"
OUT="/sites/map.smooker.org/position.json"

# Auto-detect TZ offset in hours (e.g. +0300 → 3.00)
TZ_OFFSET="$(date +%z | awk '{ sign = substr($0,1,1); hh = substr($0,2,2); mm = substr($0,4,2); val = hh + mm/60; if (sign == "-") val = -val; printf "%.2f", val }')"

# Callsigns to exclude from the map (network infra / non-mobile beacons)
EXCLUDE_RE='^(LZ3SP($|-)|LZ3NY($|-))'

perl -e '
    use JSON::PP;
    use POSIX qw(strftime);
    use Time::Local qw(timegm);
    my ($logfile, $tz_offset, $exclude_re) = @ARGV;
    my %stations;
    open my $fh, "<", $logfile or die;
    while (<$fh>) {
        chomp;
        next if /INVALID/;
        my ($date, $time, $rest);
        if (/^\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(.*)/) {
            $date = $1; $time = $2; $rest = $3;
        } else { next; }

        my ($call, $lat, $lon, $course, $speed, $via, $comment, $raw);

        if ($rest =~ /^(\S+?)>(\S+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s+(\S+)\s*(.*)/) {
            $call = $1; $raw = $2; $lat = $3; $lon = $4; $course = $5; $speed = $6; $via = $7; $comment = $8;
        }
        elsif ($rest =~ /^(LZ\S+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s+(.*)/) {
            $call = $1; $lat = $2; $lon = $3; $course = $4; $speed = $5;
            my $r = $6;
            if ($r =~ /^(\S.*?)\s{2,}(.*)/) { $via = $1; $comment = $2; }
            else { $via = $r; }
        }
        elsif ($rest =~ /^\s*([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s+(.*)/) {
            $lat = $1; $lon = $2; $course = $3; $speed = $4;
            $call = "LZ1CCM-9";
            my $r = $5;
            if ($r =~ /^(\S.*?)\s{2,}(.*)/) { $via = $1; $comment = $2; }
            else { $via = $r; }
        }
        else { next; }

        next unless $lat && $lon && $lat > 0;
        next if $call =~ /$exclude_re/;

        $comment //= "";
        $comment =~ s/\s+$//;
        $via //= "?";
        $via =~ s/\s+$//;

        # Convert UTC log timestamp → local time via tz_offset
        my $local_time = "$date $time";
        my ($Y, $M, $D) = split /-/, $date;
        my ($h, $mn, $sc) = split /:/, $time;
        my $epoch = timegm($sc, $mn, $h, $D, $M-1, $Y-1900);
        $epoch += $tz_offset * 3600;
        $local_time = strftime("%Y-%m-%d %H:%M:%S", gmtime($epoch));

        $stations{$call} = {
            call    => $call,
            lat     => $lat+0,
            lon     => $lon+0,
            course  => $course,
            speed   => $speed,
            via     => $via,
            comment => $comment,
            time    => $local_time,
        };
    }
    close $fh;
    my @list = values %stations;
    print encode_json({ stations => \@list }) . "\n";
' "$LOG" "$TZ_OFFSET" "$EXCLUDE_RE" > "$OUT"
