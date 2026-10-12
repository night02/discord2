# Security policy — Veylor

Veylor is in beta. The project currently stores user credentials and messages in a backend database, so security reports should not be posted publicly.

## Reporting security issues

If **Private vulnerability reporting** is enabled, use the **Security → Report a vulnerability** section of [night02/discord2](https://github.com/night02/discord2/security) to report a suspected vulnerability privately. If unavailable, ask the maintainer through GitHub for a private reporting channel; **do not post exploit details, passwords, real tokens, user data or database URLs in public issues**.

## Supported versions

Only the newest tested beta is maintained. Previous debug and test builds are not supported for security updates.

## Disclosure and artifacts

- Do not commit `.env`, keystores, private certificates, secrets, or production database dumps.
- Published GitHub Actions artifacts are preview builds; GitHub Releases are distributed only after CI and manual checks.
- Android debug APKs and unsigned Windows installers are not production-signed distributions.
- For public releases, always review committed files and the repository's full Git history for secrets before publication. Ignoring a secret prevents future commits but does **not** revoke an exposed token; rotate any exposed credentials.
