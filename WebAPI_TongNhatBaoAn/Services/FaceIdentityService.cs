using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace WebAPI_TongNhatBaoAn.Services;

public sealed class FaceInputException(string message) : Exception(message);
public sealed class FaceUnavailableException : Exception { }

public static class FaceMath
{
    public const double Threshold = 0.45;
    public static double Cosine(float[] a, float[] b)
    {
        if (a.Length != 128 || b.Length != 128 || a.Any(x => !float.IsFinite(x)) || b.Any(x => !float.IsFinite(x)))
            return -1;
        double dot = 0, na = 0, nb = 0;
        for (var i = 0; i < a.Length; i++) { dot += (double)a[i] * b[i]; na += (double)a[i] * a[i]; nb += (double)b[i] * b[i]; }
        return na <= 0 || nb <= 0 ? -1 : dot / Math.Sqrt(na * nb);
    }
}

public sealed class FaceMatcher(HttpClient client)
{
    public async Task<float[]> Extract(string? image)
    {
        if (string.IsNullOrEmpty(image) || image.Length > 4_194_304)
            throw new FaceInputException("Ảnh thiếu hoặc quá lớn. Hãy chụp lại trong ứng dụng.");
        byte[] bytes;
        try { bytes = Convert.FromBase64String(image); }
        catch (FormatException) { throw new FaceInputException("Dữ liệu ảnh không hợp lệ."); }
        if (bytes.Length is < 100 or > 3_145_728) throw new FaceInputException("Ảnh phải nhỏ hơn 3 MB.");
        try
        {
            using var content = new ByteArrayContent(bytes);
            content.Headers.ContentType = new("application/octet-stream");
            using var response = await client.PostAsync("http://127.0.0.1:5051/embedding", content);
            if (response.StatusCode == System.Net.HttpStatusCode.BadRequest)
            {
                var error = await response.Content.ReadFromJsonAsync<FaceError>();
                throw new FaceInputException(error?.Error ?? "Ảnh khuôn mặt không hợp lệ.");
            }
            if (!response.IsSuccessStatusCode) throw new FaceUnavailableException();
            var result = await response.Content.ReadFromJsonAsync<Embedding>();
            if (result == null || FaceMath.Cosine(result.Vector, result.Vector) < 0.99)
                throw new FaceUnavailableException();
            return result.Vector;
        }
        catch (HttpRequestException) { throw new FaceUnavailableException(); }
        catch (OperationCanceledException) { throw new FaceUnavailableException(); }
        catch (JsonException) { throw new FaceUnavailableException(); }
    }
    private sealed record Embedding(float[] Vector);
    private sealed record FaceError(string Error);
}

public sealed class FaceTemplateCipher(IConfiguration cfg)
{
    private byte[] Key => SHA256.HashData(Encoding.UTF8.GetBytes("face-template-v1:" +
        (cfg["Face:EncryptionKey"] ?? cfg["Jwt:Key"] ?? throw new FaceUnavailableException())));

    public string Encrypt(float[] vector)
    {
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(vector);
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(Key, 16);
        aes.Encrypt(nonce, plaintext, ciphertext, tag);
        return Convert.ToBase64String(nonce.Concat(tag).Concat(ciphertext).ToArray());
    }

    public float[] Decrypt(string value)
    {
        try
        {
            var bytes = Convert.FromBase64String(value);
            if (bytes.Length < 29) throw new CryptographicException();
            var plaintext = new byte[bytes.Length - 28];
            using var aes = new AesGcm(Key, 16);
            aes.Decrypt(bytes.AsSpan(0, 12), bytes.AsSpan(28), bytes.AsSpan(12, 16), plaintext);
            return JsonSerializer.Deserialize<float[]>(plaintext) ?? throw new FaceUnavailableException();
        }
        catch (Exception ex) when (ex is FormatException or CryptographicException or JsonException)
        { throw new FaceUnavailableException(); }
    }
}

