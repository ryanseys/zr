# Keyword arguments to an inherited instance method:
#
# 1. A bare call in a subclass method goes to the parent's method.
#    In `head(204, content_type: "x")`, the value "x" goes to the
#    `content_type:` keyword, not to the next positional parameter.
#
# 2. The keyword value reaches the method body. It is not lost at the
#    call site.
#
# 3. The ivar gets a String in `initialize` and a String-or-nil
#    parameter in `head`. It stays a String when the parameter is not nil.

class Base
  def initialize
    @content_type = "text/html"
  end

  def head(status, content_type: nil)
    @status = status
    @content_type = content_type unless content_type.nil?
    nil
  end

  def show_content_type
    @content_type
  end
end

class Child < Base
  def render_json
    head(204, content_type: "application/json")
  end

  def render_html
    head(200)
  end
end

c = Child.new
c.render_json
puts c.show_content_type
c2 = Child.new
c2.render_html
puts c2.show_content_type
