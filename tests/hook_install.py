#!/usr/bin/env python3
"""Extract the real local-override installer and exercise it on GNU ObjC runtime.
This tests method ownership/idempotence, not UIKit behavior or arm64e PAC.
"""
from pathlib import Path
import re,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'src/NTKNativeBackdrop.m').read_text()
start=s.index('static void NTKReplaceLocal(')
end=s.index('\nstatic void NTKDiscoverBackdrops',start)
installer=s[start:end]
start=s.index('static void NTKTryInstallBackdrop(')
end=s.index('\nstatic void NTKImageAdded',start)
body=s[start:end]
assert body.index('if (gNTKInstalled) return;') < body.index('gNTKInstalled = YES;') < body.index('NTKReplaceLocal(cls,')
code='''#include <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
static int baseCalls, childCalls, wrapperCalls;
static IMP saved;
static void base(id self, SEL cmd){(void)self;(void)cmd;++baseCalls;}
static void child(id self, SEL cmd){(void)self;(void)cmd;++childCalls;}
static void replacement(id self,SEL cmd){++wrapperCalls;((void(*)(id,SEL))saved)(self,cmd);}
'''+installer+'''
int main(void){
 Class root=objc_allocateClassPair(Nil,"NTKTestRoot",0);assert(root);objc_registerClassPair(root);
 SEL sel=sel_registerName("layoutSubviews");
 class_addMethod(root,sel,(IMP)base,"v@:");
 Class sub=objc_allocateClassPair(root,"NTKTestSub",0);objc_registerClassPair(sub);
 static int installed;
 for(int n=0;n<10000;++n){
  if(!installed){installed=1;NTKReplaceLocal(sub,sel,(IMP)replacement,&saved);}
  assert(saved==(IMP)base);
  assert(method_getImplementation(class_getInstanceMethod(root,sel))==(IMP)base);
  assert(method_getImplementation(class_getInstanceMethod(sub,sel))==(IMP)replacement);
 }
 ((void(*)(id,SEL))method_getImplementation(class_getInstanceMethod(sub,sel)))(nil,sel);
 assert(baseCalls==1 && wrapperCalls==1);
 Class own=objc_allocateClassPair(root,"NTKTestOwn",0);objc_registerClassPair(own);
 class_addMethod(own,sel,(IMP)child,"v@:");
 NTKReplaceLocal(own,sel,(IMP)replacement,&saved);
 assert(saved==(IMP)child);
 ((void(*)(id,SEL))method_getImplementation(class_getInstanceMethod(own,sel)))(nil,sel);
 assert(childCalls==1 && wrapperCalls==2 && baseCalls==1);
 puts("HOOK_RUNTIME_OK inherited+own method; 10000 install guard iterations");
 return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='ntk-hook-',dir='/tmp') as temp:
 p=Path(temp);(p/'test.m').write_text(code)
 inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
 subprocess.run(['clang','-x','objective-c','-I'+inc,str(p/'test.m'),'-lobjc','-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
