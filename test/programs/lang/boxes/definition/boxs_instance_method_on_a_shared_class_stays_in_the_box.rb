# The instance channel. It sits next to the class-method case so that the
# pair reads together.



b = Ruby::Box.new
b.eval("class String; def shout = 'S'; end")
p "a".respond_to?(:shout)
p(begin; "a".shout; rescue NoMethodError; :nome; end)
p b.eval("'a'.shout")
