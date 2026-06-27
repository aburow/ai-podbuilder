---
title: Slug sanitizer test emits a failed assertion but still passes
type: defect
status: clarifying
lineage: ai-new
parent: lifecycle/tests/ai-new-13-tests.md
labels: [defect]
assignees:
  - role: test-developer
    who: agent
---

## Reproduction Steps

1. Run `bash tests/test_slug_sanitizer.sh`.
2. Observe the `illegal chars replaced with dash` case.
3. Check the file summary and shell exit code.

## Expected Behaviour

The `ai-new` slug-sanitizer test should enforce the requirement from `R20.1`: illegal characters are replaced, repeated dashes are collapsed, and leading/trailing punctuation is trimmed. A mismatched expected slug should fail the test case and the script should exit non-zero.

## Actual Behaviour

The case logs an `ASSERT_EQ fail` because the test expects `my-proj-ect-` while the implementation returns `my-proj-ect`, which is consistent with trailing punctuation trimming. The failure is masked by the fallback branch in [tests/test_slug_sanitizer.sh](/workspace/podman-plugin/tests/test_slug_sanitizer.sh:85), the case is reported as `PASS`, the file summary reports `0 failed`, and the script exits `0`.

## Logs / Output

```text
PASS  lowercase name unchanged
PASS  uppercase letters are lowercased
PASS  spaces replaced with dash
PASS  underscores are kept
ASSERT_EQ fail: illegal chars should be replaced with dashes
  expected: my-proj-ect-
  actual:   my-proj-ect
PASS  illegal chars replaced with dash

── test_slug_sanitizer: 13 passed  0 failed  0 skipped

RC=0
```
