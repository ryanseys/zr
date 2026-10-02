# The runtime's own warnings go through Warning.warn, as ruby's
# rb_write_warning_str sends them, so a program can catch them.
module Warning
  def self.warn(message, category: nil, **)
    $stdout.print("caught(#{category.inspect}): #{message}")
  end
end

$VERBOSE = true
def m; end
def m; end

class Reader
  attr_reader :object_id
end

class Defined
  define_method(:__send__) { |*| nil }
end

Member = Struct.new(:object_id)

class Undefs
  undef_method :object_id
end

warn "explicit"
p :done
