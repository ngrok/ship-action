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

The `COMMIT_SHA` build argument is also `github.sha`, so on a pull request
it is a commit that is not in the PR. An app that shows its version can take
the head commit from a build argument of its own:

```yaml
build-args: |
  APP_VERSION=${{ github.event.pull_request.head.sha || github.sha }}
```

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

A path filter sees only the paths that you list. In a monorepo, a change to
a shared workspace package also changes the app, and `web/**` does not match
it. Gate the step with a check that knows the dependency graph, such as
`turbo ls --affected`.

### Monorepos

Run the action one time for each app, each with its own `app-id`. A job that
finds the affected apps can feed a matrix. A leg that does not run makes no
release and no preview.

```yaml
jobs:
  build:
    needs: changes
    strategy:
      matrix:
        app_id: ${{ fromJSON(needs.changes.outputs.app_ids) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - id: node
        run: echo "version=$(cat .nvmrc)" >> "$GITHUB_OUTPUT"
      - uses: ngrok/ship-action@v1
        with:
          app-id: ${{ matrix.app_id }}
          build-args: |
            NODE_VERSION=${{ steps.node.outputs.version }}
          secrets: |
            TURBO_TOKEN=${{ secrets.TURBO_TOKEN }}
            TURBO_TEAM=${{ vars.TURBO_TEAM }}
```

### Build arguments and secrets

`build-args` and `secrets` apply to an app that builds from a Dockerfile.
The action cannot read your repository's secrets, so pass each one in
`secrets`. The Dockerfile mounts a secret by its id:

```dockerfile
RUN --mount=type=secret,id=TURBO_TOKEN,env=TURBO_TOKEN pnpm build
```

A secret does not go into the image or the layer cache. A build argument
does, so do not put a credential in `build-args`.

### Layer cache

The action keeps the build's layers in the GitHub Actions cache, in a scope
for each app. Set `cache: "false"` to turn off the import and export of that
cache. A builder that the job set up can still use its own local layers.

The cache needs a Buildx builder. If the job has one, such as a builder from
`docker/setup-buildx-action`, the action uses it. If not, the action sets
one up.

### Preview URLs

The action has no URL output. Ship writes one comment on the pull request and
keeps it up to date. The comment lists each app's preview and its URLs, so
you do not need a comment step of your own.

### Cancelled runs

Ship starts the release when the action asks for the build config, so the
build shows in ship before the image is there. A run that stops before the
action reports the image deploys nothing. This includes a run that
`concurrency: cancel-in-progress` stops.

Ship follows the runs of the workflow file that it added for the app, and
marks the release of a cancelled or failed run as failed. Ship does not
follow a run of another workflow file, such as one matrix workflow for many
apps. The release of such a run shows as building until a later release
replaces it.

## Inputs

| Input | Required | Description |
| -- | -- | -- |
| `app-id` | yes | The ship app to build. |
| `api-url` | no | The ship base URL. The default is production. |
| `context` | no | The build root, relative to the repository. The default is the build root in the app's settings. |
| `build-args` | no | Build arguments for a Dockerfile build, one `NAME=value` on each line. The action also sets `COMMIT_SHA`. |
| `secrets` | no | BuildKit secrets for a Dockerfile build, one `id=value` on each line. |
| `cache` | no | Set to `"false"` to turn off the import and export of the GitHub Actions layer cache. The default is `"true"`. |

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

To pin the action, use the commit SHA of a release. The action pins each
action that it calls to a commit SHA, and it checks the sha256 of the
Railpack release that it downloads.

## Development

`.github/workflows/e2e.yml` runs this checkout of the action against a ship
environment. Run it against staging before a release tag moves.

Dependabot updates the pinned actions. It does not update Railpack: change
the version, the checksums, and the frontend digest in
`scripts/install-railpack.sh` together.
