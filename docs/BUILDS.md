# Checks, prereleases and GitHub Pages

The `check-and-build` workflow runs on main pushes, pull requests, matching `v*-pre.*` tags, and manual dispatch. Flutter is pinned to `.fvmrc`'s 3.47.6 and dependencies are installed with `--enforce-lockfile`; code generation runs on every clean checkout.

The check job runs the analyzer with errors/warnings fatal and existing style-level infos advisory, the real start-page preference tests, and Chrome tests of the browser platform services. All three build jobs depend on this check. Android uses JDK 21 and the repository's Gradle/SDK settings. iOS uses macOS 15 and Xcode 26.0. Native packaging requires no private signing credentials.

The merged initialization's Safe Walk schemas, generator consistency, upstream history/module boundaries, strict scoped analysis and complete test suite are included. Its two route contract tests are preserved in `test/route_contract_test.dart`, alongside the added preference and browser tests. No Safe Walk payload, generated model or service contract is changed. Full analysis with fatal infos remains separately reported by the existing Safe Walk workflow; the build gate permits existing style infos while rejecting errors and warnings.

Prerelease tags must match the pubspec version without `+BUILD`: for `0.0.12-pre.1+1`, push `v0.0.12-pre.1`. Only tags publish a GitHub prerelease, after all platform builds pass. The workflow run number is the native build number; iOS uses the numeric version (`0.0.12`) and the full prerelease version is preserved in build metadata. PR/main/manual runs retain downloadable artifacts without publishing a release. Never move a published tag.

## Local checks and builds

```sh
python3 tool/release_metadata.py
flutter pub get --enforce-lockfile
dart run build_runner build
flutter analyze --no-fatal-infos
flutter test
flutter test --platform chrome test/web_startup_test.dart
flutter build apk --release
flutter build ios --release --no-codesign
flutter build web --release --base-href /taipei-safe-walk-townpass/ --no-web-resources-cdn
```

Use a real Python 3 interpreter; on the Windows verification host, Python is available through WSL. iOS compilation requires macOS. `assets/build-info.json` and Dart-generated sources are generated and ignored; generate metadata before `pub get`. Locked dependency versions are retained. Unsigned IPA packaging uses `ditto` to zip `Payload/Runner.app`, not App Store export.

## GitHub Pages owner setup

The connected account may have Write access without permission to manage Pages. A repository owner/admin or a user with Manage Pages permission must:

1. Ensure the GitHub plan supports Pages from this private repository. This workflow does not change repository visibility.
2. In Settings → Pages, set Source to **GitHub Actions**.
3. For deployment from prerelease tags, allow matching `v*-pre.*` tags in the `github-pages` environment's deployment rules. Deployments from main need that branch allowed. Approve any configured environment deployment gates.
4. Run/re-run the workflow or its Pages settings job after the setting is enabled. Manual dispatch becomes available once the workflow exists on the default branch.

On non-PR runs, the workflow checks the actual Pages configuration and deploys the checked web artifact only when `build_type` is `workflow`. Missing settings skip deployment with a summary; they do not falsely mark a website as published. The GitHub Pages job's returned URL is the deployment result. Private repository source does not automatically mean its Pages website is private; the owner must choose the supported audience.

The expected default project URL is `https://csfishy.github.io/taipei-safe-walk-townpass/`; it is only a target until deployment has succeeded. The web ZIP includes `.nojekyll` and uses hash routes. A GitHub release download is not a hosted website.

Preview limitations and installation instructions are in [PRERELEASE-NOTES.md](PRERELEASE-NOTES.md). These workflow checks do not configure branch protection or required-check rules.
