from pathlib import Path
import json,hashlib,subprocess
r=Path(__file__).resolve().parents[1]
base='8b74cf8d0d9dfc70ca303dabeff77449b082d6cd'
files=['Core/TheseusView.swift','Rendering/TheseusRenderer.swift']
report={'base_commit':base,'upstream_commit':'71ca1c127a4e7fe3387361f160c4890dbd427f66',
 'reason':'Only content-window input, window coordinate conversion and drawable-presented callback; shader and material computations unchanged.',
 'files':[]}
for name in files:
 p=r/'vendor/Theseus/Sources'/name
 old=subprocess.check_output(['git','-C',str(r),'show',base+':'+str(p.relative_to(r))])
 report['files'].append({'path':name,'upstream_sha256':hashlib.sha256(old).hexdigest(),
                        'integrated_sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(r/'vendor/Theseus/INTEGRATION.json').write_text(json.dumps(report,indent=2)+'\n')
patch=subprocess.check_output(['git','-C',str(r),'diff',base,'--',*[str((r/'vendor/Theseus/Sources'/p).relative_to(r)) for p in files]])
(r/'vendor/Theseus/keyboard-integration.patch').write_bytes(patch)
print('Recorded',len(files),'integration files; original hashes retained in UPSTREAM.json')
