#!/usr/bin/env perl
# qa-redact: sanitise an HTTP response (curl -si output) or a bare body read on stdin. Fail-closed.
use strict; use warnings; use JSON::PP;
my $names_file = shift @ARGV;
die "qa-redact: names file unavailable\n" unless defined $names_file && -f $names_file && -r $names_file && !-l $names_file && -O $names_file;
open my $names, '<', $names_file or die "qa-redact: names file unavailable\n";
my @DECL;
while (my $name = <$names>) {
    chomp $name;
    die "qa-redact: invalid names file\n" unless $name =~ /\A(?:QA_[A-Z0-9_]+|PGHOST|PGUSER|PGDATABASE|PGPASSWORD|SQLITE_DB|MYSQL_HOST|MYSQL_USER|MYSQL_DATABASE|MYSQL_PWD)\z/;
    my $value = $ENV{$name};
    push @DECL, $value if defined $value && length($value) >= 4;
}
close $names;
local $/; my $in = <STDIN>; $in = '' unless defined $in;
my %SENSITIVE = map { $_ => 1 } qw(token secret password passwd pwd passphrase key session cookie auth authorization credential private dsn url uri jwt bearer otp pin sig signature);
my $STEM = qr/token|secret|passw|apikey|accesskey|privatekey|sessionid|sessid|csrf|xsrf|credential|connectionstring|recoverycode|verificationcode|backupcode/;
sub sensitive_key { my $k = shift; $k =~ s/(?<=[a-z0-9])(?=[A-Z])/_/g; $k =~ s/(?<=[A-Z])(?=[A-Z][a-z])/_/g;
    my @seg = map { my $s = $_; $s =~ s/(?<!s)s$// if length($s) > 3; $s } grep { length } split /[^A-Za-z0-9]+/, lc $k;
    return 1 if grep { $SENSITIVE{$_} } @seg;
    return join('', @seg) =~ $STEM ? 1 : 0; }
sub scrub_text { my $t = shift;
    $t =~ s/(bearer\s+)[A-Za-z0-9._~+\/=-]+/$1***/gi;
    $t =~ s/([?&;#][\w.%\[\]-]*?(?:token|key|secret|passw|pwd|auth|session|code|sig|credential)[\w.%\[\]-]*=)[^&\s"'#]+/$1***/gi;
    $t =~ s{(\b[a-z][a-z0-9+.-]*://[^:/?#\s"'@]*:)[^/?#\s"'@]+@}{$1***@}gi;
    for my $val (@DECL) { $t =~ s/\Q$val\E/***/g; }
    return $t; }
sub scrub { my $v = shift;
    if (!ref $v) { if (defined $v) { for my $val (@DECL) { $v =~ s/\Q$val\E/***/g; } } return $v; }
    if (ref $v eq 'HASH') { for my $k (keys %$v) { $v->{$k} = sensitive_key($k) ? '***' : scrub($v->{$k}); } }
    elsif (ref $v eq 'ARRAY') { $_ = scrub($_) for @$v; }
    return $v; }
my ($head, $body) = ('', $in);
if ($in =~ /^HTTP\/[0-9.]+ \d{3}/) {
    my @parts = split /\r?\n\r?\n/, $in, -1;
    my $i = 0; $i++ while ($i < $#parts && $parts[$i] =~ /^HTTP\/[0-9.]+ (?:1\d\d|3\d\d|200 Connection established)(?:\s|$)/i && $parts[$i + 1] =~ /^HTTP\/[0-9.]+ \d{3}/);
    $head = $parts[$i]; $head =~ s/\r//g;
    $body = $i < $#parts ? join("\n\n", @parts[$i + 1 .. $#parts]) : '';
    $head =~ s{^([^\s:]+)(\s*:)([^\n]*)}{ my ($n, $c, $v) = ($1, $2, $3); $n !~ /^access-control-/i && sensitive_key($n) ? "$n$c ***" : "$n$c$v" }gme;
}
my $out = '';
if ($body !~ /^\s*$/) {
    my $json = eval { JSON::PP->new->allow_nonref->decode($body) };
    if ($@ || !defined $json) { $out = sprintf("[body withheld by qa-redact: not valid JSON, %d bytes]\n", length $body); }
    elsif (!ref $json && $json !~ /^(?:-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|true|false|null)$/) { $out = sprintf("[body withheld by qa-redact: scalar body, %d bytes]\n", length $body); }
    else { $out = JSON::PP->new->canonical->indent->space_after->allow_nonref->encode(scrub($json)); }
}
print scrub_text($head eq '' ? $out : "$head\n\n$out");
