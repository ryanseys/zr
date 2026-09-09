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

  def start(full_mark: true, immediate_mark: true, immediate_sweep: true) = Primitive.zr_gc_start
  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true) = Primitive.zr_gc_start
end

module Process
  def self.pid = Primitive.zr_process_id
  def self.clock_gettime(id, unit = :float_second) = Primitive.zr_unimplemented("Process.clock_gettime")
end
