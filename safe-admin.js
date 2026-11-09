// Safe 1.3+ EIP-712 transactions. Signatures stay in this browser; no API key or private key is used.
const SAFE_TX_ABI=['function getOwners() view returns(address[])','function getThreshold() view returns(uint256)','function nonce() view returns(uint256)','function VERSION() view returns(string)','function domainSeparator() view returns(bytes32)','function getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256) view returns(bytes32)','function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures) payable returns(bool success)','event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)','event ExecutionFailure(bytes32 indexed txHash,uint256 payment)'];
const SAFE_TYPES={SafeTx:[{name:'to',type:'address'},{name:'value',type:'uint256'},{name:'data',type:'bytes'},{name:'operation',type:'uint8'},{name:'safeTxGas',type:'uint256'},{name:'baseGas',type:'uint256'},{name:'gasPrice',type:'uint256'},{name:'gasToken',type:'address'},{name:'refundReceiver',type:'address'},{name:'nonce',type:'uint256'}]};
const SAFE_MULTI={address:'0x9641d764fc13c8b624c04430c7356c1c7c8102e2',codeHash:'0xecd5bd14a08c5d2122379900b2f272bdf107a7e92423c10dd5fe3254386c9939'};
const SAFE_ALLOWED=new Set(['pauseTrust','resumeTrust','recoverOperating','recoverAllAvailable','setPeriodDuration','setPeriodAllocation','cancelEmergencyBySafe']);
let safeInfo=null,safeLoading=false,safeUiError='';
function safeKey(){return 'familyFundSafeV1:11155111:'+lower(FIXED.safe)+':'+lower(address)}
function readProposal(){try{const s=localStorage.getItem(safeKey());return s?JSON.parse(s):null}catch(e){throw Error('無法讀取本機提案，請使用一般瀏覽器視窗。')}}
function saveProposal(p){try{localStorage.setItem(safeKey(),JSON.stringify(p));if(localStorage.getItem(safeKey())!==JSON.stringify(p))throw Error('Write failed')}catch(e){throw Error('無法保存提案，請確認瀏覽器允許此網站儲存資料。')}}
function safeDomain(){return {chainId:11155111,verifyingContract:ethers.getAddress(FIXED.safe)}}
function safeBuild(plan,nonce,cancel=false){
 if(cancel){if(plan.length)throw Error('作廢交易格式錯誤。');return {to:ethers.getAddress(FIXED.safe),value:'0',data:'0x',operation:0,safeTxGas:'0',baseGas:'0',gasPrice:'0',gasToken:ethers.ZeroAddress,refundReceiver:ethers.ZeroAddress,nonce:String(nonce)}}
 if(!Array.isArray(plan)||!plan.length||plan.length>2)throw Error('不支援的父母提案。');
 if(plan.length===2&&(plan[0][0]!=='pauseTrust'||!['recoverOperating','recoverAllAvailable','setPeriodDuration','cancelEmergencyBySafe'].includes(plan[1][0])))throw Error('不支援的批次提案。');
 const calls=plan.map(([fn,args])=>{if(!SAFE_ALLOWED.has(fn))throw Error('不支援的管理功能。');return {to:ethers.getAddress(address),data:ti.encodeFunctionData(fn,args)}});
 let to=calls[0].to,data=calls[0].data,operation=0;
 if(calls.length>1){const packed=ethers.concat(calls.map(c=>ethers.solidityPacked(['uint8','address','uint256','uint256','bytes'],[0,c.to,0,ethers.getBytes(c.data).length,c.data])));to=ethers.getAddress(SAFE_MULTI.address);data=new ethers.Interface(['function multiSend(bytes)']).encodeFunctionData('multiSend',[packed]);operation=1}
 return {to,value:'0',data,operation,safeTxGas:'0',baseGas:'0',gasPrice:'0',gasToken:ethers.ZeroAddress,refundReceiver:ethers.ZeroAddress,nonce:String(nonce)};
}
function safeHash(tx){return ethers.TypedDataEncoder.hash(safeDomain(),SAFE_TYPES,tx)}
function safeTxArgs(tx){return [tx.to,tx.value,tx.data,tx.operation,tx.safeTxGas,tx.baseGas,tx.gasPrice,tx.gasToken,tx.refundReceiver]}
function validateProposal(p){
 if(!p||p.version!==1||p.chainId!==11155111||lower(p.safe)!==lower(FIXED.safe)||lower(p.trust)!==lower(address)||!/^\d+$/.test(p.nonce))throw Error('提案不屬於目前的信託或網路。');
 const tx=safeBuild(p.plan,p.nonce,p.cancel);for(const k of Object.keys(tx))if(String(tx[k]).toLowerCase()!==String(p.tx?.[k]).toLowerCase())throw Error('提案內容已變更，停止簽署。');
 if(safeHash(tx)!==p.hash)throw Error('提案雜湊不一致。');return tx;
}
function validSignatures(p,owners){validateProposal(p);const result=[],seen=new Set();for(const [who,sig]of Object.entries(p.signatures||{})){const recovered=ethers.recoverAddress(p.hash,sig);if(lower(recovered)!==lower(who)||!owners.some(a=>lower(a)===lower(recovered)))throw Error('簽名不屬於目前父母帳號。');if(seen.has(lower(recovered)))throw Error('同一位家長的簽名不能重複計算。');seen.add(lower(recovered));result.push({owner:lower(recovered),signature:ethers.Signature.from(sig).serialized})}return result.sort((a,b)=>a.owner.localeCompare(b.owner))}
function safeDescribe(p){if(p.cancel)return ['作廢原提案（不變更信託設定）'];return p.plan.map(([fn,a])=>({pauseTrust:'暫停信託',resumeTrust:'恢復信託',recoverOperating:'取回定期餘額 '+F(a[0])+' FAM',recoverAllAvailable:'取回定期餘額與急用金',setPeriodDuration:'每期改為 '+a[0]+' 秒',setPeriodAllocation:'第 '+a[0]+' 期分配：'+(Array.isArray(a[1])?a[1].map(v=>F(v)).join('／'):'')+' FAM',cancelEmergencyBySafe:'取消急用金申請 #'+a[0]})[fn])}
async function safeReadContext(forWrite=false){
 if(!state||!address)throw Error('請先載入信託合約。');const captured=epoch;
 const p=provider&&chain===11155111?provider:publicProvider;if(!p)throw Error('尚未連線。');
 if(forWrite&&(!writable()||Number(await wallet.request({method:'eth_chainId'}))!==11155111))throw Error('請連接 MetaMask 並切換到 Sepolia。');
 const c=new ethers.Contract(FIXED.safe,SAFE_TX_ABI,p);const [owners,threshold,nonce,domain,version]=await Promise.all([c.getOwners(),c.getThreshold(),c.nonce(),c.domainSeparator(),c.VERSION()]);
 if(captured!==epoch)throw Error('帳號或合約已變更，請重新操作。');
 if(owners.length!==2||threshold!==2n)throw Error('此介面只支援原設定的父母 2／2 Safe。');
 if(domain!==ethers.TypedDataEncoder.hashDomain(safeDomain()))throw Error('Safe 簽署格式不相容，停止操作。');
 if(forWrite&&!owners.some(o=>lower(o)===lower(account)))throw Error('請切換到父親或母親帳號。');
 if(forWrite){const signer=await provider.getSigner();if(lower(await signer.getAddress())!==lower(account))throw Error('錢包帳號已變更，請重新讀取。')}
 return {owners:Array.from(owners),threshold,nonce,version,c,provider:p,epoch:captured};
}
async function safeCheckLive(p,ctx){const tx=validateProposal(p);if(BigInt(p.nonce)!==await ctx.c.nonce())throw Error('Safe 序號已變更，此提案失效，請建立新提案。');if(tx.operation===1){const code=await ctx.provider.getCode(SAFE_MULTI.address);if(ethers.keccak256(code)!==SAFE_MULTI.codeHash)throw Error('無法確認批次執行合約，停止操作。')}
 const liveHash=await ctx.c.getTransactionHash(...safeTxArgs(tx),tx.nonce);if(liveHash!==p.hash)throw Error('鏈上 Safe 雜湊不一致，停止操作。');return tx;
}
async function refreshSafeAdmin(){if(safeLoading||!state)return;safeLoading=true;const captured=epoch;try{const ctx=await safeReadContext();if(captured!==epoch)return;safeInfo=ctx;safeUiError='';renderSafeAdmin()}catch(e){if(captured===epoch){safeInfo=null;safeUiError=errorText(e);renderSafeAdmin()}}finally{safeLoading=false}}
function renderSafeAdmin(){
 const el=$('safe-proposal');if(!el)return;const ctx=safeInfo,owner=!!ctx&&ctx.owners.some(o=>lower(o)===lower(account)),can=owner&&chain===11155111&&!!state&&!busy;
 if(!ctx){el.innerHTML='<div class="empty">'+esc(safeUiError||'載入合約後查看提案。')+'</div>';for(const id of ['safe-sign','safe-execute','safe-cancel'])$(id).disabled=true;return}
 try{const p=readProposal();if(!p){el.innerHTML='<div class="empty">尚無提案。請先選擇管理操作。</div>';for(const id of ['safe-sign','safe-execute','safe-cancel'])$(id).disabled=true;return}
 validateProposal(p);const sigs=validSignatures(p,ctx.owners),current=BigInt(p.nonce)===ctx.nonce,done=p.status==='executed',used=!current&&!done;
 const status=done?'執行成功':used?'已失效，請重新提出':sigs.length===2?'簽名已齊，可執行':'等待父母簽署';
 el.innerHTML='<div class="row"><strong>'+esc(status)+'</strong><span class="chip">'+sigs.length+'／2 簽署</span></div>'+safeDescribe(p).map(t=>'<p>'+esc(t)+'</p>').join('')+'<div class="code">信託：'+esc(address)+'<br>Safe 序號：'+esc(p.nonce)+'</div><div class="safe-signers">'+ctx.owners.map(o=>'<div class="row"><span>'+ (lower(o)===lower(FIXED.funder)?'父親':'母親')+' '+esc(short(o))+'</span><strong>'+(sigs.some(x=>x.owner===lower(o))?'已簽署':'未簽署')+'</strong></div>').join('')+'</div>'+(p.executionHash?'<a target="_blank" rel="noopener" href="https://sepolia.etherscan.io/tx/'+esc(p.executionHash)+'">查看執行交易 ↗</a>':'');
 $('safe-sign').disabled=!can||!current||done||sigs.some(x=>x.owner===lower(account));$('safe-execute').disabled=!can||!current||done||sigs.length!==2;$('safe-cancel').disabled=!can||!current||done||!!p.cancel;
 }catch(e){el.innerHTML='<div class="note error">'+esc(errorText(e))+'</div>';for(const id of ['safe-sign','safe-execute','safe-cancel'])$(id).disabled=true}
}
async function safeBatch(calls,label,cancel=false){
 const ctx=await safeReadContext(true);let old=readProposal();if(old){validateProposal(old);if(BigInt(old.nonce)===ctx.nonce&&old.status!=='executed'&&!cancel)throw Error('已有待處理提案，請先完成，或提出作廢提案。')}
 const plan=JSON.parse(JSON.stringify(calls,(_,v)=>typeof v==='bigint'?v.toString():v));const tx=safeBuild(plan,ctx.nonce,cancel);const p={version:1,chainId:11155111,safe:FIXED.safe,trust:address,nonce:String(ctx.nonce),plan,cancel,tx,hash:safeHash(tx),signatures:{},status:'pending',createdAt:Date.now()};
 await safeCheckLive(p,ctx);if(ctx.epoch!==epoch)throw Error('帳號或合約已變更。');
 if(!window.confirm((cancel?'建立作廢提案。原簽名須等作廢交易成功才失效。\n':'建立父母提案\n')+safeDescribe(p).join('\n')+'\n信託：'+address+'\nSafe 序號：'+p.nonce))return;
 saveProposal(p);safeInfo=ctx;renderSafeAdmin();$('tab-parents')?.click();$('safe-proposal')?.scrollIntoView?.({behavior:'smooth',block:'center'});message('提案已建立。請按「簽署提案」，再切換另一位家長簽署。');log(label,'','提案已保存在本瀏覽器，尚未執行。');return p;
}
async function signSafeProposal(){
 const ctx=await safeReadContext(true),p=readProposal();if(!p||p.status==='executed')throw Error('沒有待簽提案。');await safeCheckLive(p,ctx);const signatures=validSignatures(p,ctx.owners);if(signatures.some(s=>s.owner===lower(account)))throw Error('目前帳號已簽署，請切換另一位家長。');const from=account;
 if(!window.confirm('簽署父母提案\n'+safeDescribe(p).join('\n')+'\n信託：'+address+'\nSafe 序號：'+p.nonce))return;
 busy=true;render();renderSafeAdmin();try{const signer=await provider.getSigner();const signature=await signer.signTypedData(safeDomain(),SAFE_TYPES,p.tx);if(ctx.epoch!==epoch||lower(from)!==lower(account))throw Error('帳號已變更，未保存這次簽名。');if(lower(ethers.verifyTypedData(safeDomain(),SAFE_TYPES,p.tx,signature))!==lower(from))throw Error('簽名驗證失敗。');
 const fresh=readProposal();if(!fresh||fresh.hash!==p.hash)throw Error('提案已變更，請重新檢查。');const latest=await safeReadContext();await safeCheckLive(fresh,latest);fresh.signatures[lower(from)]=ethers.Signature.from(signature).serialized;validSignatures(fresh,latest.owners);saveProposal(fresh);safeInfo=latest;message(Object.keys(fresh.signatures).length===2?'父母簽名已齊，請按「執行提案」。':'已簽署。請切換另一位家長帳號，再按「簽署提案」。');
 }finally{busy=false;render();renderSafeAdmin()}
}
function safeReceiptResult(receipt,hash){if(receipt.status!==1)throw Error('Safe 交易失敗。');const inter=new ethers.Interface(SAFE_TX_ABI);let success=false;for(const l of receipt.logs||[]){if(lower(l.address)!==lower(FIXED.safe))continue;try{const e=(l.topics.length===1?new ethers.Interface(['event ExecutionSuccess(bytes32 txHash,uint256 payment)','event ExecutionFailure(bytes32 txHash,uint256 payment)']):inter).parseLog(l);if(e?.args?.txHash!==hash)continue;if(e.name==='ExecutionFailure')throw Error('Safe 已上鏈，但信託操作失敗。');if(e.name==='ExecutionSuccess')success=true}catch(e){if(e.message==='Safe 已上鏈，但信託操作失敗。')throw e}}if(!success)throw Error('未確認 Safe 執行成功事件，請查交易紀錄。');}
async function executeSafeProposal(){
 const ctx=await safeReadContext(true),p=readProposal();if(!p||p.status==='executed')throw Error('沒有待執行提案。');const tx=await safeCheckLive(p,ctx),sigs=validSignatures(p,ctx.owners);if(sigs.length!==2)throw Error('需要父母兩人的簽名。');const signatures=ethers.concat(sigs.map(s=>s.signature));
 if(!window.confirm('執行父母提案\n'+safeDescribe(p).join('\n')+'\n信託：'+address+'\n本次需支付 Sepolia ETH 交易費。'))return;
 busy=true;render();renderSafeAdmin();try{const signer=await provider.getSigner();const c=new ethers.Contract(FIXED.safe,SAFE_TX_ABI,signer),args=[...safeTxArgs(tx),signatures];message('檢查父母提案執行條件…');if(!await c.execTransaction.staticCall(...args))throw Error('信託條件已變更，提案目前無法執行。');const gas=await c.execTransaction.estimateGas(...args);if(ctx.epoch!==epoch)throw Error('帳號或合約已變更。');const live=await safeReadContext();await safeCheckLive(p,live);const result=await c.execTransaction(...args,{gasLimit:gas*130n/100n});log(safeDescribe(p).join('、'),result.hash,'Safe 執行交易已送出');message('等待 Safe 交易確認…');let receipt;try{receipt=await result.wait()}catch(e){if(e.code==='TRANSACTION_REPLACED'&&!e.cancelled)receipt=e.receipt;else throw e}
 safeReceiptResult(receipt,p.hash);p.status='executed';p.executionHash=receipt.hash;if(readProposal()?.hash===p.hash)saveProposal(p);message(p.cancel?'作廢交易成功，現在可建立新提案。':'提案執行成功，設定已更新。');log(safeDescribe(p).join('、'),receipt.hash,'Safe ExecutionSuccess 已確認');await refresh(true);
 }finally{busy=false;render();await refreshSafeAdmin();renderSafeAdmin()}
}
$('safe-sign').onclick=guard(signSafeProposal);$('safe-execute').onclick=guard(executeSafeProposal);$('safe-cancel').onclick=guard(()=>safeBatch([],'作廢待處理提案',true));
window.addEventListener?.('storage',e=>{if(address&&e.key===safeKey())renderSafeAdmin()});
