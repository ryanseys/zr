# The classes live in a module, and the program creates them with
# `M::Holder.new(...)` and `M::WorkerA.new`. `@w` only ever holds a
# Worker, never an M::Server.

module M
  class WorkerA
    def run(item); item + "!"; end
  end
  class WorkerB
    def run(item); item + "?"; end
  end
  class Holder
    def initialize(w); @w = w; end
    def use(item); @w.run(item); end
  end
  # The same method name (`run`) with a different param type
  # (Integer, not String). M::Server#run still adds to an Integer.
  class Server
    def run(port); port + 1; end
  end
end

puts M::Holder.new(M::WorkerA.new).use("x")
puts M::Holder.new(M::WorkerB.new).use("y")
puts M::Server.new.run(80)
