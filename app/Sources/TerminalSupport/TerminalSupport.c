#include "TerminalSupport.h"

#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>
#include <wchar.h>
#include <xlocale.h>

static struct termios saved_termios;
static volatile sig_atomic_t terminal_saved;

static struct sigaction previous_int;
static struct sigaction previous_term;
static struct sigaction previous_tstp;

static const char restore_screen[] = "\033[?25h\033[?1049l";

// The signal path uses only POSIX async-signal-safe calls and static storage.
static void handle_signal(int received) {
    if (terminal_saved) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_termios);
        write(STDOUT_FILENO, restore_screen, sizeof(restore_screen) - 1);
    }

    _exit(128 + received);
}

void das_restore_terminal(void) {
    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGTSTP);
    sigprocmask(SIG_BLOCK, &blocked, &previous);

    if (terminal_saved) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_termios);
        write(STDOUT_FILENO, restore_screen, sizeof(restore_screen) - 1);
        terminal_saved = 0;

        sigaction(SIGINT, &previous_int, NULL);
        sigaction(SIGTERM, &previous_term, NULL);
        sigaction(SIGTSTP, &previous_tstp, NULL);
    }

    sigprocmask(SIG_SETMASK, &previous, NULL);
}

int das_enter_raw_mode(void) {
    if (terminal_saved) {
        return 1;
    }

    if (tcgetattr(STDIN_FILENO, &saved_termios) != 0) {
        return 0;
    }

    struct termios settings = saved_termios;
    settings.c_lflag &= ~(ECHO | ICANON);
    settings.c_cc[VMIN] = 1;
    settings.c_cc[VTIME] = 0;

    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGTSTP);
    sigprocmask(SIG_BLOCK, &blocked, &previous);

    struct sigaction action = {0};
    action.sa_handler = handle_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, &previous_int);
    sigaction(SIGTERM, &action, &previous_term);

    // Suspending would leave the terminal raw and on the alternate screen.
    struct sigaction ignore = {0};
    ignore.sa_handler = SIG_IGN;
    sigemptyset(&ignore.sa_mask);
    sigaction(SIGTSTP, &ignore, &previous_tstp);

    terminal_saved = 1;
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &settings) != 0) {
        das_restore_terminal();
        sigprocmask(SIG_SETMASK, &previous, NULL);
        return 0;
    }

    atexit(das_restore_terminal);
    sigprocmask(SIG_SETMASK, &previous, NULL);
    return 1;
}

static pthread_once_t locale_once = PTHREAD_ONCE_INIT;
static locale_t width_locale;

static void initialize_locale(void) {
    width_locale = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", NULL);
}

int das_scalar_width(uint32_t scalar) {
    pthread_once(&locale_once, initialize_locale);

    int width = width_locale ? wcwidth_l((wchar_t)scalar, width_locale) : -1;
    return width < 0 ? 1 : width;
}
