module Turnsole

## wrappers around a simple undo stack.
##
## no redo support yet.

module CanUndo
  def to_undo desc, &b
    @undo_stack ||= []
    @undo_stack << [desc, b]
  end

  def undo!
    @undo_stack ||= []
    desc, block = @undo_stack.pop

    if block
      block.call
      @context.screen.minibuf.flash "Undid #{desc}."
    else
      @context.screen.minibuf.flash "Nothing left to undo!"
    end
  end
end
end
