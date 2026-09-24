# frozen_string_literal: true

module Zr
  class Eval
    # What an eval needs from the program it runs inside: the symbol
    # table that the program was built on, and the program's `using` entries.
    class Runtime
      def symbol_names = Primitive.zr_all_symbols.map(&:to_s)
      def sites = Primitive.zr_static_sites
      def intern(name) = Primitive.zr_intern_id(name)

      # A `using` entry is a position in one table that the whole program
      # shares. All the program's entries are taken before its first line,
      # so a snippet numbers its own entries after them and takes them
      # immediately: nothing runs in between to take them for it.
      def activations = Primitive.zr_activations_count
      def take_activations(count) = Primitive.zr_activations_reserve_m(count)

      # The SHA-256 of each source file of the compiler that this program
      # links in, by path (lib/zr/runtime.rb, `load_tables`).
      def self.sources = Primitive.zr_load_names(8).lines(chomp: true).to_h { |row| row.split("\t", 2) }

      # The library directories the program was built against, as its
      # build named them (Hir::Build.stdlib), or none where it does not
      # eval.
      def self.library_roots = Primitive.zr_load_names(0).split("\n")
    end
  end
end
