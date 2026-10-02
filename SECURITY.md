# Security

mac4DSTEM is a desktop application that reads microscopy files you choose.
It runs in the macOS App Sandbox and has no telemetry or analytics.

- **Network.** The only network connection the app makes is the
  Materials Project fetch you start yourself ("Materials Project…" in the
  phase picker): an HTTPS request to `api.materialsproject.org` carrying your
  own Materials Project API key and the mp-id you typed. No other data about
  you is sent. The app holds the network-client entitlement for this one request.
- **Stored data.** The API key is kept in the macOS Keychain. Preferences,
  recent files and the security-scoped bookmarks that let the app reopen files
  you chose, and the detector models you train in the app live in the app's
  sandbox container, besides the files the app writes for you.

To report a vulnerability — a crafted file that crashes the app or escapes the
sandbox, a leaked or mishandled API key, or a dependency problem in the
redistributed HDF5 libraries — use
GitHub's private reporting: the repository's **Security** tab → *Report a
vulnerability*. Please do not open a public issue for it. You will get a
reply in the advisory thread; fixes ship as a normal release and are noted in
`CHANGELOG.md`.
