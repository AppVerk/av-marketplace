# Post-setup review eval

The eval checks whether `av-review` with the new `code-review.md` and overlay catches typical defects of this repo. You run it in step 10b, only with the `--eval` flag.

The result goes into the report as "Eval review: N/5".

## Safety rules

- The eval runs only on a clone in the session working directory (`<tmp>/eval-<project>`). Never on the live repo.
- Defects and fake secrets exist only in the clone. Delete the clone after scoring.
- No commits in the live repo, no push, no commands on shared environments.
- A fake secret looks real but is not real, e.g. `sk_test_EVAL0000000000000000`.

## Run

1. **Clone.** `git clone --no-hardlinks <repo-root> <tmp>/eval-<project>`. Copy the new, not yet committed setup files into the clone: config, overlays, `code-review.md`, `contracts.md`, role skills.
2. **Branch.** In the clone, `git checkout -b eval/av-review`. Commit the setup as the base: `git commit -m "eval base"`.
3. **Defects.** Inject N defects (default 5) chosen as in the "Defects" section below. Each in a different file, in code that looks like a normal feature change. Also add 1-2 correct changes as background, so the diff is not made only of bugs.
4. **Answer key.** Write the defect list (file:line, description) to `<tmp>/eval-key.md`. The key stays outside the clone and outside the reviewer prompt.
5. **Commit defects.** `git commit -am "eval changes"` in the clone. The diff against the base is the review material.
6. **Review.** A fresh subagent without this session's context runs the `av-review` skill on the clone, for the range `eval base..HEAD`. Model: `agents.models.review` from the config. The prompt gives only the clone directory and the range. Do not mention the eval or the number of defects.
7. **Scoring.** Compare the findings with the key:
   - hit: a finding points to the defect's file and describes its essence (the line may differ by a few),
   - false confirmation: the reviewer judged the changed place with a defect as correct, or the verdict is APPROVED despite a blocking-severity defect,
   - false report: a finding in background code that is not a bug.
8. **Cleanup.** Delete the clone and the key. Keep only the result.

## Result

Into the setup report, row "Eval review":

```
N/5 defects, F false confirmations, Z false reports
```

- Below 4/5: check which `code-review.md` axis is missing, or which tool is missing in the `av-review.md` overlay. Propose a fix. Do not repeat the eval in the same session, so the rules are not fitted to known defects.
- Describe each false confirmation in the report's "Gaps" with the axis name.
- A result with a model other than the one in the config is not comparable. Write the model next to the result.

## Defects

Build the set from this repo, never from a stack template:
- blocking rules from the new `code-review.md` (each rule gives one defect that breaks it),
- bugs from recent fixes (`git log --grep` with the ticket prefix and the word "fix"),
- contract surfaces from `contracts.md` (a breaking change),
- defects from team measurements, when the repo has them (e.g. an old pipeline benchmark).

Pick 5 from different review axes. One axis should not have more than 2 defects. Each defect must break a rule written in the repo docs; otherwise the eval measures the reviewer against rules the repo does not have.
