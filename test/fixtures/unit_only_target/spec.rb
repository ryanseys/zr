module Store
  class Spec
    def self.limit = Rule::LIMIT
  end
  # A method-body `require_relative` is LAZY, so zr splices it at the file
  # tail -- and the file it reaches requires `rule.rb` at top level. That
  # trailing splice must not take the place of the autoload.
  def self.late
    require_relative "cmd"
  end
end
