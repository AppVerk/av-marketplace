#!/usr/bin/env perl
# qa-redact: sanitise an HTTP response (curl -si output) or a bare body read on stdin. Fail-closed.
use strict; use warnings; use JSON::PP;
use Socket qw(AF_INET6 inet_pton);
my $names_file = shift @ARGV;
die "qa-redact: names file unavailable\n" unless defined $names_file && -f $names_file && -r $names_file && !-l $names_file && -O $names_file;
open my $names, '<', $names_file or die "qa-redact: names file unavailable\n";
my @DECL;
my $CLIENT_NAMES = qr/PGHOST|PGPORT|PGUSER|PGDATABASE|PGPASSWORD|SQLITE_DB|MYSQL_HOST|MYSQL_TCP_PORT|MYSQL_USER|MYSQL_DATABASE|MYSQL_PWD|REDIS_HOST|REDIS_PORT|REDIS_DB|REDISCLI_AUTH/;
while (my $name = <$names>) {
    chomp $name;
    die "qa-redact: invalid names file\n" unless $name =~ /\A(?:QA_[A-Z0-9_]+|$CLIENT_NAMES|STORE_[A-Z0-9_]+_(?:$CLIENT_NAMES))\z/;
    next if $name =~ /\A(?:STORE_[A-Z0-9_]+_)?(?:PGPORT|MYSQL_TCP_PORT|REDIS_PORT|REDIS_DB)\z/; # Ports and Redis indexes are not secrets.
    my $value = $ENV{$name};
    push @DECL, $value if defined $value && length($value) >= 4;
    if (defined $value && $name =~ /_COOKIE(?:_[0-9]+)?\z/ && $value =~ /^[^=]*=([^;]+)/) {
        push @DECL, $1 if length($1) >= 3; # Cookies may be echoed without their name or attributes.
    }
}
close $names;
@DECL = sort { length($b) <=> length($a) } @DECL; # A host or store name may be a password prefix.
local $/; my $in = <STDIN>; $in = '' unless defined $in;
my %SENSITIVE = map { $_ => 1 } qw(token secret password passwd pwd passphrase key session cookie auth authorization credential private dsn url uri jwt bearer otp pin sig signature);
my $STEM = qr/token|secret|passw|apikey|accesskey|privatekey|sessionid|sessid|csrf|xsrf|credential|connectionstring|recoverycode|verificationcode|backupcode/;
my $ONE_TIME = qr/reset|confirm|verif|invit|magic|recover|activat|callback/;
# 0: public key; 1: fully sensitive; 2: URL-only key eligible for partial masking.
sub sensitive_key { my $k = shift; $k =~ s/(?<=[a-z0-9])(?=[A-Z])/_/g; $k =~ s/(?<=[A-Z])(?=[A-Z][a-z])/_/g;
    my @seg = map { my $s = $_; $s =~ s/(?<!s)s$// if length($s) > 3; $s } grep { length } split /[^A-Za-z0-9]+/, lc $k;
    my $flat = join('', @seg);
    return 1 if $flat =~ $STEM;
    return 0 unless grep { $SENSITIVE{$_} } @seg;
    return 1 if grep { $SENSITIVE{$_} && $_ ne 'url' && $_ ne 'uri' } @seg;
    return $flat =~ $ONE_TIME ? 1 : 2; }
# RFC 3986 components, with IPv6 literals checked by Perl's core Socket module.
# Invalid escapes, authority syntax or non-HTTP schemes keep the full mask.
my $URI_CHAR = qr/(?:[A-Za-z0-9._~!\$&'()*+,;=-]|%[0-9A-Fa-f]{2})/;
my $HTTP_URL = qr{
    \A (https?://) (?:((?:$URI_CHAR|:)*)@)?
    (\[[0-9A-Fa-f:.]+\]|\[v[0-9A-Fa-f]+\.[A-Za-z0-9._~!\$&'()*+,;=:-]+\]|$URI_CHAR+) (:([0-9]*))?
    ((?:/(?:$URI_CHAR|[:@/])*)?)
    (\?(?:$URI_CHAR|[:@/?])*)? (\#(?:$URI_CHAR|[:@/?])*)? \z
}ix;
sub scrub_url {
    my $url = shift;
    return '***' unless defined $url && !ref $url && $url =~ $HTTP_URL;
    my ($scheme, $userinfo, $host, $port, $number, $path, $query, $fragment) = ($1, $2, $3, $4, $5, $6, $7, $8);
    return '***' if defined $number && length($number) && $number > 65535;
    return '***' if $host =~ /^\[/ && $host !~ /^\[v/i && !inet_pton(AF_INET6, substr($host, 1, -1));
    return $scheme . (defined $userinfo ? '***@' : '') . $host . ($port // '') . $path
        . (defined $query ? '?***' : '') . (defined $fragment ? '#***' : '');
}
sub scrub_text { my $t = shift;
    $t =~ s/(bearer\s+)[A-Za-z0-9._~+\/=-]+/$1***/gi;
    $t =~ s/([?&;#][\w.%\[\]-]*?(?:token|key|secret|passw|pwd|auth|session|code|sig|credential)[\w.%\[\]-]*=)[^&\s"'#]+/$1***/gi;
    $t =~ s{(\b[a-z][a-z0-9+.-]*://[^:/?#\s"'@]*:)[^/?#\s"'@]+@}{$1***@}gi;
    for my $val (@DECL) { $t =~ s/\Q$val\E/***/g; }
    return $t; }
sub scrub { my $v = shift;
    if (!ref $v) { if (defined $v) { for my $val (@DECL) { $v =~ s/\Q$val\E/***/g; } } return $v; }
    if (ref $v eq 'HASH') { for my $k (keys %$v) {
        my $mode = sensitive_key($k);
        $v->{$k} = $mode == 1 ? '***' : scrub($mode == 2 ? scrub_url($v->{$k}) : $v->{$k});
    } }
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
