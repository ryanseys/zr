# a `#:` comment that no def follows
module Zr::Kern
  #: (value) -> value
  # A comment between a type and its def hides the type from RBS.
  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
