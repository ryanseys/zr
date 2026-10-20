# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

module Prism
  module Ruby
    # pm_scope_t: the locals one scope declares, what its parameters forward,
    # and whether it is closed to the scope around it.
    class Scope
      # pm_scope_parameters_t
      FORWARDING_POSITIONALS = 0x1
      FORWARDING_KEYWORDS = 0x2
      FORWARDING_BLOCK = 0x4
      FORWARDING_ALL = 0x8
      IMPLICIT_DISALLOWED = 0x10
      NUMBERED_INNER = 0x20
      NUMBERED_FOUND = 0x40

      attr_reader :previous, :locals, :implicit_parameters
      attr_accessor :parameters, :shareable_constant

      def initialize(previous, closed)
        @previous = previous
        @closed = closed
        @locals = Locals.new
        @implicit_parameters = []
        @parameters = 0
        @shareable_constant = previous ? previous.shareable_constant : 0
      end

      def closed? = @closed
    end

    # pm_locals_t: a scope's locals, a list up to eight slots and an open
    # addressed table after that. The table's layout decides the order
    # pm_locals_order warns about unused locals in, so it is kept as C
    # keeps it.
    class Locals
      # PM_LOCALS_HASH_THRESHOLD
      HASH_THRESHOLD = 5
      NOT_FOUND = 0xFFFF_FFFF

      # pm_local_t
      Local = Struct.new(:name, :start, :end, :index, :reads, :hash)

      attr_reader :size, :capacity

      def initialize
        @size = 0
        @capacity = 0
        @slots = []
      end

      # pm_locals_hash
      def self.hash_of(name)
        name = (((name >> 16) ^ name) * 0x45d9f3b) & 0xFFFF_FFFF
        name = (((name >> 16) ^ name) * 0x45d9f3b) & 0xFFFF_FFFF
        (name >> 16) ^ name
      end

      # pm_locals_write: true when the name is new to the scope.
      def write(name, start, finish, reads)
        resize if @size >= @capacity / 4 * 3

        if @capacity < HASH_THRESHOLD
          @capacity.times do |index|
            local = @slots[index]
            if local.nil?
              @slots[index] = Local.new(name, start, finish, @size, reads, 0)
              @size += 1
              return true
            elsif local.name == name
              return false
            end
          end
        else
          mask = @capacity - 1
          hash = initial = Locals.hash_of(name)
          loop do
            local = @slots[hash & mask]
            if local.nil?
              @slots[hash & mask] = Local.new(name, start, finish, @size, reads, initial)
              @size += 1
              return true
            elsif local.name == name
              return false
            end
            hash += 1
            break if (hash & mask) == initial
          end
        end
        raise "unreachable"
      end

      # pm_locals_find: the slot of the name, or NOT_FOUND.
      def find(name)
        if @capacity < HASH_THRESHOLD
          @size.times { |index| return index if @slots[index]&.name == name }
        else
          mask = @capacity - 1
          hash = Locals.hash_of(name)
          initial = hash & mask
          loop do
            local = @slots[hash & mask]
            return NOT_FOUND if local.nil?
            return hash & mask if local.name == name

            hash += 1
            break if (hash & mask) == initial
          end
        end
        NOT_FOUND
      end

      def include?(name) = find(name) != NOT_FOUND

      # pm_locals_read
      def read(name) = @slots[find(name)].reads += 1

      # pm_locals_unread
      def unread(name) = @slots[find(name)].reads -= 1

      # pm_locals_reads
      def reads(name) = @slots[find(name)].reads

      # The occupied slots in slot order, which is the order pm_locals_order
      # visits them in.
      def each_slot
        limit = @capacity < HASH_THRESHOLD ? @size : @capacity
        limit.times do |index|
          local = @slots[index]
          yield local unless local.nil?
        end
      end

      private

      # pm_locals_resize
      def resize
        next_capacity = @capacity.zero? ? 4 : @capacity * 2
        if next_capacity < HASH_THRESHOLD
          @slots = @slots.first(@size) + Array.new(next_capacity - @size)
        else
          hash_needed = @capacity <= HASH_THRESHOLD
          mask = next_capacity - 1
          grown = Array.new(next_capacity)
          @capacity.times do |index|
            local = @slots[index]
            next if local.nil?

            local.hash = Locals.hash_of(local.name) if hash_needed
            hash = local.hash
            hash += 1 until grown[hash & mask].nil?
            grown[hash & mask] = local
          end
          @slots = grown
        end
        @capacity = next_capacity
      end
    end
  end
end
