#ifndef GENPARSER_H
#define GENPARSER_H 1


struct genparser_state
{
  const char *match_pos;
  int phase;
};


static inline
void
genparser_init(struct genparser_state *state)
{
  state->phase = 0;  /* Maps to NO_MATCH in every generated parser.  */

#if 0 /* No need to initialize the following.  */
  state->match_pos = NULL;
#endif
}


static inline
int
genparser_get_match(const struct genparser_state *state)
{
  return state->phase;
}


#endif // ! GENPARSER_H
