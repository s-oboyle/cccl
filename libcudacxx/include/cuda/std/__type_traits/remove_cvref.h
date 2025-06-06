//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// SPDX-FileCopyrightText: Copyright (c) 2023 NVIDIA CORPORATION & AFFILIATES.
//
//===----------------------------------------------------------------------===//

#ifndef _LIBCUDACXX___TYPE_TRAITS_REMOVE_CVREF_H
#define _LIBCUDACXX___TYPE_TRAITS_REMOVE_CVREF_H

#include <cuda/std/detail/__config>

#if defined(_CCCL_IMPLICIT_SYSTEM_HEADER_GCC)
#  pragma GCC system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_CLANG)
#  pragma clang system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_MSVC)
#  pragma system_header
#endif // no system header

#include <cuda/std/__type_traits/is_same.h>
#include <cuda/std/__type_traits/remove_cv.h>
#include <cuda/std/__type_traits/remove_reference.h>

#include <cuda/std/__cccl/prologue.h>

_LIBCUDACXX_BEGIN_NAMESPACE_STD

#if defined(_CCCL_BUILTIN_REMOVE_CVREF) && !defined(_LIBCUDACXX_USE_REMOVE_CVREF_FALLBACK)

template <class _Tp>
using remove_cvref_t _CCCL_NODEBUG_ALIAS = _CCCL_BUILTIN_REMOVE_CVREF(_Tp);

#else

template <class _Tp>
using remove_cvref_t _CCCL_NODEBUG_ALIAS = remove_cv_t<remove_reference_t<_Tp>>;

#endif // defined(_CCCL_BUILTIN_REMOVE_CVREF) && !defined(_LIBCUDACXX_USE_REMOVE_CVREF_FALLBACK)

template <class _Tp, class _Up>
struct __is_same_uncvref : _IsSame<remove_cvref_t<_Tp>, remove_cvref_t<_Up>>
{};

template <class _Tp>
struct remove_cvref
{
  using type _CCCL_NODEBUG_ALIAS = remove_cvref_t<_Tp>;
};

_LIBCUDACXX_END_NAMESPACE_STD

#include <cuda/std/__cccl/epilogue.h>

#endif // _LIBCUDACXX___TYPE_TRAITS_REMOVE_CVREF_H
