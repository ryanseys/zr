# `include A` brings A's nested constants/modules into the includer's
# constant lookup chain. This holds also when a module itself does
# `include X`: a class that includes that module can read a bare
# nested constant from X in a method body. The lookup recurses into
# modules as well as classes.

module ActionView
  module ViewHelpers
    def self.reset_slots!
      42
    end
  end
end

module RequestDispatch
  include ActionView

  def call
    ViewHelpers.reset_slots!
  end
end

class Test
  include RequestDispatch
end

puts Test.new.call

# Multi-level chain: include of an include. Top-level constant lookup
# still finds the deeply nested module's class method.
module Outer
  module DeepHelpers
    def self.label
      "deep"
    end
  end
end

module MiddleMixin
  include Outer
end

module OuterMixin
  include MiddleMixin

  def fetch_label
    DeepHelpers.label
  end
end

class Consumer
  include OuterMixin
end

puts Consumer.new.fetch_label
