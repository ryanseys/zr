# An `@ivar` in a method of a reopened builtin.
#
# The ivar belongs to the receiver object, as in CRuby.
#
# The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
# StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
# on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
# TCPSocket.

require "strscan"

# A builtin whose instances keep ivars as a plain object does.
class StringScanner
  def tag=(v)
    @tag = v
  end

  def tag
    @tag
  end
end

sc = StringScanner.new("hello world")
sc.tag = :first
# The native behaviour is untouched.

p StringScanner.new("x").tag

