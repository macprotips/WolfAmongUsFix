/* msaa8_test: does an 8x MSAA texture really have 8 samples?
 *
 * Creates an 8x MSAA render target, clears it to one color, and reads all 8 samples back with
 * a compute shader (Texture2DMS.Load with sample indices 0..7). On a GPU with 8x MSAA every
 * sample is the clear color. A device without 8x reports 0 quality levels for it, and then
 * CreateTexture2D with 8 samples has to fail.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -o msaa8_test.exe msaa8_test.c -ld3d11 -ld3dcompiler_47 -ldxguid */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>

static const char shader[] =
    "Texture2DMS<float4> tex : register(t0);\n"
    "RWStructuredBuffer<float4> result : register(u0);\n"
    "[numthreads(8, 1, 1)]\n"
    "void main(uint i : SV_DispatchThreadID) { result[i] = tex.Load(int2(0, 0), i); }\n";

int main(void)
{
    static const float clear[4] = {0.25f, 0.5f, 0.75f, 1.0f};
    D3D11_TEXTURE2D_DESC td = {4, 4, 1, 1, DXGI_FORMAT_R8G8B8A8_UNORM, {8, D3D11_STANDARD_MULTISAMPLE_PATTERN},
            D3D11_USAGE_DEFAULT, D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE, 0, 0};
    D3D11_BUFFER_DESC bd = {8 * 16, D3D11_USAGE_DEFAULT, D3D11_BIND_UNORDERED_ACCESS, 0,
            D3D11_RESOURCE_MISC_BUFFER_STRUCTURED, 16};
    D3D11_UNORDERED_ACCESS_VIEW_DESC ud = {DXGI_FORMAT_UNKNOWN, D3D11_UAV_DIMENSION_BUFFER};
    ID3D11Device *dev;
    ID3D11DeviceContext *ctx;
    ID3D11Texture2D *tex;
    ID3D11RenderTargetView *rtv;
    ID3D11ShaderResourceView *srv;
    ID3D11Buffer *buf, *staging;
    ID3D11UnorderedAccessView *uav;
    ID3D11ComputeShader *cs;
    ID3DBlob *code, *errors = NULL;
    D3D11_MAPPED_SUBRESOURCE map;
    UINT levels = 0, i;
    HRESULT hr;
    int bad = 0;

    if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, NULL, &ctx)))
        return printf("no D3D11 device\n"), 1;
    ID3D11Device_CheckMultisampleQualityLevels(dev, td.Format, 8, &levels);
    printf("CheckMultisampleQualityLevels(R8G8B8A8_UNORM, 8): %u quality levels\n", levels);

    hr = ID3D11Device_CreateTexture2D(dev, &td, NULL, &tex);
    printf("CreateTexture2D with 8 samples: hr 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr))
        return printf("8x isn't available, and the device says so. Nothing wrong.\n"), 0;
    ID3D11Texture2D_GetDesc(tex, &td);
    printf("GetDesc on that texture: %u samples\n", td.SampleDesc.Count);

    ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)tex, NULL, &rtv);
    ID3D11Device_CreateShaderResourceView(dev, (ID3D11Resource *)tex, NULL, &srv);
    ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);

    ud.Buffer.NumElements = 8;
    ID3D11Device_CreateBuffer(dev, &bd, NULL, &buf);
    ID3D11Device_CreateUnorderedAccessView(dev, (ID3D11Resource *)buf, &ud, &uav);
    if (FAILED(D3DCompile(shader, sizeof(shader) - 1, "msaa8", NULL, NULL, "main", "cs_5_0", 0, 0, &code, &errors)))
        return printf("shader: %s\n", errors ? (char *)ID3D10Blob_GetBufferPointer(errors) : "failed"), 1;
    ID3D11Device_CreateComputeShader(dev, ID3D10Blob_GetBufferPointer(code), ID3D10Blob_GetBufferSize(code), NULL, &cs);
    ID3D11DeviceContext_CSSetShader(ctx, cs, NULL, 0);
    ID3D11DeviceContext_CSSetShaderResources(ctx, 0, 1, &srv);
    ID3D11DeviceContext_CSSetUnorderedAccessViews(ctx, 0, 1, &uav, NULL);
    ID3D11DeviceContext_Dispatch(ctx, 1, 1, 1);

    bd.Usage = D3D11_USAGE_STAGING;
    bd.BindFlags = 0;
    bd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ID3D11Device_CreateBuffer(dev, &bd, NULL, &staging);
    ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)staging, (ID3D11Resource *)buf);
    ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &map);
    printf("cleared to (%.2f %.2f %.2f %.2f); samples read back:\n", clear[0], clear[1], clear[2], clear[3]);
    for (i = 0; i < 8; i++)
    {
        const float *v = (const float *)map.pData + 4 * i;
        int ok = 1, c;

        for (c = 0; c < 4; c++)  /* 8-bit UNORM: within one step */
            ok &= v[c] > clear[c] - 0.005f && v[c] < clear[c] + 0.005f;

        printf("  sample %u: (%g %g %g %g)%s\n", i, v[0], v[1], v[2], v[3], ok ? "" : "  <- not the clear color");
        bad += !ok;
    }
    ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)staging, 0);
    printf(td.SampleDesc.Count == 8 && !bad ? "PASS\n" : "FAIL: asked for 8 samples, the texture doesn't behave like it has 8\n");
    return td.SampleDesc.Count == 8 && !bad ? 0 : 1;
}
