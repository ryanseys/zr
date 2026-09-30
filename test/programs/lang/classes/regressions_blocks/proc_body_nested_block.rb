class T_proc_body_nested_block_Defer
  def initialize
    @blocks = []
  end

  def add(&blk)
    @blocks.push(blk)
  end

  def call_all
    @blocks.each do |b|
      b.call
    end
  end
end

class T_proc_body_nested_block_Runner
  def self.with_deferred(&outer)
    d = T_proc_body_nested_block_Defer.new
    outer.call(d)
    d.call_all
  end
end

T_proc_body_nested_block_Runner.with_deferred do |d|
  d.add { puts "first" }
  d.add { puts "second" }
  puts "mid"
end
