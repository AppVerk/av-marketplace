# manifest-facts.awk - facts of one AndroidManifest.xml. Used by adapter.sh.
# Not a validating XML parser: removes comments, CDATA, <?...?> and <!...> declarations, walks
# the tags with a stack and reports a mismatched, unclosed or unterminated tag as malformed.
# Prints only whitelisted attributes (package, uses-sdk levels, permission names, the class
# names of the application and of launcher activities) that pass a strict character set.
# Never prints meta-data names or values, intent data, or any other attribute.
# Env: AV_MOD (Gradle project path), AV_PATH (file path relative to ROOT). Var: maxperm.
# Output: TSV "M<TAB>mod<TAB>path<TAB>kind<TAB>fields...". Kinds:
#   package VALUE   uses_sdk KEY VALUE   permission NAME   permissions_total N
#   application NAME   component TAG COUNT   launcher NAME   meta_data COUNT
#   status ok|malformed REASON

function out(s) { printf "M\t%s\t%s\t%s\n", mod, path, s }
function safe(s, re) { return (s != "" && length(s) <= 200 && s ~ re) }
# attr TAG NAME - value of attribute NAME in TAG text, "" when absent
function attr(t, n,   p, v, q) {
  p = index(t, " " n "=")
  if (!p) { p = index(t, "\t" n "="); if (!p) { p = index(t, "\n" n "="); if (!p) return "" } }
  v = substr(t, p + length(n) + 2)
  q = substr(v, 1, 1)
  if (q != "\"" && q != "'") return ""
  v = substr(v, 2); p = index(v, q)
  return p ? substr(v, 1, p - 1) : ""
}
# cut S OP CL - S without every OP...CL span; an OP without CL marks the file malformed
function cut(s, op, cl,   p, e) {
  while ((p = index(s, op)) > 0) {
    e = index(substr(s, p + length(op)), cl)
    if (!e) { if (bad == "") bad = "unterminated " op; return substr(s, 1, p - 1) }
    s = substr(s, 1, p - 1) " " substr(s, p + length(op) + e - 1 + length(cl))
  }
  return s
}

BEGIN { mod = ENVIRON["AV_MOD"]; path = ENVIRON["AV_PATH"] }
{ sub(/\r$/, ""); doc = doc (NR > 1 ? "\n" : "") $0 }
END {
  bad = ""
  doc = cut(doc, "<!--", "-->")
  doc = cut(doc, "<![CDATA[", "]]>")
  doc = cut(doc, "<?", "?>")
  sp = 0; roots = 0; nperm = 0; nmeta = 0; inact = 0
  rest = doc
  while (bad == "" && (p = index(rest, "<")) > 0) {
    if (sp == 0 && roots > 0 && substr(rest, 1, p - 1) ~ /[^ \t\n]/) { bad = "text after the root element"; break }
    rest = substr(rest, p + 1)
    e = index(rest, ">")
    if (!e) { bad = "unterminated tag"; break }
    t = substr(rest, 1, e - 1); rest = substr(rest, e + 1)
    if (t ~ /^!/) continue
    if (t ~ /^\//) {
      n = substr(t, 2); sub(/[ \t\n].*$/, "", n)
      if (sp == 0) { bad = "closing tag </" n "> without an open tag"; break }
      if (stack[sp] != n) { bad = "closing tag </" n "> does not match <" stack[sp] ">"; break }
      if (n == "activity" || n == "activity-alias") { if (hasmain && haslauncher && safe(actname, "^[A-Za-z0-9._$]+$")) out("launcher\t" actname); inact = 0 }
      sp--; continue
    }
    self = (t ~ /\/[ \t\n]*$/)
    n = t; sub(/[ \t\n\/].*$/, "", n)
    if (n == "" || n !~ /^[A-Za-z_][A-Za-z0-9_.:-]*$/) { bad = "invalid tag name"; break }
    if (sp == 0) {
      roots++
      if (roots > 1) { bad = "more than one root element"; break }
      if (n != "manifest") { bad = "root element is <" n ">, not <manifest>"; break }
      v = attr(t, "package"); if (safe(v, "^[A-Za-z0-9._${}]+$")) out("package\t" v)
    }
    if (n == "uses-sdk") {
      v = attr(t, "android:minSdkVersion"); if (safe(v, "^[A-Za-z0-9._${}]+$")) out("uses_sdk\tminSdkVersion\t" v)
      v = attr(t, "android:targetSdkVersion"); if (safe(v, "^[A-Za-z0-9._${}]+$")) out("uses_sdk\ttargetSdkVersion\t" v)
    }
    if (n == "uses-permission" || n == "uses-permission-sdk-23") {
      v = attr(t, "android:name")
      if (safe(v, "^[A-Za-z0-9._]+$") && !seenp[v]++) { nperm++; if (nperm <= maxperm) out("permission\t" v) }
    }
    if (n == "application" && stack[sp] == "manifest") { v = attr(t, "android:name"); if (safe(v, "^[A-Za-z0-9._$]+$")) out("application\t" v) }
    if (stack[sp] == "application" && n ~ /^(activity|activity-alias|service|receiver|provider)$/) count[n]++
    if (n == "meta-data") nmeta++
    if (n == "activity" || n == "activity-alias") { inact = 1; actname = attr(t, "android:name"); hasmain = 0; haslauncher = 0 }
    if (inact && n == "action" && attr(t, "android:name") == "android.intent.action.MAIN") hasmain = 1
    if (inact && n == "category" && attr(t, "android:name") == "android.intent.category.LAUNCHER") haslauncher = 1
    if (self) { if (n == "activity" || n == "activity-alias") inact = 0; continue }
    stack[++sp] = n
  }
  if (bad == "" && roots == 0) bad = (doc ~ /[^ \t\n]/) ? "no root element" : "empty file"
  if (bad == "" && sp > 0) bad = "unclosed <" stack[sp] "> at end of file"
  if (bad == "" && rest ~ /[^ \t\n]/ && sp == 0) bad = "text after the root element"
  for (k in count) out("component\t" k "\t" count[k])
  out("meta_data\t" nmeta)
  out("permissions_total\t" nperm)
  out("status\t" (bad == "" ? "ok" : "malformed") "\t" bad)
}
