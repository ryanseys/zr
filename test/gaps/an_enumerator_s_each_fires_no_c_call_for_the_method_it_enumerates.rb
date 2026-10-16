# CRuby's Enumerator#each calls the method it enumerates by name
# (rb_block_call), and TracePoint hears that call. zr's Enumerator sends
# the method from Ruby, with the arguments, keywords and block it keeps,
# and no event fires for it.
def trace(label)
  events = []
  tp = TracePoint.new(:c_call) { |t| events << "#{t.defined_class}##{t.method_id}" }
  tp.enable { yield }
  puts "#{label}: #{events.join(" ")}"
end
trace(:each_slice_enum) { [1, 2].each_slice(1).to_a }
trace(:enum_next) { [1, 2].each_slice(1).next }
