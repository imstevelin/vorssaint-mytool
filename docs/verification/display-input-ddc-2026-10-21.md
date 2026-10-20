# HiDPI 輸入卡頓與 DDC 亮度基準排查

## 範圍與現場證據

分支：`codex/feature-hidpi-input-ddc-baseline`。使用者回報 HiDPI 啟用後 Magic Trackpad 的游標、點擊與捲動都會間歇卡頓；目前未取得穩定觸發方式。

已安裝正式 App 的 display 日誌顯示：讀值被 `ddc cached display 2: writeOnly` 略過，route 初始化為 0.5，第一次亮度按鍵從 0.5 寫入 0.5625。這證明該次按鍵使用快取種子，不能證明面板當時實際亮度。

短時間程序取樣未捕捉到卡頓。45 秒只讀診斷顯示 CoreGraphics 回報 2560×1440、5120×2880 像素、75Hz 的虛擬來源與鏡像關係；這不是實體面板或瀏覽器動畫幀率證明。取樣內沒有觀察到 tap 被停用。tap 原有延遲統計包含很大的歷史平均值，不能把它解讀為本次發作耗時。未切換 HiDPI、重啟藍牙或終止正式 App。

## 亮度修正

- 啟動、重接、強制重建（含睡醒、HiDPI 切換）重新探測曾被快取為 write-only 的 DDC 通道。
- 閒置後的相對亮度按鍵重新讀值，即使先前探測失敗；成功後更新可讀狀態、最大值及最後硬體值。
- 從未取得有效基準且重試仍失敗時，略過相對調整，不把預設 50% 寫入面板。絕對滑桿仍可由使用者指定值；真正無法讀取的連接不能保證取得面板實際亮度。
- 保留按住按鍵時的短期快取、累加、讀值期間新操作優先與延伸軟體調暗路徑。DDC 工作仍在原有序列佇列，沒有新增常駐輪詢。

## 下次卡頓取證

```sh
swift Tools/DiagnoseDisplayInput.swift 120 > /tmp/vorssaint-display-input.jsonl
```

工具最多執行 600 秒，每秒輸出顯示模式與所有 event taps 的程序、事件遮罩、啟用狀態和延遲統計。不記錄鍵盤內容、游標位置或操作事件，不攔截輸入、不調整顯示設定。第一筆是歷史快照；後續 extrema 在每次查詢後重設為平均值，因此仍須對照歷史平均基線，不能把數值直接當成該秒的新延遲。API 行為見 [Apple CGGetEventTapList 文件](https://developer.apple.com/documentation/coregraphics/cggeteventtaplist(_:_:_:))。

發作時記下台北時間、使用中的 App，以及整個畫面是否一起停頓，將發作區間與正常區間比較。若未發作，診斷只能建立基線，不能排除藍牙或 WindowServer 問題。需要在症狀當下補 App／WindowServer 取樣，再安排同工作負載的 HiDPI 開／關比較；不可把本輪亮度修正宣稱為 Trackpad 修復。

## 驗證

- features：1173 checks 通過。
- display-restoration：251 checks 通過，包含先前 write-only 恢復實際值／非 100 最大值，以及初次讀值失敗不從 placeholder 寫入的來源擷取行為測試。
- 全套 `./build.sh --test`：113350 checks 通過，另有 AudioFeedbackBridge、偏好清理、移除 Spaces、Developer 安裝隔離檢查通過。
- `./build.sh` Release 建置、`./build/VorssaintImstevelin --selftest` 與 `codesign --verify --deep --strict` 通過。
- `./build.sh --dev --install` 通過，Developer App 已安裝至 `/Applications/實用小工具 (Developer).app`。正式 App 未替換，未啟動第二個控制同一螢幕的 App。
- 尚未驗證：修正版實體 DDC 重接／睡醒／面板按鈕變更後的按鍵操作；Magic Trackpad 卡頓重現與根因；實際螢幕／瀏覽器幀率。

## 使用者授權的正式位置測試安裝

2026-10-21，使用者要求以本分支測試版取代現行正式版並啟動。已備份舊 App ZIP、匯出的正式偏好及自己的 Application Support（排除暫時 DisplayRecovery journal），以來源提交 `5eb39def` 的 Release 建置取代 `/Applications/實用小工具.app`，保留正式 bundle ID、1.1.1／build 12 與原有簽署身分；沒有發佈新版本。

安裝後 strict deep 簽章通過，已安裝執行檔 SHA-256 與驗證過的 stage 完全相同，新程序與 VirtualDisplayHost 已啟動。啟動日誌實際讀到 `replied(current: 38, maximum: 100)`，DDC route 使用 0.38，而非預設 0.5。這證明本次啟動成功重讀面板值；亮度按鍵、真正重接／睡醒及 Magic Trackpad 卡頓仍由使用者驗收，不能視為已通過。
