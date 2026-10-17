# HiDPI 色彩路徑實機對照測試

日期：2026-10-18。顯示器：PA328QV。使用已修正 ICC 的正式 APP。

結論：本輪在 HiDPI 開啟、關閉、再開啟三個狀態之間，未檢出軟體色彩管理或 RGB Gamma 曲線差異。這不是面板校色或儀器色準認證。

## 測試方式

透過 APP 暫時關閉 HiDPI，讀取原生模式基準，再重新開啟並保留原本的 2560×1440 HiDPI、75Hz。亮度、對比、音量和螢幕色彩設定均未由測試調整。

每個狀態均獨立讀取有效 ColorSync ICC、CoreGraphics 色彩空間 ICC，以及 `CGGetDisplayTransferByTable` 回傳的顯示器 RGB 曲線。以標準 sRGB 為輸入，將 9×9×9 共 729 個 RGB 色票（包含中性色、原色、補色與中間飽和度）按相對色度意圖轉換至當下顯示色彩空間。比較的是軟體輸出的 RGB 數值，不是面板反射／發光量測。

## 結果

| 項目 | HiDPI 關閉與開啟對照 |
|---|---|
| ICC 格式驗證 | 通過，沒有回報錯誤或警告 |
| ICC 與有效色彩空間 | 完全一致，SHA256 相同 |
| 色票數量 | 每個顯示目的地 729 個 |
| 色票轉換失敗 | 0 |
| RGB 轉換最大通道差異 | 0（正規化數值） |
| RGB Gamma 讀取 | 成功，每通道 1,024 點 |
| RGB Gamma 最大數值差異 | 0 |
| Gamma 單調性 | R/G/B 全部通過 |
| 重新開啟 HiDPI | 已保留 2560×1440、2×、75Hz |

所有讀值中的 ICC SHA256 均為 `cb942dfdd13b22cf9a2e17bb03358aea3fca7c9f14d1b0123dccdc3cc0d51e3a`，與修正前保存的原實體 PA328QV 描述檔相同。

## 原始紀錄與重現

- [HiDPI 初始讀值](verification/hidpi-color/hidpi-before.json)
- [原生模式讀值](verification/hidpi-color/native.json)
- [HiDPI 恢復後讀值](verification/hidpi-color/hidpi-after.json)
- 讀值工具：[VerifyDisplayColor.swift](../Tools/VerifyDisplayColor.swift)
- [帶 sRGB 標記的目視測試色票](verification/hidpi-color/srgb-visual-check.png)

編譯讀值工具並在所需模式執行，不會寫入螢幕或校色設定：

```sh
swiftc Tools/VerifyDisplayColor.swift -o /tmp/verify-display-color
/tmp/verify-display-color /tmp/display-color.json
```

## 限制與判讀

這輪可排除已測狀態下的 ICC 替換、軟體色票轉換變化及可讀回 Gamma 表變化，不能排除顯示訊號 RGB 範圍、驅動合成／鏡像輸出、螢幕內部處理或面板輸出的差異，也未量測局部閃爍。

測試色票可用於比較開關 HiDPI 後的目視變化：保持相同亮度與環境光，查看灰階是否變色、彩色區塊飽和度是否改變，以及漸層是否出現閃爍。近黑／近白相鄰色階的可見程度受環境、亮度與視力影響，不能據此單獨判定故障。

若要確認實體色準、白點、亮度、色域與 Delta E，需要可連接的校色器／分光儀，在 HiDPI 關閉與開啟時量測同一組色票。目前沒有取得該類儀器讀值，因此不宣稱面板色差為零，也沒有產生虛構的校色 ICC。
