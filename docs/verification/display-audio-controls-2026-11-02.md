# 螢幕音訊選單與媒體鍵修正（2026-11-02）

## 已定位的問題

- MixerSection 的滑桿顯示條件、綁定讀值與圖示只讀取 AppVolumeMixer.systemOutputVolume／Muted。DisplayPort／HDMI 輸出未提供 Core Audio 音量時，雖然 SystemOutputControl 已支援 DDC，選單仍隱藏滑桿。
- routeHardwareVolume 在 DDC 寫入或讀回確認失敗時重送系統媒體鍵。這條路由原本就以「沒有原生音量控制」為前提，重送無法修復 DDC，會顯示系統浮窗；非同步返回時也可能碰到另一個預設輸出。
- 切換輸出成功後，新 UID 已發布，前一台裝置的音量能力卻會留到下一次 HAL snapshot，造成 DDC 路由短暫被錯誤的原生音量能力擋住。
- 已接管的原生／DDC 按鍵在排進主佇列後未重新核對輸出 UID，切換裝置後可能調到新輸出。

## 修正契約

選單觀察並讀寫 SystemOutputControl，與島共用原生優先、DDC 備援、靜音與讀回更新。原生能力不存在但有唯一有效 DDC 螢幕路由時仍顯示滑桿；沒有可用控制能力時不假造音量。

輸出切換成功後，在交還事件迴圈前退役舊音量控制與待處理操作、清除舊能力並同步媒體鍵接管。失敗的輸出切換不修改現有路由。

DDC 接管的按鍵失敗留在 App：保留硬體重試、讀回、確認值回退與錯誤狀態，停止重新送出原生媒體鍵。原生輸出仍可在相同 UID 上使用原生 fallback；舊輸出的非同步失敗不得重送到新輸出。主佇列操作執行前重新核對 UID，DDC 也核對 display ID。Option 系統設定捷徑、未支援的輸出及多螢幕歧義仍依既有規則處理。

## 驗證

- 生產程式的選單 Binding 直接抽取進測試，覆蓋 DDC 初始讀值、讀回更新、切換原生輸出與 DDC 寫入／解除靜音；不是另寫一份 UI 綁定實作。
- 覆蓋 DDC 失敗不重送、非同步排隊後切換輸出不誤寫，以及成功切換後立即清除舊能力並同步媒體鍵。
- 本機完整回歸 113,467 checks、mixer 595 checks、正式／Developer 建置、selftest 與 strict deep codesign 通過。[最終 CI](https://github.com/imstevelin/vorssaint-mytool/actions/runs/41335943526) 雙工具鏈成功；已合入 main 並安裝 1.2.1／14。
- 安裝後實際設定介面確認 PA328QV 選中時顯示 DDC 滑桿與 100% 讀值，且 Core Audio 不提供可寫主音量；未改音量值。硬體鍵與實際響度不以自動測試代填。本輪未更動藍牙修復、配對資訊或 HiDPI 設定。
