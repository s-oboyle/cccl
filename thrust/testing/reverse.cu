#include <thrust/iterator/discard_iterator.h>
#include <thrust/iterator/retag.h>
#include <thrust/reverse.h>

#include <unittest/unittest.h>

using ReverseTypes = unittest::type_list<unittest::int8_t, unittest::int16_t, unittest::int32_t>;

template <typename Vector>
void TestReverseSimple()
{
  Vector data{1, 2, 3, 4, 5};

  thrust::reverse(data.begin(), data.end());

  Vector ref{5, 4, 3, 2, 1};

  ASSERT_EQUAL(ref, data);
}
DECLARE_VECTOR_UNITTEST(TestReverseSimple);

template <typename BidirectionalIterator>
void reverse(my_system& system, BidirectionalIterator, BidirectionalIterator)
{
  system.validate_dispatch();
}

void TestReverseDispatchExplicit()
{
  thrust::device_vector<int> vec(1);

  my_system sys(0);
  thrust::reverse(sys, vec.begin(), vec.begin());

  ASSERT_EQUAL(true, sys.is_valid());
}
DECLARE_UNITTEST(TestReverseDispatchExplicit);

template <typename BidirectionalIterator>
void reverse(my_tag, BidirectionalIterator first, BidirectionalIterator)
{
  *first = 13;
}

void TestReverseDispatchImplicit()
{
  thrust::device_vector<int> vec(1);

  thrust::reverse(thrust::retag<my_tag>(vec.begin()), thrust::retag<my_tag>(vec.begin()));

  ASSERT_EQUAL(13, vec.front());
}
DECLARE_UNITTEST(TestReverseDispatchImplicit);

template <typename Vector>
void TestReverseCopySimple()
{
#if _CCCL_COMPILER(GCC, >=, 8) && _CCCL_COMPILER(GCC, <, 10)

  if (typeid(Vector) == typeid(thrust::host_vector<custom_numeric>))
  {
    KNOWN_FAILURE // WAR NVBug 2481122
  }
#endif // _CCCL_COMPILER(GCC, >=, 8) && _CCCL_COMPILER(GCC, <, 10)

  using Iterator = typename Vector::iterator;

  Vector input{1, 2, 3, 4, 5};
  Vector output(8); // arm GCC is complaining about destination size

  Iterator iter = thrust::reverse_copy(input.begin(), input.end(), output.begin());

  output.resize(5);
  Vector ref{5, 4, 3, 2, 1};
  ASSERT_EQUAL(5, iter - output.begin());
  ASSERT_EQUAL(ref, output);
}
DECLARE_VECTOR_UNITTEST(TestReverseCopySimple);

template <typename BidirectionalIterator, typename OutputIterator>
OutputIterator reverse_copy(my_system& system, BidirectionalIterator, BidirectionalIterator, OutputIterator result)
{
  system.validate_dispatch();
  return result;
}

void TestReverseCopyDispatchExplicit()
{
  thrust::device_vector<int> vec(1);

  my_system sys(0);
  thrust::reverse_copy(sys, vec.begin(), vec.end(), vec.begin());

  ASSERT_EQUAL(true, sys.is_valid());
}
DECLARE_UNITTEST(TestReverseCopyDispatchExplicit);

template <typename BidirectionalIterator, typename OutputIterator>
OutputIterator reverse_copy(my_tag, BidirectionalIterator, BidirectionalIterator, OutputIterator result)
{
  *result = 13;
  return result;
}

void TestReverseCopyDispatchImplicit()
{
  thrust::device_vector<int> vec(1);

  thrust::reverse_copy(
    thrust::retag<my_tag>(vec.begin()), thrust::retag<my_tag>(vec.end()), thrust::retag<my_tag>(vec.begin()));

  ASSERT_EQUAL(13, vec.front());
}
DECLARE_UNITTEST(TestReverseCopyDispatchImplicit);

template <typename T>
struct TestReverse
{
  void operator()(const size_t n)
  {
    thrust::host_vector<T> h_data   = unittest::random_integers<T>(n);
    thrust::device_vector<T> d_data = h_data;

    thrust::reverse(h_data.begin(), h_data.end());
    thrust::reverse(d_data.begin(), d_data.end());

    ASSERT_EQUAL(h_data, d_data);
  }
};
VariableUnitTest<TestReverse, ReverseTypes> TestReverseInstance;

template <typename T>
struct TestReverseCopy
{
  void operator()(const size_t n)
  {
    thrust::host_vector<T> h_data   = unittest::random_integers<T>(n);
    thrust::device_vector<T> d_data = h_data;

    thrust::host_vector<T> h_result(n);
    thrust::device_vector<T> d_result(n);

    thrust::reverse_copy(h_data.begin(), h_data.end(), h_result.begin());
    thrust::reverse_copy(d_data.begin(), d_data.end(), d_result.begin());

    ASSERT_EQUAL(h_result, d_result);
  }
};
VariableUnitTest<TestReverseCopy, ReverseTypes> TestReverseCopyInstance;

template <typename T>
struct TestReverseCopyToDiscardIterator
{
  void operator()(const size_t n)
  {
    thrust::host_vector<T> h_data   = unittest::random_integers<T>(n);
    thrust::device_vector<T> d_data = h_data;

    thrust::discard_iterator<> h_result =
      thrust::reverse_copy(h_data.begin(), h_data.end(), thrust::make_discard_iterator());

    thrust::discard_iterator<> d_result =
      thrust::reverse_copy(d_data.begin(), d_data.end(), thrust::make_discard_iterator());

    thrust::discard_iterator<> reference(n);

    ASSERT_EQUAL_QUIET(reference, h_result);
    ASSERT_EQUAL_QUIET(reference, d_result);
  }
};
VariableUnitTest<TestReverseCopyToDiscardIterator, ReverseTypes> TestReverseCopyToDiscardIteratorInstance;
