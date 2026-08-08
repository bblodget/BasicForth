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
  printf("SDL_SCALEMODE_NEAREST=%d\n", (int)SDL_SCALEMODE_NEAREST);

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

  printf("\n-- audio --\n");
  printf("SDL_INIT_AUDIO=0x%x\n", (unsigned)SDL_INIT_AUDIO);
  printf("SDL_AUDIO_S16LE=0x%x\n", (unsigned)SDL_AUDIO_S16LE);
  printf("SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK=0x%x\n",
         (unsigned)SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK);
  printf("sizeof(SDL_AudioSpec)=%zu\n", sizeof(SDL_AudioSpec));
  printf("spec.format offset=%zu\n", offsetof(SDL_AudioSpec, format));
  printf("spec.channels offset=%zu\n", offsetof(SDL_AudioSpec, channels));
  printf("spec.freq offset=%zu\n", offsetof(SDL_AudioSpec, freq));

  printf("\n-- keycodes --\n");
  printf("SDLK_ESCAPE=0x%x SDLK_SPACE=0x%x SDLK_Q=0x%x\n",
         (unsigned)SDLK_ESCAPE, (unsigned)SDLK_SPACE, (unsigned)SDLK_Q);
  printf("SDLK_LEFT=0x%x SDLK_RIGHT=0x%x SDLK_UP=0x%x SDLK_DOWN=0x%x\n",
         (unsigned)SDLK_LEFT, (unsigned)SDLK_RIGHT,
         (unsigned)SDLK_UP, (unsigned)SDLK_DOWN);

  printf("\n-- gamepad --\n");
  printf("SDL_INIT_GAMEPAD=0x%x\n", (unsigned)SDL_INIT_GAMEPAD);

  printf("\n-- gamepad buttons --\n");
  printf("SOUTH=%d EAST=%d WEST=%d NORTH=%d\n",
         (int)SDL_GAMEPAD_BUTTON_SOUTH, (int)SDL_GAMEPAD_BUTTON_EAST,
         (int)SDL_GAMEPAD_BUTTON_WEST,  (int)SDL_GAMEPAD_BUTTON_NORTH);
  printf("BACK=%d GUIDE=%d START=%d\n",
         (int)SDL_GAMEPAD_BUTTON_BACK, (int)SDL_GAMEPAD_BUTTON_GUIDE,
         (int)SDL_GAMEPAD_BUTTON_START);
  printf("LEFT_STICK=%d RIGHT_STICK=%d LEFT_SHOULDER=%d RIGHT_SHOULDER=%d\n",
         (int)SDL_GAMEPAD_BUTTON_LEFT_STICK,
         (int)SDL_GAMEPAD_BUTTON_RIGHT_STICK,
         (int)SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,
         (int)SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER);
  printf("DPAD_UP=%d DPAD_DOWN=%d DPAD_LEFT=%d DPAD_RIGHT=%d\n",
         (int)SDL_GAMEPAD_BUTTON_DPAD_UP, (int)SDL_GAMEPAD_BUTTON_DPAD_DOWN,
         (int)SDL_GAMEPAD_BUTTON_DPAD_LEFT,
         (int)SDL_GAMEPAD_BUTTON_DPAD_RIGHT);
  printf("BUTTON_COUNT=%d\n", (int)SDL_GAMEPAD_BUTTON_COUNT);

  printf("\n-- gamepad axes --\n");
  printf("LEFTX=%d LEFTY=%d RIGHTX=%d RIGHTY=%d\n",
         (int)SDL_GAMEPAD_AXIS_LEFTX, (int)SDL_GAMEPAD_AXIS_LEFTY,
         (int)SDL_GAMEPAD_AXIS_RIGHTX, (int)SDL_GAMEPAD_AXIS_RIGHTY);
  printf("LEFT_TRIGGER=%d RIGHT_TRIGGER=%d AXIS_COUNT=%d\n",
         (int)SDL_GAMEPAD_AXIS_LEFT_TRIGGER,
         (int)SDL_GAMEPAD_AXIS_RIGHT_TRIGGER,
         (int)SDL_GAMEPAD_AXIS_COUNT);

  printf("\n-- gamepad events --\n");
  printf("AXIS_MOTION=0x%x BUTTON_DOWN=0x%x BUTTON_UP=0x%x\n",
         (unsigned)SDL_EVENT_GAMEPAD_AXIS_MOTION,
         (unsigned)SDL_EVENT_GAMEPAD_BUTTON_DOWN,
         (unsigned)SDL_EVENT_GAMEPAD_BUTTON_UP);
  printf("ADDED=0x%x REMOVED=0x%x REMAPPED=0x%x\n",
         (unsigned)SDL_EVENT_GAMEPAD_ADDED,
         (unsigned)SDL_EVENT_GAMEPAD_REMOVED,
         (unsigned)SDL_EVENT_GAMEPAD_REMAPPED);
  printf("gbutton.which offset=%zu\n",
         offsetof(SDL_GamepadButtonEvent, which));
  printf("gbutton.button offset=%zu\n",
         offsetof(SDL_GamepadButtonEvent, button));
  printf("gbutton.down offset=%zu\n",
         offsetof(SDL_GamepadButtonEvent, down));
  printf("gaxis.which offset=%zu\n", offsetof(SDL_GamepadAxisEvent, which));
  printf("gaxis.axis offset=%zu\n", offsetof(SDL_GamepadAxisEvent, axis));
  printf("gaxis.value offset=%zu\n", offsetof(SDL_GamepadAxisEvent, value));
  printf("gdevice.which offset=%zu\n", offsetof(SDL_GamepadDeviceEvent, which));
  printf("sizeof(SDL_JoystickID)=%zu\n", sizeof(SDL_JoystickID));
  return 0;
}
