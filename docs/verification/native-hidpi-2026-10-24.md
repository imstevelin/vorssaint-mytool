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
- 最終 Release 建置、selftest、strict deep codesign、Info.plist lint、NativeHiDPIHelper arm64／簽章檢查通過；提交 `201650f8` 的 Fork CI（40016198575）成功。此結果只涵蓋初版。
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
- 使用者實際重新插拔後仍無法啟用。重新枚舉確認仍無 2560×1440、2×、75Hz，不能把目前 1× 狀態或設定頁存在描述為原生 HiDPI 已成功。


## 重新插拔失敗後的修正

- 確認初版只產生一筆 `[2w, 2h, 9, 0x00a00000]`，且系統 `DisplayResolutionEnabled` 不存在。這是實作缺口；尚不能判定哪個缺口是本機拒絕載入的充分原因。
- 為避免完整商業 binary 分析超時，從已抽出的 arm64 主程式（SHA-256 `0da744d33ba99f98949c810de6e8d974d68739b30420f488c516b93b69ae428d`）依 Mach-O function starts 抽取 `0x10006eb28..<0x100072e34`，使用 REA raw-binary／arm64／Ghidra 局部反編譯。此片段的彈性縮放與自訂尺寸迴圈都建立三筆配套記錄：`[2w, 2h, 9, 0x00200000]`、`[2w, 2h]`、`[w, h]`。外部呼叫與片段外資料仍有未解析限制，不聲稱重建整套產品。
- 新產生器採用此三筆 network-order 記錄。更新已受本工具管理的設定時，從 receipt 保存的原始覆寫重新建立，淘汰初版錯誤記錄；保留原始第三方資料與衝突保護。
- root helper 以 CFPreferences 僅設定系統 `com.apple.windowserver` 的 `DisplayResolutionEnabled` 為 true。`resolution-preference.json` 保存原先 true／false／不存在狀態；最後一個本工具管理的型號還原時，才還原此共用開關。偵測到不屬於已知狀態的變更時拒絕覆蓋，不修改整份系統偏好檔。
- 修正版 display-restoration 313 checks、Release 建置、selftest 與 strict deep codesign 通過；完整回歸、系統套用與模式啟用結果另記於下方。模式仍缺少時，錯誤訊息會說明重新啟動 macOS 的下一個驗證步驟，維持不自動退回虛擬鏡像。


### 修正版交付驗證

- 完整本機回歸 **113424 checks**，AudioFeedbackBridge 14 checks、偏好清理、移除 Spaces、Developer 安裝隔離皆通過。
- 已備份後替換 `/Applications/實用小工具.app` 並啟動。備份為 `20261024-043902-before-native-record-correction`；替換前後偏好完全一致，安裝包 selftest 與 strict deep codesign 通過。
- 安裝主程式 SHA-256 `f56d44c9ef18e47c69a948f48082cf2b47b8f8ff7c7c79304946d701417b918f`，NativeHiDPIHelper `f252632e8686e3b2cd71320b4f3dacf882568e7d98873e94ef8f129de8b21e51`，均與測試後 stage 相同。沿用候選版本 1.1.1 (12)，未建立 Release。
- 系統修正的管理員授權與原生模式啟用尚待驗證；App 已安裝不代表系統覆寫已更新。實機卡頓改善仍待原生 HiDPI 成功啟用後長時間驗收。


### 修正版系統授權已完成

- 管理員授權成功，root helper exit 0。覆寫已更新為三筆 `0000140000000b400000000900200000`、`0000140000000b40`、`00000a00000005a0`；SHA-256 `74b0a4f8fdb544872099fba353fd83b4c178921bc03e451821d16071eeee9e38`，root／0644，與 receipt installed bytes 完全一致。
- 系統 `DisplayResolutionEnabled` 已讀回 true。型號 receipt 與共用開關 receipt 均保存原先不存在的狀態，可經還原功能回復。
- 套用後再次枚舉：仍只有實體螢幕、無鏡像，當前 2560×1440、1×、75Hz；尚未提供所需的 2560×1440、2×、75Hz。下一個實機步驟是儲存工作後重新啟動 macOS，驗證重新載入設定後的模式；沒有自動重啟或結束 WindowServer。
- 程式提交 `723aa032` 的 Fork CI（40020938965）仍在執行；系統設定寫入成功不代表模式已被接受或卡頓已修復。


## 重新啟動後：面板原生尺寸偵測差異

- 使用者完成重新啟動後，系統開關仍為 true，正式 App 從預期路徑執行，沒有 VirtualDisplayHost。目標 2560×1440、2×、75Hz 仍未提供，維持實體 2560×1440、1×、75Hz。
- CoreDisplay_DisplayCreateInfoDictionary 已包含修正後三筆 scale-resolutions，證明覆寫已載入；不能再把缺少模式直接歸因於尚未重載。
- AppleCLCD2 的 DisplayAttributes 回報 NativeFormatHorizontalPixels=1920、NativeFormatVerticalPixels=1080，而 [ASUS PA328QV 官方規格](https://www.asus.com/us/displays-desktops/monitors/proart/proart-display-pa328qv/techspec/) 為 2560×1440。[BetterDisplay 原生縮放指南](https://github.com/waydabber/BetterDisplay/wiki/Fully-scalable-HiDPI-desktop) 要求正確偵測面板原生尺寸，且在錯誤時提供獨立校正。這是已確認的偵測差異，是否造成此次模式上限仍待實機驗證。
- REA 主程式局部分析中 DisplayPixelDimensions 分支以兩個 32-bit network-order 數值產生資料，與縮放模式產生器分開。新增明確選用的面板尺寸輸入，僅填實體廠商規格 2560×1440，不使用 5120×2880 backing 尺寸冒充面板、不改 EDID／ICC。
- helper 保留原始覆寫作還原基線，receipt 可選 nativePanelSize 保存此獨立選擇；舊 receipt 預設 nil，重新準備不會遺失已明確選用的校正，還原仍回復原始檔案。
- display-restoration 319 checks 通過，包含未選校正時保留原尺寸、明確校正使用實體尺寸、EDID／縮放紀錄不變、校正 receipt／回復基線與無效尺寸拒絕。完整建置、回歸與實機套用另行記錄。


### 面板校正版本交付

- 完整本機測試 **113430 checks**、AudioFeedbackBridge 14 checks、偏好清理／移除 Spaces／Developer 安裝隔離通過。Release 建置、selftest、strict deep codesign 通過。
- 已備份後安裝至正式位置並啟動；備份 `20261024-045910-before-native-panel-correction`，替換前後偏好完全相同。主程式 SHA-256 `e92bdd8c85244ca081efc7316b6956bfb78d99d58aff01ad9bdf0e08e109b028`，helper `253540154a0fb4648c700a1c010843965ab59dbed2f2f53e976bc96298c9c360`，與 stage 一致。
- 面板尺寸校正的系統管理員授權仍在等待；目前不能宣稱新的 DisplayPixelDimensions 已寫入或原生 HiDPI 已啟用。保留未鏡像的 1×、75Hz 現狀。新提交的 Fork CI、模式啟用與長時間卡頓驗收仍待確認。
