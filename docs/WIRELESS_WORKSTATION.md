# 與 Windows 共用區網輸入

Magic Keyboard 與 Magic Trackpad 固定配對到 Mac。Mac 啟動 Deskflow 伺服器，Windows 用戶端接收鍵盤、游標、點擊與捲動。原生 macOS 多指手勢在 Mac 本機使用。

1. 在 Mac 安裝 [Deskflow 1.27.0](https://github.com/deskflow/deskflow/releases/tag/v1.27.0) 到 `/Applications/Deskflow.app`，在「隱私權與安全性 → 輔助使用」允許 Deskflow。
2. 在功能分支執行 `./build.sh --dev --install`，再開啟「實用小工具 (Developer)」。在「設定 → 能源 → 顯示控制」啟用「Windows 工作台切換」，即可看到 Mac 區網位址與指紋。
3. 在 Windows 的「Mac 配件控制 → 螢幕」先設定兩台電腦的接孔，再到「區網輸入（Deskflow）」複製 Windows 指紋。將它貼入 Mac 的 Windows 指紋欄，按「儲存配對並啟動」，並依提示允許「實用小工具 (Developer)」使用輔助使用。在 Windows 輸入 Mac 顯示的位址和指紋，按「儲存配對並連線」。兩端都會顯示目前狀態。
4. 用 `Control+Option+Shift+F9` 往返兩端。若 Mac 的 F9 是媒體鍵，同時按 Fn。Windows 用戶端會依輸入焦點，從 Windows 的影像連線對 PA328QV 發送 DDC/CI 指令。

兩端只交換公開憑證指紋，私鑰留在自己的設定資料夾。剪貼簿同步已關閉。請透過實用小工具管理同一個伺服器。共用螢幕的輸入切到 Windows 時，Mac 仍需有可用桌面。若闔蓋造成 Deskflow 找不到作用中顯示器，打開上蓋並重啟伺服器。Mac 的日誌位於 `~/Library/Application Support/Vorssaint Workstation/deskflow-server.log`。
