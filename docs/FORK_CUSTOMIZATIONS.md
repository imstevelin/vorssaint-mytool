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
| 游標輸入法提示 | InputSourceIndicatorService／Support、InputSourceSelection | 手動啟用、實際 TIS 來源的小型「注／A」圓標、游標常駐／輸入欄 fallback；不攔截輸入、密碼／鎖屏隱藏，Electron 手動 AX 狀態可還原 | features；實際 App 輸入／切換、組字、多螢幕位置需實機確認；[設計與驗證](verification/input-source-indicator-2026-10-19.md) |
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
