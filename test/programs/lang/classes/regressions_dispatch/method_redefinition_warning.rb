# A reopened class redefines a method. A call before the redefinition
# runs the original body, and a call after it runs the new body
# ("original" then "redefined"), as in CRuby.

class T_method_redefinition_warning_Foo
  def test
    "original"
  end
end

f = T_method_redefinition_warning_Foo.new
puts f.test

class T_method_redefinition_warning_Foo
  def test
    "redefined"
  end
end

puts f.test
