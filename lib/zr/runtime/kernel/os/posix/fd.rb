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
end
