This project adapts selected features from [ac54u-mobile/Aweme](https://github.com/ac54u-mobile/Aweme), commit `a7138914a7de63bfc6964e622723d2fc75cbb2cc`.

The reference repository carries the MIT License, Copyright (c) 2024 huami. Its full license is retained in [third_party/Aweme-MIT-LICENSE.txt](third_party/Aweme-MIT-LICENSE.txt) and included with binary releases as `THIRD_PARTY_LICENSES.txt`.

Adapted parts: the offline city table (`CityManager.m` → `src/DARCityData.h`), IP timestamp display flow (`DYYY.xm` / `DYYYUtils.m`), native settings model and long-press menu composition (`DYYYSettings.xm` / `DYYYLongPressPanel.xm`), and the audio assistant folder/search/rename/share/batch-management UI plus explicitly prepared one-shot voice workflow (`DYYYAudioManager.m` / `DYYYVoiceViewController.m`).

The integration uses version-scoped Objective-C runtime hooks for the supplied Douyin 41.2.0 binary and introduces separate persisted switches. It does not include the reference repository's global file-manager interception, unrelated hooks, remote configuration, or voice effects.
