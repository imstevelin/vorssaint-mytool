# 客製功能與回歸契約

修改或同步前對照此表。來源仍保留 Vorssaint 命名的型別／路徑，以減少上游衝突；應用程式身分為「實用小工具」。

| 功能 | 正式入口／邊界 | 必須保留 | 自動驗證與實機驗收 |
| --- | --- | --- | --- |
| 品牌／更新 | AppInfo、Info.plist、UpdateService、ForkBrand、build.sh | `com.imstevelin.vorssaint-imstevelin`、獨立 dev 身分、fork Releases 手動更新；設定與權限延續 | app-management、updates、DeveloperInstallIsolationTests；下載更新及既有權限需手動確認 |
| 設定遷移／移除 | Defaults、SettingsBackupSupport、SelfUninstall | 首次相容匯入不覆蓋已有選擇；移除僅清自己的資料 | preferences、app-management、PreferenceCleanupTests、UninstallSpacesTests |
| 視窗記憶 | DisplayWindowMemoryService／Support、AXCache、ProfileStore、WindowServerSnapshot | 每顯示器配置保存、手動拖拉優先、一次還原、排除浮動／固定視窗、保留歷史 | resource-usage、window-layout；實機重接、解析度切換、不同 App AX 相容性 |
| HiDPI／顯示控制 | VirtualHiDPIService、BrightnessService、DisplayRecoverySupport、VirtualDisplayBridge／Host | 恢復 helper、色彩／更新率限制、DDC、鏡像與硬體按鍵路徑 | display-restoration、software-dimming、resource-usage；實體螢幕、色彩、睡醒與斷線 |
| 藍牙音訊修復 | BluetoothSleepService／Support | 僅指定裝置成為預設輸出才動作、保留離線選擇、30 分鐘間隔、防重啟循環與可撤銷授權 | app-management；指定／未指定裝置連線及實際音訊 |
| 音量／回饋 | SystemOutputControl、VolumeFeedbackSound、AudioFeedbackBridge、AppVolumeMixer、PreciseVolumeRollerService | CoreAudio 優先、DDC fallback、系統與島共用音量／靜音行為、每次點按回饋；音訊重配置例外不可跨入 Swift，失敗可重試 | mixer、app-management、notch、原生例外注入；耳機拔除、歸零靜音、粗階音量、DDC 喇叭 |
| 小夥伴 | NotchMascotSupport／View、NotchService、NotchView | 五種自訂動物、正面單色、可見輪廓置中、26–36 秒來訪、游標／摸摸、減少動態與不可見暫停 | notch；展開／收合、不同內容頁、窄畫面、游標互動、實機資源使用 |
| AI 日誌效能 | AgentUsageService／Store 與各 reader | 可取消掃描、非阻塞停用、佇列保存順序、Copilot 淺層探索；整合官方 reader protocol／多帳號 | agents、resource-usage；長歷史啟動與停用／重啟 |
| 錄影／媒體效能 | RecorderPointerSpool、ScreenRecorderService、MediaVideoTargetEncoder | 完整游標精度、磁碟失敗 fallback、串流編碼、取消及聲軌；整合官方 GIF／影格修正 | recorder、recording、media、resource-usage；長錄影、實際收音及取消 |

## 行為交集的處理

- 官方與 fork 都改善同一路徑：保留官方共用修正，將 fork 契約接回，避免重複服務／輪詢。
- 官方新介面移除客製功能：以小接點接回；本輪展開島保留官方 band 佈局，兩側對稱保留小夥伴空間，保持實體 camera gap 置中。
- 官方提供同等功能：先驗證相容性、設定遷移與實機行為，再移除 fork 差異；在同步紀錄說明替代關係。
- 文字自動合併不代表行為相容；尤其檢查 lifecycle、快取失效、錄影取消與更新來源。

## 發版前人工清單

- [ ] 外接螢幕重接、睡醒、切換解析度／HiDPI；視窗手動調整不被拉回。
- [ ] 指定藍牙裝置可修復；未指定不觸發；重連不循環。
- [ ] 音量歸零靜音、上調解除靜音、回饋音效與 DDC 輸出。
- [ ] 小夥伴在展開／收合、不同頁面與減少動態設定中正常，不遮擋控制。
- [ ] 真實錄影有聲、GIF、長錄影、進度及取消；長歷史 AI 日誌不阻塞介面。
- [ ] 舊版 App、設定備份可回退；正式更新頁仍指向 fork。

未勾選代表未驗證，不能因自動測試通過而代填。

## HiDPI 與瀏覽器更新率驗收

模式標籤、CoreGraphics 刷新率與瀏覽器實際動畫幀率分開記錄。2026-10-18 在 PA328QV 實測，動態虛擬螢幕已為 75Hz，但 Dia 的 GPU 記錄出現 missing NSScreen，TestUFO 仍為 60fps；重新建立 Dia GPU 程序並重新載入後恢復 75fps。只開新視窗未恢復。使用者可先保留 HiDPI 設定，再以 ⌘Q 完全退出 Dia 後開啟測試；再切換 HiDPI 可能重現。App 不得自行終止瀏覽器來掩蓋問題。完整證據與限制見 [本輪驗證](verification/display-refresh-audio-2026-10-18.md)。

後續重接修正改為確認實體模式、AppKit 與 ICC 連續穩定，並等待舊 host 完成 ColorSync 清理。使用者在 Developer 版實際拔插後回報色彩不再閃爍，但 Dia 仍為 60fps，並決定暫不追修瀏覽器相容性問題；詳見 [重接驗收](verification/hidpi-reconnect-2026-10-18.md)。保留這個限制，不以自動重啟瀏覽器處理。

鏡像切換後的驗證必須先刷新 CoreGraphics 模式快取；僅在來源模式不符且鏡像已連接時允許一次重套，ICC／實體更新率未就緒不可觸發已正確模式的重套。保留原有連續穩定、色彩與更新率條件，失敗時分項記錄。詳見 [2026-10-22 驗證排查](verification/hidpi-verification-2026-10-22.md)。

## DDC 亮度基準

啟動、連接及睡醒重建時，必須重新驗證先前的 write-only 判定；閒置後的亮度按鍵可重新讀取面板值與最大值。讀值失敗且沒有有效基準時，不得從預設 50% 執行相對調整；使用者仍可用絕對滑桿指定亮度。保留快速連按累加與軟體延伸調暗。修正與尚待實機驗證的範圍見 [2026-10-21 排查紀錄](verification/display-input-ddc-2026-10-21.md)。

## 虛擬 HiDPI 游標更新補救

VirtualDisplayHost 的游標更新補救只作用於自己的虛擬來源，使用不取得焦點、忽略點擊的極小面板，在指標活動時觸發重繪。不得為此新增阻擋／修改輸入的 tap、閒置動畫計時器，或變更藍牙、實體模式與 ICC；host 結束與睡眠／session 停用時須清理或暫停。這是已知鏡像游標停頓的候選補救，不代表已確認任何一次 Trackpad 延遲都來自 HiDPI。證據、藍牙調查與驗收限制見 [2026-10-21 下午排查](verification/hidpi-cursor-refresh-2026-10-21.md)。

使用者於 2026-10-23 確認內建觸控板也卡、只切換 HiDPI 即恢復；修正補上隱藏 panel 恢復、獨立心跳偵測原生通知失效及有活動才啟動的短期取樣。心跳沿用既有父程序檢查，閒置不重繪；本機計數不包含輸入內容或位置。可重現缺陷、測試與長期實機驗收限制見 [2026-10-23 重繪恢復](verification/hidpi-cursor-recovery-2026-10-23.md)。

同日下午再次復發後，改以相同採樣區間的事件進度避免正常停頓誤判，不因 fallback 反覆重建監聽器。重繪以實際 NSView backing pixel 為準，分開記錄請求／draw／延遲，並保留跨切換的有界歷史。先前短時間流暢不代表問題已解決；證據與驗收界線見 [再次排查](verification/hidpi-backing-damage-2026-10-23.md)。

## 視窗記憶的最新手動選擇

視窗開啟尺寸以同一顯示器上最新學到的 App／標題記錄為準；舊資料夾或文件的最大化記錄不得凌駕後來的手動尺寸。幾何記錄的可選 `learnedAt` 隨 SQLite 冷記錄保存，舊資料仍可讀取，時間相同或缺少時保留標題優先。滑鼠拖拉期間只讀 WindowServer 幾何；實際移動／縮放會取消該視窗尚未執行的開啟及重接還原。自動還原成功不再重新發布成新的使用者選擇，後續手動變化仍等待穩定後學習。暫時貼齊及真正全螢幕的排除規則不變。驗證與限制見 [2026-10-23 視窗記憶修正](verification/window-memory-manual-priority-2026-10-23.md)。
