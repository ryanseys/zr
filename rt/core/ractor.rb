# frozen_string_literal: true

# Ractor, so far only the part a shareable constant and a deep freeze
# need. A ractor of its own stops by name.
class Ractor
  class Error < RuntimeError; end
  class IsolationError < Error; end
  class ClosedError < StopIteration; end
  class MovedError < Error; end
  class RemoteError < Error; end
  class UnsafeError < Error; end
  class MovedObject < BasicObject; end

  # The classes that hold a task or a lock, which no ractor can share.
  UNSHAREABLE = [Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable].freeze
  private_constant :UNSHAREABLE

  def self.new(*, **, &)
    Primitive.zr_unimplemented("Ractor.new")
  end

  def self.current
    Primitive.zr_unimplemented("Ractor.current")
  end

  # Whether every object reachable from `obj` is frozen. A number, a
  # symbol, a class and the three singletons are shareable as they are.
  def self.shareable?(obj)
    return true if immutable?(obj)

    obj.frozen? && reachable(obj).all? { |ref| shareable?(ref) }
  end

  # Freeze `obj` and everything it reaches, and answer it. `copy: true`
  # freezes a deep copy and leaves `obj` alone.
  def self.make_shareable(obj, copy: false)
    return make_shareable(Marshal.load(Marshal.dump(obj))) if copy

    deep_freeze(obj, {})
    obj
  end

  # The value a shareable constant takes, when the compiler cannot see
  # that the value is a literal. Ruby demands a value that is already
  # shareable there.
  def self.ensure_shareable(value, name)
    Primitive.attr! :hidden
    raise IsolationError, "cannot assign unshareable object to #{name}" unless shareable?(value)

    value
  end

  def self.immutable?(obj)
    Primitive.attr! :hidden
    case obj
    when Integer, Float, Symbol, Module, NilClass, TrueClass, FalseClass then true
    else false
    end
  end

  def self.deep_freeze(obj, seen)
    Primitive.attr! :hidden
    return if immutable?(obj) || seen.key?(obj.object_id)

    raise Error, "can not make shareable object for #{obj.inspect}" if UNSHAREABLE.any? { |k| obj.is_a?(k) }

    seen[obj.object_id] = true
    obj.freeze
    reachable(obj).each { |ref| deep_freeze(ref, seen) }
  end

  # What one object refers to: its parts, then its instance variables.
  def self.reachable(obj)
    Primitive.attr! :hidden
    parts =
      case obj
      when Array then obj
      when Hash then obj.flat_map { |key, value| [key, value] } << obj.default
      when Range then [obj.begin, obj.end]
      when Struct then obj.to_a
      else []
      end
    parts + obj.instance_variables.map { |name| obj.instance_variable_get(name) }
  end
end
