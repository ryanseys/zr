# The FFI type registry is whole-program: `FFI.typedef` writes it from
# whatever namespace it stands in, and every `layout` after it reads it. The
# C99 and POSIX names whose width is the same on every target zeo emits for
# resolve without a typedef at all.
require "ffi"

module Vocabulary
  FFI.typedef :uint16, :word
  FFI.typedef :uintptr_t, :handle
end

class Row < FFI::Struct
  layout :w, :word, :h, :handle
end
p [Row.size, Row.offset_of(:h)]

class Fixed < FFI::Struct
  layout :a, :uint8_t, :b, :int32_t, :c, :uintptr_t
end
p [Fixed.size, Fixed.offset_of(:b), Fixed.offset_of(:c)]

# A layout may spell a type or an inline array's count with a CONSTANT of
# the enclosing body -- ffi-ncurses declares its whole vocabulary that way
# above the structs that spend it.
module Vocab
  ATTR_T = :int
  WCHAR  = :ushort
  MAX    = 5

  class Cell < FFI::Struct
    layout :attr, ATTR_T, :chars, [WCHAR, MAX]
  end
end
p [Vocab::Cell.size, Vocab::Cell.offset_of(:chars)]

# A `private_constant` in a branch this compile cannot decide runs where it
# stands, because the branch may never run at all.
module Sealed
  if RUBY_PLATFORM.empty?
    OPEN = :never
  else
    HIDDEN = :secret
    private_constant :HIDDEN
    def self.peek = HIDDEN
  end
end

p Sealed.peek
begin
  Sealed::HIDDEN
rescue NameError => e
  puts e.message
end
__END__
[16, 8]
[16, 4, 8]
[16, 4]
:secret
private constant Sealed::HIDDEN referenced
