#include "CCurlShim.h"
#include <curl/curl.h>
#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned char *bytes;
    size_t length;
} AMBHBuffer;

static pthread_once_t ambh_curl_once = PTHREAD_ONCE_INIT;

static void ambh_curl_initialize(void) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
}

static size_t ambh_write(void *contents, size_t size, size_t count, void *context) {
    size_t incoming = size * count;
    AMBHBuffer *buffer = (AMBHBuffer *)context;
    if (incoming == 0 || buffer->length > SIZE_MAX - incoming) return 0;

    unsigned char *grown = realloc(buffer->bytes, buffer->length + incoming);
    if (grown == NULL) return 0;
    buffer->bytes = grown;
    memcpy(buffer->bytes + buffer->length, contents, incoming);
    buffer->length += incoming;
    return incoming;
}

static curl_proxytype ambh_proxy_type(int proxy_type) {
    switch (proxy_type) {
        case 1: return CURLPROXY_HTTP;
        case 2: return CURLPROXY_HTTPS;
        case 3: return CURLPROXY_SOCKS5;
        case 4: return CURLPROXY_SOCKS5_HOSTNAME;
        default: return CURLPROXY_HTTP;
    }
}

AMBHHTTPResult ambh_http_get(
    const char *url,
    const char *referer,
    int proxy_type,
    const char *proxy_host,
    int proxy_port,
    long connect_timeout_seconds,
    long total_timeout_seconds
) {
    AMBHHTTPResult result = {0};
    pthread_once(&ambh_curl_once, ambh_curl_initialize);
    CURL *curl = curl_easy_init();
    if (curl == NULL) {
        result.curl_code = CURLE_FAILED_INIT;
        result.error_message = strdup("Unable to initialize libcurl");
        return result;
    }

    AMBHBuffer buffer = {0};
    char error_buffer[CURL_ERROR_SIZE] = {0};
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_REFERER, referer);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "AMBH/1.0");
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, ambh_write);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buffer);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, connect_timeout_seconds);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, total_timeout_seconds);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 3L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_PROXY_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_PROXY_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, error_buffer);

    // CURLOPT_PROXY with an empty value explicitly bypasses environment/system proxies.
    if (proxy_type == 0) {
        curl_easy_setopt(curl, CURLOPT_PROXY, "");
    } else {
        curl_easy_setopt(curl, CURLOPT_PROXY, proxy_host);
        curl_easy_setopt(curl, CURLOPT_PROXYPORT, (long)proxy_port);
        curl_easy_setopt(curl, CURLOPT_PROXYTYPE, ambh_proxy_type(proxy_type));
    }

    CURLcode code = curl_easy_perform(curl);
    result.curl_code = (int)code;
    result.data = buffer.bytes;
    result.length = buffer.length;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &result.http_status);
    if (code != CURLE_OK) {
        const char *message = error_buffer[0] != '\0' ? error_buffer : curl_easy_strerror(code);
        result.error_message = strdup(message);
    }
    curl_easy_cleanup(curl);
    return result;
}

void ambh_http_result_free(AMBHHTTPResult result) {
    free(result.data);
    free(result.error_message);
}
