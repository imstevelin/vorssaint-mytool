# 原生 HiDPI 縮放候選（2026-10-24）

## 目的與實機基線

使用者要求改試 BetterDisplay 的 Flexible Scaling／Native Smooth Scaling 路徑，避開虛擬顯示鏡像。這是替代架構的候選，不代表已證明先前卡頓的根因。

本輪先備份偏好，再暫時退出正式 App，讓自己的虛擬來源結束。PA328QV（vendor `0x6b3`、product `0x32c2`）在無鏡像時為 2560×1440、1×、75Hz。此時未提供 2560×1440、2×、75Hz；鏡像期間列出的相同模式不能當成實體原生支援的證據。讀取後重新開啟原 App。

## 研究來源與限制

- [BetterDisplay 系統設定與彈性縮放](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/system-configuration/)：以顯示器型號為範圍準備系統覆寫，Apply 安裝後仍需啟用；自訂模式可能被 macOS 拒絕，不能以產生檔案等同模式可用。
- 本機使用者提供的 BetterDisplay 5.1.1 DMG，以唯讀方式掛載。REA 6.5.0 搭配 Ghidra 12.1.4；原 universal binary 不受此 provider 支援，另抽 arm64 分析副本。
- 完整主程式初次分析超時，沒有把未取得的反編譯推論寫成事實。主程式 strings 觀察到 `scale-resolutions`、`DisplayPixelDimensions`、`default-resolution` 與 `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-`。
- REA 成功分析小型 BetterDisplayHelper：dispatch metadata 將 `applyDisplayOverrides:authorization:withReply:` 對應至 `0x100005e28`，反編譯顯示它進入 `FUN_100006370`。helper 亦包含系統顯示覆寫目錄、顯示識別／覆寫驗證錯誤與 `DisplayResolutionEnabled` 字串。這些是研究線索，不宣稱已重建完整商業實作。
- 商業二進位、完整 REA 證據與反編譯輸出留在工作用研究目錄，未複製進 repo／App。

## 實作邊界

- 原生選項只嘗試實體顯示模式，持久化 `nativeOnly`；模式不可用時回報，不啟動 VirtualDisplayHost。既有 nil 策略的已儲存 profiles 保持相容，不自動替使用者轉換。
- 原生啟用與驗證都要求離開 mirror set，繼續使用既有恢復 watchdog、確認倒數、ICC 與更新率檢查。
- 原生縮放準備器僅追加指定 HiDPI 的 network-order resolution records。保留既有 EDID、色彩資訊、原生尺寸與其他覆寫；不偽造較大面板、不改實體 EDID、不停用 SIP。
- root helper 只接受數字型號／尺寸，目的地固定為該型號 Overrides 路徑。保存原檔（包含原本不存在），檢查 root ownership、權限與 symlink，序列化交易；外部工具變更時拒絕強制覆蓋。
- 還原可處理已知的原始／前次／本次寫入狀態，保留更新中斷時的回復可能。UI 說明相同 vendor/product 型號共用、需系統授權及重接／重新啟動。
- 系統設定準備、macOS 接受模式、實際無鏡像啟用、長時間游標／捲動改善是不同驗證層級。

## 驗證狀態

- 初次 display-restoration：303 checks 通過。
- 最終完整測試 **113419 checks** 通過，另含 AudioFeedbackBridge 14 checks、偏好清理、移除 Spaces 與 Developer 安裝隔離。涵蓋原生策略持久化、legacy 相容、明確鏡像選擇不被 native-first 覆蓋、mirror set 拒絕與 root receipt 已知狀態／第三方衝突政策。
- 最終 Release 建置、selftest、strict deep codesign、Info.plist lint、NativeHiDPIHelper arm64／簽章檢查通過；CI 尚在執行。
- 實體新模式啟用、重接、睡醒與卡頓長時間驗收尚未完成。

## 本機系統覆寫準備

- 已透過 macOS 管理員授權安裝 `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-6b3/DisplayProductID-32c2`，owner root、mode 0644。僅含實際 vendor/product 與所選縮放資料，沒有改寫 EDID、ICC 或原生面板尺寸。
- 此次新增 record 為 `0000140000000b400000000900a00000`（5120×2880 backing 尺寸）。檔案 SHA-256 `2d532e12e9cd75525d638a3ce11ce4754873e5aeb33c6a1c6a2fd74bd73ba49f`，與 root receipt 中的 installed bytes 完全一致。
- 原先此型號沒有覆寫檔，receipt 保存這個不存在狀態；還原將只移除自己的檔案。receipt 位於 `/Library/Application Support/com.imstevelin.vorssaint-imstevelin/NativeHiDPI/1715-12994.json`。
- 此處只證明準備成功，尚未證明重接後 macOS 接受此 record，亦未證明原生 2560×1440、2×、75Hz 與長時間游標改善。

## 候選 App 安裝與目前狀態

- 程式提交 `6c8c6a04`，沿用本次修復已授權的備份／正式 App 替換流程；版本仍為候選 1.1.1 (12)，沒有建立 Release 或 tag。
- 舊 App、退出前／後偏好及自有 Application Support 保存於使用者 Backups／`20261024-035943-before-native-hidpi-6c8c6a04`。只移除 PA328QV 先前已確認的虛擬鏡像自動恢復 profile，避免混淆原生測試；其他偏好與退出後備份逐項完全相同，原 profile 另存。
- 新 App 安裝後 selftest／strict deep codesign 通過。主程式 SHA-256 `e3b19e602ba19f370e266ec476603f38c9d745368639841780df1f1fbb1befa1`；NativeHiDPIHelper `25218408faf112730bd4c397741bfeef8b9a3b6d72d98ba4e9d7cbf99eb4bf74`，皆與 stage 一致。
- 已在實際設定頁確認「原生縮放」選中、HiDPI 尚未啟用、準備／還原按鈕存在。此時 CoreGraphics 只有實體顯示器、mirror source 為 0、沒有 VirtualDisplayHost，仍為 2560×1440、1×、75Hz。
- 已請使用者重新拔插訊號線以啟用覆寫；尚未收到完成結果。不得把目前 1× 狀態或設定頁存在描述為原生 HiDPI 已成功。
