// doomgeneric for Nova on BoredOS
// Copyright (c) 2026 Christiaan (chris@boreddev.nl)
// Released under the GNU General Public License v3.0.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>
#include <ctype.h>
#include <syscall.h>
#include <poll.h>

#include <novaproto.h>

enum {
    NOVA_KEY_A = 1,
    NOVA_KEY_Z = 26,
    NOVA_KEY_0 = 27,
    NOVA_KEY_9 = 36,
    NOVA_KEY_ENTER = 37,
    NOVA_KEY_ESCAPE = 38,
    NOVA_KEY_BACKSPACE = 39,
    NOVA_KEY_TAB = 40,
    NOVA_KEY_SPACE = 41,
    NOVA_KEY_LEFT = 42,
    NOVA_KEY_RIGHT = 43,
    NOVA_KEY_UP = 44,
    NOVA_KEY_DOWN = 45,
    NOVA_KEY_LSHIFT = 46,
    NOVA_KEY_RSHIFT = 47,
    NOVA_KEY_LCTRL = 48,
    NOVA_KEY_RCTRL = 49,
    NOVA_KEY_LALT = 50,
    NOVA_KEY_RALT = 51
};

#include "doomkeys.h"
#include "doomgeneric.h"

#define WINDOW_WIDTH  640
#define WINDOW_HEIGHT 400
#define NORMAL_LAYER  2

#define KEYQUEUE_SIZE 32

static int nova_fd = -1;
static uint32_t surface_id = 0;
static uint32_t *shm_pixels = NULL;
static size_t shm_size = 0;
static char shm_path[128];

static unsigned short s_KeyQueue[KEYQUEUE_SIZE];
static unsigned int s_KeyQueueWriteIndex = 0;
static unsigned int s_KeyQueueReadIndex = 0;

static unsigned char convertToDoomKey(uint32_t nova_key) {
    if (nova_key >= NOVA_KEY_A && nova_key <= NOVA_KEY_Z) {
        return 'a' + (nova_key - NOVA_KEY_A);
    }
    if (nova_key >= NOVA_KEY_0 && nova_key <= NOVA_KEY_9) {
        return '0' + (nova_key - NOVA_KEY_0);
    }
    
    if (nova_key == NOVA_KEY_ENTER)     return KEY_ENTER;
    if (nova_key == NOVA_KEY_ESCAPE)    return KEY_ESCAPE;
    if (nova_key == NOVA_KEY_BACKSPACE) return KEY_BACKSPACE;
    if (nova_key == NOVA_KEY_TAB)       return KEY_TAB;
    if (nova_key == NOVA_KEY_SPACE)     return KEY_USE; 
    if (nova_key == NOVA_KEY_LEFT)      return KEY_LEFTARROW;
    if (nova_key == NOVA_KEY_RIGHT)     return KEY_RIGHTARROW;
    if (nova_key == NOVA_KEY_UP)        return KEY_UPARROW;
    if (nova_key == NOVA_KEY_DOWN)      return KEY_DOWNARROW;
    if (nova_key == NOVA_KEY_LSHIFT || nova_key == NOVA_KEY_RSHIFT) return KEY_RSHIFT;
    if (nova_key == NOVA_KEY_LCTRL || nova_key == NOVA_KEY_RCTRL)   return KEY_FIRE; 
    if (nova_key == NOVA_KEY_LALT || nova_key == NOVA_KEY_RALT)     return KEY_LALT; 
    
    return 0;
}
static void addKeyToQueue(int pressed, uint32_t keyCode) {
    unsigned char key = convertToDoomKey(keyCode);
    if (key == 0) return;

    unsigned short keyData = (pressed << 8) | key;
    s_KeyQueue[s_KeyQueueWriteIndex] = keyData;
    s_KeyQueueWriteIndex = (s_KeyQueueWriteIndex + 1) % KEYQUEUE_SIZE;
}
static void cleanup_nova() {
    if (nova_fd >= 0) {
        if (surface_id > 0) {
            nova_destroy_surface(nova_fd, surface_id);
            surface_id = 0;
        }
        if (shm_pixels && shm_pixels != MAP_FAILED) {
            munmap(shm_pixels, shm_size);
            shm_pixels = NULL;
        }
        close(nova_fd);
        nova_fd = -1;
    }
}
static void poll_nova_events() {
    struct pollfd pfd;
    pfd.fd = nova_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    while (nova_pending_events() || poll(&pfd, 1, 0) > 0) {
        NovaEvent ev;
        if (nova_poll_event(nova_fd, &ev) != 0) {
            break;
        }

        if (ev.type == EVT_CLOSE_REQUEST) {
            exit(0);
        } else if (ev.type == EVT_KEY) {
            addKeyToQueue(ev.data.key.pressed, ev.data.key.keycode);
        }
        
        pfd.revents = 0;
    }
}
void DG_Init() {
    atexit(cleanup_nova);

    nova_fd = nova_connect(NULL);
    if (nova_fd < 0) {
        fprintf(stderr, "DoomGeneric Error: Failed to connect to Nova WM\n");
        exit(1);
    }
    if (nova_create_surface(nova_fd, WINDOW_WIDTH, WINDOW_HEIGHT, NORMAL_LAYER, SURFACE_FLAG_NO_RESIZE, &surface_id, shm_path) < 0) {
        fprintf(stderr, "DoomGeneric Error: Surface allocation failed\n");
        close(nova_fd);
        exit(1);
    }
    int shm_fd = open(shm_path, O_RDWR);
    if (shm_fd < 0) {
        fprintf(stderr, "DoomGeneric Error: Cannot open SHM segment %s\n", shm_path);
        close(nova_fd);
        exit(1);
    }
    shm_size = WINDOW_WIDTH * WINDOW_HEIGHT * 4;
    shm_pixels = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    close(shm_fd);

    if (shm_pixels == MAP_FAILED) {
        fprintf(stderr, "DoomGeneric Error: mmap failed\n");
        close(nova_fd);
        exit(1);
    }
    nova_set_title(nova_fd, surface_id, "DOOMgeneric");
}
void DG_DrawFrame() {
    if (!shm_pixels || !DG_ScreenBuffer) return;
    memcpy(shm_pixels, DG_ScreenBuffer, WINDOW_WIDTH * WINDOW_HEIGHT * 4);
    NovaRect damage = { 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT };
    nova_damage_surface(nova_fd, surface_id, 1, &damage);
    poll_nova_events();
}
void DG_SleepMs(uint32_t ms) {
    if (ms == 0) return;


    if (ms < 10) {
        sched_yield();
    } else {
        sleep(ms);
    }
}
uint32_t DG_GetTicksMs() {
    return (uint32_t)get_ticks() * 50 / 3;
}
int DG_GetKey(int* pressed, unsigned char* doomKey) {
    if (s_KeyQueueReadIndex == s_KeyQueueWriteIndex) {
        return 0; 
    } else {
        unsigned short keyData = s_KeyQueue[s_KeyQueueReadIndex];
        s_KeyQueueReadIndex = (s_KeyQueueReadIndex + 1) % KEYQUEUE_SIZE;

        *pressed = keyData >> 8;
        *doomKey = keyData & 0xFF;

        return 1;
    }
}
void DG_SetWindowTitle(const char *title) {
    if (nova_fd >= 0 && surface_id > 0) {
        char full_title[256];
        snprintf(full_title, sizeof(full_title), "BoredOS Doom - %s", title);
        nova_set_title(nova_fd, surface_id, full_title);
    }
}
int main(int argc, char **argv) {
    doomgeneric_Create(argc, argv);

    uint32_t last_tick = DG_GetTicksMs();

    while (1) {
        doomgeneric_Tick();
        
        while (1) {
            uint32_t now = DG_GetTicksMs();
            if ((now - last_tick) >= 28) {
                last_tick = now;
                break;
            }
            
            uint32_t remain = 28 - (now - last_tick);
            if (remain >= 10) {
                sleep(remain);
            } else {
                sched_yield();
            }
        }
    }

    return 0;
}

