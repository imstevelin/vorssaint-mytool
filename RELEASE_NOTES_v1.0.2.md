# vorssaint-imstevelin 1.0.2

這是 [Vorssaint](https://github.com/vorssaint/vorssaint-utils) 的非官方 fork，由 imstevelin 維護。

## 藍牙喇叭連線修復

- 在「設定 → 聲音輸出切換器」加入可開關的「藍牙喇叭連線修復」，預設關閉。
- 啟用後，藍牙喇叭成為預設音訊輸出時，會執行一次受限的 `sudo /usr/bin/pkill -x bluetoothd`。首次使用須輸入管理員密碼安裝專用授權，之後可在設定中移除。
- 重啟藍牙服務會短暫中斷所有藍牙裝置。短暫斷線、重新連線，以及 App 重新啟動都受到連線週期與冷卻記錄保護，避免重啟循環。只有喇叭再次成為預設輸出才會考慮觸發；單純配對但未切換音訊輸出不會觸發。
- 重新安裝 App 會保留既有設定；完整解除安裝會移除本功能的管理員授權。

此版使用 Apple Development 憑證簽署，尚未經 Apple 公證。適用於 Apple Silicon、macOS 14 或更新版本。下載 DMG 後將 App 拖到「應用程式」。首次開啟可能需要在「系統設定 → 隱私權與安全性」手動允許。原始碼見 [v1.0.2](https://github.com/imstevelin/vorssaint-mytool/tree/v1.0.2)。
