# Asynchronous FIFO for Clock Domain Crossing

A parameterizable FIFO that safely transfers data between two independent,
unrelated clock domains, using Gray-coded pointers and dual-flop
synchronizers, the standard structure described in Clifford Cummings'
"Simulation and Synthesis Techniques for Asynchronous FIFO Design."

## Files

- `async_fifo.v` - the design
- `async_fifo_tb.v` - self-checking testbench (fixed, passing version)
- `bug_demo_posedge_race.v` - intentionally reverted copy of the testbench
  that reproduces the original race-condition bug, kept for documentation

## Why this project

Crossing a signal between two clock domains that have no fixed phase
relationship is one of the few places in digital design where "it works
in simulation" and "it works on real silicon" can genuinely diverge, so
it's a good vehicle for demonstrating CDC-safe design practice rather
than just RTL syntax.

## Design decisions

**Why Gray code instead of binary pointers.**
A binary counter can flip multiple bits at once when incrementing
(e.g. `0111 -> 1000` changes all four bits). If a synchronizer samples
that transition mid-flight, it can catch an arbitrary mix of old and new
bits, a value that was never valid at any point in time. Gray code
guarantees exactly one bit changes per increment, so a synchronizer
sampling mid-transition can only ever read the old value or the new
value, never garbage in between.

**Why 2 flops, not 1 or 3.**
One flop isn't enough: if the input is metastable (settling between 0
and 1) right as that flop samples it, the output itself can go
metastable and propagate garbage downstream. A second flop gives the
first one a full clock period to resolve before its output is trusted.
Three flops would add an extra cycle of latency for a marginal
improvement in failure probability that's already vanishingly small
after two stages at any reasonable clock speed: two is the standard
tradeoff point in real designs.

**Why the full/empty comparisons look the way they do.**
Both flags are computed from the *Gray-coded* pointer, not by converting
back to binary first (that would reintroduce the multi-bit-change
problem right before the comparison). `empty` is a direct equality
check between the read pointer and the synchronized write pointer.
`full` compares against the synchronized read pointer with its top two
bits inverted, the standard trick that works because of how Gray code
wraps: when the write pointer has lapped the read pointer by exactly one
full pass through the buffer, the top two Gray-code bits are always
inverted relative to each other while the rest match.

## Verification approach

- Directed fill-to-full and drain-to-empty, checking the flags assert at
  exactly the right point and that an extra write/read past that point
  is correctly dropped
- `wr_clk` and `rd_clk` run at deliberately unrelated periods (7ns vs
  13ns, not an integer multiple of each other) so the synchronizers are
  actually exercised rather than coincidentally aligned
- Concurrent randomized read/write traffic via `fork`/`join`, checked
  against a software reference queue for data-order correctness
- Reset asserted mid-stream on both domains, then checked that both
  recover to a clean empty state and resume normal operation

## A bug I hit and fixed

The first version of the testbench drove `wr_en`/`rd_en` immediately
after `@(posedge wr_clk)` / `@(posedge rd_clk)`, the same clock edge
the DUT's own flip-flops use to sample those signals. That's a race:
whether the DUT's always-block or the testbench's assignment "wins" at
that instant is scheduling-order-dependent, not something Verilog
guarantees either way.

Reproduced output from that version:

```
[611000] ERROR: read mismatch. got=xx expected=0 (idx=0)
```

A single intermittent mismatch, not a spreading corruption, that was
the tell that this was a timing race in the bench, not a real bug in
the DUT logic itself. `bug_demo_posedge_race.v` in this repo is that
exact version, kept so the failure can be reproduced rather than just
described.

**Fix:** drive stimulus on the **negative edge** instead, giving half a
clock period of margin before the DUT's next posedge samples it, so
there's no ambiguity about which assignment happens first.

```
==== PASS: all checks passed ====
```

## Results

All directed, boundary, and randomized-concurrent-traffic checks pass
with zero mismatches against the reference queue, across independent
7ns/13ns write/read clock periods.

## Extensions (not yet done)

- Almost-full / almost-empty threshold flags
- Lightweight UVM environment (driver/monitor/scoreboard) in place of
  the current directed + randomized testbench
- Gate-level synthesis (e.g. via Yosys) for real LUT/flip-flop counts
  and an estimated max clock frequency, rather than simulation-only
  verification
- Formal metastability analysis is out of scope for RTL simulation -
  a real tape-out would rely on `ASYNC_REG` / false-path timing
  constraints and static timing analysis for the synchronizer flops,
  not functional sim, to close on that risk
