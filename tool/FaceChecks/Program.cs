using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using WebAPI_TongNhatBaoAn.Services;

var checks = 0;
void Check(bool ok, string label)
{
    if (!ok) throw new Exception(label);
    checks++;
    Console.WriteLine("PASS " + label);
}
var a = new float[128]; a[0] = 1;
var b = new float[128]; b[1] = 1;
Check(FaceMath.Cosine(a, a) == 1, "Same template matches");
Check(FaceMath.Cosine(a, b) < FaceMath.Threshold, "Different template rejected");
Check(FaceMath.Cosine([], a) == -1, "Wrong dimensions rejected");
Check(FaceMath.Cosine(new float[128], a) == -1, "Zero template rejected");
var invalid = a.ToArray(); invalid[3] = float.NaN;
Check(FaceMath.Cosine(invalid, a) == -1, "NaN template rejected");
var cfg = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Jwt:Key"] = "test-only-key-with-at-least-32-characters" }).Build();
var cipher = new FaceTemplateCipher(cfg);
var encrypted = cipher.Encrypt(a);
Check(FaceMath.Cosine(a, cipher.Decrypt(encrypted)) == 1, "Encrypted template roundtrip");
Check(encrypted != cipher.Encrypt(a), "Random nonce per stored template");
var tampered = Convert.FromBase64String(encrypted); tampered[^1] ^= 1;
var rejected = false;
try { cipher.Decrypt(Convert.ToBase64String(tampered)); }
catch (FaceUnavailableException) { rejected = true; }
Check(rejected, "Tampered template rejected");
foreach (var status in new[] { HttpStatusCode.OK, HttpStatusCode.BadRequest, HttpStatusCode.ServiceUnavailable })
{
    using var http = new HttpClient(new FakeEmbeddingHandler(status, a));
    var matcher = new FaceMatcher(http);
    try
    {
        var vector = await matcher.Extract(Convert.ToBase64String(new byte[200]));
        Check(status == HttpStatusCode.OK && FaceMath.Cosine(vector, a) == 1, "Worker vector accepted");
    }
    catch (FaceInputException) { Check(status == HttpStatusCode.BadRequest, "Worker quality error preserved"); }
    catch (FaceUnavailableException) { Check(status == HttpStatusCode.ServiceUnavailable, "Worker outage fails closed"); }
}
Console.WriteLine($"{checks} checks passed");

sealed class FakeEmbeddingHandler(HttpStatusCode status, float[] vector) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        if (request.RequestUri?.Host != "127.0.0.1") throw new Exception("Images must stay on private worker");
        var json = status == HttpStatusCode.OK ? JsonSerializer.Serialize(new { vector }) : JsonSerializer.Serialize(new { error = "Invalid face" });
        return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") });
    }
}
