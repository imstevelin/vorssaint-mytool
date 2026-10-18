# 游標輸入法提示

分支：`codex/feature-input-source-indicator`；[PR #5](https://github.com/imstevelin/vorssaint-mytool/pull/5)。

## 行為與邊界

- 功能中心「滑鼠與鍵盤」新增「游標輸入法提示」，預設未安裝／未啟用。安裝後啟用主要開關。
- 使用既有 `InputSourceSelection.currentReading()` 讀取 TIS 實際來源，顯示 18 × 18 point 藍色圓標及單一代表字：注音「注」、英文「A」、倉頡「倉」、拼音「拼」等。完整系統名稱保留在輔助使用描述中。這是 App 自繪的原生風格提示，並非延長 macOS 私有系統提示的生命週期。
- 沒有自動消失期限。有效文字焦點存在時持續顯示，來源切換更新代表字，不攔截鍵盤或滑鼠、不取得焦點。
- 定位順序：AppKit `AXSelectedTextRange`／`AXBoundsForRange` → WebKit／Chromium `AXSelectedTextMarkerRange`／`AXBoundsForTextMarkerRange`（包含最多五層父元素）→ 已辨識可編輯欄位的下緣。欄位下緣定位是相容 fallback，不宣稱是精確插入點；不以滑鼠位置冒充文字游標。
- 選取／組字期間以選取末端的折疊範圍定位。只查詢範圍、幾何與必要狀態，不讀取文字內容或剪貼簿。
- Electron 若公開 `AXManualAccessibility=false`，依其官方 assistive-client 介面一次啟用文字樹。保留已經為 true 的狀態；停用／移除／退出恢復自己改動的 false 值。退出時等待還原佇列完成。避免更動 `AXEnhancedUserInterface`，保留既有視窗恢復契約。
- AX 焦點／選取通知優先，0.75 秒補查處理未發通知的 App、捲動與權限撤銷。AX 查詢使用獨立序列佇列，每輪文字位置查詢總預算 0.25 秒、單次 IPC 上限 0.12 秒；最多一份查詢，世代與前景 PID 檢查丟棄過期結果。Electron 初次啟用與觀察器註冊另有單次 IPC 上限。
- 停用、移除與退出釋放觀察器、計時器及面板。密碼／安全輸入、鎖屏、螢幕睡眠與離開可辨識文字焦點時隱藏。跨螢幕負座標及可用範圍有幾何回歸檢查。
- macOS 沒有保證所有 App 都公開文字焦點／游標的介面。未公開任何文字焦點的自繪 App 仍可能無法顯示；輸入法內部未公開的中／英模式不等同 TIS 來源，不能保證識別。未驗證情境不得宣稱全部相容。

## 來源

- [Apple AXBoundsForRange](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute)
- [Apple AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate)
- [Apple AXTextMarkerRangeCopyEndMarker](https://developer.apple.com/documentation/applicationservices/3882827-axtextmarkerrangecopyendmarker)
- [Electron accessibility](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)
- [Chromium text marker implementation](https://chromium.googlesource.com/chromium/src/+/1932b1654790288639eb22a0cfcc738774469f8b/content/browser/accessibility/browser_accessibility_cocoa.mm)

## 驗證

- 第一版完整回歸：113362 checks，bridge 14 checks、設定清理、卸載 Space 與 Developer 安裝隔離通過；正式與 Developer 建置、selftest、簽章、plist lint 及 Fork CI 通過。
- 使用者已授予 Developer 輔助使用權限，並確認第一版在文字編輯能持續顯示，但要求改為小型「注」「A」樣式並擴充其他 App 支援。
- 小型圓標與相容定位版本：features 1194 checks、完整回歸 113371 checks 通過，bridge、設定清理、卸載與 Developer 安裝隔離檢查通過；Developer 建置與安裝通過。正式建置、selftest 與最新 CI 結果以 PR Checks 為準。實際 UI 已確認 18pt 藍色圓標只顯示「注」，完整「繁體注音」保留在 AX 描述；Dia 本機測試頁的單行欄位及 contenteditable 編輯器均可顯示，切到密碼欄位時隱藏。這不等於全部網站、所有 App 或輸入法切換均已驗收。
- Codex App 受桌面工具存取限制，不能透過該工具實測；不得繞過限制取得其他內容。由使用者自行驗收其輸入欄。
- 正式 App 未替換，未發版。Developer 測試使用獨立設定備份與功能隔離；實體多螢幕、鎖屏／睡醒、全部輸入法及所有第三方 App 尚未取得通用相容性保證。
