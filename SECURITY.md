# Security

mac4DSTEM is a desktop application that reads microscopy files you choose. It
makes no network connections and stores nothing outside the files it writes
for you (see `CONTRIBUTING.md`, "Scope").

To report a vulnerability — a crafted file that crashes the app or escapes the
sandbox, or a dependency problem in the redistributed HDF5 libraries — use
GitHub's private reporting: the repository's **Security** tab → *Report a
vulnerability*. Please do not open a public issue for it. You will get a
reply in the advisory thread; fixes ship as a normal release and are noted in
`CHANGELOG.md`.
