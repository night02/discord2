// PostgreSQL is opt-in via DATABASE_URL. For staging/production we must
// require it explicitly so a missing secret never silently falls back to SQLite.
const databaseUrl=process.env.DATABASE_URL?.trim();
const postgresRequired=['1','true','yes'].includes((process.env.REQUIRE_POSTGRES||'').toLowerCase());
if(postgresRequired && !databaseUrl){
  throw new Error('PostgreSQL obrigatório: configure DATABASE_URL em ambiente seguro antes de iniciar.');
}
if(databaseUrl){
  const url=new URL(databaseUrl);
  if(!['postgres:','postgresql:'].includes(url.protocol) || !url.hostname ||
      !url.pathname || url.pathname==='/' || !url.username){
    throw new Error('DATABASE_URL deve ser uma conexão PostgreSQL válida.');
  }
  await import('./pg-server.mjs');
}else{
  await import('./sqlite-server.mjs');
}
