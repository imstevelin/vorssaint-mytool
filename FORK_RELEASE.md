# 實用小工具 1.2.0

- HiDPI 預設改為原生縮放，使用單一開關；依每台螢幕實際能力選擇解析度與更新率，必要時在同次操作完成系統準備。保留安全倒數、模式／ICC 驗證、受保護備份與還原；既有虛擬鏡像設定保持相容。
- 加強虛擬 HiDPI 游標重繪恢復、輸入觀察及有界診斷；不宣稱所有觸控板卡頓都已解決。
- DDC 亮度在啟動、重接、睡醒與閒置後重新確認硬體基準，避免以錯誤預設值調整。
- 全螢幕隱藏島時，音量與靜音仍由 App 接管，使用與亮度相同的中央卡片。
- 視窗尺寸與位置記憶優先採用最新手動選擇，避免舊文件最大化記錄覆蓋後續調整。
- 完整移除游標輸入來源指示器。
- 保留未公開 1.1.1 的音量回饋例外防護及 HiDPI 重接修正。整合 PR #7、#8、#9，沿用正式 bundle ID 與設定。
- 藍牙喇叭本次故障未修復；重啟 Bluetooth、直接聲道控制、重開喇叭及退出 App 均未恢復。依使用者決定停止排查，不新增無效的手動重啟按鈕。
- Apple Silicon；Apple Development 簽署，未公證。各硬體與長時間情境的驗收限制保留於發版紀錄。

# 實用小工具 1.1.1（變更納入 1.2.0，未獨立發版）

- 修正螢幕／HDMI 音訊輸出切換時，音量回饋播放器啟動例外導致 App 崩潰；同一輸出恢復後可在下一次點按重新建立播放器，保留每次音量操作的獨立回饋。
- 未手動選擇刷新率時，套用 HiDPI 會即時取得實體螢幕刷新率，避免冷啟動快取的 60Hz 預設值；切換螢幕時清除上一台的選擇，驗證時檢查實體端刷新率。
- HiDPI 自動重接改為等待模式、AppKit 與 ICC 連續穩定，並等待舊虛擬螢幕完成清理；本次使用者拔插驗收未再出現色彩閃爍。Dia 重接後仍可能只呈現 60fps，依使用者決定暫不追修，不宣稱已修復。
- 確認原有功能／發版／同步分支的提交都已包含在 main，保留完整歷史並清理已整合分支。

# 實用小工具 1.1.0

- 整合官方 71 筆提交至 `597f27a6`，包含錄影／GIF、AI 使用量與多帳號、音量、視窗音訊、島佈局及工具面板修正。
- 保留獨立品牌與更新來源、顯示恢復、每顯示器視窗尺寸與位置記憶、指定藍牙裝置政策、每下音量回饋及五種自訂小夥伴。
- 接回展開島的小夥伴事件反應與游標互動，修正 Command 圖示畫布，改善 AI 掃描取消與錄影資料處理。
- 建立上游同步基準、客製回歸契約、雙環境 CI、可回退整合及每週一／四上游監測。
- Apple Silicon；本地 Apple Development 簽署，未公證。實體螢幕重接、藍牙音訊、長錄影與耗電比較仍需實機驗收；不把自動測試視為硬體驗證。

# 實用小工具 1.0.9

- 重新設計正面幼犬：圓潤臉頰、短垂耳、大眼睛、小鼻子與微笑，移除厚重鼻口框及側邊尾巴。
- 五款自訂動物依可見輪廓放大至外框約 98% 高度，改善下半部留白。
- 放大後仍依可見輪廓垂直置中，保留全程正面及原有表情動作。

# 實用小工具 1.0.8

- 所有小夥伴恢復原本的正面造型，待機及來訪不再切換成全身側面或轉身。
- 縮小小狗的垂耳及小熊的圓耳，改善小尺寸下的臉部比例。
- 保留單色、垂直置中、自然表情動作與 26–36 秒自主來訪。

# 實用小工具 1.0.7

- 小夥伴統一為白色單色輪廓，移除配色選項與彩色裝飾。
- 重畫狗狗長垂耳、寬鼻口，以及小熊較小的圓耳與寬臉。
- 依島目前的實際高度置中，所有身體姿態亦依可見輪廓置中。
- 動物可側身走入、轉正、朝鏡頭走來、坐下，貓咪也會整理毛與舔爪。
- 自主來訪延長至約 26–36 秒，閒置停留延長至一分鐘。

# 實用小工具 1.0.6

- Dynamic Island 小夥伴新增小貓、小狗、小熊、小狐狸與小兔，保留原有簡約與機器人。
- 所有角色增加自然呼吸與各自的待機習性。
- 自主出場增加探頭、探索、邀請互動、離開又回頭及嬉戲等多段橋段，避免連續重複。
- 邀請橋段中可看向游標及回應摸摸，並保留原有系統事件反應。
- 新動作遵循減少動態效果、低耗電及離開畫面時暫停的設定。

# 實用小工具 1.0.5

- 藍牙連線修復可指定多台裝置，只有勾選的裝置成為預設音訊輸出時才會重啟藍牙。
- 已選裝置離線後保留名稱與選擇；未勾選或清單為空時不會重啟。
- 更新後請至「設定 → 輸出切換器 → 藍牙喇叭連線修復」選擇需要修復的裝置。
- 保留重新連線防循環與 30 分鐘重啟間隔。

# 實用小工具 1.0.4

- 全面更新應用程式顯示名稱與 Command 圖示，沿用原有設定與權限識別。
- 已開啟的視窗在螢幕配置或解析度變更後重新套用對應尺寸。
- 排除對話框、子視窗、浮動面板及固定尺寸視窗。
- 左右並排、四分割及最大化不再覆蓋正常開啟尺寸。
- 舊版本已覆蓋的正常尺寸，請手動調整一次後重新記憶。

# vorssaint-imstevelin release

This is an unofficial fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils), maintained at [imstevelin/vorssaint-mytool](https://github.com/imstevelin/vorssaint-mytool). It is not an official Vorssaint build or endorsed by the upstream maintainer. The source remains GPL-3.0-or-later; see `LICENSE` and `TRADEMARKS.md`.

## 1.0.3

- Merge upstream `vorssaint-utils/main` through `794608a5` (44 commits), including recorder, clipboard, switcher, Dynamic Island, command bar, and settings fixes. Keep the fork's display memory, Bluetooth recovery, preference migration, branding, and update channel.
- Fix display size memory fighting manual window movement and resizing: apply a saved frame once per new window or display transition, wait for mouse interaction to finish, and learn the accepted size after it settles. Never retry an old frame when an app enforces size limits.
- Match Accessibility windows by WindowServer ID instead of position, avoiding changes to another overlapping window. Avoid redundant position writes on size-only changes.
- Reduce size detection polling from 3 seconds to 0.5 seconds and display-change debounce from 3 seconds to 0.6 seconds. Actual application response time varies.

## 1.0.2

- Optional Bluetooth speaker recovery in Sound Output Switcher settings. After one administrator authorization, a new Bluetooth default output can restart `bluetoothd` with a narrowly scoped command.
- Short disconnects, a persisted cooldown, and a reconnect marker prevent a restart loop. The feature is off by default and its authorization can be removed in Settings or during a full uninstall.

## 1.0.1

- On first launch, import compatible explicit preferences from the official Vorssaint app on the same Mac. The official preferences stay unchanged. If this fork has already completed setup, its own choices take priority.
- Reinstalling the app bundle keeps the fork’s preferences and private files. A deliberate full uninstall still removes them. macOS permissions belong to the fork’s bundle ID and may need to be granted once.
- Existing official settings backup files can be imported in Advanced Settings; older backups preserve the fork’s display memory switches.

## 1.0.0

- Two independent Window Layout switches: remember each app window’s size per display, and restore still-open windows to their saved size and position when a display reconnects.
- Separate bundle identity, icon, update feed, and manual update path for this fork.

## Build and update

Run `./build.sh` and `./Tools/make-dmg.sh` on macOS with Xcode or Command Line Tools. The bundle is `build/stage/實用小工具.app` with bundle identifier `com.imstevelin.vorssaint-imstevelin` and a fork-specific icon. The release build uses the local Apple Development signing identity when present. This identity is not a Developer ID distribution certificate, and the DMG is not notarized. A Mac may require a manual Open action in System Settings after download.

The app checks only this fork's GitHub Releases. Its update button opens the fork's release page for manual installation. It never runs the upstream automatic installer, whose signature check is tied to the upstream team and bundle ID.

For upstream integration and the independent release cadence, see [docs/UPSTREAM_MAINTENANCE.md](docs/UPSTREAM_MAINTENANCE.md) and [the first integration record](docs/upstream-sync/2026-10-18.md). Development is consolidated on the fork's `main`, uses short-lived integration branches with normal merges, and validates fork behavior before tagging a release. Source integration does not publish a new release.
