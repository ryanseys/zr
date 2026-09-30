# Test: an ivar can have a keyword name (`@if`), and `@iv_if` is a different ivar.

class T_ivar_c_keyword_KeywordIvar
  def initialize
    @if = 40
    @iv_if = 1
  end

  def value
    @if + @iv_if + 1
  end
end

puts T_ivar_c_keyword_KeywordIvar.new.value
