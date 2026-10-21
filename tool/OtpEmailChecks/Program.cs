using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using WebAPI_TongNhatBaoAn.Services;

foreach (var scenario in new[] { "success", "unauthorized", "quota", "timeout", "network", "missing" })
{
    var handler = new FakeHandler(scenario);
    using var client = new HttpClient(handler);
    var cfg = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
    {
        ["Brevo:ApiKey"] = scenario == "missing" ? null : "test-key",
        ["Email:From"] = "sender@example.com"
    }).Build();
    var sender = new OtpEmailSender(client, cfg, NullLogger<OtpEmailSender>.Instance);
    var failed = false;
    try { await sender.SendAsync("recipient@example.com", "OTP", "123456"); }
    catch (OtpDeliveryException) { failed = true; }
    if (failed != (scenario != "success")) throw new Exception($"Unexpected result: {scenario}");
    if (handler.Calls != (scenario == "missing" ? 0 : 1)) throw new Exception("Unexpected retry/network call");
    Console.WriteLine($"PASS {scenario}");
}

sealed class FakeHandler(string scenario) : HttpMessageHandler
{
    public int Calls { get; private set; }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Calls++;
        if (request.Method != HttpMethod.Post || request.RequestUri?.ToString() != "https://api.brevo.com/v3/smtp/email")
            throw new Exception("Wrong HTTPS endpoint");
        if (request.Headers.GetValues("api-key").Single() != "test-key") throw new Exception("Missing API key");
        using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(cancellationToken));
        if (json.RootElement.GetProperty("to")[0].GetProperty("email").GetString() != "recipient@example.com" ||
            !json.RootElement.GetProperty("textContent").GetString()!.Contains("123456"))
            throw new Exception("Incorrect email payload");
        if (scenario == "timeout") throw new TaskCanceledException();
        if (scenario == "network") throw new HttpRequestException();
        return new HttpResponseMessage(scenario switch
        {
            "unauthorized" => HttpStatusCode.Unauthorized,
            "quota" => HttpStatusCode.TooManyRequests,
            _ => HttpStatusCode.Created
        });
    }
}
