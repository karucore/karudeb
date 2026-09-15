// cache_window_probe.c -- caches must cover the whole DRAM range.
//
// Regression for the karu64 finding of 2026-09-14: the I-cache, L1 D-cache
// and vector-store posting only covered physical 0x8000_0000..0x8FFF_FFFF,
// the first 256 MiB of the 2 GiB DRAM. Linux places user pages from the top,
// so user code and data above 256 MiB ran uncached (~10 cycles/instruction).
//
// Finds one page inside that historical window and one outside (physical
// addresses via /proc/self/pagemap, so this needs root), then times the same
// instruction loop and the same load loop in each. Both placements must
// perform alike; a ratio above 1.5x in either direction is a failure.
// Exit 0 = pass, 1 = fail, 2 = could not find both placements (small RAM).
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdlib.h>
static uint64_t pa_of(void *va){ int fd=open("/proc/self/pagemap",O_RDONLY); uint64_t e=0;
  pread(fd,&e,8,((uintptr_t)va/4096)*8); close(fd); return (e&(1ULL<<63))?(e&((1ULL<<55)-1))*4096:0; }
static inline uint64_t rdc(void){uint64_t x;__asm__ volatile("rdcycle %0":"=r"(x));return x;}
/* the loop body, position independent: a0 = count; 16 addi + bnez back */
static const uint32_t code[] = {
  0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,
  0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,0x00150513,0x00150513, /* addi a0,a0,1 x16 */
  0x00058593, /* addi a1,a1,0 (nop-ish) */
  0xfff58593, /* addi a1,a1,-1 */
  0xfa059ee3, /* bnez a1, -68 -> back to start */
  0x00008067  /* ret */
};
typedef long (*fn_t)(long a0, long a1);
static double time_at(void *page, const char *what){
  memcpy(page, code, sizeof code); __builtin___clear_cache((char*)page,(char*)page+4096);
  fn_t f=(fn_t)page; f(0,1000); /* warm */
  uint64_t c0=rdc(); f(0,300000); uint64_t c1=rdc();
  double cpi=(double)(c1-c0)/(300000.0*19);
  printf("%-8s pa=0x%09llx  %.2f cycles/insn\n", what,(unsigned long long)pa_of(page),cpi); return cpi; }
/* data side: sequential 64-bit loads over one page, 2000 passes */
static double dtime_at(void *page, const char *what){
  volatile uint64_t *p=page; uint64_t s=0; for(int i=0;i<512;i++) p[i]=i;
  for(int i=0;i<512;i++) s+=p[i];                       /* warm */
  uint64_t c0=rdc(); for(int r=0;r<2000;r++) for(int i=0;i<512;i+=4) s+=p[i]+p[i+1]+p[i+2]+p[i+3]; uint64_t c1=rdc();
  double cpl=(double)(c1-c0)/(2000.0*512);
  printf("%-8s pa=0x%09llx  %.2f cycles/load (s=%llu)\n", what,(unsigned long long)pa_of(page),cpl,(unsigned long long)s); return cpl; }
/* Map a large region, touch every page, and pick one page on each side of the
 * historical 256 MiB boundary. Single-page mmap() rarely reaches the low
 * window on a mostly free 2 GiB system; a big region spans the zone. */
#define REGION (1024UL << 20)
static int find_pages(void **in, void **out, int prot){
  *in=*out=NULL;
  char *r=mmap(NULL,REGION,prot,MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE,-1,0);
  if(r==MAP_FAILED) return 0;
  for(size_t off=0; off<REGION && (!*in||!*out); off+=4096){
    r[off]=1; uint64_t pa=pa_of(r+off); if(!pa) continue;
    if(!*in && (pa>>28)==0x8) *in=r+off; else if(!*out && (pa>>28)!=0x8) *out=r+off; }
  return *in && *out; }
int main(void){
  void *in,*out; int fails=0;
  if(!find_pages(&in,&out,PROT_READ|PROT_WRITE|PROT_EXEC)){ puts("cache_window_probe: could not get pages both inside and outside 0x8xxxxxxx"); return 2; }
  puts("== instruction fetch"); double ci=time_at(in,"inside"), co=time_at(out,"outside");
  /* rdcycle reads a frozen counter unless a perf event holds it open (run
   * under perf_run on karu64); a zero measurement must not pass. */
  if(ci<0.5||co<0.5){ puts("FAIL: cycle counter not advancing (run under perf_run --user-count)"); return 1; }
  if(co>ci*1.5||ci>co*1.5){ printf("FAIL: fetch cost differs by %.2fx across the 256 MiB boundary\n", co>ci?co/ci:ci/co); fails++; }
  puts("== data load"); double di=dtime_at(in,"inside"), dO=dtime_at(out,"outside");
  if(dO>di*1.5||di>dO*1.5){ printf("FAIL: load cost differs by %.2fx across the 256 MiB boundary\n", dO>di?dO/di:di/dO); fails++; }
  printf("cache_window_probe: %s\n", fails?"FAIL":"PASS"); return fails?1:0; }
