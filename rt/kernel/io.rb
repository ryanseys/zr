# File descriptors: the libSystem calls the IO and File classes use.
# A failure answers the negated errno, which the core turns into the
# Errno class it names.
Machine.import "fopen", [Ptr, Ptr] => Ptr
Machine.import "fileno", [Ptr] => I32
Machine.import "fclose", [Ptr] => I32
Machine.import "read", [I32, Ptr, Word] => Word
Machine.import "close", [I32] => I32
Machine.import "lseek", [I32, Word, I32] => Word
Machine.import "unlink", [Ptr] => I32
Machine.import "rename", [Ptr, Ptr] => I32
Machine.import "isatty", [I32] => I32
Machine.import "mkdir", [Ptr, I32] => I32
Machine.import "rmdir", [Ptr] => I32
Machine.import "chdir", [Ptr] => I32
Machine.import "opendir", [Ptr] => Ptr
Machine.import "readdir", [Ptr] => Ptr
Machine.import "closedir", [Ptr] => I32
Machine.import "__error", [] => Ptr
Machine.import "strerror", [I32] => Ptr

sig [] => Word
machine def zr_errno
  Machine.word(Machine.load32(__error(), 0))
end

sig [Word] => Value
machine def zr_io_failed(r)
  r < 0 ? zr_fix(0 - zr_errno()) : zr_fix(r)
end

# An int answer: 0 on success, -1 with errno set on failure.
sig [I32] => Value
machine def zr_io_status(r)
  r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(0)
end

# fopen(3), which is not variadic as open(2) is: the stream as a
# pointer, or the negated errno. The stream's descriptor is read and
# written directly; the stream only opens and closes it.
sig [Value, Value] => Value
machine def zr_io_open(path, mode)
  f = fopen(RString.ptr(path), RString.ptr(mode))
  if f == 0
    return zr_fix(0 - zr_errno())
  end
  zr_fix(Machine.word(f))
end

sig [Value] => Value
machine def zr_io_fileno(stream)
  zr_fix(Machine.word(fileno(Machine.ptr(zr_fix2long(stream)))))
end

sig [Value] => Value
machine def zr_io_fclose(stream)
  zr_io_status(fclose(Machine.ptr(zr_fix2long(stream))))
end

# Up to `count` bytes: a String, nil at the end, or the negated errno.
sig [Value, Value] => Value
machine def zr_io_read(fd, count)
  n = zr_fix2long(count)
  buf = malloc(n + 1)
  got = read(Machine.i32(zr_fix2long(fd)), buf, n)
  if got < 0
    free(buf)
    return zr_fix(0 - zr_errno())
  end
  if got == 0
    free(buf)
    return Machine.value(QNIL)
  end
  s = zr_str_new(buf, got)
  free(buf)
  s
end

# Every byte of `s`, in as many calls as the descriptor takes.
sig [Value, Value] => Value
machine def zr_io_write(fd, s)
  n = RString.len(s)
  done = 0
  while done < n
    w = write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + done, n - done)
    if w < 0
      return zr_fix(0 - zr_errno())
    end
    done += w
  end
  zr_fix(n)
end

sig [Value] => Value
machine def zr_io_close(fd)
  zr_io_status(close(Machine.i32(zr_fix2long(fd))))
end

sig [Value, Value, Value] => Value
machine def zr_io_seek(fd, offset, whence)
  zr_io_failed(lseek(Machine.i32(zr_fix2long(fd)), zr_fix2long(offset), Machine.i32(zr_fix2long(whence))))
end

sig [Value] => Value
machine def zr_io_tty_p(fd)
  zr_bool(Machine.word(isatty(Machine.i32(zr_fix2long(fd)))) != 0)
end

sig [Value] => Value
machine def zr_io_unlink(path)
  zr_io_status(unlink(RString.ptr(path)))
end

sig [Value, Value] => Value
machine def zr_io_rename(from, to)
  zr_io_status(rename(RString.ptr(from), RString.ptr(to)))
end

sig [Value, Value] => Value
machine def zr_io_mkdir(path, mode)
  zr_io_status(mkdir(RString.ptr(path), Machine.i32(zr_fix2long(mode))))
end

sig [Value] => Value
machine def zr_io_rmdir(path)
  zr_io_status(rmdir(RString.ptr(path)))
end

sig [Value] => Value
machine def zr_io_chdir(path)
  zr_io_status(chdir(RString.ptr(path)))
end

# The names in a directory, `.` and `..` among them, in the order the
# file system answers; or the negated errno.
sig [Value] => Value
machine def zr_io_dir_names(path)
  d = opendir(RString.ptr(path))
  if d == 0
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(8)
  e = readdir(d)
  while e != 0
    name = e + 21
    zr_ary_push(out, zr_str_new(name, zr_cstr_len(name)))
    e = readdir(d)
  end
  closedir(d)
  out
end

# The message strerror gives for errno `n`.
sig [Value] => Value
machine def zr_io_strerror(n)
  p = strerror(Machine.i32(zr_fix2long(n)))
  zr_str_new(p, zr_cstr_len(p))
end

# The size in bytes of the file at `path`, or the negated errno.
sig [Value] => Value
machine def zr_io_file_size(path)
  buf = Machine.slot(160)
  if stat(RString.ptr(path), buf) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_fix(Machine.load64(buf, 96))
end

# access(2): whether the process may use the file as `mode` asks (4
# read, 2 write, 1 execute).
sig [Value, Value] => Value
machine def zr_path_access(path, mode)
  zr_bool(Machine.word(access(RString.ptr(path), Machine.i32(zr_fix2long(mode)))) == 0)
end
