//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include <cuda/std/cstddef>

#include <test_macros.h>

// constexpr byte& operator ^=(byte l, byte r) noexcept;

__host__ __device__ constexpr cuda::std::byte test(cuda::std::byte b1, cuda::std::byte b2)
{
  cuda::std::byte bret = b1;
  return bret ^= b2;
}

int main(int, char**)
{
  cuda::std::byte b; // not constexpr, just used in noexcept check
  constexpr cuda::std::byte b1{static_cast<cuda::std::byte>(1)};
  constexpr cuda::std::byte b8{static_cast<cuda::std::byte>(8)};
  constexpr cuda::std::byte b9{static_cast<cuda::std::byte>(9)};

  static_assert(noexcept(b ^= b), "");

  assert(cuda::std::to_integer<int>(test(b1, b8)) == 9);
  assert(cuda::std::to_integer<int>(test(b1, b9)) == 8);
  assert(cuda::std::to_integer<int>(test(b8, b9)) == 1);

  assert(cuda::std::to_integer<int>(test(b8, b1)) == 9);
  assert(cuda::std::to_integer<int>(test(b9, b1)) == 8);
  assert(cuda::std::to_integer<int>(test(b9, b8)) == 1);

  static_assert(cuda::std::to_integer<int>(test(b1, b8)) == 9, "");
  static_assert(cuda::std::to_integer<int>(test(b1, b9)) == 8, "");
  static_assert(cuda::std::to_integer<int>(test(b8, b9)) == 1, "");

  static_assert(cuda::std::to_integer<int>(test(b8, b1)) == 9, "");
  static_assert(cuda::std::to_integer<int>(test(b9, b1)) == 8, "");
  static_assert(cuda::std::to_integer<int>(test(b9, b8)) == 1, "");

  return 0;
}
