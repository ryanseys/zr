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
require_relative "ze0/ffi"
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

    program = Program.new(
      file,
      frozen_string_literal: frozen_string_literal?(result),
      script_encoding: script_encoding(result, result.value),
    )
    program.data_section = data_section(result, file)
    program.warn_from(result, file)
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

  # Ruby's own parse-time warnings for one file -- `key :k is duplicated and
  # overwritten on line 24` and friends. prism already knows the rules and
  # which line each one names, so reading its list is the one source of
  # truth. `verbose` is the `ruby -w` tier, which a plain run never prints.
  def self.parse_warnings(result, file)
    result.warnings.filter_map do |w|
      next unless w.level == :default

      "#{file}:#{w.location.start_line}: warning: #{w.message}"
    end
  end

  # The `# frozen_string_literal:` magic comment, which makes every
  # non-interpolated String literal in the file one frozen object. The
  # LAST spelling wins, as it does in ruby.
  def self.frozen_string_literal?(result)
    comment = result.magic_comments.reverse.find { |c| c.key == "frozen_string_literal" }
    comment&.value == "true"
  end

  # The `Encoding::` constant spelling of the source encoding, or nil for
  # UTF-8 -- which is what ze0 reads a source as when nothing says
  # otherwise. prism reads the `# encoding:`/`# coding:` magic comment and
  # applies ruby's own placement rule, so a `# encoding::` inside an rdoc
  # paragraph names nothing. The four are what the runtime carries.
  SOURCE_ENCODINGS = {
    "UTF-8" => nil,
    "US-ASCII" => "US_ASCII",
    "ASCII-8BIT" => "ASCII_8BIT",
    "ISO-8859-1" => "ISO_8859_1",
  }.freeze

  def self.script_encoding(result, node)
    name = result.encoding.name
    raise Unsupported.new(node, "the source encoding `#{name}`") unless SOURCE_ENCODINGS.key?(name)

    SOURCE_ENCODINGS[name]
  end
end
