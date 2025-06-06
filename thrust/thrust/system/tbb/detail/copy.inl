/*
 *  Copyright 2008-2013 NVIDIA Corporation
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#pragma once

#include <thrust/detail/config.h>

#if defined(_CCCL_IMPLICIT_SYSTEM_HEADER_GCC)
#  pragma GCC system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_CLANG)
#  pragma clang system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_MSVC)
#  pragma system_header
#endif // no system header

#include <thrust/detail/copy.h>
#include <thrust/detail/type_traits/minimum_type.h>
#include <thrust/system/detail/generic/copy.h>
#include <thrust/system/detail/sequential/copy.h>
#include <thrust/system/tbb/detail/copy.h>

#include <cuda/std/type_traits>

THRUST_NAMESPACE_BEGIN
namespace system::tbb::detail
{
template <typename DerivedPolicy, typename InputIterator, typename OutputIterator>
OutputIterator
copy(execution_policy<DerivedPolicy>& exec, InputIterator first, InputIterator last, OutputIterator result)
{
  using traversal1 = typename iterator_traversal<InputIterator>::type;
  using traversal2 = typename iterator_traversal<OutputIterator>::type;
  using traversal  = thrust::detail::minimum_type<traversal1, traversal2>;
  if constexpr (::cuda::std::is_convertible_v<traversal, random_access_traversal_tag>)
  {
    return system::detail::generic::copy(exec, first, last, result);
  }
  else
  {
    return system::detail::sequential::copy(exec, first, last, result);
  }
}

template <typename DerivedPolicy, typename InputIterator, typename Size, typename OutputIterator>
OutputIterator copy_n(execution_policy<DerivedPolicy>& exec, InputIterator first, Size n, OutputIterator result)
{
  using traversal1 = typename iterator_traversal<InputIterator>::type;
  using traversal2 = typename iterator_traversal<OutputIterator>::type;
  using traversal  = thrust::detail::minimum_type<traversal1, traversal2>;
  if constexpr (::cuda::std::is_convertible_v<traversal, random_access_traversal_tag>)
  {
    return system::detail::generic::copy_n(exec, first, n, result);
  }
  else
  {
    return system::detail::sequential::copy_n(exec, first, n, result);
  }
}
} // namespace system::tbb::detail
THRUST_NAMESPACE_END
