#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re,plistlib
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'vendor/Theseus/UPSTREAM.json').read_text())
assert m['commit']=='71ca1c127a4e7fe3387361f160c4890dbd427f66'
for f in m['files']:
 p=r/'vendor/Theseus/Sources'/f['path']
 assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256'],p
assert not list((r/'vendor/Theseus/Sources').glob('Components/*'))
s=(r/'src/NTKGlassBackground.swift').read_text()
for literal in ['config.blur.radius = 18','config.refraction.edgeWidth = 0','config.refraction.interiorAverage = 80','glass.continuousUpdate = false','glass.setCaptureExcludedViews([self])']:
 assert literal in s,literal
c=(r/'src/NTKTabBarChrome.swift').read_text()
for name in ['iOS27ChromeLight','iOS27ChromeDark']:
 knots=re.search(name+r' = ChromeCurve\(knots: \[(.*?)\]',c).group(1).split(',')
 assert len(knots)==16
obj=(r/'src/NTKKeyboardAttachment.m').read_text()
assert 'if (gNTKInstalled) return;' in obj
for forbidden in ['system(', 'kill(', 'posix_spawn(', 'setEffect:', 'setImageForCorners:']:
 assert forbidden not in obj
for n in re.findall(r'^static (?:void|BOOL) (NTK\w+)\(',obj,re.M):
 definition=obj.index(' '+n+'(')
 assert obj.find(n+'(')>=definition,n
control=(r/'package/control').read_text()
assert 'Architecture: iphoneos-arm64e\n' in control
assert 'Maintainer: Ning&Vadim Drobinin\n' in control
f=plistlib.loads((r/'package/TheseusKeyboard.plist').read_bytes())
assert f['Filter']
assert 'workflow_dispatch:' in (r/'.github/workflows/build.yml').read_text()
workflow=(r/'.github/workflows/build.yml').read_text()
assert '\n  push:' not in workflow and '\n  pull_request:' not in workflow
print('SOURCE_VERIFICATION_OK',len(m['files']),'upstream files intact')
