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
