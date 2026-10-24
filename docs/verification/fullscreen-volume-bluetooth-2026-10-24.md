# 全螢幕音量卡片與藍牙音量補救（2026-10-24）

## 原因與修改

亮度在島無法呈現時由 BrightnessOSD 的全 Spaces、全螢幕輔助面板顯示中央卡片。原生音量按鍵原先以 `acceptsSystemFeedback`／`showsSystemFeedback` 決定 tap 與新按鍵資格，隱藏島時交回系統，因此出現 macOS 頂部卡片。

音量與靜音改用 `acceptsUserInteraction` 保留接管；島在全螢幕或等待 hover 而隱藏時，`showVolume` 使用同一 BrightnessOSD。一般桌面保留島呈現；停用、session 暫停、Mission Control 隱藏時不接管。無音量／靜音能力、Option 系統設定及寫入失敗仍保留原生 fallback，不能對不支援的輸出假裝成功。

## 藍牙研究與界線

- [Apple 音訊輸出設定](https://support.apple.com/en-gb/guide/mac-help/mchlp2256/mac) 說明輸出裝置、音量滑桿與喇叭本體音量。這不構成「系統滑桿有變就代表喇叭實際增益有變」的保證。
- [Core Audio VolumeScalar](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertyvolumescalar) 與本機 SDK `AudioHardwareBase.h` 提供 HAL scalar 介面；現有 App 寫入成功只代表驅動接受請求，無法量測喇叭實際聲壓。
- 「系統滑桿／App 有變、喇叭音量不變，而實體鍵有效」可能是 Bluetooth 音量同步或裝置端狀態失效；本輪未重現，不能確認根因，也不能以讀回相同 scalar 自動判斷故障。

沿用既有重啟 bluetoothd 的候選補救，在音訊輸出設定「藍牙喇叭連線修復」新增「立即嘗試修復音量」。只能由使用者主動操作，限目前預設輸出且已勾選的 Bluetooth 裝置，需既有一次性授權；不要求開啟自動修復。與自動路徑共用 30 分鐘持久冷卻及重連抑制標記，授權檢查後重新核對輸出身分，主執行緒不等待 sudo。按鈕顯示重啟要求、冷卻、未指定裝置、缺少授權或命令失敗，成功僅表示命令完成，不表示聲音已修復。

重啟會短暫中斷所有藍牙裝置，介面明示此影響。未改全域音量偏好、配對資訊或喇叭韌體，不在每次音量操作觸發重啟。

## 驗證

- `./build.sh --test`：113,367 checks 通過；原生 AudioFeedbackBridge 14 checks、設定清除、移除 Spaces、Developer 安裝隔離亦通過。
- 其中 notch 66,624 checks、app-management 423 checks；包含全螢幕啟動／進出保留音量 tap、隱藏島中央音量及靜音卡片、暫停時不顯示卡片、指定裝置／冷卻期與時鐘倒退的手動修復限制。
- 首次 notch suite 的 3 個新增案例未啟用音量路由偏好而失敗；補齊並還原測試偏好後，完整測試通過，未放寬產品斷言。
- 尚未實機驗證全螢幕硬體鍵、喇叭故障當下的補救效果、多螢幕 Spaces 或重連後實際音量。未在本機觸發 bluetoothd 重啟，未替換正式 App。

本批從乾淨最新 origin/main 建立獨立功能分支；未混入 PR #7 的原生 HiDPI 候選。已執行上游只讀評估；本輪為兩項明確音量問題的修補，不擴大為官方同步。
