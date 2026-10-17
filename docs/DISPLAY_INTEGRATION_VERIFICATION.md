# 顯示器功能實作與驗證

日期：2026-10-17。實機：Apple Silicon、macOS 27.0.1、PA328QV。

## 已實作

- 在既有顯示器設定中加入 HiDPI 開關、常用與自訂邏輯解析度、刷新率選擇及 15 秒保留確認。
- 支援先使用原生 HiDPI 模式，必要時建立虛擬顯示器並讓實體螢幕鏡像其桌面。
- 獨立 `VirtualDisplayHost` 持有虛擬螢幕；停止其程序以確保 WindowServer 釋放物件。
- 獨立、非管理員 `DisplayRecoveryHelper` 保存原顯示模式、鏡像與排列，處理超時與主 APP 強制終止。
- 每台實體螢幕具有獨立 session；依 UUID 恢復已確認設定，拒絕歧義識別，重新連接後不改綁其他螢幕。自動恢復失敗不持續循環切換。
- 對比、音量及靜音接入原有亮度服務的串行 DDC 佇列，加入寫入合併、逐項探測、讀回確認與失敗顯示。
- 修正 GET checksum，並驗證回覆來源、長度、result、VCP code 與 checksum。
- 選單面板加入螢幕音量與靜音；設定頁加入對比及音訊輸出覆寫。後續更新已預設開啟原生按鍵及 HDMI／DisplayPort 音訊自動配對，並修正動態島 DDC 喇叭顯示，見 [NATIVE_DISPLAY_KEYS.md](NATIVE_DISPLAY_KEYS.md)。
- HiDPI 桌面與實體 DDC 路由分開；亮度按鍵、OSD 與視窗位置記憶辨識兩者的對應，切換期間暫停視窗配置學習。
- 本機裝置綁定及 HiDPI profile 不進入可攜設定備份。引入的 MIT notices 隨 APP 封裝。

DDC 範圍只有亮度、對比、音量與靜音；未新增輸入來源、電源或色彩控制。既有 APP 的其他顯示器功能保留。

## 實機結果

| 驗證 | 結果 |
| --- | --- |
| 亮度 | 25 → 26 → 25，實際 DDC 讀回符合 |
| 對比 | 80 → 85 → 80，寫入與還原均讀回確認 |
| 音量 | 0 → 5 → 0，寫入與還原均讀回確認 |
| 靜音 | 1 → 2 → 1，寫入與還原均讀回確認 |
| 1920×1080 HiDPI | 邏輯 1920×1080、backing 3840×2160 |
| 2560×1440 HiDPI | 邏輯 2560×1440、backing 5120×2880 |
| 未保留設定 | 兩種尺寸均在倒數後復原；完整顯示快照與切換前相同 |
| 保留後控制 | 實體螢幕卡片仍存在，DDC 音量仍可讀取 |
| 關閉 HiDPI | 兩種尺寸均恢復原模式、鏡像與排列 |
| 主 APP 被 SIGKILL | 2560×1440 HiDPI 下測試；復原程序回報 restored；另一程序取得的完整快照與切換前完全相同；無殘留 host／復原程序 |

自動化測試的顯示基準為 2560×1440、1×、75Hz，各回合均核對並還原該回合捕捉的 DDC 原值。最初基準為亮度 25、對比 80、音量 0、靜音 1；後續回合開始時曾讀到音量 5，因此該回合依即時讀值還原為 5。正式版介面另外確認可設回音量 0 並維持靜音。測試未安裝 EDID Override，未啟動 BetterDisplay。

正式版安裝後已從設定頁操作 HiDPI。最終另外以獨立程序讀取，確認目前保留的 2560×1440／5120×2880、75Hz 模式，實體螢幕鏡像至本 APP 的虛擬螢幕。安裝後已有已確認設定及介面操作，保留目前使用者選擇，不再套用測試前的顯示快照。

測試過程發現，單純照搬 HiDPIScaler 的 mode 順序可能得到 1× 桌面。此版本將邏輯 base mode 放在其 2× pixel mode 之前，並在鏡像後驗證雙軸 backing；建立成功不等於 HiDPI 成功。獨立 host 同時隔離模式快取與物件釋放的系統行為。

## 自動化及建置

- `display-restoration`：125 checks 通過，包含虛擬桌面向實體螢幕的亮度鍵路由。
- `features`：1172 checks 通過，包含標準亮度／音量／靜音 GET 封包與 unsupported 回覆拒絕。
- `notch`：71705 checks 通過。
- `settings`：502 checks 通過。
- `window-layout`：500 checks 通過。
- Swift Package 建置與正式 `build.sh` 管線均納入 Objective-C bridge、host、復原元件及授權檔。
- 最終五個 suite 一次執行，共 74004 checks 通過；正式安裝位於 `/Applications/實用小工具.app`，通過 deep／strict 簽章驗證及 Info.plist lint。
- 舊 APP 備份位於 `/Users/imstevelin/.local/share/vorssaint-backups/20261017-display-integration/實用小工具.app`。

開發版具有需明確 CLI 參數才能執行的實機驗證入口：`--verify-display-integration=<JSON 路徑>`，可加 `--verify-display-2560` 或 `--verify-display-crash`。它呼叫實際產品服務，保存快照、測試 DDC／HiDPI 並還原；此入口不編入正式版。

## 驗證界線

以上是同一台 PA328QV 上兩種邏輯尺寸的驗證，不代表另有一台 1080p 實體螢幕的測試。第二台螢幕、相同型號雙螢幕、直向實體螢幕、實際拔插及睡眠喚醒尚未完成硬體驗收。自動化虛擬 HiDPI 測試使用 60Hz，安裝後另確認 2560×1440 HiDPI 的 75Hz 模式；其他刷新率、HDR、VRR、HDCP 與各種 Dock／DisplayLink 不在已驗證範圍。

音量測試證明顯示器接受並讀回硬體值；未播放測試聲音，也未把此結果宣稱為聽感驗證。媒體鍵使用既有 tap 與明確輸出綁定，仍需使用者在日常音訊輸出上確認聽感。

## 原始碼來源

- [HiDPIScaler 固定研究版本](https://github.com/txdadlab/HiDPIScaler/tree/1bfa4fa74ad54e03d3ee2b82c9418697289ccf4a)
- [MonitorControl 固定研究版本](https://github.com/MonitorControl/MonitorControl/tree/7cfe64500d19cbbcbf82121a91c826f658a403bd)
- [ddcutil 封包參考](https://github.com/rockowitz/ddcutil/blob/master/src/base/ddc_packets.c)
- [Chromium 虛擬顯示測試實作](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm)
- [go-macos/virtualdisplay 的模式快取與程序退出觀察](https://github.com/go-macos/virtualdisplay)

後兩者用於交叉檢查行為，未引入其相依套件。

## HiDPI 預設刷新率修正（2026-10-18）

原因：`presets(for:)` 及設定頁的刷新率狀態均固定初始化為 60Hz。虛擬螢幕橋接已支援傳入 75Hz，但直接開啟 HiDPI 會送出預設的 60Hz。

修正：在實體螢幕未被本 APP 鏡像時，快取其目前模式的刷新率。每個 HiDPI 解析度預設檔沿用該台螢幕的刷新率；設定頁沒有手動選擇時使用此預設，已有工作階段則保留該設定。未知值 0 或無效值不覆蓋上次有效讀值，首次完全未知時才使用 60Hz。刷新率選單包含精確的目前值，支援 59.94、74.97、165Hz 等非固定項目。

`HiDPIRefreshRateTests` 抽取產品的模式快取、預設解析度、預設設定與刷新率選單方法，測試多螢幕、75/120/144Hz、非整數值、未知值、直向螢幕及現有工作階段。`display-restoration` 共 185 項檢查通過。

實機驗證：正式版重新建置、安裝並通過 `codesign --verify --deep --strict`。透過 APP 設定頁關閉 PA328QV 的 HiDPI 後，`system_profiler SPDisplaysDataType -json` 回報實體模式 2560×1440 @ 75.00Hz；展開自訂設定、沒有操作刷新率選單即顯示 75Hz。直接開啟 HiDPI 並按「保留設定」後，APP 顯示 2560×1440 · 2× · 75Hz，macOS 對虛擬來源與 PA328QV 均回報 2560×1440 @ 75.00Hz、繪製像素 5120×2880。保留使用者原有的 2560×1440 HiDPI 75Hz。

本輪系統模式證據：`/tmp/mytool-hidpi-rate-native.json`、`/tmp/mytool-hidpi-rate-after.json`；測試及建置記錄：`/tmp/mytool-hidpi-rate-tests.log`、`/tmp/mytool-hidpi-rate-build.log`。此證據是 macOS 模式回報，未使用螢幕自身的 OSD 量測訊號時序。
