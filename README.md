# ngrok ship action

Builds an [ngrok ship](https://ngrok.com) app's container image, pushes it
to the app's registry, and reports it to ship. Ship deploys only the images
that the action reports.

The action fetches the registry, the credentials, and the build settings from
ship on each run. A change to the app's settings in the dashboard takes effect
on the next run. You do not change the workflow file.

## Usage

```yaml
name: "ngrok ship (web)"

on:
  push:
    branches: ["main"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: ngrok/ship-action@v1
        with:
          app-id: "app_2abc..."
```

### Permissions

| Permission | Why |
| -- | -- |
| `id-token: write` | The action authenticates to ship with a GitHub OIDC token. Ship gives build config only to workflows in the repository that the app is connected to. |
| `packages: write` | Needed only when the app publishes to GitHub Container Registry. |
| `contents: read` | Needed by `actions/checkout`. |

Pull requests from forks get no OIDC token, so the action cannot run for them.

### Check out the default ref

The action builds and tags `github.sha`. On a `pull_request` run, that is
GitHub's merge of the PR into its base, so the preview runs what the merge
will ship. Ship shows the preview as the PR's head commit. Keep the default
checkout: the action warns when the checkout and the tag differ.

### Build only what changed

The action is a step in your own job. Gate it like any other step. A pull
request gets a preview of the app only when the action runs for it.

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
  # dorny/paths-filter lists the PR's changed files through the API.
  pull-requests: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: dorny/paths-filter@v3
        id: changes
        with:
          filters: |
            web:
              - "web/**"
      - if: steps.changes.outputs.web == 'true'
        uses: ngrok/ship-action@v1
        with:
          app-id: "app_2abc..."
```

## Inputs

| Input | Required | Description |
| -- | -- | -- |
| `app-id` | yes | The ship app to build. |
| `api-url` | no | The ship base URL. The default is production. |
| `context` | no | The build root, relative to the repository. The default is the build root in the app's settings. |

## Outputs

| Output | Description |
| -- | -- |
| `image` | The pushed image reference, tagged with the commit SHA. |

The commit SHA is `github.sha`. On a `pull_request` run, that is GitHub's
merge of the PR into its base.

## Versions

Releases use semver tags. The `v1` tag moves to each compatible release, so
`@v1` gets fixes with no change to your workflow. A breaking change gets a
new major tag.

## Development

`.github/workflows/e2e.yml` runs this checkout of the action against a ship
environment. Run it against staging before a release tag moves.
