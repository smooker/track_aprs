#!/usr/bin/perl

=head1 NAME

track_lz1ccm.pl — Real-time APRS position tracker via APRS-IS TCP stream

=head1 SYNOPSIS

    ./track_lz1ccm.pl

=head1 DESCRIPTION

Connects directly to the APRS-IS network (TCP port 14580) and displays
incoming position reports in real time.  Unlike the aprs.fi HTTP API
(which caches data and introduces delay), the APRS-IS stream delivers
packets the moment they enter the network.

On startup the script prints the last 10 entries from the log file,
then listens for new packets.  Each received position is printed to
the terminal and appended to C<lz1ccm.log>.  Server keepalive messages
are shown as heartbeat dots.

The connection is automatically re-established if it drops.

=head1 CONFIGURATION

Callsigns to track are read from C<callsigns.conf> in the same directory
as the script.  One callsign per line; C<*> matches all SSIDs.
Lines starting with C<#> are comments.

    # callsigns.conf
    LZ1CCM*
    LZ3SP*

The APRS-IS server-side filter C<b/CALL1/CALL2/...> is built from
the config, so only matching packets are forwarded.

=head1 APRS PATH DETECTION

The script recognises two common DMR-to-APRS gateways:

=over 4

=item B<Brandmeister> — tocall C<APBM1D>, via DMR talkgroup 284999

=item B<DMR+> — tocall C<APDMRP>, via repeater (e.g. LZ0DDA)

=back

Other paths are shown as C<?>.

=head1 OUTPUT FORMAT

    Time                Call        Lat        Lon  Crs  Spd  Via           Comment
    2026-03-11 05:26:57  LZ1CCM-9   42.65267   23.36467  273  000  Brandmeister  Miroslav Tzonkov

=head1 FILES

=over 4

=item F<callsigns.conf> — tracked callsigns (one per line)

=item F<lz1ccm.log> — persistent position log (appended)

=back

=head1 DEPENDENCIES

Core Perl modules only: L<IO::Socket::INET>, L<POSIX>, L<FindBin>.

=head1 HISTORY

Originally polled the aprs.fi HTTP API every 60s (JSON + curl).
Rewritten to use APRS-IS direct TCP for zero-delay streaming.

=head1 AUTHORS

LZ1CCM (Miroslav Tzonkov) — concept & testing

Claude (Anthropic) — code

=head1 LICENSE

Free to use, 73!

=cut

use strict;
use warnings;
use IO::Socket::INET;
use POSIX qw(strftime mktime);
use FindBin qw($RealBin);

my $CALL     = $ENV{APRS_CALL}     || die "Set APRS_CALL env var (or use startup.sh)\n";
my $PASSCODE = $ENV{APRS_PASSCODE} || die "Set APRS_PASSCODE env var (or use startup.sh)\n";
my $SERVER   = 'rotate.aprs2.net';
my $PORT     = 14580;
my $LOGFILE  = "$RealBin/lz1ccm.log";
my $CONFFILE = "$RealBin/callsigns.conf";
my $last_ts  = 0;
my %seen;

$| = 1;

# --- Load callsigns from config ---

sub load_callsigns {
    my @calls;
    if (-f $CONFFILE) {
        open my $fh, '<', $CONFFILE or die "Can't read $CONFFILE: $!\n";
        while (<$fh>) {
            chomp;
            s/\r//g;
            s/#.*//;         # strip comments
            s/^\s+|\s+$//g;  # trim
            push @calls, uc($_) if length;
        }
        close $fh;
    }
    @calls = ('LZ1CCM*') unless @calls;  # fallback
    return @calls;
}

my @CALLS = load_callsigns();
my $filter_str = join('/', @CALLS);
print "Tracking: " . join(', ', @CALLS) . "\n";

# Build regex patterns from callsigns (convert * wildcard to .*)
my @call_patterns;
for my $c (@CALLS) {
    my $pat = quotemeta($c);
    $pat =~ s/\\\*/.*/g;
    push @call_patterns, qr/^($pat)>/i;
}

my $hdr = sprintf "%20s  %-10s  %9s  %9s  %3s  %3s  %-12s  %s",
    'Time', 'Call', 'Lat', 'Lon', 'Crs', 'Spd', 'Via', 'Comment';
my $sep = '-' x 105;

print "$hdr\n$sep\n";

# Load existing log — show last 10 on startup
if (-f $LOGFILE) {
    open my $lf, '<', $LOGFILE;
    my @lines;
    while (<$lf>) {
        chomp;
        push @lines, $_;
        if (/^\s*(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
            my $epoch = mktime($6, $5, $4, $3, $2-1, $1-1900);
            $seen{$epoch} = 1;
            $last_ts = $epoch if $epoch > $last_ts;
        }
    }
    close $lf;
    my @tail = @lines > 10 ? @lines[-10..$#lines] : @lines;
    print "  [log: last " . scalar(@tail) . " of " . scalar(@lines) . "]\n";
    print "$_\n" for @tail;
    print "$sep\n";
}

open my $log, '>>', $LOGFILE or warn "Can't open log: $!\n";
$log->autoflush(1);

# --- APRS position parsers ---

sub dm2dd {
    my ($dm, $dir) = @_;
    return undef unless $dm =~ /^(\d{2,3})(\d{2}\.\d+)$/;
    my $deg = $1 + $2 / 60.0;
    $deg = -$deg if $dir eq 'S' || $dir eq 'W';
    return $deg;
}

sub parse_aprs_packet {
    my ($raw) = @_;

    # Skip server messages
    return undef if $raw =~ /^#/;

    # Match against any configured callsign
    my $name;
    for my $pat (@call_patterns) {
        if ($raw =~ $pat) {
            $name = $1;
            last;
        }
    }
    return undef unless $name;

    # Determine path/via
    my $via;
    if ($raw =~ /APBM1D/) {
        $via = 'Brandmeister';
    } elsif ($raw =~ /APDMRP/) {
        my ($rep) = $raw =~ /via DMR\+ (\S+)/;
        $via = $rep ? "DMR+ $rep" : 'DMR+';
    } else {
        $via = '?';
    }

    # Parse uncompressed position: DDMM.MMN/DDDMM.MME
    my ($lat, $lon);
    if ($raw =~ /(\d{4}\.\d{2})([NS])\/(0?\d{4}\.\d{2})([EW])/) {
        $lat = dm2dd($1, $2);
        $lon = dm2dd($3, $4);
    } else {
        return undef;  # no valid position
    }

    # Course/speed after position symbol char
    my ($crs, $spd) = ('000', '000');
    if ($raw =~ /[>\[\[](0?\d{2,3})\/(0?\d{2,3})/) {
        $crs = sprintf('%03d', $1);
        $spd = sprintf('%03d', $2);
    }

    # Comment — everything after course/speed
    my $comment = '';
    if ($raw =~ /\d{3}\/\d{3}\s*(.*)$/) {
        $comment = $1;
    }

    return {
        name    => $name,
        lat     => $lat,
        lon     => $lon,
        crs     => $crs,
        spd     => $spd,
        via     => $via,
        comment => $comment,
    };
}

# --- Main loop: connect and stream ---

while (1) {
    print "Connecting to $SERVER:$PORT ...\n";

    my $sock = IO::Socket::INET->new(
        PeerAddr => $SERVER,
        PeerPort => $PORT,
        Proto    => 'tcp',
        Timeout  => 30,
    );

    unless ($sock) {
        warn "Connect failed: $! — retry in 30s\n";
        sleep 30;
        next;
    }

    # Read server banner
    my $banner = <$sock>;
    chomp $banner if $banner;
    print "  [$banner]\n" if $banner;

    # Login with filter for configured callsigns
    my $login = "user $CALL pass $PASSCODE vers PerlTracker 1.0 filter b/$filter_str\r\n";
    print $sock $login;

    # Read login response
    my $resp = <$sock>;
    chomp $resp if $resp;
    if ($resp && $resp =~ /verified/) {
        print "  [Logged in, filter: b/$filter_str]\n";
    } else {
        print "  [Login: $resp]\n" if $resp;
    }

    print "$sep\n";
    print "  Listening (real-time stream)...\n\n";

    # Stream packets
    while (my $line = <$sock>) {
        chomp $line;
        $line =~ s/\r//g;

        # Server keepalive
        if ($line =~ /^#/) {
            print ".";
            next;
        }

        my $p = parse_aprs_packet($line);
        next unless $p;

        my $now = time();
        my $key = "$p->{name}:$now";
        next if $seen{$key};

        my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime($now));

        my $out = sprintf "%20s  %-10s  %9.5f  %9.5f  %3s  %3s  %-12s  %s",
            $ts, $p->{name}, $p->{lat}, $p->{lon}, $p->{crs}, $p->{spd}, $p->{via}, $p->{comment};

        print "\n$out\n";
        print $log "$out\n";
        $seen{$key} = 1;
        $last_ts = $now;
    }

    # Connection dropped
    close $sock;
    warn "Connection lost — reconnecting in 10s...\n";
    sleep 10;
}
