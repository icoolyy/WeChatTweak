#pragma once
#ifdef __cplusplus
extern "C" {
#endif

// Main-thread only. Returned JSON / strings are malloc-owned; release with
// wct_native_free. Health contains no contact data. No pointer survives a request.
char *wct_native_health_json(void);
char *wct_native_search_json(const char *keyword, int pinyin, int fuzzy);
char *wct_native_avatar_json(const char *identifier, const char *expectedEpoch);
// Returns request acceptance only. Bridge must poll selected ID before success.
char *wct_native_request_open_json(const char *identifier);
char *wct_native_selected_id(void);
void wct_native_free(void *value);
// Research acceptance: returns flags for real Chinese/pinyin/remark search checks.
int wct_native_probe_search_validation(void);

#ifdef __cplusplus
}
#endif
