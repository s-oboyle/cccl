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

/*! \file thrust/system/omp/vector.h
 *  \brief A dynamically-sizable array of elements which reside in memory available to
 *         Thrust's OpenMP system.
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
#include <thrust/detail/vector_base.h>
#include <thrust/system/omp/memory.h>

#include <vector>

THRUST_NAMESPACE_BEGIN
namespace system
{
namespace omp
{

/*! \p omp::vector is a container that supports random access to elements,
 *  constant time removal of elements at the end, and linear time insertion
 *  and removal of elements at the beginning or in the middle. The number of
 *  elements in a \p omp::vector may vary dynamically; memory management is
 *  automatic. The elements contained in an \p omp::vector reside in memory
 *  accessible by the \p omp system.
 *
 *  \tparam T The element type of the \p omp::vector.
 *  \tparam Allocator The allocator type of the \p omp::vector.
 *          Defaults to \p omp::allocator.
 *
 *  \see https://en.cppreference.com/w/cpp/container/vector
 *  \see host_vector For the documentation of the complete interface which is
 *                   shared by \p omp::vector.
 *  \see device_vector
 *  \see universal_vector
 */
template <typename T, typename Allocator = thrust::system::omp::allocator<T>>
using vector = thrust::detail::vector_base<T, Allocator>;

/*! \p omp::universal_vector is a container that supports random access to
 *  elements, constant time removal of elements at the end, and linear time
 *  insertion and removal of elements at the beginning or in the middle. The
 *  number of elements in a \p omp::universal_vector may vary dynamically;
 *  memory management is automatic. The elements contained in a
 *  \p omp::universal_vector reside in memory accessible by the \p omp system
 *  and host systems.
 *
 *  \tparam T The element type of the \p omp::universal_vector.
 *  \tparam Allocator The allocator type of the \p omp::universal_vector.
 *          Defaults to \p omp::universal_allocator.
 *
 *  \see https://en.cppreference.com/w/cpp/container/vector
 *  \see host_vector For the documentation of the complete interface which is
 *                   shared by \p omp::universal_vector
 *  \see device_vector
 *  \see universal_host_pinned_vector
 */
template <typename T, typename Allocator = thrust::system::omp::universal_allocator<T>>
using universal_vector = thrust::detail::vector_base<T, Allocator>;

//! Like \ref universal_vector but uses pinned memory when the system supports it.
//! \see device_vector
//! \see universal_vector
template <typename T>
using universal_host_pinned_vector = thrust::detail::vector_base<T, universal_host_pinned_allocator<T>>;
} // namespace omp
} // namespace system

namespace omp
{
using thrust::system::omp::universal_vector;
using thrust::system::omp::vector;
} // namespace omp

THRUST_NAMESPACE_END
