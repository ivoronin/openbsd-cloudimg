#!/usr/bin/perl
use strict;
use warnings;
use Fcntl qw(O_RDONLY SEEK_SET);
use File::Temp qw(tempdir);
use CPAN::Meta::YAML;
use HTTP::Tiny;

my $IMDS_BASE = 'http://169.254.169.254/latest';
my ($uid, $gid, $home) = (getpwnam 'openbsd')[2, 3, 7];

# A hostname is interpolated into /etc/hosts, which (unlike sshd with keys)
# will not ignore a malformed value, so require it to be hostname-shaped.
sub hostname_ok { defined $_[0] && length $_[0] && $_[0] !~ /[^A-Za-z0-9.-]/ }

# ---- data sources ------------------------------------------------------
# Each returns { keys => \@keys, hostname => $h } if its medium yielded
# something usable, else undef so selection falls through to the next.

# Pack a source's findings into that contract, or undef if it found nothing
# usable (no keys and no valid hostname).
sub config {
    my ($keys, $host) = @_;
    return @$keys || hostname_ok($host) ? { keys => $keys, hostname => $host } : undef;
}

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
    my $doc = eval {
        open my $fh, '<', "$mnt/meta-data" or die;
        local $/;
        CPAN::Meta::YAML->read_string(scalar <$fh>)->[0];
    };
    system('umount', $mnt);
    return unless ref $doc eq 'HASH';
    # Trust the parsed list (the data source is root-equivalent); drop only
    # obvious breakage so a malformed file can't write junk to authorized_keys.
    my $pk = $doc->{'public-keys'};
    my @keys = grep { defined && !ref && /\S/ } (ref $pk eq 'ARRAY' ? @$pk : ());
    return config(\@keys, $doc->{'local-hostname'});
}

# timeout 15: give up if the IMDS does not answer within 15s, so an
# unavailable metadata endpoint cannot wedge boot.
sub imds_get {
    my $r = HTTP::Tiny->new(timeout => 15)->get("$IMDS_BASE/$_[0]");
    return unless $r->{success};
    (my $v = $r->{content}) =~ s/^\s+|\s+$//g;
    return length $v ? $v : ();
}

sub imds {
    my @keys = imds_get('meta-data/public-keys/0/openssh-key');
    my ($host) = imds_get('meta-data/local-hostname');
    return config(\@keys, $host);
}

# ---- apply -------------------------------------------------------------

sub apply_keys {
    my @keys = @_;
    my $dir = "$home/.ssh";
    mkdir $dir, 0700 unless -d $dir;
    my $file = "$dir/authorized_keys";

    my @lines;
    if (open my $fh, '<', $file) {
        # keep everything outside our managed block (flip-flop range, inclusive)
        @lines = grep { !(/^# cloud-init$/ .. /^# cloud-init end$/) } <$fh>;
    }
    open my $out, '>', $file or return;
    print $out @lines, "# cloud-init\n", map("$_\n", @keys), "# cloud-init end\n";
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

# ---- main: first present source wins -----------------------------------

# NoCloud (disk) wins if present; otherwise IMDS. NoCloud-first means a local
# VM with no IMDS does not sit through the HTTP timeout.
my $cfg = nocloud() // imds() // {};

apply_keys(@{ $cfg->{keys} })    if $cfg->{keys} && @{ $cfg->{keys} };
apply_hostname($cfg->{hostname}) if hostname_ok($cfg->{hostname});
