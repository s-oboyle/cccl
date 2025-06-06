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
#include <thrust/detail/internal_functional.h>
#include <thrust/for_each.h>
#include <thrust/iterator/zip_iterator.h>
#include <thrust/system/detail/generic/swap_ranges.h>
#include <thrust/tuple.h>

#include <cuda/std/utility>

THRUST_NAMESPACE_BEGIN
namespace system
{
namespace detail
{
namespace generic
{
namespace detail
{

// XXX define this here rather than in internal_functional.h
// to avoid circular dependence between swap.h & internal_functional.h
struct swap_pair_elements
{
  template <typename Tuple>
  _CCCL_HOST_DEVICE void operator()(Tuple t)
  {
    // use unqualified swap to allow ADL to catch any user-defined swap
    using ::cuda::std::swap;
    swap(thrust::get<0>(t), thrust::get<1>(t));
  }
}; // end swap_pair_elements

} // namespace detail

template <typename DerivedPolicy, typename ForwardIterator1, typename ForwardIterator2>
_CCCL_HOST_DEVICE ForwardIterator2 swap_ranges(
  thrust::execution_policy<DerivedPolicy>& exec,
  ForwardIterator1 first1,
  ForwardIterator1 last1,
  ForwardIterator2 first2)
{
  using IteratorTuple = thrust::tuple<ForwardIterator1, ForwardIterator2>;
  using ZipIterator   = thrust::zip_iterator<IteratorTuple>;

  ZipIterator result = thrust::for_each(
    exec,
    thrust::make_zip_iterator(first1, first2),
    thrust::make_zip_iterator(last1, first2),
    detail::swap_pair_elements());
  return thrust::get<1>(result.get_iterator_tuple());
} // end swap_ranges()

} // namespace generic
} // namespace detail
} // namespace system
THRUST_NAMESPACE_END
