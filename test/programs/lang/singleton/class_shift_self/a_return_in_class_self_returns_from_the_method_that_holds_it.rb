def a = (class << self; return :inner; end; :outer)
p a
def b(x) = (class << self; return :early if $x > 1; end; :small)
$x = 1; r1 = b(1); $x = 5; p [r1, b(5)]
def c = ([1].each { class << self; return :from_block_sclass; end }; :outer)
p c
def d = (class << self; [2].each { return :nested_block }; end; :outer)
p d
def e
  class << self
    begin
      return :ens
    ensure
      puts "ensure ran"
    end
  end
  :outer
end
p e
def f = (class << self; class << self; return :deep; end; end; :outer)
p f
def g = (class << self; def h = :h; end; :after)
p [g, h]
pr = proc { class << self; return 1; end }
pr.call rescue p $!
def mk = proc { class << self; return 2; end }
begin; mk.call; rescue LocalJumpError => e; p [e.message, e.reason, e.exit_value]; end
