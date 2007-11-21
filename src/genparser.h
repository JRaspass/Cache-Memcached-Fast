#ifndef GENPARSER_H
#define GENPARSER_H 1


struct genparser_state
{
  char *buf;
  char *buf_end;
  const char *match_pos;
  int phase;
};


static inline
void
genparser_init(struct genparser_state *state)
{
  state->phase = 0;  /* Maps to NO_MATCH in every generated parser.  */
}


static inline
void
genparser_set_buf(struct genparser_state *state, char *buf, char *buf_end)
{
  state->buf = buf;
  state->buf_end = buf_end;
}


static inline
int
genparser_get_phase(const struct genparser_state *state)
{
  return state->phase;
}


static inline
char *
genparser_get_buf(const struct genparser_state *state)
{
  return state->buf;
}


#endif // ! GENPARSER_H
