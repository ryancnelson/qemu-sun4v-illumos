#!/usr/bin/env python3
"""Compile the real ob_ide_init body with recording firmware/I/O stubs."""
import pathlib, subprocess, sys
D=pathlib.Path(__file__).resolve().parent
src=pathlib.Path(sys.argv[1]).read_text()
body=src[src.index('int ob_ide_init('):src.index('\nvoid ob_ide_quiesce(')]
helpers=''
if 'static void ob_ide_sun4u_decodeunit' in src:
 start=src.index('#ifdef CONFIG_SPARC64\n/* Same two-cell')
 helpers=src[start:src.index('static void set_cd_alias',start)]
prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
typedef uint32_t u32; typedef int phandle_t;
#define IDE_NUM_CHANNELS 2
#define IDE_MAX_CHANNELS 2
#define DEV_NAME "ide"
#define DEV_TYPE "ide"
#define IDE_DPRINTF(...) ((void)0)
#define __cpu_to_be32 htonl
#define pointer2cell(p) ((uintptr_t)(p))
#define BIND_NODE_METHODS(n,m) bind_methods(n,#m)
enum {ide_media_disk,ide_media_cdrom,ide_media_floppy,ide_media_optical};
enum {ide_type_ata,ide_type_atapi};
struct ide_channel;
struct ide_drive {int present,unit,bs,nr,media,type;char *model;struct ide_channel *channel;};
struct ide_channel {int mmio,io_regs[10],selected,present;void *obide_inb,*obide_insw,*obide_outb,*obide_outsw;struct ide_drive drives[2];};
void *ob_ide_inb,*ob_ide_insw,*ob_ide_outb,*ob_ide_outsw;
struct node {int parent,acells,scells,target,lun;char name[24],type[24],class_prop[24],methods[32];unsigned char reg[24];int reglen,compatlen;unsigned char compat[32];uintptr_t drive;};
struct node nodes[32]; int cur=0,nn=1,current_channel=7,scenario,probe_index,preset;
uintptr_t tos; char string[80]; char disk_alias[128],cd_alias[128];
void PUSH(uintptr_t x){tos=x;}
void push_str(const char *s){snprintf(string,sizeof string,"%s",s);}
phandle_t get_cur_dev(void){return cur;}
void bind_methods(int n,const char*s){snprintf(nodes[n].methods,32,"%s",s);}
void fword(const char*s){
 if(!strcmp(s,"new-device")){int p=cur;cur=nn++;nodes[cur].parent=p;nodes[cur].compatlen=preset==0?-1:preset==1?0:preset==2?13:4;if(preset==2)memcpy(nodes[cur].compat,"vendor,x\0dad\0",13);if(preset==3)memcpy(nodes[cur].compat,"dad",4);}
 else if(!strcmp(s,"finish-device"))cur=nodes[cur].parent;
 else if(!strcmp(s,"device-name"))snprintf(nodes[cur].name,24,"%s",string);
 else if(!strcmp(s,"device-type"))snprintf(nodes[cur].type,24,"%s",string);
 else if(strcmp(s,"is-deblocker")){fprintf(stderr,"unexpected fword %s\n",s);abort();}
}
void feval(const char*s){if(!strcmp(s,"value drive"))nodes[cur].drive=tos;else assert(!strcmp(s,"value chan"));}
char *get_property(int n,const char*k,int*z){assert(!strcmp(k,"compatible"));*z=nodes[n].compatlen;return *z<=0?NULL:(char*)nodes[n].compat;}
void set_property(int n,const char*k,const char*v,int z){
 if(!strcmp(k,"reg")){assert(z<=24);memcpy(nodes[n].reg,v,z);nodes[n].reglen=z;}
 else if(!strcmp(k,"class_prop"))snprintf(nodes[n].class_prop,24,"%s",v);
 else if(!strcmp(k,"type"))snprintf(nodes[n].type,24,"%s",v);
 else if(!strcmp(k,"compatible")){assert(z<=32);memcpy(nodes[n].compat,v,z);nodes[n].compatlen=z;}
 else assert(!strcmp(k,"interrupts"));
}
void set_int_property(int n,const char*k,int v){
 if(!strcmp(k,"#address-cells"))nodes[n].acells=v;
 else if(!strcmp(k,"#size-cells"))nodes[n].scells=v;
 else if(!strcmp(k,"target"))nodes[n].target=v;
 else if(!strcmp(k,"lun"))nodes[n].lun=v;
 else if(!strcmp(k,"reg")){uint32_t b=htonl(v);set_property(n,k,(char*)&b,4);}
 else abort();
}
void ob_ide_probe(struct ide_channel*c){
 int ch=probe_index++;
 if(scenario==2&&ch==0){c->present=0;return;}
 for(int u=0;u<2;u++){struct ide_drive*d=&c->drives[u];d->present=1;d->media=((scenario==1||scenario==4)&&ch==1&&u==0)?ide_media_cdrom:ide_media_disk;d->type=d->media==ide_media_cdrom?ide_type_atapi:ide_type_ata;d->model=scenario==4?"EMPTY ATAPI IDENTIFY SUCCEEDS":"fixture";}
 if(scenario==3)c->drives[0].present=c->drives[1].present=0;
 if(scenario>=5 && ch==1){c->drives[0].type=ide_type_atapi;c->drives[0].media=scenario==5?ide_media_floppy:scenario==6?ide_media_optical:ide_media_disk;}
}
void ob_ide_identify_drives(struct ide_channel*c){(void)c;}
char *get_path_from_ph(int n){static char p[128];snprintf(p,sizeof p,"node%d-parent%d-%s",n,nodes[n].parent,nodes[n].name);return p;}
void set_ide_alias(const char*p){(void)p;}
void set_hd_alias(const char*p){if(!*disk_alias)strcpy(disk_alias,p);}
void set_cd_alias(const char*p){if(!*cd_alias)strcpy(cd_alias,p);}
struct method {const char *name;void (*fn)(int*);};
#define NODE_METHODS(n) struct method n[]
void ob_ide_ctrl_open(int*x){} void ob_ide_ctrl_close(int*x){}
void ob_ide_dma_alloc(int*x){} void ob_ide_dma_free(int*x){}
void ob_ide_dma_map_in(int*x){} void ob_ide_dma_map_out(int*x){} void ob_ide_dma_sync(int*x){}
'''
suffix=r'''
int main(int argc,char**argv){scenario=argc>1?atoi(argv[1]):0;preset=argc>2?atoi(argv[2]):0;
 ob_ide_init("/pci/ide",0x100,0x200,0x300,0x400);
 int direct=0,legacy=0,drives=0;
 for(int n=1;n<nn;n++)if(nodes[n].drive){
  struct ide_drive*d=(void*)nodes[n].drive;drives++;
  int expected=preset==0?-1:preset==1?0:preset==2?13:4;
#ifdef CONFIG_SPARC64
  if(preset==0&&d->type==ide_type_ata&&d->media==ide_media_disk)expected=4;
#endif
  assert(nodes[n].compatlen==expected);
  if(expected==4)assert(!memcmp(nodes[n].compat,"dad",4));
  if(expected==13)assert(!memcmp(nodes[n].compat,"vendor,x\0dad\0",13));

  assert(d->channel->io_regs[0]==(d->nr<2?0x100:0x300));assert(d->unit==d->nr%2);
  if(nodes[n].parent==0){direct++;assert(!strcmp(nodes[n].name,"dad"));assert(nodes[n].target==d->nr);assert(nodes[n].lun==0);assert(!strcmp(nodes[n].class_prop,"ata"));assert(nodes[n].reglen==8);uint32_t v;memcpy(&v,nodes[n].reg,4);assert(ntohl(v)==(unsigned)d->nr);memcpy(&v,nodes[n].reg+4,4);assert(v==0);}
  else {legacy++;assert(!strcmp(nodes[nodes[n].parent].name,"ide"));assert(nodes[n].reglen==4);}
 }
 assert(cur==0&&drives==(scenario==2?2:scenario==3?0:4));
#ifdef CONFIG_SPARC64
 if(scenario==0||scenario==2){assert(direct==drives&&legacy==0);assert(nodes[0].acells==2&&nodes[0].scells==0);}
 else {assert(direct==0&&legacy==drives&&nodes[0].acells==0);if(scenario==1||scenario==4)assert(*cd_alias);}
 if(scenario==4)puts("APPLICABILITY FALSIFIED: empty ATAPI present; zero direct ATA nodes; legacy ancestry remains");
#else
 assert(direct==0&&legacy==drives);
#endif
 puts("PASS real constructor: node ancestry/properties/drive identity/I/O mapping");
}
'''
unit=D/'constructor.generated.c';unit.write_text(prefix+helpers+body+suffix)
for arch in ('sun4u','legacy'):
 exe=D/('constructor-'+arch)
 cmd=['cc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-std=c99','-Werror=implicit-function-declaration','-Wno-format-truncation']
 if arch=='sun4u':cmd+=['-DCONFIG_SPARC64']
 subprocess.run(cmd+[str(unit),'-o',str(exe)],check=True)
 for case in map(str,range(8)):
  for preset in map(str,range(4)):
   result=subprocess.run([str(exe),case,preset],capture_output=True,text=True)
   print(arch,case,preset,result.returncode,result.stdout.strip(),result.stderr.strip())
   if result.returncode:sys.exit(1)
