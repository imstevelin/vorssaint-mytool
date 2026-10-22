# 內建螢幕視窗最大化記憶覆蓋手動調整

日期：2026-10-23。

## 問題與修正

使用者回報在內建螢幕上，Finder 等 App 曾最大化後，新開或手動調整的視窗仍被強制填滿畫面。程式路徑確認有以下缺口；尚未以使用者的 Finder 實機重現來判定各路徑的影響比例。

- 開啟記錄永遠先取標題專屬記錄，再取 App 共用記錄。舊資料夾最大化能覆蓋後來在另一資料夾保存的小尺寸。新增可選學習時間，較新記錄優先；舊格式仍可解碼，冷記錄與重新啟動後沿用相同規則。
- 拖拉只延後新視窗的還原，放開後仍會執行。新增只讀幾何觀察，發現拖拉時實際移動／縮放即消耗該視窗的開啟／重接還原；單純點擊開新視窗仍保留一次還原。
- 自動還原後的幾何會再被當作新選擇保存。成功還原直接標記已學習；後續真正幾何變化才重新等待穩定並學習。

未清除任何既有視窗記錄，未變更正式 App、版本、設定或另一條 HiDPI 修正分支。

## 回歸涵蓋

- 內建螢幕 Finder 舊資料夾最大化 → 新視窗手動縮小 → 穩定保存 → 重開舊資料夾，應採新尺寸。
- 新視窗拖拉、放開、WindowServer ID 重用、只點擊開新視窗。
- 重接時手動移動同時取消配置與開啟還原。
- 自動最大化還原不新增持久化寫入。
- 原有最大化、貼齊排除、顯示器移位、舊格式與一次還原案例。

## 驗證

- `./build.sh --test`：113,357 checks 通過；其中 window-layout 556、resource-usage 42。
- Audio feedback bridge 14 checks、Preference cleanup、Uninstall spaces、Developer install isolation 皆通過。
- `./build.sh`：Apple Silicon release bundle 建置成功。
- `./build/VorssaintImstevelin --selftest`：通過。
- `codesign --verify --deep --strict 'build/stage/實用小工具.app'`：通過。Apple Development 簽署，不代表 Developer ID 公證。
- `git diff --check`：通過。
- Fork CI：隨本修正 PR 執行；GitHub 狀態為整合依據。

## 尚未驗證

- 使用者目前內建螢幕上的 Finder 實際拖拉、關閉、重新開啟。
- 實體螢幕拔插、睡醒，以及個別 App 的 AX 相容性。
- 幾何觀察沿用既有輪詢及 AX 事件觸發；極短且未被取樣的新視窗拖拉不保證辨識。

自動測試與建置通過不代表上述實機驗收完成。
