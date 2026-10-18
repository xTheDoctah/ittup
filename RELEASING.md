# Releasing ITTup

ITTup reaches users on three channels of growing stability. The release flow of release-please is
unchanged: the dev and rc channels are added around it.

| Channel | Stability | Audience | From | Published to | Install |
|---|---|---|---|---|---|
| **dev** | Low | Team | every commit on `main` | workflow artifact; TestPyPI when enabled | `pip install --pre -i https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple/ ittup` or `pip install git+https://github.com/xTheDoctah/ittup@main` |
| **rc** | Medium-high | Testers | tag `X.Y.ZrcN` | PyPI, as a pre-release | `pip install --upgrade --pre ittup` or `pip install ittup==X.Y.ZrcN` |
| **release** | High | Everybody | release-please's release PR | PyPI | `pip install --upgrade ittup` |

pip ignores pre-releases (`.dev`, `rc`) without `--pre`, and the update check of ITTup only compares final
releases, so normal users never get a pre-release by mistake.

## Versions (PEP 440)

`MAJOR` for breaking changes (command line, config or data format), `MINOR` for compatible features,
`PATCH` for compatible fixes.

| Channel | Format | Example |
|---|---|---|
| dev | `X.Y.Z.devN` | `1.12.2.dev5` |
| rc | `X.Y.ZrcN` | `1.13.0rc2` |
| release | `X.Y.Z` | `1.13.0` |
| patch | `X.Y.Z+1` | `1.13.1` |

**Where the version comes from.** release-please is the only one that writes the version, in
`pyproject.toml`, `.release-please-manifest.json` and `CHANGELOG.md`, in its release PR: never edit them by
hand (CLAUDE.md). Tags have no `v` prefix (`1.13.0`, like every release so far). The dev and rc versions are
written into `pyproject.toml` only inside the CI workspace, at build time (`.github/scripts/set-version.sh`),
and never committed. That is why the project doesn't use `hatch-vcs`/`setuptools-scm`: release-please and the
existing tags stay the single source of the version.

## dev

[`dev.yml`](.github/workflows/dev.yml), after `Tests` passes on a push to `main`:

1. Version: the patch after the last release, plus the commits since it (`1.12.1` + 5 commits → `1.12.2.dev5`):
   it sorts after the last release and before any next one.
2. Build, `twine check`, smoke and end-to-end tests **on the installed wheel** in a clean virtualenv.
3. The wheel and the sdist are kept as the workflow artifact `dist-dev`.
4. Published to TestPyPI only when the repository variable `TESTPYPI_PUBLISH` is `true`
   (TestPyPI trusted publisher: workflow `dev.yml`, environment `dev`).

Unfinished features on main stay behind an option of the config (as the existing `*_SCSHOT` options),
off by default.

## rc

At the feature freeze of a milestone:

1. Only fixes, tests and docs get merged into `main` until the release.
2. release-please's release PR shows the next version, e.g. `1.13.0`. Tag the head of `main` (the commit the
   release PR is based on):

   ```bash
   git fetch origin && git tag 1.13.0rc1 origin/main && git push origin 1.13.0rc1
   ```

3. [`rc.yml`](.github/workflows/rc.yml) checks the tag (format, newer than the last release, not released
   yet), runs the full test matrix with `pip-audit` blocking and the Windows unit tests, builds `1.13.0rc1`,
   tests the wheel, publishes it on PyPI as a pre-release (environment `staging`), installs it back from PyPI
   and prints the install command for the testers in the run summary.
4. **Soak period**: at least 3-5 days of real use, following [docs/release-testing.md](docs/release-testing.md).
5. Every fix (`fix:` PR on main) → a new tag `1.13.0rc2` on the new head of main, and the soak starts over
   if the fix was significant.

PyPI needs a trusted publisher for workflow `rc.yml` and environment `staging` (once, see "Setup" below).

## release

1. Merge release-please's release PR (both developers agree: one approves the PR, the other approves the
   deployment). Don't merge anything else between the last rc and the release PR.
2. [`publish.yml`](.github/workflows/publish.yml), as before: release-please creates the tag `X.Y.Z` and the
   GitHub release with the changelog; the build checks the tag matches `pyproject.toml`.
3. New checks: the release must be **the code of its last rc** (`X.Y.ZrcN`): only the version and the
   changelog may differ. Without an rc, or with a different code, it is a warning; the repository variable
   `STRICT_RELEASE=true` makes it an error. `pip-audit` warns.
4. The `pypi` environment waits for the **manual approval** of a maintainer, then publishes to PyPI with
   trusted publishing. Its name is the one in the PyPI trusted publisher: don't rename it.
5. Smoke test: `pip install ittup==X.Y.Z` from PyPI in a clean virtualenv, then `ittup --help`.

## Patch releases and hotfixes

**Usual case**: main has nothing unreleased that can't go out. The fix is a `fix:` PR on main (with a
regression test), release-please proposes `X.Y.Z+1`, an rc is optional, merge the release PR.

**main has unreleased changes that can't go out yet**:

1. `git switch -c release/1.13 1.13.0 && git push origin release/1.13` (from the release tag).
2. A branch `hotfix/1.13.1` from `release/1.13`, the fix plus a regression test, a `fix:` PR to `release/1.13`.
3. On `release/1.13`, release-please opens its own release PR for `1.13.1` (`publish.yml` runs on
   `release/**` too). An rc is optional: tag `1.13.1rc1` on the head of `release/1.13`.
4. Merge that release PR: `1.13.1` is tagged on `release/1.13` and published, as for main.
5. Cherry-pick the fix to main (`git cherry-pick -x`, PR to main). If main's next release would be a patch too,
   add the footer `Release-As: 1.13.2` to a commit on main so release-please doesn't propose `1.13.1` again.
6. Delete `hotfix/*` after the merge; delete `release/1.13` when 1.13 is no longer supported (the tags stay).

## Rollback

- **PyPI**: *yank* the broken version (it stays installable only when asked for explicitly) and publish a
  patch at once, or tell the users the previous version: `pip install ittup==X.Y.Z`.
- Note the rollback in the changelog (through a commit or the next release notes) and open a P0 issue with a
  regression test.
- Within the same `MAJOR`, the config and the data stay backwards compatible, so going back to the previous
  version always works.
- A published version is never overwritten (PyPI doesn't allow it anyway): a mistake is fixed with a new version.

## CI environments

| Environment | Channel | Protection |
|---|---|---|
| `dev` | dev | None, automatic |
| `staging` | rc | Only tags `*rc*` |
| `pypi` (production) | release | Only tags `[0-9]*.[0-9]*.[0-9]*` and branches `main`, `release/*`, plus a required reviewer |
| `github-pages` | docs | As before (`docs.yml`) |

## Setup (once per repository)

Already applied on `xTheDoctah/ittup`. On another repository (e.g. the upstream one):

- Settings → Environments: create `dev`, `staging`, `pypi` with the protections above; on `pypi` add both
  maintainers as required reviewers.
- PyPI → ittup → Publishing: trusted publishers for `publish.yml` + `pypi` (exists) and `rc.yml` + `staging`.
  TestPyPI: `dev.yml` + `dev`, then set the variable `TESTPYPI_PUBLISH=true`.
- Rulesets: `main` and `release/*` without direct push and deletion, PR with 1 approval and the required checks
  (`pytest`, `quality`, `build`, `conventional-commits`, `dco`); tags without update and deletion.
- Settings → General: "Automatically delete head branches", Issues and Discussions on; Actions → "Require
  approval for all external contributors".
- Run the `Labels` workflow once.

## Checklists

**Feature freeze → rc**: P0/P1 done or explicitly postponed · no AI PR pending for this milestone · tag
`X.Y.0rc1` · `rc.yml` green (tests, matrix, smoke from PyPI) · `pip install --pre ittup==X.Y.0rc1` checked in a
clean environment · testers told, [release-testing checklist](docs/release-testing.md) shared.

**rc → release**: soak period passed · no open blocking/critical bug · `pip-audit` clean (rc run) · release
PR changelog reviewed · nothing merged after the last rc · manual tests of the rc done · ok of both
developers (PR approval + `pypi` deployment approval) · smoke after publishing green, GitHub release published.
