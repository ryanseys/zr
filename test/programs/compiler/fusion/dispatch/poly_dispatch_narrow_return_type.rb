# A call `@w.run(item)` can reach more than one class. Every class
# that can receive it here returns a String, so the result is a String.
#
# Shape: M::Server#run takes an Integer and returns an Integer. The
# Worker classes take a String and return a String. `@w` only ever
# holds a Worker, so `s + "."` in `Holder#use` is a String concat.

module M
  class WorkerA
    def run(item); item + "!"; end
  end
  class WorkerB
    def run(item); item + "?"; end
  end
  class Holder
    def initialize(w); @w = w; end
    def use(item)
      s = @w.run(item)
      s + "."
    end
  end
  class Server
    def run(port); port + 1; end
  end
end

puts M::Holder.new(M::WorkerA.new).use("x")
puts M::Holder.new(M::WorkerB.new).use("y")
puts M::Server.new.run(80)
