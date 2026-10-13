# psych 5.5.0: Psych::BACKEND names libyaml, a handler cannot make its own
# parser parse again while it runs, and an error in event_location ends the
# parse.
require "psych"
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message.gsub(/0x\h+/, "0x")]
end
t(:psych_backend) { [Psych::BACKEND, Psych::BACKEND.encoding, Psych::BACKEND.frozen?] }
class H < Psych::Handler; attr_accessor :pa; def scalar(*) = (pa.parse("b") if pa); end
h = H.new; pa = Psych::Parser.new(h); h.pa = pa
t(:reentrant) { pa.parse("a") }
h.pa = nil
t(:after) { pa.parse("x").class }
class L < Psych::Handler; def event_location(*) = raise("boom"); end
t(:event_location) { Psych::Parser.new(L.new).parse("a: 1"); :swallowed }
