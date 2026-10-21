#!/usr/bin/env python3
"""Contract tests for code-review's composite findings and review scope safety.

Contract: docs/plugins/code-review.md, "Composite findings" and "Scope".
Run:  python3 plugins/code-review/tests/test_composite_contract.py

Each test checks an invariant across the plugin's prose files; default-branch
commands also run in disposable Git repositories. Each carries a
`# mutation:` comment quoting the sentence whose deletion must make it fail;
the mutation run (delete the sentence, watch the test fail, restore it) is
recorded in the pull request description. An assertion without that comment
is not a contract test.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

FIX_AUTO = "plugins/code-review/agents/fix-auto.md"
FIX = "plugins/code-review/commands/fix.md"
FIX_ALL = "plugins/code-review/commands/fix-all.md"
FIX_REPORT = "plugins/code-review/commands/fix-report.md"
REVIEW = "plugins/code-review/commands/review.md"
CROSS = "plugins/code-review/agents/cross-verifier.md"
ANALYST = "plugins/code-review/agents/composition-analyst.md"
GATE = "plugins/code-review/skills/decision-gate/SKILL.md"
DECISION_ANALYST = "plugins/code-review/agents/decision-analyst.md"
DOCS = "docs/plugins/code-review.md"
EXTRACT = "plugins/code-review/scripts/extract-issue-ids.sh"


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        raise AssertionError(f"missing file: {rel}")
    return path.read_text(encoding="utf-8")


class CompositeContract(unittest.TestCase):
    # ---- Task 1: prefix and category ------------------------------------

    def test_docs_prefix_table_has_composite_row(self):
        # mutation: delete the `| Composite | COMP | docs/reviews/ |` row in docs/plugins/code-review.md
        self.assertRegex(
            read(DOCS), r"(?m)^\|\s*Composite\s*\|\s*COMP\s*\|\s*`docs/reviews/`\s*\|", "docs table lacks the Composite | COMP row"
        )

    def test_fix_id_regex_has_comp(self):
        # mutation: remove `COMP` from fix.md's `^(SEC|PERF|ARCH|MAINT|DOC|QA|COMP)-\d{3}$` pattern
        self.assertRegex(read(FIX), r"\^\(SEC\|PERF\|ARCH\|MAINT\|DOC\|QA\|COMP\)-\\d\{3\}\$")

    def test_fix_auto_category_enum_has_composite(self):
        # mutation: remove `\|Composite` from fix-auto.md's `**Category:**` alternation
        self.assertRegex(read(FIX_AUTO), r"\*\*Category:\*\* Security\\\|Performance\\\|Architecture\\\|Maintainability\\\|Documentation\\\|Testing\\\|Composite")

    def test_extract_issue_ids_has_comp(self):
        # mutation: remove `|COMP` from extract-issue-ids.sh's PREFIX_RE
        self.assertIn("PREFIX_RE='(SEC|PERF|ARCH|MAINT|DOC|COMP)'", read(EXTRACT))

    # ---- Task 2: fix-auto composite mode ---------------------------------

    def test_fix_auto_composite_mode_switch(self):
        # mutation: delete the sentence "When the first block's `Category` is `Composite` **and** it carries a `**Composed-of:**` line, you are in composite mode" from fix-auto.md
        self.assertIn(
            "When the first block's `Category` is `Composite` **and** it carries a `**Composed-of:**` line, you are in composite mode",
            read(FIX_AUTO),
        )

    def test_fix_auto_root_cause_only_rule_verbatim(self):
        # mutation: delete the italic rule "In composite mode you implement the composite's Remediation. …" from fix-auto.md Phase 3
        self.assertIn(
            "it is never applied, in this phase or in Phase 5's iterations",
            read(FIX_AUTO),
        )

    def test_fix_auto_components_table_and_results(self):
        # mutation: delete the `**Components:**` table or any of the five Result values from fix-auto.md Phase 6
        text = read(FIX_AUTO)
        self.assertIn("**Components:**", text)
        for value in ("resolved", "unresolved (no location)", "skipped (fixed)", "skipped (rejected)"):
            self.assertIn(f"`{value}`", text, f"Result value {value} missing")

    def test_fix_auto_verdict_over_checked_components(self):
        # mutation: delete "The verdict is computed over the components actually checked" from fix-auto.md Phase 6
        self.assertIn("The verdict is computed over the components actually checked", read(FIX_AUTO))

    # ---- Task 3: composition-analyst ------------------------------------

    def test_analyst_frontmatter(self):
        # mutation: change `tools:` or drop `skills: finding-falsification` in composition-analyst.md
        text = read(ANALYST)
        head = text.split("---")[1]
        self.assertIn("name: composition-analyst", head)
        self.assertRegex(head, r"(?m)^tools: Read, Grep, Glob$", "tools must be exactly Read, Grep, Glob")
        self.assertIn("skills: finding-falsification", head)
        self.assertNotIn("allowed-tools", head)

    def test_analyst_closing_line_and_rejected_section(self):
        # mutation: delete the closing-line sentence or the `## Rejected groupings` requirement from composition-analyst.md
        text = read(ANALYST)
        self.assertIn("Composition: <N> groups proposed over <M> findings", text)
        self.assertIn("## Rejected groupings", text)

    def test_analyst_membership_cap(self):
        # mutation: delete "at most twelve" from composition-analyst.md
        self.assertIn("at most twelve", read(ANALYST))

    # ---- Task 4: review side --------------------------------------------

    def test_cross_verifier_composite_format_fields(self):
        # mutation: delete `Location:`, `Effort:` or `Cause:` from cross-verifier.md's Composite Findings format
        block = read(CROSS).split("### Composite Findings", 1)[1]
        for field in ("Location:", "Effort:", "Cause:", "Combined risk:", "Remediation:"):
            self.assertIn(field, block, f"{field} missing from the composite format")

    def test_cross_verifier_one_change_criterion(self):
        # mutation: delete "only where one change resolves every basis" from cross-verifier.md
        self.assertIn("only where one change resolves every basis", read(CROSS))

    def test_review_renders_composites(self):
        # mutation: delete the Step 5.5 item-2 body ("Disjointness") or the `comp_count` counter from review.md
        text = read(REVIEW)
        self.assertIn("comp_count", text)
        self.assertIn("**Part-of:**", text)
        self.assertIn("Disjointness", text)

    def test_review_disjointness_only_consumes_rendered_composites(self) -> None:
        # mutation: remove the rendered-block condition or bullet-release sentence from review.md's Disjointness rule
        rule = read(REVIEW).split("   2. Disjointness:", 1)[1].split("\n", 1)[0]
        self.assertIn(
            "a basis of an earlier composite rendered as a finding block "
            "(passed sub-items 2.3 and 2.4)",
            rule,
        )
        self.assertIn(
            "a composite kept as a plain bullet leaves its bases available to later composites",
            rule,
        )

    def test_docs_only_rendered_composites_consume_bases(self) -> None:
        # mutation: delete "Only rendered composite blocks consume bases" from docs/plugins/code-review.md
        self.assertIn(
            "Only rendered composite blocks consume bases; a proposal kept as a plain "
            "bullet leaves them available to later proposals.",
            read(DOCS),
        )

    # ---- Task 5: /fix-all ------------------------------------------------

    def test_fix_all_has_composition_steps(self):
        # mutation: delete Step 1.6, Step 2.4.5 or Step 3.0 from fix-all.md
        text = read(FIX_ALL)
        for heading in ("### Step 1.6: Composition pass", "### Step 2.4.5: The dissolve question", "### Step 3.0: Persist the composites"):
            self.assertIn(heading, text, f"{heading} missing")

    def test_fix_all_dispatchable_definition(self):
        # mutation: delete "it is **dispatchable** when open, not degenerate and not malformed" from fix-all.md Step 1.6's vocabulary sentence
        self.assertRegex(
            read(FIX_ALL),
            r"\*\*dispatchable\*\* when open, not degenerate and not malformed",
            "Step 1.6 no longer pins down the three-conjunct dispatchable definition",
        )

    def test_fix_all_validates_member_locations(self):
        # mutation: delete the Step 1.6.3 bullet "every member's `Location` is usable under that same rule **in full**, since the fixer opens each member's site and not the composite's alone; … `member-location-unusable`" from fix-all.md
        self.assertRegex(
            read(FIX_ALL),
            r"every member's `Location` is usable under that same rule \*\*in full\*\*.*`member-location-unusable`",
            "Step 1.6.3 does not validate member locations",
        )

    def test_fix_all_dissolve_question_copy(self):
        # mutation: delete the question string "Dissolve which composites into their components?" from fix-all.md
        self.assertIn("Dissolve which composites into their components?", read(FIX_ALL))

    def test_fix_all_fail_closed_gate(self):
        # mutation: delete "Dissolve question: unavailable" from fix-all.md
        self.assertIn("Dissolve question: unavailable", read(FIX_ALL))

    def test_fix_all_zero_auto_hook(self):
        # mutation: delete the Step 5.2 zero-auto paragraph that runs the dissolve question and persistence "before `code-review:decision-gate` is loaded" from fix-all.md
        self.assertIn("before `code-review:decision-gate` is loaded", read(FIX_ALL))

    def test_fix_all_composition_summary_block(self):
        # mutation: delete the `**Composition:**` block from fix-all.md Step 4.2
        text = read(FIX_ALL)
        self.assertIn("**Composition:**", text)
        self.assertIn("Verification coverage", text)

    def test_fix_all_skip_confirmation_snapshots_final_preflight(self) -> None:
        # mutation: delete the preflight_snapshot rule in fix-all.md Step 2.5
        gate = read(FIX_ALL).split("### Step 2.5: Confirmation gate", 1)[1].split("## Step 3:", 1)[0]
        self.assertIn("After Step 2.4.5", gate)
        self.assertIn("freeze `preflight_snapshot`", gate)
        self.assertIn("all ordered issue-table rows", gate)
        self.assertIn("Composites block", gate)
        self.assertIn("do not rebuild it from the edited reports", gate)
        self.assertNotIn("the only record", gate)

    def test_fix_all_unattended_summary_opens_with_full_preflight(self) -> None:
        # mutation: delete the Set out to fix prefix or its issue table from fix-all.md Step 4.2
        text = read(FIX_ALL)
        summary = text.split("### Step 4.2: Display fix summary", 1)[1].split("## Step 5:", 1)[0]
        self.assertIn("With `skip_confirmation`", summary)
        self.assertIn("`preflight_snapshot`", summary)
        template = summary.split("```markdown\n", 1)[1].split("\n```", 1)[0]
        self.assertTrue(template.startswith("## Fix Summary\n\n### Set out to fix\n"))
        intent = template.split("### Results", 1)[0]
        for field in (
            "**Reports:**",
            "**Severity floor:**",
            "**Total to fix:**",
            "**Requires user decision (skipped):**",
            "**By severity:**",
            "| CRITICAL | HIGH | MEDIUM | LOW |",
            "| # | ID | Severity | Title | Location | Source | Report |",
            "Composites block",
            "Confirmation skipped (--yes): fixing all <total_count> issues.",
        ):
            with self.subTest(field=field):
                self.assertIn(field, intent)
        self.assertIn("never collapse the table to a count or a list of IDs", summary)
        self.assertIn("Without `skip_confirmation`, omit", summary)

    def test_docs_locates_unattended_preflight_in_final_summary(self) -> None:
        # mutation: restore "the pre-flight is printed" in the after_review configuration row
        row = next(line for line in read(DOCS).splitlines() if line.startswith("| `after_review` |"))
        self.assertIn('final summary opens with "Set out to fix"', row)
        self.assertNotIn("the pre-flight is printed", row)

    # ---- Task 6: /fix-report ---------------------------------------------

    def test_fix_report_has_composition_steps(self):
        # mutation: delete Step 1.6, Step 2.1.5 or Step 2.3.5 from fix-report.md
        text = read(FIX_REPORT)
        for heading in ("### Step 1.6: Composition pass", "### Step 2.1.5: The dissolve question", "### Step 2.3.5: Persist the composites"):
            self.assertIn(heading, text, f"{heading} missing")

    def test_fix_report_composite_checklist_item(self):
        # mutation: delete the composite checklist item rule "A composite is **one checklist item**" from fix-report.md
        self.assertIn("A composite is **one checklist item**", read(FIX_REPORT))

    def test_fix_report_persists_before_gate(self):
        # mutation: delete "before Step 2.4 loads the decision gate" from fix-report.md Step 2.3.5
        self.assertIn("before Step 2.4 loads the decision gate", read(FIX_REPORT))

    # ---- Task 7: decision gate ------------------------------------------

    def test_gate_ref_clause_for_component_locations(self):
        # mutation: delete the sentence "each component's `Location` path is pinned `:ref`" from decision-gate SKILL.md
        self.assertIn("each component's `Location` path is pinned `:ref`", read(GATE))

    def test_gate_per_component_plan_clause(self):
        # mutation: delete "a plan for a composite carries at least one check per component" from decision-gate SKILL.md
        self.assertIn("a plan for a composite carries at least one check per component", read(GATE))

    def test_gate_fix_scope_row_dispatch_only(self):
        # mutation: change fix.md's scope-table row back to `render-only`
        self.assertRegex(read(GATE), r"\| `plugins/code-review/commands/fix\.md` \| dispatch-only \|")

    def test_containment_commands_take_path_characters_as_data(self) -> None:
        # mutation: put `<path>` back inside double quotes (`cd "$(dirname "<path>")"`) or drop the single quotes around './<path>' in a containment command of decision-gate SKILL.md, fix-auto.md or fix.md
        names = (
            "src/routes/users/$userId.tsx",
            "app/[id]/page.tsx",
            "app/(auth)/login/page.tsx",
            "src/routes/+page.svelte",
            "src/@types/env.d.ts",
            "docs/przegląd.md",
            "My Docs/setup.md",
            "src/x$(touch PWNED).py",
            "src/y`touch PWNED`.py",
        )
        template = re.compile(r"(?<=`)[^`]*'\./<path>'[^`]*(?=`)")
        for rel in (GATE, FIX_AUTO, FIX):
            commands = set(template.findall(read(rel)))
            resolve = [c for c in commands if "dirname" in c]
            link = [c for c in commands if c.startswith("test -L ")]
            with self.subTest(path=rel):
                self.assertTrue(resolve and link, f"no containment commands found in {rel}")
            for name in names:
                with self.subTest(path=rel, name=name), tempfile.TemporaryDirectory() as tmp:
                    repo = Path(tmp).resolve()
                    target = repo / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("x\n", encoding="utf-8")

                    def run(command: str) -> subprocess.CompletedProcess[str]:
                        literal = command.replace("<path>", name)
                        return subprocess.run(["bash", "-c", literal], cwd=repo, capture_output=True, text=True)

                    for command in resolve:
                        result = run(command)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.strip(), str(target.parent))
                    for command in link:
                        self.assertEqual(run(command).returncode, 1, "a regular file must not read as a symbolic link")
                        target.unlink()
                        target.symlink_to(repo / "elsewhere")
                        self.assertEqual(run(command).returncode, 0, "a symlinked final component must be detected")
                    self.assertEqual(list(repo.rglob("PWNED")), [], "a name's command substitution ran")

    def test_fix_containment_finishes_before_any_content_read(self) -> None:
        # mutation: delete the "Containment before content" gate or its metadata-only validation rule from fix.md
        text = read(FIX)
        phase = text.split("## Phase 1: Parse Issue", 1)[1].split("## Phase 2: Analyze Context", 1)[0]
        gate = phase.split("**Containment before content.**", 1)[1].split("\n\n", 1)[0]
        self.assertIn("initial Location and every replacement reply", gate)
        self.assertIn("complete the entire containment test before any read", gate)
        self.assertIn("only the root/parent directory resolution above (`pwd -P`)", gate)
        for check in ("`test -L`", "`[ -L`", "`test -e`"):
            with self.subTest(check=check):
                self.assertIn(check, gate)
        self.assertIn("Never use `cat`, `head`, `Read`", gate)
        self.assertIn("anything else that prints the candidate file's content", gate)
        self.assertIn("including in a chained command", gate)
        self.assertIn("Only after all checks pass may Phase 2 read the file", gate)
        self.assertLess(phase.index("**Containment before content.**"), phase.index("> This issue's location"))

    def test_fix_reply_validation_reuses_no_read_gate(self) -> None:
        # mutation: delete the "Containment before content" reference from the reply-validation paragraph
        phase = read(FIX).split("## Phase 1: Parse Issue", 1)[1].split("## Phase 2: Analyze Context", 1)[0]
        reply = phase.split("Validate the reply", 1)[1].split("\n\n", 1)[0]
        self.assertIn("the **Containment before content** gate above", reply)
        self.assertIn("before any read", reply)
        self.assertIn("without opening any file", reply)

    def test_docs_describe_metadata_only_reply_validation(self) -> None:
        # mutation: delete the metadata-only reply-validation sentence from the Fixing Issues docs
        section = read(DOCS).split("## Fixing Issues", 1)[1].split("**Recommended workflow", 1)[0]
        self.assertIn("initial location and every replacement reply before any read", section)
        self.assertIn("`pwd -P`, `test -L` / `[ -L` and `test -e`", section)
        self.assertIn("never reads or prints the candidate file's content", section)

    def test_decision_analyst_knows_composites(self):
        # mutation: delete the composite paragraph from decision-analyst.md's Input section
        self.assertIn("composite block plus each component block", read(DECISION_ANALYST))

    # ---- Task 8: /fix ----------------------------------------------------

    def test_fix_component_question(self):
        # mutation: delete Step 0.4.5 or its question "is part of composite" from fix.md
        text = read(FIX)
        self.assertIn("### Step 0.4.5: A component of an open composite", text)
        self.assertIn("is part of composite", text)

    def test_fix_root_cause_only_rule_verbatim(self):
        # mutation: delete the italic root-cause-only rule from fix.md Phase 4
        self.assertIn("it is never applied, in this phase or in Phase 6's iterations", read(FIX))

    def test_fix_runs_composite_itself(self):
        # mutation: delete "never through `fix-auto`" from fix.md
        self.assertIn("never through `fix-auto`", read(FIX))

    def test_fix_components_table(self):
        # mutation: delete the `**Components:**` table from fix.md Phase 7
        self.assertIn("**Components:**", read(FIX))

    # ---- Task 9: docs ---------------------------------------------------

    def test_docs_composite_section_and_qa_loop_sentence(self) -> None:
        # mutation: delete the `## Composite findings` section or the sentence "`/qa:run` is untouched" from docs/plugins/code-review.md
        text = read(DOCS)
        self.assertIn("## Composite findings", text)
        self.assertIn("`/qa:run` is untouched", text)

    def test_docs_upgrade_note_states_dispatch_change(self):
        # mutation: delete the 2.1.0 Upgrade Notes paragraph ("Their dispatch does change") from docs/plugins/code-review.md
        self.assertIn("Their dispatch does change", read(DOCS))

    # ---- Review scope: default-branch shell safety ---------------------

    def test_default_branch_commands_use_only_fixed_refs(self) -> None:
        # mutation: restore symbolic-ref output or the <default branch> placeholder in Review Scope step 2
        step = read(REVIEW).split("2. **Default.**", 1)[1].split("\n3.", 1)[0]
        self.assertEqual(
            re.findall(r"`(git [^`]+)`", step),
            [
                "git rev-parse --verify --quiet 'refs/remotes/origin/HEAD^{commit}'",
                "git merge-base HEAD refs/remotes/origin/HEAD",
                "git rev-parse --verify --quiet 'main^{commit}'",
                "git merge-base HEAD main",
                "git rev-parse --verify --quiet 'master^{commit}'",
                "git merge-base HEAD master",
            ],
        )
        self.assertIn("Never obtain the symbolic ref's target name", step)
        self.assertIn("resolves the literal `refs/remotes/origin/HEAD`", read(DOCS))

    def test_default_branch_resolution_and_fallbacks(self) -> None:
        # mutation: change an origin probe/merge operand or the fixed main-before-master fallback order
        step = read(REVIEW).split("2. **Default.**", 1)[1].split("\n3.", 1)[0]
        commands = re.findall(r"`(git [^`]+)`", step)
        self.assertEqual(len(commands), 6)
        cases = [
            ("origin", "normal", True, True, "base"),
            ("substitution", "$(touch${IFS}sec003-sentinel)", True, True, "base"),
            ("backticks", "`touch${IFS}sec003-sentinel`", True, True, "base"),
            ("pipeline", "topic|$(touch${IFS}sec003-sentinel)", True, True, "base"),
            ("main", None, True, True, "head"),
            ("master", None, False, True, "base"),
            ("no-default", None, False, False, None),
            ("dangling-origin", "missing", True, True, "head"),
            ("unrelated-origin", "unrelated", True, True, None),
        ]
        for label, remote_name, main_exists, master_exists, expected in cases:
            with self.subTest(case=label), tempfile.TemporaryDirectory() as temporary:
                repo = Path(temporary)

                def git(
                    *args: str, input_text: str | None = None, directory: Path = repo,
                ) -> str:
                    result = subprocess.run(
                        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.test", *args],
                        cwd=directory, input=input_text, text=True, capture_output=True, check=True,
                    )
                    return result.stdout.strip()

                git("init", "--quiet")
                git("symbolic-ref", "HEAD", "refs/heads/topic")
                tree = git("mktree", input_text="")
                base = git("commit-tree", tree, "-m", "base")
                head = git("commit-tree", tree, "-p", base, "-m", "head")
                git("update-ref", "HEAD", head)
                if main_exists:
                    git("update-ref", "refs/heads/main", head)
                if master_exists:
                    git("update-ref", "refs/heads/master", base)
                if remote_name is not None:
                    remote_ref = f"refs/remotes/origin/{remote_name}"
                    if remote_name != "missing":
                        remote_commit = (
                            git("commit-tree", tree, "-m", "unrelated")
                            if remote_name == "unrelated" else base
                        )
                        git("update-ref", remote_ref, remote_commit)
                    git("symbolic-ref", "refs/remotes/origin/HEAD", remote_ref)

                resolved = None
                for index in (0, 2, 4):
                    probe = subprocess.run(
                        ["bash", "-c", commands[index]],
                        cwd=repo, text=True, capture_output=True, check=False,
                    )
                    if probe.returncode == 0:
                        merge = subprocess.run(
                            ["bash", "-c", commands[index + 1]],
                            cwd=repo, text=True, capture_output=True, check=False,
                        )
                        if merge.returncode == 0:
                            resolved = merge.stdout.strip()
                        break
                expected_sha = {"base": base, "head": head, None: None}[expected]
                self.assertEqual(resolved, expected_sha)
                self.assertFalse((repo / "sec003-sentinel").exists())

    def test_review_shell_examples_preserve_argv_without_omp_placeholders(self) -> None:
        # mutation: restore "$@" in review.md's Shell safety suffix or remove the empty-batch guard
        paths = ["plain.py", "with spaces.py", "zażółć.py", "-option.py", "line\nbreak.py", "$(exit 7).py"]
        for path in (REVIEW, REVIEW.replace("plugins/", "plugins-omp/", 1)):
            suffix = read(path).split("~~~text\nShell safety:", 1)[1].split("\n~~~", 1)[0]
            examples = [line for line in suffix.splitlines() if line.startswith("git ")]
            with self.subTest(path=path):
                self.assertNotRegex(suffix, r"\$(?:@|ARGUMENTS|\d+)")
                self.assertEqual(len(examples), 2)

            for example in examples:
                pipeline = example.split("|", 1)[1]
                self.assertIn("exec semgrep scan --config=p/security-audit --", pipeline)
                # Record argv instead of invoking a scanner; keep the published xargs and sh wrapper.
                pipeline = pipeline.replace(
                    "exec semgrep scan --config=p/security-audit --", 'printf "%s\\000"',
                )
                for batch in ([], paths):
                    data = b"".join(name.encode("utf-8") + b"\0" for name in batch)
                    with self.subTest(path=path, example=example, batch=batch):
                        result = subprocess.run(
                            ["sh", "-c", pipeline], input=data, capture_output=True, check=False,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout, data)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]] + sys.argv[1:], verbosity=2)
