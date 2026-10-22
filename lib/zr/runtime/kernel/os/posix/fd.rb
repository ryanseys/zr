module Zr::Kern
  # Moves the open file of `from` onto the descriptor `to`, and frees
  # `from`: dup2(2), then close(2) of `from`. Returns -1 with errno set
  # when the dup2 fails, and leaves `from` open then.
  #: (i32, i32) -> i32
  def zr_os_fd_move(from, to)
    r = Libc.dup2(from, to)
    if r < Machine.i32(0)
      return r
    end
    Libc.close(from)
    Machine.i32(0)
  end

  # A directory stream that reads the directory open on `fd` and leaves
  # `fd` open: closedir closes the descriptor that it reads, so the stream
  # reads a dup. 0, with errno set, when either call fails.
  #: (i32) -> ptr
  def zr_os_dir_of_fd(fd)
    copy = Libc.dup(fd)
    if copy < Machine.i32(0)
      return Machine.ptr(0)
    end
    d = Libc.fdopendir(copy)
    if d == 0
      e = zr_errno()
      Libc.close(copy)
      zr_os_set_errno(e)
    end
    d
  end

  # Ends a stream of zr_os_dir_of_fd.
  #: (ptr) -> void
  def zr_os_dir_of_fd_close(d)
    Libc.closedir(d)
  end
end
