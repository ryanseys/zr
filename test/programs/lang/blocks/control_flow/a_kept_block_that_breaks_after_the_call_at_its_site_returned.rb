# The call at the block's site has returned, so a later call of the
# kept block, or a later call that gets it with `&`, has no call to
# leave. The method that wrote the block still runs.
def capture(&b) = b
def yielding = yield
def call_it(b) = b.call

def later(how)
  b = capture { break :gone }
  case how
  when :call then b.call
  when :method then call_it(b)
  when :yield then yielding(&b)
  when :exec then Object.new.instance_exec(&b)
  end
rescue LocalJumpError => e
  "#{how}: #{e.message}"
end
%i[call method yield exec].each { |how| puts later(how) }
