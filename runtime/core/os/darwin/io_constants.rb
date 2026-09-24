# darwin's lseek(2) whence values, which IO names, and O_NONBLOCK and
# the access modes, which File::Constants also names: IO answers its own
# descriptors before File exists, so those are IO's own here.
class IO
  SEEK_SET = 0
  SEEK_CUR = 1
  SEEK_END = 2
  SEEK_HOLE = 3
  SEEK_DATA = 4

  NONBLOCK = 4
  ACCESS = { read: 0, write: 1, both: 2, mask: 3 }.freeze
  private_constant :NONBLOCK, :ACCESS
end
