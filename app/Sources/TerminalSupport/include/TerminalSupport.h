#ifndef DAS_TERMINAL_SUPPORT_H
#define DAS_TERMINAL_SUPPORT_H
#include <stdint.h>
int das_enter_raw_mode(void);
void das_restore_terminal(void);
int das_scalar_width(uint32_t scalar);
#endif
