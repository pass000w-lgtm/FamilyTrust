// Discover MetaMask through EIP-6963 and delayed legacy injection.
const announcedWallets=new Map(),walletBoundProviders=new WeakSet();
function validWalletProvider(p){return p&&typeof p==='object'&&typeof p.request==='function'}
function captureWalletAnnouncement(event){try{const d=event.detail;if(!validWalletProvider(d?.provider)||typeof d?.info?.uuid!=='string'||announcedWallets.size>30)return;announcedWallets.set(d.info.uuid,{provider:d.provider,info:{rdns:String(d.info.rdns||''),name:String(d.info.name||'')}})}catch{}}
function requestWalletAnnouncements(){try{if(typeof Event==='function')window.dispatchEvent?.(new Event('eip6963:requestProvider'))}catch{}}
window.addEventListener?.('eip6963:announceProvider',captureWalletAnnouncement);
requestWalletAnnouncements();
function detectedMetaMask(){
 const choices=Array.from(announcedWallets.values());
 const meta=choices.find(d=>d.info.rdns.toLowerCase()==='io.metamask')||choices.find(d=>/^metamask(?:\s|$)/i.test(d.info.name)&&d.provider.isMetaMask);
 if(meta)return meta.provider;
 try{const injected=window.ethereum,list=Array.isArray(injected?.providers)?injected.providers:[injected];return list.find(p=>validWalletProvider(p)&&p.isMetaMask&&!p.isCoinbaseWallet&&!p.isPhantom)||null}catch{return null}
}
async function findMetaMask(timeout=1800){
 requestWalletAnnouncements();const ready=detectedMetaMask();if(ready)return ready;
 return new Promise(resolve=>{let done=false,timer,poll;const finish=p=>{if(done)return;done=true;clearTimeout(timer);clearInterval(poll);window.removeEventListener?.('ethereum#initialized',check);window.removeEventListener?.('eip6963:announceProvider',check);resolve(p)};const check=()=>{const p=detectedMetaMask();if(p)finish(p)};
 window.addEventListener?.('ethereum#initialized',check);window.addEventListener?.('eip6963:announceProvider',check);timer=setTimeout(()=>finish(detectedMetaMask()),timeout);poll=setInterval(check,100);requestWalletAnnouncements();check();});
}
function walletMissingMessage(){
 const loc=window.location||{},protocol=loc.protocol||'',host=loc.hostname||'';let frame=false;try{frame=window.self!==window.top}catch{frame=true}
 if(frame)return '目前網頁位於預覽或內嵌視窗，未偵測到 MetaMask。\n請下載 HTML，以安裝 MetaMask 的 Chrome／Edge 開啟本機網站：http://127.0.0.1:8000/ 。';
 if(protocol==='file:')return '目前是直接開啟 HTML 檔案（file://），瀏覽器未提供 MetaMask。\n請在檔案所在資料夾啟動本機伺服器，再開 http://127.0.0.1:8000/ 。';
 if(['localhost','127.0.0.1','[::1]'].includes(host))return '目前已在本機網站，但這個瀏覽器頁面仍未偵測到 MetaMask。\n請使用操作 Remix 的同一個瀏覽器使用者設定檔，確認 MetaMask 已啟用並允許此網站存取，再重新整理頁面。';
 return '目前頁面未偵測到 MetaMask。\n請確認是在已安裝 MetaMask 的 Chrome／Edge 開啟，不是在 ChatGPT 預覽或無痕視窗。下載 HTML 後以 http://127.0.0.1:8000/ 開啟。';
}
function walletConnectError(e){if(e.code===-32002)return 'MetaMask 有尚未完成的連線要求。請點瀏覽器右上角 MetaMask，完成或取消該要求後重試。';if(e.code===4100)return '此網站尚未取得錢包授權，請在 MetaMask 允許連線。';if(e.code===4902)return 'MetaMask 尚未加入 Sepolia，請先在錢包啟用測試網路並選擇 Sepolia。';return errorText(e)}
