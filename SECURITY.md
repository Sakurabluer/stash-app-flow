# Security Policy

## Supported Version

Security fixes are provided for the latest published release.

## Reporting a Vulnerability

Use GitHub's private security advisory feature for this repository. Do not
open a public issue containing API keys, private server addresses, logs with
credentials, or personal media information.

Include the affected app version, Android version, reproduction steps, and the
expected impact. Redact all credentials and private URLs.

## Credential Handling

Stash API keys must never be committed to the repository, embedded in an APK,
or included in diagnostic logs. Android release keystores and signing
passwords are also private and are excluded from version control.
