# `@w.run(item)` calls `run` on the object in `@w`, a WorkerA or a
# WorkerB. An unrelated class (Server) also defines `run`, with an
# Integer param. The String call does not affect Server#run, so
# `port + 1` gives an Integer.

class T_poly_recv_dispatch_narrow_WorkerA
  def run(item)
    item + "!"
  end
end

class T_poly_recv_dispatch_narrow_WorkerB
  def run(item)
    item + "?"
  end
end

class T_poly_recv_dispatch_narrow_Holder
  def initialize(w)
    @w = w
  end
  def use(item)
    @w.run(item)
  end
end

class T_poly_recv_dispatch_narrow_Server
  def run(port)
    port + 1
  end
end

# T_poly_recv_dispatch_narrow_Server#run gets only the Integer 80.
puts T_poly_recv_dispatch_narrow_Holder.new(T_poly_recv_dispatch_narrow_WorkerA.new).use("x")
puts T_poly_recv_dispatch_narrow_Holder.new(T_poly_recv_dispatch_narrow_WorkerB.new).use("y")
puts T_poly_recv_dispatch_narrow_Server.new.run(80)
