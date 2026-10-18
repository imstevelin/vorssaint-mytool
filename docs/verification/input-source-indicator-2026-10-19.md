# 游標輸入法提示

分支：`codex/feature-input-source-indicator`。

## 行為與邊界

- 功能中心的「滑鼠與鍵盤」新增「游標輸入法提示」，預設未安裝／未啟用。安裝後啟用主要開關；停用、移除與退出釋放觀察器、計時器及面板。
- 使用既有 `InputSourceSelection.currentReading()` 讀取 TIS 實際輸入來源完整名稱。沒有收到成功切換的系統狀態就不會預先顯示要求切換的目標；不執行輸入法切換。
- 用 Accessibility 的選取範圍與 `AXBoundsForRange` 查詢插入端點，只讀位置／角色／範圍，不讀文字內容。選取／組字期間以範圍末端定位。
- 沒有自動消失期限。文字焦點有效時持續顯示；切換輸入來源更新名稱；不攔截鍵盤或滑鼠、不取得焦點。
- 浮動面板使用原生 HUD 材質，避開插入游標、限制在對應螢幕可用範圍；支援負座標、不同顯示器與全螢幕 Space。
- AX 焦點／選取通知優先，0.75 秒補查處理未發通知的 App、捲動與權限撤銷。位置查詢使用獨立序列佇列、0.12 秒單次 IPC timeout、最多一份查詢；世代與前景 PID 檢查丟棄過期結果。
- 無輔助使用權限、離開文字欄位、密碼／安全輸入、鎖屏及螢幕睡眠隱藏。無可靠游標位置時不以滑鼠或整個欄位冒充插入點。
- 部分瀏覽器、自繪編輯器與終端機不提供可用的 AX 範圍位置。輸入法內部未公開的中／英模式不等同 TIS 來源，不能保證識別。其他介面語言目前以英文 fallback 顯示新功能文案。

## 來源

- [Apple AXBoundsForRange](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute)
- [Apple AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate)

## 驗證

- `./build.sh --test-suite=features`：1185 checks 通過。
- `./build.sh --test`：113362 checks 通過；音訊 bridge 14 checks、設定清理、卸載 Space 與 Developer 安裝隔離檢查通過。
- Developer 建置／安裝與 strict deep codesign 通過。使用者已授予 Developer 輔助使用權限，設定頁正確移除未授權提示；原生面板 AX 狀態顯示「繁體注音」。
- 原生外觀檢查發現 `NSTextField.intrinsicContentSize` 受既有 frame 影響造成名稱截斷，改為測量未截斷的字串寬度。
- 正式 App 未替換；Developer 測試使用獨立設定備份與功能隔離。

- `./build.sh` 正式建置通過；`./build/VorssaintImstevelin --selftest` 回報 `SELFTEST OK`，正式 staged bundle 與安裝的 Developer bundle 均通過 strict deep codesign，Info.plist lint 通過。
- Fork CI 的最新結果以 [PR #5](https://github.com/imstevelin/vorssaint-mytool/pull/5) Checks 為準，不把本機測試視為 CI 結果。
- 修正後的名稱寬度、持續顯示／切換、實體多螢幕及鎖屏／睡醒仍保留人工驗收；本輪 UI 工具可讀到提示文字，但沒有取得足以確認全部原生外觀與切換流程的證據。所有輸入法與所有第三方 App 並未因此取得通用相容性保證。
