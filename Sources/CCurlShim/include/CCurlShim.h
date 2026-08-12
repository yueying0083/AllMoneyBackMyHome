#ifndef C_CURL_SHIM_H
#define C_CURL_SHIM_H

#include <stddef.h>

typedef struct {
    unsigned char *data;
    size_t length;
    long http_status;
    int curl_code;
    char *error_message;
} AMBHHTTPResult;

// proxy_type: 0 direct, 1 http, 2 https, 3 socks5, 4 socks5h.
AMBHHTTPResult ambh_http_get(
    const char *url,
    const char *referer,
    int proxy_type,
    const char *proxy_host,
    int proxy_port,
    long connect_timeout_seconds,
    long total_timeout_seconds
);

void ambh_http_result_free(AMBHHTTPResult result);

#endif
