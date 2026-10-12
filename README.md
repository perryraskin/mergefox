# Mergefox for GitLab

Native SwiftUI code review for iPhone and iPad. Open GitLab merge requests, review changes, participate in discussions, and approve the current commit.

## Features

- Browser-based OAuth with PKCE and device-only Keychain storage; personal access token and self-hosted GitLab alternatives.
- Share a GitLab MR URL from Safari, Slack, or another app into the native share-sheet viewer.
- Release overview for feature MRs targeting `release/*`: project/branch selection, open, ready, attention, merged counts, and oldest pending MR.
- Personal review and authored inboxes with a saved default tab and status, target branch, author, labels, and search filters.
- Recently opened and recently merged lists. Home and release lists show five MRs per page.
- Rich Markdown and sanitized HTML, expandable details, tables, mentions, commit links, and locally rendered Mermaid diagrams.
- Full-width native unified diffs with line numbers, collapsible files, and horizontally scrolling filenames/code.
- MR metadata, reviewers, assignees, labels, branches, and pipeline status.
- Discussion replies and resolve/reopen; approve the loaded commit or undo approval; edit title, description, labels, and target branch.
- Native back navigation with a left-edge swipe; horizontal code and filename dragging remain available.
- Read-only demo mode.

## Build and test

Requires Xcode, XcodeGen, and an Apple signing team for device builds. Change `DEVELOPMENT_TEAM` in `project.yml` for your own account.

```sh
cp Config/OAuth.example.xcconfig Config/OAuth.local.xcconfig
# Set your public GitLab OAuth application ID in the local file.
xcodegen generate
xcodebuild -project Mergefox.xcodeproj -scheme Mergefox -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
coot deploy
```

The pinned Swift Package Manager dependency resolves automatically. Distributed builds include the preconfigured public OAuth client ID. The source repository excludes that ID; `Config/OAuth.local.xcconfig` is ignored and included optionally through `Config/OAuth.xcconfig`. Without it, use a personal access token or an application ID in advanced account settings. Never commit access tokens, refresh tokens, or a client secret.

## OAuth and upgrade compatibility

Register a non-confidential/public GitLab OAuth application named **Mergefox for GitLab**, with the `api` scope. The existing callback remains `mergepocket://oauth/callback` to preserve the registered OAuth integration. No client secret is used.

The original bundle identifiers and Keychain service remain stable so existing installs upgrade normally and keep their saved account. These internal compatibility identifiers are not the product branding.

## Links

Use `mergefox://open?url=<percent-encoded HTTPS GitLab MR URL>` for Shortcuts and deep links. Older `mergepocket://open` links continue to work.

For ordinary GitLab URLs, choose **Share → Mergefox**. Enable it under **More** on first use, and sign in in the main app before reviewing private MRs. GitLab-controlled URLs cannot become third-party Universal Links without GitLab associating its domain. The share extension presents the review directly; it does not launch the containing app.

## Current boundaries

One account at a time. Release readiness uses confirmed GitLab approval and check status; unavailable checks are disclosed and excluded from Ready. Release discovery uses recent personal MRs and opened links; counts cover all authors for the selected project/target branch. Release summary and diff/discussion fetches have a 1,000-row cap with notices.

No push notifications or offline cache. Existing diff threads are grouped under their file; new line-specific comments are not included. GitLab permissions, project rules, and approval reauthentication apply.

## Design and third-party notices

Purple controls, neutral body text, orange accents, and light lavender surfaces follow [GitLab Pajamas](https://design.gitlab.com/). The icon uses a faceted orange glass GitLab fox on pale lavender. Compact review navigation takes cues from [GitHub Mobile](https://github.com/mobile).

See `App/ThirdPartyNotices.txt` for licenses covering gitdiff, Marked, DOMPurify, and Mermaid. These library notices do not declare the app itself MIT-licensed. Rebuild the pinned Mermaid bundle with `scripts/bundle-mermaid.sh`.
