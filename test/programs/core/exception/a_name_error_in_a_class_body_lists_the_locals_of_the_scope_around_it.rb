# NameError#local_variables lists the locals that ruby's
# rb_iseq_local_variables finds: those of the scope that raised, and out
# of a block, an eval, or a class, module or singleton class body, those
# of the scope around it, all of its names, also ones written later. A
# method body stops the walk. did_you_mean suggests from this list.
# rubocop:disable Lint/UselessAssignment, Lint/UnusedMethodArgument, Lint/UnusedBlockArgument
top = 1
def m(a) = (zz rescue $!.local_variables)
p m(1)
class D
  inner = 2
  def self.k(b) = (zz rescue $!.local_variables)
  p k(1)
  p((zz rescue $!.local_variables))
  module E
    deep = 3
    p((zz rescue $!.local_variables))
    [1].each { |blk| p((zz rescue $!.local_variables)) }
  end
  class << self
    single = 4
    p((zz rescue $!.local_variables))
  end
  Class.new { anon = 5; p((zz rescue $!.local_variables)) }
end
p proc { |q| (zz rescue $!.local_variables) }.call(1)
p((zz rescue $!.local_variables))
p eval("(zz rescue $!.local_variables)")

class F
  begin
    lat
  rescue NameError => e
    puts e.detailed_message(highlight: false)
  end
end
later = top
p later
# rubocop:enable Lint/UselessAssignment, Lint/UnusedMethodArgument, Lint/UnusedBlockArgument
