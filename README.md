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
        with:
          # Build the PR's head commit, not GitHub's test merge commit.
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
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

### Check out the commit you build

For a `pull_request` run, the action tags the image with the PR's head
commit, and ship deploys it as that commit. The default checkout on a
`pull_request` run is a test merge commit, so check out the head commit as the
example shows. The action warns when the checkout and the tag differ.

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
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
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

The commit SHA is the pull request's head commit for a `pull_request` run,
and `github.sha` for every other run.

## Versions

Releases use semver tags. The `v1` tag moves to each compatible release, so
`@v1` gets fixes with no change to your workflow. A breaking change gets a
new major tag.

## Development

`.github/workflows/e2e.yml` runs this checkout of the action against a ship
environment. Run it against staging before a release tag moves.
