# frozen_string_literal: true

module Ze0
  # The sidecar's JSON, written here so stage 1 needs no `require "json"`:
  # strings, integers, booleans, nil, arrays and hashes, nothing else.
  module Json
    def self.dump(value, indent = 0)
      case value
      when Hash
        return "{}" if value.empty?

        pad = "  " * (indent + 1)
        rows = value.map { |k, v| "#{pad}#{dump(k.to_s)}: #{dump(v, indent + 1)}" }
        "{\n#{rows.join(",\n")}\n#{"  " * indent}}"
      when Array
        return "[]" if value.empty?

        pad = "  " * (indent + 1)
        rows = value.map { |v| "#{pad}#{dump(v, indent + 1)}" }
        "[\n#{rows.join(",\n")}\n#{"  " * indent}]"
      when String
        "\"#{escape(value)}\""
      when Integer
        value.to_s
      when true, false
        value.to_s
      when nil
        "null"
      else
        raise ArgumentError, "#{value.class} has no JSON spelling"
      end
    end

    def self.escape(text)
      text.each_char.map do |c|
        case c
        when '"' then '\\"'
        when "\\" then "\\\\"
        when "\n" then "\\n"
        when "\r" then "\\r"
        when "\t" then "\\t"
        else c.ord < 0x20 ? format("\\u%04x", c.ord) : c
        end
      end.join
    end
  end
end
