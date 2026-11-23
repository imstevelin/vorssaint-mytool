# 與 Windows 共用區網輸入

Magic Keyboard 與 Magic Trackpad 固定配對到 Mac。Mac 啟動 Deskflow 伺服器，Windows 用戶端接收鍵盤、游標、點擊與捲動。原生 macOS 多指手勢在 Mac 本機使用。

1. 在 Mac 安裝 [Deskflow 1.27.0](https://github.com/deskflow/deskflow/releases/tag/v1.27.0) 到 `/Applications/Deskflow.app`，在「隱私權與安全性 → 輔助使用」允許 Deskflow。
2. 在 Windows 用 PowerShell 7 執行 `DeskflowSetup.ps1` 取得 Windows SHA‑256 指紋。Mac 在本專案執行 `bash Tools/setup-workstation-deskflow.sh 'Windows 指紋'`，以輸出的 Mac SHA‑256 指紋完成 Windows 端設定。
3. 在功能分支執行 `./build.sh --dev --install`，再開啟「實用小工具 (Developer)」。在「設定 → 能源 → 顯示控制」啟用「Windows 工作台切換」及「啟動 Deskflow 區網伺服器」。Windows 在「螢幕」設定接孔並啟動用戶端。
4. 用 `Control+Option+Shift+F9` 往返兩端。若 Mac 的 F9 是媒體鍵，同時按 Fn。Windows 用戶端會依輸入焦點，從 Windows 的影像連線對 PA328QV 發送 DDC/CI 指令。

兩端只交換公開憑證指紋，私鑰留在自己的設定資料夾。剪貼簿同步已關閉。請透過實用小工具管理同一個伺服器，並在測試時保留螢幕實體輸入鍵。Mac 的伺服器日誌位於 `~/Library/Application Support/Vorssaint Workstation/deskflow-server.log`。
