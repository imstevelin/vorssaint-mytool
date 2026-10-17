# HiDPI 色彩與切換穩定性（2026-10-18）

## 問題與證據

舊虛擬螢幕 descriptor 使用固定 sRGB 原色與 D65 白點，沒有套用實體顯示器的有效 ICC。實機 PA328QV 的 ColorSync 與 CoreGraphics 色彩空間均回報 PA328QV ICC；虛擬來源則回報不同的「實用小工具 HiDPI」ICC。兩者 RGB XYZ 原色 tag 不同，不能視為同一色彩管理目的地。

- 原實體 ICC：3364 bytes，SHA256 `cb942dfdd13b22cf9a2e17bb03358aea3fca7c9f14d1b0123dccdc3cc0d51e3a`。
- 舊虛擬 ICC：3372 bytes，SHA256 `a353d1da1a8acad249de85f4cbb2ed8cd121e12f0ad6216ab41d3a7ff1a6a6ae`。
- 修正後：實體與虛擬顯示器的 ColorSync ICC、CoreGraphics 有效色彩空間 ICC 共四份資料，全部與原實體 ICC 逐 byte 相同。

## 修正

啟用前讀取實體顯示器的有效 ICC（包含使用者選擇的描述檔），傳給獨立虛擬螢幕 host。host 使用 [ColorSyncDeviceSetCustomProfiles](https://developer.apple.com/documentation/colorsync/colorsyncdevicesetcustomprofiles(_:_:_:)) 僅設定自己建立的虛擬顯示器；原實體顯示器的 ICC 不更動。ColorSync 註冊是非同步的，host 等待 ColorSync 與 CoreGraphics 均讀回相同 ICC 才發布虛擬 display ID，讓主程式開始鏡像。

HiDPI 完成條件現在同時包含所選 2× 模式、刷新率、鏡像關係與兩端的有效 ICC。每 0.1 秒檢查，連續四次成立才完成，之後才恢復視窗。失敗會還原原模式，不使用 sRGB 當作無法讀取 ICC 的替代品。host 正常退出、父程序消失或收到 SIGTERM 時，清除自己虛擬顯示器的 ICC 覆寫並刪除暫存 ICC。

原本單次模式讀回成功就立即確認並恢復視窗，沒有等待色彩註冊與鏡像狀態穩定。連續檢查針對此切換競態提供防護；不能僅憑此靜態原因分析宣稱所有局部閃爍皆已消除。

## 驗證邊界

產品方法測試涵蓋 ColorSync/WindowServer 描述檔不同步、讀取失敗、ICC bytes 跨程序傳遞，以及連續穩定檢查遇到失敗歸零。實機讀回結果存於 `/tmp/mytool-display-color-verification/active-profiles.txt`。

ICC 完全一致證明軟體色彩管理目的地一致；它不是校色器量測的色差報告。尚未量測實體面板輸出的 Delta E，也未以高速錄影量測局部閃爍。

最終版已安裝並重新啟動，嚴格深層簽章驗證通過；`display-restoration` 206 項、`window-layout` 500 項，共 706 項測試通過。最終讀回紀錄為 `/tmp/mytool-display-color-verification/final-profiles.txt`，四份 ICC 仍與原實體描述檔相同；`final-modes.json` 回報 2560×1440 HiDPI、5120×2880 繪製解析度、75Hz。使用者可視飽和度與閃爍的回饋仍待確認，不能用 ICC hash 或單張截圖代替面板觀察。
