const fs = require('fs'), path = require('path');
const p = __dirname;
const abi = JSON.parse(fs.readFileSync(path.join(p, 'FamilyTrustContinuous.abi.json'), 'utf8'));
const app = fs.readFileSync(path.join(p, 'app.js'), 'utf8').replace('__ABI__', JSON.stringify(abi)).replace('__SAFE_ADMIN__', fs.readFileSync(path.join(p, 'safe-admin.js'), 'utf8')).replace('__WALLET_DISCOVERY__', fs.readFileSync(path.join(p, 'wallet-discovery.js'), 'utf8'));
const html = fs.readFileSync(path.join(p, 'template.html'), 'utf8').replace('__APP__', app);
fs.writeFileSync(path.join(p, 'FamilyTrust_Continuous_DApp.html'), html);
console.log('Built single-file DApp', Buffer.byteLength(html), 'bytes');
