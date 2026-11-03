/* Checks the shader patching against shaders compiled by Microsoft's compiler (fixtures/). */
#include "../fix/wolffix_core.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static unsigned char *load(const char *name, size_t *size)
{
    char path[512];
    unsigned char *data;
    FILE *f;

    snprintf(path, sizeof(path), "%s/fixtures/%s", FIXTURES, name);
    if (!(f = fopen(path, "rb")))
    {
        printf("FAIL: can't open %s\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    *size = ftell(f);
    rewind(f);
    data = malloc(*size);
    fread(data, 1, *size, f);
    fclose(f);
    return data;
}

static uint32_t rd32(const unsigned char *p)
{
    return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

/* Our checksum matches the one Microsoft's compiler wrote. */
static void test_checksum(const char *name)
{
    size_t size;
    unsigned char *orig = load(name, &size), *copy = malloc(size);

    memcpy(copy, orig, size);
    memset(copy + 4, 0, 16);
    wolffix_dxbc_checksum(copy, size);
    CHECK(!memcmp(copy, orig, size));
    free(orig);
    free(copy);
}

/* Reads of samples 4..7 become 0..3, and nothing else changes but the checksum. */
static void test_remaps_samples_4_to_7(void)
{
    size_t size, i;
    int count, changed = 0, again;
    unsigned char *orig = load("ms8.dxbc", &size), *fixed = wolffix_remap_samples(orig, size, &count), *check;

    CHECK(fixed != NULL);
    CHECK(count == 4);
    if (!fixed)
        return;
    for (i = 20; i + 4 <= size; i += 4)
    {
        uint32_t before = rd32(orig + i), after = rd32(fixed + i);

        if (before == after)
            continue;
        changed++;
        CHECK(before >= 4 && before < 8 && after == before - 4);
        CHECK(rd32(orig + i - 4) == 0x00004001);
    }
    CHECK(changed == 4);

    check = malloc(size);
    memcpy(check, fixed, size);
    wolffix_dxbc_checksum(check, size);
    CHECK(!memcmp(check, fixed, 20));
    CHECK(memcmp(orig + 4, fixed + 4, 16));

    /* a fixed shader has nothing left to fix */
    CHECK(wolffix_remap_samples(fixed, size, &again) == NULL && again == 0);
    free(check);
    free(fixed);
    free(orig);
}

static void test_leaves_other_shaders_alone(void)
{
    size_t size;
    int count = -1;
    unsigned char *orig = load("plain.dxbc", &size);

    CHECK(wolffix_remap_samples(orig, size, &count) == NULL && count == 0);
    free(orig);
}

/* Truncated or foreign data is left alone, without reading past it. */
static void test_rejects_bad_input(void)
{
    size_t size, cut;
    int count;
    unsigned char *orig = load("ms8.dxbc", &size), junk[64] = "not a shader";

    CHECK(wolffix_remap_samples(NULL, 4096, &count) == NULL);
    CHECK(wolffix_remap_samples(junk, sizeof(junk), &count) == NULL);
    CHECK(wolffix_remap_samples(orig, 16, &count) == NULL);
    for (cut = 0; cut < size; cut += 7)
    {
        unsigned char *part = malloc(cut ? cut : 1), *out;

        memcpy(part, orig, cut);
        out = wolffix_remap_samples(part, cut, &count);
        CHECK(out == NULL);
        free(out);
        free(part);
    }
    free(orig);
}

int main(void)
{
    test_checksum("ms8.dxbc");
    test_checksum("plain.dxbc");
    test_remaps_samples_4_to_7();
    test_leaves_other_shaders_alone();
    test_rejects_bad_input();
    printf(failures ? "%d failed\n" : "all tests passed\n", failures);
    return failures != 0;
}
