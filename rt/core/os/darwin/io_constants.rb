# darwin's lseek(2) whence values, which IO names, and O_NONBLOCK, which
# `File::NONBLOCK` also names: IO answers its own descriptors before File
# exists, so the flag is IO's own here.
class IO
  SEEK_SET = 0
  SEEK_CUR = 1
  SEEK_END = 2
  SEEK_HOLE = 3
  SEEK_DATA = 4

  NONBLOCK = 4
  private_constant :NONBLOCK
end
