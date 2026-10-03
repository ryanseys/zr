# frozen_string_literal: true

module Zr
  class Eval
    # What an eval needs from the program it runs inside: the symbol
    # table that the program was built on, and the program's `using` entries.
    class Runtime
      # A name for each id, nil for a pad (`Machine::Symbols`).
      #: () -> Array[String?]
      def symbol_names = Primitive.zr_symbol_table.map { |sym| sym&.to_s }
      #: () -> Integer
      def sites = Primitive.zr_static_sites
      #: (String name) -> Integer
      def intern(name) = Primitive.zr_intern_id(name)

      # A `using` entry is a position in one table that the whole program
      # shares. All the program's entries are taken before its first line,
      # so a snippet numbers its own entries after them and takes them
      # immediately: nothing runs in between to take them for it.
      #: () -> Integer
      def activations = Primitive.zr_activations_count

      # An eval compiles its string with TracePoint's events armed when one
      # is enabled, as ruby's instructions fire them.
      #: () -> bool
      def tracing? = Primitive.zr_trace_armed_m
      #: (Integer? count) -> void
      def take_activations(count) = Primitive.zr_activations_reserve_m(count)

      # The SHA-256 of each source file of the compiler that this program
      # links in, by path (lib/zr/load_tables.rb).
      #: () -> Hash[String, String]
      def self.sources = Primitive.zr_load_names(8).lines(chomp: true).to_h { |row| row.split("\t", 2) }

      # The library directories the program was built against, as its
      # build named them (Library::Roots.stdlib), or none where it does not
      # eval.
      #: () -> Array[String]
      def self.library_roots = Primitive.zr_load_names(0).split("\n")

      # The separators that the core library reads from globals, which a
      # program can set: while the compiler runs they are ruby's defaults,
      # and the program's come back after, with no hook and no warning.
      SEPARATORS = %i[$, $; $/ $\\].freeze

      #: [T] () { () -> T } -> T
      def self.plain_separators
        kept = SEPARATORS.map { |name| Primitive.zr_gvar_get_m(name) }
        SEPARATORS.each { |name| Primitive.zr_gvar_set_m(name, name == :$/ ? String.send(:default_rs) : nil) }
        yield
      ensure
        SEPARATORS.zip(kept) { |name, value| Primitive.zr_gvar_set_m(name, value) } if kept
      end

      # The compiler's Enumerable methods walk the core's collections with
      # the core's own `each` (zr_eval_compiling_m) while it runs.
      #: [T] () { () -> T } -> T
      def self.compiling
        was = Primitive.zr_eval_compiling_m(true)
        yield
      ensure
        Primitive.zr_eval_compiling_m(was)
      end
    end
  end
end
