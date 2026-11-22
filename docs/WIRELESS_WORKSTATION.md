# 與 Windows 共用無線鍵盤與觸控板

此功能支援 ASUS ProArt PA328QV、Magic Keyboard 與 Magic Trackpad。Mac 使用 App 內建的 DDC/CI。兩端啟用藍牙交接後，由螢幕輸入來源協調配件交接，鍵盤與觸控板使用各系統的原生藍牙連線。

## 安裝 Developer 版

從 `codex/feature-wireless-workstation` 分支執行：

```sh
./build.sh --dev --install
open '/Applications/實用小工具 (Developer).app'
```

Developer 與正式版有各自的設定及藍牙權限。測試時請結束另一個版本。

## 設定與驗收

1. 在 PA328QV 的螢幕選單啟用 DDC/CI。
2. 在實用小工具的「設定 → 能源 → 顯示控制」開啟「Windows 工作台切換」。確認 Mac 接孔及 Windows 接孔，按「讀取目前來源」。
3. 分別在兩台電腦配對同一組配件。每端各需能辨識一個名稱含 `Magic Keyboard` 的裝置及一個含 `Magic Trackpad` 的裝置。
4. 在兩端開啟藍牙跟隨。若 macOS 詢問藍牙權限，允許後再驗證。
5. 在畫面所在的電腦按 `Ctrl+Alt+Shift+F9`（Mac 為 `Control+Option+Shift+F9`）。若 Mac 頂列目前是媒體鍵，可能需要同時按 Fn。設定中的切換按鈕也能發起切換。

配件交接保留配對資料和藍牙電源。若只有畫面切到另一端，先按鍵或輕觸觸控板喚醒配件，或使用螢幕實體選單切回。使用螢幕實體選單切換時，舊來源仍須能讀到新輸入才能自動釋放配件。

驗收時，兩方向各切換一次，確認畫面、鍵盤輸入、游標與各系統的原生觸控板手勢。另測重新開啟 App 後能否再次切換。睡眠、合蓋與登入畫面需要單獨驗證。
