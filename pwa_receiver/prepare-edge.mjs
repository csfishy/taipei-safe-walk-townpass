import {mkdir,cp,writeFile} from 'node:fs/promises';
import path from 'node:path';import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const output=path.resolve(root,'../supabase/functions/nearby-push');
await mkdir(output,{recursive:true});
for(const file of ['dispatch.mjs','edge-handler.mjs'])await cp(path.join(root,'worker',file),path.join(output,file));
await writeFile(path.join(output,'deno.json'),JSON.stringify({imports:{'web-push':'npm:web-push@3.6.7'}},null,2)+'\n');
console.log('Prepared Supabase Edge worker; no network or deployment performed.');
