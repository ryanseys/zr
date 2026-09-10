# The collector as Ruby sees it: one heap, collected on demand.
module GC
  def self.start(full_mark: true, immediate_mark: true, immediate_sweep: true) = Primitive.zr_gc_start
  def self.count = Primitive.zr_gc_count
  def self.disable = Primitive.zr_gc_set_disabled(true)
  def self.enable = Primitive.zr_gc_set_disabled(false)
  def self.stress = Primitive.zr_gc_stress
  def self.stress=(flag)
    Primitive.zr_gc_set_stress(flag)
  end

  def self.stat(key = nil)
    stats = {
      count: Primitive.zr_gc_count,
      heap_live_slots: Primitive.zr_gc_live_slots,
      total_allocated_objects: Primitive.zr_gc_allocated
    }
    return stats if key.nil?
    return stats.fetch(key) if stats.key?(key)

    raise ArgumentError, "unknown key: #{key}"
  end

  # The one collector here runs a full mark and sweep every time.
  def self.latest_gc_info(key = nil)
    info = {
      major_by: :force, need_major_by: nil, gc_by: :method, have_finalizer: false,
      immediate_sweep: true, state: :none, weak_references_count: 0, retained_weak_references_count: 0
    }
    return info if key.nil?
    return info.fetch(key) if info.key?(key)

    raise ArgumentError, "unknown key: #{key}"
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

  # Nothing moves here, so a compaction considers no object at all.
  def self.compact = { considered: {}, moved: {}, moved_up: {}, moved_down: {} }

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
    @measure_total_time = flag
  end

  def self.config(**options) = { rgengc_allow_full_mark: true, implementation: "default" }

  # One pool of one cell size holds every object.
  def self.stat_heap(pool = nil, out = {})
    stats = {
      slot_size: 128,
      heap_live_slots: Primitive.zr_gc_live_slots,
      heap_free_slots: 0,
      total_allocated_objects: Primitive.zr_gc_allocated
    }
    return out.merge!(0 => stats) if pool.nil?
    raise RangeError, "pool index out of range" unless pool == 0

    out.merge!(stats)
  end

  def start(full_mark: true, immediate_mark: true, immediate_sweep: true) = Primitive.zr_gc_start
  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true) = Primitive.zr_gc_start
end

module Process
  CLOCK_REALTIME = 0
  CLOCK_MONOTONIC = 6
  CLOCK_PROCESS_CPUTIME_ID = 12
  CLOCK_THREAD_CPUTIME_ID = 16

  def pid = Primitive.zr_process_id

  def clock_gettime(id, unit = :float_second)
    Process.send(:in_unit, Primitive.zr_clock_ns(id), unit)
  end

  def clock_getres(id, unit = :float_second)
    Process.send(:in_unit, Primitive.zr_clock_res_ns(id), unit)
  end

  def uid = Primitive.zr_process_ids(0)
  def euid = Primitive.zr_process_ids(1)
  def gid = Primitive.zr_process_ids(2)
  def egid = Primitive.zr_process_ids(3)

  module_function :pid, :clock_gettime, :clock_getres, :uid, :euid, :gid, :egid

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
