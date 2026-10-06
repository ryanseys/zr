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


# Reflection reaches the same storage.
sc.instance_variable_set(:@tag, :second)

# A CLASS object: `civars`, keyed `(class_id, name)`.
class Class
  def parent_name=(v)
    @parent_name = v
  end

  def parent_name
    @parent_name
  end
end

class Widget; end
class Gadget; end

# A CLASS object: `civars`, keyed `(class_id, name)`.
class Class
  def parent_name=(v)
    @parent_name = v
  end

  def parent_name
    @parent_name
  end
end

class Widget; end
class Gadget; end

Widget.parent_name = "Assembly"
p Widget.parent_name
p Gadget.parent_name

