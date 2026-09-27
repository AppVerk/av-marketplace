# toml-facts.awk - entries of one Gradle version catalog (*.versions.toml). Used by adapter.sh.
# Not a full TOML parser: accepts the shapes a version catalog uses (tables [versions],
# [libraries], [bundles], [plugins], one "key = value" per line, inline tables, arrays that may
# span lines, # comments) and reports every other line as "bad". Keys that look like secrets are
# counted as redacted and their values are never printed; values pass a strict character set.
# Env: AV_PATH (file path relative to ROOT).
# Output: TSV "T<TAB><TAB>path<TAB>kind<TAB>fields...". Kinds:
#   version KEY VALUE LINE           library KEY MODULE VERSION VERSION_REF LINE
#   plugin KEY ID VERSION VERSION_REF LINE    bundle KEY MEMBERS LINE
#   section NAME LINE (tables outside the 4 catalog tables)   bad LINE REASON   redacted COUNT

function out(s) { printf "T\t\t%s\t%s\n", path, s }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function safe(s, re) { return (s != "" && length(s) <= 160 && s ~ re) }
function bad(ln, why) { out("bad\t" ln "\t" why) }
# strip S - S without a trailing # comment (outside strings); sets open = 1 for an unterminated string
function strip(s,   i, c, q, r) {
  r = ""; q = ""; open = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { r = r c; if (c == "\\" && q == "\"") { r = r substr(s, i + 1, 1); i++; continue } if (c == q) q = ""; continue }
    if (c == "#") break
    if (c == "\"" || c == "'") q = c
    r = r c
  }
  if (q != "") open = 1
  return trim(r)
}
function unq(s) { s = trim(s); if (s ~ /^".*"$/ || s ~ /^'.*'$/) return substr(s, 2, length(s) - 2); return s }
# field T K - value of key K inside inline table T ("{ a = "x", b.c = "y" }"), "" when absent
function field(t, k,   n, parts, i, kv, key) {
  t = trim(t); sub(/^\{/, "", t); sub(/\}$/, "", t)
  n = split(t, parts, ",")
  for (i = 1; i <= n; i++) {
    kv = parts[i]; key = kv; sub(/=.*$/, "", key); key = unq(key)
    if (key == k) { sub(/^[^=]*=/, "", kv); kv = trim(kv); if (kv ~ /^\{/) return "{"; return unq(kv) }
  }
  return ""
}
# rich T - version from a rich version table { strictly/require/prefer = "x" }
function rich(t,   v) { v = field(t, "strictly"); if (v == "") v = field(t, "require"); if (v == "") v = field(t, "prefer"); return v }

BEGIN { path = ENVIRON["AV_PATH"]; VER ="^[][A-Za-z0-9._+(),-]+$"; sec = ""; redacted = 0; arr = 0 }
{
  raw = $0; sub(/\r$/, "", raw)
  s = strip(raw)
  if (open) { bad(NR, "unterminated string"); next }
  if (arr) {
    members += gsub(/"[^"]*"/, "&", s)
    if (s ~ /\]/) { arr = 0; if (!skipk) out("bundle\t" akey "\t" members "\t" aln) }
    next
  }
  if (s == "") next
  if (s ~ /^\[[^]]*\]$/) {
    sec = trim(substr(s, 2, length(s) - 2))
    if (seen[sec]++) bad(NR, "table [" sec "] defined twice")
    if (sec !~ /^(versions|libraries|bundles|plugins)$/) out("section\t" sec "\t" NR)
    next
  }
  if (s !~ /^("[^"]+"|'[^']+'|[A-Za-z0-9_.-]+)[ \t]*=/) { bad(NR, "not a key = value line"); next }
  key = s; sub(/[ \t]*=.*$/, "", key); key = unq(key)
  val = s; sub(/^[^=]*=[ \t]*/, "", val); val = trim(val)
  if (val == "") { bad(NR, "empty value"); next }
  if (dup[sec SUBSEP key]++) { bad(NR, "key " key " defined twice in [" sec "]"); next }
  skipk = (tolower(key) ~ /pass(word|wd)?|secret|token|api_?key|credential/)
  if (skipk) redacted++
  if (sec == "bundles") {
    if (val !~ /^\[/) { bad(NR, "bundle is not an array"); next }
    members = gsub(/"[^"]*"/, "&", val)
    if (val ~ /\]$/) { if (!skipk) out("bundle\t" key "\t" members "\t" NR) } else { arr = 1; akey = key; aln = NR }
    next
  }
  if (val ~ /^\{/ && val !~ /\}$/) { bad(NR, "inline table does not end on the same line"); next }
  if (val !~ /^\{/ && val !~ /^"[^"]*"$/ && val !~ /^'[^']*'$/) { bad(NR, "value is not a string or an inline table"); next }
  if (skipk) next
  if (sec == "versions") {
    v = (val ~ /^\{/) ? rich(val) : unq(val)
    out("version\t" key "\t" (safe(v, VER) ? v : "") "\t" NR)
  } else if (sec == "libraries") {
    if (val ~ /^\{/) {
      m = field(val, "module"); if (m == "" && field(val, "group") != "") m = field(val, "group") ":" field(val, "name")
      v = field(val, "version"); if (v == "{") v = ""
      r = field(val, "version.ref"); if (r == "" && val ~ /version[ \t]*=[ \t]*\{/) { t = val; sub(/^.*version[ \t]*=[ \t]*/, "", t); sub(/\}.*$/, "}", t); r = field(t, "ref"); if (r == "") v = rich(t) }
    } else {
      m = unq(val); v = ""; r = ""
      if (split(m, parts, ":") >= 3) { v = parts[3]; m = parts[1] ":" parts[2] }
    }
    if (!safe(m, "^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$")) { bad(NR, "library without a group:name module"); next }
    if (!safe(v, VER)) v = ""
    if (!safe(r, "^[A-Za-z0-9_.-]+$")) r = ""
    out("library\t" key "\t" m "\t" v "\t" r "\t" NR)
  } else if (sec == "plugins") {
    if (val ~ /^\{/) {
      id = field(val, "id"); v = field(val, "version"); if (v == "{") v = ""
      r = field(val, "version.ref"); if (r == "" && val ~ /version[ \t]*=[ \t]*\{/) { t = val; sub(/^.*version[ \t]*=[ \t]*/, "", t); sub(/\}.*$/, "}", t); r = field(t, "ref") }
    } else { id = unq(val); v = ""; r = ""; if (split(id, parts, ":") == 2) { id = parts[1]; v = parts[2] } }
    if (!safe(id, "^[A-Za-z0-9._-]+$")) { bad(NR, "plugin without an id"); next }
    if (!safe(v, "^[A-Za-z0-9._+-]+$")) v = ""
    if (!safe(r, "^[A-Za-z0-9_.-]+$")) r = ""
    out("plugin\t" key "\t" id "\t" v "\t" r "\t" NR)
  } else if (sec == "") bad(NR, "key outside a table")
}
END {
  if (arr) bad(aln, "array not closed at end of file")
  out("redacted\t" redacted)
}
