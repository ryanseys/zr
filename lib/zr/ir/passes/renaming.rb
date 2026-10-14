# frozen_string_literal: true

module Zr
  module IR
    module Passes
      # Renames uses in place through `@rename` (a value to its replacement).
      # The lookup follows the chain, because a replacement can also have a
      # replacement.
      module Renaming
        # @rbs @f: Function
        # @rbs @rename: Hash[String, untyped]

        #: () -> void
        def rename_uses
          @f.blocks.each { |b| b.insts.each { |i| rename(i) } }
        end

        #: (Inst i) -> void
        def rename(i)
          return if @rename.empty?

          i.args.map! { |a| resolve(a) }
          i.targets&.each { |(_, args)| args.map! { |a| resolve(a) } }
        end

        #: (untyped v) -> untyped
        def resolve(v)
          v = @rename[v] while @rename.key?(v)
          v
        end
      end
    end
  end
end
