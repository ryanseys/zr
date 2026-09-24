# frozen_string_literal: true

module Zr
  # A class of named fields, used in place of a Struct. Each subclass
  # writes out its fields (`FIELDS`, the accessors, `initialize` and
  # `to_a`), so creating and reading one are plain method calls and ivar
  # reads. A Struct uses the core library's generic code, which a compiled
  # compiler runs as Ruby. This class gives the other Struct behavior from
  # `FIELDS` and `to_a`: equality by value, fields in order, and the walk
  # over a node's children that the builder's passes use.
  class Record
    def self.members = self::FIELDS

    def members = self.class::FIELDS
    def values = to_a
    def deconstruct = to_a
    def to_h = members.zip(to_a).to_h
    def size = members.size
    alias length size

    def deconstruct_keys(keys)
      pairs = to_h
      keys ? pairs.slice(*keys) : pairs
    end

    def each(&)
      return enum_for(:each) unless block_given?

      to_a.each(&)
      self
    end

    def each_pair
      return enum_for(:each_pair) unless block_given?

      members.zip(to_a).each { |name, value| yield name, value }
      self
    end

    def [](key) = key.is_a?(Integer) ? to_a.fetch(key) : public_send(member(key))
    def []=(key, value)
      public_send(:"#{key.is_a?(Integer) ? members.fetch(key) : member(key)}=", value)
    end

    def ==(other) = other.class == self.class && other.to_a == to_a
    def eql?(other) = other.class == self.class && other.to_a.eql?(to_a)
    def hash = [self.class, *to_a].hash

    def inspect = "#<#{self.class.name} #{members.zip(to_a).map { |name, value| "#{name}=#{value.inspect}" }.join(', ')}>"
    alias to_s inspect

    private

    def member(key)
      name = key.to_sym
      raise NameError, "no member '#{key}' in #{self.class.name}" unless members.include?(name)

      name
    end
  end
end
