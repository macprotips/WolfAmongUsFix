/* compile <in.hlsl> <out.dxbc>: ps_5_0 with Microsoft's d3dcompiler_47 (run under Wine).
 * Makes the test fixtures; the .dxbc files are checked in. */
#define COBJMACROS
#include <windows.h>
#include <d3dcompiler.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    ID3DBlob *code = NULL, *errors = NULL;
    static char src[1 << 16];
    size_t n;
    FILE *f;

    if (argc != 3 || !(f = fopen(argv[1], "rb")))
        return 2;
    n = fread(src, 1, sizeof(src), f);
    fclose(f);
    if (FAILED(D3DCompile(src, n, argv[1], NULL, NULL, "main", "ps_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &errors)))
    {
        fprintf(stderr, "%s\n", errors ? (char *)ID3D10Blob_GetBufferPointer(errors) : "failed");
        return 1;
    }
    if (!(f = fopen(argv[2], "wb")))
        return 2;
    fwrite(ID3D10Blob_GetBufferPointer(code), 1, ID3D10Blob_GetBufferSize(code), f);
    fclose(f);
    return 0;
}
