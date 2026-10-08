# frozen_string_literal: true

require "shellwords"

module Zr
  module Ext
    # The Makefile that mkmf writes for a C extension, read for what zr
    # needs to link the extension: its objects, its libraries, and the
    # name that `require` finds it by. It reads the `NAME = value`
    # assignments, and expands `$(NAME)`, `${NAME}` and a substitution
    # reference, `$(NAME:.c=.o)`, as make does. Of the rules it reads
    # only the targets: they tell mkmf's template from a Makefile that
    # needs make (`standard?`).
    class Makefile
      # @rbs @raw: Hash[String, String]
      # @rbs @rules: Array[String]

      ASSIGNMENT = /\A([A-Za-z_][A-Za-z0-9_]*)\s*[:+]?=\s?(.*)\z/
      REFERENCE = /\$(?:\(([^()]*)\)|\{([^{}]*)\})/
      # A rule's targets, before its one or two colons.
      RULE = /\A([^:=]+?)\s*::?(?!=)/
      # The rules that mkmf's template writes, by target.
      TEMPLATE = %w[
        all install static install-so install-rb install-rb-default pre-install-rb pre-install-rb-default
        do-install-rb do-install-rb-default site-install site-install-so site-install-rb
        clean clean-so clean-static clean-rb clean-rb-default realclean
        distclean distclean-so distclean-static distclean-rb distclean-rb-default
        .SUFFIXES .PHONY .c.o .c.S .cc.o .cc.S .mm.o .mm.S .cxx.o .cxx.S .cpp.o .cpp.S .m.o .m.S
        $(TARGET_SO) $(TARGET_SO_DIR_TIMESTAMP) $(OBJS) $(STATIC_LIB)
        build_complete $(build_complete) clean-build_complete gemspec $(gemspec) clean-gemspec
      ].to_set.freeze #: Set[String]

      # The Makefile at `path`.
      #: (String path) -> Makefile
      def self.read(path) = new(File.read(path), dir: File.dirname(path))

      attr_reader :dir #: String

      # `text` is the Makefile; `dir` is its directory, where the objects
      # are.
      #: (String text, dir: String) -> void
      def initialize(text, dir:)
        @dir = dir
        @raw = {}
        @rules = []
        text.gsub("\\\n", " ").each_line(chomp: true) do |line|
          next if line.start_with?("\t", "#") || line.strip.empty?

          name, value = ASSIGNMENT.match(line)&.captures
          if name && value
            @raw[name] = value.strip
          elsif (targets = RULE.match(line)&.[](1))
            @rules.concat(targets.split)
          end
        end
      end

      # The value of the variable `name`, expanded; "" when it is not set.
      #: (String name) -> String
      def [](name) = expand(@raw.fetch(name, ""), [name])

      #: (String name) -> bool
      def key?(name) = @raw.key?(name)

      # The extension's name: `msgpack`.
      #: () -> String
      def target = self["TARGET"]

      # What `require` names the extension by: `msgpack/msgpack`, its
      # `target_prefix` (the directory under lib/) and its target.
      #: () -> String
      def feature = File.join(self["target_prefix"].delete_prefix("/"), target).delete_prefix("/")

      # The function that ruby runs to load it: `Init_msgpack`.
      #: () -> String
      def init = "Init_#{key?("TARGET_NAME") ? self["TARGET_NAME"] : target}"

      # The object files, as paths in the Makefile's directory.
      #: () -> Array[String]
      def objects = words("OBJS").map { |name| File.expand_path(name, dir) }

      # The words that the link takes for libraries, as mkmf's link rule
      # gives them: LIBPATH, then LOCAL_LIBS, then LIBS. A directory or an
      # archive in the Makefile's directory is made absolute, so the link
      # can run elsewhere.
      #: () -> Array[String]
      def libraries
        (words("LIBPATH") + words("LOCAL_LIBS") + words("LIBS")).map do |word|
          if word.start_with?("-L") && !word.start_with?("-L/") then "-L#{File.expand_path(word.delete_prefix("-L"), dir)}"
          elsif word.end_with?(".a") && !word.start_with?("/", "-") then File.expand_path(word, dir)
          else word
          end
        end
      end

      # The words of the variable `name` as a rule gives them to the shell,
      # which takes their quotes: `-DNAME=\"x\"` is the word `-DNAME="x"`.
      #: (String name) -> Array[String]
      def words(name) = Shellwords.split(self[name])

      # Each source file with the object that it compiles to, in the
      # order of SRCS: `[srcdir/a.c, dir/a.o]`.
      #: () -> Array[[String, String]]
      def sources
        srcdir = File.expand_path(self["srcdir"], dir)
        words("SRCS").map { |name| [File.expand_path(name, srcdir), File.expand_path(name.sub(/\.[^.\/]+\z/, ".o"), dir)] }
      end

      # Whether the Makefile is mkmf's template alone: each rule is one
      # that mkmf writes, or names an object's headers (a `depend` file).
      # An extconf that adds rules of its own (a vendored library to
      # build first) needs make.
      #: () -> bool
      def standard?
        objects = self.objects.map { |path| File.basename(path) }
        @rules.all? { |target| TEMPLATE.include?(target) || objects.include?(File.basename(target)) }
      end

      private

      # `value` with each reference replaced by its value. `seen` holds the
      # variables that the expansion is inside, so a loop expands to "".
      #: (String value, Array[String] seen) -> String
      def expand(value, seen)
        value.gsub(REFERENCE) do
          inner = Regexp.last_match(1) || Regexp.last_match(2) || ""
          name, substitution = inner.split(":", 2)
          name = name.to_s
          next "" if seen.include?(name)

          text = expand(@raw.fetch(name, ""), seen + [name])
          substitution ? substitute(text, substitution) : text
        end
      end

      # A substitution reference: each word that ends in `from` ends in
      # `to` instead (`.c=.o`).
      #: (String text, String substitution) -> String
      def substitute(text, substitution)
        from, to = substitution.split("=", 2)
        return text unless from && to

        text.split.map { |word| word.end_with?(from) ? word.delete_suffix(from) + to : word }.join(" ")
      end
    end
  end
end
