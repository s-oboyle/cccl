#include <thrust/functional.h>
#include <thrust/iterator/discard_iterator.h>
#include <thrust/iterator/retag.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/random.h>
#include <thrust/scan.h>

#include <unittest/unittest.h>

template <typename Vector>
void TestInclusiveScanByKeySimple()
{
  using T        = typename Vector::value_type;
  using Iterator = typename Vector::iterator;

  Vector keys{0, 1, 1, 1, 2, 3, 3};
  Vector vals{1, 2, 3, 4, 5, 6, 7};
  Vector output(7, 0);

  Iterator iter = thrust::inclusive_scan_by_key(keys.begin(), keys.end(), vals.begin(), output.begin());

  ASSERT_EQUAL_QUIET(iter, output.end());

  Vector ref{1, 2, 5, 9, 5, 6, 13};
  ASSERT_EQUAL(output, ref);

  thrust::inclusive_scan_by_key(
    keys.begin(), keys.end(), vals.begin(), output.begin(), ::cuda::std::equal_to<T>(), ::cuda::std::multiplies<T>());

  ref = {1, 2, 6, 24, 5, 6, 42};
  ASSERT_EQUAL(output, ref);

  thrust::inclusive_scan_by_key(keys.begin(), keys.end(), vals.begin(), output.begin(), ::cuda::std::equal_to<T>());

  ref = {1, 2, 5, 9, 5, 6, 13};
  ASSERT_EQUAL(output, ref);
}
DECLARE_VECTOR_UNITTEST(TestInclusiveScanByKeySimple);

template <typename InputIterator1, typename InputIterator2, typename OutputIterator>
OutputIterator
inclusive_scan_by_key(my_system& system, InputIterator1, InputIterator1, InputIterator2, OutputIterator result)
{
  system.validate_dispatch();
  return result;
}

void TestInclusiveScanByKeyDispatchExplicit()
{
  thrust::device_vector<int> vec(1);

  my_system sys(0);
  thrust::inclusive_scan_by_key(sys, vec.begin(), vec.begin(), vec.begin(), vec.begin());

  ASSERT_EQUAL(true, sys.is_valid());
}
DECLARE_UNITTEST(TestInclusiveScanByKeyDispatchExplicit);

template <typename InputIterator1, typename InputIterator2, typename OutputIterator>
OutputIterator inclusive_scan_by_key(my_tag, InputIterator1, InputIterator1, InputIterator2, OutputIterator result)
{
  *result = 13;
  return result;
}

void TestInclusiveScanByKeyDispatchImplicit()
{
  thrust::device_vector<int> vec(1);

  thrust::inclusive_scan_by_key(
    thrust::retag<my_tag>(vec.begin()),
    thrust::retag<my_tag>(vec.begin()),
    thrust::retag<my_tag>(vec.begin()),
    thrust::retag<my_tag>(vec.begin()));

  ASSERT_EQUAL(13, vec.front());
}
DECLARE_UNITTEST(TestInclusiveScanByKeyDispatchImplicit);

struct head_flag_predicate
{
  template <typename T>
  _CCCL_HOST_DEVICE bool operator()(const T&, const T& b)
  {
    return b ? false : true;
  }
};

template <typename Vector>
void TestScanByKeyHeadFlags()
{
  using T = typename Vector::value_type;

  Vector keys{0, 1, 0, 0, 1, 1, 0};
  Vector vals{1, 2, 3, 4, 5, 6, 7};

  Vector output(7, 0);

  thrust::inclusive_scan_by_key(
    keys.begin(), keys.end(), vals.begin(), output.begin(), head_flag_predicate(), ::cuda::std::plus<T>());

  Vector ref{1, 2, 5, 9, 5, 6, 13};
  ASSERT_EQUAL(output, ref);
}
DECLARE_VECTOR_UNITTEST(TestScanByKeyHeadFlags);

template <typename Vector>
void TestInclusiveScanByKeyTransformIterator()
{
  using T = typename Vector::value_type;

  Vector keys{0, 1, 1, 1, 2, 3, 3};
  Vector vals{1, 2, 3, 4, 5, 6, 7};
  Vector output(7, 0);

  thrust::inclusive_scan_by_key(
    keys.begin(), keys.end(), thrust::make_transform_iterator(vals.begin(), ::cuda::std::negate<T>()), output.begin());

  Vector ref{-1, -2, -5, -9, -5, -6, -13};
  ASSERT_EQUAL(output, ref);
}
DECLARE_VECTOR_UNITTEST(TestInclusiveScanByKeyTransformIterator);

template <typename Vector>
void TestScanByKeyReusedKeys()
{
  Vector keys{0, 1, 1, 1, 0, 1, 1};
  Vector vals{1, 2, 3, 4, 5, 6, 7};
  Vector output(7, 0);

  thrust::inclusive_scan_by_key(keys.begin(), keys.end(), vals.begin(), output.begin());

  Vector ref{1, 2, 5, 9, 5, 6, 13};
  ASSERT_EQUAL(output, ref);
}
DECLARE_VECTOR_UNITTEST(TestScanByKeyReusedKeys);

template <typename T>
void TestInclusiveScanByKey(const size_t n)
{
  thrust::host_vector<int> h_keys(n);
  thrust::default_random_engine rng;
  for (size_t i = 0, k = 0; i < n; i++)
  {
    h_keys[i] = static_cast<int>(k);
    if (rng() % 10 == 0)
    {
      k++;
    }
  }
  thrust::device_vector<int> d_keys = h_keys;

  thrust::host_vector<T> h_vals = unittest::random_integers<int>(n);
  for (size_t i = 0; i < n; i++)
  {
    h_vals[i] = static_cast<int>(i % 10);
  }
  thrust::device_vector<T> d_vals = h_vals;

  thrust::host_vector<T> h_output(n);
  thrust::device_vector<T> d_output(n);

  thrust::inclusive_scan_by_key(h_keys.begin(), h_keys.end(), h_vals.begin(), h_output.begin());
  thrust::inclusive_scan_by_key(d_keys.begin(), d_keys.end(), d_vals.begin(), d_output.begin());
  ASSERT_EQUAL(d_output, h_output);
}
DECLARE_VARIABLE_UNITTEST(TestInclusiveScanByKey);

template <typename T>
void TestInclusiveScanByKeyInPlace(const size_t n)
{
  thrust::host_vector<int> h_keys(n);
  thrust::default_random_engine rng;
  for (size_t i = 0, k = 0; i < n; i++)
  {
    h_keys[i] = static_cast<int>(k);
    if (rng() % 10 == 0)
    {
      k++;
    }
  }
  thrust::device_vector<int> d_keys = h_keys;

  thrust::host_vector<T> h_vals = unittest::random_integers<int>(n);
  for (size_t i = 0; i < n; i++)
  {
    h_vals[i] = static_cast<int>(i % 10);
  }
  thrust::device_vector<T> d_vals = h_vals;

  thrust::host_vector<T> h_output(n);
  thrust::device_vector<T> d_output(n);

  // in-place scans: in/out values aliasing
  h_output = h_vals;
  d_output = d_vals;
  thrust::inclusive_scan_by_key(h_keys.begin(), h_keys.end(), h_output.begin(), h_output.begin());
  thrust::inclusive_scan_by_key(d_keys.begin(), d_keys.end(), d_output.begin(), d_output.begin());
  ASSERT_EQUAL(d_output, h_output);

  // in-place scans: in/out keys aliasing
  thrust::inclusive_scan_by_key(h_keys.begin(), h_keys.end(), h_vals.begin(), h_keys.begin());
  thrust::inclusive_scan_by_key(d_keys.begin(), d_keys.end(), d_vals.begin(), d_keys.begin());
  ASSERT_EQUAL(d_keys, h_keys);
}
DECLARE_VARIABLE_UNITTEST(TestInclusiveScanByKeyInPlace);

void TestScanByKeyMixedTypes()
{
  const unsigned int n = 113;

  thrust::host_vector<int> h_keys(n);
  thrust::default_random_engine rng;
  for (size_t i = 0, k = 0; i < n; i++)
  {
    h_keys[i] = static_cast<int>(k);
    if (rng() % 10 == 0)
    {
      k++;
    }
  }
  thrust::device_vector<int> d_keys = h_keys;

  thrust::host_vector<unsigned int> h_vals = unittest::random_integers<unsigned int>(n);
  for (size_t i = 0; i < n; i++)
  {
    h_vals[i] %= 10;
  }
  thrust::device_vector<unsigned int> d_vals = h_vals;

  thrust::host_vector<float> h_float_output(n);
  thrust::device_vector<float> d_float_output(n);
  thrust::host_vector<int> h_int_output(n);
  thrust::device_vector<int> d_int_output(n);

  // mixed vals/output types
  thrust::inclusive_scan_by_key(h_keys.begin(), h_keys.end(), h_vals.begin(), h_float_output.begin());
  thrust::inclusive_scan_by_key(d_keys.begin(), d_keys.end(), d_vals.begin(), d_float_output.begin());
  ASSERT_EQUAL(d_float_output, h_float_output);
}
DECLARE_UNITTEST(TestScanByKeyMixedTypes);

template <typename T>
void TestScanByKeyDiscardOutput(std::size_t n)
{
  thrust::host_vector<T> h_keys(n);
  thrust::default_random_engine rng;

  for (size_t i = 0, k = 0; i < n; i++)
  {
    h_keys[i] = static_cast<T>(k);
    if (rng() % 10 == 0)
    {
      k++;
    }
  }
  thrust::device_vector<T> d_keys = h_keys;

  thrust::host_vector<T> h_vals(n);
  for (size_t i = 0; i < n; i++)
  {
    h_vals[i] = static_cast<T>(i % 10);
  }
  thrust::device_vector<T> d_vals = h_vals;

  auto out = thrust::make_discard_iterator();

  // These are no-ops, but they should compile.
  thrust::inclusive_scan_by_key(d_keys.cbegin(), d_keys.cend(), d_vals.cbegin(), out);
  thrust::inclusive_scan_by_key(d_keys.cbegin(), d_keys.cend(), d_vals.cbegin(), out, ::cuda::std::equal_to<T>{});
  thrust::inclusive_scan_by_key(
    d_keys.cbegin(), d_keys.cend(), d_vals.cbegin(), out, ::cuda::std::equal_to<T>{}, ::cuda::std::multiplies<T>{});
}
DECLARE_VARIABLE_UNITTEST(TestScanByKeyDiscardOutput);

void TestScanByKeyLargeInput()
{
  const unsigned int N = 1 << 20;

  thrust::host_vector<unsigned int> vals_sizes = unittest::random_integers<unsigned int>(10);

  thrust::host_vector<unsigned int> h_vals   = unittest::random_integers<unsigned int>(N);
  thrust::device_vector<unsigned int> d_vals = h_vals;

  thrust::host_vector<unsigned int> h_output(N, 0);
  thrust::device_vector<unsigned int> d_output(N, 0);

  for (unsigned int i = 0; i < vals_sizes.size(); i++)
  {
    const unsigned int n = vals_sizes[i] % N;

    // define segments
    thrust::host_vector<unsigned int> h_keys(n);
    thrust::default_random_engine rng;
    for (size_t j = 0, k = 0; j < n; j++)
    {
      h_keys[j] = static_cast<unsigned int>(k);
      if (rng() % 100 == 0)
      {
        k++;
      }
    }
    thrust::device_vector<unsigned int> d_keys = h_keys;

    thrust::inclusive_scan_by_key(h_keys.begin(), h_keys.begin() + n, h_vals.begin(), h_output.begin());
    thrust::inclusive_scan_by_key(d_keys.begin(), d_keys.begin() + n, d_vals.begin(), d_output.begin());
    ASSERT_EQUAL(d_output, h_output);
  }
}
DECLARE_UNITTEST(TestScanByKeyLargeInput);

template <typename T, unsigned int N>
void _TestScanByKeyWithLargeTypes()
{
  size_t n = (64 * 1024) / sizeof(FixedVector<T, N>);

  thrust::host_vector<unsigned int> h_keys(n);
  thrust::host_vector<FixedVector<T, N>> h_vals(n);
  thrust::host_vector<FixedVector<T, N>> h_output(n);

  thrust::default_random_engine rng;
  for (size_t i = 0, k = 0; i < h_vals.size(); i++)
  {
    h_keys[i] = static_cast<unsigned int>(k);
    h_vals[i] = FixedVector<T, N>(static_cast<T>(i));
    if (rng() % 5 == 0)
    {
      k++;
    }
  }

  thrust::device_vector<unsigned int> d_keys      = h_keys;
  thrust::device_vector<FixedVector<T, N>> d_vals = h_vals;
  thrust::device_vector<FixedVector<T, N>> d_output(n);

  thrust::inclusive_scan_by_key(h_keys.begin(), h_keys.end(), h_vals.begin(), h_output.begin());
  thrust::inclusive_scan_by_key(d_keys.begin(), d_keys.end(), d_vals.begin(), d_output.begin());

  ASSERT_EQUAL_QUIET(h_output, d_output);
}

void TestScanByKeyWithLargeTypes()
{
  _TestScanByKeyWithLargeTypes<int, 1>();
  _TestScanByKeyWithLargeTypes<int, 2>();
  _TestScanByKeyWithLargeTypes<int, 4>();
  _TestScanByKeyWithLargeTypes<int, 8>();

  // too many resources requested for launch:
  //_TestScanByKeyWithLargeTypes<int,   16>();
  //_TestScanByKeyWithLargeTypes<int,   32>();

  // too large to pass as argument
  //_TestScanByKeyWithLargeTypes<int,   64>();
  //_TestScanByKeyWithLargeTypes<int,  128>();
  //_TestScanByKeyWithLargeTypes<int,  256>();
  //_TestScanByKeyWithLargeTypes<int,  512>();
  //_TestScanByKeyWithLargeTypes<int, 1024>();
}
DECLARE_UNITTEST(TestScanByKeyWithLargeTypes);
