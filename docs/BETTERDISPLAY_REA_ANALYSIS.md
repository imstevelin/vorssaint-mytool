# 已安裝 BetterDisplay 的 REA 分析

日期：2026-10-17（Asia/Taipei）。目標是本機 `/Applications/BetterDisplay.app`，並非 GitHub 舊版 BetterDummy。

## 安裝與使用

- REA：6.5.0，安裝於 `/Users/imstevelin/.local/share/rea/node_modules/rea-agents`。
- 可直接執行的入口：`/Users/imstevelin/.local/bin/rea`，wrapper 會選取本次安裝的 Ghidra／JDK。
- 原生分析引擎：Ghidra 12.1.4、OpenJDK 21.0.12.1。Homebrew 安裝時也更新了其所需的 pcre2、glib、harfbuzz、libpng、xorgproto、cairo、xz、little-cms2。
- 已實際使用 REA CLI、獨立 stdio MCP 連線與 Ghidra；沒有修改 Codex 的全域 MCP 設定，也沒有以註冊成功代替分析成功。
- 完整 JSON 證據與派生分析保存在 `/Users/imstevelin/.local/share/rea/analyses/betterdisplay-5.0.5/`。它們不加入專案 Git。

安裝方式依據：[REA 官方倉庫](https://github.com/morluto/rea)、[CLI 說明](https://github.com/morluto/rea/blob/main/docs/cli.md)。

## 目標身分與分析邊界

REA `inspect-plist` 確認版本 **5.0.5／53495**，Bundle ID 為 `pro.betterdisplay.BetterDisplay`，最低系統版本 26.3。主程式是 x86_64／arm64 universal Mach-O。

主程式完整檔案 SHA-256：`c866e4afe1b71c41ca5f8208efe85b63ddb9e541b5d1ec73a28c6fc020af9888`。

Ghidra provider 不接受這個 universal Mach-O，故以 `lipo -thin arm64` 建立分析副本，原本 App 完全未改。副本 SHA-256：`ca4739da936800242e6cf9c99793548e6670c9614f476b4f7404e9dce5112a12`。helper 同樣以 arm64 副本分析。

REA `inspect-signature` 觀察到 Developer ID 簽署與 hardened runtime，沒有 `get-task-allow` entitlement。本次未重新簽署、注入或繞過該限制；因此沒有 LLDB 實際函式執行追蹤。簽章 metadata 讀取也不等同完整信任驗證。

Ghidra 已成功反編譯較小的特權 helper。主程式的全量 auto-analysis 則遇到 Objective-C type metadata 遞迴錯誤與耗時的 Decompiler Switch Analysis；調整為停用這兩項 analyzer 後，仍出現 constant propagation 的 `out of address spaces` 診斷。本輪終止主程式全量分析並保留 `main-first-analysis.log`／`main-adjusted-analysis.log`，未取得成功的主程式 Ghidra 函式搜尋或呼叫圖。本文主程式結論僅使用已成功的 REA Mach-O 觀察、系統 metadata／字串與 CLI 證據，不把未完成的分析視為成功。分析連線與所屬 Ghidra 程序已關閉。

## 你的螢幕目前確實在使用 HiDPI

以唯讀 CoreGraphics／AppKit 程式取得目前線上螢幕：

| 項目 | 實際讀值 |
| --- | --- |
| 螢幕 | PA328QV |
| 邏輯桌面 | 2560×1440 |
| 渲染像素 | 5120×2880 |
| 更新率 | 75 Hz |
| 鏡像集合 | 否 |
| 系統提供模式 | 124，其中 58 個符合 backing 大於 logical 的 HiDPI 判定 |

BetterDisplay 自身保存的這個型號資料將 native size 記為 2560×1440，並標示 `hasHiDPI=true`、`overrideCapable=true`、`virtualScreenLinked=false`。設定檔為當時磁碟快照，可能落後於記憶體；因此主要結論另用 CoreGraphics 與實際 CLI 查詢交叉確認。

REA `capture-process` 實際執行的命令均為 `get`：

| 查詢 | 回傳 | exit |
| --- | --- | --- |
| `get --resolution --hiDPI` | `on,2560x1440` | 0 |
| `get --name=PA328QV --configuredControllerList` | DDCController、AmbientLightController、ColorController、CompositorFilterController、CombinedController | 0 |
| `get --name=PA328QV --volume` | `0.0` | 0 |

這些結果證明 App 對目前螢幕回報 HiDPI、存在 DDC controller 配置與可讀取的音量值。音量值可能來自 App 狀態，不能據此宣稱已測試硬體音量讀回或喇叭聲音。

目前 `/Library/Displays/Contents/Resources/Overrides` 下沒有找到 `DisplayVendorID-*/DisplayProductID-*` 的一般檔案。因此，**不能把目前 HiDPI 模式的起因直接歸因於這次找到的檔案 override 機制**，也不能由目錄空白推斷模式沒有受過其他設定影響。沒有啟停 BetterDisplay、切換模式或重新初始化螢幕來做因果實驗。

## HiDPI 至少有兩條不同實作路徑

### 1. 實體螢幕的 system override

這次最重要的新證據來自已安裝的 `BetterDisplayHelper`，不再只是官方文件或主程式字串。

REA＋Ghidra 反編譯建立了下列靜態鏈路：

`applyDisplayOverrides:authorization:withReply:` → callback → JSON request 解碼 → 逐項驗證與寫入指定型號的 plist。

| arm64 helper 位址 | 已恢復的職責 |
| --- | --- |
| `0x100005664` | Objective-C applyDisplayOverrides 入口，供應 callback |
| `0x100004ea8` | 解碼 JSON request，轉交處理 |
| `0x100005048` | 每一項 override 的 ID／路徑／寫入或刪除 |
| `0x100007904` | plist 型別、vendor/product 配對與 key 白名單驗證 |

驗證與寫入行為：

- 接收 32-byte administrator authorization external form，並以 Authorization Services 取得修改系統顯示設定的權限。
- vendor/product 限定 UInt32，據此建立 `DisplayVendorID-…/DisplayProductID-…` 的限定路徑。
- payload 必須能解為 plist dictionary，其中 `DisplayVendorID`／`DisplayProductID` 必須與 request 相符。
- 白名單共九項：`DisplayPixelDimensions`、`DisplayProductID`、`DisplayVendorID`、`DisplayProductName`、`IODisplayEDID`、`DisplayIsTV`、`default-resolution`、`scale-resolutions`、`target-default-ppmm`。
- 建立中間資料夾，使用 atomic Data write，設定 owner/group 0 與權限 0644。
- 沒有 payload 時走指定檔案刪除路徑。未在這條鏈路看到多項變更的 transactional rollback；不能把單檔 atomic write 視為整批變更可自動回復。

這證實現行 App **具備安裝顯示器模式 override 的原生機制**。主程式另有 `CGSGetNumberOfDisplayModes`、`CGSGetDisplayModeDescriptionOfLength`、`CGSConfigureDisplayMode` 等匯入，用於模式相關能力。

仍未完成的部分是主程式如何產生 `scale-resolutions` 每個 entry 的完整位元組格式、HiDPI flags、範圍與 GPU 限制，以及如何 activation／reinitialize。helper 是驗證／安裝端，不能由它的 plist 白名單直接還原模式產生演算法。

詳細反編譯紀錄：[helper 報告](/Users/imstevelin/.local/share/rea/analyses/betterdisplay-5.0.5/helper/REPORT.md)。

### 2. 虛擬 HiDPI 桌面與鏡像／串流

REA 的 arm64 Mach-O 匯入清單包含 `CGVirtualDisplay`、`CGVirtualDisplayDescriptor`、`CGVirtualDisplayMode`、`CGVirtualDisplaySettings`。這與舊開源 BetterDummy 使用的 API 家族一致，支持現行 App 也包含虛擬顯示器功能。

匯入存在不等於本機目前正在建立或使用虛擬顯示器。這次線上螢幕觀察沒有鏡像，且 BetterDisplay 回報未關聯 virtual screen；因此不能把目前 PA328QV 的畫面描述成 BetterDummy 鏡像方案。

## DDC 與音量控制

實際二進位匯入顯示兩個架構的 transport 不同：

| 平台 | 已觀察到的 IOKit 匯入 |
| --- | --- |
| Apple Silicon | `IOAVServiceCreateWithService`、`IOAVServiceReadI2C`、`IOAVServiceWriteI2C` |
| Intel | `IOFBGetI2CInterfaceCount`、`IOFBCopyI2CInterfaceForBus`、`IOI2CInterfaceOpen`、`IOI2CSendRequest`、`IOI2CInterfaceClose` |

Objective-C metadata 包含 `BetterDisplay.DDCController`，及 `ddcSetQueue`、`arm64IOAVService` 成員。封裝字串包含 DDC capabilities／VCP 解析、讀寫間隔、重試、checksum 處理、喚醒重套用，以及 mute/unmute/volume 的寫入順序設定。

另有 CoreAudio volume／boolean property 寫入與 listener 匯入，UI 說明也描述「將螢幕關聯到可原生控制音量的音訊裝置」。因此音量後端不只有 DDC：需要依裝置選擇 DDC、原生音訊或其他控制器，並避免兩者同時控制。

本次沒有還原完整 DDC 封包 encoder、音量 VCP 數值常數、預設 timing，亦沒有寫入音量／亮度做實體驗證。字串與匯入證據不可當成實際 I²C 封包追蹤。

詳細證據：[DDC 報告](/Users/imstevelin/.local/share/rea/analyses/betterdisplay-5.0.5/ddc/REPORT.md)。

## 對「實用小工具」的影響

1. **原生新增低解析度 HiDPI 的可行性比前一輪更明確。** 現在有目前安裝版 helper 的實際驗證／安裝流程可供理解；下一個技術缺口是主程式的模式資料產生與套用後的 activation，而非是否存在 override 路徑。
2. **BetterDummy 虛擬螢幕仍是可獨立開發的替代路徑。** MIT 原始碼可作為實作起點，但應避免將其與原生 override 畫上等號。
3. **DDC 音量可沿用本專案現有 IOAVService 基礎。** 先抽出與亮度共用的序列 transport，再增加音量能力探測、螢幕與 CoreAudio device 配對及 OSD。
4. **Override helper 必須限縮到 App 自己管理的檔案。** 保留原設定、測試回復，不能將其他程式或使用者的 override 一併移除。模式／鏡像變動也需協調既有視窗布局記憶服務。

此次沒有修改 BetterDisplay、本專案 App 功能或顯示器設定。安裝的是分析工具與依賴；實際目標執行僅為三次唯讀 CLI 查詢。

## 證據索引

完整資料根目錄：`/Users/imstevelin/.local/share/rea/analyses/betterdisplay-5.0.5/`。

| 檔案 | REA Evidence ID |
| --- | --- |
| `macho.json` | `ev_3db4ecff5e90286c2c55c982328f681d8e3710d75ad8b91ee61ba66769610d43` |
| `plist.json` | `ev_9fd85990f3bd64334d7240e509eb099e7edc53a2a6f5a1aa51941c23707cb7a7` |
| `signature.json` | `ev_e9e99b9bb43f9630e2e7aa62d94d42a2b652e33e01e0f1b7da8f76b5c902ac1d` |
| `artifact.json` | `ev_4379dee988d1c0ee8b3501426cf741d98e398324495776f2bf6c1eb3332fc072` |
| `cli-get-capture.json` | `ev_4c7efe053b3f76a2586780d1f1f224ce0bb9de6281b784f63a87660f37d75763` |
| `cli-controllers-capture.json` | `ev_caf99a340a164c03d985d37db0349b723b129b9775b84b8f230a25ce8a3f431a` |
| `cli-volume-capture.json` | `ev_ba0461ab442ef9b8fa7afa4c0643fbc26e0921f5bf300248ea1d056503be151c` |
| `helper/override-change.json` | `ev_aed9f9c4db750a5b02ddfb5a54c33b90481cef9a6b16d70a1c6cbd203a5bf0b5` |
| `helper/override-validation.json` | `ev_dc0f9ad5fbc08c1d04118ba8a622033d26c5866772dfa98211351025bd44bbb2` |

CoreGraphics 實機資料在 `current-display-modes.json`／`display-modes.swift`；選取且不含授權／序號資料的 App 設定摘要在 `selected-display-settings.json`。這些是額外的本機證據，不冒稱 REA Evidence。
