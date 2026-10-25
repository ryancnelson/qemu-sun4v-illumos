#!/usr/bin/env python3
"""Compile actual IDE node construction, with host OF/property stubs; no firmware build."""
from pathlib import Path
import subprocess, tempfile, hashlib, json
root=Path(__file__).resolve().parents[1]
stub=r"""
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef int phandle_t;
enum {ide_type_ata,ide_type_atapi,ide_type_unknown};
enum {ide_media_disk,ide_media_cdrom,ide_media_floppy,ide_media_optical};
struct ide_drive {int type,media;};
static int prop_len, writes;
static unsigned char prop[64];
static void event(const char *s) {printf("%s|",s);}
static void fword(const char *s){event(s);}
static void push_str(const char *s){event(s);}
static int get_cur_dev(void){return 7;}
static void set_int_property(int n,const char *s,int v){if(n!=7||v!=1)abort();event(s);}
static char *get_property(int n,const char*s,int *len) {
 if(n!=7||strcmp(s,"compatible"))abort();
 *len=prop_len;
 /* An existing empty property may have a null data pointer. */
 return prop_len<=0?NULL:(char*)prop;
}
static void set_property(int n,const char*s,const char*v,int len){
 if(n!=7||strcmp(s,"compatible")||len<0||len>64)abort();
 memcpy(prop,v,len);prop_len=len;writes++;
}
static void feval(const char*s){event(s);}
#define pointer2cell(p) ((uintptr_t)(p))
#define PUSH(p) do {if((p)!=(uintptr_t)drive)abort();event("drive-pointer");}while(0)
#define BIND_NODE_METHODS(n,m) event("ob_ide-methods")
static const char *get_path_from_ph(int n){if(n!=7)abort();return "/ide/disk@1";}
static void set_ide_alias(const char*s){event("ide-alias");event(s);}
static void set_cd_alias(const char*s){event("cd-alias");event(s);}
static void set_hd_alias(const char*s){event("hd-alias");event(s);}
int main(int argc,char **argv){
 if(argc!=4)return 2;
 struct ide_drive drv={atoi(argv[1]),atoi(argv[2])},*drive=&drv;
 const char *names[]={"disk","cdrom","floppy","mo"};
 const char *media=names[drv.media];
 int j=1,dnode; char nodebuff[128];
 int preset=atoi(argv[3]);
 prop_len=preset==0?-1:preset==1?0:preset==2?13:4;
 if(preset==2)memcpy(prop,"vendor,x\0dad\0",13);
 if(preset==3)memcpy(prop,"dad",4);
"""
end=r"""
 printf("\n%d %d ",prop_len,writes);
 for(int k=0;k<prop_len;k++)printf("%02x",prop[k]);
 puts("");return 0;
}
"""
def block(s):
 a=s.index('\t\t\tfword("new-device");',s.index('int ob_ide_init'))
 b=s.index('\n\t\t}',a)
 text=s[a:b]
 assert 'set_hd_alias(nodebuff);' in text
 return text
base=(root/'baseline/drivers/ide.c').read_text()
cand=(root/'candidate/drivers/ide.c').read_text()
# Removing exactly the added SPARC block must restore ALL original source bytes.
a=cand.index('#ifdef CONFIG_SPARC64',cand.index('int ob_ide_init'))
# Locate our uniquely marked block, not any earlier architecture conditional.
mark=cand.index('/* Let Solaris preload')
a=cand.rfind('#ifdef CONFIG_SPARC64',0,mark)
b=cand.index('#endif\n\n',mark)+len('#endif\n\n')
assert cand[:a]+cand[b:]==base
passed=0; expected_baseline_failures=0
with tempfile.TemporaryDirectory(prefix='dad-node-tests-') as tmp:
 bins={}
 for variant,src in [('before',base),('after',cand)]:
  for sparc in (False,True):
   c=Path(tmp)/('%s-%s.c'%(variant,sparc));exe=c.with_suffix('')
   c.write_text(stub+block(src)+end)
   command=['clang','-std=c99','-fsanitize=address,undefined','-fno-omit-frame-pointer','-g']
   if sparc:command+=['-DCONFIG_SPARC64']
   subprocess.run(command+[str(c),'-o',str(exe)],check=True)
   bins[variant,sparc]=exe
 for sparc in (False,True):
  for typ in range(3):
   for med in range(4):
    for preset in range(4):
     results={}
     for variant in ('before','after'):
      p=subprocess.run([str(bins[variant,sparc]),str(typ),str(med),str(preset)],capture_output=True,text=True,check=True)
      assert not p.stderr,p.stderr
      results[variant]=p.stdout.splitlines()
     before,after=results['before'],results['after']
     assert before[0]==after[0],(sparc,typ,med,preset,'name/method/alias/stack events changed')
     eligible=sparc and typ==0 and med==0 and preset==0
     if eligible:
      assert before[1]=='-1 0 ',before
      assert after[1]=='4 1 64616400',after
      expected_baseline_failures+=1
      print('FAIL-BEFORE / PASS-AFTER: absent SPARC64 ATA disk compatible -> dad NUL')
     else:
      assert before==after,(sparc,typ,med,preset,before,after)
     passed+=1
 assert expected_baseline_failures==1
 print('PASS: %d differential cases; actual extracted node code; ASan/UBSan; property bytes and all original node/alias events checked'%passed)
 print('PASS: whole source outside added block byte-identical (including other IDE creation path)')
