# Security Policy

## Supported scope

This project consists of shell scripts that install and update Claude Desktop resources on Arch Linux.

In-scope reports generally include:

- Unsafe script behavior that can cause privilege misuse
- Symlink/path handling vulnerabilities
- Command injection opportunities from untrusted inputs
- Insecure download/update flow handling

Out of scope:

- Vulnerabilities in upstream third-party software (Electron, Arch packages, or Claude service itself)
- Local misconfiguration issues without a reproducible security impact in this repository

## Reporting a vulnerability

Please do not open a public issue for security vulnerabilities.

Instead, report privately by contacting the repository maintainer directly through GitHub security reporting, or by private email if listed in the repository profile.

Include:

- A clear description of the issue
- Reproduction steps
- Potential impact
- Any suggested fix
- Environment details (Arch version, package versions, shell)

## Response expectations

- Initial acknowledgment target: within 7 days
- Triage and remediation timeline depends on severity and maintainer availability

Severity is assessed by exploitability and impact on user systems.

## Disclosure

Please allow time for a fix before public disclosure.

When a fix is shipped, maintainers may publish a summary in release notes or repository discussions.
