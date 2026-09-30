# frozen_string_literal: true

# erb's escape.c, in ruby: ERB::Escape.html_escape, the one escape that
# ERB ships as a C extension. Rails is not expected to override this one,
# which is why ERB keeps it apart from `ERB::Util#html_escape`. The C
# defines the class ERB itself, so the file works without erb.rb. It
# also defines an empty class CGI, and calls CGI.escapeHTML only for a
# string whose encoding is not ASCII-compatible; it does not load
# cgi/escape.
class ERB
  module Escape
    # Returns `str` itself when it has nothing to escape, as the C does,
    # else a new String in the same encoding. A value that is not a
    # String is converted with to_s first.
    def html_escape(str)
      unless str.is_a?(String)
        converted = str.to_s
        unless converted.is_a?(String)
          name = conversion_name(str)
          raise TypeError, "can't convert #{name} to String (#{name}#to_s gives #{conversion_name(converted)})"
        end
        str = converted
      end
      return CGI.escapeHTML(str) unless str.encoding.ascii_compatible?

      bytes = str.b
      return str unless bytes.match?(/['&"<>]/n)

      bytes.gsub(/['&"<>]/n, "'" => "&#39;", "&" => "&amp;", '"' => "&quot;", "<" => "&lt;", ">" => "&gt;").force_encoding(str.encoding)
    end
    module_function :html_escape
  end
end

class CGI
end
