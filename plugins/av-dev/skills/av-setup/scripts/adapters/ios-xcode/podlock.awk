# podlock.awk - line reader for Podfile.lock as written by CocoaPods (used by adapter.sh).
#
# Reads the fixed YAML layout CocoaPods writes; not a general YAML parser.
# Prints TSV records (line = line number in Podfile.lock):
#   V line cocoapods_version           COCOAPODS: x.y.z (the CocoaPods version that wrote the lock)
#   K line                             PODFILE CHECKSUM present (the value is not printed)
#   P line name version                PODS: one locked pod or subspec
#   D line name requirement            DEPENDENCIES: one entry; requirement "" or "(= 1.0)"; "external" for "(from ...)"
#   R line repo count                  SPEC REPOS: one repo key (URL user info and query removed) and its pod count
#   S line name kind                   EXTERNAL SOURCES: pod name and source kind (git, path, podspec, http); values not printed
#   U line section                     a top-level section that is not read
#   E line message                     layout error: the file is not a Podfile.lock written by CocoaPods

function unq(s) { if (s ~ /^".*"$/ || s ~ /^'.*'$/) s = substr(s, 2, length(s) - 2); return s }
function clean(s) { gsub(/\t/, " ", s); return s }
function flushrepo() { if (repo != "") print "R\t" rline "\t" clean(repo) "\t" rcount; repo = "" }

BEGIN { sec = ""; seen = 0; sawpods = 0 }

{
  sub(/\r$/, "")
  if ($0 ~ /^[ \t]*$/) next
  if ($0 ~ /^[A-Z][A-Z ]*:/) {
    flushrepo()
    sec = $0; sub(/:.*$/, "", sec); val = $0; sub(/^[^:]*:[ \t]*/, "", val)
    seen++
    if (sec == "PODS") sawpods = 1
    else if (sec == "COCOAPODS") print "V\t" NR "\t" clean(val)
    else if (sec == "PODFILE CHECKSUM") print "K\t" NR
    else if (sec != "DEPENDENCIES" && sec != "SPEC REPOS" && sec != "EXTERNAL SOURCES" && sec != "SPEC CHECKSUMS" && sec != "CHECKOUT OPTIONS") print "U\t" NR "\t" clean(sec)
    next
  }
  if ($0 !~ /^[ \t]/) { print "E\t" NR "\tunexpected top-level line"; exit }
  if (sec == "PODS" && $0 ~ /^  - /) {
    t = $0; sub(/^  - /, "", t); sub(/:[ \t]*$/, "", t); t = unq(t)
    if (match(t, / \([^()]*\)$/)) print "P\t" NR "\t" clean(substr(t, 1, RSTART - 1)) "\t" clean(substr(t, RSTART + 2, RLENGTH - 3))
    else { print "E\t" NR "\tPODS entry without a version"; exit }
  } else if (sec == "DEPENDENCIES" && $0 ~ /^  - /) {
    t = $0; sub(/^  - /, "", t); t = unq(t)
    if (match(t, / \(from .*\)$/)) print "D\t" NR "\t" clean(substr(t, 1, RSTART - 1)) "\texternal"
    else if (match(t, / \([^()]*\)$/)) print "D\t" NR "\t" clean(substr(t, 1, RSTART - 1)) "\t" clean(substr(t, RSTART + 1))
    else print "D\t" NR "\t" clean(t) "\t"
  } else if (sec == "SPEC REPOS") {
    if ($0 ~ /^  [^ -]/) {
      flushrepo()
      repo = $0; sub(/^  /, "", repo); sub(/:[ \t]*$/, "", repo); repo = unq(repo)
      sub(/:\/\/[^\/]*@/, "://", repo); sub(/[?#].*$/, "", repo)
      rline = NR; rcount = 0
    } else if ($0 ~ /^    - /) rcount++
  } else if (sec == "EXTERNAL SOURCES") {
    if ($0 ~ /^  [^ ]/) { name = $0; sub(/^  /, "", name); sub(/:[ \t]*$/, "", name); name = unq(name) }
    else if ($0 ~ /^    :[a-z_]+:/) { k = $0; sub(/^    :/, "", k); sub(/:.*$/, "", k); if (k == "git" || k == "path" || k == "podspec" || k == "http") print "S\t" NR "\t" clean(name) "\t" k }
  }
}

END { flushrepo(); if (!sawpods) print "E\t" NR "\tno PODS section" }
