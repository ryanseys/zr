# frozen_string_literal: true

module Ze0
  class Eval
    # What an eval needs from the program it runs inside: the symbol
    # table that program was built on.
    class Runtime
      def symbol_names = Primitive.zr_all_symbols.map(&:to_s)
      def sites = Primitive.zr_static_sites
      def intern(name) = Primitive.zr_intern_id(name)
    end
  end
end
