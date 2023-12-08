**Example document**.

* Extract source code by using `nailit tangle test.md testCode`.
* Produce a readable HTML file by using `nailit weave test.md test.html`.

# Sequence and strings difference between v1 and v2

The internal representation of sequences and strings differ between MM methods from Nim ≥ 2.0. The nimv2 implementation is implemented when using ARC/ORC, which is the default. The old (nimv1) implementation can be accessed by using the "classic" reference counting GC (`--mm:refc`). This turns out to be a pretty big deal when it comes to interop with C libraries.

## C setup

Let's work with an actual C-to-Nim setup. For the C part I'll just have one function that views whatever is pointed at by the `address` argument, for `how_many` bytes.

It's quite a simple function:

``` /test.c
#include <stdio.h>
#include <stdint.h>

void print_hex(uint8_t *address, size_t how_many) {
    @{Print the pointer's address}
    @{Iterate over the contents within the pointer}
    printf("\n");
}
```
.. raw:: html

Just so I'm sure of where it is, I'll have the pointer itself printed…

``` Print the pointer's address
printf("%p -> ", address);
```
.. raw:: html

And then, the actual contents.

``` Iterate over the contents within the pointer
for (size_t i = 0; i < how_many; i++) {
    printf("%02x ", address[i]);
}
```
.. raw:: html

I can then let Nim know about this function like so:

``` print_hex C to Nim binding
proc printHex(address: ptr UncheckedArray[uint8], howMany: csize_t) {.cdecl, importc:"print_hex".}
```

## Nim setup

Next up is the Nim code. Here I'll define the objects I want to inspect: a sequence and a string. Then, I'll call the C function to look around their actual memory addresses.

``` /test.nim
{.compile: "test.c".}

@{print_hex C to Nim binding}

when isMainModule:
    @{Define a sequence and a string}
    @{Find out what the sequence contains}
    @{Find out what the string contains}
```

``` Define a sequence and a string
let
    a = @[1, 2, 3, 4]
    st = "Insert something cool here."
```

``` Find out what the sequence contains
@{Print out the sequence container}
@{Print out bytes around the first element}
```
.. raw:: html

I can set any amount of arbitrary bytes to look at. I dunno, I felt like peeking at 64 bytes:

``` Print out the sequence container
printHex(
    cast[ptr UncheckedArray[uint8]](a.addr),
    64
)
```
.. raw:: html

Here I'm doing heretical things, but it's for ✨science✨ I promise.

``` Print out bytes around the first element
printHex(
    cast[ptr UncheckedArray[uint8]](
        cast[int]((a[0].addr)) - 10
    ),
    64
)
```
.. raw:: html

I think I'll just do the same things for the string.

``` Find out what the string contains
@{Print out the string container}
@{Print out bytes around the first character}
```

``` Print out the string container
printHex(
    cast[ptr UncheckedArray[uint8]](st.addr),
    64
)
```

``` Print out bytes around the first character
printHex(
    cast[ptr UncheckedArray[uint8]](
        cast[int]((st[0].addr)) - 10
    ),
    64
)
```

## Observation time

Alright, let's see what we have here. First let's test the defaults.

``` Compile command, defaults
nim r test
```
.. raw:: html

Note the default settings as of writing.

``` Compiler output, defaults
...
Hint: mm: orc; threads: on; opt: none
...
```

``` Program output, defaults
0x55ca2bc7e120 -> 04 00 00 00 00 00 00 00 50 70 72 c4 30 7f 00 00 1b 00 00 00 00 00 00 00 c0 a0 c7 2b ca 55 00 00 01 00 00 00 00 00 00 00 f8 10 37 4e ff 7f 00 00 08 11 37 4e ff 7f 00 00 00 00 00 00 00 00 00 00
0x7f30c472704e -> 00 00 04 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 02 00 00 00 00 00 00 00 03 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0x55ca2bc7e130 -> 1b 00 00 00 00 00 00 00 c0 a0 c7 2b ca 55 00 00 01 00 00 00 00 00 00 00 f8 10 37 4e ff 7f 00 00 08 11 37 4e ff 7f 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0x55ca2bc7a0be -> 00 00 1b 00 00 00 00 00 00 40 49 6e 73 65 72 74 20 73 6f 6d 65 74 68 69 6e 67 20 63 6f 6f 6c 20 68 65 72 65 2e 00 00 00 00 00 74 65 73 74 00 00 00 00 2f 6d 6e 74 2f 70 65 72 73 69 73 74 65 6e
```

Alright, what's going on here? Let's try to unpack this:
* First is the **sequence container address**, that's `0x55ca2bc7e120`.
* Second is the address **near the first element**, that's `0x7f30c472704e`.
* Third is the **string container address**, that's `0x55ca2bc7e130`.
* Fourth is the address **near the first string character**, that's `0x55ca2bc7a0be`.

At the sequence container address, I see `04 00 00 ..` and `50 70 72 c4 30 7f`. I know the former encodes a length of some kind and the latter is little endian for `0x7f30c4727050`, which is near that second address.

What's the second address? I see another `04 00 00 ..` and then what looks like the actual elements (since they're all 64-bit ints). `04 00 00 ..` here seems to start 3 bytes in, so `0x7f30c4727050`—checks out.

What's the difference between the first `04 00 00 ..` and the second `04 00 00 ..`? Let's consult the Nim compiler source code to be sure:

``` Extract of nim/lib/system/seqs_v2.nim
type
  NimSeqPayloadBase = object
    cap: int

  NimSeqPayload[T] = object
    cap: int
    data: UncheckedArray[T]

  NimSeqV2*[T] = object
    # if you change this implementation, also change seqs_v2_reimpl.nim!
    len: int
    p: ptr NimSeqPayload[T]
```
.. raw:: html

It looks like the first address is a **NimSeqV2** and the second address is near the **NimSeqPayload**! Sure enough, the first element is 10 bytes in and is the beginning of the actual data (since I did subtract the pointer by 10 bytes)
