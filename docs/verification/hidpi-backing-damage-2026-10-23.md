# HiDPI 游標再次卡頓：繪製路徑與監聽誤判

## 再次發作的證據

使用者在 2026-10-23 下午再次回報：滑鼠及內建觸控板移動都卡頓；僅關閉 HiDPI 即恢復，重新開啟仍流暢。因此前一版的短時間驗收不能視為問題已解決。

此次正式主程式仍為先前安裝版本；VirtualDisplayHost SHA-256 為 `07d239e38a8600fc92e5755b31a2134443274cf79125115f86cec965ef1f22cf`。14:35 的舊 host 記錄多次 `recovered silent observation`，14:35:56 退出，14:36 新來源啟動。舊即時狀態在正常退出時被刪除，讀到的 1,023 次原生事件與 995 次重繪是新來源的恢復後資料，不能用來證明故障當下輸入或繪製正常。

沒有取得能證明 App Nap 或 GPU hang 是本次精確觸發條件的記錄；不把一般背景／可見性斷言或恢復通知當成此類證明。

## 確定的誤判與測量缺口

1. 原先每 0.2 秒心跳採樣，卻以「最近 0.1 秒沒有事件」判斷通知失效。事件在 30.01 秒正常到達、30.2 秒採樣時，舊條件必定誤判，並可能反覆重建正常 monitor。本次測試直接覆蓋這個 190ms 正常停頓。
2. 舊 `redrawCount` 在變更 NSWindow 背景屬性時即遞增，並非 AppKit 實際內容繪製完成。先前測試只比較背景屬性，沒有驗證 backing pixels。新測試亦證實 AppKit 會將首次繪製延後到 run loop，不能用同步函式返回作為完成標記。
3. 正常關閉 HiDPI 會刪除 `.cursor-status`，使使用者切換恢復後失去故障前資料。

## 本次修正

- 以同一採樣區間內的 native event 計數進度判斷通知有無送達；正常停手不觸發 fallback。fallback 不再拆除／重建監聽器，原生通知恢復即可停止替代取樣。
- 以自有 NSView 明確交替繪製黑／白 backing pixel，明確標記需要繪製；surface 採正常 readOnly sharing，不排除在一般合成路徑之外。仍維持 1×1、1% opacity、不取得焦點、忽略點擊、僅自有來源有活動才更新，不修改輸入、解析度、75Hz、ICC 或藍牙。
- 分開記錄重繪請求與實際 NSView draw 次數，以及原生事件送達、host 心跳排程與繪製等待。內容繪製完成仍不等於實體鏡像硬體已呈現；不得據此宣稱所有 macOS 合成器狀態都已修復。
- 每個實體來源保留 current／previous 兩份歷史，每份最多十二筆、最多每五秒更新一次；正常退出強制寫入最後狀態，新 host 開始前輪替前次資料。不儲存按鍵、滑鼠位置或畫面內容，閒置狀態不變時不寫檔。
- 已將最新 origin/main 的視窗記憶修正一般 merge 回原 HiDPI 功能分支，保留兩邊契約。

## 驗證

- display-restoration：289 checks 通過，包含正常停頓不誤判、通知恢復後停用 fallback、實際 draw 完成及像素交替、歷史容量限制與跨 host 輪替。
- 最終完整測試 113399 checks、Release 建置、selftest 與簽章檢查通過，細節見下方安裝紀錄。
- 本次來源為修正候選，尚不能宣稱已證明使用者該次 macOS 鏡像停滯的精確觸發。需保留實機即時及長時間觀察結果。

## 安裝與新觀察

- 最終來源提交 `ab6cfab9`：完整回歸 113399 checks、AudioFeedbackBridge、偏好清理、移除 Spaces、Developer 安裝隔離檢查通過。Release 建置、selftest、strict deep codesign、plist lint 通過，host 為 arm64。
- 沿用使用者本次修復流程已明確給出的「備份後替換正式 App，保留目前設定」授權，先備份舊 App、退出前／後偏好與退出後 Application Support，再替換及啟動正式位置。備份目錄為 App 自有 Backups／`20261023-152104-before-backing-damage-ab6cfab9`。
- 安裝後主程式 SHA-256 `98a47a3247fcc7f14628867b37d4e7073f2e1e242da67f64b57f37b9f100575f`；host `a0b6cdd77f3d0097706e167a806a7b6795607a0af14bb965b47ba121ffa4342f`，皆與 stage 一致。已安裝程式 selftest／strict deep codesign 通過。
- 15:22:47 啟動驗證來源與實體鏡像皆為 2560×1440、5120×2880 像素、75Hz，模式／更新率／鏡像／兩端 ICC 全部通過。HiDPI 偏好內容相同，其他偏好僅執行態的 `systemShortcutsSuppressed` 變化。
- 新來源約二十秒的診斷為 585 次原生事件、547 次重繪請求、548 次實際內容 draw（包含初始繪製）、一次 fallback、沒有 panel repair，活動取樣已停止。這是正常時的運作證據，不是偶發症狀根治的證據。
- 使用者補充並明確確認：「影片流暢，但游標與捲動仍會卡」。這不支持單純整個鏡像停止更新的解釋，也不能把本次 backing damage 改善當成已證明的根因修復。後續須區分事件送達延遲、App／WindowServer 輸入處理與局部／游標合成。
- 已檢查目前啟用功能及 tap masks：主程式的 mouseMoved 監聽為 listenOnly，FocusFollowsMouse／SmoothScroll／LinearScroll／MouseAcceleration 等功能未啟用；AppSwitcher 的非 session scroll 快速路徑直接傳遞。尚無足夠證據把卡頓歸因於某個輸入功能，未擅自停用或改寫它們。卡頓仍需故障當下或切換前保存的資料來定位。
- [本次 Fork CI](https://github.com/imstevelin/vorssaint-mytool/actions/runs/39916910232) 已成功，驗證程式提交 `ab6cfab9`。保留草稿，不發布版本，長時間及復發驗收仍待完成。
