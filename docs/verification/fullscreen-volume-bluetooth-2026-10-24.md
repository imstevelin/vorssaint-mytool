# 全螢幕音量卡片與藍牙故障研究（2026-10-24）

## 全螢幕修正

亮度在島無法呈現時由 BrightnessOSD 的全 Spaces、全螢幕輔助面板顯示中央卡片。原生音量按鍵原先以 `acceptsSystemFeedback`／`showsSystemFeedback` 決定 tap 與新按鍵資格，隱藏島時交回系統，因此出現 macOS 頂部卡片。

音量與靜音改用 `acceptsUserInteraction` 保留接管；島在全螢幕或等待 hover 而隱藏時，`showVolume` 使用同一 BrightnessOSD。一般桌面保留島呈現；停用、session 暫停、Mission Control 隱藏時不接管。無音量／靜音能力、Option 系統設定及寫入失敗仍保留原生 fallback；沒有目標顯示器時不宣稱已顯示中央卡片。

## 藍牙故障當下的實測

本機 macOS 27.0.1（26A434），預設輸出為 EMBERTON II，Bluetooth、44.1kHz。使用者確認當時電腦音量無效，只有喇叭實體鍵有效。

1. Core Audio 回報 VirtualMainVolume 約 0.15625，左右 VolumeScalar 約 0.15625、0.15624955；所有屬性可寫，mute 為 false。觀察期間數值隨操作變到約 0.23437。
2. 確認輸出已被使用者指定、自動修復已開啟且有原有 sudo 授權。距上次嘗試約 28 分鐘，等滿 30 分鐘才執行一次原有 `/usr/bin/sudo -n /usr/bin/pkill -x bluetoothd`。先保存冷卻及防循環標記，命令成功。
3. 喇叭短暫離線，約一分鐘內重新成為預設輸出。使用者再次明確回報「仍卡住，只有喇叭按鈕有效」。因此重啟 Bluetooth 對本次故障無效。
4. 另測直接左右聲道 scalar：由約 0.2313 各降一半至 0.11565，兩次寫入及讀回成功。使用者確認「仍然一樣大聲」。稍後確認沒有新的手動音量改動，已將兩聲道還原至測試前值。直接寫左右聲道亦無效，不把 HAL 成功視為實際響度恢復。

最初新增了手動重啟補救候選；因實機證據顯示無效，本輪移除此新增入口及政策，保留既有自動修復設定與行為，不交付未有效的手動音量修復按鈕。

## 研究與界線

- [Apple 音訊輸出設定](https://support.apple.com/en-gb/guide/mac-help/mchlp2256/mac) 說明系統音量與喇叭本體音量。它不保證 HAL scalar 成功就代表喇叭實際增益改變。
- [Core Audio VolumeScalar](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertyvolumescalar) 與本機 SDK 提供 HAL scalar 介面；本次實測已確認系統讀寫可成功而實際控制仍失效。
- [Marshall 異常排查](https://www.marshall.com/us/en/support/speakers/support-for-emberton-ii/troubleshooting-erratic-behavior) 建議檢查韌體或重置；[韌體確認](https://www.marshall.com/gb/en/support/speakers/support-for-emberton-ii/latest-firmware-version) 要求從 Marshall Bluetooth App 確認版本。本輪未更改韌體、配對或重置喇叭，尚不能確認裝置端根因。
- 既有 AppVolumeMixer 可對個別程式使用 process tap 及軟體增益，這是繞過硬體音量的另一條路；若要接管整個系統所有音訊，需另處理捕捉授權、未捕捉程序、受保護內容、延遲與路由生命週期，不能把現有每 App 混音滑桿直接冒充可靠的全域修復。

目前未找到可確認修復本次故障的原生音量或 Bluetooth 重啟方法；不宣稱藍牙問題已修好。

## 驗證

- 初版完整 `./build.sh --test`、正式建置、selftest、strict deep codesign 通過；第一次新增卡片測試未開啟路由偏好，補齊測試條件後通過。正式編譯另發現目標顯示器是可選型別，已加入存在檢查及缺少顯示器案例。
- 移除實機無效的新增手動重啟候選後，最終來源完整 `./build.sh --test` 通過 113,361 checks（notch 66,625），音訊原生邊界、設定清除、移除及安裝隔離亦通過。最終建置、簽章與 CI 結果記錄於 [PR #9](https://github.com/imstevelin/vorssaint-mytool/pull/9)。
- 全螢幕實際硬體按鍵、多螢幕 Spaces 尚待人工驗收。已建置及安裝獨立 Developer 候選，僅以 selftest 啟動；未替換正式 App。

本批從乾淨最新 origin/main 建立獨立功能分支；未混入 PR #7 的原生 HiDPI 候選。已執行上游只讀評估，本輪為明確音量問題的修補與研究，不擴大為官方同步。
