
/*
 *  Copyright 2008-2021 NVIDIA Corporation
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

/*! \file
 *  \brief A pointer to a variable which resides in memory associated with a
 *  system.
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

#include <thrust/detail/reference_forward_declaration.h>
#include <thrust/detail/type_traits.h>
#include <thrust/detail/type_traits/pointer_traits.h>
#include <thrust/iterator/detail/iterator_traversal_tags.h>
#include <thrust/iterator/iterator_adaptor.h>

#include <cuda/std/cstddef>
#include <cuda/std/type_traits>

#include <ostream>

THRUST_NAMESPACE_BEGIN
template <typename Element, typename Tag, typename Reference = use_default, typename Derived = use_default>
class pointer;
THRUST_NAMESPACE_END

// Specialize `std::iterator_traits` (picked up by cuda::std::iterator_traits) to avoid problems with the name of
// pointer's constructor shadowing its nested pointer type. We do this before pointer is defined so the specialization
// is correctly used inside the definition.
namespace std
{
template <typename Element, typename Tag, typename Reference, typename Derived>
struct iterator_traits<THRUST_NS_QUALIFIER::pointer<Element, Tag, Reference, Derived>>
{
  using pointer           = THRUST_NS_QUALIFIER::pointer<Element, Tag, Reference, Derived>;
  using iterator_category = typename pointer::iterator_category;
  using value_type        = typename pointer::value_type;
  using difference_type   = typename pointer::difference_type;
  using reference         = typename pointer::reference;
};
} // namespace std

THRUST_NAMESPACE_BEGIN

namespace detail
{

// this metafunction computes the type of iterator_adaptor thrust::pointer should inherit from
template <typename Element, typename Tag, typename Reference, typename Derived>
struct pointer_base
{
  // void pointers should have no element type
  // note that we remove_cv from the Element type to get the value_type
  using value_type = typename thrust::detail::eval_if<::cuda::std::is_void<::cuda::std::remove_cvref_t<Element>>::value,
                                                      ::cuda::std::type_identity<void>,
                                                      ::cuda::std::remove_cv<Element>>::type;

  // if no Derived type is given, just use pointer
  using derived_type =
    typename thrust::detail::eval_if<::cuda::std::is_same<Derived, use_default>::value,
                                     ::cuda::std::type_identity<pointer<Element, Tag, Reference, Derived>>,
                                     ::cuda::std::type_identity<Derived>>::type;

  // void pointers should have no reference type
  // if no Reference type is given, just use reference
  using reference_type = typename thrust::detail::eval_if<
    ::cuda::std::is_void<::cuda::std::remove_cvref_t<Element>>::value,
    ::cuda::std::type_identity<void>,
    thrust::detail::eval_if<::cuda::std::is_same<Reference, use_default>::value,
                            ::cuda::std::type_identity<reference<Element, derived_type>>,
                            ::cuda::std::type_identity<Reference>>>::type;

  using type =
    thrust::iterator_adaptor<derived_type,
                             Element*,
                             value_type,
                             Tag,
                             thrust::random_access_traversal_tag,
                             reference_type,
                             std::ptrdiff_t>;
}; // end pointer_base

} // namespace detail

// the base type for all of thrust's tagged pointers.
// for reasonable pointer-like semantics, derived types should reimplement the following:
// 1. no-argument constructor
// 2. constructor from OtherElement *
// 3. constructor from OtherPointer related by convertibility
// 4. constructor from OtherPointer to void
// 5. assignment from OtherPointer related by convertibility
// These should just call the corresponding members of pointer.
template <typename Element, typename Tag, typename Reference, typename Derived>
class pointer : public thrust::detail::pointer_base<Element, Tag, Reference, Derived>::type
{
private:
  using super_t = typename thrust::detail::pointer_base<Element, Tag, Reference, Derived>::type;

  using derived_type = typename thrust::detail::pointer_base<Element, Tag, Reference, Derived>::derived_type;

  // friend iterator_core_access to give it access to dereference
  friend class thrust::iterator_core_access;

  _CCCL_HOST_DEVICE typename super_t::reference dereference() const;

  // don't provide access to this part of super_t's interface
  using super_t::base;
  using typename super_t::base_type;

public:
  using raw_pointer = typename super_t::base_type;

  // constructors

  _CCCL_HOST_DEVICE pointer();

  // NOTE: This is needed so that Thrust smart pointers can be used in
  // `std::unique_ptr`.
  _CCCL_HOST_DEVICE pointer(std::nullptr_t);

  // OtherValue shall be convertible to Value
  // XXX consider making the pointer implementation a template parameter which defaults to Element *
  template <typename OtherElement>
  _CCCL_HOST_DEVICE explicit pointer(OtherElement* ptr);

  // OtherPointer's element_type shall be convertible to Element
  // OtherPointer's system shall be convertible to Tag
  template <typename OtherPointer>
  _CCCL_HOST_DEVICE pointer(
    const OtherPointer& other,
    typename thrust::detail::enable_if_pointer_is_convertible<OtherPointer,
                                                              pointer<Element, Tag, Reference, Derived>>::type* = 0);

  // OtherPointer's element_type shall be void
  // OtherPointer's system shall be convertible to Tag
  template <typename OtherPointer>
  _CCCL_HOST_DEVICE explicit pointer(
    const OtherPointer& other,
    typename thrust::detail::
      enable_if_void_pointer_is_system_convertible<OtherPointer, pointer<Element, Tag, Reference, Derived>>::type* = 0);

  // assignment

  // NOTE: This is needed so that Thrust smart pointers can be used in
  // `std::unique_ptr`.
  _CCCL_HOST_DEVICE derived_type& operator=(std::nullptr_t);

  // OtherPointer's element_type shall be convertible to Element
  // OtherPointer's system shall be convertible to Tag
  template <typename OtherPointer>
  _CCCL_HOST_DEVICE
  typename thrust::detail::enable_if_pointer_is_convertible<OtherPointer, pointer, derived_type&>::type
  operator=(const OtherPointer& other);

  // observers

  _CCCL_HOST_DEVICE Element* get() const;

  _CCCL_HOST_DEVICE Element* operator->() const;

  // NOTE: This is needed so that Thrust smart pointers can be used in
  // `std::unique_ptr`.
  _CCCL_HOST_DEVICE explicit operator bool() const;

  _CCCL_HOST_DEVICE static derived_type
  pointer_to(typename thrust::detail::pointer_traits_detail::pointer_to_param<Element>::type r)
  {
    return thrust::detail::pointer_traits<derived_type>::pointer_to(r);
  }
}; // end pointer

// Output stream operator
template <typename Element, typename Tag, typename Reference, typename Derived, typename charT, typename traits>
_CCCL_HOST std::basic_ostream<charT, traits>&
operator<<(std::basic_ostream<charT, traits>& os, const pointer<Element, Tag, Reference, Derived>& p);

// NOTE: This is needed so that Thrust smart pointers can be used in
// `std::unique_ptr`.
template <typename Element, typename Tag, typename Reference, typename Derived>
_CCCL_HOST_DEVICE bool operator==(std::nullptr_t, pointer<Element, Tag, Reference, Derived> p);

template <typename Element, typename Tag, typename Reference, typename Derived>
_CCCL_HOST_DEVICE bool operator==(pointer<Element, Tag, Reference, Derived> p, std::nullptr_t);

template <typename Element, typename Tag, typename Reference, typename Derived>
_CCCL_HOST_DEVICE bool operator!=(std::nullptr_t, pointer<Element, Tag, Reference, Derived> p);

template <typename Element, typename Tag, typename Reference, typename Derived>
_CCCL_HOST_DEVICE bool operator!=(pointer<Element, Tag, Reference, Derived> p, std::nullptr_t);

THRUST_NAMESPACE_END

#include <thrust/detail/pointer.inl>
