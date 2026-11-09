# 測試說明

2026-11-09 已在整理後的專案根目錄重跑 `npm test`，所有套件通過。

在專案根目錄執行：

```bash
npm install
npm test
```

## 測試套件

| 程式 | 驗證內容 |
|---|---|
| `tests/contracts.cjs` | 建構參數、時間條件、持續給付、缺款暫停與恢復、急用金、提前支領、手足借款及資金回收 |
| `tests/ui.cjs` | 代幣授權與入金、帳號角色、結算、領款、提前支領與直接發放 |
| `tests/safe-admin.cjs` | 官方 Safe 1.4.1 代理、雙簽暫停與恢復、單期分配、批次取回、提案保存、nonce 作廢及失敗狀態 |
| `tests/wallet-discovery.cjs` | EIP-6963、延遲注入、其他錢包干擾、開啟環境診斷 |
| `tests/wallet-connect.cjs` | 完整頁面在只有 EIP-6963、沒有 window.ethereum 時的連線流程 |

合約與交易流程使用本機 Ganache。一般前端測試以 Node VM 模擬 DOM，錢包注入亦使用模擬物件。父母管理測試使用官方 Safe 1.4.1 編譯產物、SafeProxyFactory 與 MultiSendCallOnly。

這些測試不會向 Sepolia 發送交易，也不代表已在老師的電腦上驗證 MetaMask 擴充功能。真實網路與瀏覽器操作需以實際交易及錢包授權畫面確認。

## 原始報告

專案根目錄的 `TEST_RESULTS.txt`、`UI_TEST_RESULTS.txt`、`SAFE_ADMIN_TEST_RESULTS.txt` 與 `WALLET_TEST_RESULTS.txt` 記錄各階段測試。新的合約測試執行會更新編譯產物與 `TEST_RESULTS.txt`。
