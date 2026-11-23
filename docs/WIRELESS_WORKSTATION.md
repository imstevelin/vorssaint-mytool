# 與 Windows 共用區網輸入

Magic Keyboard 與 Magic Trackpad 固定配對到 Mac。兩個 App 隨包提供 Deskflow 1.27.0 的輸入引擎，由各 App 管理啟動、連線和配對。Windows 能接收鍵盤、游標、點擊與捲動。macOS 多指手勢留在 Mac 本機。

1. 讓兩台電腦連上同一個區域網路。在 Mac 的「設定 → 能源 → 顯示控制」啟用「Windows 工作台切換」，並依 macOS 提示允許輔助使用和區域網路。
2. 在 Mac 按「產生配對碼」。在 Windows 的「Mac 配件控制 → 螢幕 → 區網輸入」貼上配對碼，再按「配對並連線」。配對碼三分鐘後失效。兩端會顯示連線狀態。
3. 確認兩台電腦的螢幕接孔設定。若要在 Windows 登入畫面使用共用鍵盤與觸控板，在 Windows 啟用「登入畫面接管」並核准系統提示。既有使用者可從同一頁移轉已啟用的服務。
4. 用 Control + Command + 反斜線（\）往返兩端。兩端都更新後，原畫面會淡出，播放短提示音，Windows 會對 PA328QV 發送 DDC/CI 指令，目標畫面再淡入。

既有配對會在實用小工具重新啟動時自動更新快捷鍵。當 Windows 接管輸入時，Mac 會將 Caps Lock 轉送給 Windows 的中英切換功能。若 Mac 顯示 Caps Lock 轉送無法啟動，請在「隱私權與安全性 → 輸入監控」允許實用小工具並重新開啟。

兩端只交換公開憑證指紋，私鑰留在自己的設定資料夾。剪貼簿同步已關閉。請透過實用小工具管理同一個伺服器。共用螢幕的輸入切到 Windows 時，Mac 仍需有可用桌面。若闔蓋造成 Deskflow 找不到作用中顯示器，打開上蓋並重啟伺服器。Mac 的日誌位於 `~/Library/Application Support/Vorssaint Workstation/deskflow-server.log`。

建置會驗證並封裝 [Deskflow 1.27.0 發行資產與原始碼](https://github.com/deskflow/deskflow/releases/tag/v1.27.0)。內建引擎仍為獨立的背景程序，App 本體負責設定、憑證配對與畫面切換。
