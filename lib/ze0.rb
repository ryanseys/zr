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

    program = Program.new(file)
    Lower.new(program).lower(result.value)
    [program.clif, program.zeodata]
  end
end
