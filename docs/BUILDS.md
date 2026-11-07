# Checks, prereleases and GitHub Pages

CI／Demo 資料庫 gate：兩份工作流的 runner-local PostGIS 初始化、雙重重設與安全測試都是必要檢查。遠端另以 **Repository Actions Variable `DEMO_DATABASE_RESET_ENABLED`** 控制；未設定或精確值 `false` 表示未啟用，遠端 job 預期跳過，全部檢查及建置成功後仍可執行既有 main prerelease／Pages，Summary 明示未重設遠端，不能宣稱 Demo 已就緒。精確值 `true` 才啟用 main 的單一遠端 reset；啟用後必須成功，缺白名單／Secrets／marker／角色或失敗、取消、非預期跳過都阻擋後續發布。其他值使配置檢查失敗。版本 tag 不重設共享 Demo。啟用須另完成 Level C 審查，見 [隔離資料庫重設](SAFE_WALK_DATABASE_RESET.md)。

The delivery policy is [LIVE-FIRST / NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md), with full user-flow acceptance in [Live MVP](SAFE_WALK_LIVE_MVP.md) and per-capability evidence in [Readiness](SAFE_WALK_LIVE_READINESS.md). Production must use real providers or show Unavailable with the true blocker and next step; Fake, Mock and fixtures belong only in isolated Unit/Integration tests. New features do not require a prior Mock/Demo/Prototype. A successful build, prerelease or Pages deployment does not verify real providers or iPhone behavior.

Historical baseline `7b99fea` followed #49's restoration and had not yet restored Live wiring. That snapshot is not the current release state: native crime-query configuration and verification are described below and in [Supabase setup](SAFE_WALK_SUPABASE.md). Assess each release using its source commit and recorded evidence. Competition delivery excludes Google Maps and AED functionality. Production switches, database permissions and deployment still require the applicable Level C review.

The `check-and-build` workflow runs on main pushes, pull requests, matching `v*-pre.*` tags, and manual dispatch. Flutter is pinned to `.fvmrc`'s 3.47.6 and dependencies are installed with `--enforce-lockfile`; code generation runs on every clean checkout.

Each run has its own build concurrency group, so a newer push does not cancel active builds. Remote Demo reset jobs additionally share the `safe-walk-demo-database` concurrency group and a database transaction advisory lock. Website deployment is serialized separately; stale builds skip deployment so they cannot replace a newer main website.

The check job runs the analyzer with errors/warnings fatal and existing style-level infos advisory, the real start-page preference tests, and Chrome tests of the browser guards with a typed device-plugin fixture. All three build jobs depend on this check. Android uses JDK 21 and the repository's Gradle/SDK settings. iOS uses macOS 15 and Xcode 26.1.1, required by the locked device_info_plus package. Native packaging requires no private signing credentials.

The merged initialization's Safe Walk schemas, generator consistency, upstream history/module boundaries, strict scoped analysis and complete test suite are included. Its two route contract tests are preserved in `test/route_contract_test.dart`, alongside the added preference and browser tests. No Safe Walk payload, generated model or service contract is changed. Full analysis with fatal infos remains separately reported by the existing Safe Walk workflow; the build gate permits existing style infos while rejecting errors and warnings.

Every **push to main** automatically publishes a GitHub prerelease after mandatory local database tests, checks, all three platform builds, and the Demo activation gate pass. The `check` job parses the repository variable once and exports an enabled/disabled snapshot used by both reset and publication decisions; changing the variable later does not silently change that run's decision. With remote reset disabled, only its expected skip is allowed; current builds do not consume `safe_walk_demo`, so their existing publication can continue. With reset enabled, its success is required; failure, cancellation, or an unexpected skip never opens the publication gate. No version edit or manual tag is needed. For example, workflow run 42 at commit `31cb0ac12345…` builds version `0.0.12-pre.r0000000042.g31cb0ac12345` and creates tag `v0.0.12-pre.r0000000042.g31cb0ac12345` at that exact source commit. The numeric base comes from pubspec; the run number and commit identify the build. A push containing several commits builds its head commit once. Unpushed local commits and feature branches do not publish; a failed check/build prevents publication.

GitHub's Releases list can order prerelease suffixes alphabetically, placing legacy `pre.84` above `pre.135`. Automatic versions now use `pre.r` plus a ten-digit zero-padded run number so the list stays ordered across counter-width changes and new builds appear above legacy numeric suffixes. The letter prefix makes the padding valid [SemVer](https://semver.org/#spec-item-9). Native build numbers remain unpadded integers. Existing published tags and assets are preserved, and the native verifier accepts both legacy and current version formats.

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
# Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in the local process first.
dart tool/prepare_native_client_config.dart secrets/native-client.json
flutter build apk --release --dart-define-from-file=secrets/native-client.json
flutter build ios --release --no-codesign --dart-define-from-file=secrets/native-client.json
flutter build web --release --base-href /taipei-safe-walk-townpass/ --no-web-resources-cdn
```

Use a real Python 3 interpreter. On Windows, use `py -3` or an installed `python.exe` if `python3` is only an App Execution Alias; WSL is optional and must be installed separately. iOS compilation requires macOS. `assets/build-info.json` and Dart-generated sources are generated and ignored; generate metadata before `pub get`. Locked dependency versions are retained. Unsigned IPA packaging uses `ditto` to zip `Payload/Runner.app`, not App Store export.

## Native public client configuration

Android and iPhone release builds require the repository Actions variable
`SUPABASE_URL` and Actions secret `SUPABASE_PUBLISHABLE_KEY`. The latter is a
**public client key**, stored as a secret solely so GitHub masks it in runner
logs; it is necessarily embedded in the installed app. Never use a service-role
key, secret API key, database password, or administration token.

After package setup, `tool/prepare_native_client_config.dart` validates these
settings using the same `SafeWalkSupabaseConfig` parser as the app, then writes
only the two accepted values to `$RUNNER_TEMP/native-client.json`. Both native
build commands consume that file with `--dart-define-from-file`. A missing,
invalid, or elevated key fails the native job before compilation and therefore
blocks publication. The generated JSON is neither logged nor uploaded as an
artifact. The native package verifier also checks that the expected URL and
public key reached the compiled arm64 Flutter payload, without printing either
value. Local `secrets/` files are ignored and must not be committed.

Same-repository PR builds use the same configuration. Fork PRs do not receive
the key secret, so their native jobs deliberately fail configuration validation;
the shared unit-check job can still run. Do not substitute a dummy key to make
an installable but unusable artifact. Maintainers can run the reviewed change
on a trusted repository branch to validate native packages.

This build check verifies configuration syntax, not remote availability. The
reviewed read-only RPC, its permissions, snapshot validity, and an iPhone query
must also be verified before calling the feature live. Existing installed apps
need a newly built package; changing Actions settings alone cannot update their
compile-time values. Web builds retain their existing disabled browser-query
default and receive neither these values nor `SAFE_WALK_WEB_ROUTES=true`.

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
