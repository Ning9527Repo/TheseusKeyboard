#!/usr/bin/env python3
"""macOS/Xcode only. Builds one genuine arm64e test package, no install/respring."""
from pathlib import Path
import subprocess, sys, os, plistlib, struct, hashlib, json, shutil
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
DIST=ROOT/'dist'
PKG='com.ning.theseuskeyboard'
VERSION='0.1.0-test2'
DYLIB='TheseusKeyboard'

def run(args):
 print('+',' '.join(map(str,args)),flush=True)
 return subprocess.run(list(map(str,args)),check=True)

def output(args):
 return subprocess.check_output(list(map(str,args)),text=True).strip()

def check_macho(path):
 data=Path(path).read_bytes()
 assert data[:4]==b'\xcf\xfa\xed\xfe', 'expected thin Mach-O64'
 cpu,sub=struct.unpack_from('<II',data,4)
 assert cpu==0x0100000c
 assert sub==0x80000002, f'not genuine arm64e: {sub:#x}'
 ncmds=struct.unpack_from('<I',data,16)[0]
 pos=32
 dylibs=[]
 for _ in range(ncmds):
  cmd,size=struct.unpack_from('<II',data,pos)
  if cmd in [0xc,0x80000018,0x8000001f]:
   offset=struct.unpack_from('<I',data,pos+8)[0]
   dylibs.append(data[pos+offset:pos+size].split(b'\0',1)[0].decode())
  pos+=size
 assert not any('/Users/' in p or '/opt/' in p or '/var/jb/' in p for p in dylibs),dylibs
 return {'cpu':hex(cpu),'cpusubtype':hex(sub),'dependencies':dylibs}

def main():
 assert sys.platform=='darwin','requires macos-latest/Xcode'
 BUILD.mkdir(exist_ok=True); DIST.mkdir(exist_ok=True)
 sdk=output(['xcrun','--sdk','iphoneos','--show-sdk-path'])
 print(output(['xcrun','swiftc','--version']))
 run([sys.executable,ROOT/'tools/verify_sources.py'])
 stage=BUILD/'stage'
 lib=stage/'Library/MobileSubstrate/DynamicLibraries'
 lib.mkdir(parents=True,exist_ok=True)
 bundle=lib/'TheseusKeyboard.bundle'
 bundle.mkdir(exist_ok=True)
 plistlib.dump({'CFBundleIdentifier':'com.ning.theseuskeyboard.resources','CFBundleName':'TheseusKeyboard',
  'CFBundlePackageType':'BNDL','CFBundleVersion':'1','CFBundleShortVersionString':'0.1.0'},open(bundle/'Info.plist','wb'))
 shader=ROOT/'vendor/Theseus/Sources/Shaders/TheseusShaders.metal'
 run(['xcrun','--sdk','iphoneos','metal','-mios-version-min=15.0','-c',shader,'-o',BUILD/'TheseusShaders.air'])
 run(['xcrun','--sdk','iphoneos','metallib',BUILD/'TheseusShaders.air','-o',bundle/'default.metallib'])
 assert (bundle/'default.metallib').stat().st_size>1024
 objects=[]
 for source in sorted((ROOT/'src').glob('*.m')):
  obj=BUILD/(source.stem+'.o')
  run(['xcrun','--sdk','iphoneos','clang','-arch','arm64e','-isysroot',sdk,'-miphoneos-version-min=15.0',
   '-fobjc-arc','-fblocks','-O2','-Wall','-Wextra','-Werror','-c',source,'-o',obj])
  objects.append(obj)
 selected=['Core/TheseusCapability.swift','Core/TheseusConfiguration.swift','Core/TheseusMaterialModel.swift',
  'Core/TheseusSettings.swift','Core/TheseusView.swift','Internal/DisplayLinkDriver.swift','Internal/FlexGlow.swift',
  'Internal/LensMorph.swift','Internal/NativeLens26.swift','Rendering/BackgroundCaptureDraw.swift',
  'Rendering/BlurKernelCalculator.swift','Rendering/CaptureCompensation.swift','Rendering/CaptureEdges.swift',
  'Rendering/MetalContext.swift','Rendering/ShaderTypes.swift','Rendering/TheseusRenderer.swift',
  'Rendering/TheseusTextureCache.swift','Rendering/ViewLayerCapture.swift','Rendering/VisualEffectFallback.swift']
 sources=[ROOT/'vendor/Theseus/Sources'/p for p in selected]+sorted((ROOT/'src').glob('*.swift'))
 dylib=lib/(DYLIB+'.dylib')
 args=['xcrun','--sdk','iphoneos','swiftc','-swift-version','5','-strict-concurrency=minimal','-target','arm64e-apple-ios15.0','-sdk',sdk,
  '-O','-whole-module-optimization','-parse-as-library','-emit-library','-module-name','NTKGlass',
  '-import-objc-header',ROOT/'src/NTKBridge.h','-Xlinker','-install_name','-Xlinker','@rpath/TheseusKeyboard.dylib',
  '-Xlinker','-rpath','-Xlinker','/usr/lib/swift','-o',dylib]
 for framework in ['UIKit','Foundation','QuartzCore','CoreGraphics','CoreVideo','Metal','MetalKit','Accelerate','IOSurface']:
  args+=['-framework',framework]
 run(args+sources+objects)
 architecture=check_macho(dylib)
 run(['codesign','--force','--sign','-',dylib])
 run(['codesign','--verify','--strict','--all-architectures',dylib])
 run(['xcrun','nm','-gU',dylib])
 architecture=check_macho(dylib)
 shutil.copyfile(ROOT/'package/TheseusKeyboard.plist',lib/'TheseusKeyboard.plist')
 docs=stage/'usr/share/doc'/PKG
 docs.mkdir(parents=True,exist_ok=True)
 for n in ['LICENSE','NOTICE']:
  shutil.copyfile(ROOT/'vendor/Theseus'/n,docs/n)
 shutil.copyfile(ROOT/'TESTING.md',docs/'TESTING.md')
 control=BUILD/'control'
 control.mkdir(exist_ok=True)
 shutil.copyfile(ROOT/'package/control',control/'control')
 lines=[]
 for p in sorted(stage.rglob('*')):
  if p.is_file():
   lines.append(hashlib.md5(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(stage)))
 (control/'md5sums').write_text('\n'.join(lines)+'\n')
 deb=DIST/f'{PKG}_{VERSION}_iphoneos-arm64e.deb'
 run([sys.executable,ROOT/'tools/mkdeb.py',stage,control,deb])
 run([sys.executable,ROOT/'tools/verify_package.py',deb])
 report={'package':deb.name,'sha256':hashlib.sha256(deb.read_bytes()).hexdigest(),'size':deb.stat().st_size,
  'dylib_sha256':hashlib.sha256(dylib.read_bytes()).hexdigest(),'architecture':architecture,
  'source_commit':output(['git','rev-parse','HEAD']),'codesign_strict':True,'runtime_tested':False,
  'experimental_backdrop_capture':True,'automatic_respring':False}
 (DIST/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
 (DIST/'SHA256SUMS').write_text(report['sha256']+'  '+deb.name+'\n')
 print(json.dumps(report,indent=2))

if __name__=='__main__': main()
