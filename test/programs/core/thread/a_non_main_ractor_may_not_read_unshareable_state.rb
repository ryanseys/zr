$VERBOSE = nil
NONSH = ["a"]
$g = 1
class CV
  @@v = 1
  def self.v = @@v
end
def t(name, r)
  p [name, r.value]
rescue Ractor::RemoteError => e
  p [name, e.cause.class, e.cause.message]
end
t(:const, Ractor.new { NONSH })
t(:global, Ractor.new { $g })
t(:cvar, Ractor.new { CV.v })
t(:const_set, Ractor.new { Object.const_set(:NEWC, [1]) })
def u(name)
  p [name, yield]
rescue => e
  p [name, e.class, e.message.sub(/0x\h+/, "X")]
end
u(:name_type) { Ractor.new(name: 3) {} }
u(:proc_self) { x = 1; Ractor.make_shareable(proc { x }) }
u(:range) { Ractor.shareable?("a".."b") }
