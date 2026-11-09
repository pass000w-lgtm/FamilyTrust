# 家庭基金 Family Fund

在 Ethereum Sepolia 上運作的家庭式鏈上信託專案，包含一個不可升級的持續給付合約，以及可連接 MetaMask 的網頁操作介面。父母以 2／2 Safe 管理，三位子女領取生活費並申請彈性給付。

## 快速查看

- [信託合約原始碼](FamilyTrustContinuous.sol)
- [DApp 操作介面](FamilyTrust_Continuous_DApp.html)（下載後以本機網站開啟）
- [簡報 PDF](docs/slides/FamilyFund_Midterm.pdf)
- [可編輯 PowerPoint](docs/slides/FamilyFund_Midterm.pptx)
- [部署與操作說明](README_先讀這份.md)

## 情境與角色

父親先存入 FAM 代幣作為家庭基金，合約依期數與額度控制給付。父母透過既有的 Safe 共同管理，子女可領款、申請急用金或與手足借款。

| 角色 | 可以做的事 | 權限限制 |
|---|---|---|
| 出資人（父親） | 存入 FAM、首次啟動 | 個人錢包無法直接執行父母管理功能 |
| 父母 Safe | 暫停／恢復、改期長、改單期分配、取回未分配資金 | 須父母兩人共同簽署 |
| 受益人（哥哥、弟弟、妹妹） | 領款、提前支領、急用金、提出借款 | 受自己的額度與既有承諾限制 |
| 出借人（其中一位手足） | 接受借款，以當期未領款出借 | 不能出借已轉出錢包的同一筆未領款 |

## 功能與資金規則

| 功能 | 規則 |
|---|---|
| 定期給付 | 預設每期 20 秒，三人各 500 FAM，合計 1,500 FAM |
| 持續運作 | 無總期數上限，可持續補款，不用六期後重新部署 |
| 急用金 | 補足目標 5,000 FAM，新入金先補池，剩餘才供定期給付 |
| 缺款暫停 | 到期交易發現定期餘額不足時暫停，不增期、不部分付款 |
| 補款恢復 | 缺款補足並入帳後接續下一期，重新等待一期，不補扣停頓期間 |
| 手動暫停 | 父母 Safe 決定，補款不能越過手動暫停 |
| 單期分配 | 父母可改指定未來一期，三人總額仍為 1,500 FAM，保留已鎖定承諾 |
| 急用金核准 | 申請人以外的另外兩位手足都核准後支付 |
| 提前支領 | 第一期後可提前動用下一期未承諾面額，每個下一期限一次，實領 95% |
| 手足借款 | 本金來自出借人的當期未領款，最早約定於當期＋2 還款 |
| 暫停後取回 | 只取回定期未分配餘額，或連急用金一起取回，均退到父母 Safe |
| 既有未領款 | 暫停或父母取回資金時仍保留，不在取回範圍內 |

### 結算、發放與自動執行

- `settleNextPeriod()` 只結算一期，留下受益人的未領款，方便手足借款。
- `distributeNextPeriod()` 結算一期，並把三人的全部既有未領款直接轉入各自錢包。
- `withdrawAll()` 讓受益人領取自己的未領款。
- `checkUpkeep()`／`performUpkeep()` 提供外部執行器可使用的介面。

20 秒是最早可執行時間。示範借款時先按「只結算」，避免出借人的當期未領款先轉出。

## 執行 DApp

操作介面已包含 ethers，不需先安裝 npm 套件。

1. 下載本儲存庫的 ZIP 並解壓縮。
2. 在專案資料夾開啟終端機，執行：

   ```bash
   python -m http.server 8000 --bind 127.0.0.1
   ```

3. 用已安裝 MetaMask 的 Chrome／Edge 開啟：

   ```text
   http://127.0.0.1:8000/FamilyTrust_Continuous_DApp.html
   ```

4. 貼上新版信託合約地址，連接錢包並切換 Sepolia。
5. 父親存入例如 10,000 FAM，確認授權與存入交易，然後首次啟動。

首次存入 10,000 FAM 時，5,000 補急用金，5,000 供定期給付，足夠預設三期。之後可補款接續運作。

### 父母直接多簽

在「父母管理」選操作並建立提案，父親簽署、切換母親簽署，2／2 後按「執行提案」。不需要下載 JSON 或匯入 Safe Transaction Builder。

提案及簽名儲存在同一瀏覽器、同一網站來源的 localStorage。重新整理或切換 MetaMask 帳號會保留，不會自動同步到其他電腦或 Safe 網站。簽署不收 Gas，最後執行才支付 Sepolia ETH。

## 鏈上部署資訊

**新版信託地址：待專案作者補入。** 最新檔案未包含該地址，因此這裡不填入舊版六期合約地址。DApp 可直接輸入現有的新信託地址。

| 項目 | 資料 |
|---|---|
| 網路 | Ethereum Sepolia，Chain ID 11155111 |
| 新版信託合約 | 待填，亦可同步更新 `deployment-parameters.json` 的 `trustAddress` |
| FAM 代幣 | [0x950F3735f0a939A3Ce80aD5c5b8d56b50cff1C58](https://sepolia.etherscan.io/address/0x950F3735f0a939A3Ce80aD5c5b8d56b50cff1C58) |
| 父母 Safe | [0x9bDE8a27D271A12911f7d0e0A7BfaFcc59539B65](https://sepolia.etherscan.io/address/0x9bDE8a27D271A12911f7d0e0A7BfaFcc59539B65) |
| Solidity | 0.8.34，Optimizer 200，EVM shanghai，viaIR 關閉 |
| FAM 單位 | 6 位小數，500 FAM 為 `500000000` 基本單位 |

實際交易可在信託地址的 Transactions 與 ERC-20 Token Transfers 查看。可讀的 Solidity 程式碼需先在 Etherscan 完成原始碼驗證，本儲存庫另附 `standard-input.json`。

## 現場 demo 順序

1. 父親入金並啟動，確認急用金及定期餘額。
2. 父母共同調整下一個未結算期的分配。
3. 到期只結算，哥哥向弟弟借款，由弟弟接受。
4. 哥哥提前支領下一期的部分額度。
5. 妹妹申請急用金，由哥哥與弟弟核准。
6. 父母暫停並取回未分配的定期餘額，確認未領款保留。

## 開發與測試

需要 Node.js、npm，以及可取得套件的網路環境：

```bash
npm install
npm test
```

測試會編譯合約並啟動本機 Ganache，不會送出 Sepolia 交易。測試涵蓋定期給付、權限、急用金、提前支領、借款、缺款恢復、官方 Safe 多簽與錢包偵測。`compiled-local.json` 是測試時生成的暫存編譯結果，不放進儲存庫。

前端原始碼為 `app.js`、`safe-admin.js`、`wallet-discovery.js` 與 `template.html`。更新後執行：

```bash
node build-ui.cjs
```

即可重新產生單檔 `FamilyTrust_Continuous_DApp.html`。

## 主要檔案

| 路徑 | 用途 |
|---|---|
| `FamilyTrustContinuous.sol` | 不可升級、持續給付的信託合約 |
| `FamilyTrustContinuous.abi.json` | 合約 ABI |
| `FamilyTrust_Continuous_DApp.html` | 可直接使用的完整前端 |
| `app.js` | 鏈上讀取與受益人操作 |
| `safe-admin.js` | 父母 Safe EIP-712 簽署與執行 |
| `wallet-discovery.js` | MetaMask 與 EIP-6963 偵測 |
| `tests/` | 合約、前端、Safe 與錢包測試 |
| `docs/slides/` | 報告簡報 |
| `README_先讀這份.md` | 詳細部署、入金與操作說明 |

## 第三方元件

本專案使用 ethers、OpenZeppelin、Ganache 與 solc。Safe 測試包含官方 1.4.1 合約編譯產物，其來源與授權見 [第三方說明](THIRD_PARTY_NOTICES.md)、`tests/SAFE_ARTIFACTS_SOURCE.md` 與 `tests/SAFE_LICENSE`。
