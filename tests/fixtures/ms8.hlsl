// Reads all 8 samples of an 8x MSAA texture, like the game's MSAA resolve shaders.
Texture2DMS<float4, 8> scene : register(t0);

float4 main(float4 pos : SV_Position) : SV_Target
{
    int2 p = int2(pos.xy);
    float4 sum = 0;
    [unroll] for (int i = 0; i < 8; i++)
        sum += scene.Load(p, i) * (i + 1);
    return sum;
}
