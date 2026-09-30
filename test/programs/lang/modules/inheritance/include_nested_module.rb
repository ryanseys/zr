# A bare-receiver call to a method defined on an `include`d
# module works when the including class is nested inside a
# module namespace:
#
#   module Ns
#     module Helper
#       def helped; "helped"; end
#     end
#     class Base
#       include Helper
#       def call; helped; end
#     end
#   end
#
# The include arg `Helper` resolves to `Ns::Helper` first, and
# to a top-level module when the namespace has none.
#
# Coverage:
#   - Canonical Rails-style shape: module namespace, included
#     module also in the namespace.
#   - Cross-namespace include: top-level module included into a
#     nested class.  The qualified lookup misses, falls back to
#     the bare name, still resolves.
#   - Multiple levels of nesting via class reopening are not
#     covered here.

module Ns
  module Helper
    def helped
      "helped-from-Ns"
    end
  end

  class Base
    include Helper

    def call
      helped
    end
  end
end

puts Ns::Base.new.call            # helped-from-Ns

# Cross-namespace fallback: top-level module included into a
# nested class. The qualified `Ns2_Helper2` doesn't exist, so the
# resolver falls back to the bare `Helper2` which DOES exist at
# top-level.
module Helper2
  def helped2
    "helped-from-top"
  end
end

module Ns2
  class Base2
    include Helper2

    def call2
      helped2
    end
  end
end

puts Ns2::Base2.new.call2          # helped-from-top

# Same shape with no nesting.
module BareHelper
  def hi
    "hi"
  end
end

class BareBase
  include BareHelper

  def go
    hi
  end
end

puts BareBase.new.go               # hi
