//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

// <chrono>

// template <class Duration> class hh_mm_ss;
//   If Duration is not an instance of duration, the program is ill-formed.

#include <cuda/std/cassert>
#include <cuda/std/chrono>

#include <string>

#include "test_macros.h"

struct A
{};

int main(int, char**)
{
  cuda::std::chrono::hh_mm_ss<void> h0; // expected-error-re@chrono:* {{{{(static_assert|static assertion)}} failed
                                        // {{.*}} {{"?}}template parameter of hh_mm_ss must be a
                                        // cuda::std::chrono::duration{{"?}}}}
  cuda::std::chrono::hh_mm_ss<int> h1; // expected-error-re@chrono:* {{{{(static_assert|static assertion)}} failed
                                       // {{.*}} {{"?}}template parameter of hh_mm_ss must be a
                                       // cuda::std::chrono::duration{{"?}}}}
  cuda::std::chrono::hh_mm_ss<std::string> h2; // expected-error-re@chrono:* {{{{(static_assert|static assertion)}}
                                               // failed {{.*}} {{"?}}template parameter of hh_mm_ss must be a
                                               // cuda::std::chrono::duration{{"?}}}}
  cuda::std::chrono::hh_mm_ss<A> h3; // expected-error-re@chrono:* {{{{(static_assert|static assertion)}} failed {{.*}}
                                     // {{"?}}template parameter of hh_mm_ss must be a
                                     // cuda::std::chrono::duration{{"?}}}}

  return 0;
}
