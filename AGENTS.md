# Mergefox for GitLab

- Generate the project with `xcodegen generate`; edit `project.yml` rather than the generated project.
- Keep the approved marketing version for routine TestFlight updates; increment only the build number until Perry explicitly requests a new version or approves a suggested version change for a substantial feature release.
- Preserve bundle identifiers, Keychain identifiers, and the legacy OAuth callback for existing installs. Product branding is Mergefox.
- Never commit OAuth client IDs, access tokens, refresh tokens, client secrets, or signing files. Local OAuth configuration belongs in ignored `Config/OAuth.local.xcconfig`.
- Use Coot for iOS builds/distribution and Helm CLI for App Store Connect.
- Keep neutral body text, purple controls, pale lavender surfaces, and orange brand accents. Diffs use full width with horizontal scrolling.
- Git commits must use Perry Raskin <perryraskin@gmail.com> as author and committer.
