# gradle-facts.awk - text facts of one Gradle script (settings or build, Groovy or Kotlin DSL).
# Used by adapter.sh. Not a Groovy or Kotlin parser: splits code into statements at braces,
# semicolons and line ends (outside strings and comments), keeps a stack of block names and
# matches a fixed whitelist of statement shapes. Values are copied only from whitelisted slots
# and only when they pass a strict character set; statements that look like secrets, and every
# statement inside signingConfigs or credentials blocks, are counted as redacted and never printed.
# Env: AV_MOD (Gradle project path, empty for settings), AV_PATH (file path relative to ROOT). Var: maxmarkers.
# Output: TSV records "G<TAB>mod<TAB>path<TAB>kind<TAB>fields...". An android VALUE that starts
# with "=" is an expression, not a literal; an empty VALUE or NOTATION did not pass the checks.
# "a" + "b" is joined into one literal; "a" + expr is an expression (a dep NOTATION or plugin
# VERSION starting with "=" too), so a concatenated version never prints as a wrong literal. Kinds:
#   plugin ID VERSION VIA APPLIED LINE   dep CONF KIND NOTATION LINE   android KEY VALUE LINE
#   feature KEY VALUE LINE       include PROJECT LINE          include_build PATH LINE
#   root_name VALUE LINE         catalog NAME FROM LINE        ext NAME VALUE LINE
#   dir_override PROJECT LINE    marker NAME LINE              redacted COUNT
#   markers_total COUNT          status ok|malformed REASON

function out(s) { printf "G\t%s\t%s\t%s\n", mod, path, s }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function safe(s, re) { return (s != "" && length(s) <= 160 && s ~ re) }
# firstq S - contents of the first '...' or "..." literal in S, "" when none; qfound is 1 when a literal was found
function firstq(s,   i, c, q, j) {
  qfound = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\"" || c == "'") {
      q = c
      for (j = i + 1; j <= length(s); j++) {
        c = substr(s, j, 1)
        if (c == "\\") { j++; continue }
        if (c == q) { qfound = 1; qrest = substr(s, j + 1); return substr(s, i + 1, j - i - 1) }
      }
      return ""
    }
  }
  return ""
}
# allq S - every quoted literal in S joined by SUBSEP; qcount = how many
function allq(s,   r, v) {
  r = ""; qcount = 0
  while (1) {
    v = firstq(s)
    if (!qfound) break
    r = (qcount ? r SUBSEP : "") v; qcount++; s = qrest
  }
  return r
}
# lit_chain S - S starts with a literal: the text of "a" + "b" + ... joined; chain_rest is what
# follows the chain, chain_expr is 1 when an operand is not a literal (the result then keeps
# that operand as text, e.g. 1.0+suffix, and is an expression, never a declared value)
function lit_chain(s,   r, l, t) {
  chain_expr = 0; chain_rest = s
  l = firstq(s); if (!qfound) return ""
  r = l; t = qrest
  while (t ~ /^[ \t]*\+[ \t]*/) {
    sub(/^[ \t]*\+[ \t]*/, "", t)
    if (t ~ /^["']/) { l = firstq(t); if (!qfound) { chain_expr = 1; break } r = r l; t = qrest; continue }
    if (!match(t, /^[A-Za-z0-9_.${}]+/)) { chain_expr = 1; break }
    chain_expr = 1; r = r "+" substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
    if (match(t, /^\([^()]*\)/)) { r = r substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH) }
  }
  chain_rest = t
  return r
}
# blank S - S with the contents of string literals removed, for keyword checks outside strings
function blank(s,   i, c, q, r) {
  r = ""; q = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\") { i++; continue } if (c == q) { q = ""; r = r c } continue }
    if (c == "\"" || c == "'") q = c
    r = r c
  }
  return r
}
# plugin_version T - the version text after "version": a literal, a joined chain, or "=" + expression
function plugin_version(t,   v) {
  if (!match(t, /["']/)) return ""
  v = lit_chain(substr(t, RSTART))
  if (!qfound) return ""
  return (chain_expr ? "=" v : v)
}
function in_block(name,   i) { for (i = 1; i <= sp; i++) if (stack[i] == name) return 1; return 0 }
function marker(name, ln) {
  if (seenm[name]) return
  seenm[name] = 1; mtotal++
  if (mtotal <= maxmarkers) out("marker\t" name "\t" ln)
}
# value KEY-LESS TEXT - literal value or an expression that passes the character set
function value(v,   l) {
  v = trim(v); sub(/^=[ \t]*/, "", v); v = trim(v)
  if (v ~ /^\(.*\)$/) { v = substr(v, 2, length(v) - 2); v = trim(v) }
  if (v ~ /^["']/) {
    l = lit_chain(v)
    if (!qfound || chain_rest !~ /^[ \t]*$/ || !safe(l, "^[A-Za-z0-9._${}():+-]+$")) return ""
    return (chain_expr ? "=" l : l)
  }
  if (v ~ /^[0-9]+$/) return v
  if (safe(v,"^[A-Za-z0-9._$(){}]+$")) return "=" v
  return ""
}

# MARK: statements

function stmt(s, ln,   b, low, top, parent, id, ver, via, conf, rest, rb, kind, v, n, i, parts, k) {
  s = trim(s)
  if (s == "") return
  b = blank(s); low = tolower(b)
  top = (sp > 0) ? stack[sp] : ""; parent = (sp > 1) ? stack[sp - 1] : ""
  if (in_block("signingConfigs") || in_block("credentials") || low ~ /pass(word|wd)?|secret|token|api_?key|credential|keyalias|storefile|signingconfig|keystore/ \
      || b ~ /^(buildConfigField|resValue|manifestPlaceholders)/) { redacted++; return }

  if (b ~ /^apply[ (]/ && b ~ /from/) marker("script_plugin", ln)
  if (b ~ /(^|[^A-Za-z0-9_])(subprojects|allprojects)([^A-Za-z0-9_]|$)/) marker("cross_project_config", ln)
  if (b ~ /^(if|else)([ (]|$)|[ }]else[ {]/) marker("conditional", ln)
  if (b ~ /\.each[A-Za-z]*([ ({]|$)|forEach|^for[ (]/) marker("loop", ln)
  if (b ~ /getenv|environmentVariable/) marker("env_access", ln)
  if (b ~ /findProperty|hasProperty|gradleProperty|project\.property|providers\./) marker("property_access", ln)
  if (b ~ /afterEvaluate/) marker("after_evaluate", ln)
  if (b ~ /^productFlavors/) marker("product_flavors", ln)
  if (b ~ /^flavorDimensions/) marker("product_flavors", ln)

  # plugins
  if (top == "plugins") {
    id = ""; ver = ""; via = ""
    if (b ~ /^id[ (]/) { id = firstq(s); via = "id"; if (qrest ~ /version/) { v = qrest; sub(/^.*version[ (]*/, "", v); ver = plugin_version(v) } }
    else if (b ~ /^alias[ (]/) { id = s; sub(/^alias[ (]*/, "", id); sub(/\).*$/, "", id); id = trim(id); via = "alias"
      if (s ~ /version/) marker("alias_version_override", ln) }
    else if (b ~ /^kotlin[ (]/) { id = firstq(s); if (id != "") id = "org.jetbrains.kotlin." id; via = "kotlin"; if (qrest ~ /version/) { v = qrest; sub(/^.*version[ (]*/, "", v); ver = plugin_version(v) } }
    else if (b ~ /^`[A-Za-z0-9._-]+`$/) { id = s; gsub(/`/, "", id); via = "id" }
    k = (b ~ /apply[ \t(]*false/) ? "false" : "true"
    if (id != "" && safe(id, "^[A-Za-z0-9._-]+$")) {
      if (!safe(ver, "^=?[A-Za-z0-9._${}()+-]+$")) ver = ""
      out("plugin\t" id "\t" ver "\t" via "\t" k "\t" ln)
    } else if (id != "") out("plugin\t\t\tunparsed\t" k "\t" ln)
    return
  }
  if (b ~ /^apply[ (]/ && b ~ /plugin/ && b !~ /from/) {
    id = firstq(s)
    if (safe(id, "^[A-Za-z0-9._-]+$")) out("plugin\t" id "\t\tapply\ttrue\t" ln)
    return
  }

  # settings
  if (mod == "" && b ~ /^include[ (]/ && b !~ /^includeBuild/) {
    v = allq(s)
    rest = b; gsub(/["'][^"']*["']/, "", rest); gsub(/[ \t(),]/, "", rest)
    if (qcount == 0 || rest != "include") marker("dynamic_include", ln)
    n = split(v, parts, SUBSEP)
    for (i = 1; i <= n; i++) {
      if (safe(parts[i], "^:?[A-Za-z0-9_.:-]+$")) out("include\t" (parts[i] ~ /^:/ ? "" : ":") parts[i] "\t" ln)
      else marker("dynamic_include", ln)
    }
    return
  }
  if (b ~ /^includeBuild[ (]/) {
    v = firstq(s)
    if (qfound && safe(v, "^[A-Za-z0-9_./ -]+$")) out("include_build\t" v "\t" ln); else marker("dynamic_include_build", ln)
    return
  }
  if (b ~ /^rootProject\.name[ =]/) { v = firstq(s); if (safe(v, "^[A-Za-z0-9 ._-]+$")) out("root_name\t" v "\t" ln); return }
  if (b ~ /^project\(.*\)\.projectDir/) { v = firstq(s); if (safe(v, "^:?[A-Za-z0-9_.:-]+$")) out("dir_override\t" (v ~ /^:/ ? "" : ":") v "\t" ln); else marker("dir_override", ln); return }
  if (top == "versionCatalogs" && b ~ /^create[ (]/) { v = firstq(s); if (safe(v, "^[A-Za-z0-9_]+$")) { out("catalog\t" v "\t\t" ln); lastcat = v }; return }
  if (b ~ /^from[ (]/ && in_block("versionCatalogs")) { v = firstq(s); if (!safe(v, "^[A-Za-z0-9_./ -]+$")) v = ""; out("catalog_from\t" lastcat "\t" v "\t" ln); return }

  # ext literals: ext { x = ... }, ext.x = ..., extra["x"] = ..., set("x", ...) inside ext
  n = ""
  if (top == "ext" && b ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/) { n = b; sub(/[ \t]*=.*$/, "", n); v = s; sub(/^[^=]*=/, "", v) }
  else if (b ~ /^(project\.|rootProject\.)?ext\.[A-Za-z_][A-Za-z0-9_]*[ \t]*=/) { n = b; sub(/^.*ext\./, "", n); sub(/[ \t]*=.*$/, "", n); v = s; sub(/^[^=]*=/, "", v) }
  else if (b ~ /^(val[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]+by[ \t]+extra\(/) { n = b; sub(/^val[ \t]+/, "", n); sub(/[ \t].*$/, "", n); v = s; sub(/^[^(]*\(/, "", v); sub(/\)[ \t]*$/, "", v) }
  else if (b ~ /^extra\[/) { n = firstq(s); v = s; sub(/^[^=]*=/, "", v) }
  if (n != "") {
    v = trim(v)
    if (v ~ /^["']/) { k = lit_chain(v); v = (qfound && !chain_expr && chain_rest ~ /^[ \t]*$/) ? k : "" }
    else if (v !~ /^[0-9]+$/) v = ""
    if (safe(n, "^[A-Za-z_][A-Za-z0-9_]*$") && safe(v, "^[A-Za-z0-9._+-]+$")) out("ext\t" n "\t" v "\t" ln)
    return
  }

  # android block
  if (in_block("android") && (top == "android" || top == "defaultConfig" || top == "compileOptions" || top == "kotlinOptions" || top == "compilerOptions")) {
    if (match(b, /^(namespace|applicationId|versionName|versionCode|compileSdk|compileSdkVersion|minSdk|minSdkVersion|targetSdk|targetSdkVersion|testInstrumentationRunner|sourceCompatibility|targetCompatibility|jvmTarget)([ \t=(]|$)/)) {
      k = b; sub(/[ \t=(].*$/, "", k)
      v = substr(s, length(k) + 1)
      if (k == "jvmTarget" && v ~ /set\(/) { sub(/^[^(]*\(/, "", v); sub(/\)[ \t]*$/, "", v) }
      v = value(v)
      out("android\t" k "\t" v "\t" ln)
      return
    }
  }
  if (b ~ /^jvmToolchain[ (]/) { v = s; sub(/^jvmToolchain[ (]*/, "", v); sub(/\)[ \t]*$/, "", v); v = trim(v); if (v ~ /^[0-9]+$/) out("android\tjvmToolchain\t" v "\t" ln); return }
  if (in_block("android") && (top == "buildFeatures" || top == "dataBinding" || top == "viewBinding")) {
    if (match(b, /^(compose|viewBinding|dataBinding|buildConfig|aidl|renderScript|resValues|shaders|enabled|isEnabled)([ \t=]|$)/)) {
      k = b; sub(/[ \t=].*$/, "", k); v = b; sub(/^[A-Za-z]+[ \t]*=?[ \t]*/, "", v); v = trim(v)
      if (k == "enabled" || k == "isEnabled") k = top
      if (v == "true" || v == "false") out("feature\t" k "\t" v "\t" ln)
    }
    return
  }

  # dependencies
  if (top == "dependencies") {
    if (!match(b, /^[A-Za-z_][A-Za-z0-9_]*([ \t(]|$)/)) return
    conf = b; sub(/[ \t(].*$/, "", conf)
    if (conf ~ /^(if|else|for|while|def|val|var|return|constraints|configurations|exclude|force|because|modules|components|apply|println|add|attributes|capabilities)$/) return
    rest = substr(s, length(conf) + 1)
    kind = "other"
    if (blank(rest) ~ /(enforcedPlatform|platform)\(/) { kind = "platform"; sub(/^[^"']*[Pp]latform\(/, "", rest) }
    rb = blank(rest)
    if (rb ~ /(^|[^A-Za-z0-9_.])project\(/) {
      v = rest; sub(/^[^"']*project\(/, "", v); v = firstq(v)
      out("dep\t" conf "\tproject\t" (safe(v, "^:[A-Za-z0-9_.:-]*$") ? v : "") "\t" ln); return
    }
    if (rb ~ /(^|[^A-Za-z0-9_])projects\.[A-Za-z0-9_.]+/) {
      v = rb; sub(/^.*projects\./, "projects.", v); sub(/[^A-Za-z0-9_.].*$/, "", v)
      out("dep\t" conf "\tproject\t" v "\t" ln); return
    }
    if (rb ~ /(^|[^A-Za-z0-9_])(files|fileTree)\(/) { out("dep\t" conf "\tfiles\t\t" ln); return }
    if (rb ~ /group[ \t]*[:=]/ && rb ~ /name[ \t]*[:=]/) {
      v = rest; sub(/^.*group[ \t]*[:=][ \t]*/, "", v); k = firstq(v)
      v = rest; sub(/^.*name[ \t]*[:=][ \t]*/, "", v); n = firstq(v)
      v = rest; if (v ~ /version[ \t]*[:=]/) { sub(/^.*version[ \t]*[:=][ \t]*/, "", v); v = firstq(v) } else v = ""
      v = k ":" n (v != "" ? ":" v : "")
      out("dep\t" conf "\t" (kind == "platform" ? "platform" : "coordinate") "\t" (safe(v, COORD) ? v : "") "\t" ln); return
    }
    if (match(rest, /["']/)) {
      v = lit_chain(substr(rest, RSTART))
      if (qfound) {
        if (chain_expr) v = (safe(v, COORD) && v ~ /:/ ? "=" v : "")
        else if (!(safe(v, COORD) && v ~ /:/)) v = ""
        out("dep\t" conf "\t" (kind == "platform" ? "platform" : "coordinate") "\t" v "\t" ln); return
      }
    }
    if (rb ~ /(^|[^A-Za-z0-9_])libs\.[A-Za-z0-9_.]+/) {
      v = rb; sub(/^.*libs\./, "libs.", v); sub(/[^A-Za-z0-9_.].*$/, "", v)
      if (v ~ /^libs\.bundles\./) kind = "bundle"; else if (kind != "platform") kind = "catalog"; else kind = "platform_catalog"
      out("dep\t" conf "\t" kind "\t" v "\t" ln); return
    }
    out("dep\t" conf "\t" kind "\t\t" ln)
    return
  }
}

# MARK: block header

function push(h, ln,   n) {
  n = trim(blank(h))
  sub(/->.*$/, "", n)
  while (n ~ /\)[ \t]*$/) if (!sub(/\([^()]*\)[ \t]*$/, "", n)) break
  n = trim(n); sub(/^.*[^A-Za-z0-9_]/, "", n)
  if (n == "") n = lastname
  stack[++sp] = n
}

# MARK: main

BEGIN { mod = ENVIRON["AV_MOD"]; path = ENVIRON["AV_PATH"]; COORD = "^[][A-Za-z0-9._:${}+@,() -]+$"; sp = 0; redacted = 0; mtotal = 0; incom = 0; bad = ""; seg = ""; segln = 0; paren = 0; lastname = "" }
{
  line = $0; sub(/\r$/, "", line)
  i = 1; L = length(line); q = ""
  while (i <= L) {
    c = substr(line, i, 1)
    if (incom) { if (substr(line, i, 2) == "*/") { incom = 0; i += 2 } else i++; continue }
    if (q != "") {
      seg = seg c
      if (c == "\\") { seg = seg substr(line, i + 1, 1); i += 2; continue }
      if (c == q) q = ""
      i++; continue
    }
    if (c == "\"" || c == "'") { q = c; if (seg !~ /[^ \t]/) segln = NR; seg = seg c; i++; continue }
    if (substr(line, i, 2) == "/*") { incom = 1; i += 2; continue }
    if (substr(line, i, 2) == "//") break
    if (c == "(") paren++
    if (c == ")") paren--
    if (c == "{") {
      h = seg; stmt(seg, segln); push(h, segln); seg = ""; paren = 0; i++; continue
    }
    if (c == "}") {
      stmt(seg, segln); seg = ""; paren = 0
      if (sp == 0) { if (bad == "") bad = "closing brace without an open block at line " NR } else sp--
      i++; continue
    }
    if (c == ";") { stmt(seg, segln); seg = ""; paren = 0; i++; continue }
    if (seg !~ /[^ \t]/ && c !~ /[ \t]/) segln = NR
    seg = seg c; i++
  }
  if (q != "" && bad == "") bad = "unterminated string at line " NR
  if (q != "") { seg = ""; paren = 0; q = "" }
  t = trim(seg)
  if (paren > 0 || t ~ /,$/ || t ~ /[=+]$/) { seg = seg " "; next }
  if (t != "") { tb = trim(blank(t)); sub(/[^A-Za-z0-9_].*$/, "", tb); lastname = tb }
  stmt(seg, segln); seg = ""; paren = 0
}
END {
  if (trim(seg) != "") stmt(seg, segln)
  if (bad == "" && incom) bad = "unterminated block comment"
  if (bad == "" && sp > 0) bad = sp " unclosed block(s) at end of file, innermost " stack[sp]
  if (bad == "" && paren > 0) bad = "unclosed parenthesis at end of file"
  out("redacted\t" redacted)
  out("markers_total\t" mtotal)
  out("status\t" (bad == "" ? "ok" : "malformed") "\t" bad)
}
