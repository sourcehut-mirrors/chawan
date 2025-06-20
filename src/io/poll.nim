type PollType* = enum
  ptPoll = (1, "poll"), ptSelect = (2, "select")

const forcePollMode {.intdefine.} = 0

const PollMode* = when forcePollMode != 0:
  PollType(forcePollMode)
elif defined(macosx):
  ptSelect
else:
  ptPoll

when PollMode == ptSelect:
  include io/poll_select
else:
  include io/poll_standard
