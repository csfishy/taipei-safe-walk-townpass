// Manual local preparation only; never runs in CI and never contacts a service.
import {mkdir,readFile,writeFile} from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';import webpush from 'web-push';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const ref='gxofnhzkqcmzrftxqddi',url=`https://${ref}.supabase.co`;
const folder=path.join(root,'.local-data/nearby-push');await mkdir(folder,{recursive:true});
const file=path.join(folder,'credentials.json');let keys;
try { keys=JSON.parse(await readFile(file,'utf8'));if(keys.project!==ref)throw new Error('Project binding mismatch'); }
catch(error){if(error.code!=='ENOENT')throw error;
 const vapid=webpush.generateVAPIDKeys();keys={project:ref,publicKey:vapid.publicKey,privateKey:vapid.privateKey,cronToken:randomBytes(32).toString('hex')};
 await writeFile(file,JSON.stringify(keys),{flag:'wx',mode:0o600});
}
const env={NEARBY_PUSH_ENABLED:'true',NEARBY_VAPID_PUBLIC_KEY:keys.publicKey,NEARBY_VAPID_PRIVATE_KEY:keys.privateKey,
 NEARBY_PUSH_CRON_TOKEN:keys.cronToken,NEARBY_VAPID_SUBJECT:'https://csfishy.github.io/taipei-safe-walk-townpass/receiver/'};
await writeFile(path.join(folder,'edge.env'),Object.entries(env).map(([k,v])=>`${k}=${v}`).join('\n')+'\n',{mode:0o600});
await writeFile(path.join(folder,'public-key.txt'),keys.publicKey+'\n');
const cleanup=await readFile(path.join(root,'supabase/nearby_live_test/pwa/03_cleanup.sql'),'utf8');
const activation=`-- MANUAL ONLY after remote v2 verifier and Edge health pass. Deadline unchanged.
BEGIN;
DO $check$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.control WHERE enabled_until>now()) THEN RAISE EXCEPTION 'Live window expired; do not extend automatically'; END IF;
 IF (SELECT count(*) FROM pg_extension WHERE extname IN('pg_cron','pg_net','supabase_vault'))<>3 THEN RAISE EXCEPTION 'Scheduler extensions must be reviewed first'; END IF;
END $check$;
DO $vault$ DECLARE existing uuid; BEGIN
 SELECT id INTO existing FROM vault.secrets WHERE name='nearby_push_cron_token';
 IF existing IS NULL THEN PERFORM vault.create_secret('${keys.cronToken}','nearby_push_cron_token','Limited Live PWA worker token');
 ELSE PERFORM vault.update_secret(existing,'${keys.cronToken}'); END IF;
END $vault$;
SELECT cron.schedule('swtest-nearby-push','10 seconds',$job$
 SELECT net.http_post(url:='${url}/functions/v1/nearby-push',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='nearby_push_cron_token')),
 body:='{}'::jsonb,timeout_milliseconds:=25000)
 WHERE EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.control WHERE push_enabled AND enabled_until>now());
$job$);
SELECT cron.schedule('swtest-nearby-push-cleanup','* * * * *',$job$
${cleanup}
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname IN('swtest-nearby-push','swtest-nearby-push-cleanup')
 AND NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.control WHERE enabled_until>now());
$job$);
UPDATE safe_walk_nearby_live_test.control SET push_enabled=true WHERE id;
COMMIT;
`;
await writeFile(path.join(folder,'activate.sql'),activation,{mode:0o600});
console.log('Prepared project-bound ignored credentials and activation SQL. No secrets printed; no remote changes.');
