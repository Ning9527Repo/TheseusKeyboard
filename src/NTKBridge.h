#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// UTF-8 absolute path, lifetime of process. Resolved from the loaded dylib.
const char *NTKResourceDirectory(void);
uint64_t NTKNowMS(void);
// Lifecycle-only diagnostics. Values are fixed literals, never keyboard content.
void NTKRecordStage(const char *stage);
#ifdef __cplusplus
}
#endif
