import {readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url)),folder=new URL('../apps/server/test/',import.meta.url);
const pgFiles=['import.test.mjs','postgres.test.mjs','discord-pg.test.mjs'];
const tests=readdirSync(folder).filter(name=>name.endsWith('.test.mjs') && !pgFiles.includes(name)).map(name=>fileURLToPath(new URL(name,folder)));
async function run(files,database=''){
  return new Promise(resolve=>{
    const child=spawn(process.execPath,['--test',...files],{cwd:root,stdio:'inherit',env:{...process.env,DATABASE_URL:database}});
    child.once('error',()=>resolve(1));child.once('exit',code=>resolve(code??1));
  });
}
process.exitCode=await run(tests);
if(!process.exitCode && process.env.VEYLOR_TEST_DATABASE_URL){
  for(const file of pgFiles){
    process.exitCode=await run([fileURLToPath(new URL(file,folder))],process.env.VEYLOR_TEST_DATABASE_URL);
    if(process.exitCode)break;
  }
}
