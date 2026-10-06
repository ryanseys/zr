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

Widget.parent_name = "Assembly"

# A bare heap value: `value_ivars`' identity-keyed side table.
class Array
  def label=(v)
    @label = v
  end

  def label
    @label
  end
end

xs = [1, 2, 3]
ys = [1, 2, 3]
xs.label = "counted"
# Identity, not equality -- `ys == xs` yet carries nothing.

class String
  def note=(v)
    @note = v
  end

  def note
    @note
  end
end

s = +"hi"
s.note = 9

# Reaching the same storage through a method defined on the reopened builtin
# rather than at the call site, so the read and the write cross a call boundary.
class Array
  def bump
    @label = "#{@label}!"
    self
  end
end

# Reaching the same storage through a method defined on the reopened builtin
# rather than at the call site, so the read and the write cross a call boundary.
class Array
  def bump
    @label = "#{@label}!"
    self
  end
end

p xs.bump.label
