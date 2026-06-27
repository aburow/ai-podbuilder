---
title: Resume missing-project message repeats the resume flag
type: defect
status: done
lineage: ai-new
parent: lifecycle/tests/ai-new-13-tests.md
labels: [defect]
assignees:
  - role: test-developer
    who: agent
---

## Reproduction Steps

1. Run `bash tests/test_resume_missing_session.sh`.
2. Observe the first case, `--resume on non-existent project fails clearly`.
3. Note that the script prints an `ASSERT_NOT_CONTAINS fail` line but still reports the case and file as passing.
4. Re-run the underlying command directly with the test harness environment:
   `AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" ghostproject --resume`

## Expected Behaviour

The missing-project resume path should fail without suggesting `--resume` again in the error text, and the integration test should fail the case and exit non-zero when that assertion is violated.

## Actual Behaviour

The command exits non-zero, but its error text says `Run without --resume to create it.`, which causes the `assert_not_contains "--resume"` check to fail. That assertion is suppressed with `|| true` in `tests/test_resume_missing_session.sh`, so the test case is still reported as `PASS` and the file exits `0`.

## Logs / Output

```text
$ bash tests/test_resume_missing_session.sh
    ASSERT_NOT_CONTAINS fail: should not loop-suggest --resume: --resume should NOT be in output
  PASS  --resume on non-existent project fails clearly
  PASS  --resume with missing session.json fails clearly
  PASS  --resume on complete status fails (terminal)
  PASS  --resume on generated-unvalidated fails (terminal)

  ── test_resume_missing_session: 4 passed  0 failed  0 skipped
```

```text
$ AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" ghostproject --resume
[ERROR] Project 'ghostproject' does not exist. Run without --resume to create it.
```
