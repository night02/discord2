const repository='night02/discord2';
const api=`https://api.github.com/repos/${repository}`;

// Public release metadata only. Requests never carry the user's bearer session.
// Keep the last accepted snapshot on outages, and coalesce simultaneous clients.
export function createReleaseMetadata({fallback,fetchImpl=fetch,clock=Date.now,
  enabled=process.env.NODE_ENV==='production'}={}) {
  let snapshot=fallback,expires=0,pending;
  const json=async url=>{
    const response=await fetchImpl(url,{
      headers:{accept:'application/vnd.github+json','user-agent':'Veylor-Updates'},
      signal:AbortSignal.timeout(5000)
    });
    if(!response.ok)throw new Error('Release provider unavailable');
    return response.json();
  };
  const refresh=async()=>{
    try{
      const releases=await json(api+'/releases?per_page=10');
      if(!Array.isArray(releases))throw new Error('Invalid release catalog');
      const release=releases.find(r=>!r.draft&&r.prerelease&&
        /^v\d+\.\d+\.\d+-beta\.[1-9]\d*$/.test(r.tag_name));
      if(!release)throw new Error('No published beta');
      const [,version,runId]=/^v(\d+\.\d+\.\d+)-beta\.([1-9]\d*)$/.exec(release.tag_name);
      const page=`https://github.com/${repository}/releases/tag/${release.tag_name}`;
      if(release.html_url!==page||!Array.isArray(release.assets))throw new Error('Invalid release origin');
      const complete=name=>release.assets.filter(a=>a.name===name&&a.size>0).length===1;
      const prefix=`Veylor-v${version}`;
      for(const name of [`${prefix}-Setup-Windows-x64.exe`,`${prefix}-Windows-x64.zip`,
        `${prefix}-Linux-x64.tar.gz`,'SHA256SUMS.txt']){
        if(!complete(name))throw new Error('Incomplete release');
      }
      if(!complete(`${prefix}-Android-debug-TEST-ONLY.apk`) &&
        !complete(`${prefix}-Android-signed.apk`))throw new Error('Missing Android package');
      const run=await json(api+'/actions/runs/'+runId);
      if(run.name!=='Veylor preview builds'||run.status!=='completed'||
        run.conclusion!=='success'||run.event!=='push'||run.head_branch!=='main'||
        !/^[a-f0-9]{40}$/.test(run.head_sha)||run.head_sha!==release.target_commitish||
        !Number.isSafeInteger(run.run_number)||run.run_number<1){
        throw new Error('Release build was not approved on main');
      }
      // The tag contains a workflow RUN ID, not the installed package build
      // number. Using it as "build" would cause an endless update prompt.
      snapshot=Object.fromEntries(['android','windows'].map(platform=>[platform,{
        ...fallback[platform],version,build:run.run_number,
        title:`Veylor V${version} — Beta`,
        notes:`Beta ${version} disponível no GitHub. Confira os arquivos e SHA-256 na página de downloads.`,
        download_url:page,distribution:'github_releases_public',
        installation:'manual',mandatory:false
      }]));
      expires=clock()+600000;
    }catch{
      // Do not expose provider payloads or make every client retry an outage.
      expires=clock()+60000;
    }
  };
  return {
    async get(platform){
      if(!['android','windows'].includes(platform))throw new Error('Unsupported update platform');
      if(enabled&&clock()>=expires){
        pending??=refresh().finally(()=>{pending=undefined;});
        await pending;
      }
      return {...snapshot[platform]};
    }
  };
}
