# 移除游標輸入法提示

使用者決定完全移除此功能。以 `git revert -m 1` 撤回 PR #5 的 merge commit `063b04ee3d713684219ad21e812a08b0ccfdfe3f`，保留 Git 歷史。

- 刪除功能服務、CaretReader、圓標 UI、設定頁、文案、功能中心／runtime／權限入口、Defaults 及專屬測試。
- 原始碼、測試與 build.sh 恢復為加入功能前 `05c069d726ada43e08cbec716ef1568ebc9d9377` 的內容；既有共用 InputSourceSelection 保留。
- 刪除舊的功能設計文件與客製契約項目；此文件僅記錄移除，不提供殘留的功能入口。
- 本機正常退出含該功能的 Developer App，清除兩個 App 設定域中的 `inputSourceIndicatorEnabled` 與 `featureAvailable.inputSourceIndicator`。
- 依測試前備份還原本次改動的 Developer 測試設定；只還原仍等於測試值的欄位，避免覆蓋後續其他變更。保留使用者在文字編輯測試文件中輸入的內容。
- 重建並替換 Developer App。正式 App 從未安裝此功能，不替換、不發版，也不清除其其他設定或權限。

驗證以本輪完整 `./build.sh --test`、正式／Developer 建置、`--selftest`、strict deep codesign、安裝二進位無功能型別／符號及移除 PR 的 Fork CI Checks 為準。此移除不需要擴充任何裝置或第三方 App 的相容性驗收。
