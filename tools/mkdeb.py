#!/usr/bin/env python3
"""Portable deterministic Debian ar writer (never use macOS ar)."""
import sys, io, tarfile, gzip
from pathlib import Path
stage,control,out=map(Path,sys.argv[1:])
def tar_dir(root):
 buf=io.BytesIO()
 with tarfile.open(fileobj=buf,mode='w',format=tarfile.GNU_FORMAT) as t:
  for p in sorted(root.rglob('*'),key=lambda p:(len(p.parts),str(p))):
   i=t.gettarinfo(str(p),arcname='./'+str(p.relative_to(root)))
   i.uid=i.gid=0;i.uname=i.gname='root';i.mtime=0
   i.mode=0o755 if p.is_dir() else (0o755 if p.name.endswith('.dylib') else 0o644)
   if p.is_file():
    with p.open('rb') as f:t.addfile(i,f)
   else:t.addfile(i)
 return gzip.compress(buf.getvalue(),mtime=0)
with out.open('wb') as f:
 f.write(b'!<arch>\n')
 for name,data in [('debian-binary',b'2.0\n'),('control.tar.gz',tar_dir(control)),('data.tar.gz',tar_dir(stage))]:
  h=f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n'.encode()
  assert len(h)==60
  f.write(h);f.write(data)
  if len(data)%2:f.write(b'\n')
print(out,out.stat().st_size)
