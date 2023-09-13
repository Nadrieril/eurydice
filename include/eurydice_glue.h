#pragma once

#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#define KRML_HOST_EXIT exit
#define KRML_HOST_EPRINTF(...) fprintf(stderr, __VA_ARGS__)

typedef struct {
  void *ptr;
  size_t len;
} Eurydice_slice;

#define EURYDICE_SLICE(x, start, end, t) ((Eurydice_slice){ .ptr = (void*)(x + start), .len = end - start })
#define EURYDICE_SLICE_LEN(s, _) s.len
#define EURYDICE_SLICE_INDEX(s, i, t) (((t*) s.ptr)[i])
#define EURYDICE_SLICE_SUBSLICE(s, r, t) EURYDICE_SLICE(((t*)s.ptr), r.start, r.end, t)
#define EURYDICE_ARRAY_TO_SLICE(x, end, t) EURYDICE_SLICE(x, 0, end, t)
#define EURYDICE_ARRAY_TO_SUBSLICE(x, r, t) EURYDICE_SLICE(x, r.start, r.end, t)
#define CORE_SLICE__T__0_LEN(s, t) EURYDICE_SLICE_LEN(s, t)
