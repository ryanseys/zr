# `@worker.run(item)` calls `run` on the Worker or Other object in the
# ivar. An unrelated class also defines `run`, but no code makes one
# or puts one in the ivar. So the call returns a String, and
# File.write writes it.

class T_poly_recv_ivar_narrow_drops_unrelated_Worker
  def run(item)
    item + ""
  end
end

class T_poly_recv_ivar_narrow_drops_unrelated_Other < T_poly_recv_ivar_narrow_drops_unrelated_Worker
  def run(item)
    item + "!"
  end
end

# T_poly_recv_ivar_narrow_drops_unrelated_Unrelated has no relation to
# T_poly_recv_ivar_narrow_drops_unrelated_Worker.
# Never instantiated, never assigned to a T_poly_recv_ivar_narrow_drops_unrelated_Pool@worker slot.
# Its `run` has zero formal args and returns an Integer.
class T_poly_recv_ivar_narrow_drops_unrelated_Unrelated
  def run
    1
  end
end

class T_poly_recv_ivar_narrow_drops_unrelated_Pool
  attr_accessor :worker
  def initialize(w); @worker = w; end
  def go(item, path)
    File.write(path, @worker.run(item))
    0
  end
end

T_poly_recv_ivar_narrow_drops_unrelated_Pool.new(T_poly_recv_ivar_narrow_drops_unrelated_Worker.new).go("a", "spinel_poly_recv_ivar_narrow_a.txt")
T_poly_recv_ivar_narrow_drops_unrelated_Pool.new(T_poly_recv_ivar_narrow_drops_unrelated_Other.new).go("b", "spinel_poly_recv_ivar_narrow_b.txt")
puts File.read("spinel_poly_recv_ivar_narrow_a.txt")
puts File.read("spinel_poly_recv_ivar_narrow_b.txt")
File.delete("spinel_poly_recv_ivar_narrow_a.txt")
File.delete("spinel_poly_recv_ivar_narrow_b.txt")
