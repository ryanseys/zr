# A `class << self` body holding a BARE `private` compiles inside a run-time
# `eval`.
#
# A class body in a snippet runs as a `class_eval` of its own source text.
# A bare `private` in a singleton body makes the methods after it private
# until the body ends. The `class << self` of rubygems' `platform.rb` has
# a bare `private` two thirds of the way down.

src = <<~RUBY
  class Widget
    class << self
      def build
        "built"
      end

      private

      def helper
        "helper"
      end
    end
  end
RUBY

eval src

p Widget.build
p Widget.singleton_class.private_method_defined?(:helper)
begin
  Widget.helper
rescue NoMethodError => e
  p e.class
end
# The cursor dies with the body, exactly as CRuby's dies with the cref: a
# `def self.x` written after it is public again.
class Widget
  def self.after
    "after"
  end
end
p Widget.after
