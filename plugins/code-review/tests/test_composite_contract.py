#!/usr/bin/env python3
"""Contract test for code-review's composite findings.

Contract: docs/plugins/code-review.md, "Composite findings".
Run:  python3 plugins/code-review/tests/test_composite_contract.py

Each test greps one invariant across the plugin's prose files. Each carries a
`# mutation:` comment quoting the sentence whose deletion must make it fail;
the mutation run (delete the sentence, watch the test fail, restore it) is
recorded in the pull request description. An assertion without that comment
is not a contract test.
"""

from __future__ import annotations

import sys
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


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]] + sys.argv[1:], verbosity=2)
