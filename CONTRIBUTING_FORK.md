# 實用小工具維護規則

此檔案是版本控制內的 fork 維護依據。修改前先讀本檔及 `docs/FORK_CUSTOMIZATIONS.md`；完整策略見 `docs/UPSTREAM_MAINTENANCE.md`。

- `origin` 是 imstevelin/vorssaint-mytool，`upstream` 是 vorssaint/vorssaint-utils；推送目的地必須明確指定 origin。
- 長期開發主線只有 fork `main`。功能使用 `codex/feature-*`，上游同步使用 `codex/sync-upstream-YYYYMMDD`，以 PR 一般 merge 回 main，保留來源歷史。不要 squash 上游 merge、force-push main 或全域選 ours/theirs。
- 同步前先確認工作目錄與遠端狀態。固定本次上游 SHA；不要混入正在發生的另一批上游更新。
- 每週檢查兩次、每週同步一次。距上次同步超過 14 天或待同步達 50 筆，優先同步再擴充大型功能。重大崩潰／資料損失修正另走快速 patch。
- Bundle ID、設定遷移、fork 更新來源、顯示器安全恢復、視窗手動操作優先、藍牙指定裝置、防循環與小夥伴互動都是必須保留的契約；見客製清單。
- 與官方功能交集時，整合行為及測試，移除不再需要的客製差異。新功能不自動替使用者啟用。
- 合入 main 前完成相關 suite、`./build.sh --test`、`./build.sh`、`./build/VorssaintImstevelin --selftest` 與簽章驗證，檢查 Fork CI。發版另驗證 DMG。
- 不得把建置、單元測試或程序啟動當成實體螢幕、藍牙音訊、長錄影、耗電的驗證。同步紀錄要明列實測與未驗證項目。
- 每次同步更新 `docs/upstream-state.json` 及 `docs/upstream-sync/` 紀錄；寫入來源 SHA、衝突處理、測試、延後項目與下次檢查日期。
- 發版使用 fork `1.x` 版本與自己的 Releases；main 合併不等於已發版，也不自動安裝到使用者的正式 App。
- 排程只讀取、比較並產出報告；不自動合併、發版、安裝或修改使用者設定。
