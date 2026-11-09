# 新視窗自然排列與事件還原延遲

日期：2026-11-09。

## 問題與修正

- 原本每個新視窗都套用 App／標題記錄的完整座標，導致同一 App 在同一顯示器的新視窗蓋住既有視窗。現在額外視窗保留 macOS／App 提供的開啟位置，只套用記憶尺寸並限制在工作區；記憶為最大化時保留額外視窗的自然幾何，避免蓋住既有視窗。這種保留不重新發布成新的使用者偏好。
- 單一視窗重新開啟仍可還原位置、大小及視窗化最大狀態；既有視窗在顯示器或解析度轉換時仍還原位置。受管理 HiDPI 轉換保留視窗身分，由 generation 判定轉換，避免被當成額外新視窗。
- AX 通知在下一個主佇列回合合併處理，不再固定等 50ms；僅查詢事件所屬 App。查詢中的事件保存為待辦，完成後接續處理。部分查詢不清除其他 App 的 AX 快取或事件訂閱，也不發布不完整的顯示器配置。
- App 啟動／啟用通知補上新 App 的事件路徑。滑鼠按下／放開以不攔截輸入的 monitor 觀察 WindowServer 幾何，短拖拉亦保留手動優先；放開後立即接續待辦，不再加固定 250ms 靜默期。
- 未縮短既有半秒保底掃描，未新增快速輪詢；幾何穩定學習的 1.5 秒、顯示器轉換就緒及安全捕捉門檻保留。

## 驗證

- 視窗專項：`./build.sh --test-suite=window-layout`，571 checks 通過。
- 完整回歸：`./build.sh --test`，113,484 checks 通過；resource-usage 43、window-layout 571。
- Audio feedback bridge 14 checks、Preference cleanup、Uninstall spaces、Developer install isolation 均通過。
- `./build.sh`、`./build/VorssaintImstevelin --selftest`：通過。
- `codesign --verify --deep --strict 'build/stage/實用小工具.app'`、Info.plist lint：通過；Apple Development 簽署，不代表 Developer ID 公證。
- `git diff --check`：通過。
- Fork CI：隨本修正 PR 執行，結果於整合時確認。

## 尚未驗證與限制

- 尚未在使用者的 Finder／瀏覽器實際開窗、短拖拉及外接顯示器重接驗收，不能將自動測試當作視覺流暢度驗收。
- 事件可用時消除本服務的人為等待；不支援 AX 通知的 App 仍依保底掃描。已在進行的 AX 查詢及 App 自身反應仍可能耗時，不保證所有 App 零延遲。
- 多視窗保留自然開啟位置，並不重新排列或解開 App 自己已重疊的視窗。
- 未變更正式版本、未替換正式 App、未發佈 Release。
