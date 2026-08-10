using System.Text.Json.Serialization;
using Orchestrator.Api.Modulos;
using Orchestrator.Api.Picking;
using Orchestrator.Api.Zonas;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddSingleton<PickingStore>();

// PoC: o frontend pda corre num dev server separado (Vite).
// Em produção, orchestrator e frontend ficam atrás do mesmo IIS/domínio
// e este CORS deixa de ser necessário.
const string PdaClientPolicy = "PdaClient";
builder.Services.AddCors(options =>
{
    options.AddPolicy(PdaClientPolicy, policy =>
        policy.WithOrigins("http://localhost:5173", "http://127.0.0.1:5173")
              .AllowAnyHeader()
              .AllowAnyMethod());
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors(PdaClientPolicy);

app.MapPickingEndpoints();
app.MapZonaEndpoints();
app.MapModuloEndpoints();

app.Run();
