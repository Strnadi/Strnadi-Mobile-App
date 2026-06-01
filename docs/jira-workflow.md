# Jira and GitHub Workflow

This repository is configured for the `APP` Jira project on `strnadi-status.atlassian.net`.

## Branches

- `feature/APP-123-short-description`: normal task, story, and bug work.
- `release/1.6.0`: release candidate branch.
- `release/APP-123-1.6.0`: release branch tied to a Jira release task.
- `development`: integration branch for feature work.
- `main`: deploy branch for internal tester builds.

The `Branch and Jira Policy` workflow validates feature and release branch names on pushes and pull requests.

## Pull Requests

- Feature branches should include the Jira key in the branch name and PR template.
- Jira issue keys are detected from the branch, title, and PR body.
- If `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` are configured, the workflow verifies that detected Jira issues exist.
- On PR open, reopen, or ready-for-review, the workflow adds a Jira comment with the GitHub PR link.

## Deployments

- Push to `main`: deploys Android to the Play Console `internal` track and iOS to TestFlight.
- Push to `release/**`: deploys Android to the closed testing track and iOS to TestFlight.
- The closed testing track defaults to `alpha`; set the `GOOGLE_PLAY_CLOSED_TRACK` repository variable if your Play Console closed-testing track uses another name.
- Manual deploys can override the Play track with the `play_track` workflow input.
- If a deploy branch contains a Jira issue key, the deploy workflow comments on that Jira issue after successful Android and iOS uploads.

## Required GitHub Variables

- `JIRA_BASE_URL`: defaults to `https://strnadi-status.atlassian.net`.
- `JIRA_PROJECT_KEYS`: defaults to `APP`. Use comma-separated values like `APP,WEB` if this repo should accept multiple Jira projects.
- `GOOGLE_PLAY_CLOSED_TRACK`: optional Play Console closed-testing track for `release/**` pushes. Defaults to `alpha`.

## Required GitHub Secrets for Jira Comments and Validation

- `JIRA_USER_EMAIL`: Atlassian account email for the automation user.
- `JIRA_API_TOKEN`: Jira API token for the automation user.

Without the Jira secrets, branch naming is still enforced, but issue existence checks and Jira comments are skipped.
