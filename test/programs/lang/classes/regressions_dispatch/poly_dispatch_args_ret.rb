# A method returns instances of different classes from its branches.

class T_poly_dispatch_args_ret_A
  def read(v)
    v + 1
  end
end

class T_poly_dispatch_args_ret_B
  def read(v)
    v + 2
  end
end

class T_poly_dispatch_args_ret_Builder
  def make(flag)
    if flag == 0
      T_poly_dispatch_args_ret_A.new
    else
      T_poly_dispatch_args_ret_B.new
    end
  end

  def make_with_return(flag)
    if flag == 0
      return T_poly_dispatch_args_ret_A.new
    end
    return T_poly_dispatch_args_ret_B.new
  end
end

b = T_poly_dispatch_args_ret_Builder.new

obj0 = b.make(0)
puts obj0.read(41)

obj1 = b.make(1)
puts obj1.read(41)

ret0 = b.make_with_return(0)
puts ret0.read(41)

ret1 = b.make_with_return(1)
puts ret1.read(41)
