# frozen_string_literal: true

module Zr
  module CLI
    # `--dump=parsetree`: a prism tree as ruby prints it, in the format of
    # prism's C pretty printer (templates/src/prettyprint.c.erb). Each node
    # is a line with its name and location, then one line for each of its
    # fields, in the order of prism's config: the flags first. Children go
    # below their field with one more level of prefix.
    module ParseTree
      # A field's prefix: "|   " while more fields follow, else blanks.
      MORE = "|   "
      LAST = "    "

      # pm_buffer_append_source with PM_BUFFER_ESCAPING_RUBY: the escapes
      # of the control bytes that have one.
      ESCAPES = { "\a" => "\\a", "\b" => "\\b", "\t" => "\\t", "\n" => "\\n", "\v" => "\\v", "\f" => "\\f",
                  "\r" => "\\r", '"' => "\\\"", "\\" => "\\\\" }.freeze

      # The text of the tree of `node`.
      #: (Prism::Node node) -> String
      def self.text(node) = node(+"".b, node, "")

      #: (String out, Prism::Node node, String prefix) -> String
      def self.node(out, node, prefix)
        out << "@ #{node.class.name.to_s.delete_prefix("Prism::")} (location: #{location(node.location)})\n"
        fields = Prism::Reflection.fields_for(node.class)
        fields.each_with_index do |field, index|
          inner = prefix + (index == fields.size - 1 ? LAST : MORE)
          out << prefix << "+-- " << field_name(node, field) << ":"
          value(out, node, field, inner)
        end
        out
      end

      # One field's value, after its name, through to the end of its line,
      # with a child node below it.
      #: (String out, Prism::Node node, Prism::Reflection::Field field, String inner) -> void
      def self.value(out, node, field, inner)
        # The flags have no reader of their own; each field has one.
        value = field.is_a?(Prism::Reflection::FlagsField) ? nil : node.public_send(field.name) #: untyped
        case field
        when Prism::Reflection::NodeField, Prism::Reflection::OptionalNodeField
          return out << " nil\n" if value.nil?

          out << "\n" << inner
          node(out, value, inner)
        when Prism::Reflection::NodeListField
          out << " (length: #{value.size})\n"
          value.each_with_index do |child, index|
            out << inner << "+-- "
            node(out, child, inner + (index == value.size - 1 ? LAST : MORE))
          end
        when Prism::Reflection::StringField then out << " \"" << escaped(value) << "\"\n"
        when Prism::Reflection::ConstantField, Prism::Reflection::OptionalConstantField
          out << (value.nil? ? " nil" : " :#{value.name.b}") << "\n"
        when Prism::Reflection::ConstantListField then out << " [" << value.map { |name| ":#{name.name.b}" }.join(", ") << "]\n"
        when Prism::Reflection::LocationField, Prism::Reflection::OptionalLocationField
          out << (value.nil? ? " nil" : " #{location(value)} = \"#{escaped(value.slice)}\"") << "\n"
        when Prism::Reflection::IntegerField then out << " #{value}\n"
        when Prism::Reflection::FloatField then out << " #{double(value)}\n"
        when Prism::Reflection::FlagsField then out << flags(node, field) << "\n"
        end
      end

      # A field's name; the flags are named by their type, as in prism's
      # config: `CallNodeFlags`, `IntegerBaseFlags`.
      #: (Prism::Node node, Prism::Reflection::Field field) -> String
      def self.field_name(node, field)
        return field.name.to_s unless field.is_a?(Prism::Reflection::FlagsField)

        flags_type(node.class).name.to_s.delete_prefix("Prism::")
      end

      # The flags module whose values are the node's flags. Each set of
      # values belongs to one module.
      #: (singleton(Prism::Node) klass) -> Module
      def self.flags_type(klass)
        field = Prism::Reflection.fields_for(klass).grep(Prism::Reflection::FlagsField).first #: Prism::Reflection::FlagsField
        names = field.flags.map { |flag| flag.to_s.delete_suffix("?").upcase.to_sym }.sort
        Prism.constants.grep(/Flags\z/).map { |name| Prism.const_get(name) }
             .find { |mod| mod.is_a?(Module) && mod.constants(false).sort == names } or raise "no flags of #{klass}"
      end

      # " a, b" for the flags that the node has, in the config's order, or
      # " nil" for none.
      #: (Prism::Node node, Prism::Reflection::FlagsField field) -> String
      def self.flags(node, field)
        set = field.flags.select { |flag| node.public_send(flag) }
        set.empty? ? " nil" : set.map { |flag| " #{flag.to_s.delete_suffix("?")}" }.join(",")
      end

      # prettyprint_location: lines from 1, columns in bytes.
      #: (Prism::Location location) -> String
      def self.location(location)
        "(#{location.start_line},#{location.start_column})-(#{location.end_line},#{location.end_column})"
      end

      # pm_buffer_append_source: bytes 0 to 6, 14 to 31 and 127 and above
      # as \xNN, the other control bytes as their escapes, and a `#` that
      # starts an interpolation escaped.
      #: (String text) -> String
      def self.escaped(text)
        text.b.gsub(/[\x00-\x1f"\\\x7f-\xff]|#(?=[{@$])/n) do |byte|
          next "\\#" if byte == "#"

          ESCAPES[byte] || format("\\x%02X", byte.ord)
        end
      end

      # printf's "%f", which writes the infinities and NaN in lowercase.
      #: (Float value) -> String
      def self.double(value)
        return value.to_s.downcase.sub("infinity", "inf") unless value.finite?

        format("%f", value)
      end
    end
  end
end
