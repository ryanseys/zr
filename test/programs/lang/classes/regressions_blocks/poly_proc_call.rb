# `.call` on a Proc stored in an ivar runs the proc body.

class T_poly_proc_call_Runner
  def initialize(pr)
    @pr = pr
  end

  def run
    @pr.call
  end
end

class T_poly_proc_call_Factory
  def wrap(&block)
    block
  end
end

f = T_poly_proc_call_Factory.new

puts "start"
T_poly_proc_call_Runner.new(f.wrap { puts "one" }).run
T_poly_proc_call_Runner.new(f.wrap { puts "two" }).run
puts "end"
