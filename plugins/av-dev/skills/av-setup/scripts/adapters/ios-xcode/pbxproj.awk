# pbxproj.awk - structure reader for one Xcode project.pbxproj (used by adapter.sh).
#
# Reads the OpenStep plist that Xcode writes: a "// !$*UTF8*$!" header, then nested { } and ( ).
# Tracks nesting depth outside quoted strings and /* */ comments; does not evaluate build settings.
# Prints TSV records (tabs inside values become spaces):
#   H key value line            root-level scalar (archiveVersion, objectVersion, rootObject)
#   O id isa line               every object in "objects", single-line objects included
#   A id key value line         object scalar, kept isa only (XCBuildConfiguration: name and baseConfigurationReference*,
#                               which covers the Xcode 16 ...Anchor and ...RelativePath keys)
#   L id key item line          item of an object list, kept isa only
#   D id parent.key value line  scalar inside an object dictionary, kept isa only;
#                               XCBuildConfiguration buildSettings only for keys in SETTINGS
#   E line message              structure error: the file is malformed and no other record is trusted
# Values of other build settings never leave this program.

BEGIN {
  n = split("PBXProject PBXNativeTarget PBXAggregateTarget PBXLegacyTarget XCConfigurationList XCBuildConfiguration XCRemoteSwiftPackageReference XCLocalSwiftPackageReference XCSwiftPackageProductDependency", k, " ")
  for (i = 1; i <= n; i++) keep[k[i]] = 1
  n = split("IPHONEOS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET SWIFT_VERSION SDKROOT SUPPORTED_PLATFORMS TARGETED_DEVICE_FAMILY", k, " ")
  for (i = 1; i <= n; i++) setting[k[i]] = 1
  depth = 0; incomment = 0; bad = 0; hasobjects = 0; inobjects = 0; root = ""; cur = ""
}

function fail(msg) { if (!bad) print "E\t" NR "\t" msg; bad = 1; exit }
function clean(s) { gsub(/\t/, " ", s); return s }

# unq S - value of a quoted string with \" and \\ unescaped; bare tokens unchanged
function unq(s,    out, i, c, n) {
  if (s !~ /^".*"$/) return s
  s = substr(s, 2, length(s) - 2)
  if (index(s, "\\") == 0) return s
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < n) { i++; c = substr(s, i, 1); if (c == "n") c = " "; else if (c == "t") c = " " }
    out = out c
  }
  return out
}

# scan S - sets NC (S without comments, strings kept) and BARE (S without comments and strings)
function scan(s,    i, c, n, out, bare, instr, t) {
  t = s; sub(/^[ \t]+/, "", t)
  if (!incomment && substr(t, 1, 2) == "//") { NC = ""; BARE = ""; return }
  if (!incomment && index(s, "\"") == 0 && index(s, "/*") == 0) { NC = s; BARE = s; return }
  n = length(s); out = ""; bare = ""; instr = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (incomment) { if (c == "*" && substr(s, i + 1, 1) == "/") { incomment = 0; i++ } continue }
    if (instr) {
      out = out c
      if (c == "\\") { i++; out = out substr(s, i, 1); continue }
      if (c == "\"") instr = 0
      continue
    }
    if (c == "\"") { instr = 1; out = out c; continue }
    if (c == "/" && substr(s, i + 1, 1) == "*") { incomment = 1; i++; continue }
    out = out c; bare = bare c
  }
  if (instr) fail("unterminated quoted string")
  NC = out; BARE = bare
}

# keyval S - splits "key = rest" into KEY and REST; returns 0 when S has no such form
function keyval(s,    j) {
  KEY = ""; REST = ""
  if (substr(s, 1, 1) == "\"") {
    if (!match(s, /^"([^"\\]|\\.)*"/)) return 0
    KEY = unq(substr(s, 1, RLENGTH)); s = substr(s, RLENGTH + 1)
  } else {
    if (!match(s, /^[^ \t=;{}()]+/)) return 0
    KEY = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
  }
  if (!match(s, /^[ \t]*=[ \t]*/)) return 0
  REST = substr(s, RLENGTH + 1)
  return 1
}

function scalar(s) { sub(/[ \t]*;[ \t]*$/, "", s); sub(/^[ \t]+/, "", s); return clean(unq(s)) }
function add(rec) { buf = buf rec "\n" }

NR == 1 {
  sub(/\r$/, "")
  if ($0 !~ /^\/\/ !\$\*UTF8\*\$!/) fail("missing // !$*UTF8*$! header; only the plist format written by Xcode is read")
  next
}

{
  sub(/\r$/, "")
  scan($0)
  t = BARE; o = gsub(/[{(]/, "", t)
  t = BARE; c = gsub(/[})]/, "", t)
  before = depth; depth += o - c
  if (depth < 0) fail("unbalanced braces: more closing than opening")
  line = NC; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
  if (line == "") next

  if (before == 1) {
    if (keyval(line)) {
      if (KEY == "objects" && REST ~ /^\{/) { hasobjects = 1; inobjects = (depth == 2) }
      else if (REST !~ /^[{(]/) { v = scalar(REST); print "H\t" KEY "\t" v "\t" NR; if (KEY == "rootObject") root = v }
    }
  } else if (before == 2 && inobjects) {
    if (keyval(line) && REST ~ /^\{/) {
      if (depth == 2) {
        isa = "?"
        if (match(line, /isa[ \t]*=[ \t]*[A-Za-z0-9_]+/)) { isa = substr(line, RSTART, RLENGTH); sub(/^isa[ \t]*=[ \t]*/, "", isa) }
        print "O\t" KEY "\t" isa "\t" NR
      } else { cur = KEY; cisa = ""; cline = NR; buf = ""; ckey = "" }
    }
  } else if (before == 3 && cur != "") {
    if (keyval(line)) {
      if (REST ~ /^\(/) {
        if (depth > before) { ckey = KEY; ckind = "L" }
        else {
          items = REST; sub(/^\(/, "", items); sub(/\)[ \t]*;?[ \t]*$/, "", items)
          m = split(items, it, ",")
          for (i = 1; i <= m; i++) { v = it[i]; gsub(/^[ \t]+|[ \t]+$/, "", v); if (v != "") add("L\t" cur "\t" KEY "\t" clean(unq(v)) "\t" NR) }
        }
      } else if (REST ~ /^\{/) {
        if (depth > before) { ckey = KEY; ckind = "D" }
      } else {
        v = scalar(REST)
        if (KEY == "isa") cisa = v
        add("A\t" cur "\t" KEY "\t" v "\t" NR)
      }
    }
  } else if (before == 4 && cur != "" && ckey != "") {
    if (ckind == "L") {
      if (line !~ /^\)/) { v = line; sub(/[ \t]*,[ \t]*$/, "", v); if (v != "") add("L\t" cur "\t" ckey "\t" clean(unq(v)) "\t" NR) }
    } else if (depth == before && keyval(line) && REST !~ /^[{(]/) {
      add("D\t" cur "\t" ckey "." KEY "\t" scalar(REST) "\t" NR)
    }
  }

  if (cur != "" && depth <= 3) ckey = ""
  if (cur != "" && depth <= 2) {
    if (cisa in keep) {
      m = split(buf, rows, "\n")
      for (i = 1; i <= m; i++) {
        if (rows[i] == "") continue
        split(rows[i], f, "\t")
        if (cisa == "XCBuildConfiguration") {
          if (f[1] == "A" && f[3] != "name" && f[3] !~ /^baseConfigurationReference/) continue
          if (f[1] == "L") continue
          if (f[1] == "D") { s = f[3]; if (s !~ /^buildSettings\./) continue; sub(/^buildSettings\./, "", s); if (!(s in setting)) continue }
        }
        print rows[i]
      }
    }
    print "O\t" cur "\t" (cisa == "" ? "?" : cisa) "\t" cline
    cur = ""; buf = ""
  }
  if (inobjects && depth <= 1) inobjects = 0
}

END {
  if (bad) exit
  if (NR == 0) { print "E\t0\tempty file"; exit }
  if (incomment) { print "E\t" NR "\tunterminated /* comment"; exit }
  if (depth != 0) { print "E\t" NR "\tunbalanced braces: " depth " not closed at end of file"; exit }
  if (!hasobjects) { print "E\t" NR "\tno objects dictionary"; exit }
  if (root == "") { print "E\t" NR "\tno rootObject"; exit }
}
