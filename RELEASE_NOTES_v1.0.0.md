# vorssaint-imstevelin 1.0.0

這是 [Vorssaint](https://github.com/vorssaint/vorssaint-utils) 的非官方 fork，由 imstevelin 維護，並非官方發行版。

## 新功能

- 「視窗配置」新增兩個可獨立開關的功能：依螢幕記住視窗大小，以及螢幕重新連接時還原仍開啟視窗的大小與位置。
- 使用獨立的 App 名稱、圖示、bundle ID，並只檢查此 fork 的 GitHub Releases。更新按鈕會打開本頁，供手動安裝。

## 安裝

適用於 Apple Silicon、macOS 14 或更新版本。下載 DMG，將 `vorssaint-imstevelin.app` 拖至「應用程式」。此版本使用 Apple Development 憑證簽署，但沒有 Developer ID 簽署與 Apple 公證；macOS 可能阻止首次啟動。若出現提示，可在「系統設定 → 隱私權與安全性」確認開啟。視窗操作需另外授予「輔助使用」權限。

實體螢幕拔插情境尚未完成硬體驗證。程式碼與測試涵蓋視窗配置邏輯；請先在不影響重要工作時試用。

原始碼與授權資訊見本 Release 的 tag、[LICENSE](https://github.com/imstevelin/vorssaint-mytool/blob/v1.0.0/LICENSE) 及 [TRADEMARKS.md](https://github.com/imstevelin/vorssaint-mytool/blob/v1.0.0/TRADEMARKS.md)。
