# `Module#dup`/`#clone` on a CLASS return the SAME OBJECT in zr --
# `K.dup.equal?(K)` is true where ruby answers false. So the name is not
# merely wrong, it is `K`'s own: renaming the copy would rename `K`.
#
# CRuby's `rb_mod_init_copy` moves the source's own method table,
# constants and class-level ivars onto the new class (`clone` additionally
# copies the singleton class and the frozen state; `dup` takes neither).
class K; end
p K.clone.name
p K.dup.name
p K.name
