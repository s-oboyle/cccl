//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

// UNSUPPORTED: c++17
// XFAIL: dylib-has-no-filesystem

// File clock is unsupported in NVRTC
// UNSUPPORTED: nvrtc

// <cuda/std/chrono>

// file_clock

// static time_point now() noexcept;

#include <cuda/std/cassert>
#include <cuda/std/chrono>

#include "test_macros.h"

int main(int, char**)
{
  typedef cuda::std::chrono::file_clock C;
  static_assert(noexcept(C::now()));

  C::time_point t1 = C::now();
  assert(t1.time_since_epoch().count() != 0);
  assert(C::time_point::min() < t1);
  assert(C::time_point::max() > t1);

  return 0;
}
