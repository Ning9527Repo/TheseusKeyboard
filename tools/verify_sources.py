#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re,plistlib
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'vendor/Theseus/UPSTREAM.json').read_text())
assert m['commit']=='71ca1c127a4e7fe3387361f160c4890dbd427f66'
integration=json.loads((r/'vendor/Theseus/INTEGRATION.json').read_text())
patched={f['path']:f for f in integration['files']}
assert set(patched)=={'Core/TheseusView.swift','Rendering/TheseusRenderer.swift'}
for f in m['files']:
 p=r/'vendor/Theseus/Sources'/f['path']
 expected=patched.get(f['path'],{}).get('integrated_sha256',f['sha256'])
 if f['path'] in patched: assert patched[f['path']]['upstream_sha256']==f['sha256']
 assert hashlib.sha256(p.read_bytes()).hexdigest()==expected,p
assert not list((r/'vendor/Theseus/Sources').glob('Components/*'))
s=(r/'src/NTKGlassBackground.swift').read_text()
for literal in ['config.blur.radius = 18','config.refraction.edgeWidth = 0','config.refraction.interiorAverage = 80','glass.continuousUpdate = false','glass.setCaptureExcludedViews([self])']:
 assert literal in s,literal
c=(r/'src/NTKTabBarChrome.swift').read_text()
for name in ['iOS27ChromeLight','iOS27ChromeDark']:
 knots=re.search(name+r' = ChromeCurve\(knots: \[(.*?)\]',c).group(1).split(',')
 assert len(knots)==16
obj='\n'.join(p.read_text() for p in (r/'src').glob('*.m'))
native=(r/'src/NTKNativeBackdrop.m').read_text()
assert 'if (gNTKInstalled) return;' in native
assert '_dyld_register_func_for_add_image(NTKImageAdded)' in native
assert 'class_addMethod(cls, selector' in native
assert native.index('gNTKInstalled = YES;') < native.index('NTKReplaceLocal(cls, @selector(layoutSubviews)')
for forbidden in ['system(', 'kill(', 'posix_spawn(', 'setImageForCorners:', 'MSHookMessageEx', 'removeFromSuperview']:
 assert forbidden not in obj,forbidden
capture=(r/'src/NTKWindowCapture.swift').read_text()
assert 'window.drawHierarchy(in: window.bounds' in capture
assert 'CaptureCompensation' not in capture
assert 'write' not in capture and 'pngData' not in capture
renderer=(r/'vendor/Theseus/Sources/Rendering/TheseusRenderer.swift').read_text()
assert 'drawable.addPresentedHandler' in renderer
assert 'overlay.convert(inOverlay, to: contentWindow)' in renderer
assert 'NTKCurrentKeyboardClient' in native
control=(r/'package/control').read_text()
assert 'Architecture: iphoneos-arm64e\n' in control
assert 'Maintainer: Ning&Vadim Drobinin\n' in control
f=plistlib.loads((r/'package/TheseusKeyboard.plist').read_bytes())
assert f['Filter']
assert 'workflow_dispatch:' in (r/'.github/workflows/build.yml').read_text()
workflow=(r/'.github/workflows/build.yml').read_text()
assert '\n  push:' not in workflow and '\n  pull_request:' not in workflow
print('SOURCE_VERIFICATION_OK',len(m['files'])-len(patched),'upstream files intact;',len(patched),'integration patches verified')
