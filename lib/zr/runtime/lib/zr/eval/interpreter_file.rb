# frozen_string_literal: true

# The toplevel of each file that the tree-walking interpreter runs for a
# require: a file that the program was not compiled with. The kernel runs
# a required file by the address of its compiled toplevel, and the
# interpreter has no compiled code to give. So `Zr::Eval#compile_file`
# gives the address of this file's toplevel, and this toplevel walks the
# file that it holds next. Each run has a frame of its own, so its
# binding is a new top-level scope, with main as self, as a required
# file has. Its lexical scope is the top-level one too: Object, with no
# outer scope. The cref of the frame that requires the file (an
# interpreter's frame, or `module M; require "x"; end`) is not the file's.
#
# The first run is the require that loads the interpreter. It holds no
# file, and keeps this file's path, to find its address later.

::Zr::Eval.current.walk_next(Primitive.zr_own_binding, __FILE__, Primitive.zr_eval_cref_under(Object, nil))
