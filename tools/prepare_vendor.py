from pathlib import Path
import shutil, hashlib, json
root=Path(__file__).resolve().parents[1]
ref=root/'reference/Theseus'
out=root/'vendor/Theseus'
if (out/'INTEGRATION.json').exists():
 raise SystemExit('Integration patches are present; do not overwrite the verified vendor tree')
files=[]
for directory in ['Core','Rendering','Internal','Animation']:
 files.extend(sorted((ref/'Sources/Theseus'/directory).glob('*.swift')))
files.append(ref/'Sources/Theseus/Shaders/TheseusShaders.metal')
manifest=[]
for p in files:
 rel=p.relative_to(ref/'Sources/Theseus')
 dest=out/'Sources'/rel
 dest.parent.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(p,dest)
 manifest.append({'path':str(rel),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for n in ['LICENSE','NOTICE']:
 shutil.copyfile(ref/n,out/n)
(out/'UPSTREAM.json').write_text(json.dumps({'repository':'https://github.com/valzevul/Theseus','commit':'71ca1c127a4e7fe3387361f160c4890dbd427f66','files':manifest},indent=2)+'\n')
print('Vendored',len(files),'files; no demo or tab controls included')
