# frozen_string_literal: true

require "digest/sha2"
require_relative "function"

module Zr
  module IR
    # The digest of everything that a backend reads to assemble a function
    # (`Native::CodeCache`): the function's IR after inlining and before
    # the passes, and which of the symbols it takes the address of are
    # defined in its own unit. Two functions with one fingerprint assemble
    # to the same bytes with the same backend.
    #
    # It writes each field as text, in a fixed order. It does not use
    # Marshal: Marshal writes a link for an object it has already written,
    # so two equal functions whose Strings are shared differently would
    # have different bytes. `FIELDS` lists the fields it writes, and a unit
    # test fails when a class of the IR gets a field that is not listed, so
    # a new field cannot be left out of the key.
    module Fingerprint
      FIELDS = {
        Function => %i[@name @params @ret_type @args @slots @globals @sigs @callees @blocks @entry_block],
        Block => %i[@name @params @insts],
        Inst => %i[@op @type @args @results @cond @offset @targets @callee @flags @region]
      }.freeze

      # The instance variables of a Function that do not change its code:
      # the tables that its builder uses, and the block that gets new
      # instructions. The unit test also checks this list.
      BUILDER = %i[@current @global_of @callee_of @sig_of @block_of @next_value @next_block @entry @hoisted @iconst_of
                   @analysis].freeze

      module_function

      # `defined` answers whether a symbol is defined in the unit. One
      # interpolated String for each instruction: 20% faster than appending
      # each field (4.1 million instructions in the runtime).
      def of(function, defined)
        out = +"#{function.name}\n#{function.params.join(",")}>#{function.ret_type}\n#{function.args.join(",")}\n"
        function.slots.each { |s| out << "s#{s.bytes},#{s.align};" }
        function.globals.each { |g| out << "g#{g.gv},#{g.symbol},#{g.colocated};" }
        function.sigs.each { |s| out << "S#{s.sig},#{s.params.join(",")}>#{s.ret};" }
        function.callees.each do |c|
          out << "c#{c.fn},#{c.symbol},#{c.sig},#{c.colocated},#{c.from},#{c.effects},#{defined.include?(c.symbol)};"
        end
        out << "\n#{function.entry_block.name}\n"
        function.blocks.each do |b|
          out << "b#{b.name}(#{b.params.map { |v, t| "#{v}:#{t}" }.join(",")})\n"
          b.insts.each do |i|
            t = i.targets
            out << "#{i.op} #{i.type} #{i.args.join(",")} #{i.results.join(",")} #{i.cond} #{i.offset} #{i.callee} " \
                   "#{i.flags} #{i.region}#{t && t.map { |n, a| " >#{n}(#{a.join(",")})" }.join}\n"
          end
        end
        Digest::SHA256.hexdigest(out)
      end
    end
  end
end
