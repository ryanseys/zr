# frozen_string_literal: true

module Zr
  module Obj
    # The string table of an object file: every name, each ended by a NUL,
    # after one leading NUL. A name's entry is its offset in the table. ELF
    # gives an empty name the offset 0, the leading NUL (`blank: 0`).
    class StringTable
      # @rbs @blank: Integer?

      attr_reader :bytes #: String

      #: (?blank: Integer?) -> void
      def initialize(blank: nil)
        @bytes = +"\0".b
        @blank = blank
      end

      # Appends `name`, and returns its offset.
      #: (String name) -> Integer
      def add(name)
        blank = @blank
        return blank if blank && name.empty?

        at = @bytes.bytesize
        @bytes << name.b << "\0".b
        at
      end
    end
  end
end
