# frozen_string_literal: true

require "prism"

require_relative "ze0/capi"
require_relative "ze0/names"
require_relative "ze0/params"
require_relative "ze0/scope"
require_relative "ze0/json"
require_relative "ze0/clif"
require_relative "ze0/emit"
require_relative "ze0/lower"

module Ze0
  # Compile `source` (from `file`) to `[clif text, zeodata text]`.
  def self.compile(source, file)
    result = Prism.parse(source, filepath: file)
    unless result.errors.empty?
      e = result.errors.first
      raise Unsupported.new(result.value, "a syntax error: #{e.message}") if e.location.nil?

      raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
    end

    program = Program.new(file, frozen_string_literal: frozen_string_literal?(result))
    Lower.new(program).lower(result.value)
    [program.clif, program.zeodata]
  end

  # The `# frozen_string_literal:` magic comment, which makes every
  # non-interpolated String literal in the file one frozen object. The
  # LAST spelling wins, as it does in ruby.
  def self.frozen_string_literal?(result)
    comment = result.magic_comments.reverse.find { |c| c.key == "frozen_string_literal" }
    comment&.value == "true"
  end
end
