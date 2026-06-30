#!/usr/bin/perl
use strict;
use warnings;
use Fcntl qw(O_RDONLY SEEK_SET);
use File::Temp qw(tempdir tempfile);
use CPAN::Meta::YAML;
use HTTP::Tiny;

my $EC2_BASE = 'http://169.254.169.254/latest';
my $GCE_BASE = 'http://169.254.169.254/computeMetadata/v1';
my $HTTP = HTTP::Tiny->new(timeout => 5);   # one client, reused for every fetch
my ($uid, $gid, $home) = (getpwnam 'openbsd')[2, 3, 7];
# Flat state file (no dir to create - /var/db exists in base and survives the
# seal). Holds the instance-id of the last boot that ran user-data.
my $STATE_FILE = '/var/db/cloud-tini-instance-id';

# A hostname is interpolated into /etc/hosts, which (unlike sshd with keys)
# will not ignore a malformed value, so require it to be hostname-shaped.
sub hostname_ok { defined $_[0] && length $_[0] && $_[0] !~ /[^A-Za-z0-9.-]/ }

# ---- data sources ------------------------------------------------------
# Each returns { source => $name, keys => \@keys, hostname => $h,
# user_data => $s, instance_id => $id } if its medium yielded something usable,
# else undef so selection falls through.

# Pack a source's findings (tagged with its name) into that contract, or undef
# if it found nothing usable.
sub config {
    my ($source, $keys, $host, $user_data, $instance_id) = @_;
    return @$keys || hostname_ok($host) || length($user_data // '')
        ? { source => $source, keys => $keys, hostname => $host,
            user_data => $user_data, instance_id => $instance_id }
        : undef;
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or return;
    local $/;
    return scalar <$fh>;
}

# Strip leading and trailing whitespace; undef in, undef out.
sub trim { my $s = shift; return unless defined $s; $s =~ s/^\s+|\s+$//g; $s }

# The disk whose ISO9660 volume label is exactly CIDATA, else undef. Reads the
# Primary Volume Descriptor (no mount); the mount in nocloud() is the validator.
sub cidata_disk {
    chomp(my $names = `sysctl -n hw.disknames`);
    for my $dev (map { s/:.*//r } split /,/, $names) {
        sysopen my $fh, "/dev/r${dev}c", O_RDONLY or next;
        # The PVD is sector 16. Raw devices reject unaligned/short reads, so read
        # that whole 2048-byte sector and slice it: "CD001" at offset 1, the
        # 32-byte volume id at offset 40.
        my $pvd = '';
        sysseek($fh, 16 * 2048, SEEK_SET) and sysread($fh, $pvd, 2048);
        next unless length($pvd) >= 72 && substr($pvd, 1, 5) eq 'CD001';
        (my $label = substr($pvd, 40, 32)) =~ tr/A-Za-z0-9_//cd;
        return $dev if uc $label eq 'CIDATA';
    }
    return;
}

sub nocloud {
    my $dev = cidata_disk() // return;
    my $mnt = tempdir(CLEANUP => 1);   # private mount point, auto-removed
    system('mount', '-t', 'cd9660', '-r', "/dev/${dev}c", $mnt) == 0 or return;
    my $user_data = slurp("$mnt/user-data");
    my $doc = eval {
        open my $fh, '<', "$mnt/meta-data" or die;
        local $/;
        CPAN::Meta::YAML->read_string(scalar <$fh>)->[0];
    };
    system('umount', $mnt);
    return config('nocloud', [], undef, $user_data) unless ref $doc eq 'HASH';
    # Trust the parsed list (the data source is root-equivalent); drop only
    # obvious breakage so a malformed file can't write junk to authorized_keys.
    # public-keys may be a list or a single scalar (the common one-key form).
    my $pk = $doc->{'public-keys'};
    my @keys = grep { defined && !ref && /\S/ }
        ref $pk eq 'ARRAY' ? @$pk : defined $pk ? ($pk) : ();
    # Optional instance-id (the standard NoCloud meta-data key); gates user-data.
    my $iid = $doc->{'instance-id'};
    undef $iid if ref $iid;
    return config('nocloud', \@keys, $doc->{'local-hostname'}, $user_data, trim($iid));
}

# One HTTP call (the 5s timeout lives on $HTTP, so an absent or silent endpoint
# cannot wedge boot). Returns the body on 2xx, else undef.
sub http_get {
    my ($method, $url, $headers) = @_;
    my $r = $HTTP->request($method, $url, { headers => $headers // {} });
    return unless $r->{success};
    return $r->{content};
}

sub gce_get { http_get('GET', "$GCE_BASE/$_[0]", { 'Metadata-Flavor' => 'Google' }) }

# Past the instance-id probe the cloud is present, so retry a transient fetch rather
# than let one 5xx/timeout yield an empty (lockout) key set.
sub retry { my $f = shift; for (1 .. 3) { my $r = $f->(); return $r if defined $r } return }

# EC2 IMDS, IMDSv2-first. Grab a token if the endpoint offers one and send it on
# every GET; EC2-compatible services without a token endpoint (OpenStack, the
# test server) just fail the PUT, so we fall back to tokenless IMDSv1 GETs. The
# instance-id GET is the probe: no answer means this is not EC2 (or IMDS is off).
sub ec2 {
    my $token = http_get('PUT', "$EC2_BASE/api/token",
        { 'X-aws-ec2-metadata-token-ttl-seconds' => '21600' });
    $token =~ s/\s+$// if defined $token;
    my $hdr = $token ? { 'X-aws-ec2-metadata-token' => $token } : {};
    # A getter that already carries the token, so callers never thread it and a
    # later fetch cannot forget it - the same shape as gce_get's static header.
    my $get = sub { http_get('GET', "$EC2_BASE/$_[0]", $hdr) };

    my $iid = trim($get->('meta-data/instance-id'));
    return unless length($iid // '');

    # Enumerate the public-keys index ("<n>=<name>" per line) and fetch every
    # key, not just index 0; fall back to index 0 if the index is unavailable.
    my $list = $get->('meta-data/public-keys/') // '';
    my @idx = $list =~ /^(\d+)=/mg;
    @idx = (0) unless @idx;
    my @keys = map { my $n = $_; retry(sub { $get->("meta-data/public-keys/$n/openssh-key") }) } @idx;
    @keys = grep { length } map { trim($_) } @keys;

    my $host = trim($get->('meta-data/local-hostname'));
    my $user_data = $get->('user-data');
    return config('ec2', \@keys, $host, $user_data, $iid);
}

# GCE metadata. Same 169.254.169.254 as EC2 but a different path and the required
# Metadata-Flavor header, so on EC2 these GETs 404 and gce() returns undef. The
# instance/id GET is the probe.
sub gce {
    my $iid = trim(gce_get('instance/id'));
    return unless length($iid // '');

    # ssh-keys are "username:<key>" lines; the username is the account GCE would
    # log into, which we ignore - keep everything after the first ":" and install
    # every key into the openbsd user, like the EC2 path.
    my $raw = retry(sub { gce_get('instance/attributes/ssh-keys') }) // '';
    my @keys = map { (split /:/, $_, 2)[1] } grep { /:/ } split /\n/, $raw;
    @keys = grep { length } map { trim($_) } @keys;

    my $host = trim(gce_get('instance/hostname'));
    my $user_data = gce_get('instance/attributes/user-data');
    return config('gce', \@keys, $host, $user_data, $iid);
}

# ---- apply -------------------------------------------------------------

sub apply_keys {
    my @keys = @_;
    my $dir = "$home/.ssh";
    mkdir $dir, 0700 unless -d $dir;
    my $file = "$dir/authorized_keys";

    my @lines;
    if (open my $fh, '<', $file) {
        my @raw = <$fh>;
        # Strip our block only when the end marker is present; a legacy/truncated file
        # (start marker, no end) would otherwise run the range to EOF and wipe the
        # operator's own keys.
        if (grep { /^# cloud-tini end$/ } @raw) {
            @lines = grep { !(/^# cloud-tini$/ .. /^# cloud-tini end$/) } @raw;
        } else {
            @lines = @raw;
        }
    }
    open my $out, '>', $file or return;
    print $out @lines, "# cloud-tini\n", map("$_\n", @keys), "# cloud-tini end\n";
    close $out;
    chown $uid, $gid, $dir, $file;
}

sub apply_hostname {
    my $name = shift;
    if (open my $fh, '>', '/etc/myname') { print $fh "$name\n" }
    system('hostname', $name);

    (my $short = $name) =~ s/\..*//;
    my $names = join ' ', 'localhost', $short, ($short ne $name ? $name : ());
    open my $in, '<', '/etc/hosts' or return;
    my @hosts = <$in>;
    s/^(127\.0\.0\.1|::1)\s.*/$1 $names/ for @hosts;
    open my $out, '>', '/etc/hosts' or return;
    print $out @hosts;
}

sub run_user_data {
    my ($user_data, $iid) = @_;
    return unless length($user_data // '');

    # Run once per instance, like per-instance modules elsewhere: key and
    # hostname are idempotent and re-applied every boot, but user-data is an
    # arbitrary script, so gate it on the instance-id. IMDS always has one; a
    # CIDATA seed may carry an optional instance-id. Absent, it falls back to a
    # constant, so user-data runs exactly once.
    $iid //= 'iid-default';
    my $prev = slurp($STATE_FILE);
    $prev =~ s/\s+$// if defined $prev;
    return if defined $prev && $prev eq $iid;

    my ($fh, $path) = eval {
        tempfile('cloud-tini-user-data.XXXXXXXX', DIR => '/var/run', UNLINK => 1);
    };
    unless ($fh) {
        warn "cloud-tini: cannot write user-data: $@";
        return;   # do not record the iid: retry on the next boot
    }
    print $fh $user_data;
    close $fh;

    # Record once the tempfile is ready (a failure above retries next boot) but before
    # running, so a script that reboots or fails does not re-run every boot.
    if (open my $sfh, '>', $STATE_FILE) { print $sfh "$iid\n"; close $sfh }

    system('/bin/sh', $path);
    my $how = $? == -1 ? 'could not run'
            : $? & 127 ? 'killed by signal ' . ($? & 127)
            :            'exited ' . ($? >> 8);
    print "cloud-tini: user-data $how\n";
}

# ---- main: first present source wins -----------------------------------

# NoCloud (disk) wins if present; otherwise probe EC2 then GCE. Each network
# source self-detects by fetching its instance-id, so a non-cloud VM falls
# straight through instead of sitting on a metadata timeout.
my $cfg = nocloud() // ec2() // gce() // {};
print "cloud-tini: ", ($cfg->{source} // 'no data source'), "\n";

apply_keys(@{ $cfg->{keys} })    if $cfg->{keys} && @{ $cfg->{keys} };
apply_hostname($cfg->{hostname}) if hostname_ok($cfg->{hostname});
run_user_data($cfg->{user_data}, $cfg->{instance_id});
