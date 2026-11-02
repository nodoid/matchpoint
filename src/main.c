/* main.c - the only C in Match Point.
 *
 * Everything that matters (screen, input, physics, the match) lives in
 * match.s next door.  This file exists to give the program an entry point.
 */
#include <atmos.h>

#include "matchpoint.h"

int main(void)
{
    /* Never returns: the game owns the machine from here on. */
    game_run();
    return 0;
}
