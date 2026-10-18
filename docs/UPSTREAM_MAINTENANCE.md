# 實用小工具：上游追蹤與獨立發版計畫

研究日期：2026-10-18（Asia/Taipei）。下方現況與數量保留為研究時快照；第一輪的實際執行與驗證見 [同步紀錄](upstream-sync/2026-10-18.md)，目前整合基準由 [upstream-state.json](upstream-state.json) 記錄。維護規則見 [CONTRIBUTING_FORK.md](../CONTRIBUTING_FORK.md)。

## 現況與證據

| 項目 | 本次確認結果 |
| --- | --- |
| Fork | `imstevelin/vorssaint-mytool`，目前工作分支 `codex/upstream-window-memory-fix` |
| 本次功能快照 | `cc4b8c6a`，172 個檔案，包含先前尚未提交的功能與驗證紀錄 |
| App 版本 | `1.0.9` / build `10`；版本號不代表已建立同名 GitHub Release |
| 官方最新正式版 | `v3.4.1`，GitHub 發佈於 2026-10-09 07:45 台北時間 |
| 已整合的上游基準 | `794608a58d8a88608d3c3cb2e4f22373cf52bfdc`；Git ancestry 確認包含 `v3.4.1` |
| 本次抓取的上游 main | `5457c2d69a0dffb62a7c644252e28207b1188457`，台北時間 2026-10-18 02:12 的 changelog 提交 |
| 待同步 | 自已整合基準以來 64 筆提交，223 個檔案，19,777 行新增／3,780 行刪除（含文件及測試） |
| 雙方共同改動 | 54 個檔案；合併預演得到 12 個文字衝突檔案 |
| Fork 預設分支 | GitHub 仍為 `main`，停在 `47c2653c`，不是目前完整客製版本 |

來源：[官方 Releases](https://github.com/vorssaint/vorssaint-utils/releases/tag/v3.4.1)、[固定版本 Changelog](https://github.com/vorssaint/vorssaint-utils/blob/5457c2d69a0dffb62a7c644252e28207b1188457/CHANGELOG.md)、[本次待同步範圍](https://github.com/vorssaint/vorssaint-utils/compare/794608a58d8a88608d3c3cb2e4f22373cf52bfdc...5457c2d69a0dffb62a7c644252e28207b1188457)。數量由本地 fetch 後的 Git 計算，後續上游可能繼續前進。

這不是落後一個正式版：目前已包含最新正式版，也已吸收部分正式版之後的修改。問題在於上游仍快速前進，而我們的品牌、顯示器、音量與小夥伴也改動共用檔案；拖久會增加每次同步的成本。依這次觀察，上游 10/15–10/17 已新增 64 筆提交，不能將這三天的速度當成長期固定速率。

## 官方最近在做什麼

最新正式版提供多顯示器／無瀏海／鎖定畫面 Dynamic Island、小夥伴、Watch、AI agents、視窗吸附區域與截圖分享。這些已在目前 fork 的祖先歷史中。

尚未整合的 main 修改重點如下；它們仍屬 Unreleased，不能視為下一版已承諾的發佈內容：

| 領域 | 最新內容 | 對 fork 的意義 |
| --- | --- | --- |
| 錄影 | `55d5f8e4` 修正 GIF 複製、無法解碼影格及匯出進度 | 優先檢查，須保留我們的游標 spool、串流編碼與取消路徑 |
| 音訊 | `71375a50` 音量歸零同步靜音；`f1632e5f` 耳機拔除後可靜音；無效麥克風值處理 | 與 SystemOutputControl、音量回饋有功能交集，需做行為整合 |
| AI Agents | `57be2112` reader protocol 重構；`995c2741` Codex log continuation；`ba56623b` 多帳號 limits；Claude CLI limits 與降低閒置更新頻率 | 與我們的啟停／保存佇列改善重疊，適合整批 review，不能單純選一邊 |
| Dynamic Island | `3fbcd4ed` 展開介面重排、`d9878eb0` 控制空間調整、封面與 VoiceOver 修正 | 高衝突區；官方移除展開島的小夥伴及部分追蹤事件，我們需接回自訂互動 |
| 視窗 | 關閉／隱藏視窗判定、僅前置指定視窗、Java 程序辨識、modifier drag snapping | 以官方為主，回歸我們的尺寸記憶與快取失效 |
| 工具 | 截圖 Spotlight／畫布擴張／圖片圖層、Markdown 待辦、功能別 What's New、更新例外清單 | 可以跟著整合，但新功能仍由使用者選擇啟用 |

公開 PR 是研究線索，並非已合併功能。例如 [#3197 鏡像顯示器控制](https://github.com/vorssaint/vorssaint-utils/pull/3197) 與我們的 HiDPI／鏡像路徑密切相關；[#3095 選取文字工具列](https://github.com/vorssaint/vorssaint-utils/pull/3095) 仍在審查，適合追蹤，不宜提前整批搬入。

## 建議的更新節奏

採用「持續吸收、獨立發版」：同步上游原始碼的頻率高於對外發佈頻率。保有 fork 功能與版本，不需要跟官方每個版本同日推出。

| 工作 | 建議頻率／時限 | 完成條件 |
| --- | --- | --- |
| 檢查上游 | 每週兩次；官方正式發版時加查一次 | 記錄 SHA、提交數、重要修正、重疊檔案與風險 |
| 常規同步 | 每週建立一次整合分支；超過 50 筆提交或 14 天則提前安排 | 合併、相關測試與完整建置通過，合入 fork main |
| 官方正式版 | 發佈後 7 天內評估、目標 14 天內整合 | 相容性與客製回歸通過；不必立即發 fork release |
| 緊急修正 | 安全、資料損失、崩潰、無法錄影等，24–72 小時內評估 | 必要時挑選修正及依賴，測試後發 patch |
| Fork 發版 | 每 2–4 週或有值得推出的客製功能 | 固定候選版、驗收、封裝、標記與 release notes |

以上為維護目標。第一輪已加入每週兩次的 GitHub Actions 檢查流程；同步及發版仍需依驗證結果執行，不會自動合併或安裝。遇到行為衝突可延後該功能的對外發佈，但應記錄阻擋原因與下一次處理日期，避免無限期擱置。

## 分支與歷史

目標只保留一條長期 fork `main`，短期使用 `codex/feature-*`、`codex/sync-upstream-YYYYMMDD`、`codex/release-*`。`upstream/main` 維持遠端追蹤用途，不要再創一條長期鏡像開發分支。

1. 先把目前客製分支以 PR 整理進 `origin/main`。用一般 merge 保留歷史；避免 squash 上游同步提交或重寫已推送歷史。
2. 後續功能及上游同步皆從 fork main 分出短期分支；通過驗證後回 main。
3. 上游同步以 `git merge --no-ff <固定上游 SHA>` 為主，讓 Git 正確知道哪些歷史已吸收。不要長期只 cherry-pick 功能，導致祖先基準持續落後。
4. Cherry-pick 僅用於緊急修正，使用 `-x` 記錄來源及依賴；下次完整合併檢查是否重複或語意衝突。
5. 發版以 tag 固定來源，不要為每個版本留下永久 release 分支；需要維護舊版時才例外保留。

範例（完成 main 整理後；先確認工作目錄乾淨）：

```sh
git fetch origin
git fetch upstream
git switch main
git pull --ff-only origin main
git switch -c codex/sync-upstream-YYYYMMDD
git merge --no-ff <reviewed-upstream-sha>
./build.sh --test
./build.sh
```

禁止直接將上游覆蓋 fork main，或對衝突全域套用 `ours`／`theirs`。文字自動合併成功也要檢查行為是否改變。

## 降低客製維護成本

| 範圍 | 建議邊界 |
| --- | --- |
| 品牌與發版 | 以 AppInfo／獨立品牌配置集中名稱、bundle ID、release repo、icon、版本。逐步減少散布於各語系的硬編碼名稱 |
| 顯示器 | 保持 DisplayRecoverySupport、VirtualDisplayBridge／Host 與 HiDPI 服務獨立；以窄介面接 BrightnessService 與 Settings |
| 視窗記憶 | 保持 profile store、AX cache、WindowServer snapshot 的邊界；保留手動操作優先、一次還原及事件失效規則 |
| 音量 | 由 SystemOutputControl 統一音量／靜音語意，VolumeFeedbackSound 管理音效；讓 UI 呼叫共用行為 |
| 小夥伴 | 自訂造型／動作／來訪邏輯獨立；用 adapter 接官方 island 佈局與 lifecycle，避免整份 NotchView 分叉 |
| 效能修正 | 依服務保存小而可驗證的差異；官方改善同一路徑時評估用其實作取代，避免重複快取與排程 |

不建議現在大規模搬移整棵 Sources 或重新命名所有 `Vorssaint` 型別／路徑，會讓後續 Git 比對更難。先抽最常衝突的接點，分次完成。建立客製清單，記錄每項目的、入口、對應測試與上游替代情況；官方完成同等功能且通過回歸時，刪除不再需要的 fork 差異。

可回饋上游的通用修正（視窗識別、錄影記憶體、生命周期等）應先整理為小提交及可重現測試；是否發 PR 另行決定。品牌、自訂動物與個人藍牙策略繼續由 fork 維護。

## 驗證與更新通道

- 每次同步跑相關 suite、完整 `./build.sh --test` 及 `./build.sh`，記錄上游 SHA、fork SHA、toolchain、結果與已知限制。
- 錄影驗證有聲／無聲、GIF、長錄影、進度與取消；音訊驗證靜音、粗階音量、耳機拔除與選定藍牙裝置。
- 顯示器驗證重接／解析度切換／HiDPI／鏡像／色彩，以及手動拖拉視窗不被還原拉回。
- 小夥伴驗證展開與收合島、來訪、游標互動、減少動態效果、閒置暫停；AI logs 驗證長歷史、多帳號及停用／重啟邊界。
- 自動測試不替代實體顯示器、藍牙、長時間錄影及耗電量測。正式發版前記錄實測範圍；回退保留舊 App 與設定備份，尤其涉及 profile 格式時。

Fork 繼續使用自己的 `1.x` 版本與 bundle ID，release notes 另列「上游基準 SHA／相容的官方版本」。更新只指向 fork 的 GitHub Releases，保留現在的手動安裝通道；不能把來源改成官方二進位檔，否則會失去客製內容與身分延續。

第一輪已修正 `.github/workflows/ci.yml` 的 fork 執行檔路徑，涵蓋 main 的程式變更及 PR（sync 分支透過 PR 驗證），驗證自訂 helper 並上傳候選 DMG。現有 `release.yml` 限制官方 repo／actor，不能視為 fork 已有自動發版；應另建 fork 發版流程。Developer ID、公證與自動安裝列為後續獨立工作。本地原生動畫測試需在登入且螢幕解鎖時重跑；鎖定狀態的失敗應保留並記錄，透過 CI 的獨立圖形環境驗證，不能修改斷言來消除失敗。

## 操作入口

首次 clone fork 後，設定來源：

```sh
git remote add upstream https://github.com/vorssaint/vorssaint-utils.git
python3 Tools/check-upstream.py
```

已存在 upstream 時不要重複新增。工具預設 fetch upstream、查詢官方最新正式版，輸出 Markdown；`--format json` 供其他工具讀取。離線檢查使用 `--no-fetch --no-release-check`，代表未查詢最新網路狀態。評估既有提交，不包含尚未提交的修改；不 checkout、merge 或 push。

GitHub → Actions → Upstream assessment 可手動執行並查看 summary／artifact。排程為每週一及四台北 09:00，由 GitHub 代跑，可能延遲；不需要本機保持開機。正常與有差異的結果均保留報告，不另行自動留言或開 issue。

## 第一輪完成後的操作

第一輪已將客製工作與 71 筆官方提交整理進 main，固定上游基準為 `597f27a6`；README 安裝入口、Fork CI、客製契約、同步記錄、回退演練與 GitHub 監測均已建立。完整證據見 [第一輪紀錄](upstream-sync/2026-10-18.md)。

1. 每週一／四查看 Actions 的 Upstream assessment；開始大型功能前執行 `python3 Tools/check-upstream.py`，先確認同步負債。
2. 每週同步時建立新的 `codex/sync-upstream-YYYYMMDD`，固定新目標 SHA，按客製契約審核變更、處理衝突並保留上游 ancestry。
3. 更新同步基準與記錄，通過相關回歸、完整 CI、建置和回退驗證後，以一般 merge 合回 main。
4. 官方新增同等修正時，驗證後刪除對應 fork 差異；分別追蹤未整合提交數、同步天數、持續衝突與未完成人工驗收。
5. 依客製清單完成實機驗收，再單獨決定 fork 發版；本輪候選 DMG 不直接覆蓋正式 1.0.9 發佈。

下次檢查為 2026-10-19、常規同步目標為 2026-10-25；重大修正、50 筆提交或 14 天門檻會提前。截止後出現的新提交依下一輪報告審核，不延伸已驗證批次。
