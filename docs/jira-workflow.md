# Jira and GitHub Workflow

This repository is configured for the `APP` Jira project on `strnadi-status.atlassian.net`.

## Branches

- `feature/APP-123-short-description`: normal task, story, and bug work.
- `release/1.6.0`: release candidate branch.
- `release/APP-123-1.6.0`: release branch tied to a Jira release task.
- `development`: integration branch for feature work.
- `main`: deploy branch for internal tester builds.

The `Branch and Jira Policy` workflow validates feature and release branch names on pushes and pull requests.

## Jira Release Model

- Every feature, story, task, and bug that will ship must have a Jira release in `Fix versions`.
- The release name should match the Git branch version, for example Jira `fixVersion` `1.6.0` maps to `release/1.6.0`.
- Use one Jira release task per app release when you want a single control issue for automation state. The recommended statuses for that release task are `Release Candidate`, `Open Beta`, and `Production Released`.
- Add a `To Test` status to the `APP` project workflow for feature/story/task/bug issues. The deploy workflow will use `JIRA_TEST_STATUS` and defaults to `To Test`.
- QA marks tested issues `Done`. If testing fails, QA moves the issue back to `In Progress` with a comment.

## Pull Requests

- Feature branches should include the Jira key in the branch name and PR template.
- Pull request titles must include the Jira key so GitHub for Jira can link the PR natively.
- The Jira issue must have `Fix versions` set before it is merged into a `release/**` branch.
- At least one feature branch commit subject must include the Jira key so GitHub for Jira can link builds and deployments.
- Jira issue keys are detected from the branch, title, PR body, and commit subjects.
- If `JIRA_USER_EMAIL` and `JIRA_API_TOKEN` are configured, the workflow verifies that detected Jira issues exist.
- On PR open, reopen, or ready-for-review, the workflow adds a Jira comment with the GitHub PR link.

## Deployments

- Push to `main`: runs the `internal` deployment stage.
- Push to `release/**`: runs the `internal` deployment stage.
- Manual or Jira-triggered `external_beta`: promotes Android to Google Play open testing and distributes iOS to TestFlight group `open_beta`.
- Manual or Jira-triggered `production`: promotes Android to Google Play production and submits the latest TestFlight build for App Store review with automatic release after approval.
- The release-candidate track defaults to `alpha`; set `GOOGLE_PLAY_RELEASE_CANDIDATE_TRACK` if your Play Console track uses another name.
- The open beta track defaults to `beta`; set `GOOGLE_PLAY_OPEN_BETA_TRACK` if your Play Console open testing track uses another name.
- The deploy workflow creates GitHub deployment events and status updates so Jira can show Android and iOS deployments in the Deployments view.
- Deployment events use the deployed branch name as the GitHub deployment ref and pin the exact deployed commit SHA.
- Android deployments use the `android-testing` environment unless the Play track is `production`, in which case they use `android-production`.
- iOS release-candidate TestFlight deployments use `ios-testflight`.
- iOS open beta distribution uses `ios-testflight-open-beta`.
- iOS production submission uses `ios-app-store`.
- Custom deployment environments are mapped for Jira in `.jira/config.yml`.
- If a deploy branch contains a Jira issue key, the deploy workflow comments on that Jira issue after a successful platform deploy.
- After both Android and iOS release-candidate deploys succeed, `.github/scripts/release-jira.sh` finds all issues with the release `fixVersion`, comments on them, and transitions them to `JIRA_TEST_STATUS`.

## Jira Automation Rules

Create these rules in the `APP` Jira project.

### Notify Testers

- Trigger: Issue transitioned to `To Test`.
- Condition: Project is `APP`.
- Action: Notify the QA/tester group with the issue key, summary, release, and GitHub workflow link from the latest issue comment.

### Release To Open Beta

- Trigger: Issue transitioned.
- Condition: The issue has at least one `Fix versions` value.
- Lookup issues JQL: `project = APP AND fixVersion = "{{issue.fixVersions.first.name}}" AND issuetype in (Feature, Story, Task, Bug) AND statusCategory != Done`.
- If the lookup result count is `0`, send a web request to GitHub:

URL: `https://api.github.com/repos/Strnadi/Strnadi-Mobile-App/actions/workflows/deploy.yml/dispatches`

Headers:

- `Authorization: Bearer <GitHub workflow dispatch token>`
- `Accept: application/vnd.github+json`
- `Content-Type: application/json`

```json
{
  "ref": "release/{{issue.fixVersions.first.name}}",
  "inputs": {
    "platform": "all",
    "deployment_stage": "external_beta",
    "jira_release_version": "{{issue.fixVersions.first.name}}"
  }
}
```

- Then transition the release task for that version to `Open Beta`, or comment on the release if you do not use release tasks.

### Release To Production After Seven Days

- Trigger: Scheduled, once per day.
- JQL: `project = APP AND issuetype = Task AND status = "Open Beta" AND status CHANGED TO "Open Beta" BEFORE -7d`.
- Action: Send the same GitHub workflow dispatch request with `"deployment_stage": "production"`.
- Then transition the release task to `Production Released`.
- If production was already released manually, transition the release task to `Production Released`; the scheduled rule will no longer match it.

The Jira web request needs a GitHub token with permission to dispatch repository workflows for `Strnadi/Strnadi-Mobile-App`.

## Required GitHub Variables

- `JIRA_BASE_URL`: defaults to `https://strnadi-status.atlassian.net`.
- `JIRA_PROJECT_KEYS`: defaults to `APP`. Use comma-separated values like `APP,WEB` if this repo should accept multiple Jira projects.
- `JIRA_TEST_STATUS`: defaults to `To Test`.
- `RELEASE_SYNC_APP_CLIENT_ID`: GitHub App Client ID used for release branch version sync bypass. It can be stored as an Actions secret or repository variable; the workflow reads the secret first.
- `GOOGLE_PLAY_RELEASE_CANDIDATE_TRACK`: optional Play Console release-candidate testing track. Defaults to `alpha`.
- `GOOGLE_PLAY_OPEN_BETA_TRACK`: optional Play Console open testing track. Defaults to `beta`.
- `TESTFLIGHT_CLOSED_BETA_GROUPS`: optional comma-separated TestFlight groups for new internal and release-candidate iOS builds. Defaults to `closed_beta`.
- `TESTFLIGHT_OPEN_BETA_GROUPS`: optional comma-separated TestFlight groups for Open Beta distribution. Defaults to `open_beta`.

## Required GitHub Secrets for Jira Comments and Validation

- `JIRA_USER_EMAIL`: Atlassian account email for the automation user.
- `JIRA_API_TOKEN`: Jira API token for the automation user.

Without the Jira secrets, branch naming is still enforced, but issue existence checks and Jira comments are skipped.
