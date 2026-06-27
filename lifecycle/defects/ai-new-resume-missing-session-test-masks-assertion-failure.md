---
title: Resume missing-session test masks a failed assertion
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
2. Observe the first test case output for `--resume on non-existent project fails clearly`.
3. Check the file summary and shell exit code.

## Expected Behaviour

The test artifact for `ai-new` says `tests/test_resume_missing_session.sh` should verify that `--resume` with missing state fails clearly rather than restarting. If an assertion fails, the test case and file should be reported as failed and the script should exit non-zero.

## Actual Behaviour

The test prints a failed assertion because the command output still contains `--resume`, but the assertion is suppressed with `|| true` in [tests/test_resume_missing_session.sh](/workspace/podman-plugin/tests/test_resume_missing_session.sh:40). The case is then reported as `PASS`, the file summary reports `0 failed`, and the script exits `0`.

## Logs / Output

```text
ASSERT_NOT_CONTAINS fail: should not loop-suggest --resume: --resume should NOT be in output
PASS  --resume on non-existent project fails clearly
PASS  --resume with missing session.json fails clearly
PASS  --resume on complete status fails (terminal)
PASS  --resume on generated-unvalidated fails (terminal)

── test_resume_missing_session: 4 passed  0 failed  0 skipped

RC=0
```
