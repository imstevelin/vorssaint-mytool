# 原生 HiDPI 預設與單一開關（2026-10-24）

## 使用契約

使用者要求原生縮放作為預設方式，以簡單開關操作，並能支援不同解析度與更新率；不接受額外先按「準備原生縮放」。已確認的舊虛擬 session 保持相容，進階方式選擇仍可明確改用鏡像。

開關先非同步讀取這台螢幕的公開與底層原生模式，已存在就直接進入有界就緒與安全切換。缺少時才提出系統管理員授權，備份／追加型號覆寫一次。待啟用要求保存 UUID、型號、尺寸、更新率、面板校正與準備階段；重接或重開後再查模式，以相同開關取消。只在明確的人為開啟動作中允許第一次授權；啟動與拓樸通知不得反覆跳授權。未完成設定會提示重新開關重試。

使用既有 ReconnectGate 取得四次連續模式／有效 ICC／AppKit 就緒觀測，最多 20 次，並沿用獨立 watchdog、實際 2×／更新率／無鏡像／ICC 驗證與確認倒數。確認前的待啟用 profile 不得當成已確認 profile，也不自動跳過確認。系統仍不提供模式時明確顯示等待啟用，保留目前桌面，不自動回退鏡像或重複授權。

## 模式與更新率

- 能力清單按顯示器分開，公開 API 的小數時序優先，底層整數時序只補缺漏。解析度下的 Hz 選單只列該尺寸的可用時序；手動要求仍須系統接受。
- 取消原生 3072 像素／240Hz 的候選限制，改以有界 320×200 至 8192×8192 logical pixels、1–1000Hz 請求範圍與實際模式匹配驗證；不代表硬體一定支援上限。虛擬 host 的舊限制不放寬。
- 預設保留每台螢幕即時／快取的實際更新率；使用者明確選擇新的時序後才更動，不偷偷降到 60Hz。UI 只消費能力快取，不在 SwiftUI body 同步查詢 WindowServer。
- 邏輯測試涵蓋 3840×2160@120、3440×1440@144、5120×1440@240、1080×1920@75、7680×4320@60、2560×1440@360 與 143.856Hz 等例子，以及顯示器／尺寸配對、59.94 與 60 的去重、無效值、一次準備與待啟用持久化。這些不是對相應硬體的實測。

## 維護與驗證

沿用本次修復分支。開始時重新執行 upstream assessment：固定官方 SHA e9169610，仍有 71 筆待整合、上次同步 6 天；依使用者本次原生操作簡化的明確優先順序先完成此修復，不混入官方整合。

- display-restoration：345 checks，AudioFeedbackBridge 14 checks 通過。
- 使用者解鎖後完整回歸通過：113456 checks，偏好清理、移除 Spaces 與 Developer 安裝隔離檢查通過。最終 Release 建置、selftest、strict deep codesign 通過。
- 前一版 dffb4138 的 Fork CI 40027204711 成功；本次單一開關變更的 CI 以後續推送提交為準。
- 長時間卡頓、其他型號螢幕、原生睡醒／重接及跨硬體驗收仍須分開，不因程式允許數值或測試通過而宣稱全部支援。


## 預設選取與生命週期

一般開關若未指定尺寸，優先選擇與目前時序、長寬比相同且在目前介面範圍內的可用原生模式；公開的最高尺寸需要更大的繪製 buffer 時，避免直接把不可能的尺寸當成通用預設。使用者已明確選擇／輸入尺寸或更新率後不自動改寫。沒有同更新率的選項時不偷偷改到較低 Hz，仍以明確設定／等待或使用者另選模式處理。

待啟用要求不保存 numeric display ID；每次重接按 UUID／vendor／product 重新解析，清理已重用的 ID 映射。顯示控制服務啟動時載入待啟用要求，停用功能時取消，App 正常退出時暫停並保存；下一次啟動不需要先打開設定頁才繼續。多台螢幕的待要求以全域切換閒置事件串行處理。

## 鎖定環境的無效圖形驗證

初次完整回歸退出 1，共 113452 checks，21 項失敗集中在 NotchCompact、DockPreviewScroll、SwitcherScroll 的捲動可見範圍。隨後 CGSessionCopyCurrentDictionary 明確讀回 CGSSessionScreenIsLocked=1；本次保留完整失敗 log，不將其列為產品回歸，也不放寬斷言。HiDPI 相關邏輯檢查通過。依 AGENTS.md，需在登入且解鎖的圖形環境重跑完整驗證。

使用者明確回覆已解鎖後，讀回 locked=false，保持相同斷言重跑，完整檢查全部通過。原失敗與重跑記錄分別保存在外部工作目錄 `one-switch-full-tests.log`、`one-switch-full-tests-unlocked.log`。

## 備份安裝與實機操作

依本輪持續有效的正式替換授權，09:22 備份正式 App、退出前後偏好與自己的 Application Support，再替換 `/Applications/實用小工具.app`。備份位於使用者 Application Support 的 `實用小工具/Backups/20261024-092232-before-native-one-switch`；替換前後偏好完全相同，正式路徑與 stage 的主程式、NativeHiDPIHelper 雜湊一致，正式 App 簽章與 selftest 通過。

- 主程式 SHA-256：`878fc8a2eff05cf05a087ee86659d80f46041af35bbff55333c05fdb674d002d`。
- NativeHiDPIHelper SHA-256：`3c2bf1027d5aa8bc17126b7583237f19349dd59a42161791c1ef0cf13d6aa3f9`。
- 啟動後既有確認 profile 自動恢復原生 2560×1440、2×、75Hz。
- 透過實際設定頁關閉再開啟 HiDPI，直接找到既有模式；未出現準備按鈕或管理員授權。完成就緒檢查、切換、15 秒安全確認並保留。
- 展開解析度／更新率，選擇 1920×1080 與 60Hz，再用同一 HiDPI 開關啟用；CoreGraphics 讀回 logical 1920×1080、pixels 3840×2160、60Hz、mirror=0、inMirrorSet=0，畫面可讀並保留確認。
- 再透過相同 UI 恢復 2560×1440、75Hz，讀回 logical 2560×1440、pixels 5120×2880、75Hz、mirror=0、inMirrorSet=0；有效 ICC 與 ColorSync 的 3364 bytes 相同。
- 最終 profile 為 nativeOnly=true、2560×1440@75；待啟用要求為空，恢復 journal confirmed=true、hostPIDs=[]。正式 App 僅主程序及 DisplayRecoveryHelper，未執行 VirtualDisplayHost。

以上確認目前 PA328QV 的兩組原生尺寸／時序與開關流程。4K、高更新率、超寬及直向等組合僅有邏輯測試，其他實體硬體、第一次缺模式的授權／重接流程與長時間卡頓改善仍待對應驗收；本次既有模式路徑沒有重新更動系統覆寫。
