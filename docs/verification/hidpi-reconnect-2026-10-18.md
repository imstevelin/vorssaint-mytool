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
- 完整測試、建置、CI 與實機重接驗收待完成；尚未宣稱持續色彩閃爍或 Dia 無須退出即可恢復 75Hz 已解決。
- 不自動退出 Dia、重啟其 GPU、替換使用者 ICC、切成 sRGB、修改全域色彩設定或無限反覆切換 HiDPI。
