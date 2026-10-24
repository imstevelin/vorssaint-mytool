# HiDPI 間歇性游標卡頓：重繪恢復

## 使用者實測與範圍

2026-10-23 使用者回報：使用中沒有明顯睡醒、鎖定或 Space 切換，外接滑鼠與內建觸控板移動都卡頓。僅手動關閉 HiDPI，卡頓即消失；重新開啟後仍流暢。這次沒有退出主程式，比先前同時退出 App、移除輸入掛鉤與重建虛擬顯示的比較，更能把範圍縮小到虛擬 HiDPI／鏡像路徑。

使用者切換前沒有取得 host 狀態，因此不能宣稱已證明該次 macOS 合成器停止更新的精確觸發條件。切換後的程序、設定與日誌不是故障當下證據。原有 [鏡像游標更新補救](hidpi-cursor-refresh-2026-10-21.md) 並未消除這次間歇性問題。

## 可重現的程式缺陷

舊 `VirtualDisplayCursorRefresh.pointerActivity` 在重繪 panel 不可見時直接返回，後續的指標事件都無法恢復它；全域 NSEvent monitor 也只有建立／拆除，沒有獨立確認通知是否仍送達。

本機圖形環境的最小重現：建立 refresh → 一次 pointerActivity → 對 panel 執行 orderOut → 再次 pointerActivity。舊版輸出 `hidden panel recovered=false redraws=1 expected=2`；修正後同一重現輸出 `hidden panel recovered=true redraws=2 expected=2`。這證明恢復缺陷，不代表 orderOut 已被證明是使用者該次發作的觸發。

## 修正

- 指標活動可恢復被隱藏的自有重繪 panel；Space、顯示配置與睡醒通知重新排列／恢復 panel。panel 提升至 screenSaver 層，避免正常全螢幕或選單遮住唯一的損傷區域，仍為一個邏輯點、1% opacity、不取得焦點且忽略點擊。
- 重用 host 原有 0.2 秒父程序存活心跳，比對指標位置與最近原生事件。偵測到移動卻沒有原生通知時，執行重繪、重新註冊 NSEvent monitor，並短暫啟動共用 run-loop mode 的活動取樣。
- 活動取樣在停止移動 0.25 秒、正常事件恢復、離開來源螢幕、睡眠或 teardown 時停止。閒置時不產生重繪，也不新增常駐高頻動畫計時器；沒有阻擋／修改輸入的 CGEvent tap 或新權限需求。
- host 心跳採 common mode，保留父程序檢查與退出清理；不重新建立顯示、不修改解析度、更新率、鏡像、ICC 或藍牙設定。
- host request 旁的 `.cursor-status` 記錄原生事件數、重繪數、fallback／repair 次數、活動取樣、可見與暫停狀態。最多每五秒寫入一次，狀態沒變不寫；不儲存按鍵或游標位置，正常退出刪除。

## 驗證與限制

- `./build.sh --test-suite=display-restoration`：278 checks 通過。
- 新增隱藏 panel 恢復、刻意不送 NSEvent 的移動偵測、閒置無重繪、睡眠／喚醒、離開來源螢幕與 stop 後不復活的回歸測試。
- 完整 `./build.sh --test`：113378 checks 通過，另有 AudioFeedbackBridge、偏好清理、移除 Spaces 與 Developer 安裝隔離檢查通過。
- Developer `./build.sh --dev --install` 與 Release `./build.sh` 建置成功；兩版 selftest、strict deep codesign、plist lint 通過，host 為 arm64。Developer 已安裝但未啟動，避免與目前正式程序同時控制顯示器。
- 程式提交 `43ff78a2` 的 Release stage 主程式 SHA-256：`94970d67114951ce02559bc3d4bf5f9e3b0c2d267fbd380a1691640e16a7beb5`；VirtualDisplayHost：`07d239e38a8600fc92e5755b31a2134443274cf79125115f86cec965ef1f22cf`。
- 此提交的 [Fork CI](https://github.com/imstevelin/vorssaint-mytool/actions/runs/39815174274) 已明確派送，目前排隊，未以舊提交的綠燈代替。正式 App 尚未替換；依 AGENTS.md 等候使用者選擇安裝方式。未發布 tag 或 Release。
- 修正版的全螢幕／Space、睡醒及長時間無復發驗收待完成。不得以測試或正常狀態下的診斷計數代填。

## 授權安裝與即時驗收

使用者明確選擇「備份後替換正式 App，保留目前設定」。台北時間 2026-10-23 00:38 已將舊正式 App 與退出前／後偏好備份於 App 自有 Backups／`20261023-003818-before-cursor-recovery-43ff78a2`，正常退出舊主程式與顯示 helpers 後替換正式位置。Developer 未啟動，沒有兩版同時控制顯示器。

- 安裝後主程式與 host SHA-256 皆與上述 Release stage 一致；已安裝程式 selftest、strict deep codesign 通過。保留正式 bundle ID、1.1.1 build12，未發布 tag 或 Release。
- HiDPI 設定內容與退出後備份一致，其他偏好僅 `systemShortcutsSuppressed` 隨 App 啟動進入執行狀態而變化；未匯入或重設使用者偏好。
- 新主程式與 host 日誌確認來源／實體鏡像為 2560×1440、5120×2880 像素、75Hz，解析度、實體更新率、鏡像與兩端 ICC 驗證全部通過。重繪 panel 可見且未暫停，診斷檔可讀。
- 使用者在本次安裝後回覆「目前流暢」。這是即時游標操作驗收，不能取代間歇性問題的長時間無復發、全螢幕／Space 與睡醒驗收。
