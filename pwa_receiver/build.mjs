import {readFile,writeFile,mkdir,cp} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const args=process.argv.slice(2);
let output=path.join(root,'../artifacts/pwa/receiver'),config={};
for(let i=0;i<args.length;i+=2){
  if(args[i]==='--out')output=path.resolve(args[i+1]);
  else if(args[i]==='--config')config=JSON.parse(await readFile(args[i+1],'utf8'));
  else throw new Error('Use --out DIRECTORY --config PUBLIC_CONFIG.json');
}
if(!Object.keys(config).every(k=>['supabaseUrl','anonKey','vapidPublicKey','tileUrl'].includes(k)))throw new Error('Only public browser configuration is allowed');
if(config.supabaseUrl && !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(config.supabaseUrl))throw new Error('Expected Supabase HTTPS project URL');
if(config.anonKey){
  if(config.anonKey.startsWith('sb_secret_'))throw new Error('Server credentials cannot enter the browser');
  if(!config.anonKey.startsWith('sb_publishable_')){
    const claims=JSON.parse(Buffer.from(config.anonKey.split('.')[1] || '','base64url').toString());
    if(claims.role!=='anon')throw new Error('Only anon/publishable key allowed');
  }
}
if(config.vapidPublicKey && !/^[A-Za-z0-9_-]{87}$/.test(config.vapidPublicKey))throw new Error('Invalid VAPID public key');
if(config.tileUrl && config.tileUrl!=='https://tile.openstreetmap.org/{z}/{x}/{y}.png')throw new Error('A new tile provider also needs an explicit CSP/privacy review');
// An explicit receiver directory prevents accidental overwrite of the app shell.
if(path.basename(output)!=='receiver')throw new Error('Output must end in /receiver');
await mkdir(output,{recursive:true});
await cp(path.join(root,'public'),output,{recursive:true});
await cp(path.join(root,'src/core.mjs'),path.join(output,'core.mjs'));
await mkdir(path.join(output,'vendor'),{recursive:true});
for(const name of ['leaflet.js','leaflet.css'])await cp(path.join(root,'node_modules/leaflet/dist',name),path.join(output,'vendor',name));
await cp(path.join(root,'node_modules/leaflet/LICENSE'),path.join(output,'vendor/leaflet-LICENSE.txt'));
await cp(path.join(root,'node_modules/leaflet/dist/images'),path.join(output,'vendor/images'),{recursive:true});
for(const size of [192,1024])await cp(path.join(root,`../web/icons/Icon-${size}.png`),path.join(output,`icon-${size}.png`));
await writeFile(path.join(output,'config.mjs'),`// Public client configuration only. No service key or VAPID private key.\nexport default ${JSON.stringify(config)};\n`);
console.log(`Built receiver at ${output}; ${config.supabaseUrl?'public configuration supplied':'unconfigured (explicitly unavailable)'}`);
