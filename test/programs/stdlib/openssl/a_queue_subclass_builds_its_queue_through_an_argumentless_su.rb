# A user class inheriting a native type has no struct of its own: its instances
# wrap the real native value as a payload and carry their own ivars beside it.
# `Queue` has a real empty form, so `super()` builds one; nothing in the IO
# family does -- no descriptor, peer or algorithm can be conjured -- so those
# subclasses seat the real payload through `super`, which is the whole reason
# gems subclass them.
#
# actionpool's `Queue < ::Queue`, kgio's `Kgio::Pipe < IO`, dalli's
# `TCP < TCPSocket`, and the `SSLSocket < OpenSSL::SSL::SSLSocket` that bunny,
# dalli and mongo each write -- the largest single subclassing bucket in the
# gem corpus.

require "socket"
require "openssl"
require "tmpdir"

# A real empty form: `super()` builds the queue, and the subclass adds an ivar
# on top of the inherited behaviour.
class Jobs < ::Queue
  def initialize(name)
    super()
    @name = name
  end

  attr_reader :name

  def push_all(*xs) = xs.each { |x| push(x) }
end

q = Jobs.new("work")
q.push_all(1, 2, 3)
p q.name
p q.size
p q.pop
p q.class
p q.is_a?(Queue)
p Jobs.superclass
p Jobs.ancestors.take(3)

