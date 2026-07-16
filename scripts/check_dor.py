#!/usr/bin/env python3
"""
Definition of Ready (DoR) gate.

Reads the PR body (passed via the PR_BODY env var) and fails the build unless
every required section from .github/PULL_REQUEST_TEMPLATE.md is present and
actually filled in (not left as a placeholder or blank).

Exit 0 = PASS, exit 1 = FAIL. This is the whole contract with CI.

Design notes (read this before extending):
- We deliberately do NOT try to judge quality of the answer (e.g. "is this a
  real Given/When/Then"). That is a human review job. This gate only asks:
  "is there something here beyond the template's own scaffolding?" It is a
  cheap, fast, unambiguous check -- the kind the brief calls "small and sharp."
- We accept an explicit "NO SPEC EXISTS" escape hatch for Spec/PRD, because
  forcing a fabricated spec link is worse than an honest declaration that
  none exists. The Testing section has a similar explicit escape hatch.
  Everything else must be filled with real content.
"""
import os
import re
import sys

# Section header -> (required, allows an explicit named escape hatch)
REQUIRED_SECTIONS = {
    "Spec / PRD": {"escape_hatch": "NO SPEC EXISTS"},
    "Acceptance Criteria": {"escape_hatch": None},
    "Solution / Design Plan": {"escape_hatch": None},
    "Testing": {"escape_hatch": "docs only"},
}

MIN_CONTENT_LENGTH = 15  # chars, after stripping placeholders/whitespace

PLACEHOLDER_PATTERNS = [
    r"<!--.*?-->",   # HTML comments (the template's own instructions)
]


def extract_section(body: str, heading: str) -> str:
    """Grab everything between '## {heading}' and the next '## ' or EOF."""
    pattern = rf"##\s*{re.escape(heading)}\s*\n(.*?)(?=\n##\s|\Z)"
    match = re.search(pattern, body, re.DOTALL | re.IGNORECASE)
    return match.group(1).strip() if match else ""


def strip_placeholders(text: str) -> str:
    cleaned = text
    for pattern in PLACEHOLDER_PATTERNS:
        cleaned = re.sub(pattern, "", cleaned, flags=re.DOTALL)
    return cleaned.strip()


def main() -> None:
    body = os.environ.get("PR_BODY", "") or ""
    if not body.strip():
        print("DoR FAIL: PR body is empty. Use the PR template.")
        sys.exit(1)

    failures = []

    for heading, rules in REQUIRED_SECTIONS.items():
        raw = extract_section(body, heading)
        if not raw:
            failures.append(f"Section '## {heading}' is missing entirely.")
            continue

        content = strip_placeholders(raw)
        escape_hatch = rules["escape_hatch"]

        if escape_hatch and escape_hatch.lower() in content.lower():
            continue  # explicit, honest opt-out — allowed

        if len(content) < MIN_CONTENT_LENGTH:
            failures.append(
                f"Section '## {heading}' is empty or still a placeholder "
                f"(need at least {MIN_CONTENT_LENGTH} real characters)."
            )

    # Checklist: at least the "ran test suite locally" box must be checked,
    # OR the Testing section must use its explicit escape hatch.
    testing_content = strip_placeholders(extract_section(body, "Testing"))
    ran_tests_checked = bool(re.search(r"- \[[xX]\] I ran the full test suite", body))
    testing_exempt = "docs only" in testing_content.lower()

    if not ran_tests_checked and not testing_exempt:
        failures.append(
            "Testing checklist: 'I ran the full test suite locally' is not "
            "checked, and the Testing section does not declare an exemption."
        )

    if failures:
        print("Definition of Ready: FAIL\n")
        for f in failures:
            print(f" - {f}")
        print(
            "\nFix the PR description (not the code) and this check will "
            "re-run automatically on the next push."
        )
        sys.exit(1)

    print("Definition of Ready: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
