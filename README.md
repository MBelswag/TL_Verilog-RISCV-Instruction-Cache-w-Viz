# 2-Way Set-Associative Instruction Cache for a RISC-V CPU in TL-Verilog

This project adds a small **2-way set-associative instruction cache** to a MYTH workshop RISC-V CPU in **TL-Verilog / \SV_Plus**. The cache is placed on the instruction-fetch side of the processor, between the program counter and instruction decode. It also includes a Makerchip visualization so the cache behavior can be watched while the CPU runs.

**ISA:** RV32I
**Cache:** 2-way set-associative instruction cache
**Sets:** 4
**Language:** TL-Verilog / \SV_Plus
**Platform:** Makerchip IDE

---

## Introduction

Modern processors do not normally fetch every instruction directly from main memory. They use an **instruction cache** to keep recently fetched instructions close to the CPU. If the CPU asks for an instruction that is already stored in the cache, the access is a **hit**. If it is not there, the access is a **miss**, and the cache fills itself with the instruction from memory.

This project adds a small instruction cache to a simple RISC-V CPU to make that process easier to see. The goal is not to model a realistic memory system yet. This version focuses on the core cache behavior: how the PC selects a set, how tags are compared, how valid bits are used, how hits and misses are detected, how a line fills on a miss, and how the hit/miss counts change over time.

---

## TL-Verilog

**TL-Verilog** is a hardware design methodology that extends Verilog/SystemVerilog with pipeline-oriented syntax. Logic is written in stages such as `@0`, `@1`, `@2`, and so on. The tool automatically handles much of the staging between signals.

A signal assigned in one stage can be used in a later stage without manually declaring every pipeline register in between. Alignment operators such as `>>1$sig` are used when the design intentionally references a value from a different cycle.

```tlv
@1
   $instr[31:0] = $imem_rd_data;

@2
   $opcode[6:0] = $instr[6:0];
```

This matters for the cache because most fetch and decode signals describe the same instruction transaction. Those signals should not be manually delayed unless there is a real cross-cycle interaction.

The cache entries themselves are state. Each valid bit, tag, instruction word, and replacement toggle keeps its previous value unless the current cycle updates it. That is why the cache storage uses `>>1` references to retain the previous state.

```tlv
$cache_valid = $reset ? 1'b0 :
               $fill  ? 1'b1 :
                        >>1$cache_valid;
```

Here, `>>1` is not being used to align one instruction with another. It is being used to preserve state across cycles.

---

## Baseline RISC-V CPU

The starting point is a MYTH RISC-V CPU with separate instruction memory, register file, and data memory macros.

The fetch path begins at stage `@0`, where the PC is calculated and the instruction memory address is generated.

```tlv
@0
   $pc[31:0] = ...;
   $inc_pc[31:0] = $pc + 32'd4;
   $imem_rd_en = !$reset;
   $imem_rd_addr[M4_IMEM_INDEX_CNT-1:0] = $pc[M4_IMEM_INDEX_CNT+1:2];
```

Originally, the decode path read the instruction directly from instruction memory at `@1`.

```tlv
@1
   $instr[31:0] = $imem_rd_data[31:0];
```

This project changes that fetch/decode boundary so the CPU can use a cached instruction on a hit and fall back to instruction memory on a miss.

---

## Instruction Cache Overview

The added cache is an **instruction cache**, not a data cache. It only interacts with instruction fetches from the program counter.

The fetch path changes from a direct instruction-memory read into a cache lookup first.

```text
PC
to 2-way set-associative instruction cache
to hit: use cached instruction
to miss: use instruction memory data and fill cache
to instruction decode
```

There are no cache stalls yet, so instruction memory still returns data immediately through `m4+imem(@1)`. This keeps the CPU functional while the cache is added as a visual and educational structure.

On a hit:

```tlv
$instr = $icache_hit_instr;
```

On a miss:

```tlv
$instr = $imem_rd_data;
```

The cache then stores the missed instruction so future fetches to the same PC can hit.

---

## Cache Architecture

The cache is a **2-way set-associative cache** with **4 sets**. Each set contains two possible locations, called way 0 and way 1.

```text
Set 0: way 0, way 1
Set 1: way 0, way 1
Set 2: way 0, way 1
Set 3: way 0, way 1
```

Each cache entry stores a valid bit, a tag, and a 32-bit instruction word.

```text
valid bit   tells whether the entry contains usable data
tag         identifies which upper PC address is stored
instruction cached 32-bit instruction word
```

### Address breakdown

RISC-V instructions are 32 bits, or 4 bytes. In this CPU, instruction fetches are word-aligned, so the bottom two PC bits are always `00` and are not useful for selecting a cache set.

The cache uses this breakdown:

```text
PC[31:4] = tag
PC[3:2]  = set index
PC[1:0]  = byte offset, ignored for full-word instruction fetch
```

`PC[3:2]` is used as the set index because those are the first address bits that change between consecutive 4-byte instruction addresses.

```text
PC      PC[3:2]   selected set
0x00    00        set 0
0x04    01        set 1
0x08    10        set 2
0x0C    11        set 3
0x10    00        set 0
```

### Hit and miss condition

The selected set checks both ways in parallel.

```text
way0_hit = way0_valid && (way0_tag == requested_tag)
way1_hit = way1_valid && (way1_tag == requested_tag)
icache_hit = way0_hit || way1_hit
icache_miss = !icache_hit
```

If either way matches, the cache has the instruction. If neither way matches, the cache misses and fills one of the ways.

### Replacement policy

On a miss, the cache chooses which way to fill in this order:

```text
1. Fill way 0 if way 0 is invalid.
2. Otherwise fill way 1 if way 1 is invalid.
3. Otherwise use a simple per-set toggle bit to alternate replacement.
```

This is not a full LRU policy. It is a round-robin-style replacement policy chosen because it is easier to visualize and explain.

---

## Implementation

The cache is inserted at `@1`, between the instruction memory output and the normal decode logic.

The original instruction assignment:

```tlv
$instr[31:0] = $imem_rd_data[31:0];
```

is replaced by:

```tlv
$instr[31:0] = $icache_hit ? $icache_hit_instr : $imem_rd_data;
```

This means the CPU decodes the cached instruction on a hit and decodes the backing instruction memory output on a miss.

The current PC is split into a set index and tag:

```tlv
$icache_set_index[1:0] = $pc[3:2];
$icache_tag[27:0] = $pc[31:4];
```

The selected set’s valid bits, tags, instruction words, and replacement toggle are read from the cache state. Both ways are then compared against the requested tag.

A cache fill occurs on a miss:

```tlv
$icache_fill = !$reset && $icache_miss;
```

The selected way is updated with the valid bit set to `1`, the tag set to the current PC tag, and the instruction data set to `$imem_rd_data`.

The CPU still receives `$imem_rd_data` immediately on the miss, so this first version does not need a stall.

The design also includes counters for visualization.

```tlv
$icache_access_count
$icache_hit_count
$icache_miss_count
```

These counters show the cache warming up. The first loop through the program is expected to have misses because the cache starts empty. Later loop iterations can hit if the instructions have not been evicted.

---

## Visualization

The project includes a `\viz_js` block that displays cache activity.
<img width="630" height="480" alt="image" src="https://github.com/user-attachments/assets/c68bae1b-8738-448b-a3ac-07c46c590efd" />

The visualization shows the four cache sets, both ways in each set, which entries are valid, which set and way are selected, whether the access is a hit or miss, whether a miss fills way 0 or way 1, and the running hit/miss counts.

The cache visualization uses color to make the current state easier to follow. Gray means that a cache entry has not been used yet. Blue means the entry is valid and currently holds an instruction. Green shows the entry that produced a cache hit. Orange shows the entry being filled after a cache miss.

The visualizer is meant to make the hidden cache state visible while the CPU runs the normal RISC-V test program.

---

## Test Program

The current program adds the numbers 1 through 9 using a small loop. The branch causes the CPU to fetch the same loop instructions repeatedly, which makes it useful for observing cache behavior.

The expected cache behavior is that the first time each instruction is fetched, it misses because the cache starts empty. Repeated loop instructions can hit after they have been filled. If multiple instruction addresses map to the same set, the cache may evict an older instruction and cause a later conflict miss.

The test passes when register `x15` receives the final sum loaded from data memory.

```text
1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 = 45
```

---

## Running the Design

Open Makerchip, create a new project, paste the contents of `src/riscv_icache_cpu.tlv` into the editor, then compile and simulate. After a successful compile, open the Diagram, Waveform, and Viz panes.

While the program runs, the main thing to watch is how the PC maps into the cache. The set is chosen using `PC[3:2]`, so different instruction addresses move through the four cache sets. For each fetch, the cache checks both ways in the selected set.

If either `$way0_hit` or `$way1_hit` is true, then `$icache_hit` becomes true and the cached instruction is used. If neither way matches, `$icache_miss` becomes true and the cache fills one of the ways using `$icache_fill` and `$chosen_replace_way`.

The valid-entry display, `$icache_viz_all_valids`, shows which cache spots have already been filled. The counters, `$icache_hit_count` and `$icache_miss_count`, make it easier to see how the cache behaves over time.

The CPU should still finish normally, with `*passed` asserting at the end of the test program.

---

## Limitations and Future Improvements

The current version does not stall on a cache miss. It still uses `m4+imem(@1)` as an immediate backing memory. A more realistic cache would stall or replay fetch until memory returns.

This is also only an instruction cache. The data memory path is unchanged.

The cache is intentionally small, using only 4 sets and 2 ways. That makes it easier to visualize, but it is not meant to be realistic.

The replacement policy is also simple. The toggle policy is easier to explain than LRU, but it does not track true recency.

Possible extensions include adding a direct-mapped cache mode and comparing it against the 2-way version, adding real cache-miss stalls, using a larger instruction memory test program, adding hit-rate percentage calculation, adding a data cache for load/store instructions, or replacing the toggle policy with true LRU.

---

## References and Credits

Built from the MYTH Workshop RISC-V CPU structure.

Uses the TL-Verilog / Makerchip flow from Redwood EDA.

Original RISC-V shell library from the MYTH workshop support code.
