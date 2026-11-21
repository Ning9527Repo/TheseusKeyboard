#!/usr/bin/env python3
from pathlib import Path,PurePosixPath
import sys,io,tarfile,struct,hashlib,json,plistlib
p=Path(sys.argv[1]);d=p.read_bytes();assert d[:8]==b'!<arch>\n'
pos=8;members={}
while pos<len(d):
 h=d[pos:pos+60];assert h[58:60]==b'`\n'
 n=h[:16].decode().strip().rstrip('/');size=int(h[48:58])
 members[n]=d[pos+60:pos+60+size];pos+=60+size+(size%2)
assert members['debian-binary']==b'2.0\n'
def unpack(name):
 with tarfile.open(fileobj=io.BytesIO(members[name]),mode='r:*') as t:
  a={};dirs=set()
  for m in t:
   n=m.name.removeprefix('./').rstrip('/')
   assert not n.startswith('/') and '..' not in PurePosixPath(n).parts
   if m.isdir():dirs.add(n)
   elif m.isfile():a[n]=t.extractfile(m).read()
   else:raise AssertionError('unexpected special file '+n)
  for n in a:
   for par in PurePosixPath(n).parents:
    if str(par)!='.':assert str(par) in dirs,(n,par)
  return a
c=unpack('control.tar.gz');a=unpack('data.tar.gz')
control=c['control'].decode()
assert 'Architecture: iphoneos-arm64e\n' in control
assert not any(x in c for x in ['postinst','preinst','postrm','prerm'])
assert not any(n.startswith('var/jb/') for n in a)
base='Library/MobileSubstrate/DynamicLibraries/'
b=a[base+'TheseusKeyboard.dylib']
assert b[:4]==b'\xcf\xfa\xed\xfe'
assert struct.unpack_from('<II',b,4)==(0x100000c,0x80000002)
ncmds=struct.unpack_from('<I',b,16)[0];o=32;signature=False
for _ in range(ncmds):
 cmd,size=struct.unpack_from('<II',b,o)
 if cmd==0x1d:
  off,length=struct.unpack_from('<II',b,o+8)
  assert length>0 and off+length<=len(b);signature=True
 o+=size
assert signature,'missing code signature'
shader=a[base+'TheseusKeyboard.bundle/default.metallib']
assert shader[:4]==b'MTLB' and len(shader)>1024
info=plistlib.loads(a[base+'TheseusKeyboard.bundle/Info.plist'])
assert info['CFBundleIdentifier']=='com.ning.theseuskeyboard.resources'
for line in c['md5sums'].decode().splitlines():
 md5,n=line.split('  ',1);assert hashlib.md5(a[n]).hexdigest()==md5,n
print(json.dumps({'file':p.name,'bytes':len(d),'sha256':hashlib.sha256(d).hexdigest(),
 'arch':'arm64e/0x80000002','root_hide_layout':True,'code_signature_present':True,
 'payload_files':len(a),'metallib_bytes':len(shader),'no_install_scripts':True},indent=2))
