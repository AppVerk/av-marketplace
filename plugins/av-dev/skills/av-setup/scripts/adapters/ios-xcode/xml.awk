# xml.awk - element reader for small Xcode XML files: contents.xcworkspacedata and *.xcscheme (used by adapter.sh).
#
# Not a general XML parser: no DTD, no namespaces, no CDATA. Splits the file on "<" and tracks the element stack.
# Args: -v attrs="a,b,c" - attribute names to print; values of other attributes never leave this program.
# Prints TSV records (tabs and newlines inside values become spaces):
#   T seq path line        start of an element; path = element names from the root joined with "/"
#   A seq name value       whitelisted attribute of element seq (entities &amp; &lt; &gt; &quot; &apos; &#10; decoded)
#   E line message         structure error: the file is malformed and no other record is trusted
BEGIN {
  RS = "<"
  n = split(attrs, a, ",")
  for (i = 1; i <= n; i++) want[a[i]] = 1
  sp = 0; seq = 0; line = 1; roots = 0; bad = 0; incomment = 0
}

function fail(msg) { if (!bad) print "E\t" line "\t" msg; bad = 1; exit }
function decode(s) {
  gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "'", s)
  gsub(/&#10;|&#13;|&#9;/, " ", s); gsub(/&amp;/, "\\&", s); gsub(/[\t\n\r]/, " ", s)
  return s
}
function path(   i, s) { s = ""; for (i = 1; i <= sp; i++) s = s (i > 1 ? "/" : "") st[i]; return s }

{
  rec = $0; start = line
  t = rec; line += gsub(/\n/, "", t)
  if (NR == 1) { if (rec ~ /[^ \t\r\n\357\273\277]/) fail("text before the first element"); next }
  if (incomment) { if (index(rec, "-->")) incomment = 0; next }
  if (substr(rec, 1, 3) == "!--") { if (!index(rec, "-->")) incomment = 1; next }
  if (substr(rec, 1, 1) == "?" || substr(rec, 1, 1) == "!") next
  gt = index(rec, ">")
  if (gt == 0) fail("element without closing \">\"")
  tag = substr(rec, 1, gt - 1)
  if (substr(tag, 1, 1) == "/") {
    name = substr(tag, 2); sub(/[ \t\r\n]+$/, "", name)
    if (sp == 0 || st[sp] != name) fail("closing </" name "> does not match the open element")
    sp--
    next
  }
  self = (tag ~ /\/[ \t\r\n]*$/)
  if (self) sub(/\/[ \t\r\n]*$/, "", tag)
  if (!match(tag, /^[A-Za-z_][A-Za-z0-9_.:-]*/)) fail("element without a name")
  name = substr(tag, 1, RLENGTH); rest = substr(tag, RLENGTH + 1)
  if (sp == 0) { roots++; if (roots > 1) fail("more than one root element") }
  st[++sp] = name; seq++
  print "T\t" seq "\t" path() "\t" start
  while (match(rest, /[A-Za-z_][A-Za-z0-9_.:-]*[ \t\r\n]*=[ \t\r\n]*("[^"]*"|'[^']*')/)) {
    kv = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
    k = kv; sub(/[ \t\r\n]*=.*$/, "", k)
    v = kv; sub(/^[^=]*=[ \t\r\n]*/, "", v); v = substr(v, 2, length(v) - 2)
    if (k in want) print "A\t" seq "\t" k "\t" decode(v)
  }
  if (self) sp--
}

END {
  if (bad) exit
  if (incomment) { print "E\t" line "\tunterminated <!-- comment"; exit }
  if (roots == 0) { print "E\t" line "\tno root element"; exit }
  if (sp != 0) { print "E\t" line "\telement <" st[sp] "> not closed at end of file"; exit }
}
