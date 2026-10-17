# BetterDisplay／低解析度螢幕 HiDPI 整合研究

研究日期：2026-10-17。範圍：讓原本不提供 HiDPI 的 1920×1080、2560×1440 外接螢幕使用 HiDPI，以及 DDC 亮度／音量控制。這是原始碼與文件層面的可行性研究，尚未實作或驗證實體螢幕。

後續已有本機 BetterDisplay 5.0.5 的 REA／Ghidra 分析：見 [BETTERDISPLAY_REA_ANALYSIS.md](BETTERDISPLAY_REA_ANALYSIS.md)。其中確認了實際 helper 的原生 Override 安裝鏈路，以及目前 PA328QV 正在使用非鏡像 HiDPI；本文保留第一輪開源碼研究的範圍與結論。

## 結論

可以將相關能力整合到「實用小工具」。建議原生擴充既有 DDC 引擎，並以 MIT 授權 BetterDummy 原始碼為起點開發「虛擬螢幕 HiDPI」；原生顯示器 configuration override 則另立研究項目。呼叫已安裝的 BetterDisplay 可作為選配，並非獨立運作的必要條件。

| 需求 | 現況與判斷 | 建議 |
| --- | --- | --- |
| DDC 硬體亮度 | 本專案已有 IOAVService I²C 實作與 VCP 0x10 | 延伸現有服務 |
| DDC 螢幕音量 | 現有音量入口走 Core Audio，未找到 DDC 0x62 音量實作 | 抽出共用 DDC transport，增加音量與選配靜音 |
| 低解析度螢幕新增 HiDPI | 現有專案未找到虛擬螢幕或自訂模式產生功能 | BetterDummy 虛擬 HiDPI 桌面＋鏡像，先做相容性原型 |
| 原生連線直接新增 HiDPI | 現行 BetterDisplay 有 system override 流程，舊開源分支不包含其完整實作 | 另行研究，不能由舊程式碼推定已可移植 |
| BetterDisplay 跨 App 整合 | 官方有通知 request/response、CLI 與 OSD 通知 | 選配橋接；需 BetterDisplay 執行並符合功能授權 |

## 原始碼與 Release 核對

- 主倉庫預設 `landing` 分支目前只有 README。
- `opensource` 分支確實有 **BetterDummy OpenSource Edition** 的 Swift／Objective-C bridge 原始碼及 MIT LICENSE。核對到的 tip 為 `0aa8394a3c04762d41268fa9c35053ef24d1ef1e`，最後提交日期為 2022-02-24。
- 實際下載並檢查最新 Release `v5.1.1` 的 Source code ZIP：只有頂層資料夾與 README.md，壓縮檔 5,717 bytes。這個自動產生的 ZIP 是該 tag 的倉庫快照，並不包含現行 App 原始碼。此結論只針對已檢查的版本，未逐一檢查所有歷史 Release。
- 因此可採用的原始碼基礎是舊版 BetterDummy，而不是把現行 BetterDisplay App 全部合併進來。

依據：[opensource README](https://github.com/waydabber/BetterDisplay/blob/opensource/README.md)、[MIT LICENSE](https://github.com/waydabber/BetterDisplay/blob/opensource/LICENSE)、[v5.1.1 tag tree](https://github.com/waydabber/BetterDisplay/tree/v5.1.1)、[Release](https://github.com/waydabber/BetterDisplay/releases/tag/v5.1.1)。

## 1080p／1440p HiDPI 的實作路徑

本研究的目標是「新增原本沒有的 HiDPI 渲染模式」。只列出系統現有模式或切換 `hiDPI=on`，不能滿足這個目標。

### A. 虛擬 HiDPI 螢幕＋鏡像：有可研究與移植的程式碼

`BetterDummy/Model/Dummy.swift` 的 `createVirtualDisplay` 使用 `CGVirtualDisplayDescriptor` 建立描述，產生 `CGVirtualDisplayMode`，再設定 `CGVirtualDisplaySettings.hiDPI = 1` 與 `applySettings`。`Bridging-Header.h` 自行宣告這些未公開介面。

`DummyManager.swift` 提供虛擬螢幕建立／釋放、序號保存、與實體顯示器的關聯及連接管理。`Display.swift` 用 CGS 私有函式列出／選擇模式。上述原始碼可作為原型基礎，但不是 macOS 26／27 的相容性證明。

設計上的資料流是：

`App 的邏輯桌面 → 2× HiDPI backing → macOS 鏡像縮放 → 實體面板`

以下是希望達到的模式組合，並非本次已測得的結果：

| 實體面板 | 希望保留的邏輯桌面 | HiDPI backing | 輸出 |
| --- | --- | --- | --- |
| 1920×1080 | 1920×1080 | 3840×2160 | 縮放到 1920×1080 |
| 2560×1440 | 2560×1440 | 5120×2880 | 縮放到 2560×1440 |

需要以當前 SDK／OS 實測 mode 的 logical／pixel dimensions 與鏡像縮放結果，避免把「虛擬 mode 的輸入尺寸」直接等同最後的邏輯尺寸。HiDPI 改變渲染方式，面板的實際像素數仍然不變；文字觀感、延遲與效能都應實測。

舊開源分支有鏡像狀態辨識與睡眠 workaround；檢查相關檔案未找到完整的自動 `CGConfigureDisplayMirrorOfDisplay` 設定流程。因此一鍵啟用、鏡像方向、目標解析度、失敗復原與原先桌面配置保存，仍需我們實作；初期原型可先由 macOS 設定完成鏡像。

先限定單一虛擬來源與單一實體目標、SDR、60 Hz，再逐步測試高更新率、HDR、直向與多螢幕。鏡像本身與擷取串流是不同路徑；只有加入畫面擷取／串流時才應依該路徑處理螢幕錄製權限。

依據：[Dummy.swift](https://github.com/waydabber/BetterDisplay/blob/opensource/BetterDummy/Model/Dummy.swift)、[Bridging-Header.h](https://github.com/waydabber/BetterDisplay/blob/opensource/BetterDummy/Bridging-Header.h)、[DummyManager.swift](https://github.com/waydabber/BetterDisplay/blob/opensource/BetterDummy/Support/DummyManager.swift)、[Display.swift](https://github.com/waydabber/BetterDisplay/blob/opensource/BetterDummy/Model/Display.swift)。

### B. 原生 system configuration override：獨立研究

現行 BetterDisplay 可對支援的實體顯示器型號新增縮放設定，再經 helper／管理員授權 Apply 與 activation／重開機套用。設定可能影響相同 vendor/model 的所有螢幕；建立成功也不代表 macOS 接受或實體面板可用。

這是較貼近直接使用實體顯示器的方案，但從目前可取得的 BetterDummy 原始碼，無法得出現行 BetterDisplay 的完整 override 技術、套用格式或相容性處理。不能把 DDC 或簡單的 mode selection 當成這項能力。

依據：[System Configuration](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/system-configuration/)、[官方 HiDPI 流程](https://betterdisplay.pro/guide/tutorials/fully-scalable-hidpi-desktop/)。

## 對照目前專案的整合位置

本次讀取的是工作目錄實際內容；基底 HEAD 為 `f85fc69a`，分支 `codex/upstream-window-memory-fix`。工作目錄已有大量未提交修改，本次只新增研究文件。

- `Services/Display/BrightnessService.swift`：已有每螢幕 route、IORegistry 配對、序列 workQueue、寫入合併、睡眠喚醒後重建及 DDC 交易間隔。
- `Services/Display/BrightnessSupport.swift`：封包／回覆解析接受 VCP code，但目前使用以亮度為主。
- `UI/MenuPanel/BrightnessSection.swift`：已有逐螢幕操作介面，可延伸為亮度與音量控制。
- `Services/Audio/AppVolumeMixer.swift:2203`：現有系統音量 setter 只對可寫 Core Audio volume property 工作；HDMI／DP 裝置沒有這個 property 時，不能靠此入口直接控制螢幕硬體音量。
- `Services/Notch/NotchService.swift`：已有 `showVolume`，可提供顯示回饋；DDC 音量不會自動變成 Core Audio 音量變更通知，需要明確接入。
- `Services/WindowLayout/DisplayWindowMemoryService.swift:88`：會回應螢幕幾何／拓撲變化，虛擬螢幕建立與鏡像過程需避免中間狀態被記為正常配置。
- `Core/FeatureCatalog.swift`／`App/FeatureRuntime.swift`：適合登錄新的原生功能及啟停生命週期。

建議新元件（名稱為提案，尚不存在）：

1. `DisplayDDCTransport`：共用 serial queue、配對、節流、取消與 VCP read/write，亮度與音量不得各自另開 queue 互相交錯。
2. `DisplayHardwareAudioService`：VCP `0x62` 音量、選配 `0x8D` 靜音、每功能獨立 capability／讀取狀態、最大值正規化。亮度能讀取不代表音量也支援。讀取失敗但寫入被接受，也不應直接顯示「已驗證支援」。
3. `VirtualHiDPIService`：持有虛擬 display、穩定序號與目標 identity，管理鏡像、啟用確認與 rollback；退出時僅清除本 App 建立的資源。
4. `DisplayConfigurationCoordinator`：讓模式／鏡像變更完成後再恢復視窗布局記憶，失敗時回復原布局。
5. 選配 `BetterDisplayBridge`：與原生控制明確分工，避免同一螢幕由兩個引擎同時寫入。

DDC 音量實作可參考 MonitorControl 的 `Command.swift` 與 `OtherDisplay.swift`；兩者與 BetterDummy 均需保留各自 MIT 版權／授權聲明。現有專案使用 GPL-3.0-or-later；採用 MIT 部分時保留來源與授權文件。現行 BetterDisplay 二進位不在這些開源授權的移植範圍內。

依據：[MonitorControl 音量控制](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Model/OtherDisplay.swift)、[VCP codes](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Enums/Command.swift)、[MIT License](https://github.com/MonitorControl/MonitorControl/blob/main/License.txt)。研究時 MonitorControl main 為 `7cfe64500d19cbbcbf82121a91c826f658a403bd`。

## 選配 BetterDisplay 整合

官方 `DistributedNotificationCenter` 介面可直接從 Swift 使用，不必安裝 Homebrew 或額外 CLI。通知 JSON 放在 `object`，先註冊 response，再以 UUID 配對 request，並處理 timeout、App 結束與功能不可用。OSD 通知也能接到本專案的動態島。

可讀取顯示器 identifiers／displayModeList、控制 DDC volume，並選擇已有的 HiDPI mode。官方 `hiDPI` 參數只在該解析度已有 HiDPI／LoDPI alternatives 時工作，不能將它當成替 1080p／1440p 自動建立新模式的指令。

BetterDisplay 需要安裝並保持執行；CLI 目前列為 Free，但 flexible scaling 等功能仍依 Pro 授權與裝置條件決定。舊 Wiki／舊 README 的授權描述可能不同，應以當前功能表及 terms 為準。

依據：[第三方整合](https://betterdisplay.pro/guide/integration/third-party-apps/)、[CLI reference](https://betterdisplay.pro/guide/integration/cli-reference/)、[功能與授權](https://betterdisplay.pro/guide/licensing/free-and-pro-features/)、[MIT CLI](https://github.com/waydabber/betterdisplaycli)。

## 建議實作與驗收順序

1. **優先驗證低解析度 HiDPI 核心**：原型建立虛擬來源，分別在真實 1080p／1440p 目標確認 2× backing 與鏡像輸出；先驗證畫面與文字品質，再包 UI。
2. **DDC 音量**：重構共用 transport，先滑桿與手動選擇目標，再加入媒體鍵。預設跟隨音訊輸出，配對不明確時讓使用者指定，避免調到其他螢幕。
3. **完整原生介面**：每螢幕的 HiDPI 開關、桌面大小、亮度／音量及能力狀態；進階設定才顯示 virtual display 詳細資料。
4. **後續研究**：直接對實體顯示器的 configuration override，以及需要時的 BetterDisplay 橋接。

必要實機驗收包括：真實 1080p／1440p 非 HiDPI 模式與新模式比較、USB-C／DP／HDMI 與擴充塢、休眠喚醒、拔插、App 退出／異常終止、原有多螢幕布局與視窗記憶、相同型號雙螢幕及失敗回復。不要承諾所有 HDMI／DisplayLink 路徑均支援 DDC；MonitorControl 自身就列有連線例外。

本次未建立虛擬顯示器、修改解析度、寫入 DDC 或變動系統 override，亦未執行 App 建置／功能測試。可行性結論來自當前專案、上游程式碼與官方文件；實際支援程度仍須原型與硬體驗證。
