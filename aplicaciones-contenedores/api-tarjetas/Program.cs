using MySqlConnector;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Esta API se conecta a "db_tarjetas", UNA de las 5 bases que viven en la MISMA instancia
// compartida de MariaDB (ver tp-2026/db).
string ConnectionString()
{
    var host = Environment.GetEnvironmentVariable("DB_HOST") ?? "localhost";
    var port = Environment.GetEnvironmentVariable("DB_PORT") ?? "3306";
    var name = Environment.GetEnvironmentVariable("DB_NAME") ?? "db_tarjetas";
    var user = Environment.GetEnvironmentVariable("DB_USER") ?? "appuser";
    var pass = Environment.GetEnvironmentVariable("DB_PASSWORD") ?? "apppass";
    return $"Server={host};Port={port};Database={name};User={user};Password={pass};";
}

app.MapGet("/", () => Results.Ok(new { status = "ok", servicio = "api-tarjetas" }));

// GET /tarjetas -> listar todas
app.MapGet("/tarjetas", async () =>
{
    var tarjetas = new List<Tarjeta>();
    await using var conn = new MySqlConnection(ConnectionString());
    await conn.OpenAsync();
    await using var cmd = new MySqlCommand("SELECT id, alias, titular, tipo, limite FROM tarjetas", conn);
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        tarjetas.Add(LeerTarjeta(reader));
    }
    return Results.Ok(tarjetas);
});

// GET /tarjetas/{id} -> obtener una
app.MapGet("/tarjetas/{id:int}", async (int id) =>
{
    await using var conn = new MySqlConnection(ConnectionString());
    await conn.OpenAsync();
    await using var cmd = new MySqlCommand("SELECT id, alias, titular, tipo, limite FROM tarjetas WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("@id", id);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (await reader.ReadAsync())
    {
        return Results.Ok(LeerTarjeta(reader));
    }
    return Results.NotFound(new { error = "Tarjeta no encontrada" });
});

// POST /tarjetas -> crear (alta)
app.MapPost("/tarjetas", async (Tarjeta nueva) =>
{
    await using var conn = new MySqlConnection(ConnectionString());
    await conn.OpenAsync();
    await using var cmd = new MySqlCommand(
        "INSERT INTO tarjetas (alias, titular, tipo, limite) VALUES (@alias, @titular, @tipo, @limite); SELECT LAST_INSERT_ID();",
        conn);
    cmd.Parameters.AddWithValue("@alias", nueva.Alias);
    cmd.Parameters.AddWithValue("@titular", nueva.Titular);
    cmd.Parameters.AddWithValue("@tipo", nueva.Tipo);
    cmd.Parameters.AddWithValue("@limite", nueva.Limite);
    var id = Convert.ToInt32(await cmd.ExecuteScalarAsync());
    nueva.Id = id;
    return Results.Created($"/tarjetas/{id}", nueva);
});

// PUT /tarjetas/{id} -> modificar
app.MapPut("/tarjetas/{id:int}", async (int id, Tarjeta cambios) =>
{
    await using var conn = new MySqlConnection(ConnectionString());
    await conn.OpenAsync();
    await using var cmd = new MySqlCommand(
        "UPDATE tarjetas SET alias=@alias, titular=@titular, tipo=@tipo, limite=@limite WHERE id=@id",
        conn);
    cmd.Parameters.AddWithValue("@alias", cambios.Alias);
    cmd.Parameters.AddWithValue("@titular", cambios.Titular);
    cmd.Parameters.AddWithValue("@tipo", cambios.Tipo);
    cmd.Parameters.AddWithValue("@limite", cambios.Limite);
    cmd.Parameters.AddWithValue("@id", id);
    var filas = await cmd.ExecuteNonQueryAsync();
    if (filas == 0) return Results.NotFound(new { error = "Tarjeta no encontrada" });
    cambios.Id = id;
    return Results.Ok(cambios);
});

// DELETE /tarjetas/{id} -> baja
app.MapDelete("/tarjetas/{id:int}", async (int id) =>
{
    await using var conn = new MySqlConnection(ConnectionString());
    await conn.OpenAsync();
    await using var cmd = new MySqlCommand("DELETE FROM tarjetas WHERE id=@id", conn);
    cmd.Parameters.AddWithValue("@id", id);
    var filas = await cmd.ExecuteNonQueryAsync();
    return filas == 0 ? Results.NotFound(new { error = "Tarjeta no encontrada" }) : Results.NoContent();
});

var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
app.Run($"http://0.0.0.0:{port}");

static Tarjeta LeerTarjeta(MySqlDataReader reader) => new()
{
    Id = reader.GetInt32(reader.GetOrdinal("id")),
    Alias = reader.GetString(reader.GetOrdinal("alias")),
    Titular = reader.GetString(reader.GetOrdinal("titular")),
    Tipo = reader.GetString(reader.GetOrdinal("tipo")),
    Limite = reader.GetDecimal(reader.GetOrdinal("limite")),
};

class Tarjeta
{
    public int Id { get; set; }
    public string Alias { get; set; } = "";
    public string Titular { get; set; } = "";
    public string Tipo { get; set; } = "";
    public decimal Limite { get; set; }
}
