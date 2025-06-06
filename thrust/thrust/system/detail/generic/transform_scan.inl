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
#include <thrust/detail/type_traits.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/scan.h>
#include <thrust/system/detail/generic/transform_scan.h>

#include <cuda/std/type_traits>

THRUST_NAMESPACE_BEGIN
namespace system
{
namespace detail
{
namespace generic
{

template <typename ExecutionPolicy,
          typename InputIterator,
          typename OutputIterator,
          typename UnaryFunction,
          typename BinaryFunction>
_CCCL_HOST_DEVICE OutputIterator transform_inclusive_scan(
  thrust::execution_policy<ExecutionPolicy>& exec,
  InputIterator first,
  InputIterator last,
  OutputIterator result,
  UnaryFunction unary_op,
  BinaryFunction binary_op)
{
  // Use the input iterator's value type per https://wg21.link/P0571
  using InputType  = thrust::detail::it_value_t<InputIterator>;
  using ResultType = thrust::detail::invoke_result_t<UnaryFunction, InputType>;
  using ValueType  = ::cuda::std::remove_cvref_t<ResultType>;

  thrust::transform_iterator<UnaryFunction, InputIterator, ValueType> _first(first, unary_op);
  thrust::transform_iterator<UnaryFunction, InputIterator, ValueType> _last(last, unary_op);

  return thrust::inclusive_scan(exec, _first, _last, result, binary_op);
} // end transform_inclusive_scan()

template <typename ExecutionPolicy,
          typename InputIterator,
          typename OutputIterator,
          typename UnaryFunction,
          typename InitialValueType,
          typename BinaryFunction>
_CCCL_HOST_DEVICE OutputIterator transform_inclusive_scan(
  thrust::execution_policy<ExecutionPolicy>& exec,
  InputIterator first,
  InputIterator last,
  OutputIterator result,
  UnaryFunction unary_op,
  InitialValueType init,
  BinaryFunction binary_op)
{
  using InputType  = thrust::detail::it_value_t<InputIterator>;
  using ResultType = thrust::detail::invoke_result_t<UnaryFunction, InputType>;
  using ValueType  = ::cuda::std::remove_cvref_t<ResultType>;

  thrust::transform_iterator<UnaryFunction, InputIterator, ValueType> _first(first, unary_op);
  thrust::transform_iterator<UnaryFunction, InputIterator, ValueType> _last(last, unary_op);

  return thrust::inclusive_scan(exec, _first, _last, result, init, binary_op);
} // end transform_inclusive_scan()

template <typename ExecutionPolicy,
          typename InputIterator,
          typename OutputIterator,
          typename UnaryFunction,
          typename InitialValueType,
          typename AssociativeOperator>
_CCCL_HOST_DEVICE OutputIterator transform_exclusive_scan(
  thrust::execution_policy<ExecutionPolicy>& exec,
  InputIterator first,
  InputIterator last,
  OutputIterator result,
  UnaryFunction unary_op,
  InitialValueType init,
  AssociativeOperator binary_op)
{
  // Use the initial value type per https://wg21.link/P0571
  using ValueType = ::cuda::std::remove_cvref_t<InitialValueType>;

  thrust::transform_iterator<UnaryFunction, InputIterator, ValueType> _first(first, unary_op);
  thrust::transform_iterator<UnaryFunction, InputIterator, ValueType> _last(last, unary_op);

  return thrust::exclusive_scan(exec, _first, _last, result, init, binary_op);
} // end transform_exclusive_scan()

} // end namespace generic
} // end namespace detail
} // end namespace system
THRUST_NAMESPACE_END
