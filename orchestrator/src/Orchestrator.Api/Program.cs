using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Artigos;
using Orchestrator.Api.Config;
using Orchestrator.Api.Data;
using Orchestrator.Api.Missoes;
using Orchestrator.Api.Modulos;
using Orchestrator.Api.OrdensPreparacao;
using Orchestrator.Api.Picking;
using Orchestrator.Api.Plataformas;
using Orchestrator.Api.Tipificacao;
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

// Anexo A do documento de requisitos v0.4: cubicagem/tipificação —
// stateless por cima do DbContext, por isso pode ser scoped como ele.
builder.Services.AddScoped<CubicagemService>();

// As origens de CORS vêm da configuração (Cors:AllowedOrigins), com os dev
// servers do Vite como omissão — em produção, install-wopa.ps1 escreve
// appsettings.Production.json com os URLs reais do pda/controller no IIS.
// Se ficarem atrás do mesmo domínio/IIS que o orchestrator, o CORS deixa de
// ser necessário, mas continua inofensivo tê-lo configurado.
const string ClientsPolicy = "Clients";
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
    ?? ["http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:5174", "http://127.0.0.1:5174"];
builder.Services.AddCors(options =>
{
    options.AddPolicy(ClientsPolicy, policy =>
        policy.WithOrigins(allowedOrigins)
              .AllowAnyHeader()
              .AllowAnyMethod());
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors(ClientsPolicy);

// ADR-009: pedido leve para os clientes (sobretudo o pda) verificarem se o
// servidor está mesmo alcançável, não só se há rede.
app.MapGet("/health", () => Results.Ok(new { status = "ok" })).WithTags("Health");

app.MapPickingEndpoints();
app.MapZonaEndpoints();
app.MapModuloEndpoints();
app.MapRegrasMissaoEndpoints();
app.MapArtigosEndpoints();
app.MapOrdensPreparacaoEndpoints();
app.MapPlataformasEndpoints();
app.MapMissoesEndpoints();

app.Run();
