# frozen_string_literal: true

# The collector as Ruby sees it: one heap, collected on demand. CRuby
# writes most of GC in Ruby (its gc.rb), so those methods return their
# own parameters, under CRuby's names.
module GC
  # One heap serves every Ractor here, so a collection is always global.
  def self.start(full_mark: true, immediate_mark: true, immediate_sweep: true, global: true)
    Primitive.attr! :ruby
    Primitive.zr_gc_start_m(full_mark, immediate_sweep)
    nil
  end

  def self.count = Primitive.zr_gc_count
  def self.disable = Primitive.zr_gc_set_disabled(true)
  def self.enable = Primitive.zr_gc_set_disabled(false)
  # A number sets CRuby's stress flags; this collector reads it as on,
  # and returns the number it was given, as ruby does.
  STRESS = [nil]
  private_constant :STRESS

  def self.stress = Primitive.zr_gc_stress && STRESS[0].is_a?(Integer) ? STRESS[0] : Primitive.zr_gc_stress
  def self.stress=(flag)
    Primitive.attr! :ruby
    STRESS[0] = flag
    Primitive.zr_gc_set_stress(flag)
  end

  # Every key that CRuby's collector returns, in its order. One arena here
  # is a page, and nothing is moved or finalized later. `zr_collect`
  # decides whether a collection is minor or major. The counts and the two
  # phase times show which ran and what each cost. The trace and the sweep
  # are measured separately because a minor collection traces only the
  # young objects, but its sweep still walks every arena. The :global
  # scope gives the counts that all Ractors share; one heap here has no
  # global cycle of its own.
  def self.stat(hash_or_key = nil, scope: :ractor)
    Primitive.attr! :ruby
    raise ArgumentError, "unknown scope: #{scope.inspect}" unless %i[ractor local global].include?(scope)

    # A counter that the collector keeps returns its value with no walk
    # of the heap, which the slot counts need.
    if hash_or_key.is_a?(Symbol) && (scope != :global || GLOBAL_KEYS.include?(hash_or_key))
      counted = counter(hash_or_key)
      return counted unless counted.nil?
    end
    pages, freed_pages = Primitive.zr_gc_pages
    count = Primitive.zr_gc_count
    majors, marking, sweeping = Primitive.zr_gc_phases
    malloc_total, free_total = Primitive.zr_gc_malloc_totals
    stats = {
      count: count, time: Primitive.zr_gc_nanoseconds / 1_000_000,
      marking_time: marking / 1_000_000, sweeping_time: sweeping / 1_000_000,
      total_malloc_bytes: malloc_total, total_free_bytes: free_total,
      heap_allocated_pages: pages, heap_empty_pages: 0, heap_allocatable_bytes: 0, heap_eden_pages: pages,
      total_allocated_pages: pages + freed_pages, total_freed_pages: freed_pages,
      malloc_increase_bytes: Primitive.zr_gc_malloced, malloc_increase_bytes_limit: Primitive.zr_gc_malloc_limit,
      minor_gc_count: count - majors, major_gc_count: majors, global_gc_count: 0, compact_count: COMPACTED[1],
      read_barrier_faults: 0, total_moved_objects: 0,
      remembered_wb_unprotected_objects: 0, remembered_wb_unprotected_objects_limit: 0, old_objects: 0,
      old_objects_limit: 0, oldmalloc_increase_bytes: 0, oldmalloc_increase_bytes_limit: 16 * 1024 * 1024,
      total_allocated_objects: 0, total_freed_objects: 0,
      heap_available_slots: 0, heap_live_slots: 0, heap_free_slots: 0, heap_final_slots: 0, heap_marked_slots: 0,
      page_pool_arenas: pages, page_pool_arenas_freed: freed_pages, page_pool_total_pages: pages + freed_pages,
      page_pool_discarded_pages: 0
    }
    stats = stats.slice(*GLOBAL_KEYS) if scope == :global
    # The census comes after every allocation of this call, so the slot
    # counts agree with ObjectSpace.count_objects, as CRuby's stat
    # allocates nothing.
    total, free = Primitive.zr_objspace_census
    live = total - free
    allocated = Primitive.zr_gc_allocated
    unless scope == :global
      stats[:heap_available_slots] = total
      stats[:heap_live_slots] = live
      stats[:heap_free_slots] = free
      stats[:total_allocated_objects] = allocated
      stats[:total_freed_objects] = allocated > live ? allocated - live : 0
    end
    case hash_or_key
    when nil then stats
    when Hash
      # Pair by pair, as rb_hash_aset, so nothing is allocated after the census.
      Primitive.zr_hash_foreach(stats) { |key, value| Primitive.zr_hash_aset_m(hash_or_key, key, value) }
      hash_or_key
    when Symbol
      raise ArgumentError, "unknown key: #{hash_or_key}" unless stats.key?(hash_or_key)

      stats[hash_or_key]
    else
      raise TypeError, +"non-hash or symbol given"
    end
  end

  # The tuning variables that rb_gc_impl_set_params reads, in its order,
  # each with its default, its bounds and whether 0 passes: a size
  # (strtoll with a k, m or g suffix) or a double (strtod). Under -w each
  # one that is set prints what became of it, in CRuby's words.
  TUNING = [
    [:size, "RUBY_GC_HEAP_FREE_SLOTS", 4096, 0],
    [:size, "RUBY_GC_HEAP_INIT_BYTES", 2560 * 1024, 1023],
    [:size, "RUBY_GC_RACTOR_HEAP_INIT_BYTES", 0, 1023],
    [:double, "RUBY_GC_HEAP_GROWTH_FACTOR", 1.8, 1.0, 0.0, false],
    [:size, "RUBY_GC_HEAP_GROWTH_MAX_BYTES", 0, 0],
    [:double, "RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO", 0.20, 0.0, 1.0, false],
    [:double, "RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO", 0.65, :min_ratio, 1.0, false],
    [:double, "RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO", 0.40, :min_ratio, :max_ratio, true],
    [:double, "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR", 2.0, 0.0, 0.0, true],
    [:double, "RUBY_GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO", 0.01, 0.0, 0.0, true],
    [:size, "RUBY_GC_MALLOC_LIMIT", 16 * 1024 * 1024, 0],
    [:size, "RUBY_GC_MALLOC_LIMIT_MAX", 32 * 1024 * 1024, 0],
    [:double, "RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR", 1.4, 1.0, 0.0, false],
    [:size, "RUBY_GC_OLDMALLOC_LIMIT", 16 * 1024 * 1024, 0],
    [:size, "RUBY_GC_OLDMALLOC_LIMIT_MAX", 128 * 1024 * 1024, 0],
    [:double, "RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR", 1.2, 1.0, 0.0, false]
  ].freeze
  private_constant :TUNING

  # rb_gc_impl_set_params, once, as a program starts: the collector takes
  # the old-object limit factor; the other values only answer as CRuby's.
  def self.read_tuning
    Primitive.attr! :hidden
    values = {}
    TUNING.each do |kind, name, default, *rest|
      text = Primitive.zr_environment_get(name)
      next values[name] = default if text.nil? || text.empty?

      values[name] = kind == :size ? tuning_size(name, text, default, *rest) : tuning_double(name, text, default, *rest.map { tuning_bound(it, values) })
    end
    Primitive.zr_gc_old_factor_set_m((values["RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR"] * 100).round)
    nil
  end

  # A ratio bound that an earlier variable sets.
  def self.tuning_bound(bound, values)
    Primitive.attr! :hidden
    case bound
    when :min_ratio then values["RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO"]
    when :max_ratio then values["RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO"]
    else bound
    end
  end

  # get_envparam_size.
  def self.tuning_size(name, text, default, lower)
    Primitive.attr! :hidden
    m = text.match(/\A\s*([-+]?(?:0[xX]\h+|0[0-7]*|[1-9]\d*))([kKmMgG]?)\s*\z/)
    unless m
      $stderr.write("invalid string for #{name}: #{text}\n") if $VERBOSE
      return default
    end
    val = Integer(m[1], m[1].match?(/\A[-+]?0[xX]/) ? 16 : (m[1].match?(/\A[-+]?0\d/) ? 8 : 10))
    unit = { "k" => 1024, "m" => 1024**2, "g" => 1024**3 }[m[2].downcase] || 0
    if unit.positive?
      if val.abs > (2**63 - 1) / unit
        $stderr.write("#{name}=#{text} is ignored because it overflows\n") if $VERBOSE
        return default
      end
      val *= unit
    end
    if val.positive? && val > lower
      $stderr.write("#{name}=#{val} (default value: #{default})\n") if $VERBOSE
      return val
    end
    $stderr.write("#{name}=#{val} (default value: #{default}) is ignored because it must be greater than #{lower}.\n") if $VERBOSE
    default
  end

  # get_envparam_double.
  def self.tuning_double(name, text, default, lower, upper, accept_zero)
    Primitive.attr! :hidden
    val = begin
      Float(text.strip.empty? ? "x" : text)
    rescue ArgumentError
      nil
    end
    if val.nil?
      $stderr.write("invalid string for #{name}: #{text}\n") if $VERBOSE
      return default
    end
    shown = ->(x) { format("%f", x) }
    unless accept_zero && val.zero?
      if val <= lower
        $stderr.write("#{name}=#{shown.(val)} (default value: #{shown.(default)}) is ignored because it must be greater than #{shown.(lower)}.\n") if $VERBOSE
        return default
      end
      if upper != 0.0 && val > upper
        $stderr.write("#{name}=#{shown.(val)} (default value: #{shown.(default)}) is ignored because it must be lower than #{shown.(upper)}.\n") if $VERBOSE
        return default
      end
    end
    $stderr.write("#{name}=#{shown.(val)} (default value: #{shown.(default)})\n") if $VERBOSE
    val
  end
  private_class_method :read_tuning, :tuning_bound, :tuning_size, :tuning_double

  # The keys of GC.stat(scope: :global).
  GLOBAL_KEYS = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count].freeze
  private_constant :GLOBAL_KEYS

  def self.counter(key)
    Primitive.attr! :hidden
    case key
    when :global_gc_count then 0
    when :total_malloc_bytes then Primitive.zr_gc_malloc_totals[0]
    when :total_free_bytes then Primitive.zr_gc_malloc_totals[1]
    when :count then Primitive.zr_gc_count
    when :time then Primitive.zr_gc_nanoseconds / 1_000_000
    when :marking_time then Primitive.zr_gc_phases[1] / 1_000_000
    when :sweeping_time then Primitive.zr_gc_phases[2] / 1_000_000
    when :major_gc_count then Primitive.zr_gc_phases[0]
    when :minor_gc_count then Primitive.zr_gc_count - Primitive.zr_gc_phases[0]
    when :total_allocated_objects then Primitive.zr_gc_allocated
    when :malloc_increase_bytes then Primitive.zr_gc_malloced
    when :malloc_increase_bytes_limit then Primitive.zr_gc_malloc_limit
    when :total_freed_pages then Primitive.zr_gc_pages[1]
    when :compact_count then COMPACTED[1]
    end
  end
  private_class_method :counter

  # What the last collection was, in CRuby's words: why it was major (nil
  # for a minor), whether the next must be, and what started it. Every
  # sweep here finishes at once, but one that ruby does lazily (any that
  # GC.start did not ask to be immediate) reads as still :sweeping, as
  # ruby's does until its sweep ends.
  def self.latest_gc_info(hash_or_key = nil)
    Primitive.attr! :ruby
    bits, due, weak = Primitive.zr_gc_info
    info = {
      major_by: MAJOR_BY[bits >> 3], need_major_by: (:oldgen if due),
      gc_by: if bits.anybits?(1) then :method
             elsif bits.anybits?(2) then :malloc
             else :newobj
             end,
      have_finalizer: false, immediate_sweep: bits.nobits?(4), state: bits.anybits?(4) ? :sweeping : :none,
      weak_references_count: weak
    }
    case hash_or_key
    when nil then info
    when Hash then hash_or_key.merge!(info)
    when Symbol
      raise ArgumentError, "unknown key: #{hash_or_key}" unless info.key?(hash_or_key)

      info[hash_or_key]
    else raise TypeError, +"non-hash or symbol given"
    end
  end

  # Heap#last_info's reason for a major, by its bits from 8 up.
  MAJOR_BY = [nil, :force, :oldgen, :nofree].freeze
  private_constant :MAJOR_BY

  # One record per collection while the profiler is enabled, as CRuby's
  # gc_profile_record: the collector appends the numbers
  # (`zr_gc_profile_push`), and the rows here are built from them. The
  # records stay through a disable, and only `clear` drops them.
  module Profiler
    @enabled = false

    # configure's mark for no max_records given.
    UNSET = Object.new.freeze
    private_constant :UNSET

    class << self
      def enable
        @enabled = true
        Primitive.zr_gc_profile_set(true)
      end

      def disable
        @enabled = false
        Primitive.zr_gc_profile_set(false)
      end

      def enabled? = @enabled

      def clear = Primitive.zr_gc_profile_clear

      def total_time = rows.sum(0.0) { |row| row[:GC_TIME] }

      # The records, oldest first: the last `limit` of them, of those
      # numbered after `since`.
      def raw_data(limit: nil, since: nil)
        limit = count_of(limit, "limit")
        since = count_of(since, "since")
        return nil unless @enabled

        records = rows
        records = records.select { |row| row[:GC_SEQUENCE] > since } if since
        limit && limit < records.size ? records.last(limit) : records
      end

      # Keeps at most `max_records` records (nil for no bound), and drops
      # the records so far.
      def configure(max_records: UNSET)
        return nil if UNSET.equal?(max_records)

        unless max_records.nil?
          max_records = Primitive.zr_index_operand_m(max_records)
          raise ArgumentError, +"max_records must be positive or nil" unless max_records.positive?
        end
        Primitive.zr_gc_profile_configure(max_records)
      end

      def result
        records = rows
        return +"" if records.empty?

        out = +"GC #{GC.count} invokes.\n"
        out << "Index    Invoke Time(sec)       Use Size(byte)     Total Size(byte)         Total Object                    GC Time(ms)\n"
        records.each.with_index(1) do |row, i|
          out << format("%5d %19.3f %20d %20d %20d %30.20f\n", i, row[:GC_INVOKE_TIME], row[:HEAP_USE_SIZE],
                        row[:HEAP_TOTAL_SIZE], row[:HEAP_TOTAL_OBJECTS], row[:GC_TIME] * 1000)
        end
        out
      end

      def report(out = $stdout)
        out.write(result)
        nil
      end

      private

      # A non-negative count argument (NUM2LONG), or nil.
      def count_of(value, name)
        return nil if value.nil?

        value = Primitive.zr_index_operand_m(value)
        raise ArgumentError, "#{name} must be non-negative" if value.negative?

        value
      end

      # A collection's flags as CRuby gives them: GC.start (or stress)
      # asked for it and swept at once; the collector started any other one
      # for an allocation. The whole collection stops the program here, so
      # its wall time is its pause and its stop-the-world time; nothing
      # waits to stop other threads, and nothing is compacted.
      def rows
        weak = Primitive.zr_gc_info[2]
        Primitive.zr_gc_profile_rows.map do |row|
          started, took, live, total, slots, flags, mark, sweep, sequence = row
          asked = flags.anybits?(2)
          major_by = (asked ? :force : :oldgen) if flags.anybits?(1)
          { GC_FLAGS: { major_by: major_by, gc_by: asked ? :method : :newobj, have_finalizer: false, immediate_sweep: asked,
                        weak_references_count: weak },
            GC_SEQUENCE: sequence, GC_TIME: took / 1e9, GC_INVOKE_TIME: (started - STARTED) / 1e9,
            GC_WALL_TIME: took / 1e9, GC_INVOKE_WALL_TIME: (started - STARTED) / 1e9, GC_PAUSE_TIME: took / 1e9,
            GC_STOP_TIME: 0.0, GC_STW_TIME: took / 1e9, GC_MARK_WALL_TIME: mark / 1e9, GC_SWEEP_WALL_TIME: sweep / 1e9,
            GC_COMPACT_WALL_TIME: 0.0, HEAP_USE_SIZE: live, HEAP_TOTAL_SIZE: total,
            HEAP_TOTAL_OBJECTS: slots, MOVED_OBJECTS: 0, GC_IS_MARKED: true }
        end
      end
    end
  end

  # The build options CRuby reports; this collector is built with none
  # of its own to add.
  OPTS = %w[USE_RGENGC RGENGC_ESTIMATE_OLDMALLOC GC_ENABLE_LAZY_SWEEP GC_COMPACTION_SUPPORTED].freeze

  # The sizes that CRuby's heap reports (RVALUE_SIZE and the rest); this
  # heap's own cells and arenas differ, and nothing here reads them.
  INTERNAL_CONSTANTS = {
    DEBUG: false, RVALUE_SIZE: 40, RBASIC_SIZE: 16, RVALUE_OVERHEAD: 0, HEAP_PAGE_BITMAP_SIZE: 256,
    HEAP_PAGE_SIZE: 65_536, HEAP_COUNT: 12, RVARGC_MAX_ALLOCATE_SIZE: 1024, RVALUE_OLD_AGE: 3
  }.freeze

  # Nothing moves here: a compaction considers each live object by its
  # type, as CRuby's does, and moves none of them. It counts as one.
  def self.compact
    considered = ObjectSpace.count_objects.reject { |type, count| type == :TOTAL || type == :FREE || count.zero? }
    COMPACTED[1] += 1
    COMPACTED[0] = { considered: considered, moved: {}, moved_up: {}, moved_down: {} }
  end

  # The last compaction's info, and the number of compactions.
  COMPACTED = [{ considered: {}, moved: {}, moved_up: {}, moved_down: {} }, 0]
  private_constant :COMPACTED

  def self.latest_compact_info = COMPACTED[0]

  def self.verify_compaction_references(toward: nil, double_heap: false, expand_heap: false) = compact

  # Nothing moves here, but the switch keeps what it is set to.
  AUTO_COMPACT = [false]
  private_constant :AUTO_COMPACT

  def self.auto_compact = AUTO_COMPACT[0]

  def self.auto_compact=(flag)
    AUTO_COMPACT[0] = flag ? true : false
    flag
  end

  def self.verify_internal_consistency = nil

  # The nanoseconds the collector has spent, measured on the monotonic
  # clock around every mark and sweep.
  def self.total_time = Primitive.zr_gc_nanoseconds

  @measure_total_time = true

  def self.measure_total_time = @measure_total_time

  # While it is off, the collector does not time its collections.
  def self.measure_total_time=(flag)
    Primitive.attr! :ruby
    @measure_total_time = flag ? true : false
    Primitive.zr_gc_measure_set(flag)
  end

  CONFIG = { rgengc_allow_full_mark: true }
  private_constant :CONFIG

  # The one setting CRuby's default collector takes, kept as it is set.
  def self.config(hash = nil)
    Primitive.attr! :ruby
    raise ArgumentError, +"ArgumentError" unless hash.nil? || hash.is_a?(Hash)

    hash&.each_key do |key|
      raise TypeError, "wrong argument type #{key.class} (expected Symbol)" unless key.is_a?(Symbol)
      raise ArgumentError, +'Attempting to set read-only key "Implementation"' if key == :implementation
    end
    CONFIG[:rgengc_allow_full_mark] = hash[:rgengc_allow_full_mark] ? true : false if hash&.key?(:rgengc_allow_full_mark)
    { **CONFIG, implementation: +"default" }
  end

  # The four pools of 32, 64, 128 and 256-byte cells, and a fifth that
  # stays empty, so every pool index that ruby returns is valid here too.
  POOLS = 5
  private_constant :POOLS

  # One pool's numbers, or every pool's under its index, as
  # rb_gc_impl_stat_heap returns them: into the Hash given, or one of
  # them by name.
  def self.stat_heap(heap_name = nil, hash_or_key = nil)
    Primitive.attr! :ruby
    if heap_name.nil?
      raise TypeError, +"non-hash given" unless hash_or_key.nil? || hash_or_key.is_a?(Hash)

      out = hash_or_key || {}
      POOLS.times { |pool| out[pool] = pool_stats(pool, out[pool].is_a?(Hash) ? out[pool] : {}) }
      return out
    end
    raise TypeError, +"heap_name must be nil or an Integer" unless heap_name.is_a?(Integer)
    raise ArgumentError, +"size pool index out of range" unless (0...POOLS).cover?(heap_name)

    case hash_or_key
    when nil then pool_stats(heap_name, {})
    when Hash then pool_stats(heap_name, hash_or_key)
    when Symbol
      stats = pool_stats(heap_name, {})
      raise ArgumentError, "unknown key: #{hash_or_key}" unless stats.key?(hash_or_key)

      stats[hash_or_key]
    else raise TypeError, +"non-hash or symbol given"
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
      heap_eden_pages: pages, heap_eden_slots: live + free, heap_allocatable_slots: 0, total_allocated_pages: pages,
      force_major_gc_count: 0, force_incremental_marking_finish_count: 0,
      total_allocated_objects: allocated, total_freed_objects: [allocated - live, 0].max
    )
  end
  private_class_method :pool_stats

  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true, global: true)
    Primitive.attr! :ruby
    Primitive.zr_gc_start_m(full_mark, immediate_sweep)
    nil
  end
end

module Process
  def pid = Primitive.zr_process_id

  # An emulated clock (EMULATED_CLOCKS) reads its real clock to its own
  # resolution, as CRuby's fallbacks read gettimeofday, time and getrusage.
  def clock_gettime(id, unit = :float_second)
    if (emulated = Process.send(:emulated_clock, id))
      real, step = emulated
      return Process.send(:in_unit, (Primitive.zr_clock_ns(real) / step) * step, unit)
    end

    Process.send(:in_unit, Primitive.zr_clock_ns(Process.send(:clock_id, id, "clock_gettime")), unit)
  end

  def clock_getres(id, unit = :float_second)
    emulated = Process.send(:emulated_clock, id)
    ns = emulated ? emulated.last : Primitive.zr_clock_res_ns(Process.send(:clock_id, id, "clock_getres"))
    # :hertz is the ticks per second, the reciprocal of :float_second.
    return 1e9 / ns if unit == :hertz

    Process.send(:in_unit, ns, unit)
  end

  def uid = Primitive.zr_process_ids(0)
  def euid = Primitive.zr_process_ids(1)
  def gid = Primitive.zr_process_ids(2)
  def egid = Primitive.zr_process_ids(3)

  module_function :pid, :clock_gettime, :clock_getres, :uid, :euid, :gid, :egid

  # A clock is a raw id or the name of one of this module's own CLOCK_
  # constants. The symbol spelling is the portable one: a platform that
  # does not have the clock raises a rescuable Errno::EINVAL here, not a
  # NameError at the constant read. An OS whose clocks ruby identifies
  # with Symbols (WASI) maps each to its id in CLOCK_IDS.
  def self.clock_id(id, verb)
    Primitive.attr! :hidden
    return Primitive.zr_index_operand_m(id) unless id.is_a?(Symbol)
    return CLOCK_IDS.fetch(id) if CLOCK_IDS.key?(id)
    raise Errno::EINVAL, "#{verb}(#{id.inspect})" unless id.start_with?("CLOCK_") && const_defined?(id)

    clock_id(const_get(id), verb)
  end

  # The real clock and the resolution in nanoseconds of each clock that
  # CRuby emulates, or nil for any other id.
  def self.emulated_clock(id)
    Primitive.attr! :hidden
    case id
    when :GETTIMEOFDAY_BASED_CLOCK_REALTIME then [CLOCK_REALTIME, 1000]
    when :TIME_BASED_CLOCK_REALTIME then [CLOCK_REALTIME, 1_000_000_000]
    when :GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID, :CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID then [CLOCK_PROCESS_CPUTIME_ID, 1000]
    when :TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID then [CLOCK_PROCESS_CPUTIME_ID, 10_000_000]
    end
  end
  private_class_method :emulated_clock

  def self.in_unit(ns, unit)
    Primitive.attr! :hidden
    case unit
    when nil, :float_second then ns.to_f / 1e9
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

module GC::Profiler
  # The monotonic clock as the program started, which GC_INVOKE_TIME
  # counts from. It comes after Process above, whose clock it reads.
  STARTED = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  private_constant :STARTED
end
