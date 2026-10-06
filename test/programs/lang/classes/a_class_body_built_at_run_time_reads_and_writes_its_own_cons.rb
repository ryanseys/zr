# `class Adapter < parent` with a LOCAL superclass has no compile-time class to
# lay out, so zr builds it with `Class.new(parent) { ... }`. A block is not a
# class body in two ways ruby cares about, and zr gives class-body behavior for both:
#
#   * a block SHARES the enclosing local scope, where a class body has its own;
#   * a block opens no cref, so `@@v` in one raises "class variable access from
#     toplevel".
#
# sidekiq's ActiveJob adapter is built exactly this way and hits both at once.

class AbstractAdapter
  def kind = :abstract
end

parent = AbstractAdapter
callback = :OUTER_UNTOUCHED

class Adapter < parent
  @@stopping = false

  # A body local, read from two nested blocks. Sharing the enclosing scope
  # would have clobbered the `callback` above.
  callback = -> { @@stopping = true }

  [1].each { |_| [2].each { |_| callback.call } }

  def self.stopping? = @@stopping

  def self.stop! = @@stopping = true
end

p Adapter.stopping?
p callback
p [Adapter.new.kind, Adapter.superclass]

