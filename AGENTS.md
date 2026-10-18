# 實用小工具 — Agent 專案指引

此檔案是所有在本 repository 工作的 agent 的共同入口。每次新對話、恢復中斷任務或開始修改前，先確認已讀取本文件與下列相關文件；本文件更新後重新閱讀。遵循使用者本次明確指示與較高層級指令，並保留未授權改動的既有工作。

## 先建立正確上下文

1. 修改前閱讀 `CONTRIBUTING_FORK.md`、`docs/FORK_CUSTOMIZATIONS.md` 與 `docs/MAINTENANCE_PLAYBOOK.md`。同步官方時另讀 `docs/UPSTREAM_MAINTENANCE.md`、`docs/upstream-state.json` 及最近的 `docs/upstream-sync/` 紀錄；發版時讀 `FORK_RELEASE.md` 與最近的 `docs/releases/` 紀錄。
2. 檢查 `git status --short --branch`、所在分支、remotes 與差異，識別使用者未提交工作。不要覆蓋、不明原因 stash、reset 或清掉無關檔案。需要新分支時先確認 main 最新且工作目錄乾淨；未完成的功能保留在原分支。
3. 以本次實際檔案、Git 與 CI 結果為準。App 版本／build 讀 `Resources/Info.plist`；已整合官方基準讀 `docs/upstream-state.json`；正式發佈狀態查 fork Releases。不要從聊天記憶、候選 DMG 或舊紀錄推斷目前狀態。
4. 用繁體中文說明結果，交代修改、驗證與尚未驗證部分；必要的長期決策更新對應專案文件，避免只留在聊天。

## 專案與架構

這是 Vorssaint 的獨立 macOS Swift／SwiftUI／AppKit fork，產品名稱「實用小工具」，以 Apple Silicon 為目標。保留既有 Vorssaint 型別與原始碼目錄名稱以減少上游衝突，不做無需求的大規模重新命名。

| 入口 | 用途 |
| --- | --- |
| `Sources/Vorssaint/App/` | AppDelegate、FeatureRuntime、選單列入口與生命週期 |
| `Sources/Vorssaint/Core/` | FeatureCatalog、Defaults、AppInfo、共用模型與 Localizations |
| `Sources/Vorssaint/Services/` | 功能服務；按 Display、WindowLayout、Audio、Bluetooth、Notch、AgentUsage、Recorder 等範圍查找 |
| `Sources/Vorssaint/UI/` | SwiftUI／AppKit 視圖、設定頁、島與工具面板 |
| `Sources/DisplayRecovery*`、`Sources/VirtualDisplay*` | 顯示恢復 helper、虛擬顯示器 host／bridge |
| `Sources/FanControlHelper/`、`Sources/NowPlayingAdapter/` | 風扇與 Now Playing 原生輔助元件 |
| `Resources/` | Info.plist、圖示、entitlements 與封裝資源 |
| `Tests/` | 行為回歸、來源產生器、原生 fixture 與安裝／移除隔離檢查 |
| `Tools/`、`build.sh` | 上游評估、DMG 封裝與正式／Developer 建置入口 |
| `.github/workflows/` | Fork CI、只讀上游監測及有官方 repo 限制的原 release workflow |
| `docs/` | 客製契約、維護流程、同步來源、驗證與發版紀錄 |

新增功能前追蹤相鄰功能的 catalog → runtime → service → UI／settings → defaults／localizations → tests 路徑，遵循既有安裝選擇與生命週期。用 `rg` 尋找實際型別與入口；避免另起重複服務或輪詢。詳細客製邊界由 `docs/FORK_CUSTOMIZATIONS.md` 維護。

## 必須保留的產品契約

- 正式 bundle ID：`com.imstevelin.vorssaint-imstevelin`；Developer：`com.imstevelin.vorssaint-imstevelin.dev`。品牌、圖示、設定遷移與更新來源維持 fork 身分。
- 每顯示器的視窗大小／位置記憶、視窗化最大狀態、手動操作優先與顯示器安全恢復。排除真正全螢幕、暫時貼齊、對話框與固定視窗。
- 藍牙修復只針對已選裝置，保留離線選擇、冷卻與防循環；音量每次接受的點按／連續操作都有獨立回饋，不更動 macOS 全域音效設定。
- 保留五種自訂小夥伴、游標與事件反應、減少動態效果及不可見暫停。保留 AI 掃描取消／保存順序、錄影游標精度與取消行為。
- 更新只指向 fork Releases，採手動安裝；不得換成官方二進位更新通道、bundle ID 或簽署身分。遵循 LICENSE 與 TRADEMARKS.md。

## 自行開發功能

- 唯一長期主線為 fork `main`，追蹤 `origin/main`。從最新乾淨 main 建立 `codex/feature-*`，一條分支處理一個可審查的功能。
- 大型功能開始前執行 `python3 Tools/check-upstream.py`。達維護門檻時優先整合官方，再擴充大型功能；使用者本次另有明確優先順序則依其指示。
- 日常編譯使用 `./build.sh --dev --install`，再以 `open '/Applications/實用小工具 (Developer).app'` 啟動。Developer 權限獨立；測試時避免兩個 App 同時控制相同視窗、音量或快捷鍵。
- 依修改範圍執行 `./build.sh --test-suite=<suite>`；用 `./build.sh --list-tests` 查名稱。UI 優先沿用原生結構與漸進揭露。
- 完成後 commit、推送 `origin`、開 PR 到 main；符合 `CONTRIBUTING_FORK.md` 的整合檢查後合併。功能開發本身不代表已授權替換正式 App 或發版。
- 若官方同步與功能開發並行，從乾淨 main 完成獨立同步 PR，再把更新後的 main merge 回功能分支並重新驗證。不要把未完成功能混入同步分支。

## 跟進官方

- `origin`：`https://github.com/imstevelin/vorssaint-mytool.git`；`upstream`：`https://github.com/vorssaint/vorssaint-utils.git`。推送明確指定 origin；不推送 upstream。
- 上游監測每週一／四台北 09:00 由 GitHub Actions 執行，可能延遲；只讀取、比較、預演及產出 summary／artifact，不自動合併、發版、安裝、開 issue 或留言。不要把排程設定當成已成功執行。
- 原則每週同步一次。有未整合提交且距上次同步達 14 天、待同步達 50 筆或重大修正時提前；官方正式版 7 天內評估、目標 14 天內整合。
- 使用 `python3 Tools/check-upstream.py` 取得最新評估，檢查待同步範圍、正式版與衝突。離線模式需明確註明未確認最新網路狀態。
- 從最新乾淨 main 建立 `codex/sync-upstream-YYYYMMDD`，固定本輪官方 SHA。審核行為及相依性後一般 merge，逐項整合衝突；不得 squash 上游 merge、force-push main 或整份選 ours／theirs。
- 對照客製契約檢查自動合併結果；官方有等效修正時驗證後縮小 fork 差異。官方新功能遵循既有功能啟用選擇，不替使用者自動開啟。
- 完成相關回歸、完整 CI、建置與回退驗證後，以 PR 一般 merge 合回 main。更新 `docs/upstream-state.json` 與 `docs/upstream-sync/`，記錄來源、衝突取捨、驗證、延後項目與下次檢查。
- 本輪截止後的新提交留待下一輪，除非使用者明確變更範圍；不要無限追逐上游。

## 驗證與正式交付

- 所有 `build.sh` 建置與測試共用 build 目錄，依序執行，不能同時編譯／測試或邊編譯邊改來源。不要直接編輯產生的測試原始碼；修改原始測試或 `Tests/generate_sources.py`。
- 程式整合依維護規則完成完整 `./build.sh --test`、`./build.sh`、`./build/VorssaintImstevelin --selftest`、strict deep codesign 與 Fork CI；發版另做 DMG 完整性、版本、架構及 checksum 驗證。純文件修改檢查內容與連結，不需重跑 App 建置。
- 原生動畫測試在登入且解鎖的圖形環境執行；保留失敗證據並定位原因，不放寬斷言來掩蓋失敗。非同步測試等待實際事件／佇列標記並設失敗上限，避免用固定短睡眠推定完成。
- 建置、selftest、程序啟動或設定頁可用不等於實體螢幕、藍牙音訊、長錄影或耗電已驗證；紀錄中區分自動測試與實機驗收，不代填未做項目。
- 使用者要求正式安裝／發版時，完成已授權交付。先保存舊 App 與自己的設定備份，再替換、驗證簽章與版本並啟動；保留原 bundle ID 與既有設定。
- 發版提升 fork 版本與 build，同步更新 `Tests/SwitcherModelFeatureTests.swift` 的版本保護與支援提示決策、`FORK_RELEASE.md` 及 `docs/releases/`。標籤固定驗證提交；上傳對應 DMG／SHA-256，驗證公開下載，不覆蓋既有 tag 或公開資產。
- fork 採獨立 `1.x` 版本。原 `release.yml` 限制官方 repo／actor，不代表 fork 會自動發版。Apple Development 簽署不等於 Developer ID 公證，依實際驗證結果說明。
- 回退 App 使用保存的舊包與必要設定備份；回退原始碼使用修復 PR 或 `git revert -m 1 <merge SHA>`。保留歷史；重套被 revert 的官方 merge 需明確處理 revert，不假設相同上游 SHA 能再次帶回修改。

## 維護這份指引

架構、命令或流程改變時同步修正本文件與對應詳細文件。保持此入口精簡，動態版本／SHA／測試數量留在其專責紀錄，不在此複製。不要寫入憑證、簽署私鑰或個人敏感資料。此檔案需受 Git 版本控制，讓新 checkout／worktree 與新對話使用相同指引。
