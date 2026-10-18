# HiDPI 重接穩定性修正 — 2026-10-18

## 回報與證據邊界

使用者確認：先在未接外接螢幕時開啟 Dia，再接上外接螢幕，TestUFO 固定 60Hz；色彩飽和度會持續交替，直到手動關閉／開啟 HiDPI。前輪的手動開關及 GPU 重建驗收不涵蓋這項實體重接情境，不能視為已修復。

[BetterDisplay #261](https://github.com/waydabber/BetterDisplay/issues/261) 記錄類似虛擬鏡像色調閃爍，包含 ICC 相同仍閃爍的情境。此資料提供調查方向，不能直接證明本機原因相同。[Chromium 155 的 NSScreen 刷新率讀取](https://github.com/chromium/chromium/blob/155.0.8059.80/ui/display/mac/screen_utils_mac.mm) 在無法取得 NSScreen 時退回 60Hz。Dia 可能含自有修改，因此不把 Chromium 相同版本的全部實作視為 Dia 原始碼。

## 本輪程式修改

- 自動恢復不再以固定 0.5 秒等同「已穩定」。每 0.5 秒取樣實體 ID、模式、尺寸、更新率與完整 ICC；要求 AppKit 可見、ColorSync 與 CoreGraphics ICC 相同，連續四次一致後才套用。讀取缺失／變動重設穩定計數，20 次仍未就緒則停止自動嘗試並保留原生顯示。
- 舊 host 的 SIGTERM 清理是非同步的，且會重設穩定虛擬身分的 ColorSync override。新建相同身分前等舊 host 結束；手動操作也受此保護，不強制殺掉卡住的 helper。
- 虛擬顯示器建立後先確認 AppKit 連續可見，再設定鏡像主螢幕；後續模式／鏡像／ICC 驗證重新由零累計。
- 重接可能保留數字 ID 卻解除鏡像；不再僅憑 sessions 與 online 判定正常。識別仍相符時先安全恢復原生模式，清理舊 session，再走穩定恢復流程。

## 驗證

- display-restoration：249 checks 通過；原生音訊例外 fixture：14 checks 通過。
- 新增真實 readiness 狀態機的回歸，涵蓋晚到 ICC、AppKit／清理未就緒、實體 ID 更換、連續穩定與有限重試。
- 本機完整測試 `TESTS OK (113347 checks)`、偏好清理／移除／Developer 安裝隔離通過。Developer 建置、安裝、selftest 與 strict deep codesign 通過，建置標記為 `e27656fa`。
- Developer 僅啟用顯示器功能，正式版退出以避免同時控制。沿用正式版的 HiDPI 設定，Developer 舊偏好另行備份；初次啟動面板亮度顯示 44%，已恢復為切換前的 100%，對比維持 80%、音量 28% 與靜音。
- 使用者實際依「Dia 保持開啟、拔除外接螢幕、等內建穩定再接回、等待約 10 秒、不手動切換 HiDPI」測試，回報未再見到色彩閃爍，TestUFO 仍為 60。此為本次一次重接的使用者驗收，尚未代表所有螢幕、睡醒或長時間情境皆通過。
- Dia 的 60fps 尚未修復。使用者於本輪明確決定先不處理，保留為已知相容性限制；不得把它改寫為已解決，也不擴大到瀏覽器／GPU 操作。
- 不自動退出 Dia、重啟其 GPU、替換使用者 ICC、切成 sRGB、修改全域色彩設定或無限反覆切換 HiDPI。

## 交付與暫緩範圍

- 使用者驗收後再次量測：虛擬顯示器約 75.003fps、實體鏡像端約 74.977fps；此為 CVDisplayLink 回呼，不等同面板攝影或瀏覽器所有呈現路徑測量。
- 正式建置、`SELFTEST OK`、strict deep codesign 通過；相同程式已替換 `/Applications/實用小工具.app`，安裝檔與 stage 主執行檔 SHA-256 相同：`60b22e9becd7875c54a7d76a8741d8054adb87706c6f20b6513040b1fd5da664`。
- Developer 已退出並還原測試前偏好。正式版啟動後自動恢復 2560×1440、2×、75Hz，回饋音啟用；亮度恢復 100%、對比 80%、音量 28%、靜音保留。正式版重新啟動的結果不代替另一次實體拔插驗收。
- 舊正式 App／偏好保存在 `~/Library/Application Support/實用小工具/Backups/`，檔名帶 `before-reconnect-e27656fa`。維持未公開版本 1.1.1 build12；這次是本機修正部署，未建立 tag 或 GitHub Release。
- 後續若沒有新的實際使用問題，不再對 Dia 的 60fps 進行程式修改、瀏覽器設定調整或 GPU 重啟。現有證據較支持 Dia／動態虛擬螢幕的相容性限制，不能宣稱其內部全部原因已確認。

## 最終整合

- [Fork CI 39137288233](https://github.com/imstevelin/vorssaint-mytool/actions/runs/39137288233) 全部通過：macOS 26 為 113347 checks，Swift 6.0.3／macOS 15 為 113346 checks；兩套原生例外 fixture 皆 14 checks，selftest 與安裝隔離通過；維護工具 5 項通過，候選 DMG 完整性驗證通過。
- [PR #4](https://github.com/imstevelin/vorssaint-mytool/pull/4) 一般 merge 合入 main，合併提交 `3f06b54ec93fb993a249199644b33441c80422d1`，修正分支驗證為 main 祖先後清理。
- 最後提交僅更新文件，程式來源與已驗證的 `e27656fa75a5376b2da72bf7d7acc4f378fae170` 相同；公開 Release 未更新。
