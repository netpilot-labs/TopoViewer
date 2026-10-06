#!/usr/bin/env python3
"""Task-owned empty-profile browser receipt; use only the watcher's exact nonce URL."""
from pathlib import Path
import json, os, re, shutil, signal, subprocess, sys, tempfile, time, urllib.request
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
  args=[browser_path,'--headless=new','--remote-debugging-port=0','--disable-gpu','--use-mock-keychain','--password-store=basic','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-extensions','--disable-sync','--user-data-dir='+temporary,'about:blank']
  browser_stderr=(Path(temporary)/'browser.stderr').open('w')
  browser=subprocess.Popen(args,stdout=subprocess.DEVNULL,stderr=browser_stderr,start_new_session=True)
  try:
   active=Path(temporary)/'DevToolsActivePort'; deadline=time.monotonic()+20
   while not active.exists() and time.monotonic()<deadline:
    if browser.poll() is not None: break
    time.sleep(.2)
   if not active.exists(): raise RuntimeError('isolated Chrome CDP unavailable')
   port=active.read_text().splitlines()[0]
   if not port.isdigit() or not 0<int(port)<65536: raise RuntimeError('invalid local browser port')
   targets=json.load(urllib.request.urlopen('http://127.0.0.1:'+port+'/json/list',timeout=3))
   endpoint=next(target['webSocketDebuggerUrl'] for target in targets if target['type']=='page')
   if not endpoint.startswith('ws://127.0.0.1:'+port+'/'): raise RuntimeError('unexpected browser debugging endpoint')
   driver=Path(temporary)/'receipt.mjs'
   driver.write_text('''
 import assert from 'node:assert/strict';
 const [endpoint,url,sha]=process.argv.slice(2);
 const deadline=setTimeout(()=>{console.error('browser receipt timed out');process.exit(1)},70000);
const ws=new WebSocket(endpoint); let id=0; const pending=new Map();const scripts=new Map();const ingest=[];
 const send=(method,params={})=>new Promise((resolve,reject)=>{const n=++id;const timer=setTimeout(()=>{pending.delete(n);reject(new Error(method+' timed out'))},20000);pending.set(n,{resolve,reject,timer});ws.send(JSON.stringify({id:n,method,params}))});
 const ready=new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
 let loaded;const load=new Promise(resolve=>loaded=resolve);
 ws.onmessage=e=>{const data=JSON.parse(e.data);if(data.id){const p=pending.get(data.id);if(!p)return;pending.delete(data.id);clearTimeout(p.timer);data.error?p.reject(new Error(JSON.stringify(data.error))):p.resolve(data.result);return}
  if(data.method==='Page.loadEventFired')loaded();
  if(data.method==='Network.responseReceived'){const {type,response}=data.params;if(type==='Script')scripts.set(response.url,response.status);if(response.url.startsWith('https://app.netpilot.io/ingest/'))ingest.push({url:response.url.split('?')[0],status:response.status})}};
 let status=0;
 try {
  await ready;await send('Network.enable');await send('Network.setCacheDisabled',{cacheDisabled:true});await send('Page.enable');
  const navigation=await send('Page.navigate',{url});assert.equal(navigation.errorText,undefined);
  await Promise.race([load,new Promise((_,reject)=>setTimeout(()=>reject(new Error('page load timed out')),35000))]);
  const result=await send('Runtime.evaluate',{expression:"(async()=>({url:location.href,version:await fetch('/version.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw new Error('version HTTP '+r.status);return r.json()})}))()",awaitPromise:true,returnByValue:true});
  assert.equal(result.exceptionDetails,undefined);const receipt=result.result.value;assert.equal(receipt.url,url);assert.equal(receipt.version.version,sha);
  // Let the production analytics client's own queue flush. No synthetic capture call.
  await new Promise(resolve=>setTimeout(resolve,15000));
  const loadedScripts=[...scripts].map(([url,status])=>({url,status}));assert.ok(loadedScripts.some(x=>x.url.startsWith('https://app.netpilot.io/_next/static/')));assert.ok(loadedScripts.every(x=>x.status>=200&&x.status<400));
  console.log(JSON.stringify({isolated_empty_cache:true,verified_at:new Date().toISOString(),...receipt,loaded_scripts:loadedScripts,analytics_responses:ingest},null,2));
 } catch(error) {console.error(String(error));status=1;}
finally {clearTimeout(deadline);for(const p of pending.values())clearTimeout(p.timer);ws.close();setTimeout(()=>process.exit(status),50)}
 ''')
   result=subprocess.run([node,str(driver),endpoint,url,sha],capture_output=True,text=True,timeout=80)
   if result.returncode:raise RuntimeError(result.stderr)
   receipt=json.loads(result.stdout)
   assert receipt['version']['version']==sha and receipt['url']==url
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

def main():
 if len(sys.argv)!=3:
  print('usage: browser-capture-probe.py EXACT_NONCE_URL FULL_SHA',file=sys.stderr);return 2
 try:
  print(json.dumps(capture(*sys.argv[1:]),indent=2));return 0
 except (ValueError,RuntimeError,OSError,subprocess.SubprocessError,KeyError,StopIteration,AssertionError) as error:
  print('browser-capture-probe: '+str(error),file=sys.stderr);return 1

if __name__=='__main__': sys.exit(main())
