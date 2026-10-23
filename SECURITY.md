# Security

Sixty locks your screen and installs its own updates, so security reports matter.

**Report a vulnerability privately** through GitHub: [Security → Report a vulnerability](https://github.com/leplik/sixty/security/advisories/new). Please do not open a public issue. You get an answer within 7 days.

In scope, for example:
- a way to make the updater install code that is not signed with the developer's Developer ID (team `JVW2N74WL3`);
- a way for another app to read audio or data through Sixty;
- a lock that does not end (the watchdog must end every break within 90 seconds).

Out of scope: ending a break early with the emergency phrase, killing Sixty with root or SSH, the power button. Those are documented behaviour.

Supported versions: the latest release.
