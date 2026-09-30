# A constant aliasing a class, defined in a LEXICAL PARENT and reached only
# through `.new` from a class nested inside it. The lexical lookup finds it,
# so no `NameError` occurs. prism's serializer is
# written exactly this way (`FastStringIO = ::StringIO`, then
# `FastStringIO.new` inside its `Loader`).
module M
  module S
    Fast = ::String

    class Loader
      def build = Fast.new("hi")
    end
  end
end
p M::S::Loader.new.build

# A bare read of the same name elsewhere in the class does not change the
# result.
module N
  module T
    Fast = ::String

    class Loader
      def named = Fast
      def build = Fast.new("ok")
    end
  end
end
p N::T::Loader.new.named
p N::T::Loader.new.build

# The same shape one level deeper, and through a qualified path.
module U
  Wrapped = ::Array

  module V
    class Maker
      def build = Wrapped.new(2, 0)
      def qualified = ::U::Wrapped.new(1, 9)
    end
  end
end
p U::V::Maker.new.build
p U::V::Maker.new.qualified
