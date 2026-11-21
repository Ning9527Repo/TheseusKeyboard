#!/usr/bin/env python3
from pathlib import Path
import urllib.request,urllib.error,json,os,subprocess,hashlib
R=Path(__file__).resolve().parents[1]
REPO='Ning9527Repo/TheseusKeyboard'
def api(path,data=None,method=None):
 h={'Authorization':'Bearer '+os.environ['GITHUB'],'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
 q=urllib.request.Request('https://api.github.com'+path,data=json.dumps(data).encode() if data is not None else None,headers=h,method=method)
 with urllib.request.urlopen(q,timeout=60) as f:
  s=f.read();return json.loads(s) if s else None
assert api('/user')['login']=='Ning9527Repo'
try:
 existing=api('/repos/'+REPO)
 raise SystemExit('Target repository already exists; refusing to overwrite it')
except urllib.error.HTTPError as e:
 if e.code!=404:raise
created=api('/user/repos',{'name':'TheseusKeyboard','description':'Experimental Theseus glass keyboard background for RootHide arm64e','private':False,'auto_init':False,'has_issues':True},'POST')
assert created['full_name']==REPO and created['private']==False
os.chdir(R)
def git(*a):return subprocess.check_output(['git',*a],text=True).strip()
subprocess.run(['git','init','-b','main'],check=True)
git('config','user.name','Ning');git('config','user.email','Ning9527Repo@users.noreply.github.com')
git('add','.');git('commit','-m','Initial Theseus keyboard arm64e test sources [skip ci]')
head=git('rev-parse','HEAD')
ask=R/'.git-askpass-auth'
ask.write_text('#!/bin/sh\ncase "$1" in *sername*) printf "%s\\n" x-access-token;; *) printf "%s\\n" "$GITHUB";; esac\n');ask.chmod(0o700)
try:
 git('remote','add','origin','https://github.com/'+REPO+'.git')
 env=os.environ.copy();env['GIT_ASKPASS']=str(ask);env['GIT_TERMINAL_PROMPT']='0'
 subprocess.run(['git','-c','credential.helper=','push','-u','origin','main'],check=True,env=env)
finally:ask.unlink(missing_ok=True)
remote=api('/repos/'+REPO+'/git/ref/heads/main')['object']['sha'];assert remote==head
commit=api('/repos/'+REPO+'/git/commits/'+remote)
tree=api('/repos/'+REPO+'/git/trees/'+commit['tree']['sha']+'?recursive=1')
assert not tree['truncated']
remote_files={e['path']:e['sha'] for e in tree['tree'] if e['type']=='blob'}
local={}
for line in git('ls-files','-s').splitlines():
 meta,path=line.split('\t',1);mode,sha,stage=meta.split();local[path]=sha
assert local==remote_files,(len(local),len(remote_files))
# Compute every remote git blob against actual local bytes, not just the index.
for p,sha in remote_files.items():
 b=(R/p).read_bytes();assert hashlib.sha1(('blob '+str(len(b))+'\0').encode()+b).hexdigest()==sha,p
runs=api('/repos/'+REPO+'/actions/runs?per_page=10')
assert runs['total_count']==0,'Unexpected automatic Actions run'
report={'repo':REPO,'branch':'main','commit':head,'files_verified':len(local),'actions_before_dispatch':0}
(R/'build').mkdir(exist_ok=True)
(R/'build/source-sync.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
