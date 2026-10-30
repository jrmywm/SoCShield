#include "soc.h"
#ifndef GAP
#define GAP 0
#endif
#ifndef CONTENTION
#define CONTENTION 0
#endif
#ifndef BOOT_ONLY
#define BOOT_ONLY 0
#endif
static volatile u32 bss_probe[8];
static volatile u32 data_probe=0x13579bdfu;
static void put(char c){REG(LOG,0)=(u32)c;}
static void say(const char *s){while(*s)put(*s++);}
static void fail(u32 n){say("FAIL\n");REG(LOG,4)=0xdead0000u|n;for(;;);}
static void check(int condition,u32 n){if(!condition)fail(n);}
static void wait_idle(void){u32 n=200000;while(REG(FW,4)&1u)if(!--n)fail(1);}
static void command(u32 cmd){wait_idle();REG(FW,8)=cmd;barrier();wait_idle();check(REG(FW,12)==0,2);}
static void policy(u32 permissions, int broad){
  command(1);
  for(u32 i=0;i<4;i++){
    REG(FW,0x10)=i; REG(FW,0x14)=broad?0:SHARED;
    REG(FW,0x18)=broad?0xffffffffu:SHARED+0xff;
    REG(FW,0x1c)=i==0?permissions:0; command(2);
    for(volatile u32 j=0;j<GAP;j++) __asm__ volatile("nop");
  }
  u32 before=REG(FW,0x20); command(3);
  u32 n=200000;while(REG(FW,0x20)==before)if(!--n)fail(3);
}
static void start(u32 addr,u32 count,u32 write,u32 pattern){
  REG(DMA,0)=addr;REG(DMA,4)=count;REG(DMA,8)=write;REG(DMA,12)=pattern;REG(DMA,16)=1;
}
static void done(void){u32 n=200000;while(REG(DMA,0x14)&1u)if(!--n)fail(4);check(REG(DMA,0x24)==(REG(DMA,0x1c)!=0),5);}
static void transfer(u32 addr,u32 count,u32 write,u32 pattern,u32 success,u32 denied){
  start(addr,count,write,pattern);done();check(REG(DMA,0x18)==success,6);check(REG(DMA,0x1c)==denied,7);
}
int main(void){
  volatile unsigned char *bytes=(volatile unsigned char *)&bss_probe[0];
  volatile unsigned short *halves=(volatile unsigned short *)&bss_probe[0];
  for(u32 i=0;i<8;i++)check(bss_probe[i]==0,8);
  check(data_probe==0x13579bdfu,9);bss_probe[0]=0x11223344;
  bytes[1]=0xaa;halves[1]=0xbeef;check(bss_probe[0]==0xbeefaa44,10);
  REG(LOG,12)=bss_probe[0]; // independent boot observation
  say("BOOT RV32I\n");
  if(BOOT_ONLY){REG(LOG,4)=0x600d0001;for(;;);}
  volatile u32 *mem=(volatile u32 *)SHARED;
  mem[0]=0xaaaa0000;mem[128]=0xfeedcafe;
  transfer(SHARED,1,1,0x1234,0,1);check(mem[0]==0xaaaa0000,11);say("DEFAULT DENY\n");
  policy(7,0);transfer(SHARED,16,1,0x12340000,16,0);
  for(u32 i=0;i<16;i++)check(mem[i]==0x12340000+i,12);
  transfer(SHARED,16,0,0,16,0);u32 sum=0;for(u32 i=0;i<16;i++)sum^=mem[i];check(REG(DMA,0x20)==sum,13);
  transfer(SHARED+512,1,1,0,0,1);check(mem[128]==0xfeedcafe,14);
  transfer(SHARED+512,1,0,0,0,1);check(REG(DMA,0x20)==0,15);say("GRANT AND CONTAINMENT\n");
  policy(7,1); // deliberately broad: topology must still exclude CPU/MMIO.
  transfer(0,1,1,0,0,1);transfer(FW,1,1,0,0,1);transfer(0x30000000,1,1,0,0,1);
  check(REG(FW,0)==0x534f4301,16);say("NO BYPASS\n");
  policy(7,0);
  REG(LOG,0x10)=1; // testbench arms a deterministic mid-transfer delay here.
  start(SHARED,1024,1,0xabc00000);
  u32 n=200000;while(REG(DMA,0x18)==0)if(!--n)fail(17);
  if(CONTENTION)for(u32 i=0;i<16;i++)check(mem[128]==0xfeedcafe,24);
  REG(LOG,0x14)=1; // beginning of measured programming phase
  command(1);
  for(u32 i=0;i<4;i++){
    REG(FW,0x10)=i;REG(FW,0x14)=SHARED;REG(FW,0x18)=SHARED+255;REG(FW,0x1c)=0;
    command(2);
    for(volatile u32 j=0;j<GAP;j++) __asm__ volatile("nop");
    if(CONTENTION)check(mem[128]==0xfeedcafe,25);
  }
  u32 seq=REG(FW,0x20);command(3);
  n=200000;while(REG(FW,0x20)==seq)if(!--n)fail(18);
  REG(LOG,0x14)=2;
  done();check(REG(DMA,0x1c)>0,19);check(REG(DMA,0x18)+REG(DMA,0x1c)==1024,20);
  check(mem[128]==0xfeedcafe,21);say("REVOKED\n");
  policy(7,0);transfer(SHARED,4,1,0x98760000,4,0);check(mem[3]==0x98760003,22);
  policy(0,0);policy(7,0);transfer(SHARED,1,0,0,1,0);say("REGRANT\n");
  check(REG(LOG,8)==0,23);REG(LOG,4)=0x600d600d;for(;;);
}
