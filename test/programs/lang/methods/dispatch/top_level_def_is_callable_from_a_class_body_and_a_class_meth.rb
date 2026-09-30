# `self` in a class body/class method is the CLASS OBJECT, so
# implicit-self dispatch, such as calling a top-level `def`, must
# resolve correctly against the class object itself.

def helper(tag)
  "helped-#{tag}"
end
class AtBody
  RESULT = helper("body")
end
class Factory
  def self.build
    helper("class-method")
  end
end
puts AtBody::RESULT
puts Factory.build
