# frozen_string_literal: true

require "prism"

require_relative "ze0/capi"
require_relative "ze0/guards"
require_relative "ze0/names"
require_relative "ze0/params"
require_relative "ze0/scope"
require_relative "ze0/json"
require_relative "ze0/clif"
require_relative "ze0/emit"
require_relative "ze0/patterns"
require_relative "ze0/lower"

module Ze0
  # Compile `source` (from `file`) to `[clif text, zeodata text]`.
  def self.compile(source, file, roots = [])
    result = Prism.parse(source, filepath: file)
    unless result.errors.empty?
      e = result.errors.first
      raise Unsupported.new(result.value, "a syntax error: #{e.message}") if e.location.nil?

      raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
    end

    program = Program.new(file, frozen_string_literal: frozen_string_literal?(result))
    program.data_section = data_section(result, file)
    Lower.new(program, roots).lower(result.value)
    [program.clif, program.zeodata]
  end

  # Where `DATA` reads from: the main file's `__END__` bytes. prism's
  # `data_loc` spans the MARKER and the bytes after it, so the offset is
  # past `__END__` and the one line terminator CRuby skips there -- a
  # blank line after the marker is DATA's first line. A file with no
  # `__END__` leaves `DATA` undefined rather than empty.
  def self.data_section(result, file)
    loc = result.data_loc
    return nil if loc.nil?

    after = result.source.source.byteslice(loc.start_offset + MARKER, 2).to_s
    terminator = after.start_with?("\r") ? 2 : 1
    [File.expand_path(file), loc.start_offset + MARKER + terminator]
  end

  MARKER = "__END__".bytesize

  # The `# frozen_string_literal:` magic comment, which makes every
  # non-interpolated String literal in the file one frozen object. The
  # LAST spelling wins, as it does in ruby.
  def self.frozen_string_literal?(result)
    comment = result.magic_comments.reverse.find { |c| c.key == "frozen_string_literal" }
    comment&.value == "true"
  end
end
