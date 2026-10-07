#!/usr/bin/env python3
"""Real authenticated deployment witness; private operator account, isolated profile, native event and owned-session revoke."""
from pathlib import Path
import json, os, re, shutil, signal, subprocess, sys, tempfile, time, urllib.request, urllib.error, socket
class OwnedSessionFailure(RuntimeError):
 def __init__(self,session):
  super().__init__('owned browser witness failed');self.session=session

def runtimes():
 candidates=[os.environ.get('NETPILOT_PROBE_BROWSER',''),'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','/Applications/Chromium.app/Contents/MacOS/Chromium']
 candidates += [shutil.which(name) or '' for name in ('google-chrome','google-chrome-stable','chromium','chromium-browser')]
 browser=next((p for p in candidates if p and Path(p).is_file() and os.access(p,os.X_OK)),None)
 node=shutil.which('node')
 if not browser or not node: raise RuntimeError('supported Chrome/Chromium and Node.js 22+ required for isolated browser proof')
 probe=subprocess.run([node,'-e',"if(typeof WebSocket!=='function')process.exit(1)"],capture_output=True,text=True,timeout=5)
 if probe.returncode: raise RuntimeError('Node.js runtime lacks built-in WebSocket API; use Node.js 22+')
 return browser,node

def capture(url,sha):
 if not re.fullmatch(r'[0-9a-f]{40}', sha): raise ValueError('full hexadecimal deployment SHA required')
 if not re.fullmatch(r'https://app\.netpilot\.io/sign-in\?netpilot_deploy_probe='+sha+r'\.[0-9a-f]{32}',url): raise ValueError('exact production nonce URL required')
 browser_path,node=runtimes()
 with tempfile.TemporaryDirectory(prefix='netpilot-browser-probe-') as temporary:
  with socket.socket() as reservation:
   reservation.bind(('127.0.0.1',0)); selected_port=reservation.getsockname()[1]
  args=[browser_path,'--remote-debugging-port='+str(selected_port),'--disable-gpu','--use-mock-keychain','--password-store=basic','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-extensions','--disable-sync','--user-data-dir='+temporary,'about:blank']
  browser_stderr=(Path(temporary)/'browser.stderr').open('w')
  browser=subprocess.Popen(args,stdout=subprocess.DEVNULL,stderr=browser_stderr,start_new_session=True)
  try:
   deadline=time.monotonic()+20; endpoint_owned=None
   while time.monotonic()<deadline:
    if browser.poll() is not None: break
    diagnostic=(Path(temporary)/'browser.stderr').read_text()
    found=re.search(r'DevTools listening on (ws://127[.]0[.]0[.]1:'+str(selected_port)+r'/devtools/browser/[^\s]+)',diagnostic)
    if found: endpoint_owned=found.group(1); break
    time.sleep(.2)
   if not endpoint_owned: raise RuntimeError('owned browser debugging server unavailable')
   port=str(selected_port)
   info=json.load(urllib.request.urlopen('http://127.0.0.1:'+port+'/json/version',timeout=3))
   if info['webSocketDebuggerUrl']!=endpoint_owned: raise RuntimeError('refusing unowned browser server')
   targets=json.load(urllib.request.urlopen('http://127.0.0.1:'+port+'/json/list',timeout=3))
   endpoint=next(target['webSocketDebuggerUrl'] for target in targets if target['type']=='page')
   if not endpoint.startswith('ws://127.0.0.1:'+port+'/'): raise RuntimeError('unexpected browser debugging endpoint')
   driver=Path(temporary)/'receipt.mjs'
   driver.write_text('''
 import assert from 'node:assert/strict';
 import {gunzipSync} from 'node:zlib';
 import {writeFileSync,existsSync,readFileSync} from 'node:fs';
 const [endpoint,url,sha]=process.argv.slice(2);
 const deadline=setTimeout(()=>{console.error('browser receipt timed out');process.exit(1)},110000);
const ws=new WebSocket(endpoint); let id=0; const pending=new Map();const scripts=new Map();const ingest=[];const requests=new Map();const requestErrors=[];const consoleErrors=[];const outboundEvents=[];const ingestBodies=[];let ownedSession;
 const recordOwnedSession=sid=>{assert.match(sid,/^sess_[A-Za-z0-9]+$/);const path=process.env.NETPILOT_WITNESS_SESSION_FILE;ownedSession=sid;assert.ok(existsSync(path),'private session record was not reserved before sign-in');const prior=readFileSync(path,'utf8');if(prior)assert.equal(prior,sid);else writeFileSync(path,sid,{flag:'r+',flush:true});};
 const send=(method,params={})=>new Promise((resolve,reject)=>{const n=++id;const timer=setTimeout(()=>{pending.delete(n);reject(new Error(method+' timed out'))},20000);pending.set(n,{resolve,reject,timer});ws.send(JSON.stringify({id:n,method,params}))});
 const ready=new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
 let loaded;let load=new Promise(resolve=>loaded=resolve);
 ws.onmessage=e=>{const data=JSON.parse(e.data);if(data.id){const p=pending.get(data.id);if(!p)return;pending.delete(data.id);clearTimeout(p.timer);data.error?p.reject(new Error(JSON.stringify(data.error))):p.resolve(data.result);return}
  if(data.method==='Page.loadEventFired')loaded();
  if(data.method==='Network.loadingFinished' && (requests.get(data.params.requestId)??'').split('?')[0]==='https://clerk.netpilot.io/v1/client/sign_ins')send('Network.getResponseBody',{requestId:data.params.requestId}).then(x=>{const body=x.base64Encoded?Buffer.from(x.body,'base64').toString():x.body;const sid=JSON.parse(body)?.response?.created_session_id;if(sid)recordOwnedSession(sid);}).catch(()=>consoleErrors.push('owned sign-in response could not be recorded'));
  if(data.method==='Network.loadingFinished' && requests.get(data.params.requestId)?.includes('/ingest/e/'))send('Network.getResponseBody',{requestId:data.params.requestId}).then(x=>{const body=x.base64Encoded?Buffer.from(x.body,'base64').toString():x.body;let ack;try{const data=JSON.parse(body);ack={status:data.status,error:data.error,keys:Object.keys(data)};}catch{}ingestBodies.push({size:body.length,prefix:body.slice(0,80),ack});}).catch(e=>ingestBodies.push({error:String(e)}));
  if(data.method==='Network.requestWillBeSent'){requests.set(data.params.requestId,data.params.request.url); const request=data.params.request; if(request.url.includes('/ingest/e/')){try{let body=request.postData; if(request.postDataEntries?.[0]?.bytes)body=gunzipSync(Buffer.from(request.postDataEntries[0].bytes,'base64')).toString();else if(body?.charCodeAt(0)===31)body=gunzipSync(Buffer.from(body,'latin1')).toString();let parsed=JSON.parse(body);const events=Array.isArray(parsed)?parsed:(parsed.batch??[parsed]);outboundEvents.push(...events.map(x=>({event:x.event,url:x.properties?.$current_url,timestamp:x.timestamp,uuid:x.uuid,browser_type:x.properties?.$browser_type,lib_version:x.properties?.$lib_version,keys:Object.keys(x)})));}catch(e){outboundEvents.push({decodeError:String(e)});}}}
  if(data.method==='Network.loadingFailed')requestErrors.push({url:requests.get(data.params.requestId),error:data.params.errorText,blockedReason:data.params.blockedReason});
  if(data.method==='Runtime.exceptionThrown')consoleErrors.push(data.params.exceptionDetails.text+' '+(data.params.exceptionDetails.exception?.description??''));
  if(data.method==='Runtime.consoleAPICalled' && data.params.type==='error')consoleErrors.push(data.params.args.map(x=>x.value??x.description).join(' '));
  if(data.method==='Network.responseReceived'){const {type,response}=data.params;if(type==='Script')scripts.set(response.url,response.status);if(response.url.startsWith('https://app.netpilot.io/ingest/'))ingest.push({url:response.url.split('?')[0],status:response.status})}};
 let status=0;
 try {
  await ready;await send('Network.enable');await send('Network.setCacheDisabled',{cacheDisabled:true});await send('Page.enable');await send('Runtime.enable');
  // Reserve the isolated, session-free Clerk client identity before ticket consumption.
  await send('Page.navigate',{url:'https://app.netpilot.io/sign-in'});
  let client;for(let i=0;i<80;i++){await new Promise(r=>setTimeout(r,500));const x=await send('Runtime.evaluate',{expression:'window.Clerk?.client?{id:window.Clerk.client.id,sessions:window.Clerk.client.sessions.map(s=>s.id)}:null',returnByValue:true});if(x.result?.value){client=x.result.value;break}}
  assert.ok(client);assert.match(client.id,/^client_[A-Za-z0-9]+$/);assert.deepEqual(client.sessions,[]);
  writeFileSync(process.env.NETPILOT_WITNESS_CLIENT_FILE,client.id,{flag:'r+',flush:true});
  const authURL='https://app.netpilot.io/sign-in?__clerk_ticket='+encodeURIComponent(process.env.NETPILOT_WITNESS_TICKET);
  await send('Page.navigate',{url:authURL});await send('Page.bringToFront');
  let authenticated=false;
  for(let i=0;i<80;i++){await new Promise(r=>setTimeout(r,500));const x=await send('Runtime.evaluate',{expression:'window.Clerk?.session?.id??null',returnByValue:true});if(x.result?.value){recordOwnedSession(x.result.value);authenticated=true;break}}
  assert.ok(authenticated,'ticket did not establish an active authenticated session');
  delete process.env.NETPILOT_WITNESS_TICKET;
  scripts.clear();ingest.length=0;requests.clear();requestErrors.length=0;consoleErrors.length=0;outboundEvents.length=0;ingestBodies.length=0;
  load=new Promise(resolve=>loaded=resolve);

  const navigation=await send('Page.navigate',{url});assert.equal(navigation.errorText,undefined);await send('Page.bringToFront');
  await Promise.race([load,new Promise((_,reject)=>setTimeout(()=>reject(new Error('page load timed out')),35000))]);
  const result=await send('Runtime.evaluate',{expression:"(async()=>({url:location.href,version:await fetch('/version.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw new Error('version HTTP '+r.status);return r.json()})}))()",awaitPromise:true,returnByValue:true});
  assert.equal(result.exceptionDetails,undefined);const receipt=result.result.value;assert.ok(receipt.url.startsWith("https://app.netpilot.io/"));assert.equal(receipt.version.version,sha);
  // Let the production analytics client's own queue flush. No synthetic capture call.
  await new Promise(resolve=>setTimeout(resolve,30000));
  const diagnostics=await send('Runtime.evaluate',{expression:'JSON.stringify({url:location.href,ua:navigator.userAgent,webdriver:navigator.webdriver,doNotTrack:navigator.doNotTrack,visibilityState:document.visibilityState,posthogGlobals:Object.keys(window).filter(x=>x.toLowerCase().includes("posthog")),cookieNames:document.cookie.split(";").map(x=>x.split("=")[0].trim()),localStorageKeys:Object.keys(localStorage)})',returnByValue:true});
  assert.equal(JSON.parse(diagnostics.result.value).webdriver,false,'normal browser unexpectedly automation-filtered');const loadedScripts=[...scripts].map(([url,status])=>({url,status}));assert.ok(loadedScripts.some(x=>x.url.startsWith('https://app.netpilot.io/_next/static/')));assert.ok(loadedScripts.every(x=>x.status>=200&&x.status<400));
  const finalAuth=await send('Runtime.evaluate',{expression:'window.Clerk?.session?.id??null',returnByValue:true});
  assert.equal(finalAuth.result?.value,ownedSession,'nonce page lost the owned authenticated session');
  console.log(JSON.stringify({owned_session:ownedSession,isolated_empty_cache:true,authenticated_witness:true,verified_at:new Date().toISOString(),...receipt,loaded_scripts:loadedScripts,analytics_responses:ingest,requestErrors,consoleErrors,outboundEvents,ingestBodies,diagnostics:JSON.parse(diagnostics.result.value),analytics_requests:[...requests.values()].filter(x=>x.includes("/ingest/")).map(x=>x.split("?")[0])},null,2));
 } catch(error) {console.error('owned browser witness failed');if(ownedSession)console.error('OWNED_WITNESS_SESSION='+ownedSession);status=1;}
finally {clearTimeout(deadline);for(const p of pending.values())clearTimeout(p.timer);ws.close();setTimeout(()=>process.exit(status),50)}
 ''')
   result=subprocess.run([node,str(driver),endpoint,url,sha],capture_output=True,text=True,timeout=120)
   if result.returncode:
    found=re.search(r'^OWNED_WITNESS_SESSION=(sess_[A-Za-z0-9]+)$',result.stderr,re.M)
    raise OwnedSessionFailure(found[1] if found else None)
   receipt=json.loads(result.stdout)
   assert receipt['version']['version']==sha
   return receipt
  finally:
   try:os.killpg(browser.pid,signal.SIGTERM)
   except ProcessLookupError:pass
   try:browser.wait(timeout=5)
   except subprocess.TimeoutExpired:pass
   try:os.killpg(browser.pid,signal.SIGKILL)
   except ProcessLookupError:pass
   browser.wait(timeout=5)
   browser_stderr.close()

def config():
 workspace=os.environ.get('WORKSPACE')
 if not workspace or not Path(workspace).is_dir(): raise ValueError('BROKEN: WORKSPACE must name the operator workspace')
 values={}
 # Credentials stay in their existing owners; the operator witness ID is private configuration.
 for relative,name in (('netpilot-devops/.env','NETPILOT_PROBE_CLERK_USER_ID'),('NetPilot-2-Backend/.env.prod','CLERK_SECRET_KEY')):
  path=Path(workspace)/relative
  if path.is_file():
   for line in path.read_text().splitlines():
    match=re.fullmatch(r"([A-Z][A-Z0-9_]*)\s*=\s*(.*)",line)
    if match and match[1]==name: values[name]=match[2].strip().strip("\"'")
 user=values.get('NETPILOT_PROBE_CLERK_USER_ID','')
 if not re.fullmatch(r'user_[A-Za-z0-9]+',user): raise ValueError('BROKEN: NETPILOT_PROBE_CLERK_USER_ID must name the sanctioned account in the canonical gitignored netpilot-devops/.env; no account is selected implicitly')
 key=values.get('CLERK_SECRET_KEY','')
 if not key.startswith('sk_live_'): raise ValueError('BROKEN: production Clerk credential unavailable from its existing Backend .env.prod owner')
 try: runtimes()
 except RuntimeError as error: raise ValueError('BROKEN: '+str(error)) from None
 return user,key

def clerk(key,path,payload):
 request=urllib.request.Request('https://api.clerk.com/v1/'+path,data=json.dumps(payload).encode() if payload is not None else None,headers={'Authorization':'Bearer '+key,'Content-Type':'application/json','User-Agent':'NetPilot-Deployment-Witness/1.0'},method='POST' if payload is not None else 'GET')
 try:
  with urllib.request.urlopen(request,timeout=20) as response: return json.load(response)
 except (OSError,ValueError) as error:
  raise RuntimeError('BROKEN: Clerk witness request failed; credentials and ticket are not logged') from None

def witness(url,sha):
 if not re.fullmatch(r'[0-9a-f]{40}',sha) or not re.fullmatch(r'https://app\.netpilot\.io/sign-in\?netpilot_deploy_probe='+sha+r'\.[0-9a-f]{32}',url): raise ValueError('BROKEN: exact production nonce URL and full SHA required before authentication')
 user,key=config()
 with tempfile.TemporaryDirectory(prefix='netpilot-clerk-witness-') as private:
  os.chmod(private,0o700)
  marker=Path(private)/'owned-session'
  fd=os.open(marker,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.fchmod(fd,0o600);os.fsync(fd);os.close(fd)
  client_marker=Path(private)/'owned-client'
  fd=os.open(client_marker,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.fchmod(fd,0o600);os.fsync(fd);os.close(fd)
  previous={name:os.environ.get(name) for name in ('NETPILOT_WITNESS_TICKET','NETPILOT_WITNESS_SESSION_FILE','NETPILOT_WITNESS_CLIENT_FILE')}
  receipt=None;known_session=None
  try:
   ticket=clerk(key,'sign_in_tokens',{'user_id':user,'expires_in_seconds':180}).get('token')
   if not isinstance(ticket,str) or not ticket: raise RuntimeError('BROKEN: Clerk did not issue a single-use witness ticket')
   os.environ['NETPILOT_WITNESS_TICKET']=ticket
   os.environ['NETPILOT_WITNESS_SESSION_FILE']=str(marker)
   os.environ['NETPILOT_WITNESS_CLIENT_FILE']=str(client_marker)
   receipt=capture(url,sha)
   session=receipt.pop('owned_session',None)
   if not marker.is_file() or marker.read_text()!=session: raise RuntimeError('BROKEN: witness session ownership was not recorded')
   receipt['requestErrors']=[x for x in receipt.get('requestErrors',[]) if '__clerk_ticket' not in str(x)]
   # Never retain authentication tickets, account identifiers or cookies in receipts.
   receipt=json.loads(json.dumps(receipt).replace(ticket,'[redacted]'))
   native=[x for x in receipt.get('outboundEvents',[]) if x.get('event')=='$pageview' and x.get('url')==url and x.get('uuid')]
   if not native: raise RuntimeError('BROKEN: authenticated browser emitted no native exact-nonce pageview')
   ack=any(x.get('ack',{}).get('status')=='Ok' for x in receipt.get('ingestBodies',[]))
   if not ack: raise RuntimeError('BROKEN: native ingestion returned no real acknowledgement; HTTP200 alone is insufficient')
  except OwnedSessionFailure as error:
   known_session=error.session;raise
  finally:
   for name,value in previous.items():
    if value is None: os.environ.pop(name,None)
    else: os.environ[name]=value
   session=marker.read_text().strip() if marker.is_file() else known_session
   session=session or known_session
   if not session and client_marker.read_text().strip():
    client=client_marker.read_text().strip()
    try:
     if not re.fullmatch(r'client_[A-Za-z0-9]+',client): raise RuntimeError('invalid client')
     recovered=clerk(key,'clients/'+client,None)
     sessions=recovered['sessions']
     if recovered.get('id')!=client or not isinstance(sessions,list) or len(sessions)!=1: raise RuntimeError('ambiguous client')
     if sessions:
      item=sessions[0]
      if not isinstance(item,dict) or item.get('user_id')!=user or not re.fullmatch(r'sess_[A-Za-z0-9]+',item.get('id','')): raise RuntimeError('unexpected ownership')
      session=item['id']
    except (RuntimeError,KeyError,TypeError):
     recovery=Path.home()/'.local/share/netpilot-browser-probe/recovery';recovery.mkdir(parents=True,exist_ok=True,mode=0o700)
     if recovery.is_symlink(): raise ValueError('BROKEN: unsafe recovery directory')
     fd,path=tempfile.mkstemp(prefix='owned-client-',dir=recovery)
     with os.fdopen(fd,'w') as record:
      os.fchmod(record.fileno(),0o600);json.dump({'client_id':client,'user_id':user},record);record.flush();os.fsync(record.fileno())
     raise ValueError('BROKEN: owned client session recovery unreadable; private recovery record '+path) from None
   if session:
    if not re.fullmatch(r'sess_[A-Za-z0-9]+',session): raise RuntimeError('BROKEN: invalid owned-session recovery record')
    try: clerk(key,'sessions/'+session+'/revoke',{})
    except RuntimeError:
     # A remote outage cannot be promised away; retain the owned identity privately for retry.
     recovery=Path.home()/'.local/share/netpilot-browser-probe/recovery'
     recovery.mkdir(parents=True,exist_ok=True,mode=0o700)
     if recovery.is_symlink(): raise ValueError('BROKEN: owned-session revoke failed and recovery directory is unsafe')
     fd,path=tempfile.mkstemp(prefix='owned-session-',dir=recovery)
     with os.fdopen(fd,'w') as record:
      os.fchmod(record.fileno(),0o600);record.write(session+'\n');record.flush();os.fsync(record.fileno())
     raise ValueError('BROKEN: owned-session revoke failed; retry with the existing Clerk credential using the private recovery record '+path) from None
  receipt['owned_session_revoked']=True
  return receipt

def main():
 def interrupted(signum,frame): raise RuntimeError('owned witness interrupted')
 signal.signal(signal.SIGTERM,interrupted)
 try:
  if sys.argv[1:]==['--check-config']:
   config();print('Authenticated real-browser witness prerequisites available');return 0
  if len(sys.argv)!=3: raise ValueError('usage: browser-capture-probe.py EXACT_NONCE_URL FULL_SHA | --check-config')
  print(json.dumps(witness(*sys.argv[1:]),indent=2));return 0
 except (ValueError,RuntimeError,OSError,subprocess.SubprocessError,KeyError,StopIteration,AssertionError):
  # API and browser errors may contain sensitive request details. Log only controlled prerequisites.
  error=sys.exc_info()[1]
  message=str(error) if isinstance(error,ValueError) else 'BROKEN: authenticated browser proof failed or owned-session revoke failed; inspect private operator prerequisites'
  print(message,file=sys.stderr);return 2

if __name__=='__main__': sys.exit(main())
