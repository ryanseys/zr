# frozen_string_literal: true

module Zr
  module Machine
    # The words of a scope's FrameMeta that come from the scope itself,
    # which a binary's lowering (`Lower#meta`) and the host walker
    # (`Machine::Host::Walk::Frames#meta`) both write. `cover` is the
    # def-site entry that the scope uses when it makes a method, `using`
    # its `using` entry, and `span` where its code starts and ends
    # (#source_range and #syntax_tree read it).
    # @rbs skip -- typed in sig/zr/machine/frame_words.rbs
    FrameWords = Data.define(:line, :end_line, :node, :arity, :env, :ruby, :cover, :owns_backref, :reads_backref, :frameless,
                             :blocks, :using, :span)

    class FrameWords
      # The fields that `each_word` writes.
      FIELDS = %w[line end_line node arity env ruby cover owns_backref reads_backref frameless blocks using span_line column
                  end_column].freeze

      # @rbs line: Integer
      # @rbs end_line: Integer
      # @rbs node: Integer
      # @rbs arity: Integer
      # @rbs env: bool
      # @rbs ruby: bool
      # @rbs cover: Integer?
      # @rbs owns_backref: bool
      # @rbs reads_backref: bool
      # @rbs frameless: bool | Integer
      # @rbs blocks: Integer
      # @rbs using: Integer?
      # @rbs span: Array[Integer]?
      # @rbs return: void
      def initialize(line:, end_line: 0, node: 0, arity: 0, env: false, ruby: false, cover: nil, owns_backref: false, reads_backref: false,
                     frameless: false, blocks: 0, using: nil, span: nil)
        super
      end

      # Each FrameMeta field with its word. A `cover` or `using` entry is
      # one more than its index, so 0 means none.
      #: () { (String field, Integer word) -> void } -> void
      def each_word
        yield "line", line
        yield "end_line", end_line
        yield "node", node
        yield "arity", arity
        yield "env", env ? 1 : 0
        yield "ruby", ruby ? 1 : 0
        yield "cover", cover ? cover + 1 : 0
        yield "owns_backref", owns_backref ? 1 : 0
        yield "reads_backref", reads_backref ? 1 : 0
        # A Lower::Function#frameless_word, or a bool.
        word = case frameless
               when Integer then frameless
               when true then 1
               else 0
               end
        yield "frameless", word
        yield "blocks", blocks
        yield "using", using ? using + 1 : 0
        return unless span

        yield "span_line", span[0]
        yield "column", span[1]
        yield "end_column", span[3]
      end
    end
  end
end
