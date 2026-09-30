# Push a Proc into an ivar Array (set to `[]` first). Then
# `.each { |b| b.call }` runs each proc.
class T_proc_array_push_Runner
  def initialize
    @procs = []
  end

  def add(&block)
    @procs.push(block)
  end

  def call_all
    @procs.each do |p|
      p.call
    end
  end
end

r = T_proc_array_push_Runner.new
r.add { puts "first" }
r.add { puts "second" }
puts "before"
r.call_all
puts "after"
