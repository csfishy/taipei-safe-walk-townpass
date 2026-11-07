# Checks, prereleases and GitHub Pages

CI／Demo 資料庫 gate：兩份工作流的 runner-local PostGIS 初始化、雙重重設與安全測試都是必要檢查。遠端另以 **Repository Actions Variable `DEMO_DATABASE_RESET_ENABLED`** 控制；未設定或精確值 `false` 表示未啟用，遠端 job 預期跳過，全部檢查及建置成功後仍可執行既有 main prerelease／Pages，Summary 明示未重設遠端，不能宣稱 Demo 已就緒。精確值 `true` 才啟用 main 的單一遠端 reset；啟用後必須成功，缺白名單／Secrets／marker／角色或失敗、取消、非預期跳過都阻擋後續發布。其他值使配置檢查失敗。版本 tag 不重設共享 Demo。啟用須另完成 Level C 審查，見 [隔離資料庫重設](SAFE_WALK_DATABASE_RESET.md)。

The delivery policy is [LIVE-FIRST / NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md), with full user-flow acceptance in [Live MVP](SAFE_WALK_LIVE_MVP.md) and per-capability evidence in [Readiness](SAFE_WALK_LIVE_READINESS.md). Production must use real providers or show Unavailable with the true blocker and next step; Fake, Mock and fixtures belong only in isolated Unit/Integration tests. New features do not require a prior Mock/Demo/Prototype. A successful build, prerelease or Pages deployment does not verify real providers or iPhone behavior.

The current main baseline `7b99fea` still has a Mock production entry after #49 restored `3c433001` and removed #35's P0 wiring. This is a pending implementation gap, not a compliant delivery or a new runtime gate added by this document. #39 is merged into a feature branch, #44 remains open, and #47's explicit Demo activation fix is also pending; the #40 database gate described above remains in main. Competition delivery excludes Google Maps and AED functionality. Production switches, database permissions and deployment still require the applicable Level C review.

The `check-and-build` workflow runs on main pushes, pull requests, matching `v*-pre.*` tags, and manual dispatch. Flutter is pinned to `.fvmrc`'s 3.47.6 and dependencies are installed with `--enforce-lockfile`; code generation runs on every clean checkout.

Each run has its own build concurrency group, so a newer push does not cancel active builds. Remote Demo reset jobs additionally share the `safe-walk-demo-database` concurrency group and a database transaction advisory lock. Website deployment is serialized separately; stale builds skip deployment so they cannot replace a newer main website.

The check job runs the analyzer with errors/warnings fatal and existing style-level infos advisory, the real start-page preference tests, and Chrome tests of the browser guards with a typed device-plugin fixture. All three build jobs depend on this check. Android uses JDK 21 and the repository's Gradle/SDK settings. iOS uses macOS 15 and Xcode 26.1.1, required by the locked device_info_plus package. Native packaging requires no private signing credentials.

The merged initialization's Safe Walk schemas, generator consistency, upstream history/module boundaries, strict scoped analysis and complete test suite are included. Its two route contract tests are preserved in `test/route_contract_test.dart`, alongside the added preference and browser tests. No Safe Walk payload, generated model or service contract is changed. Full analysis with fatal infos remains separately reported by the existing Safe Walk workflow; the build gate permits existing style infos while rejecting errors and warnings.

Every **push to main** automatically publishes a GitHub prerelease after mandatory local database tests, checks, all three platform builds, and the Demo activation gate pass. The `check` job parses the repository variable once and exports an enabled/disabled snapshot used by both reset and publication decisions; changing the variable later does not silently change that run's decision. With remote reset disabled, only its expected skip is allowed; current builds do not consume `safe_walk_demo`, so their existing publication can continue. With reset enabled, its success is required; failure, cancellation, or an unexpected skip never opens the publication gate. No version edit or manual tag is needed. For example, workflow run 42 at commit `31cb0ac12345…` builds version `0.0.12-pre.42.g31cb0ac12345` and creates tag `v0.0.12-pre.42.g31cb0ac12345` at that exact source commit. The numeric base comes from pubspec; the run number and commit identify the build. A push containing several commits builds its head commit once. Unpushed local commits and feature branches do not publish; a failed check/build prevents publication.

Manual prerelease tag pushes remain supported: the tag must match the pubspec version without `+BUILD`, such as `v0.0.12-pre.1` for `0.0.12-pre.1+1`. PR and manual-dispatch runs only retain downloadable artifacts, including dispatch against a tag. The workflow run number is the native build number; iOS uses the numeric marketing version (`0.0.12`) and preserves the full prerelease version in embedded metadata. Never move a published tag.

Publication stages all five assets in a draft before publishing. A rerun resumes an unfinished matching draft or keeps an already complete matching prerelease; it refuses a tag pointing to another commit or an incomplete published release. Releases are marked prerelease and do not replace a stable release's Latest designation. Automatic tags use the built-in `GITHUB_TOKEN`, whose tag pushes [do not recursively trigger another workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow).

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

Use a real Python 3 interpreter. On Windows, use `py -3` or an installed `python.exe` if `python3` is only an App Execution Alias; WSL is optional and must be installed separately. iOS compilation requires macOS. `assets/build-info.json` and Dart-generated sources are generated and ignored; generate metadata before `pub get`. Locked dependency versions are retained. Unsigned IPA packaging uses `ditto` to zip `Payload/Runner.app`, not App Store export.

## GitHub Pages owner setup

The connected account may have Write access without permission to manage Pages. A repository owner/admin or a user with Manage Pages permission must:

1. Confirm Pages is available for this repository. This project is Public; if visibility changes later, check the plan and supported website audience. This workflow does not change repository visibility.
2. In Settings → Pages, set Source to **GitHub Actions**.
3. Allow `main` in the `github-pages` environment's deployment rules. Approve any configured environment deployment gates. Tag builds provide a web ZIP; the hosted website deploys from main.
4. Run/re-run the workflow or its Pages settings job after the setting is enabled. Manual dispatch becomes available once the workflow exists on the default branch.

On main runs, Pages also requires the same Demo activation gate described above, including manual dispatch on main. The workflow checks the actual Pages configuration and deploys the checked web artifact only when `build_type` is `workflow` and its source is still the current main commit. Missing Pages settings or stale source skip deployment with a summary; they do not falsely mark a website as published. This does not excuse a missing or failed remote reset when reset was enabled. Release publication does not depend on Pages deployment. The GitHub Pages job's returned URL is the deployment result. Private repository source does not automatically mean its Pages website is private; the owner must choose the supported audience.

The expected default project URL is `https://csfishy.github.io/taipei-safe-walk-townpass/`; it is only a target until deployment has succeeded. The web ZIP includes `.nojekyll` and uses hash routes. A GitHub release download is not a hosted website.

Preview limitations and installation instructions are in [PRERELEASE-NOTES.md](PRERELEASE-NOTES.md). These workflow checks do not configure branch protection or required-check rules.

## Native release package verification

Before native artifacts are uploaded, `tool/verify_native_release.py` checks package integrity and compares the embedded metadata with this workflow's generated source/version/build metadata. Android must include compiled DEX, the preview application identifier, and an arm64 Flutter AOT library; `apksigner` separately verifies its test signature. iOS must contain an unsigned arm64 iPhone app with the preview bundle identifier, matching marketing/build versions, and no app signature/provisioning profile. Device/runtime behavior remains a separate verification step.

To check downloaded native packages, pass their matching downloaded `build-info.json`:

```sh
python3 tool/verify_native_release.py android path/to/preview.apk --metadata path/to/build-info.json
python3 tool/verify_native_release.py ios path/to/unsigned.ipa --metadata path/to/build-info.json
```
