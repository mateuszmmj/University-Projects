# AKSO projects

Projects from the Computer Architecture and Operating Systems course.
Mostly low-level C and x86-64 assembly.

## `rstack`

Recursive stack library written in C.

A stack can contain numbers or references to other stacks. The main difficulty was memory management: reference counting, shared stacks and cycles.

Main files:

- `rstack/rstack.c`
- `rstack/rstack.h`

Topics: C API, manual memory management, reference counting, cycle cleanup, parsing `uint64_t` values.

Example build:

```sh
gcc -std=c2x -Wall -Wextra -O2 -fPIC -shared rstack/rstack.c -o librstack.so
```

## `discrete_fractal`

Standalone x86-64 assembly program for generating a discrete fractal described by rewriting rules.

The program reads an initial string and replacement rules, then expands the system for a given number of iterations.

Main file:

- `discrete_fractal/zad.asm`

Topics: Linux syscalls, `mmap`, dynamic buffers, manual stack instead of recursion, input validation, buffered output.

Example build:

```sh
nasm -f elf64 discrete_fractal/zad.asm -o discrete_fractal.o
ld discrete_fractal.o -o discrete_fractal
```

Example run:

```sh
./discrete_fractal 5 < input.txt
```

## `arithmetic_sequence`

x86-64 assembly function for computing terms of an arithmetic sequence on multi-word integers.

This is not a standalone program. It is meant to be linked with the course test harness.

Main file:

- `arithmetic_sequence/zad.asm`

Topics: System V AMD64 ABI, multi-precision arithmetic, carries and borrows, `adc`, `sbb`, `mul`, signed cases.

Example build:

```sh
nasm -f elf64 arithmetic_sequence/zad.asm -o arithmetic_sequence.o
```

## Structure

```text
.
├── arithmetic_sequence/
│   └── zad.asm
├── discrete_fractal/
│   └── zad.asm
└── rstack/
    ├── rstack.c
    └── rstack.h
```
