#!/usr/bin/env bash
# docs_lib.sh - helpers shared by check_refs.sh, check_names.sh and check_linerefs.sh.
# Sourced by those scripts, not run on its own.
#
#   docs_overlay_file <root>             prints <paths.overlays>/av-docs-sync.md when it exists
#                                        (paths.overlays from .ai/av.config.json, default .ai/overlays)
#   docs_section_items <file> <kind> <need_section>
#                                        prints backticked list items of an overlay section:
#                                        kind "names" = "Known false names" (Polish alias
#                                        "Znane falszywe nazwy", with or without diacritics),
#                                        kind "paths" = "Excluded docs paths" (Polish alias
#                                        "Wykluczone sciezki docs", with or without diacritics),
#                                        kind "known" = "Known false paths" (Polish alias
#                                        "Znane falszywe sciezki", with or without diacritics).
#                                        need_section 0 reads the whole file when it has no such section.
#                                        Names may contain non-ASCII letters (UTF-8 bytes).
#   docs_exclude_globs <root> <globs>    prints the --exclude globs (newline separated) and the
#                                        globs from the overlay section "Excluded docs paths"
#   docs_exclude <root> <globs_file> <count_file>
#                                        filters document paths (absolute or relative to root)
#                                        from stdin and writes the number of excluded ones.
#                                        Glob syntax like git pathspec :(glob), relative to root:
#                                        "*" and "?" do not cross "/", "**/" matches any number of
#                                        directories, a trailing "/**" everything inside. A glob
#                                        without "*" or "?" also matches everything under it.
#   docs_known_paths <root>              prints the entries of the overlay section "Known false paths":
#                                        "<doc>.md:<line>" (every path on that docs line) or
#                                        "<path or glob>" (that referenced path everywhere, glob
#                                        syntax as in docs_exclude; a ":<line>" suffix is dropped)
#   docs_known_match <known_file> <where> <path>...
#                                        prints the first entry that matches the finding at <where>
#                                        (<doc>:<line>) for any of the paths; code 1 when none matches
#   docs_known_stale <known_file> <used_file> <docs_file> <index_file> <doc_lines>
#                                        prints "KNOWN_STALE <entry>" for entries not in <used_file>:
#                                        a path entry when a path in <index_file> matches it (the path
#                                        now exists), a <doc>:<line> entry (only with doc_lines 1) when
#                                        the document is in <docs_file> (it was checked)
# Requires: bash 3.2+, awk; jq optional.

docs_overlay_file() {
  local root="$1" overlays="" config_sh
  if [ -f "$root/.ai/av.config.json" ]; then
    config_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/av-verify/scripts/config.sh"
    if command -v jq >/dev/null 2>&1 && [ -f "$config_sh" ]; then
      overlays="$(bash "$config_sh" --root "$root" 2>/dev/null | jq -r '.paths.overlays // empty' 2>/dev/null)"
    elif command -v jq >/dev/null 2>&1; then
      overlays="$(jq -r '.paths.overlays // empty' "$root/.ai/av.config.json" 2>/dev/null)"
    else
      overlays="$(sed -n 's/.*"overlays"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.ai/av.config.json" | head -1)"
    fi
  fi
  [ -n "$overlays" ] || overlays=".ai/overlays"
  [ -f "$root/${overlays%/}/av-docs-sync.md" ] && printf '%s\n' "$root/${overlays%/}/av-docs-sync.md"
  return 0
}

docs_section_items() {
  # C locale: bytes >= 0x80 (UTF-8 sequences) count as letters of a name.
  LC_ALL=C awk -v kind="$2" -v need_section="$3" '
    BEGIN { name_re = "^[A-Za-z_\200-\377][A-Za-z0-9_\200-\377]*[*]?$" }
    function take(line,    t) {
      if (match(line, /^[ \t]*[-*][ \t]+`[^`]+`/)) {
        t = substr(line, RSTART, RLENGTH); sub(/^[^`]*`/, "", t); sub(/`$/, "", t)
      } else if (kind == "names") {
        t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t !~ name_re) return
      } else return
      if (kind == "names" && t !~ name_re) return
      gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t != "") print t
    }
    { lines[NR] = $0 }
    # Section headers: canonical English name or the Polish alias (references/localization.md).
    kind == "names" && /^#+[ \t]+(Known false names|Znane fa(ł|l)szywe nazwy)/ { sec = NR }
    kind == "paths" && /^#+[ \t]+(Excluded docs paths|Wykluczone (ś|s)cie(ż|z)ki docs)/ { sec = NR }
    kind == "known" && /^#+[ \t]+(Known false paths|Znane fa(ł|l)szywe (ś|s)cie(ż|z)ki)/ { sec = NR }
    END {
      if (sec) {
        for (i = sec + 1; i <= NR && lines[i] !~ /^#/; i++) take(lines[i])
      } else if (!need_section) {
        for (i = 1; i <= NR; i++) if (lines[i] !~ /^#/) take(lines[i])
      }
    }' "$1"
}

docs_exclude_globs() {
  local overlay
  printf '%s' "$2"
  overlay="$(docs_overlay_file "$1")"
  [ -z "$overlay" ] || docs_section_items "$overlay" paths 1
}

# glob_re: glob (git pathspec :(glob), relative to root) -> anchored regex; shared by the awk programs.
_docs_glob_awk='
    function glob_re(g,    r, i, c, n, wild) {
      while (substr(g, 1, 2) == "./") g = substr(g, 3)
      sub(/^\/+/, "", g); sub(/\/+$/, "", g)
      if (g == "") return ""
      wild = (g ~ /[*?]/)
      r = ""; n = length(g)
      for (i = 1; i <= n; i++) {
        c = substr(g, i, 1)
        if (c == "*" && substr(g, i + 1, 1) == "*") {
          if (substr(g, i + 2, 1) == "/") { r = r "(.*/)?"; i += 2 } else { r = r ".*"; i++ }
        } else if (c == "*") r = r "[^/]*"
        else if (c == "?") r = r "[^/]"
        else if (index("\\^[]", c) > 0) r = r "\\" c
        else if (index(".$|()+{}", c) > 0) r = r "[" c "]"
        else r = r c
      }
      return "^" r (wild ? "" : "(/.*)?") "$"
    }
    function known_doc_line(e) { return (e ~ /\.md:[0-9]+$/) }
    function known_path(e) { sub(/:[0-9]+(-[0-9]+)?$/, "", e); return e }
    function rel_path(p) {
      while (substr(p, 1, 2) == "./") p = substr(p, 3)
      sub(/\/+$/, "", p)
      return p
    }
'

docs_exclude() {
  LC_ALL=C awk -v root="$1" -v globs="$2" -v count_file="$3" "$_docs_glob_awk"'
    BEGIN {
      while ((getline g < globs) > 0) { g = glob_re(g); if (g != "") re[++n] = g }
      excluded = 0
    }
    {
      rel = $0
      if (index(rel, root "/") == 1) rel = substr(rel, length(root) + 2)
      while (sub(/\/\.\//, "/", rel)) ;
      while (substr(rel, 1, 2) == "./") rel = substr(rel, 3)
      for (i = 1; i <= n; i++) if (rel ~ re[i]) { excluded++; next }
      print
    }
    END { print excluded > count_file }'
}

docs_known_paths() {
  local overlay
  overlay="$(docs_overlay_file "$1")"
  [ -z "$overlay" ] || docs_section_items "$overlay" known 1
}

docs_known_match() {
  local known="$1" where="$2"
  shift 2
  printf '%s\n' "$@" | LC_ALL=C awk -v known="$known" -v where="$where" "$_docs_glob_awk"'
    { p = rel_path($0); if (p != "") paths[++np] = p }
    END {
      where = rel_path(where)
      while ((getline e < known) > 0) {
        if (known_doc_line(e)) { if (rel_path(e) == where) { print e; exit 0 } continue }
        re = glob_re(known_path(e))
        if (re == "") continue
        for (i = 1; i <= np; i++) if (paths[i] ~ re) { print e; exit 0 }
      }
      exit 1
    }'
}

docs_known_stale() {
  LC_ALL=C awk -v known="$1" -v used="$2" -v docs="$3" -v doc_lines="$5" "$_docs_glob_awk"'
    BEGIN {
      while ((getline e < used) > 0) was_used[e] = 1
      while ((getline d < docs) > 0) checked[rel_path(d)] = 1
      while ((getline e < known) > 0) {
        if ((e in was_used) || (e in seen)) continue
        seen[e] = 1
        if (known_doc_line(e)) {
          d = rel_path(e); sub(/:[0-9]+$/, "", d)
          if (doc_lines == 1 && (d in checked)) print "KNOWN_STALE " e
          continue
        }
        re = glob_re(known_path(e))
        if (re != "") { n++; entry[n] = e; regex[n] = re }
      }
    }
    {
      p = rel_path($0)
      for (i = 1; i <= n; i++) if (!(i in hit) && p ~ regex[i]) { hit[i] = 1; print "KNOWN_STALE " entry[i] }
    }' "$4"
}
