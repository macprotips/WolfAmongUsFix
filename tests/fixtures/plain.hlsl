// No MSAA reads: the fix must leave it alone.
Texture2D<float4> scene : register(t0);

float4 main(float4 pos : SV_Position) : SV_Target
{
    return scene.Load(int3(pos.xy, 0)) * 2;
}
