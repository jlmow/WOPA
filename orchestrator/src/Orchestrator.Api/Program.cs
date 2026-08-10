using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Config;
using Orchestrator.Api.Data;
using Orchestrator.Api.Modulos;
using Orchestrator.Api.OrdensSeparacao;
using Orchestrator.Api.Picking;
using Orchestrator.Api.Zonas;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// A base de dados é criada por database/schema.sql (não por migrations —
// este DbContext é "database first" por desenho, ver Data/WopaDbContext.cs).
// A connection string real fica em appsettings.{Environment}.json ou na
// variável de ambiente ConnectionStrings__Wopa — nunca aqui no código.
builder.Services.AddDbContext<WopaDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("Wopa")));

// PoC: os frontends (pda, controller) correm em dev servers separados (Vite).
// Em produção, orchestrator e frontends ficam atrás do mesmo IIS/domínio
// e este CORS deixa de ser necessário.
const string DevClientsPolicy = "DevClients";
builder.Services.AddCors(options =>
{
    options.AddPolicy(DevClientsPolicy, policy =>
        policy.WithOrigins(
                  "http://localhost:5173", "http://127.0.0.1:5173", // pda
                  "http://localhost:5174", "http://127.0.0.1:5174") // controller
              .AllowAnyHeader()
              .AllowAnyMethod());
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors(DevClientsPolicy);

// ADR-009: pedido leve para os clientes (sobretudo o pda) verificarem se o
// servidor está mesmo alcançável, não só se há rede.
app.MapGet("/health", () => Results.Ok(new { status = "ok" })).WithTags("Health");

app.MapPickingEndpoints();
app.MapZonaEndpoints();
app.MapModuloEndpoints();
app.MapRegrasMissaoEndpoints();
app.MapOrdensSeparacaoEndpoints();

app.Run();
