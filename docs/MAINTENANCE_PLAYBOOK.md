# 日常開發、官方同步與發版

長期主線是 fork `main`。官方來源是 `upstream`；自己的程式、PR、tag 與 Release 都推到 `origin`。開發、同步、安裝及發版是四個分開的動作。

## 跟進官方

GitHub Actions 的 **Upstream assessment** 每週一／四台北 09:00 產出 summary 與報告，不要求這台 Mac 開機；排程可能延遲。查看待同步提交、正式版、預演衝突與優先原因。報告不會自動修改程式或更新已安裝 App，也不會主動開 issue／留言。

每週安排一次同步；新提交達 50 筆、超過 14 天仍有未整合提交或重大修正時提前。官方正式版 7 天內評估、目標 14 天內整合；beta 要先審核，不直接覆蓋目前驗證批次。開始大型客製功能前也先執行：

```sh
python3 Tools/check-upstream.py
```

同步由乾淨且最新的 main 建立 `codex/sync-upstream-YYYYMMDD`，固定官方 SHA，對照 `docs/FORK_CUSTOMIZATIONS.md` 整合，通過相關測試與完整 CI 後，以 PR 一般 merge 合入 main。更新 `docs/upstream-state.json` 與 `docs/upstream-sync/`。詳細步驟見 `CONTRIBUTING_FORK.md`；不要 squash 上游 merge、force-push main 或整份採 ours/theirs。

## 開發自己的功能

先把未完成的修改 commit 在原功能分支，保持工作目錄乾淨；不要把它混進官方同步分支。每個功能從最新 main 開一條短期分支：

```sh
git switch main
git pull --ff-only origin main
python3 Tools/check-upstream.py
git switch -c codex/feature-your-feature
```

先用獨立 Developer App 測試：

```sh
./build.sh --dev --install
open '/Applications/實用小工具 (Developer).app'
./build.sh --test-suite=notch  # 依修改範圍選 suite；--list-tests 可查名稱
```

Developer 的 bundle ID 為 `com.imstevelin.vorssaint-imstevelin.dev`，與正式 App 分開；權限需要獨立授予。測試時只啟用需要的功能，避免兩個 App 同時控制音量、視窗或快捷鍵。所有 build/test 共用 build 目錄，必須依序執行，不能同時建置與測試。

完成後 commit、`git push -u origin HEAD` 並開 PR 到 main，審查客製契約與 CI，合併後回到 main 執行 `git pull --ff-only origin main`。若期間官方需要同步，先由乾淨 main 完成同步 PR，再把更新後的 `origin/main` merge 回功能分支，重新驗證；不要在含未完成功能的分支上直接混入官方整合。

## 更新正式 App 與發版

只有準備驗收或發版時才操作正式 App；功能分支編譯成功不代表可以發版。使用乾淨且已通過 CI 的 main，提升 fork 版本／build，更新 `FORK_RELEASE.md`，依序建置、驗證及封裝：

```sh
./build.sh
./build/VorssaintImstevelin --selftest
codesign --verify --deep --strict 'build/stage/實用小工具.app'
./Tools/make-dmg.sh
```

保留舊 App 與自己的設定備份，完成實機驗收後才更新 `/Applications/實用小工具.app`。標籤只指向該次已提交、驗證的 main 版本，以 fork `v1.x` tag 建立 GitHub Release、上傳對應 DMG 和 SHA-256。每個公開版本都使用新版本號，不覆蓋已發佈的資產。沿用正式 bundle ID 與簽署識別以維持設定／權限；macOS 仍可能重新要求權限。

現有 `release.yml` 限制官方 repo／actor，並不會替 fork 自動發版。目前 fork 是手動發版、手動下載安裝，不會自動覆蓋正式 App。Apple Development 簽署不等於 Developer ID 公證。

出問題時先還原已保存的舊 App；原始碼用修復 PR 或 `git revert -m 1 <merge SHA>`，保留歷史。不要 reset／force-push main。回退 App 不代表回退新版本已寫入的設定，必要時另還原自己的設定備份。

## 可以直接交代的工作

- 「檢查官方更新，先給我待同步內容與衝突報告。」只做評估。
- 「執行本週上游同步，保留客製行為，通過 CI 後合入 main。」做原始碼整合。
- 「新增某功能，用 Developer App 測試，通過後合入 main。」做功能開發。
- 「把目前 main 發為下一版，替換正式 App 並發布 GitHub Release。」做正式交付。

這些工作都遵循版本控制內的規則；每次都以現況重新檢查，不依賴前一次聊天記憶。
