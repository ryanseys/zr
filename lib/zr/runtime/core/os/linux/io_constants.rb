# frozen_string_literal: true

# Linux's lseek(2) whence values, which IO defines, and O_NONBLOCK and
# the access modes, which File::Constants also defines. IO opens its own
# descriptors before File exists, so those are IO's own here.
class IO
  SEEK_SET = 0
  SEEK_CUR = 1
  SEEK_END = 2
  SEEK_DATA = 3
  SEEK_HOLE = 4

  O_NONBLOCK = 2048
  ACCESS = { read: 0, write: 1, both: 2, mask: 3 }.freeze
  private_constant :O_NONBLOCK, :ACCESS
end
