/* BasicForth — SDL3 constant / struct-offset reference (dev aid, not built
 * into BasicForth). Prints the constants and event-struct offsets that
 * sdl3.fs hard-codes, straight from the SDL3 headers, so they can be
 * verified rather than guessed.
 * Build & run:  cc -I<sdl3-src>/include -o sdl3off tools/sdl3off.c && ./sdl3off
 * SPDX-License-Identifier: GPL-2.0-only */
#include <stdio.h>
#include <stddef.h>
#include <SDL3/SDL.h>

int main(void) {
  printf("-- init / window / texture constants --\n");
  printf("SDL_INIT_VIDEO=0x%x\n", (unsigned)SDL_INIT_VIDEO);
  printf("SDL_PIXELFORMAT_XRGB8888=0x%x\n", (unsigned)SDL_PIXELFORMAT_XRGB8888);
  printf("SDL_TEXTUREACCESS_STREAMING=%d\n", (int)SDL_TEXTUREACCESS_STREAMING);

  printf("\n-- event types --\n");
  printf("SDL_EVENT_QUIT=0x%x\n", (unsigned)SDL_EVENT_QUIT);
  printf("SDL_EVENT_KEY_DOWN=0x%x\n", (unsigned)SDL_EVENT_KEY_DOWN);
  printf("SDL_EVENT_KEY_UP=0x%x\n", (unsigned)SDL_EVENT_KEY_UP);
  printf("SDL_EVENT_WINDOW_CLOSE_REQUESTED=0x%x\n",
         (unsigned)SDL_EVENT_WINDOW_CLOSE_REQUESTED);

  printf("\n-- SDL_Event --\n");
  printf("sizeof(SDL_Event)=%zu\n", sizeof(SDL_Event));
  printf("event.type offset=%zu\n", offsetof(SDL_Event, type));
  printf("key.scancode offset=%zu\n", offsetof(SDL_KeyboardEvent, scancode));
  printf("key.key offset=%zu\n", offsetof(SDL_KeyboardEvent, key));
  printf("key.mod offset=%zu\n", offsetof(SDL_KeyboardEvent, mod));
  printf("key.down offset=%zu\n", offsetof(SDL_KeyboardEvent, down));
  printf("key.repeat offset=%zu\n", offsetof(SDL_KeyboardEvent, repeat));

  printf("\n-- keycodes --\n");
  printf("SDLK_ESCAPE=0x%x SDLK_SPACE=0x%x SDLK_Q=0x%x\n",
         (unsigned)SDLK_ESCAPE, (unsigned)SDLK_SPACE, (unsigned)SDLK_Q);
  printf("SDLK_LEFT=0x%x SDLK_RIGHT=0x%x SDLK_UP=0x%x SDLK_DOWN=0x%x\n",
         (unsigned)SDLK_LEFT, (unsigned)SDLK_RIGHT,
         (unsigned)SDLK_UP, (unsigned)SDLK_DOWN);
  return 0;
}
