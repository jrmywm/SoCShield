#ifndef SOC_H
#define SOC_H
typedef unsigned int u32;
#include "soc_map.h"
#define REG(base,off) (*(volatile u32 *)((base)+(off)))
#define FW SOC_FW_BASE
#define DMA SOC_DMA_BASE
#define LOG SOC_LOG_BASE
#define SHARED SOC_SHARED_BASE
static inline void barrier(void){ __asm__ volatile("fence iorw,iorw" ::: "memory"); }
#endif
