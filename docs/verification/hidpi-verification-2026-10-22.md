# HiDPI 自動恢復驗證 — 2026-10-22

## 回報與診斷

使用者在重新連接 PA328QV 後，看到「HiDPI 模式或色彩描述檔未穩定，已恢復原設定」，HiDPI 未啟用。當時正式 App 為既有本機候選版，工作分支 `codex/feature-hidpi-input-ddc-baseline` 包含先前 DDC 基準與游標重繪修改；本輪延續相同顯示器修正分支，保留既有提交。

- 原始日誌顯示 23:17:24 鏡像配置成功，約 23:17:28 回退。原版沒有記錄各驗證分項，不能確定是解析度、實體更新率、鏡像或哪一端 ICC 未通過。
- 原生快照為 2560×1440、1×、75Hz。僅加入分項診斷的 Developer 版重新啟動後，即成功恢復 2560×1440、2×、75Hz；實體與虛擬來源的 ColorSync／CoreGraphics ICC SHA-256 均與原生基準一致。
- 使用者依拔除、等待內建穩定、接回、不手動切換的步驟回報「已重接，HiDPI 正常啟用」。這是修正前診斷版的一次成功回報，不能用來證明後續程式修正已消除偶發失敗；該次未取得新的失敗分項。
- 原始日誌與 ICC 快照保存在本機 `/tmp/hidpi-reconnect-20261022/`，不納入 repository。

## 修正

1. 鏡像切換後每次驗證前，使用既有 `DisplayRecoverySnapshot.onlineIDs()` 刷新 active display list 與每程序模式快取，避免持續驗證切換前的舊模式。先前只有建立／掛接階段使用這項刷新。
2. 只有模式不符、鏡像仍正確連接時，才允許原有的一次模式重套。ICC 或實體更新率未通過時，不再重套已正確的虛擬來源模式，避免再次觸發顯示／色彩重配置。
3. 保留原有有限重試、四次連續成功、ICC 完全一致、實體更新率與 recovery helper 安全回退。失敗介面顯示具體未通過項目；日誌分類為 `hidpi`，分別記錄 mode、physical-rate、mirror、source-ICC、physical-ICC。

這些是恢復流程缺口的修正，不代表已由原始失敗取得確定根因。沒有變更使用者 ICC、放寬色彩／更新率條件、自動重啟瀏覽器或無限重試。

## 驗證

- display-restoration：269 checks 通過；AudioFeedbackBridge 原生 fixture：14 checks 通過。
- 新增回歸涵蓋 ICC 晚到不重套模式、鏡像斷開不重套、實體更新率與 ICC 各自保留失敗，以及所有原驗證條件皆需通過。
- 完整 `./build.sh --test`：113369 checks 通過；AudioFeedbackBridge、偏好清理、移除與 Developer 安裝隔離通過。
- 最終 Developer 建置／安裝、selftest 與 strict deep codesign 通過。23:27 啟動兩端為 2560×1440、2×、75Hz，所有分項通過；ICC、有效色彩空間、729 組 RGB 轉換與 gamma 表均與原生快照一致。設定頁確認 HiDPI 啟用、亮度 43%、對比 80%、音量 64%、未靜音與回饋音啟用。
- 正式 `./build.sh`、`./build/VorssaintImstevelin --selftest` 與 stage App strict deep codesign 通過。來源修正提交 `42343ca1`，stage 主執行檔 SHA-256：`461f13582c62a53fc6bcd85e759cde2cbe62d52d2d39208b767960a8677f16d3`。
- [草稿 PR #7](https://github.com/imstevelin/vorssaint-mytool/pull/7) 已更新；先前游標延遲候選補救仍待驗收，維持草稿，不合入 main。
- Fork CI 執行中。正式 App 尚未替換，等待本輪明確安裝授權。
- 最終修正版的實體重接、睡醒與長時間使用：尚未驗證。
