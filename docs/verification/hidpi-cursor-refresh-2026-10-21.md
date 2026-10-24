# 16:01–16:03 Trackpad 延遲排查與 HiDPI 重繪候選修正

## 本機證據與限制

使用者回報台北時間 2026-10-21 16:01–16:03 發生游標、點擊與捲動延遲，16:03 後自行恢復。程序取樣從 16:03:09 才開始，不能視為發作期間取樣。該取樣中 App 主執行緒多數在正常等待事件，沒有抓到持續卡死；這不能排除先前發作時阻塞。

已擷取指定時間的 bluetoothd／BlueTool／HID／kernel／WindowServer 日誌，並對照 IORegistry 的實體輸入裝置：

- 該區間沒有找到 Trackpad 斷線、HID 逾時或重傳記錄；55 次 HID control report 的回應均為 success 1。它們不是每個觸控輸入封包的統計，不能據此排除藍牙干擾或封包延遲。
- Event latency 的 sender 經 IORegistry 對照是藍牙鍵盤驅動，不是 Trackpad；vendor 事件的巨額 timestamp 數值不解讀為使用者等待時間。
- 外接 Trackpad 當前 Transport 為 Bluetooth、BatteryPercent 21，Critical Errors／ResetCount 為 0；不是發作期間的連續品質測量。
- WindowServer 的 ping timeout 涉及數個背景服務與其他 App，未取得能指向本 App 或 Trackpad 的因果證據。
- 未取得 WindowServer 堆疊：一般權限不允許，非互動 sudo 也需要密碼。未變更權限或重啟該程序。
- `hidutil dump system` 另確認外接 Trackpad 的 firmware CriticalErrors、Duplicate Contact Count 為 0，沒有當前 NoPointing／MomentumActive 狀態；這是恢復後的快照，不能當作發作期間無封包問題的證據。
- 原始日誌保留在本機 `/tmp/vorssaint-stutter-live/`，含私人裝置資訊，不納入 Git。

仍需以保持 HiDPI、改用 USB 的對照方式，以及下次症狀當下取樣區分無線傳輸延遲與視覺更新停頓。不得宣稱已確認本機根因。

## HiDPI 候選補救的依據

[BetterDisplay #807](https://github.com/waydabber/BetterDisplay/issues/807) 記錄虛擬來源鏡像的游標停頓；[維護者的說明](https://github.com/waydabber/BetterDisplay/issues/807#issuecomment-2593772073) 指出畫面沒有損傷時可能停止更新，透過來源上的極小區域重繪補救。[發布說明回覆](https://github.com/waydabber/BetterDisplay/issues/807#issuecomment-2601026163) 也確認不需新增輔助使用權限即可實作。

本分支以自有實作在 VirtualDisplayHost 內建立 1×1 邏輯點、1% opacity 的 nonactivating panel；只對來源螢幕上的指標活動觸發實際顏色變化，允許最高兩倍來源更新率（上限 240 次／秒）的更新，避免 125Hz 輸入與 75Hz 畫面的節拍交錯把重繪降成 62.5Hz。沒有新增可攔截／修改輸入的 tap，也沒有閒置動畫計時器。螢幕矩形在拓撲通知時快取，不在指標通知內查詢顯示配置或 Accessibility。host 關閉、睡眠或登入 session 停用時移除／隱藏 panel。只影響本 App 建立的虛擬來源，不修改藍牙、實體顯示模式、ICC 或全域輸入設定。

這是針對已知鏡像問題的候選補救，不能證明使用者這次發作就是相同原因。自動測試驗證窗口焦點、重繪、限流、跨螢幕、睡醒與清理，不等於實機延遲消失。

## 驗證

- 最終 display-restoration：262 checks 通過；完整 `./build.sh --test`：113362 checks 通過，另有 AudioFeedbackBridge、偏好清理、移除 Spaces 與 Developer 安裝隔離檢查通過。
- Release 建置、stage App selftest、strict deep codesign 通過，VirtualDisplayHost 為 arm64。
- 16:20 已備份並安裝來源提交 `733052de` 的候選版至正式 App 位置，沿用既有設定及簽署身分；未發布新版本。安裝後 strict deep 簽章通過，helper SHA-256 與 stage 一致。
- 真正執行中的 host 日誌確認 `observer available true`；WindowServer 視窗清單確認 1×1、alpha 約 0.01 的 panel 位於螢幕上。CoreGraphics 來源／鏡像仍回報 2560×1440、2x、75Hz，DDC 回讀 38/100。這些是啟動與配置證據，不是實體游標延遲消失的證據。
- Trackpad 藍牙／USB 對照與修正後症狀：待使用者實測。
