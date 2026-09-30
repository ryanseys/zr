# The default message of a namespaced exception class uses Ruby's
# `::` module separator, as in "ActiveRecord::RecordNotFound".

module ActiveRecord
  class RecordNotFound < StandardError
  end

  class RecordInvalid < StandardError
  end
end

module Outer
  module Inner
    class DeepError < StandardError
    end
  end
end

# Non-namespaced subclass with underscore in its name should NOT
# get the underscore replaced (My_Class is one identifier).
class My_Class < StandardError
end

puts ActiveRecord::RecordNotFound.new.message
puts ActiveRecord::RecordInvalid.new.message
puts Outer::Inner::DeepError.new.message
puts My_Class.new.message
