/******************************************************************************
 * Copyright (c) 2011, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2018, NVIDIA CORPORATION.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the NVIDIA CORPORATION nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 ******************************************************************************/

/**
 * \file
 * cub::AgentRle implements a stateful abstraction of CUDA thread blocks for participating in device-wide
 * run-length-encode.
 */

#pragma once

#include <cub/config.cuh>

#if defined(_CCCL_IMPLICIT_SYSTEM_HEADER_GCC)
#  pragma GCC system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_CLANG)
#  pragma clang system_header
#elif defined(_CCCL_IMPLICIT_SYSTEM_HEADER_MSVC)
#  pragma system_header
#endif // no system header

#include <cub/agent/single_pass_scan_operators.cuh>
#include <cub/block/block_discontinuity.cuh>
#include <cub/block/block_exchange.cuh>
#include <cub/block/block_load.cuh>
#include <cub/block/block_scan.cuh>
#include <cub/block/block_store.cuh>
#include <cub/grid/grid_queue.cuh>
#include <cub/iterator/cache_modified_input_iterator.cuh>

#include <cuda/ptx>
#include <cuda/std/type_traits>

CUB_NAMESPACE_BEGIN

/******************************************************************************
 * Tuning policy types
 ******************************************************************************/

/**
 * Parameterizable tuning policy type for AgentRle
 *
 * @tparam _BLOCK_THREADS
 *   Threads per thread block
 *
 * @tparam _ITEMS_PER_THREAD
 *   Items per thread (per tile of input)
 *
 * @tparam _LOAD_ALGORITHM
 *   The BlockLoad algorithm to use
 *
 * @tparam _LOAD_MODIFIER
 *   Cache load modifier for reading input elements
 *
 * @tparam _STORE_WARP_TIME_SLICING
 *   Whether or not only one warp's worth of shared memory should be allocated and time-sliced among
 *   block-warps during any store-related data transpositions
 *   (versus each warp having its own storage)
 *
 * @tparam _SCAN_ALGORITHM
 *   The BlockScan algorithm to use
 *
 * @tparam DelayConstructorT
 *   Implementation detail, do not specify directly, requirements on the
 *   content of this type are subject to breaking change.
 */
template <int _BLOCK_THREADS,
          int _ITEMS_PER_THREAD,
          BlockLoadAlgorithm _LOAD_ALGORITHM,
          CacheLoadModifier _LOAD_MODIFIER,
          bool _STORE_WARP_TIME_SLICING,
          BlockScanAlgorithm _SCAN_ALGORITHM,
          typename DelayConstructorT = detail::fixed_delay_constructor_t<350, 450>>
struct AgentRlePolicy
{
  enum
  {
    /// Threads per thread block
    BLOCK_THREADS = _BLOCK_THREADS,

    /// Items per thread (per tile of input)
    ITEMS_PER_THREAD = _ITEMS_PER_THREAD,

    /// Whether or not only one warp's worth of shared memory should be allocated and time-sliced
    /// among block-warps during any store-related data transpositions (versus each warp having its
    /// own storage)
    STORE_WARP_TIME_SLICING = _STORE_WARP_TIME_SLICING,
  };

  /// The BlockLoad algorithm to use
  static constexpr BlockLoadAlgorithm LOAD_ALGORITHM = _LOAD_ALGORITHM;

  /// Cache load modifier for reading input elements
  static constexpr CacheLoadModifier LOAD_MODIFIER = _LOAD_MODIFIER;

  /// The BlockScan algorithm to use
  static constexpr BlockScanAlgorithm SCAN_ALGORITHM = _SCAN_ALGORITHM;

  struct detail
  {
    using delay_constructor_t = DelayConstructorT;
  };
};

/******************************************************************************
 * Thread block abstractions
 ******************************************************************************/

namespace detail
{
namespace rle
{

/**
 * @brief AgentRle implements a stateful abstraction of CUDA thread blocks for participating in device-wide
 * run-length-encode
 *
 * @tparam AgentRlePolicyT
 *   Parameterized AgentRlePolicyT tuning policy type
 *
 * @tparam InputIteratorT
 *   Random-access input iterator type for data
 *
 * @tparam OffsetsOutputIteratorT
 *   Random-access output iterator type for offset values
 *
 * @tparam LengthsOutputIteratorT
 *   Random-access output iterator type for length values
 *
 * @tparam EqualityOpT
 *   T equality operator type
 *
 * @tparam OffsetT
 *   Signed integer type for global offsets
 *
 * @tparam StreamingContextT
 *   Type providing information about the partition for streaming invocations. NullType if not a streaming invocation.
 */
template <typename AgentRlePolicyT,
          typename InputIteratorT,
          typename OffsetsOutputIteratorT,
          typename LengthsOutputIteratorT,
          typename EqualityOpT,
          typename OffsetT,
          typename GlobalOffsetT,
          typename StreamingContextT>
struct AgentRle
{
  // Whether or not this is a streaming invocation (i.e., multiple kernel invocations over partitions of the input)
  static constexpr bool is_streaming_invocation = !_CUDA_VSTD::is_same_v<StreamingContextT, NullType>;

  //---------------------------------------------------------------------
  // Types and constants
  //---------------------------------------------------------------------

  /// The input value type
  using T = cub::detail::it_value_t<InputIteratorT>;

  /// The lengths output value type
  using LengthT = cub::detail::non_void_value_t<LengthsOutputIteratorT, GlobalOffsetT>;

  /// Tuple type for scanning (pairs run-length and run-index)
  using LengthOffsetPair = KeyValuePair<OffsetT, LengthT>;

  /// Tile status descriptor interface type
  using ScanTileStateT = ReduceByKeyScanTileState<LengthT, OffsetT>;

  // Constants
  enum
  {
    WARP_THREADS     = warp_threads,
    BLOCK_THREADS    = AgentRlePolicyT::BLOCK_THREADS,
    ITEMS_PER_THREAD = AgentRlePolicyT::ITEMS_PER_THREAD,
    WARP_ITEMS       = WARP_THREADS * ITEMS_PER_THREAD,
    TILE_ITEMS       = BLOCK_THREADS * ITEMS_PER_THREAD,
    WARPS            = (BLOCK_THREADS + WARP_THREADS - 1) / WARP_THREADS,

    /// Whether or not to sync after loading data
    SYNC_AFTER_LOAD = (AgentRlePolicyT::LOAD_ALGORITHM != BLOCK_LOAD_DIRECT),

    /// Whether or not only one warp's worth of shared memory should be allocated and time-sliced
    /// among block-warps during any store-related data transpositions (versus each warp having
    /// its own storage)
    STORE_WARP_TIME_SLICING = AgentRlePolicyT::STORE_WARP_TIME_SLICING,
    ACTIVE_EXCHANGE_WARPS   = (STORE_WARP_TIME_SLICING) ? 1 : WARPS,
  };

  /**
   * Special operator that signals all out-of-bounds items are not equal to everything else,
   * forcing both (1) the last item to be tail-flagged and (2) all oob items to be marked
   * trivial.
   */
  template <bool LAST_TILE>
  struct OobInequalityOp
  {
    OffsetT num_remaining;
    EqualityOpT equality_op;

    _CCCL_DEVICE _CCCL_FORCEINLINE OobInequalityOp(OffsetT num_remaining, EqualityOpT equality_op)
        : num_remaining(num_remaining)
        , equality_op(equality_op)
    {}

    template <typename Index>
    _CCCL_HOST_DEVICE _CCCL_FORCEINLINE bool operator()(T first, T second, Index idx)
    {
      if (!LAST_TILE || (idx < num_remaining))
      {
        return !equality_op(first, second);
      }
      else
      {
        return true;
      }
    }
  };

  // Cache-modified Input iterator wrapper type (for applying cache modifier) for data
  // Wrap the native input pointer with CacheModifiedVLengthnputIterator
  // Directly use the supplied input iterator type
  using WrappedInputIteratorT =
    ::cuda::std::_If<::cuda::std::is_pointer_v<InputIteratorT>,
                     CacheModifiedInputIterator<AgentRlePolicyT::LOAD_MODIFIER, T, OffsetT>,
                     InputIteratorT>;

  // Parameterized BlockLoad type for data
  using BlockLoadT =
    BlockLoad<T, AgentRlePolicyT::BLOCK_THREADS, AgentRlePolicyT::ITEMS_PER_THREAD, AgentRlePolicyT::LOAD_ALGORITHM>;

  // Parameterized BlockDiscontinuity type for data
  using BlockDiscontinuityT = BlockDiscontinuity<T, BLOCK_THREADS>;

  // Parameterized WarpScan type
  using WarpScanPairs = WarpScan<LengthOffsetPair>;

  // Reduce-length-by-run scan operator
  using ReduceBySegmentOpT = ReduceBySegmentOp<::cuda::std::plus<>>;

  // Callback type for obtaining tile prefix during block scan
  using DelayConstructorT = typename AgentRlePolicyT::detail::delay_constructor_t;
  using TilePrefixCallbackOpT =
    TilePrefixCallbackOp<LengthOffsetPair, ReduceBySegmentOpT, ScanTileStateT, DelayConstructorT>;

  // Warp exchange types
  using WarpExchangePairs = WarpExchange<LengthOffsetPair, ITEMS_PER_THREAD>;

  using WarpExchangePairsStorage =
    ::cuda::std::_If<STORE_WARP_TIME_SLICING, typename WarpExchangePairs::TempStorage, NullType>;

  using WarpExchangeOffsets = WarpExchange<OffsetT, ITEMS_PER_THREAD>;
  using WarpExchangeLengths = WarpExchange<LengthT, ITEMS_PER_THREAD>;

  using WarpAggregates = LengthOffsetPair[WARPS];

  // Shared memory type for this thread block
  struct _TempStorage
  {
    // Aliasable storage layout
    union Aliasable
    {
      struct ScanStorage
      {
        // Smem needed for discontinuity detection
        typename BlockDiscontinuityT::TempStorage discontinuity;

        // Smem needed for warp-synchronous scans
        typename WarpScanPairs::TempStorage warp_scan[WARPS];

        // Smem needed for sharing warp-wide aggregates
        Uninitialized<LengthOffsetPair[WARPS]> warp_aggregates;

        // Smem needed for cooperative prefix callback
        typename TilePrefixCallbackOpT::TempStorage prefix;
      } scan_storage;

      // Smem needed for input loading
      typename BlockLoadT::TempStorage load;

      // Aliasable layout needed for two-phase scatter
      union ScatterAliasable
      {
        unsigned long long align;
        WarpExchangePairsStorage exchange_pairs[ACTIVE_EXCHANGE_WARPS];
        typename WarpExchangeOffsets::TempStorage exchange_offsets[ACTIVE_EXCHANGE_WARPS];
        typename WarpExchangeLengths::TempStorage exchange_lengths[ACTIVE_EXCHANGE_WARPS];
      } scatter_aliasable;

    } aliasable;

    OffsetT tile_idx; // Shared tile index
    LengthOffsetPair tile_inclusive; // Inclusive tile prefix
    LengthOffsetPair tile_exclusive; // Exclusive tile prefix
  };

  // Alias wrapper allowing storage to be unioned
  struct TempStorage : Uninitialized<_TempStorage>
  {};

  //---------------------------------------------------------------------
  // Per-thread fields
  //---------------------------------------------------------------------

  _TempStorage& temp_storage; ///< Reference to temp_storage

  WrappedInputIteratorT d_in; ///< Pointer to input sequence of data items
  OffsetsOutputIteratorT d_offsets_out; ///< Input run offsets
  LengthsOutputIteratorT d_lengths_out; ///< Output run lengths

  EqualityOpT equality_op; ///< T equality operator
  ReduceBySegmentOpT scan_op; ///< Reduce-length-by-flag scan operator
  OffsetT num_items; ///< Total number of input items
  StreamingContextT streaming_context; ///< Context providing information about this partition for streaming invocations

  //---------------------------------------------------------------------
  // Constructor
  //---------------------------------------------------------------------

  /**
   * @param[in] temp_storage
   *   Reference to temp_storage
   *
   * @param[in] d_in
   *   Pointer to input sequence of data items
   *
   * @param[out] d_offsets_out
   *   Pointer to output sequence of run offsets
   *
   * @param[out] d_lengths_out
   *   Pointer to output sequence of run lengths
   *
   * @param[in] equality_op
   *   Equality operator
   *
   * @param[in] num_items
   *   Total number of input items
   *
   * @param streaming_context
   *   Streaming context providing context about this partition for streaming invocations
   */
  template <typename StreamingContext>
  _CCCL_DEVICE _CCCL_FORCEINLINE AgentRle(
    TempStorage& temp_storage,
    InputIteratorT d_in,
    OffsetsOutputIteratorT d_offsets_out,
    LengthsOutputIteratorT d_lengths_out,
    EqualityOpT equality_op,
    OffsetT num_items,
    StreamingContext streaming_context)
      : temp_storage(temp_storage.Alias())
      , d_in(d_in)
      , d_offsets_out(d_offsets_out)
      , d_lengths_out(d_lengths_out)
      , equality_op(equality_op)
      , scan_op(::cuda::std::plus<>{})
      , num_items(num_items)
      , streaming_context(streaming_context)
  {}

  //---------------------------------------------------------------------
  // Utility methods for initializing the selections
  //---------------------------------------------------------------------

  template <bool FIRST_TILE, bool LAST_TILE>
  _CCCL_DEVICE _CCCL_FORCEINLINE void InitializeSelections(
    OffsetT tile_offset,
    OffsetT num_remaining,
    T (&items)[ITEMS_PER_THREAD],
    LengthOffsetPair (&lengths_and_num_runs)[ITEMS_PER_THREAD])
  {
    bool head_flags[ITEMS_PER_THREAD];
    bool tail_flags[ITEMS_PER_THREAD];

    OobInequalityOp<LAST_TILE> inequality_op(num_remaining, equality_op);

    if (FIRST_TILE && LAST_TILE)
    {
      // First-and-last-tile always head-flags the first item and tail-flags the last item

      BlockDiscontinuityT(temp_storage.aliasable.scan_storage.discontinuity)
        .FlagHeadsAndTails(head_flags, tail_flags, items, inequality_op);
    }
    else if (FIRST_TILE)
    {
      // First-tile always head-flags the first item

      // Get the first item from the next tile
      T tile_successor_item;
      if (threadIdx.x == BLOCK_THREADS - 1)
      {
        tile_successor_item = d_in[tile_offset + TILE_ITEMS];
      }

      BlockDiscontinuityT(temp_storage.aliasable.scan_storage.discontinuity)
        .FlagHeadsAndTails(head_flags, tail_flags, tile_successor_item, items, inequality_op);
    }
    else if (LAST_TILE)
    {
      // Last-tile always flags the last item

      // Get the last item from the previous tile
      T tile_predecessor_item;
      if (threadIdx.x == 0)
      {
        tile_predecessor_item = d_in[tile_offset - 1];
      }

      BlockDiscontinuityT(temp_storage.aliasable.scan_storage.discontinuity)
        .FlagHeadsAndTails(head_flags, tile_predecessor_item, tail_flags, items, inequality_op);
    }
    else
    {
      // Get the first item from the next tile
      T tile_successor_item;
      if (threadIdx.x == BLOCK_THREADS - 1)
      {
        tile_successor_item = d_in[tile_offset + TILE_ITEMS];
      }

      // Get the last item from the previous tile
      T tile_predecessor_item;
      if (threadIdx.x == 0)
      {
        tile_predecessor_item = d_in[tile_offset - 1];
      }

      BlockDiscontinuityT(temp_storage.aliasable.scan_storage.discontinuity)
        .FlagHeadsAndTails(head_flags, tile_predecessor_item, tail_flags, tile_successor_item, items, inequality_op);
    }

    // Zip counts and runs
    _CCCL_PRAGMA_UNROLL_FULL()
    for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ++ITEM)
    {
      // input                   output
      // items [ 0 0 0 1 2 3 3 ]
      // heads [ 1 0 0 1 1 1 0 ]
      // tails [ 0 0 1 1 1 0 1 ]
      // key   [ 1 0 0 0 0 1 0 ]  head && !tail - heads of non-trivial (length > 1) runs
      // value [ 1 1 1 0 0 1 1 ] !head || !tail - elements of non-trivial runs
      lengths_and_num_runs[ITEM].key   = head_flags[ITEM] && (!tail_flags[ITEM]);
      lengths_and_num_runs[ITEM].value = ((!head_flags[ITEM]) || (!tail_flags[ITEM]));
    }
  }

  //---------------------------------------------------------------------
  // Scan utility methods
  //---------------------------------------------------------------------

  /**
   * Scan of allocations
   */
  _CCCL_DEVICE _CCCL_FORCEINLINE void WarpScanAllocations(
    LengthOffsetPair& tile_aggregate,
    LengthOffsetPair& warp_aggregate,
    LengthOffsetPair& warp_exclusive_in_tile,
    LengthOffsetPair& thread_exclusive_in_warp,
    LengthOffsetPair (&lengths_and_num_runs)[ITEMS_PER_THREAD])
  {
    // Perform warpscans
    unsigned int warp_id = ((WARPS == 1) ? 0 : threadIdx.x / WARP_THREADS);
    int lane_id          = ::cuda::ptx::get_sreg_laneid();

    LengthOffsetPair identity;
    identity.key   = 0;
    identity.value = 0;

    LengthOffsetPair thread_inclusive;

    // `thread_exclusive_in_warp.key`:
    //      number of non-trivial runs starts in previous threads
    // `thread_exclusive_in_warp.val`:
    //      number of items in the last non-trivial run in previous threads

    // `thread_aggregate.key`:
    //      number of non-trivial runs starts in this thread
    // `thread_aggregate.val`:
    //      number of items in the last non-trivial run in this thread
    LengthOffsetPair thread_aggregate = cub::ThreadReduce(lengths_and_num_runs, scan_op);
    WarpScanPairs(temp_storage.aliasable.scan_storage.warp_scan[warp_id])
      .Scan(thread_aggregate, thread_inclusive, thread_exclusive_in_warp, identity, scan_op);

    // `thread_inclusive.key`:
    //      number of non-trivial runs starts in this and previous warp threads
    // `thread_inclusive.val`:
    //      number of items in the last non-trivial run in this or previous warp threads

    // Last lane in each warp shares its warp-aggregate
    if (lane_id == WARP_THREADS - 1)
    {
      // `temp_storage.aliasable.scan_storage.warp_aggregates[warp_id].key`:
      //      number of non-trivial runs starts in this warp
      // `temp_storage.aliasable.scan_storage.warp_aggregates[warp_id].val`:
      //      number of items in the last non-trivial run in this warp
      temp_storage.aliasable.scan_storage.warp_aggregates.Alias()[warp_id] = thread_inclusive;
    }

    __syncthreads();

    // Accumulate total selected and the warp-wide prefix

    // `warp_exclusive_in_tile.key`:
    //      number of non-trivial runs starts in previous warps
    // `warp_exclusive_in_tile.val`:
    //      number of items in the last non-trivial run in previous warps
    warp_exclusive_in_tile = identity;
    warp_aggregate         = temp_storage.aliasable.scan_storage.warp_aggregates.Alias()[warp_id];

    // `tile_aggregate.key`:
    //      number of non-trivial runs starts in this CTA
    // `tile_aggregate.val`:
    //      number of items in the last non-trivial run in this CTA
    tile_aggregate = temp_storage.aliasable.scan_storage.warp_aggregates.Alias()[0];

    _CCCL_PRAGMA_UNROLL_FULL()
    for (int WARP = 1; WARP < WARPS; ++WARP)
    {
      if (warp_id == WARP)
      {
        warp_exclusive_in_tile = tile_aggregate;
      }

      tile_aggregate = scan_op(tile_aggregate, temp_storage.aliasable.scan_storage.warp_aggregates.Alias()[WARP]);
    }

    // Ensure all threads have read warp aggregates before temp_storage is repurposed in the
    // subsequent scatter stage
    __syncthreads();
  }

  //---------------------------------------------------------------------
  // Utility methods for scattering selections
  //---------------------------------------------------------------------

  /**
   * Two-phase scatter, specialized for warp time-slicing
   */
  _CCCL_DEVICE _CCCL_FORCEINLINE void ScatterTwoPhase(
    OffsetT tile_num_runs_exclusive_in_global,
    OffsetT warp_num_runs_aggregate,
    OffsetT warp_num_runs_exclusive_in_tile,
    OffsetT (&thread_num_runs_exclusive_in_warp)[ITEMS_PER_THREAD],
    LengthOffsetPair (&lengths_and_offsets)[ITEMS_PER_THREAD],
    ::cuda::std::true_type is_warp_time_slice)
  {
    unsigned int warp_id = ((WARPS == 1) ? 0 : threadIdx.x / WARP_THREADS);
    int lane_id          = ::cuda::ptx::get_sreg_laneid();

    // Locally compact items within the warp (first warp)
    if (warp_id == 0)
    {
      WarpExchangePairs(temp_storage.aliasable.scatter_aliasable.exchange_pairs[0])
        .ScatterToStriped(lengths_and_offsets, thread_num_runs_exclusive_in_warp);
    }

    // Locally compact items within the warp (remaining warps)
    _CCCL_PRAGMA_UNROLL_FULL()
    for (int SLICE = 1; SLICE < WARPS; ++SLICE)
    {
      __syncthreads();

      if (warp_id == SLICE)
      {
        WarpExchangePairs(temp_storage.aliasable.scatter_aliasable.exchange_pairs[0])
          .ScatterToStriped(lengths_and_offsets, thread_num_runs_exclusive_in_warp);
      }
    }

    // Global scatter
    _CCCL_PRAGMA_UNROLL_FULL()
    for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ITEM++)
    {
      // warp_num_runs_aggregate - number of non-trivial runs starts in current warp
      if ((ITEM * WARP_THREADS) < warp_num_runs_aggregate - lane_id)
      {
        OffsetT item_offset =
          tile_num_runs_exclusive_in_global + warp_num_runs_exclusive_in_tile + (ITEM * WARP_THREADS) + lane_id;

        // Scatter offset
        if constexpr (is_streaming_invocation)
        {
          d_offsets_out[streaming_context.num_uniques() + item_offset] =
            (streaming_context.base_offset() + lengths_and_offsets[ITEM].key);

          // Scatter length if not the first (global) length
          if (streaming_context.num_uniques() + item_offset > 0)
          {
            d_lengths_out[streaming_context.num_uniques() + item_offset - 1] = lengths_and_offsets[ITEM].value;
          }
        }
        else
        {
          d_offsets_out[item_offset] = lengths_and_offsets[ITEM].key;

          // Scatter length if not the first (global) length
          if ((ITEM != 0) || (item_offset > 0))
          {
            d_lengths_out[item_offset - 1] = lengths_and_offsets[ITEM].value;
          }
        }
      }
    }
  }

  /**
   * Two-phase scatter
   */
  _CCCL_DEVICE _CCCL_FORCEINLINE void ScatterTwoPhase(
    OffsetT tile_num_runs_exclusive_in_global,
    OffsetT warp_num_runs_aggregate,
    OffsetT warp_num_runs_exclusive_in_tile,
    OffsetT (&thread_num_runs_exclusive_in_warp)[ITEMS_PER_THREAD],
    LengthOffsetPair (&lengths_and_offsets)[ITEMS_PER_THREAD],
    ::cuda::std::false_type is_warp_time_slice)
  {
    unsigned int warp_id = ((WARPS == 1) ? 0 : threadIdx.x / WARP_THREADS);
    int lane_id          = ::cuda::ptx::get_sreg_laneid();

    // Unzip
    OffsetT run_offsets[ITEMS_PER_THREAD];
    LengthT run_lengths[ITEMS_PER_THREAD];

    _CCCL_PRAGMA_UNROLL_FULL()
    for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ITEM++)
    {
      run_offsets[ITEM] = lengths_and_offsets[ITEM].key;
      run_lengths[ITEM] = lengths_and_offsets[ITEM].value;
    }

    WarpExchangeOffsets(temp_storage.aliasable.scatter_aliasable.exchange_offsets[warp_id])
      .ScatterToStriped(run_offsets, thread_num_runs_exclusive_in_warp);

    __syncwarp(0xffffffff);

    WarpExchangeLengths(temp_storage.aliasable.scatter_aliasable.exchange_lengths[warp_id])
      .ScatterToStriped(run_lengths, thread_num_runs_exclusive_in_warp);

    // Global scatter
    _CCCL_PRAGMA_UNROLL_FULL()
    for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ITEM++)
    {
      if ((ITEM * WARP_THREADS) + lane_id < warp_num_runs_aggregate)
      {
        OffsetT item_offset =
          tile_num_runs_exclusive_in_global + warp_num_runs_exclusive_in_tile + (ITEM * WARP_THREADS) + lane_id;

        // Scatter offset
        if constexpr (is_streaming_invocation)
        {
          d_offsets_out[streaming_context.num_uniques() + item_offset] =
            (streaming_context.base_offset() + run_offsets[ITEM]);
          // Scatter length if not the first (global) length
          if ((ITEM != 0) || (streaming_context.num_uniques() + item_offset > 0))
          {
            d_lengths_out[streaming_context.num_uniques() + item_offset - 1] = run_lengths[ITEM];
          }
        }
        else
        {
          d_offsets_out[item_offset] = run_offsets[ITEM];
          // Scatter length if not the first (global) length
          if ((ITEM != 0) || (item_offset > 0))
          {
            d_lengths_out[item_offset - 1] = run_lengths[ITEM];
          }
        }
      }
    }
  }

  /**
   * Direct scatter
   */
  _CCCL_DEVICE _CCCL_FORCEINLINE void ScatterDirect(
    OffsetT tile_num_runs_exclusive_in_global,
    OffsetT warp_num_runs_aggregate,
    OffsetT warp_num_runs_exclusive_in_tile,
    OffsetT (&thread_num_runs_exclusive_in_warp)[ITEMS_PER_THREAD],
    LengthOffsetPair (&lengths_and_offsets)[ITEMS_PER_THREAD])
  {
    _CCCL_PRAGMA_UNROLL_FULL()
    for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ++ITEM)
    {
      if (thread_num_runs_exclusive_in_warp[ITEM] < warp_num_runs_aggregate)
      {
        OffsetT item_offset =
          tile_num_runs_exclusive_in_global + warp_num_runs_exclusive_in_tile + thread_num_runs_exclusive_in_warp[ITEM];

        // Scatter offset
        if constexpr (is_streaming_invocation)
        {
          // For streaming invocations, we need to add the base offset of the partition
          d_offsets_out[streaming_context.num_uniques() + item_offset] =
            (streaming_context.base_offset() + lengths_and_offsets[ITEM].key);

          // Scatter length if not the first (global) length
          if (streaming_context.num_uniques() + item_offset > 0)
          {
            d_lengths_out[streaming_context.num_uniques() + item_offset - 1] = lengths_and_offsets[ITEM].value;
          }
        }
        else
        {
          d_offsets_out[item_offset] = lengths_and_offsets[ITEM].key;

          // Scatter length if not the first (global) length
          if (item_offset > 0)
          {
            d_lengths_out[item_offset - 1] = lengths_and_offsets[ITEM].value;
          }
        }
      }
    }
  }

  /**
   * Scatter
   */
  _CCCL_DEVICE _CCCL_FORCEINLINE void Scatter(
    OffsetT tile_num_runs_aggregate,
    OffsetT tile_num_runs_exclusive_in_global,
    OffsetT warp_num_runs_aggregate,
    OffsetT warp_num_runs_exclusive_in_tile,
    OffsetT (&thread_num_runs_exclusive_in_warp)[ITEMS_PER_THREAD],
    LengthOffsetPair (&lengths_and_offsets)[ITEMS_PER_THREAD])
  {
    if ((ITEMS_PER_THREAD == 1) || (tile_num_runs_aggregate < BLOCK_THREADS))
    {
      // Direct scatter if the warp has any items
      if (warp_num_runs_aggregate)
      {
        ScatterDirect(tile_num_runs_exclusive_in_global,
                      warp_num_runs_aggregate,
                      warp_num_runs_exclusive_in_tile,
                      thread_num_runs_exclusive_in_warp,
                      lengths_and_offsets);
      }
    }
    else
    {
      // Scatter two phase
      ScatterTwoPhase(
        tile_num_runs_exclusive_in_global,
        warp_num_runs_aggregate,
        warp_num_runs_exclusive_in_tile,
        thread_num_runs_exclusive_in_warp,
        lengths_and_offsets,
        bool_constant_v<STORE_WARP_TIME_SLICING>);
    }
  }

  //---------------------------------------------------------------------
  // Cooperatively scan a device-wide sequence of tiles with other CTAs
  //---------------------------------------------------------------------

  /**
   * @brief Process a tile of input (dynamic chained scan)
   *
   * @param num_items
   *   Total number of global input items
   *
   * @param num_remaining
   *   Number of global input items remaining (including this tile)
   *
   * @param tile_idx
   *   Tile index
   *
   * @param tile_offset
   *   Tile offset
   *
   * @param &tile_status
   *   Global list of tile status
   */
  template <bool LAST_TILE>
  _CCCL_DEVICE _CCCL_FORCEINLINE LengthOffsetPair
  ConsumeTile(OffsetT num_items, OffsetT num_remaining, int tile_idx, OffsetT tile_offset, ScanTileStateT& tile_status)
  {
    if (tile_idx == 0)
    {
      // First tile

      // Load items
      T items[ITEMS_PER_THREAD];
      if (LAST_TILE)
      {
        BlockLoadT(temp_storage.aliasable.load).Load(d_in + tile_offset, items, num_remaining, T());
      }
      else
      {
        BlockLoadT(temp_storage.aliasable.load).Load(d_in + tile_offset, items);
      }

      if (SYNC_AFTER_LOAD)
      {
        __syncthreads();
      }

      // Set flags
      LengthOffsetPair lengths_and_num_runs[ITEMS_PER_THREAD];

      if constexpr (is_streaming_invocation)
      {
        if (streaming_context.first_partition)
        {
          if (streaming_context.last_partition)
          {
            InitializeSelections<true, LAST_TILE>(tile_offset, num_remaining, items, lengths_and_num_runs);
          }
          else
          {
            InitializeSelections<true, false>(tile_offset, num_remaining, items, lengths_and_num_runs);
          }
        }
        else
        {
          if (streaming_context.last_partition)
          {
            InitializeSelections<false, LAST_TILE>(tile_offset, num_remaining, items, lengths_and_num_runs);
          }
          else
          {
            InitializeSelections<false, false>(tile_offset, num_remaining, items, lengths_and_num_runs);
          }
        }
      }
      else
      {
        InitializeSelections<true, LAST_TILE>(tile_offset, num_remaining, items, lengths_and_num_runs);
      }

      // Exclusive scan of lengths and runs
      LengthOffsetPair tile_aggregate;
      LengthOffsetPair warp_aggregate;
      LengthOffsetPair warp_exclusive_in_tile;
      LengthOffsetPair thread_exclusive_in_warp;

      if constexpr (is_streaming_invocation)
      {
        // If this is a streaming invocation, we need to incorporate the run-length of the previous partition's last run
        if (!streaming_context.first_partition && threadIdx.x == 0)
        {
          lengths_and_num_runs[0].value += streaming_context.prefix();
        }
      }

      WarpScanAllocations(
        tile_aggregate, warp_aggregate, warp_exclusive_in_tile, thread_exclusive_in_warp, lengths_and_num_runs);

      // Update tile status if this is not the last tile
      if (!LAST_TILE && (threadIdx.x == 0))
      {
        tile_status.SetInclusive(0, tile_aggregate);
      }

      // Update thread_exclusive_in_warp to fold in warp run-length
      if (thread_exclusive_in_warp.key == 0)
      {
        // If there are no non-trivial runs starts in the previous warp threads, then
        // `thread_exclusive_in_warp.val` denotes the number of items in the last
        // non-trivial run of the previous CTA threads, so the better name for it is
        // `thread_exclusive_in_tile`.
        thread_exclusive_in_warp.value += warp_exclusive_in_tile.value;
      }

      LengthOffsetPair lengths_and_offsets[ITEMS_PER_THREAD];
      OffsetT thread_num_runs_exclusive_in_warp[ITEMS_PER_THREAD];
      LengthOffsetPair lengths_and_num_runs2[ITEMS_PER_THREAD];

      // Downsweep scan through lengths_and_num_runs
      detail::ThreadScanExclusive(lengths_and_num_runs, lengths_and_num_runs2, scan_op, thread_exclusive_in_warp);

      // Zip
      _CCCL_PRAGMA_UNROLL_FULL()
      for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ITEM++)
      {
        lengths_and_offsets[ITEM].value = lengths_and_num_runs2[ITEM].value;
        lengths_and_offsets[ITEM].key   = tile_offset + (threadIdx.x * ITEMS_PER_THREAD) + ITEM;
        thread_num_runs_exclusive_in_warp[ITEM] =
          (lengths_and_num_runs[ITEM].key) ? lengths_and_num_runs2[ITEM].key : // keep
            WARP_THREADS * ITEMS_PER_THREAD; // discard
      }

      OffsetT tile_num_runs_aggregate           = tile_aggregate.key;
      OffsetT tile_num_runs_exclusive_in_global = 0;
      OffsetT warp_num_runs_aggregate           = warp_aggregate.key;
      OffsetT warp_num_runs_exclusive_in_tile   = warp_exclusive_in_tile.key;

      // Scatter
      Scatter(tile_num_runs_aggregate,
              tile_num_runs_exclusive_in_global,
              warp_num_runs_aggregate,
              warp_num_runs_exclusive_in_tile,
              thread_num_runs_exclusive_in_warp,
              lengths_and_offsets);

      // Return running total (inclusive of this tile)
      return tile_aggregate;
    }
    else
    {
      // Not first tile

      // Load items
      T items[ITEMS_PER_THREAD];
      if (LAST_TILE)
      {
        BlockLoadT(temp_storage.aliasable.load).Load(d_in + tile_offset, items, num_remaining, T());
      }
      else
      {
        BlockLoadT(temp_storage.aliasable.load).Load(d_in + tile_offset, items);
      }

      if (SYNC_AFTER_LOAD)
      {
        __syncthreads();
      }

      // Set flags
      LengthOffsetPair lengths_and_num_runs[ITEMS_PER_THREAD];

      if constexpr (is_streaming_invocation)
      {
        if (streaming_context.last_partition)
        {
          InitializeSelections<false, LAST_TILE>(tile_offset, num_remaining, items, lengths_and_num_runs);
        }
        else
        {
          InitializeSelections<false, false>(tile_offset, num_remaining, items, lengths_and_num_runs);
        }
      }
      else
      {
        InitializeSelections<false, LAST_TILE>(tile_offset, num_remaining, items, lengths_and_num_runs);
      }

      // Exclusive scan of lengths and runs
      LengthOffsetPair tile_aggregate;
      LengthOffsetPair warp_aggregate;
      LengthOffsetPair warp_exclusive_in_tile;
      LengthOffsetPair thread_exclusive_in_warp;

      WarpScanAllocations(
        tile_aggregate, warp_aggregate, warp_exclusive_in_tile, thread_exclusive_in_warp, lengths_and_num_runs);

      // First warp computes tile prefix in lane 0
      TilePrefixCallbackOpT prefix_op(
        tile_status, temp_storage.aliasable.scan_storage.prefix, ::cuda::std::plus<>{}, tile_idx);
      unsigned int warp_id = ((WARPS == 1) ? 0 : threadIdx.x / WARP_THREADS);
      if (warp_id == 0)
      {
        prefix_op(tile_aggregate);
        if (threadIdx.x == 0)
        {
          temp_storage.tile_exclusive = prefix_op.exclusive_prefix;
        }
      }

      __syncthreads();

      LengthOffsetPair tile_exclusive_in_global = temp_storage.tile_exclusive;

      // Update thread_exclusive_in_warp to fold in warp and tile run-lengths
      LengthOffsetPair thread_exclusive = scan_op(tile_exclusive_in_global, warp_exclusive_in_tile);
      if (thread_exclusive_in_warp.key == 0)
      {
        // If there are no non-trivial runs starts in the previous warp threads, then
        // `thread_exclusive_in_warp.val` denotes the number of items in the last
        // non-trivial run of the previous grid threads, so the better name for it is
        // `thread_exclusive_in_grid`.
        thread_exclusive_in_warp.value += thread_exclusive.value;
      }

      // Downsweep scan through lengths_and_num_runs

      // `lengths_and_num_runs2.key`:
      //      number of non-trivial runs starts in previous grid threads
      // `lengths_and_num_runs2.val`:
      //      number of items in the last non-trivial run in previous grid threads
      LengthOffsetPair lengths_and_num_runs2[ITEMS_PER_THREAD];

      // `lengths_and_offsets.key`:
      //      offset to the item in the input sequence
      // `lengths_and_offsets.val`:
      //      number of items in the last non-trivial run in previous grid threads
      LengthOffsetPair lengths_and_offsets[ITEMS_PER_THREAD];
      OffsetT thread_num_runs_exclusive_in_warp[ITEMS_PER_THREAD];

      detail::ThreadScanExclusive(lengths_and_num_runs, lengths_and_num_runs2, scan_op, thread_exclusive_in_warp);

      // Zip
      _CCCL_PRAGMA_UNROLL_FULL()
      for (int ITEM = 0; ITEM < ITEMS_PER_THREAD; ITEM++)
      {
        lengths_and_offsets[ITEM].value = lengths_and_num_runs2[ITEM].value;
        lengths_and_offsets[ITEM].key   = tile_offset + (threadIdx.x * ITEMS_PER_THREAD) + ITEM;
        thread_num_runs_exclusive_in_warp[ITEM] =
          (lengths_and_num_runs[ITEM].key) ? lengths_and_num_runs2[ITEM].key : // keep
            WARP_THREADS * ITEMS_PER_THREAD; // discard
      }

      OffsetT tile_num_runs_aggregate           = tile_aggregate.key;
      OffsetT tile_num_runs_exclusive_in_global = tile_exclusive_in_global.key;
      OffsetT warp_num_runs_aggregate           = warp_aggregate.key;
      OffsetT warp_num_runs_exclusive_in_tile   = warp_exclusive_in_tile.key;

      // Scatter
      Scatter(tile_num_runs_aggregate,
              tile_num_runs_exclusive_in_global,
              warp_num_runs_aggregate,
              warp_num_runs_exclusive_in_tile,
              thread_num_runs_exclusive_in_warp,
              lengths_and_offsets);

      // Return running total (inclusive of this tile)
      return prefix_op.inclusive_prefix;
    }
  }

  /**
   * @brief Scan tiles of items as part of a dynamic chained scan
   *
   * @param num_tiles
   *   Total number of input tiles
   *
   * @param tile_status
   *   Global list of tile status
   *
   * @param d_num_runs_out
   *   Output pointer for total number of runs identified
   *
   * @tparam NumRunsIteratorT
   *   Output iterator type for recording number of items selected
   */
  template <typename NumRunsIteratorT>
  _CCCL_DEVICE _CCCL_FORCEINLINE void
  ConsumeRange(int num_tiles, ScanTileStateT& tile_status, NumRunsIteratorT d_num_runs_out)
  {
    // Blocks are launched in increasing order, so just assign one tile per block
    int tile_idx          = (blockIdx.x * gridDim.y) + blockIdx.y; // Current tile index
    OffsetT tile_offset   = static_cast<OffsetT>(tile_idx) * static_cast<OffsetT>(TILE_ITEMS);
    OffsetT num_remaining = num_items - tile_offset; // Remaining items (including this tile)

    if (tile_idx < num_tiles - 1)
    {
      // Not the last tile (full)
      ConsumeTile<false>(num_items, num_remaining, tile_idx, tile_offset, tile_status);
    }
    else if (num_remaining > 0)
    {
      // The last tile (possibly partially-full)
      LengthOffsetPair running_total = ConsumeTile<true>(num_items, num_remaining, tile_idx, tile_offset, tile_status);

      if (threadIdx.x == 0)
      {
        if constexpr (is_streaming_invocation)
        {
          // Add the number of unique items in this partition to the global aggregate
          auto total_uniques = streaming_context.add_num_uniques(running_total.key);

          // If this is the last partition, write out the number of unique items
          if (streaming_context.last_partition)
          {
            // Output the total number of items selected
            *d_num_runs_out = total_uniques;

            // The inclusive prefix contains accumulated length reduction for the last run
            if (running_total.key + streaming_context.num_uniques() > 0)
            {
              d_lengths_out[streaming_context.num_uniques() + running_total.key - 1] = running_total.value;
            }
          }

          if (!streaming_context.last_partition)
          {
            // Write the run-length of this partition as context for the subsequent partition
            streaming_context.write_prefix(running_total.value);
          }
        }
        else
        {
          // Output the total number of items selected
          *d_num_runs_out = running_total.key;

          // The inclusive prefix contains accumulated length reduction for the last run
          if (running_total.key > 0)
          {
            d_lengths_out[running_total.key - 1] = running_total.value;
          }
        }
      }
    }
  }
};

} // namespace rle
} // namespace detail

CUB_NAMESPACE_END
