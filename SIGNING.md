# Android Release Signing

The official Stash Flow release key is stored outside this repository at:

```text
C:\Users\Sakura\Documents\StashFlowSigning\stash-flow-release.jks
```

The Gradle build reads these user environment variables:

```text
STASH_FLOW_KEYSTORE
STASH_FLOW_KEY_ALIAS
STASH_FLOW_STORE_PASSWORD
STASH_FLOW_KEY_PASSWORD
```

The keystore and all four values must be backed up securely. Losing the key or
password prevents future APKs from upgrading existing installations. Never
commit them, attach them to a GitHub Release, paste them into an Issue, or send
them through chat.

The official key is not required to clone, analyze, test, run, or build a debug
APK from source. Other developers may configure their own keystore for release
builds. An APK signed with another key cannot upgrade an installed official
build with the same application ID; uninstall the official build or use a
different application ID for independent distributions.

To inspect the configured values locally without putting them in repository
files, open a new PowerShell window and run:

```powershell
[Environment]::GetEnvironmentVariable('STASH_FLOW_KEYSTORE', 'User')
[Environment]::GetEnvironmentVariable('STASH_FLOW_KEY_ALIAS', 'User')
[Environment]::GetEnvironmentVariable('STASH_FLOW_STORE_PASSWORD', 'User')
[Environment]::GetEnvironmentVariable('STASH_FLOW_KEY_PASSWORD', 'User')
```

Store the passwords in a trusted password manager and keep an offline copy of
the keystore. Release builds created without these environment variables are
not official signed builds and should not be distributed.

Official certificate SHA-256 fingerprint:

```text
3A:54:3B:54:FA:D6:B0:24:2F:AB:8E:E6:51:1B:F1:F7:3B:2C:AF:6B:4E:25:EF:1C:12:17:C3:B8:04:DB:AE:58
```
