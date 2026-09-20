# The collector as Ruby sees it: one heap, collected on demand. CRuby
# writes most of GC in Ruby (its gc.rb), so those methods answer their
# own parameters, under CRuby's names.
module GC
  def self.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
    Primitive.attr! :ruby
    Primitive.zr_gc_start
  end

  def self.count = Primitive.zr_gc_count
  def self.disable = Primitive.zr_gc_set_disabled(true)
  def self.enable = Primitive.zr_gc_set_disabled(false)
  def self.stress = Primitive.zr_gc_stress
  def self.stress=(flag)
    Primitive.attr! :ruby
    Primitive.zr_gc_set_stress(flag)
  end

  # Every key CRuby's collector answers, in its order. One arena here is
  # a page, and nothing is moved or finalized later. A collection is
  # minor or major as `zr_collect` decides, and the counts and the two
  # phase times say which ran and what each cost -- the trace and the
  # sweep are asked apart because a minor traces only the young while
  # its sweep still walks every arena.
  def self.stat(hash_or_key = nil)
    Primitive.attr! :ruby
    total, free = Primitive.zr_objspace_census
    pages = Primitive.zr_gc_arenas
    live = total - free
    allocated = Primitive.zr_gc_allocated
    count = Primitive.zr_gc_count
    majors, marking, sweeping = Primitive.zr_gc_phases
    stats = {
      count: count, time: Primitive.zr_gc_nanoseconds / 1_000_000,
      marking_time: marking / 1_000_000, sweeping_time: sweeping / 1_000_000,
      heap_allocated_pages: pages, heap_empty_pages: 0, heap_allocatable_slots: 0, heap_available_slots: total,
      heap_live_slots: live, heap_free_slots: free, heap_final_slots: 0, heap_marked_slots: 0, heap_eden_pages: pages,
      total_allocated_pages: pages, total_freed_pages: 0, total_allocated_objects: allocated,
      total_freed_objects: [allocated - live, 0].max, malloc_increase_bytes: Primitive.zr_gc_malloced,
      malloc_increase_bytes_limit: Primitive.zr_gc_malloc_limit,
      minor_gc_count: count - majors, major_gc_count: majors, compact_count: 0, read_barrier_faults: 0, total_moved_objects: 0,
      remembered_wb_unprotected_objects: 0, remembered_wb_unprotected_objects_limit: 0, old_objects: 0,
      old_objects_limit: 0, oldmalloc_increase_bytes: 0, oldmalloc_increase_bytes_limit: 16 * 1024 * 1024
    }
    case hash_or_key
    when nil then stats
    when Hash then hash_or_key.merge!(stats)
    when Symbol
      stats.fetch(hash_or_key) { raise ArgumentError, "unknown key: #{hash_or_key}" }
    else
      raise TypeError, "non-hash or symbol given"
    end
  end

  # The one collector here runs a full mark and sweep every time.
  def self.latest_gc_info(hash_or_key = nil)
    Primitive.attr! :ruby
    info = {
      major_by: :force, need_major_by: nil, gc_by: :method, have_finalizer: false,
      immediate_sweep: true, state: :none, weak_references_count: 0, retained_weak_references_count: 0
    }
    return info if hash_or_key.nil?
    return info.fetch(hash_or_key) if info.key?(hash_or_key)

    raise ArgumentError, "unknown key: #{hash_or_key}"
  end

  # The switch a program reads before it asks for a report. The
  # collector keeps no per-run rows, so the report is empty.
  module Profiler
    @enabled = false

    class << self
      def enable
        @enabled = true
        nil
      end

      def disable
        @enabled = false
        nil
      end

      def enabled? = @enabled

      def clear = nil

      def total_time = 0.0

      def result = ""

      def raw_data = nil

      def report(out = $stdout)
        out.write(result)
        nil
      end
    end
  end

  # The build options CRuby reports; this collector is built with none
  # of its own to add.
  OPTS = %w[USE_RGENGC RGENGC_ESTIMATE_OLDMALLOC GC_ENABLE_LAZY_SWEEP GC_COMPACTION_SUPPORTED].freeze

  # The heap's own sizes: cells of 32 to 256 bytes in 4 MiB arenas.
  INTERNAL_CONSTANTS = {
    DEBUG: false, BASE_SLOT_SIZE: 32, RBASIC_SIZE: 16, RVALUE_OVERHEAD: 0, HEAP_PAGE_OBJ_LIMIT: 131_064,
    HEAP_PAGE_BITMAP_SIZE: 16_384, HEAP_PAGE_SIZE: 4_194_304, HEAP_COUNT: 5, RVARGC_MAX_ALLOCATE_SIZE: 256, RVALUE_OLD_AGE: 3
  }.freeze

  # Nothing moves here, so a compaction considers no object at all.
  def self.compact = latest_compact_info

  def self.latest_compact_info = { considered: {}, moved: {}, moved_up: {}, moved_down: {} }

  def self.verify_compaction_references(**options) = compact

  def self.auto_compact = false

  def self.auto_compact=(flag)
    flag
  end

  def self.verify_internal_consistency = nil

  # The nanoseconds the collector has spent, measured on the monotonic
  # clock around every mark and sweep.
  def self.total_time = Primitive.zr_gc_nanoseconds

  @measure_total_time = true

  def self.measure_total_time = @measure_total_time

  def self.measure_total_time=(flag)
    Primitive.attr! :ruby
    @measure_total_time = flag
  end

  def self.config(hash = nil)
    Primitive.attr! :ruby
    { rgengc_allow_full_mark: true, implementation: "default" }
  end

  # The four pools of 32, 64, 128 and 256-byte cells, and a fifth that
  # stays empty, so a pool index ruby answers is answered here too.
  POOLS = 5
  private_constant :POOLS

  # One pool's numbers, or every pool's under its index, as
  # rb_gc_impl_stat_heap answers them: into the Hash given, or one of
  # them by name.
  def self.stat_heap(heap_name = nil, hash_or_key = nil)
    Primitive.attr! :ruby
    if heap_name.nil?
      raise TypeError, "non-hash given" unless hash_or_key.nil? || hash_or_key.is_a?(Hash)

      out = hash_or_key || {}
      POOLS.times { |pool| out[pool] = pool_stats(pool, out[pool].is_a?(Hash) ? out[pool] : {}) }
      return out
    end
    raise TypeError, "heap_name must be nil or an Integer" unless heap_name.is_a?(Integer)
    raise ArgumentError, "size pool index out of range" unless (0...POOLS).cover?(heap_name)

    case hash_or_key
    when nil then pool_stats(heap_name, {})
    when Hash then pool_stats(heap_name, hash_or_key)
    when Symbol then pool_stats(heap_name, {}).fetch(hash_or_key) { raise ArgumentError, "unknown key: #{hash_or_key}" }
    else raise TypeError, "non-hash or symbol given"
    end
  end

  # Pool `pool`'s numbers written into `out`, in CRuby's key order. An
  # arena here is a page; nothing waits to be finalized or forces a
  # major collection.
  def self.pool_stats(pool, out)
    Primitive.attr! :hidden
    slot_size, live, free, pages, allocated = Primitive.zr_gc_pool(pool)
    out.merge!(
      slot_size: slot_size, heap_live_slots: live, heap_free_slots: free, heap_final_slots: 0,
      heap_eden_pages: pages, heap_eden_slots: live + free, total_allocated_pages: pages,
      force_major_gc_count: 0, force_incremental_marking_finish_count: 0,
      total_allocated_objects: allocated, total_freed_objects: [allocated - live, 0].max
    )
  end
  private_class_method :pool_stats

  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true)
    Primitive.attr! :ruby
    Primitive.zr_gc_start
  end
end

module Process
  def pid = Primitive.zr_process_id

  def clock_gettime(id, unit = :float_second)
    Process.send(:in_unit, Primitive.zr_clock_ns(Process.send(:clock_id, id, "clock_gettime")), unit)
  end

  def clock_getres(id, unit = :float_second)
    Process.send(:in_unit, Primitive.zr_clock_res_ns(Process.send(:clock_id, id, "clock_getres")), unit)
  end

  def uid = Primitive.zr_process_ids(0)
  def euid = Primitive.zr_process_ids(1)
  def gid = Primitive.zr_process_ids(2)
  def egid = Primitive.zr_process_ids(3)

  module_function :pid, :clock_gettime, :clock_getres, :uid, :euid, :gid, :egid

  # A clock is a raw id or the name of one of this module's own CLOCK_
  # constants. The symbol spelling is the portable one: a platform that
  # lacks the clock answers a rescuable Errno::EINVAL here rather than a
  # NameError at the constant read. An OS whose clocks ruby names with
  # Symbols (WASI) maps each to its id in CLOCK_IDS.
  def self.clock_id(id, verb)
    Primitive.attr! :hidden
    return Primitive.zr_index_operand_m(id) unless id.is_a?(Symbol)
    return CLOCK_IDS.fetch(id) if CLOCK_IDS.key?(id)
    raise Errno::EINVAL, "#{verb}(#{id.inspect})" unless id.start_with?("CLOCK_") && const_defined?(id)

    clock_id(const_get(id), verb)
  end

  def self.in_unit(ns, unit)
    Primitive.attr! :hidden
    case unit
    when :float_second then ns.to_f / 1e9
    when :float_millisecond then ns.to_f / 1e6
    when :float_microsecond then ns.to_f / 1e3
    when :second then ns / 1_000_000_000
    when :millisecond then ns / 1_000_000
    when :microsecond then ns / 1000
    when :nanosecond then ns
    else raise ArgumentError, "unexpected unit: #{unit}"
    end
  end
  private_class_method :in_unit
end
