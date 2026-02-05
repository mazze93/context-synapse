# Security Policy

## Reporting a Vulnerability

I take security seriously and appreciate responsible disclosure of vulnerabilities in any of my projects.

### Security Contact

If you discover a security issue, please report it through one of the following channels:

- **GitHub Security Advisories**: Use [GitHub's private vulnerability reporting](https://github.com/mazze93/<REPO>/security/advisories) for the specific repository
- **Email**: See the repository README for maintainer contact information (if available)

### What to Include in Your Report

A helpful vulnerability report includes:

- **Description**: Clear explanation of the security issue and its potential impact
- **Affected versions**: Specific versions, branches, or components affected
- **Attack vector**: How the vulnerability could be exploited
- **Proof of Concept (PoC)**: Reproducible steps or code demonstrating the vulnerability
- **Impact assessment**: Potential consequences for users, data, or infrastructure
- **Proposed remediation**: Suggested fixes or mitigation strategies (optional but appreciated)

Please do not disclose vulnerability details in public issues, pull requests, or discussions until we've coordinated disclosure.

### What's Out of Scope

The following are generally outside the scope of this security program:

- Vulnerabilities in third-party dependencies (report to upstream maintainers)
- Social engineering attacks
- Physical security issues
- Denial-of-service attacks without demonstrable impact
- Issues in unsupported or deprecated versions
- Theoretical vulnerabilities without proof of exploitability

If you're unsure whether an issue qualifies, please report it and I'll make the determination.

## Coordinated Vulnerability Disclosure

I follow a **Coordinated Vulnerability Disclosure (CVD)** approach that balances transparency with responsible handling of security issues.

### My Commitment to Reporters

When you report a vulnerability, you can expect:

- **Acknowledgment within 72 hours**: Initial response confirming receipt of your report
- **Status updates**: Regular communication on remediation progress
- **Collaborative remediation**: Opportunity to contribute patches or validation testing
- **Public recognition**: Credit in security advisories (unless you prefer anonymity)
- **Safe harbor**: No legal action for good-faith security research

### Disclosure Timeline

| Timeframe | Action |
|-----------|--------|
| Day 0 | Vulnerability reported |
| Day 0-3 | Acknowledgment sent to reporter |
| Day 3-14 | Validation and impact assessment |
| Day 14-90 | Patch development and testing |
| Day 90 | Default public disclosure deadline |
| Post-Patch + 30 days | Public disclosure after patch release |

**Accelerated disclosure**: For critical vulnerabilities actively exploited in the wild, I may expedite the timeline with mutual agreement.

**Extended disclosure**: If additional time beyond 90 days is needed, I'll communicate this and provide regular progress updates.

**Early disclosure**: I may disclose earlier than 90 days if a patch is available and stable, with your agreement.

### CVE Assignment

For eligible vulnerabilities, I will request CVE assignment through the GitHub Security Advisory system or MITRE directly. CVE publication is coordinated with the public disclosure schedule.

## Supported Versions

Security updates are provided for the following versions:

| Version | Supported |
|---------|-----------|
| Latest release | ✓ |
| Main/Production branch | ✓ (subject to change) |
| Development branches | Limited support |
| Older releases | ✗ |

Specific projects may have different version support policies—check the repository documentation for details.

## Security Standards

My projects aim to follow security best practices aligned with:

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OpenSSF Best Practices](https://bestpractices.coreinfrastructure.org/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- GitHub's recommended security configurations

### Security Controls

Where applicable, repositories implement:

- **Branch protection**: Required reviews and status checks on main branches
- **Secret scanning**: Automated detection of exposed credentials
- **Dependency scanning**: Automated vulnerability alerts via Dependabot
- **Code scanning**: Static analysis for security vulnerabilities
- **Signed commits**: Verified commits on protected branches
- **Dependency updates**: Regular automated updates for security fixes

## Incident Response

### Severity Classification

| Severity | Impact | Target Response |
|----------|--------|-----------------|
| Critical | Active exploitation, data breach | 24-48 hours |
| High | Authentication bypass, significant data exposure | 7 days |
| Medium | Limited exposure, minor security issues | 14 days |
| Low | Minimal impact, edge cases | 30 days |

### Incident Disclosure

If a confirmed security incident affects users:

1. Immediate containment and remediation
2. Impact assessment
3. Private notification to affected parties (if applicable)
4. Patch release
5. Public security advisory with timeline, impact, and remediation steps

## Safe Harbor

I am committed to protecting security researchers who report vulnerabilities in good faith. I will not pursue legal action against researchers who:

- Report vulnerabilities responsibly through designated channels
- Avoid intentional harm to users, data, or infrastructure
- Do not publicly disclose vulnerabilities before coordinated disclosure
- Respect user privacy and data confidentiality
- Comply with applicable laws during security research

I encourage security research that helps improve the safety and security of these projects.

## Security Best Practices for Contributors

### For Code Contributors

- Never commit credentials, API keys, or sensitive data to repositories
- Use environment variables or GitHub Secrets for configuration
- Include security considerations in pull request descriptions
- Run security scanners locally before submitting pull requests
- Sign commits with GPG or SSH keys when possible

### Reporting Security Issues in Dependencies

If you discover a vulnerability in a third-party dependency:

1. Report it to the upstream maintainer first
2. If the dependency is unmaintained, report it here so I can evaluate migration options

## Updates to This Policy

This security policy is reviewed periodically and updated as needed. Material changes will be announced through GitHub Security Advisories or repository releases.

Version history is maintained in the repository commit history.

---

**Document Information**

- **Last Updated**: February 1, 2026
- **Effective Date**: February 1, 2026
- **Next Review**: May 1, 2026
