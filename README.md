# 臺北安心行 · TownPass 原生開發基底

團隊 Repository：<https://github.com/csfishy/taipei-safe-walk-townpass>。安心行以官方 Flutter App 為主，原 React 專案保留為 Legacy；本次不建立新增 UI，完整設計交由 M3 莅紋後續負責。

先讀 [初始化與驗證](docs/SAFE_WALK_INITIALIZATION.md)、[架構](docs/SAFE_WALK_ARCHITECTURE.md)、[Schema](docs/SAFE_WALK_SCHEMA.md)、[五人模組](docs/SAFE_WALK_MODULES.md)、[顏色規範](docs/SAFE_WALK_COLOR_SPEC.md)、[競賽與授權待確認](docs/SAFE_WALK_COMPETITION_LICENSE.md) 及 [AGENTS.md](AGENTS.md)。初始化 PR 尚待確認合併，五個模組分支須在合併後從同一個基線建立。

下方保留官方 README；官方 Base 與完整歷史見 [來源紀錄](docs/SAFE_WALK_UPSTREAM.json)，原 GPLv3 LICENSE 保持不變。

# What is Town Pass?

Town Pass is an open-source project developed by the Taipei City Government. With the growth of smart cities, the demand for digitalization in city management and citizen services continues to rise. As we enter a new digital era, our goal is to involve citizens in the process, combining third-party expertise and innovation to make digital life in Taipei more convenient.

Town Pass is not just an application; it is an open community project. Through open-source, every citizen can participate in the ideation, development, and optimization of the application. This not only enhances citizen engagement and satisfaction but also leverages collective intelligence to continuously improve the application, making it truly serve the people. Furthermore, we hope that various municipalities can widely adopt the open-source framework of Town Pass, integrate it with their existing municipal service systems, and quickly have their own applications to enhance digital governance.

Open source is a key driver of technological progress and social development. Through open-source, Town Pass will become an ever-evolving platform, attracting developers from all backgrounds to contribute. We welcome experts to submit code, report issues, provide suggestions, and even develop new features and creative ideas, working together to perfect Town Pass as we advance toward a smart city.

# Getting Started

For CI checks, preview APK / unsigned IPA / Flutter Web builds, and GitHub Pages owner setup, see [Builds and deployment](docs/BUILDS.md). Previews use a separate app identity and are not official municipal-service releases.

We highly recommend to read through our [document](https://townpass.taipei/en/docs/) for more detail.

Here are some quick setup guide.

## Requirement

- [Flutter](https://docs.flutter.dev/get-started/install) or [FVM](https://fvm.app/documentation/getting-started/installation)
- [XCode](https://developer.apple.com/xcode/) (for iOS)
- [Android SDK](https://developer.android.com/studio/index.html) (for Android, with or without Android Studio)

## Build the Project

1. Get the packages project needed:

   ``` bash
   flutter pub get
   ```

2. Generate additional needed dart code for the project.

   ``` bash
   dart run build_runner build
   ```

3. You are all set now, Run the project from your IDE or the through the command line:

   ``` bash
   flutter run
   ```
