# 2-Way Set-Associative Instruction Cache for a RISC-V CPU in TL-Verilog

A small **2-way set-associative instruction cache** added to a MYTH-style single-issue RISC-V CPU in **TL-Verilog / \SV_Plus**. The cache sits on the instruction-fetch side of the processor, between the program counter and instruction decode, and visualizes cache behavior in Makerchip.

**ISA:** RV32I subset  •  **Cache:** 2-way set-associative I-cache  •  **Sets:** 4  •  **Language:** TL-Verilog / \SV_Plus  •  **Platform:** Makerchip IDE

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [TL-Verilog](#2-tl-verilog)
3. [Baseline RISC-V CPU](#3-baseline-risc-v-cpu)
4. [Instruction Cache Overview](#4-instruction-cache-overview)
5. [Cache Architecture](#5-cache-architecture)
6. [Implementation](#6-implementation)
7. [Visualization](#7-visualization)
8. [Test Program](#8-test-program)
9. [Running the Design](#9-running-the-design)
10. [Limitations and Future Improvements](#10-limitations-and-future-improvements)
11. [References and Credits](#11-references-and-credits)

---

## 1. Motivation

Modern processors do not normally fetch every instruction directly from main memory. They use an **instruction cache** to store recently fetched instructions close to the CPU. If the CPU asks for an instruction that is already in the cache, the access is a **hit**. If not, the access is a **miss**, and the cache fills itself with the instruction from memory.

This project adds a small instruction cache to a simple RISC-V CPU to make that process visible. The goal is not to model a realistic memory hierarchy yet. Instead, the first version focuses on showing the core cache mechanism:

- how the PC selects a cache set,
- how tags are compared,
- how valid bits determine whether stored entries are usable,
- how hits and misses are detected,
- how a cache line is filled on a miss,
- and how hit/miss counts change over time.

The project is intentionally small so the cache behavior can be understood directly in the Makerchip waveform and visualization panes.

---

## 2. TL-Verilog

**TL-Verilog** is a hardware design methodology that extends Verilog/SystemVerilog with pipeline-oriented syntax. Logic is written in pipeline stages such as `@0`, `@1`, `@2`, and so on, and the tool automatically handles much of the staging between signals.

### 2.1 Automatic pipelining

A signal assigned in one stage can be used in a later stage without manually declaring all intermediate pipeline registers. Alignment operators such as `>>1$sig` are used when the design intentionally references a value from a different cycle.

```
@1
   $instr[31:0] = $imem_rd_data;

@2
   $opcode[6:0] = $instr[6:0];
```

This matters for the cache because most fetch/decode signals describe the same instruction transaction and should not be manually delayed unless there is a true cross-cycle interaction.

### 2.2 State with previous-cycle values

The cache entries themselves are state. Each valid bit, tag, instruction word, and replacement toggle keeps its previous value unless the current cycle updates it. This is why cache storage uses `>>1` references to retain the previous state.

```
$cache_valid = $reset ? 1'b0 :
               $fill  ? 1'b1 :
                        >>1$cache_valid;
```

Here `>>1` is not being used to align one instruction with another. It is being used to preserve state across cycles.

---

## 3. Baseline RISC-V CPU

The starting point is a MYTH-style RISC-V CPU with separate instruction memory, register file, and data memory macros.

The fetch path begins at stage `@0`, where the PC is calculated and the instruction memory address is generated:

```
@0
   $pc[31:0] = ...;
   $inc_pc[31:0] = $pc + 32'd4;
   $imem_rd_en = !$reset;
   $imem_rd_addr[M4_IMEM_INDEX_CNT-1:0] = $pc[M4_IMEM_INDEX_CNT+1:2];
```

The original decode path read the instruction directly from instruction memory at `@1`:

```
@1
   $instr[31:0] = $imem_rd_data[31:0];
```

This project changes that fetch/decode boundary so that the CPU can use a cached instruction on a hit and fall back to instruction memory on a miss.

---

## 4. Instruction Cache Overview

The added cache is an **instruction cache**, not a data cache. It only interacts with instruction fetches from the program counter.

The fetch path becomes:

```
PC
↓
2-way set-associative instruction cache
↓ hit: use cached instruction
↓ miss: use instruction memory data and fill cache
↓
instruction decode
```

Since there are no cache stalls yet, instruction memory still returns data immediately through `m4+imem(@1)`. This keeps the CPU functional while the cache is added as a visual and educational structure.

On a hit:

```
$instr = $icache_hit_instr;
```

On a miss:

```
$instr = $imem_rd_data;
```

The cache then stores the missed instruction so future fetches to the same PC can hit.

---

## 5. Cache Architecture

The cache is a **2-way set-associative cache** with **4 sets**. Each set contains two possible locations, called way 0 and way 1.

```
Set 0: way 0, way 1
Set 1: way 0, way 1
Set 2: way 0, way 1
Set 3: way 0, way 1
```

Each cache entry stores:

| Field | Purpose |
| --- | --- |
| valid bit | tells whether the entry contains usable data |
| tag | identifies which upper PC address is stored |
| instruction | cached 32-bit instruction word |

### 5.1 Address breakdown

RISC-V instructions are 32 bits, or 4 bytes. In this CPU, instruction fetches are word-aligned, so the bottom two PC bits are always `00` and are not useful for selecting a cache set.

The cache uses:

```
PC[31:4] = tag
PC[3:2]  = set index
PC[1:0]  = byte offset, ignored for full-word instruction fetch
```

`PC[3:2]` is used as the set index because those are the first address bits that change between consecutive 4-byte instruction addresses.

Example:

| PC | PC[3:2] | Selected set |
| --- | --- | --- |
| 0x00 | 00 | set 0 |
| 0x04 | 01 | set 1 |
| 0x08 | 10 | set 2 |
| 0x0C | 11 | set 3 |
| 0x10 | 00 | set 0 |

### 5.2 Hit/miss condition

The selected set checks both ways in parallel:

```
way0_hit = way0_valid && (way0_tag == requested_tag)
way1_hit = way1_valid && (way1_tag == requested_tag)
icache_hit = way0_hit || way1_hit
icache_miss = !icache_hit
```

If either way matches, the cache has the instruction. If neither way matches, the cache misses and fills one of the ways.

### 5.3 Replacement policy

On a miss, the cache chooses which way to fill:

1. Fill way 0 if way 0 is invalid.
2. Otherwise fill way 1 if way 1 is invalid.
3. Otherwise use a simple per-set toggle bit to alternate replacement.

This is not a full LRU policy. It is a small round-robin-style replacement policy chosen because it is easy to visualize and explain.

---

## 6. Implementation

### 6.1 Integration point

The cache is inserted at `@1`, between the instruction memory output and the normal decode logic.

The original instruction assignment:

```
$instr[31:0] = $imem_rd_data[31:0];
```

is replaced by:

```
$instr[31:0] = $icache_hit ? $icache_hit_instr : $imem_rd_data;
```

This means the CPU decodes the cached instruction on a hit and decodes the backing instruction memory output on a miss.

### 6.2 Cache lookup

The current PC is split into a set index and tag:

```
$icache_set_index[1:0] = $pc[3:2];
$icache_tag[27:0] = $pc[31:4];
```

The selected set's valid bits, tags, instruction words, and replacement toggle are read from the cache state. Both ways are then compared against the requested tag.

### 6.3 Cache fill

A cache fill occurs on a miss:

```
$icache_fill = !$reset && $icache_miss;
```

The selected way is updated with:

- valid bit set to `1`,
- tag set to the current PC tag,
- instruction data set to `$imem_rd_data`.

The CPU still receives `$imem_rd_data` immediately on the miss, so this first version does not need a stall.

### 6.4 Counters

The design includes counters for visualization:

```
$icache_access_count
$icache_hit_count
$icache_miss_count
```

These counters show the cache warming up. The first loop through the program is expected to have misses because the cache starts empty. Later loop iterations can hit if the instructions have not been evicted.

---

## 7. Visualization

The project includes a Makerchip `\viz_js` block that displays cache activity.

The visualization shows:

- the four cache sets,
- both ways in each set,
- which entries are valid,
- which set and way are selected,
- whether the access is a hit or miss,
- whether a miss fills way 0 or way 1,
- and the running hit/miss counts.

Color meaning:

| Color | Meaning |
| --- | --- |
| gray | invalid entry |
| blue | valid entry |
| green | cache hit |
| orange | miss fill |

The visualizer is meant to make the hidden cache state visible while the CPU runs the normal RISC-V test program.

---

## 8. Test Program

The current program adds the numbers 1 through 9 using a small loop. The branch causes the CPU to fetch the same loop instructions repeatedly, which makes it useful for observing cache behavior.

Expected cache behavior:

- The first time each instruction is fetched, it misses because the cache starts empty.
- Repeated loop instructions can hit after they have been filled.
- If multiple instruction addresses map to the same set, the cache may evict an older instruction and cause a later conflict miss.

The test passes when register `x15` receives the final sum loaded from data memory.

```
1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 = 45
```

---

## 9. Running the Design

1. Open [Makerchip](https://makerchip.com/).
2. Create a new project.
3. Paste the contents of `src/riscv_icache_cpu.tlv` into the editor.
4. Compile and simulate.
5. Open the Diagram, Waveform, and Viz panes.

### What to observe

| Observation | Signal / behavior |
| --- | --- |
| Cache set selection | `$icache_set_index` changes based on `PC[3:2]` |
| Tag comparison | `$way0_hit`, `$way1_hit` |
| Overall result | `$icache_hit`, `$icache_miss` |
| Cache fill | `$icache_fill` and `$chosen_replace_way` |
| Valid entries | `$icache_viz_all_valids` |
| Hit/miss totals | `$icache_hit_count`, `$icache_miss_count` |
| CPU correctness | `*passed` should assert at the end |

---

## 10. Limitations and Future Improvements

- **No stall on cache miss.** The current version still uses `m4+imem(@1)` as an immediate backing memory. A realistic cache would stall or replay fetch until memory returns.
- **Instruction cache only.** The data memory path is unchanged.
- **Small cache size.** The cache uses only 4 sets and 2 ways, which is useful for visualization but not realistic.
- **Simple replacement policy.** The replacement toggle is easier to explain than LRU but does not track true recency.
- **Manual cache storage signals.** Each set and way is written explicitly. A future version could use hierarchy or arrays/macros to reduce repetition.
- **Limited benchmark.** The sum loop is useful for repeated fetches, but more programs could be added to demonstrate conflict misses and locality more clearly.

Possible extensions:

1. Add a direct-mapped cache mode and compare it against the 2-way version.
2. Add real cache-miss stalls.
3. Add a larger instruction memory test program.
4. Add hit-rate percentage calculation.
5. Add a data cache for load/store instructions.
6. Replace the toggle policy with true LRU.

---

## 11. References and Credits

- Built from the MYTH Workshop RISC-V CPU structure.
- Uses the TL-Verilog / Makerchip flow from Redwood EDA.
- Original RISC-V shell library from the MYTH workshop support code.
- Project extension: 2-way set-associative instruction-cache visualizer.
