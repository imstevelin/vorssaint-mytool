# 換螢幕後首次開窗的還原延遲

日期：2026-11-11。

## 使用者情境

前輪視窗修正安裝後，使用者仍看到各 App 在連接不同螢幕後，第一次開窗恢復記憶大小／位置時有一致且明顯的延遲。這不是僅指 App 啟動的第一個視窗。

## 修正

- AX 建立通知保留實際視窗 handle，直接取得幾何與標題／App profile，不必等可見 WindowServer 清單出現該視窗。寫入前仍檢查正常可縮放視窗、全螢幕、目前幾何、滑鼠狀態及生命週期，並使用原通知的精確視窗 handle。
- 重接整體配置還原後，同一輪處理未匹配到配置的新視窗；不再直接返回、留待下一次半秒掃描。成功套過整體配置的視窗跳過舊快照，避免重新學習還原前的幾何。
- 建立事件的直接路徑不消耗尚待完成的整體配置；後續整體配置排除本 generation 已處理的視窗，避免新視窗被二次移動。
- 顯示器就緒回呼接續等待中的開窗事件，保留 HiDPI／拓樸既有就緒門檻；不以縮短安全等待或增加永久輪詢頻率來處理。
- App 啟動與功能啟用時先註冊 App 層事件；未成功的 App 通知註冊可重試。新視窗通知加入原有視窗訂閱，不移除同 App 其他視窗的監聽。

## 原生回歸與量測

新增 `Tests/WindowOpeningLatencyTests.py` 及專用 AppKit fixture。它使用生產版 service、AX observer、AX frame 寫入和真正的專用 NSWindow；僅延後測試視窗在可見清單中的曝光 250ms，重現建立事件與可見快照之間的競態。Controller 使用獨立的暫存偏好、唯一 fixture bundle ID、無磁碟 profile store，不變更使用者既有視窗或記憶資料。需登入、解鎖且執行端已具 AX 權限。

```sh
python3 Tests/WindowOpeningLatencyTests.py --baseline=343124ec --reconnect
python3 Tests/WindowOpeningLatencyTests.py --reconnect
python3 Tests/WindowOpeningLatencyTests.py
```

本輪同一 fixture 的重接量測：舊路徑約 446ms，新路徑約 41ms；最終修正版重跑為 37.3ms、36.2ms。一般建立事件舊路徑約 417ms，新路徑約 34ms，最終重跑為 36.6ms。此數字是原生 fixture 量測，包含模擬的快照落後，不代表已完成實體螢幕拔插或所有第三方 App 的現場驗收。

## 驗證狀態

完整自動回歸 `./build.sh --test`：113,494 checks 通過，其中 window-layout 579、display-restoration 351；音訊原生邊界、偏好清除、移除及安裝隔離皆通過。最終正式建置、selftest、strict deep codesign 均通過；Apple Development 簽署不代表 Developer ID 公證。Fork CI 結果於本輪整合時確認。正式安裝需先保存舊 App 與自己的設定／資料，再核對執行檔內容及保留原正式 bundle ID／簽署要求。

仍須區分本輪可重現並量測的程式競態，與使用者實體螢幕及第三方 App 自身的 AX 反應；不宣稱顯示器未就緒時也能立即安全移動視窗。
