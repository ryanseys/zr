# frozen_string_literal: true

module Zr
  module Ext
    # The Makefile that mkmf writes for a C extension, read for what zr
    # needs to link the extension: its objects, its libraries, and the
    # name that `require` finds it by. It reads the `NAME = value`
    # assignments, and expands `$(NAME)`, `${NAME}` and a substitution
    # reference, `$(NAME:.c=.o)`, as make does. Rules are not read.
    class Makefile
      # @rbs @raw: Hash[String, String]

      ASSIGNMENT = /\A([A-Za-z_][A-Za-z0-9_]*)\s*[:+]?=\s?(.*)\z/
      REFERENCE = /\$(?:\(([^()]*)\)|\{([^{}]*)\})/

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
        text.gsub("\\\n", " ").each_line(chomp: true) do |line|
          next if line.start_with?("\t", "#")

          name, value = ASSIGNMENT.match(line)&.captures
          @raw[name] = value.strip if name && value
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

      # The libraries that the link takes: LOCAL_LIBS, then LIBS.
      #: () -> Array[String]
      def libraries = words("LOCAL_LIBS") + words("LIBS")

      #: (String name) -> Array[String]
      def words(name) = self[name].split

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
