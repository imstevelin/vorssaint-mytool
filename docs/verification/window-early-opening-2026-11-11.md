# 縮短換螢幕等待期間的新視窗還原

日期：2026-11-11。

## 量測與取捨

使用者要求再縮短首次還原延遲。先嘗試批次 AX 屬性讀取及寫入前的批次重查，但交錯重跑未呈現穩定改善，因此未採用此改法。現行寫入前的身分、角色、可縮放、最小化按鈕、全螢幕、幾何及輸入檢查保留。

真正可減少的是換螢幕後讓既有 App 完成重排的固定等待。新建立的 AX 視窗也被一併阻擋，縱使其顯示器座標已經一致。

## 行為

- 只有 AX 建立通知提供的新視窗可提早走原還原路徑；一般掃描與已觀察過的 CG 視窗保留原重排等待，包括重複的建立通知。
- 必須無受管理的 HiDPI 切換，當前配置與最後一個拓樸事件的配置一致，每個螢幕均在線且啟用，AppKit／CG 邏輯尺寸一致，工作區有限、非空且位於顯示器範圍內。
- 查詢前及寫入前重新檢查；不一致時保留原等待，既有 transition generation、滑鼠操作優先及精確 AX handle 檢查不變。
- 不改顯示模式、色彩／ICC、既有視窗重排時序或永久輪詢頻率。整體配置仍不會再次移動已處理的新視窗。

## 可重現的原生驗證

原生 fixture 新增 `--settling`，在相同的待重接配置與 250ms 可見快照落後條件下，額外設定既有視窗 600ms 重排等待。完成時間改由真正的 AppKit resize 通知記錄，移除原本 5ms 取樣造成的量測誤差。

```sh
python3 Tests/WindowOpeningLatencyTests.py --baseline=b452840f --reconnect --settling
python3 Tests/WindowOpeningLatencyTests.py --reconnect --settling
python3 Tests/WindowOpeningLatencyTests.py --reconnect
```

本輪等待期間量測：前版 558.6ms；新版 32.0ms，重跑 38.3ms、37.5ms。無重排等待的新路徑重跑 32.4ms。這些是專用原生 fixture 的還原時間，不能與未包含 600ms 門檻的前輪 36–37ms 直接比較，也不是所有實體螢幕／App 的像素呈現或現場操作驗收。

完整 `./build.sh --test`：113,502 checks 通過（window-layout 587）；音訊原生邊界、偏好清除、移除及安裝隔離皆通過。強化測試後 window-layout 587 checks 再次通過；正式建置、selftest、strict deep codesign 通過。CI 結果於本輪整合時確認。正式交付保留原 App 身分、設定與可回退備份。
