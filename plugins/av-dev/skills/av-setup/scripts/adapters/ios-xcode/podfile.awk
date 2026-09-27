# podfile.awk - line reader for a CocoaPods Podfile (used by adapter.sh).
#
# A Podfile is Ruby. This program does not run or parse Ruby: it reads one statement per line
# with literal string arguments and follows do/end blocks by keywords at the start of a line.
# Prints TSV records (line = line number in the Podfile):
#   P line platform version                 platform :ios, '15.0' (version empty when not given)
#   F line flag                             use_frameworks!, use_modular_headers!, inhibit_all_warnings!
#   T line kind name parent                 target / abstract_target block; parent = enclosing target or ""
#   D line name constraints options target  pod; constraints and options joined with "|"; target = enclosing
#                                           target, "" at top level, "def:<name>" inside a def
#   C line pod configurations               configuration names of a pod, joined with "|"
#   S line source                           source 'url'
#   J line project                          project 'path'
#   K line hook                             post_install, pre_install, post_integrate
#   X line reason                           a statement that is not read (dynamic pod name, load, eval, ...)
#   B line depth                            block balance at end of file (0 = all do/def/if blocks closed)
# Option values (:git, :path, :branch, ...) are never printed; only their names.

function clean(s) { gsub(/\t/, " ", s); return s }

# strip S - S without a trailing # comment outside quotes
function strip(s,    i, c, q, n) {
  if (index(s, "#") == 0) return s
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\") { i++; continue } if (c == q) q = ""; continue }
    if (c == "\"" || c == "'") { q = c; continue }
    if (c == "#") return substr(s, 1, i - 1)
  }
  return s
}

# str S - first literal string at the start of S ('x' or "x" without #{}), sets RESTS; "" when none
function str(s) {
  RESTS = s
  if (match(s, /^'[^']*'/) || match(s, /^"[^"]*"/)) {
    v = substr(s, 2, RLENGTH - 2); RESTS = substr(s, RLENGTH + 1)
    if (index(v, "#{")) return ""
    return v
  }
  return ""
}

function enclosing(   i) {
  for (i = sp; i >= 1; i--) if (kind[i] == "target" || kind[i] == "def") return (kind[i] == "def" ? "def:" : "") bname[i]
  return ""
}

function push(k, n) { sp++; kind[sp] = k; bname[sp] = n }

BEGIN { sp = 0; inbegin = 0 }

{
  sub(/\r$/, "")
  if (inbegin) { if ($0 ~ /^=end/) inbegin = 0; next }
  if ($0 ~ /^=begin/) { inbegin = 1; next }
  s = strip($0); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  if (s == "") next

  if (s ~ /^platform[ \t(]+:/) {
    t = s; sub(/^platform[ \t(]+:/, "", t)
    p = t; sub(/[^A-Za-z0-9_].*$/, "", p)
    rest = t; sub(/^[A-Za-z0-9_]+[ \t]*,?[ \t]*/, "", rest)
    print "P\t" NR "\t" p "\t" clean(str(rest))
  } else if (s ~ /^(use_frameworks|use_modular_headers|inhibit_all_warnings)!/) {
    f = s; sub(/!.*$/, "!", f); print "F\t" NR "\t" f
  } else if (s ~ /^source[ \t(]+['"]/) {
    t = s; sub(/^source[ \t(]+/, "", t); print "S\t" NR "\t" clean(str(t))
  } else if (s ~ /^(xcodeproj|project)[ \t(]+['"]/) {
    t = s; sub(/^(xcodeproj|project)[ \t(]+/, "", t); print "J\t" NR "\t" clean(str(t))
  } else if (s ~ /^(post_install|pre_install|post_integrate)[ \t(]/) {
    h = s; sub(/[ \t(].*$/, "", h); print "K\t" NR "\t" h
  } else if (s ~ /^pod[ \t(]/) {
    t = s; sub(/^pod[ \t(]+/, "", t)
    n = str(t)
    if (n == "") print "X\t" NR "\tpod without a literal name"
    else {
      rest = RESTS; cons = ""; opts = ""; confs = ""
      while (rest != "") {
        sub(/^[ \t]*,[ \t]*/, "", rest)
        if (match(rest, /^'[^']*'|^"[^"]*"/)) {
          v = str(rest); rest = RESTS
          if (v != "") cons = cons (cons == "" ? "" : "|") v
          continue
        }
        break
      }
      o = rest
      while (o != "") {
        sub(/^[ \t,]+/, "", o)
        if (o == "") break
        c1 = substr(o, 1, 1)
        if (c1 == "'" || c1 == "\"") { e = index(substr(o, 2), c1); o = (e ? substr(o, e + 2) : ""); continue }
        if (c1 == "[") { e = index(o, "]"); o = (e ? substr(o, e + 1) : ""); continue }
        if (c1 == "{") { e = index(o, "}"); o = (e ? substr(o, e + 1) : ""); continue }
        if (!match(o, /^:?[A-Za-z_]+[ \t]*=>/) && !match(o, /^[A-Za-z_]+:[ \t]/)) { o = substr(o, 2); continue }
        k = substr(o, 1, RLENGTH); o = substr(o, RLENGTH + 1)
        gsub(/[: \t=>]/, "", k)
        opts = opts (opts == "" ? "" : "|") k
        if (k == "configurations" || k == "configuration") {
          c = o; sub(/^[ \t]*/, "", c)
          if (substr(c, 1, 1) == "[") { e = index(c, "]"); c = (e ? substr(c, 2, e - 2) : substr(c, 2)) }
          else if (match(c, /^'[^']*'|^"[^"]*"/)) c = substr(c, 1, RLENGTH)
          else c = ""
          m = split(c, parts, ",")
          for (i = 1; i <= m; i++) { v = parts[i]; gsub(/^[ \t]+|[ \t]+$/, "", v); v = str(v); if (v != "") confs = confs (confs == "" ? "" : "|") v }
        }
      }
      print "D\t" NR "\t" clean(n) "\t" clean(cons) "\t" clean(opts) "\t" clean(enclosing())
      if (confs != "") print "C\t" NR "\t" clean(n) "\t" clean(confs)
      if (s ~ /[,\\]$/) print "X\t" NR "\tpod statement continues on the next line; its further constraints and options are not read"
    }
  } else if (s ~ /^(target|abstract_target)[ \t(]+/) {
    k = s; sub(/[ \t(].*$/, "", k)
    t = s; sub(/^(target|abstract_target)[ \t(]+/, "", t)
    n = str(t)
    if (n == "") { if (t ~ /^:/) { n = t; sub(/^:/, "", n); sub(/[^A-Za-z0-9_].*$/, "", n) } }
    if (n == "") print "X\t" NR "\t" k " without a literal name"
    print "T\t" NR "\t" k "\t" clean(n) "\t" clean(enclosing())
  } else if (s ~ /^(load|eval|instance_eval|require|require_relative)[ \t(]/) {
    w = s; sub(/[ \t(].*$/, "", w); print "X\t" NR "\t" w " is not followed"
  }

  if (s ~ /^def[ \t]/) { d = s; sub(/^def[ \t]+/, "", d); sub(/[^A-Za-z0-9_?!].*$/, "", d); push("def", d) }
  else if (s ~ /^(if|unless|case|while|until|begin)([ \t(]|$)/) push("other", "")
  else if (s ~ /[ \t]do([ \t]*\|[^|]*\|)?$/ || s ~ /^do([ \t]|$)/) {
    if (s ~ /^(target|abstract_target)[ \t(]/) push("target", n)
    else push("other", "")
  }
  if (s ~ /^end([ \t.;)]|$)/) { if (sp > 0) sp--; else { print "X\t" NR "\tend without an open block"; } }
}

END { print "B\t" NR "\t" sp }
