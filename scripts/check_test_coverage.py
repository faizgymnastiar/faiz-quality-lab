#!/usr/bin/env python3
"""
No Test No Merge gate.

For every changed file under api/app/**/*.rb, require a correlated change
under api/spec/**/*_spec.rb (mirrored path). This does not prove the test is
good -- it only proves a developer did not silently skip testing. Quality of
the test is a human review job; existence is what CI can cheaply enforce.

Usage: python scripts/check_test_coverage.py <base_ref>
Exit 0 = PASS, exit 1 = FAIL.
"""
import subprocess
import sys

# Files/dirs that legitimately have no matching spec. Keep this list short
# and deliberate -- every entry is a conscious exemption, not a loophole.
EXEMPT_PREFIXES = (
    "api/app/views/",
    "api/app/mailers/",           # covered by request specs, not unit specs
    "api/db/",
    "api/config/",
)


def get_changed_files(base_ref: str) -> list[str]:
    output = subprocess.check_output(
        ["git", "diff", "--name-only", f"origin/{base_ref}...HEAD"]
    ).decode()
    return [f for f in output.strip().split("\n") if f]


def expected_spec_path(app_path: str) -> str:
    # api/app/services/portfolios/generator.rb
    #   -> api/spec/services/portfolios/generator_spec.rb
    return app_path.replace("app/", "spec/", 1).replace(".rb", "_spec.rb")


def is_exempt(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in EXEMPT_PREFIXES)


def main() -> None:
    base_ref = sys.argv[1] if len(sys.argv) > 1 else "main"
    changed = get_changed_files(base_ref)
    changed_set = set(changed)

    changed_app_files = [
        f for f in changed
        if f.startswith("api/app/") and f.endswith(".rb") and not is_exempt(f)
    ]

    missing = []
    for app_file in changed_app_files:
        spec_file = expected_spec_path(app_file)
        if spec_file not in changed_set:
            missing.append((app_file, spec_file))

    if missing:
        print("No Test No Merge: FAIL\n")
        for app_file, spec_file in missing:
            print(f" - {app_file} changed, but {spec_file} did not.")
        print(
            "\nIf this file genuinely needs no spec, add its prefix to "
            "EXEMPT_PREFIXES in scripts/check_test_coverage.py in this same "
            "PR, with a one-line reason in the commit message -- do not "
            "silently skip."
        )
        sys.exit(1)

    print("No Test No Merge: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
