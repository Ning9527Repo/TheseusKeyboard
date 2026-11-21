#!/usr/bin/env python3
from pathlib import Path
import urllib.request,urllib.error,json,os,sys,subprocess,hashlib,zipfile
R=Path(__file__).resolve().parents[1];B=R/'build';B.mkdir(exist_ok=True)
REPO='Ning9527Repo/TheseusKeyboard'
def api(p,data=None,method=None):
 req=urllib.request.Request('https://api.github.com'+p,headers={'Authorization':'Bearer '+os.environ['GITHUB'],'Accept':'application/vnd.github+json'},data=json.dumps(data).encode() if data is not None else None,method=method)
 with urllib.request.urlopen(req,timeout=60) as f:
  b=f.read();return json.loads(b) if b else None

def verify():
 assert api('/user')['login']=='Ning9527Repo'
 head=subprocess.check_output(['git','-C',str(R),'rev-parse','HEAD'],text=True).strip()
 assert api('/repos/'+REPO+'/git/ref/heads/main')['object']['sha']==head
 commit=api('/repos/'+REPO+'/git/commits/'+head)
 tree=api('/repos/'+REPO+'/git/trees/'+commit['tree']['sha']+'?recursive=1')
 assert not tree['truncated']
 remote={x['path']:x['sha'] for x in tree['tree'] if x['type']=='blob'}
 entries=subprocess.check_output(['git','-C',str(R),'ls-files','-s'],text=True).splitlines()
 local={line.split('\t',1)[1]:line.split()[1] for line in entries}
 assert local==remote
 for p,sha in remote.items():
  b=(R/p).read_bytes();assert hashlib.sha1(('blob '+str(len(b))+'\0').encode()+b).hexdigest()==sha,p
 report={'repo':REPO,'branch':'main','commit':head,'files_verified':len(remote)}
 (B/'source-sync.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
 return head

def dispatch():
 head=verify();receipt=B/'dispatch.json'
 assert not receipt.exists(),'Dispatch already recorded; no automatic retry permitted'
 assert api('/repos/'+REPO+'/actions/runs?per_page=10')['total_count']==0
 receipt.write_text(json.dumps({'state':'requesting','commit':head}))
 api('/repos/'+REPO+'/actions/workflows/build.yml/dispatches',{'ref':'main'},'POST')
 receipt.write_text(json.dumps({'state':'accepted','http':204,'commit':head},indent=2)+'\n')
 print('SINGLE_DISPATCH_ACCEPTED',head)

def status():
 head=json.loads((B/'dispatch.json').read_text())['commit']
 runs=api('/repos/'+REPO+'/actions/runs?per_page=20')['workflow_runs']
 matches=[x for x in runs if x['head_sha']==head and x['event']=='workflow_dispatch']
 assert len(matches)<=1,'Unexpected multiple runs'
 if not matches:print('AWAITING_RUN');return
 x=matches[0];(B/'run.json').write_text(json.dumps(x,indent=2)+'\n')
 print(json.dumps({k:x.get(k) for k in ['id','status','conclusion','run_attempt','html_url','head_sha']}))
 jobs=api('/repos/'+REPO+'/actions/runs/'+str(x['id'])+'/jobs')['jobs']
 print(json.dumps([{'name':j['name'],'status':j['status'],'conclusion':j['conclusion'],'steps':[{'name':s['name'],'status':s['status'],'conclusion':s['conclusion']} for s in j.get('steps',[])]} for j in jobs]))

class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):return None

def signed_download(path,dest):
 opener=urllib.request.build_opener(NoRedirect)
 req=urllib.request.Request('https://api.github.com'+path,headers={'Authorization':'Bearer '+os.environ['GITHUB'],'Accept':'application/vnd.github+json'})
 try:
  response=opener.open(req,timeout=60)
 except urllib.error.HTTPError as e:
  assert e.code in [301,302,303,307,308];url=e.headers['Location']
  response=urllib.request.urlopen(url,timeout=120)
 with response,open(dest,'wb') as f:
  while True:
   b=response.read(1024*1024)
   if not b:break
   f.write(b)

def download():
 x=json.loads((B/'run.json').read_text());assert x['conclusion']=='success' and x['run_attempt']==1
 a=api('/repos/'+REPO+'/actions/runs/'+str(x['id'])+'/artifacts')['artifacts']
 assert len(a)==1 and not a[0]['expired']
 info=a[0];dest=B/'official-artifact.zip'
 signed_download('/repos/'+REPO+'/actions/artifacts/'+str(info['id'])+'/zip',dest)
 digest=hashlib.sha256(dest.read_bytes()).hexdigest()
 assert info.get('digest')=='sha256:'+digest,(digest,info.get('digest'))
 out=Path('/var/minis/attachments')/('theseus-keyboard-'+str(x['id']));out.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(dest) as z:
  assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
  z.extractall(out)
 (B/'artifact-receipt.json').write_text(json.dumps({'run_id':x['id'],'artifact':info,'verified_sha256':digest,'extracted_to':str(out)},indent=2)+'\n')
 print(json.dumps({'run_id':x['id'],'artifact_id':info['id'],'zip_sha256':digest,'files':[str(p) for p in out.rglob('*') if p.is_file()]}))

{'verify':verify,'dispatch':dispatch,'status':status,'download':download}[sys.argv[1]]()
