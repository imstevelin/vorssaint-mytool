# 顯示切換／音量回饋修復 — 2026-10-18

## 已確認根因與修改

兩份 2026-10-18 崩潰報告皆為 SIGABRT，faulting thread 指向 `AVAudioPlayerNodeImpl::StartImpl` → `VolumeFeedbackAudioPlayer.prepare(uid:)`。AVFAudio 在輸出裝置變更時可拋 NSException，Swift NSError catch 不會攔住。新增 AudioFeedbackBridge，把連接、啟動、play、schedule、stop 的例外留在 Objective-C 邊界，失敗後下一次點按重建；同 UID 的硬體重配置也會重新驗證播放器，保留每次點按獨立排程。

未手動選刷新率時，在 HiDPI 套用動作重新讀取實體模式，避免未就緒快取的 60Hz fallback；切換顯示器時重設表單，驗證時檢查實體端已知刷新率是否匹配。這項防護本身不代表瀏覽器實際幀率問題已解決。

## 驗證

- 原生 Objective-C 例外測試 14 項通過，包括啟動／play／schedule／stop 拋例外、正常連續排程與失敗復原。
- 本地完整回歸 `TESTS OK (113341 checks)`；偏好清理、移除空間、Developer 安裝隔離均通過。
- PA328QV 原生模式為 2560×1440、75Hz。暫停舊版回饋音效後，HiDPI 套用與還原沒有崩潰；HiDPI 模式為 2560×1440、5120×2880 render、75Hz。
- 使用者指出驗收依據是 Dia 的 TestUFO。已重現 HiDPI 模式讀回 75Hz、NSScreen maximum FPS 75、實際 CVDisplayLink 回呼約 74.98fps，但 Dia 的 TestUFO 為 60fps／60Hz。需另查瀏覽器／compositor，不以模式標籤宣稱已修復。

## 分支盤點

盤點檔 `branch-consolidation-2026-10-18.json` 的全部 12 個本地／origin 分支參照，皆為當時 main 的祖先，未整合提交數為 0。分支名稱數量不能作為功能未合併的證據。修復完成後清理這些已整合分支，保留 main、上游 remote 與既有 release tags；不 force-push 或丟棄任何分支提交。
