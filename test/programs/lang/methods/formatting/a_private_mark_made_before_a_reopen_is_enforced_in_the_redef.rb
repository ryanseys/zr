# A `private` mark made before a reopen is enforced in the REDEFINITION
# WINDOW, and the reopen clears it -- both channels.
#
# The gap filed this as TWO writes: a mark to apply, and each install to
# rewrite it. It is ONE, because the fact was already in the right place.
# `lower::defs` retags a `def` IN PLACE when `private :v` names a method the
# same body just defined (there is no `MethodVisibility` node at all in that
# shape). So by the time `analyze::redefs` builds a timeline, every body
# already carries its own visibility, and installing it beside the body gives
# both halves at once: the first body's `private` applies, and the second
# body's `public` -- the class body's running default at that `def` -- is
# what clears it.
#
# That is also ruby's own rule. A re-`def` resets a name to the running
# default; it does not inherit the previous body's mark.
#
# The mark rides the existing install in both positions: bits 1-2 of
# `REG_BOOT_REDEF`'s flag byte for the first body (bit 0 was already the
# channel), and a `zr_rt_install_positional_visibility` call beside each
# later one. That entry is infallible on purpose -- unlike
# `zr_rt_runtime_set_visibility` there is no name to resolve and no
# `method_added` to fire, because the install on the line above created the
# method.
#
# Falling back to the static row would NOT have worked: it records the END
# state, which is public here.
class V
  def v = "v1"
  private :v
end
p [(V.new.v rescue $!.class.to_s), V.new.send(:v)]
class V
  def v = "v2"
end
p V.new.v

