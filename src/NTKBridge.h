#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// UTF-8 absolute path, lifetime of process. Resolved from the loaded dylib.
const char *NTKResourceDirectory(void);
#ifdef __cplusplus
}
#endif
