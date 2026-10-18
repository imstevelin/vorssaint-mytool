# 顯示切換／音量回饋修復 — 2026-10-18

## 已確認根因與修改

兩份 2026-10-18 崩潰報告皆為 SIGABRT，faulting thread 指向 `AVAudioPlayerNodeImpl::StartImpl` → `VolumeFeedbackAudioPlayer.prepare(uid:)`。AVFAudio 在輸出裝置變更時可拋 NSException，Swift NSError catch 不會攔住。新增 AudioFeedbackBridge，把連接、啟動、play、schedule、stop 的例外留在 Objective-C 邊界，失敗後下一次點按重建；同 UID 的硬體重配置也會重新驗證播放器，保留每次點按獨立排程。

未手動選刷新率時，在 HiDPI 套用動作重新讀取實體模式，避免未就緒快取的 60Hz fallback；切換顯示器時重設表單，驗證時檢查實體端已知刷新率是否匹配。這項防護本身不代表瀏覽器實際幀率問題已解決。

## 驗證

- 原生 Objective-C 例外測試 14 項通過，包括啟動／play／schedule／stop 拋例外、正常連續排程與失敗復原。
- 本地完整回歸 `TESTS OK (113341 checks)`；偏好清理、移除空間、Developer 安裝隔離均通過。
- PA328QV 原生模式為 2560×1440、75Hz。暫停舊版回饋音效後，HiDPI 套用與還原沒有崩潰；HiDPI 模式為 2560×1440、5120×2880 render、75Hz。
- 使用者指出驗收依據是 Dia 的 TestUFO。已重現 HiDPI 模式讀回 75Hz、NSScreen maximum FPS 75、實際 CVDisplayLink 回呼約 74.98fps，但 Dia 的 TestUFO 為 60fps／60Hz；後續定位見下節，不以模式標籤宣稱已修復。

## Dia 實際幀率定位

Dia 的 GPU 診斷記錄在動態新增虛擬顯示器後出現 `Skipping CVDisplayLinkCreateWithCGDisplay for missing NSScreen. Display ID: 78`，其他新建虛擬 ID 也有相同訊息。原生與虛擬顯示器實際 CVDisplayLink 回呼皆約 75fps，Dia TestUFO 卻為 60fps／60Hz；重新載入、另開視窗均未恢復。

透過 Dia 的 `chrome://gpucrash` 診斷入口重新建立 GPU 程序，再重新載入 TestUFO，相同 HiDPI 模式下顯示 75fps／75Hz、READY。修正版 App 安裝後再關閉／開啟 HiDPI、新建虛擬 ID 81 時重現 60fps；相同步驟再次恢復 75fps。此時實測虛擬顯示器 74.997fps、實體鏡像端 74.979fps。

這些結果支持 Dia 的動態顯示資訊／GPU 生命週期問題；未證明其內部所有原因。日常建議先保留 HiDPI，再用 ⌘Q 完全退出 Dia 後重新開啟；此建議依據 GPU 重新初始化結果，尚未另做完整退出／重啟的 A/B 驗證。單純關閉視窗不等於結束 GPU 程序。再次切換 HiDPI 可能重現，本輪沒有把終止瀏覽器當作 App 的自動修復。

## 本地安裝與實機範圍

- 正式路徑已替換為 1.1.1 build12，保留正式 bundle ID，strict deep codesign 通過；正式建置與 `SELFTEST OK` 通過。
- 舊版與設定備份存於 `~/Library/Application Support/實用小工具/Backups/實用小工具-1.1.0-before-1.1.1.app`、`preferences-before-1.1.1.plist`。
- 回饋音效設定恢復為啟用；新版本在此設定下完成 HiDPI 開／關及保留設定，程序仍存活，診斷目錄沒有新的 App 崩潰報告。
- 最終 HiDPI 為 2560×1440、2×、75Hz，Dia TestUFO 在 GPU 重建及重新載入後為 75fps／75Hz、READY。
- 未驗證實際拔插線材、另一台螢幕、不同瀏覽器或長期運作；音量回饋物理聲音與延遲仍需聆聽驗收。未建立 1.1.1 公開 Release。

## 分支盤點

盤點檔 `branch-consolidation-2026-10-18.json` 的全部 12 個本地／origin 分支參照，皆為當時 main 的祖先，未整合提交數為 0。分支名稱數量不能作為功能未合併的證據。修復完成後清理這些已整合分支，保留 main、上游 remote 與既有 release tags；不 force-push 或丟棄任何分支提交。

已重新 fetch origin 並對上述 12 個參照逐一確認為 origin/main 祖先，接著刪除六條舊遠端分支與六條本地分支；所有提交仍可從 main 追溯。修正分支獨立經 PR #3 與 CI 驗證。

## 整合結果

- [Fork CI 39135303018](https://github.com/imstevelin/vorssaint-mytool/actions/runs/39135303018) 對修正提交 `43d27b041e6a60b39b522de9f6702096ebc88dc8` 全部通過。macOS 26 為 113341 checks，Swift 6.0.3／macOS 15 為 113340 checks；兩者原生例外測試皆為 14 項，selftest、偏好清理／移除／Developer 安裝隔離皆通過。維護工具測試 5 項通過，候選 DMG 封裝與驗證通過。
- [PR #3](https://github.com/imstevelin/vorssaint-mytool/pull/3) 於 2026-10-18 22:32 台北時間一般 merge，合併提交為 `ca85c23c6a0e314de69f6bff8000fa8dabd1149e`。未 squash、reset 或 force-push。
- 修正分支確認為 main 祖先後亦刪除。本地開發分支與 origin 遠端 heads 最終僅保留 main，保留 upstream remote／追蹤參照及所有既有 tag。
- 後續提交只補充本文件與客製契約，程式來源、版本與測試仍與上述已驗證提交相同。公開 Release 未隨 main 合併更新。
