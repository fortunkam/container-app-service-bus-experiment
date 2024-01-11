using Dapr.Client;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Running!");

app.MapPost("/incoming", async(Input input) => {

    using var client = new DaprClientBuilder().Build();

    await client.InvokeBindingAsync("outgoing", "create", new Output
    {
        message = input.message,
        isValid = true
    });
});

app.Run();
