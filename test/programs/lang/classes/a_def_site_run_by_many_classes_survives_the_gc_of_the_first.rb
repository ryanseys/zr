# One def site that many classes run (a class body in a loop): the first
# class can be collected while the later ones still run the def. Their
# frames, backtrace labels and `super` must not read the freed class.
module Base
  def x = [:base]
end

labels = []
results = []
6.times do |i|
  c = Class.new do
    include Base
    def x = [:c, *super]
    def boom = raise("e")
  end
  GC.start
  # Fill the freed cells with other objects.
  Array.new(3000) { [i] * 3 }
  results << c.new.x
  begin
    c.new.boom
  rescue => e
    labels << e.backtrace_locations[0].label
  end
end
p results
p labels

# The same with a refinement made in each pass.
module M; def m = [:M]; end
class C; include M; end
3.times do |i|
  r = Module.new { refine(M) { def m = [:R, *super] } }
  GC.start
  Array.new(3000) { [i] * 3 }
  p Module.new.module_eval { using r; C.new.m } rescue p $!.class
end

# A singleton method def that each pass runs on a new object: the first
# object goes, and the later frames still show the method.
labels = []
4.times do
  o = Object.new
  def o.boom = raise("e")
  GC.start
  Array.new(3000) { [1] * 3 }
  begin
    o.boom
  rescue => e
    labels << e.backtrace_locations[0].label
  end
end
p labels
